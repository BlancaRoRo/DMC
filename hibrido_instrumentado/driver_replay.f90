! driver_replay.f90
!
! Prueba forense final (ver comparacion-final.md, "prueba de recalculo
! en CPU pura"): lee snapshot_colapso.dat, el volcado que
! pasodmc_gpu_pipeline (msteps.f90, opcion=7) escribe justo antes de
! lanzar el grafo de GPU para el paso que acaba en colapso (nwfin=0) --
! contiene el estado EXACTO (posiciones, funcion de onda, energias,
! semilla irn de cada walker, y ncmtras/dtau/etrial) que la GPU usa de
! entrada a ese paso.
!
! Este programa NO relanza la simulacion ni el grafo -- hace la misma
! inicializacion de siempre (leer in.mcv/conf, igual que qmccluster)
! para tener natom/ncmtras/dtau/rotamol/etc. disponibles, y luego, para
! cada walker del volcado, llama a dmc2_hd -- la MISMA subrutina
! attributes(host,device) de dmc2.cuf que ejecuta cada hilo del kernel
! k_dmc2, pero invocada aqui directamente en el host, un walker detras
! de otro, sin ningun kernel ni paralelismo de por medio. Si con los
! mismos datos exactos tambien sale nsons=0 para todos los walkers,
! queda demostrado que el colapso no depende de que el calculo se haga
! en la GPU -- ocurre igual en CPU pura, con los mismos numeros.
program driver_replay

 use mentradatos
 use mmontecarlo
 use mminimiza
 use mparametros
 use mparalelo
 use msync_gpu, only: sincroniza_globales_gpu
 use mdmc2, only: dmc2_hd => dmc2, ncmtras_gpu => ncmtras, &
                   dtau_gpu => dtau, etrial_gpu => etrial
 use mtipos, only: vec3
 implicit none
 integer, parameter :: r8 = selected_real_kind(15,9)
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: i8 = selected_int_kind(15)

 logical :: soydire
 integer(kind=i4) :: nwpaso_dump, natom_dump, ncmtras_dump
 real(kind=r8) :: dtau_dump, etrial_dump

 type(vec3), allocatable :: atomw(:,:), spropw(:,:), dwfw(:,:)
 real(kind=r8), allocatable :: hb2mw(:,:), bw(:), dphiw(:,:)
 real(kind=r8), allocatable :: wfw(:), wfhe4w(:), wfhe3w(:), wfmw(:), wfxw(:)
 real(kind=r8), allocatable :: kinw(:), eimpw(:), erotw(:), potw(:), enew(:)
 integer(kind=i8), allocatable :: irnw(:)
 integer(kind=i4), allocatable :: nsonsw(:)

 type(vec3) :: atom_l(200), dwf_l(200), sprop_l(3)
 real(kind=r8) :: hb2m_l(200), dphi_l(2)
 integer(kind=i4) :: iwalker, nwfin, u

  ! ---- misma inicializacion que qmccluster.f90, hasta iniwalkers:
  ! necesaria para tener natom/ncmtras/dtau/rotamol/hb2m/etc. fijados
  ! desde el mismo in.mcv/conf que la corrida que genero el volcado ----
  call iniciaparalelo
  call quiensoy(soydire)
  if (soydire) then
    call leedatos
    call escribedatos
  endif
  call iniprocesos
  call reparteentrada
  call repartepotencial
  call inimontecarlo
  call compruebatodos
  call iniwalkers
  call sincroniza_globales_gpu

  ! ---- leer el volcado forense ----
  open(newunit=u, file='snapshot_colapso.dat', form='unformatted', &
       access='sequential', status='old', action='read')
  read(u) nwpaso_dump, natom_dump, ncmtras_dump, dtau_dump, etrial_dump

  if (natom_dump .ne. natom) then
    write(*,*) 'ERROR: natom del volcado (', natom_dump, ') no coincide con natom actual (', natom, ')'
    write(*,*) 'Revisa que el in.mcv/conf usado aqui es el mismo que genero snapshot_colapso.dat.'
    stop 1
  endif

  allocate(atomw(nwpaso_dump,natom_dump), spropw(nwpaso_dump,3), &
           hb2mw(nwpaso_dump,natom_dump), bw(nwpaso_dump))
  allocate(wfw(nwpaso_dump), wfhe4w(nwpaso_dump), wfhe3w(nwpaso_dump), &
           wfmw(nwpaso_dump), wfxw(nwpaso_dump))
  allocate(kinw(nwpaso_dump), eimpw(nwpaso_dump), erotw(nwpaso_dump), &
           potw(nwpaso_dump), enew(nwpaso_dump))
  allocate(dwfw(nwpaso_dump,natom_dump), dphiw(nwpaso_dump,2), &
           irnw(nwpaso_dump), nsonsw(nwpaso_dump))

  read(u) atomw, spropw, hb2mw, bw
  read(u) wfw, wfhe4w, wfhe3w, wfmw, wfxw
  read(u) kinw, eimpw, erotw, potw, enew
  read(u) dwfw, dphiw, irnw
  close(u)

  write(*,*) '=== driver_replay: snapshot leido ==='
  write(*,*) 'nwpaso  =', nwpaso_dump
  write(*,*) 'natom   =', natom_dump
  write(*,*) 'ncmtras (dump) =', ncmtras_dump, '  (actual) =', ncmtras
  write(*,*) 'dtau    (dump) =', dtau_dump,    '  (actual) =', dtau
  write(*,*) 'etrial  (dump) =', etrial_dump,  '  (inicial actual) =', etrial

  ! ---- forzar en dmc2.cuf las MISMAS constantes que tenia la GPU en
  ! el instante exacto del colapso (etrial evoluciona paso a paso, asi
  ! que su valor inicial de esta corrida NO sirve -- ncmtras/dtau no
  ! deberian haber cambiado, pero se fijan igual por rigor) ----
  ncmtras_gpu = ncmtras_dump
  dtau_gpu    = dtau_dump
  etrial_gpu  = etrial_dump

  ! ---- recalculo en CPU pura, walker a walker, llamando a la MISMA
  ! dmc2_hd que usa k_dmc2 en el device -- aqui sin kernel, sin GPU ----
  nwfin = 0
  do iwalker = 1, nwpaso_dump
    atom_l(1:natom_dump) = atomw(iwalker,:)
    dwf_l(1:natom_dump)  = dwfw(iwalker,:)
    hb2m_l(1:natom_dump) = hb2mw(iwalker,:)
    sprop_l = spropw(iwalker,:)
    dphi_l  = dphiw(iwalker,:)

    call dmc2_hd(atom_l(1:natom_dump), sprop_l, hb2m_l(1:natom_dump), bw(iwalker), &
                 wfw(iwalker), wfhe4w(iwalker), wfhe3w(iwalker), wfmw(iwalker), wfxw(iwalker), &
                 kinw(iwalker), eimpw(iwalker), erotw(iwalker), potw(iwalker), enew(iwalker), &
                 dwf_l(1:natom_dump), dphi_l, irnw(iwalker), nsonsw(iwalker))

    if (nsonsw(iwalker) .gt. 0) nwfin = nwfin + 1
  enddo

  write(*,*) '=== driver_replay: resultado ==='
  write(*,*) 'walkers de entrada           =', nwpaso_dump
  write(*,*) 'walkers vivos (CPU pura)     =', nwfin
  if (nwfin .eq. 0) then
    write(*,*) 'CONFIRMADO: con los mismos datos exactos, la CPU pura (sin GPU, sin kernel,'
    write(*,*) 'un walker detras de otro) tambien da nwfin=0 -- el mismo colapso.'
  else
    write(*,*) 'DIVERGENCIA: en CPU pura NO colapsa (nwfin>0) -- revisar, esto contradiria'
    write(*,*) 'todas las pruebas anteriores (op5/op6/op7/op8).'
  endif

end program driver_replay
