! driver_diagnostico.f90
!
! Continuacion de la prueba forense (driver_replay.f90): ya sabemos que
! los 1936 walkers dan nsons=0 tanto en GPU como en CPU pura. Aqui se
! busca POR QUE -- dmc2 (dmc2.cuf) tiene tres caminos distintos que
! acaban en nsons=0:
!   (1) wftest=(wf/wfold)**2 < ratio (1e-7) tras el PRIMER hpsi -> return
!       inmediato, la mitad del paso ni se completa (config. descartada)
!   (2) idem tras el SEGUNDO hpsi
!   (3) se llega al final, se calcula gb=exp(-(0.5*(eold+ene)-etrial)*dtau)
!       y se sortea nsons=int(gb+rn); si nsons>10 se pone a 0 (un walker
!       "demasiado bueno" se mata en vez de capar su reproduccion)
!   (4) se llega al final y nsons=int(gb+rn) da 0 "de forma normal"
!       (gb+rn<1, la muerte esperable de un walker de peor energia)
!
! dmc2_hd (la subrutina real, dmc2.cuf) no expone por cual de estos
! caminos murio cada walker -- por eso aqui se REPLICA su misma logica
! linea a linea (reutilizando hpsi/rota/gauss3_gpu/rand1_gpu, ya
! validados, sin tocar dmc2.cuf ni la fisica real) con una variable de
! diagnostico extra que si lo cuenta.
program driver_diagnostico

 use mentradatos
 use mmontecarlo
 use mminimiza
 use mparametros
 use mparalelo
 use msync_gpu, only: sincroniza_globales_gpu
 use mtipos, only: vec3
 use mhpsi, only: hpsi
 use mrota, only: rota
 use mrandgpu, only: gauss3_gpu, rand1_gpu
 use mderananum, only: rotamol
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

 type(vec3) :: atom_l(200), dwf_l(200), sprop_l(3)
 real(kind=r8) :: hb2m_l(200), dphi_l(2)
 integer(kind=i4) :: iwalker, u

 ! ---- resultado del recalculo instrumentado, por walker ----
 integer(kind=i4) :: motivo, nsons_l
 real(kind=r8) :: gb_l, eold_l, wfold_l

 ! ---- estadisticas ----
 integer(kind=i4) :: n_ret1, n_ret2, n_capado, n_normal0, n_vivos
 real(kind=r8) :: eold_min, eold_max, eold_sum
 real(kind=r8) :: ene_min, ene_max, ene_sum
 real(kind=r8) :: gb_min, gb_max, gb_sum
 real(kind=r8) :: wftest1_min, wftest1_max
 integer(kind=i4) :: n_gb

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

  open(newunit=u, file='snapshot_colapso.dat', form='unformatted', &
       access='sequential', status='old', action='read')
  read(u) nwpaso_dump, natom_dump, ncmtras_dump, dtau_dump, etrial_dump

  allocate(atomw(nwpaso_dump,natom_dump), spropw(nwpaso_dump,3), &
           hb2mw(nwpaso_dump,natom_dump), bw(nwpaso_dump))
  allocate(wfw(nwpaso_dump), wfhe4w(nwpaso_dump), wfhe3w(nwpaso_dump), &
           wfmw(nwpaso_dump), wfxw(nwpaso_dump))
  allocate(kinw(nwpaso_dump), eimpw(nwpaso_dump), erotw(nwpaso_dump), &
           potw(nwpaso_dump), enew(nwpaso_dump))
  allocate(dwfw(nwpaso_dump,natom_dump), dphiw(nwpaso_dump,2), irnw(nwpaso_dump))

  read(u) atomw, spropw, hb2mw, bw
  read(u) wfw, wfhe4w, wfhe3w, wfmw, wfxw
  read(u) kinw, eimpw, erotw, potw, enew
  read(u) dwfw, dphiw, irnw
  close(u)

  write(*,*) '=== driver_diagnostico: snapshot leido, nwpaso=', nwpaso_dump, ' ==='
  write(*,*) 'etrial usado =', etrial_dump, '  dtau usado =', dtau_dump

  write(*,*) '--- comprobacion de diversidad: semillas (irn) y posicion x del atomo 1, primeros walkers ---'
  do iwalker = 1, min(10, nwpaso_dump)
    write(*,'(a,i5,a,i0,a,f20.10,a,f20.10)') ' walker=', iwalker, '  irn=', irnw(iwalker), &
      '  atom1_x=', atomw(iwalker,1)%comp(1), '  ene=', enew(iwalker)
  enddo
  write(*,*) '--- cuantos irn DISTINTOS hay en total (de 1936) ---'
  block
    integer(kind=i8), allocatable :: irn_sorted(:)
    integer(kind=i4) :: n_distintos, k
    allocate(irn_sorted(nwpaso_dump))
    irn_sorted = irnw
    call sort_i8(irn_sorted, nwpaso_dump)
    n_distintos = 1
    do k = 2, nwpaso_dump
      if (irn_sorted(k) .ne. irn_sorted(k-1)) n_distintos = n_distintos + 1
    enddo
    write(*,*) 'irn distintos =', n_distintos, ' de ', nwpaso_dump
    deallocate(irn_sorted)
  end block

  n_ret1 = 0; n_ret2 = 0; n_capado = 0; n_normal0 = 0; n_vivos = 0
  eold_min =  1.0e300_r8; eold_max = -1.0e300_r8; eold_sum = 0.0_r8
  ene_min  =  1.0e300_r8; ene_max  = -1.0e300_r8; ene_sum  = 0.0_r8
  gb_min   =  1.0e300_r8; gb_max   = -1.0e300_r8; gb_sum   = 0.0_r8
  wftest1_min = 1.0e300_r8; wftest1_max = -1.0e300_r8
  n_gb = 0

  do iwalker = 1, nwpaso_dump
    atom_l(1:natom_dump) = atomw(iwalker,:)
    dwf_l(1:natom_dump)  = dwfw(iwalker,:)
    hb2m_l(1:natom_dump) = hb2mw(iwalker,:)
    sprop_l = spropw(iwalker,:)
    dphi_l  = dphiw(iwalker,:)

    call dmc2_diag(atom_l(1:natom_dump), sprop_l, hb2m_l(1:natom_dump), bw(iwalker), &
                    wfw(iwalker), wfhe4w(iwalker), wfhe3w(iwalker), wfmw(iwalker), wfxw(iwalker), &
                    kinw(iwalker), eimpw(iwalker), erotw(iwalker), potw(iwalker), enew(iwalker), &
                    dwf_l(1:natom_dump), dphi_l, irnw(iwalker), natom_dump, ncmtras_dump, &
                    dtau_dump, etrial_dump, nsons_l, motivo, gb_l, eold_l, wfold_l)

    eold_min = min(eold_min, eold_l); eold_max = max(eold_max, eold_l); eold_sum = eold_sum + eold_l
    ene_min  = min(ene_min, enew(iwalker)); ene_max = max(ene_max, enew(iwalker)); ene_sum = ene_sum + enew(iwalker)

    select case (motivo)
    case (1)
      n_ret1 = n_ret1 + 1
    case (2)
      n_ret2 = n_ret2 + 1
    case (3)
      n_capado = n_capado + 1
      gb_min = min(gb_min, gb_l); gb_max = max(gb_max, gb_l); gb_sum = gb_sum + gb_l; n_gb = n_gb + 1
    case (4)
      n_normal0 = n_normal0 + 1
      gb_min = min(gb_min, gb_l); gb_max = max(gb_max, gb_l); gb_sum = gb_sum + gb_l; n_gb = n_gb + 1
    end select
    if (nsons_l .gt. 0) n_vivos = n_vivos + 1
  enddo

  write(*,*) '=== driver_diagnostico: resultado ==='
  write(*,*) 'walkers de entrada                         =', nwpaso_dump
  write(*,*) 'walkers vivos (nsons>0)                     =', n_vivos
  write(*,*) '--- desglose de POR QUE murieron los demas ---'
  write(*,*) 'return tras 1er wftest<ratio (config. mala) =', n_ret1
  write(*,*) 'return tras 2o  wftest<ratio (config. mala) =', n_ret2
  write(*,*) 'llegaron a gb, nsons>10 -> capado a 0        =', n_capado
  write(*,*) 'llegaron a gb, nsons=0 "normal" (gb+rn<1)    =', n_normal0
  write(*,*)
  write(*,*) '--- rango de energias (eold, antes del paso) ---'
  write(*,*) 'eold min =', eold_min, '  max =', eold_max, '  media =', eold_sum/nwpaso_dump
  write(*,*) '--- rango de energias (ene, despues del paso) ---'
  write(*,*) 'ene  min =', ene_min,  '  max =', ene_max,  '  media =', ene_sum/nwpaso_dump
  if (n_gb .gt. 0) then
    write(*,*) '--- rango de gb (solo walkers que llegaron a calcularlo) ---'
    write(*,*) 'gb   min =', gb_min, '  max =', gb_max, '  media =', gb_sum/n_gb, '  n=', n_gb
  else
    write(*,*) 'NINGUN walker llego a calcular gb -- todos murieron por wftest<ratio.'
  endif

contains

 subroutine sort_i8(a, n)
  integer(kind=i4), intent(in) :: n
  integer(kind=i8), intent(inout) :: a(n)
  integer(kind=i4) :: ii, jj
  integer(kind=i8) :: key
   do ii = 2, n
     key = a(ii)
     jj = ii - 1
     do while (jj .ge. 1)
       if (a(jj) .le. key) exit
       a(jj+1) = a(jj)
       jj = jj - 1
     enddo
     a(jj+1) = key
   enddo
 end subroutine sort_i8

 ! ---- copia diagnostica de dmc2 (dmc2.cuf), SIN tocar el original --
 ! misma fisica exacta (hpsi/rota/gauss3_gpu/rand1_gpu ya validados),
 ! con una salida extra "motivo" que dice por donde murio el walker.
 subroutine dmc2_diag(atom, sprop, hb2m, b, &
                       wf, wfhe4, wfhe3, wfm, wfx, &
                       kin, eimp, erot, pot, ene, &
                       dwf, dphi, irn, natomv, ncmtrasv, dtauv, etrialv, &
                       nsons, motivo, gb_out, eold_out, wfold_out)
  integer(kind=i4), intent(in) :: natomv, ncmtrasv
  real(kind=r8), intent(in) :: dtauv, etrialv
  type(vec3), intent (inout) :: atom(natomv)
  type(vec3), intent (inout) :: sprop(3)
  real(kind=r8), intent (in) :: hb2m(natomv)
  real(kind=r8), intent (in) :: b
  real(kind=r8), intent (inout) :: wf, wfhe4, wfhe3, wfm, wfx
  real(kind=r8), intent (inout) :: kin, eimp, erot, pot, ene
  type(vec3), intent (inout) :: dwf(natomv)
  real(kind=r8), intent (inout) :: dphi(2)
  integer(kind=i8), intent (inout) :: irn
  integer(kind=i4), intent (out) :: nsons, motivo
  real(kind=r8), intent (out) :: gb_out, eold_out, wfold_out

  type(vec3) :: rtemp
  real(kind=r8) :: phix1, phiy, phix2
  real(kind=r8) :: gvar3(3)
  real(kind=r8) :: eold, wfold
  real(kind=r8) :: wftest
  real(kind=r8) :: gb, rn
  real(kind=r8) :: sigma1_l, sigma2_l, sig1rot_l, sig2rot_l, sig1hrot_l, sig2hrot_l
  integer(kind=i4) :: iatom
  real(kind=r8), parameter :: ratiov = 1.0d-7

    nsons = 0
    motivo = 0
    gb_out = -1.0_r8

    eold = ene
    wfold = wf
    eold_out = eold
    wfold_out = wfold

    do iatom = 1, ncmtrasv
      call gauss3_gpu(irn, gvar3)
      sigma1_l = sqrt(2.0_r8*hb2m(iatom)*dtauv)
      sigma2_l = 2.0_r8*hb2m(iatom)*dtauv
      rtemp%comp(:) = sigma1_l*gvar3(:)
      rtemp%comp(:) = rtemp%comp(:) + 0.50_r8*sigma2_l*dwf(iatom)%comp(:)
      atom(iatom)%comp(:) = atom(iatom)%comp(:) + rtemp%comp(:)
    enddo
    if (rotamol) then
      call gauss3_gpu(irn, gvar3)
      sig1rot_l  = sqrt(2.0_r8*b*dtauv)
      sig2rot_l  = 2.0_r8*b*dtauv
      sig1hrot_l = sqrt(b*dtauv)
      sig2hrot_l = b*dtauv
      phix1 = sig1hrot_l*gvar3(1) + 0.50_r8*sig2hrot_l*dphi(1)
      phiy  = sig1rot_l *gvar3(2) + 0.50_r8*sig2rot_l *dphi(2)
      phix2 = sig1hrot_l*gvar3(3) + 0.50_r8*sig2hrot_l*dphi(1)
      call rota(1, phix1, sprop)
      call rota(2, phiy,  sprop)
      call rota(1, phix2, sprop)
    endif

    call hpsi(atom, sprop, hb2m, b, wf, wfhe4, wfhe3, wfm, wfx, &
              kin, eimp, erot, pot, ene, dwf, dphi)

    wftest = (wf/wfold)**2
    if (wftest .lt. ratiov) then
      motivo = 1
      return
    endif

    do iatom = 1, ncmtrasv
      sigma2_l = 2.0_r8*hb2m(iatom)*dtauv
      atom(iatom)%comp(:) = atom(iatom)%comp(:) + 0.50_r8*sigma2_l*dwf(iatom)%comp(:)
    enddo
    if (rotamol) then
      sig2rot_l  = 2.0_r8*b*dtauv
      sig2hrot_l = b*dtauv
      phix1 = 0.50_r8*sig2hrot_l*dphi(1)
      phiy  = 0.50_r8*sig2rot_l *dphi(2)
      phix2 = 0.50_r8*sig2hrot_l*dphi(1)
      call rota(1, phix1, sprop)
      call rota(2, phiy,  sprop)
      call rota(1, phix2, sprop)
    endif

    call hpsi(atom, sprop, hb2m, b, wf, wfhe4, wfhe3, wfm, wfx, &
              kin, eimp, erot, pot, ene, dwf, dphi)

    wftest = (wf/wfold)**2
    if (wftest .lt. ratiov) then
      motivo = 2
      return
    endif

    gb = exp(-(0.50_r8*(eold+ene)-etrialv)*dtauv)
    gb_out = gb
    call rand1_gpu(rn, irn)
    nsons = int(gb+rn)

    if (nsons .gt. 10) then
      nsons = 0
      motivo = 3
    else if (nsons .eq. 0) then
      motivo = 4
    endif

 end subroutine dmc2_diag

end program driver_diagnostico
