module msteps

 use mparametros
 use mtipos
 use mrandom
 use mwavef
 use mrotaciones
 use mmcvpromedia
 ! pasodmc_gpu (opcion=5, ver docs-kernels/hibrido.md Paso 5): usa el
 ! kernel k_dmc2 ya portado y validado, y k_split_seeds para repartir
 ! una semilla por walker (mismo mecanismo que mrandom.md) -- pasodmc
 ! original (arriba) no se toca.
 use mdmc2, only: k_dmc2, dmc2_hd => dmc2
 use mrandgpu, only: k_split_seeds, rand1p_gpu
 use msync_gpu, only: sincroniza_globales_gpu, sincroniza_constantes_gpu, sincroniza_etrial_gpu
 use cudafor
 ! pasodmc_gpu_pipeline (opcion=7, Opcion 1 de
 ! arquitectura-streams-kin-pot.md Parte 12-13): reparto de dmc2 en 7
 ! fases + CUDA Graph en horquilla para derananum/vpot -- NO toca
 ! pasodmc_gpu/k_dmc2, viven aparte como referencia de correccion.
 use mdmc2_pipeline, only: inicializa_pipeline, lanza_pipeline,       &
&                           atom_p, sprop_p, hb2m_p, b_p,             &
&                           wf_p, wfhe4_p, wfhe3_p, wfm_p, wfx_p,     &
&                           kin_p, eimp_p, erot_p, pot_p, ene_p,      &
&                           dwf_p, dphi_p, irn_p, nsons_p
 ! instrumentacion de tiempos, solo en test-tiempos/ (ver mtiempos.f90)
 use mtiempos, only: i8t, tiempos_tic, tiempos_toc, tiempos_reset,          &
&                     tiempos_escribe4, tiempos_escribe5,                   &
&                     t_hpsi, t_rota, t_random, t_dmc2call, t_pasodmc_body, &
&                     t_total4,                                            &
&                     t_sync, t_seeds, t_pack, t_h2d, t_kernel, t_d2h,      &
&                     t_unpack, t_repart, t_pasodmc_gpu_body, t_total5,     &
&                     t_sync7, t_pack7, t_h2d7, t_kernel7, t_d2h7,          &
&                     t_unpack7, t_repart7, t_pasodmc_gpu_pipeline_body

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: i8=selected_int_kind(15)
 integer, private, parameter :: r8=selected_real_kind(15,9)

contains

 subroutine pasodmc(nwpaso,egrow,wsim)
  integer(kind=i4), intent (inout) :: nwpaso
  real(kind=r8), intent (out) :: egrow
  type(walker), intent (inout) :: wsim(2*nwalkers)
  real(kind=r8) :: nwnew,nwold
  integer(kind=i4) :: nwfin,nwrep
  integer(kind=i4) :: nsons
  integer(kind=i4) :: iwalker,isons
  integer(kind=i4), save :: ivez=0
  real(kind=r8), save :: segrow=0.0_r8
  integer(kind=i8t) :: tt0body

   call tiempos_tic(tt0body)

   nwfin=0
   nwrep=0
   do iwalker=1,nwpaso
     block
       integer(kind=i8t) :: tt0
       call tiempos_tic(tt0)
       call dmc2(wsim(iwalker),nsons)
       t_dmc2call=t_dmc2call+tiempos_toc(tt0)
     end block
     if(nsons.gt.0) then
       nwfin=nwfin+1
       wsim(nwfin)=wsim(iwalker)
       do isons=2,nsons
         nwrep=nwrep+1
         if(nwpaso+nwrep.le.2*nwalkers) then
           wsim(nwpaso+nwrep)=wsim(iwalker)
         endif
       enddo
     endif
   enddo

   do iwalker=1,nwrep
     if(nwfin+1.gt.2*nwalkers) exit
     if(nwpaso+iwalker.gt.2*nwalkers) exit
     nwfin=nwfin+1
     wsim(nwfin)=wsim(nwpaso+iwalker)
   enddo


   nwnew=nwfin
   nwold=nwpaso
   egrow=etrial-log(nwnew/nwold)/dtau
   ivez=ivez+1
   segrow=segrow+egrow
   if(ivez.eq.ncetrial) then
     etrial=0.50_r8*(etrial+segrow/ncetrial)
     ivez=0
     segrow=0.0_r8
   endif

   nwpaso=nwfin

   t_pasodmc_body=t_pasodmc_body+tiempos_toc(tt0body)

 end subroutine pasodmc

! ---- pasodmc_gpu: mismo algoritmo exacto que pasodmc, pero el bucle
! secuencial "do iwalker=1,nwpaso; call dmc2(wsim(iwalker),nsons)"
! se sustituye por un unico lanzamiento de k_dmc2 para todos los
! walkers a la vez. La reparticion/compactacion de la poblacion segun
! nsons es la MISMA logica que pasodmc, repetida aqui porque ahora
! nsons es un array precalculado (uno por walker) en vez de un
! escalar que se calcula walker a walker dentro del bucle.
!
! irn_walkers: cada walker necesita su propio estado de aleatoriedad
! persistente entre pasos (ver mrandom.md Parte 1) -- se guarda aqui,
! local a esta subrutina con "save" (mismo patron que ivez/segrow de
! pasodmc), en vez de anadir un campo nuevo a type(walker) en
! mtipos.f90 (que usa TODO el codigo original, no solo esta via). Al
! reordenarse/replicarse wsim(:) segun nsons, irn_walkers(:) se mueve
! exactamente igual, en el mismo bucle.
 subroutine pasodmc_gpu(nwpaso,egrow,wsim)
  integer(kind=i4), intent (inout) :: nwpaso
  real(kind=r8), intent (out) :: egrow
  type(walker), intent (inout) :: wsim(2*nwalkers)
  real(kind=r8) :: nwnew,nwold
  integer(kind=i4) :: nwfin,nwrep
  integer(kind=i4) :: iwalker,isons,iatom
  integer(kind=i4), save :: ivez=0
  real(kind=r8), save :: segrow=0.0_r8
  integer(kind=i8), save, allocatable :: irn_walkers(:)
  logical, save :: iniciado=.false.
  integer(kind=i8) :: irnmaster
  integer(kind=i4) :: threads, blocks
  integer(kind=i8t) :: tt0, tt0body
  integer :: istat_sync

  ! ---- SoA host, dimensionadas a nwpaso (varia paso a paso, siempre
  ! <=2*nwalkers). Walker (nwpaso) como dimension RAPIDA/contigua --
  ! ver tiempo-ncu-resultado.md Parte 3 -- para que el paquetado y la
  ! copia H2D/D2H sean coalescidos entre walkers consecutivos. ----
  type(vec3) :: atom_h(nwpaso,natom), sprop_h(nwpaso,3)
  real(kind=r8) :: hb2m_h(nwpaso,natom), b_h(nwpaso)
  real(kind=r8) :: wf_h(nwpaso), wfhe4_h(nwpaso), wfhe3_h(nwpaso), wfm_h(nwpaso), wfx_h(nwpaso)
  real(kind=r8) :: kin_h(nwpaso), eimp_h(nwpaso), erot_h(nwpaso), pot_h(nwpaso), ene_h(nwpaso)
  type(vec3) :: dwf_h(nwpaso,natom)
  real(kind=r8) :: dphi_h(nwpaso,2)
  integer(kind=i4) :: nsons(nwpaso)

  ! ---- SoA device ----
  type(vec3), device :: atom_d(nwpaso,natom), sprop_d(nwpaso,3)
  real(kind=r8), device :: hb2m_d(nwpaso,natom), b_d(nwpaso)
  real(kind=r8), device :: wf_d(nwpaso), wfhe4_d(nwpaso), wfhe3_d(nwpaso), wfm_d(nwpaso), wfx_d(nwpaso)
  real(kind=r8), device :: kin_d(nwpaso), eimp_d(nwpaso), erot_d(nwpaso), pot_d(nwpaso), ene_d(nwpaso)
  type(vec3), device :: dwf_d(nwpaso,natom)
  real(kind=r8), device :: dphi_d(nwpaso,2)
  integer(kind=i8), device :: irn_d(nwpaso)
  integer(kind=i4), device :: nsons_d(nwpaso)

   call tiempos_tic(tt0body)

   ! ---- sincronizar variables device con los valores reales (ver
   ! msync_gpu.cuf) -- todos los pasos, no solo el primero, porque
   ! etrial cambia durante la simulacion ----
   call tiempos_tic(tt0)
   call sincroniza_globales_gpu
   t_sync=t_sync+tiempos_toc(tt0)

   ! ---- reparto de semillas, una sola vez (ver mrandom.md Parte 1) ----
   if (.not.iniciado) then
     call tiempos_tic(tt0)
     allocate(irn_walkers(2*nwalkers))
     block
       integer(kind=i8), device :: irn_walkers_d(2*nwalkers)
       call sacasemilla(irnmaster)
       threads = 32
       blocks = (2*nwalkers + threads - 1) / threads
       call k_split_seeds<<<blocks,threads>>>(2*nwalkers, irnmaster, irn_walkers_d)
       irn_walkers = irn_walkers_d
     end block
     iniciado = .true.
     t_seeds=t_seeds+tiempos_toc(tt0)
   endif

   ! ---- empaquetar wsim(1:nwpaso) -> arrays SoA host ----
   call tiempos_tic(tt0)
   do iwalker = 1, nwpaso
     do iatom = 1, natom
       atom_h(iwalker,iatom) = wsim(iwalker)%atom(iatom)
       dwf_h(iwalker,iatom)  = wsim(iwalker)%dwf(iatom)
     enddo
     sprop_h(iwalker,:) = wsim(iwalker)%sprop(:)
     hb2m_h(iwalker,:)  = wsim(iwalker)%hb2m(:)
     b_h(iwalker)       = wsim(iwalker)%b
     wf_h(iwalker)      = real(wsim(iwalker)%lw%wf,r8)
     wfhe4_h(iwalker)   = real(wsim(iwalker)%lw%wfhe4,r8)
     wfhe3_h(iwalker)   = real(wsim(iwalker)%lw%wfhe3,r8)
     wfm_h(iwalker)     = real(wsim(iwalker)%lw%wfm,r8)
     wfx_h(iwalker)     = real(wsim(iwalker)%lw%wfx,r8)
     kin_h(iwalker)     = wsim(iwalker)%lw%kin
     eimp_h(iwalker)    = wsim(iwalker)%lw%eimp
     erot_h(iwalker)    = wsim(iwalker)%lw%erot
     pot_h(iwalker)     = wsim(iwalker)%lw%pot
     ene_h(iwalker)     = wsim(iwalker)%lw%ene
     dphi_h(iwalker,:)  = wsim(iwalker)%dphi
   enddo
   t_pack=t_pack+tiempos_toc(tt0)

   call tiempos_tic(tt0)
   atom_d = atom_h; sprop_d = sprop_h; hb2m_d = hb2m_h; b_d = b_h
   wf_d = wf_h; wfhe4_d = wfhe4_h; wfhe3_d = wfhe3_h; wfm_d = wfm_h; wfx_d = wfx_h
   kin_d = kin_h; eimp_d = eimp_h; erot_d = erot_h; pot_d = pot_h; ene_d = ene_h
   dwf_d = dwf_h; dphi_d = dphi_h
   irn_d = irn_walkers(1:nwpaso)
   t_h2d=t_h2d+tiempos_toc(tt0)

   ! ---- un unico lanzamiento para todos los walkers en paralelo ----
   call tiempos_tic(tt0)
   threads = 32
   blocks = (nwpaso + threads - 1) / threads
   call k_dmc2<<<blocks,threads>>>(nwpaso, atom_d, sprop_d, hb2m_d, b_d, &
                                    wf_d, wfhe4_d, wfhe3_d, wfm_d, wfx_d, &
                                    kin_d, eimp_d, erot_d, pot_d, ene_d, &
                                    dwf_d, dphi_d, irn_d, nsons_d)
   istat_sync = cudaDeviceSynchronize()
   t_kernel=t_kernel+tiempos_toc(tt0)

   call tiempos_tic(tt0)
   atom_h = atom_d; sprop_h = sprop_d
   wf_h = wf_d; wfhe4_h = wfhe4_d; wfhe3_h = wfhe3_d; wfm_h = wfm_d; wfx_h = wfx_d
   kin_h = kin_d; eimp_h = eimp_d; erot_h = erot_d; pot_h = pot_d; ene_h = ene_d
   dwf_h = dwf_d; dphi_h = dphi_d
   nsons = nsons_d
   irn_walkers(1:nwpaso) = irn_d
   t_d2h=t_d2h+tiempos_toc(tt0)

   ! ---- desempaquetar de vuelta en wsim(1:nwpaso) ----
   call tiempos_tic(tt0)
   do iwalker = 1, nwpaso
     do iatom = 1, natom
       wsim(iwalker)%atom(iatom) = atom_h(iwalker,iatom)
       wsim(iwalker)%dwf(iatom)  = dwf_h(iwalker,iatom)
     enddo
     wsim(iwalker)%sprop(:)    = sprop_h(iwalker,:)
     wsim(iwalker)%lw%wf       = wf_h(iwalker)
     wsim(iwalker)%lw%wfhe4    = wfhe4_h(iwalker)
     wsim(iwalker)%lw%wfhe3    = wfhe3_h(iwalker)
     wsim(iwalker)%lw%wfm      = wfm_h(iwalker)
     wsim(iwalker)%lw%wfx      = wfx_h(iwalker)
     wsim(iwalker)%lw%kin      = kin_h(iwalker)
     wsim(iwalker)%lw%eimp     = eimp_h(iwalker)
     wsim(iwalker)%lw%erot     = erot_h(iwalker)
     wsim(iwalker)%lw%pot      = pot_h(iwalker)
     wsim(iwalker)%lw%ene      = ene_h(iwalker)
     wsim(iwalker)%dphi        = dphi_h(iwalker,:)
   enddo
   t_unpack=t_unpack+tiempos_toc(tt0)

   ! ---- reparticion/compactacion de la poblacion: MISMA logica que
   ! pasodmc, moviendo tambien irn_walkers junto con wsim ----
   call tiempos_tic(tt0)
   nwfin=0
   nwrep=0
   do iwalker=1,nwpaso
     if(nsons(iwalker).gt.0) then
       nwfin=nwfin+1
       wsim(nwfin)=wsim(iwalker)
       irn_walkers(nwfin)=irn_walkers(iwalker)
       do isons=2,nsons(iwalker)
         nwrep=nwrep+1
         if(nwpaso+nwrep.le.2*nwalkers) then
           wsim(nwpaso+nwrep)=wsim(iwalker)
           irn_walkers(nwpaso+nwrep)=irn_walkers(iwalker)
         endif
       enddo
     endif
   enddo

   do iwalker=1,nwrep
     if(nwfin+1.gt.2*nwalkers) exit
     if(nwpaso+iwalker.gt.2*nwalkers) exit
     nwfin=nwfin+1
     wsim(nwfin)=wsim(nwpaso+iwalker)
     irn_walkers(nwfin)=irn_walkers(nwpaso+iwalker)
   enddo

   nwnew=nwfin
   nwold=nwpaso
   egrow=etrial-log(nwnew/nwold)/dtau
   ivez=ivez+1
   segrow=segrow+egrow
   if(ivez.eq.ncetrial) then
     etrial=0.50_r8*(etrial+segrow/ncetrial)
     ivez=0
     segrow=0.0_r8
   endif

   nwpaso=nwfin
   t_repart=t_repart+tiempos_toc(tt0)

   t_pasodmc_gpu_body=t_pasodmc_gpu_body+tiempos_toc(tt0body)

 end subroutine pasodmc_gpu

! ---- pasodmc_gpu_pipeline (opcion=7): mismo algoritmo exacto que
! pasodmc_gpu (empaqueta wsim -> SoA, corre en GPU, desempaqueta,
! reparte poblacion segun nsons -- identico), pero el lanzamiento de
! k_dmc2 se sustituye por el grafo de 7 fases de mdmc2_pipeline
! (inicializa_pipeline/lanza_pipeline), con derananum/vpot corriendo en
! paralelo dentro de esas fases (arquitectura-streams-kin-pot.md Parte
! 12-13). Los arrays SoA device NO son locales aqui (a diferencia de
! pasodmc_gpu): son los persistentes de mdmc2_pipeline, dimensionados a
! 2*nwalkers -- se usa solo la seccion 1:nwpaso en cada paso. ----
 subroutine pasodmc_gpu_pipeline(nwpaso,egrow,wsim)
  integer(kind=i4), intent (inout) :: nwpaso
  real(kind=r8), intent (out) :: egrow
  type(walker), intent (inout) :: wsim(2*nwalkers)
  real(kind=r8) :: nwnew,nwold
  integer(kind=i4) :: nwfin,nwrep
  integer(kind=i4) :: iwalker,isons,iatom
  integer(kind=i4) :: idecorrela
  real(kind=r8) :: rn_decorrela
  integer(kind=i4), save :: ivez=0
  real(kind=r8), save :: segrow=0.0_r8
  integer(kind=i8), save, allocatable :: irn_walkers(:)
  logical, save :: iniciado=.false.
  integer(kind=i8) :: irnmaster
  integer(kind=i4) :: threads, blocks
  integer(kind=i8t) :: tt0, tt0body

  ! ---- SoA host, dimensionadas a nwpaso (varia paso a paso) -- mismo
  ! patron que pasodmc_gpu, solo para empaquetar/desempaquetar wsim.
  ! hb2m/b ya NO estan aqui -- son constantes fisicas (nunca cambian
  ! durante la simulacion, ver aos-to-soa.md) que se empaquetan y
  ! copian a device UNA SOLA VEZ, en el bloque ".not.iniciado" de mas
  ! abajo, no en cada paso. wfhe4/wfhe3/wfm/wfx tampoco estan: nada las
  ! lee nunca (ni otro kernel del pipeline ni el lado CPU), se
  ! eliminaron del todo del round-trip -- ver ese mismo documento. ----
  type(vec3) :: atom_h(nwpaso,natom), sprop_h(nwpaso,3)
  real(kind=r8) :: wf_h(nwpaso)
  real(kind=r8) :: kin_h(nwpaso), eimp_h(nwpaso), erot_h(nwpaso), pot_h(nwpaso), ene_h(nwpaso)
  type(vec3) :: dwf_h(nwpaso,natom)
  real(kind=r8) :: dphi_h(nwpaso,2)
  integer(kind=i4) :: nsons(nwpaso)

  ! ---- volcado forense pre-colapso (ver comparacion-final.md,
  ! "prueba de recalculo en CPU pura"): justo antes de lanzar el grafo
  ! (call lanza_pipeline), se guarda una copia de TODO lo que dmc2_hd
  ! necesita para recalcular estos mismos walkers en el host, sin GPU.
  ! Si tras procesar el paso resulta nwfin=0 (colapso), ese buffer
  ! (el estado DE ENTRADA a ese paso, no el de salida) se escribe a
  ! disco una sola vez -- es el snapshot que usa driver_replay.f90. ----
  type(vec3), save, allocatable :: dump_atom(:,:), dump_sprop(:,:), dump_dwf(:,:)
  real(kind=r8), save, allocatable :: dump_hb2m(:,:), dump_b(:), dump_dphi(:,:)
  real(kind=r8), save, allocatable :: dump_wf(:), dump_wfhe4(:), dump_wfhe3(:), dump_wfm(:), dump_wfx(:)
  real(kind=r8), save, allocatable :: dump_kin(:), dump_eimp(:), dump_erot(:), dump_pot(:), dump_ene(:)
  integer(kind=i8), save, allocatable :: dump_irn(:)
  integer(kind=i4), save :: dump_nwpaso
  logical, save :: volcado_hecho = .false.
  integer(kind=i4) :: uvolcado

   call tiempos_tic(tt0body)

   ! ---- Fase 3: solo etrial cambia paso a paso -- las otras 24
   ! constantes se sincronizan una sola vez, mas abajo, la primera vez
   ! que se llama a esta subrutina (ver msync_gpu.cuf) ----
   call tiempos_tic(tt0)
   call sincroniza_etrial_gpu
   t_sync7=t_sync7+tiempos_toc(tt0)

   if (.not.iniciado) then
     call sincroniza_constantes_gpu
     allocate(irn_walkers(2*nwalkers))
     block
       integer(kind=i8), device :: irn_walkers_d(2*nwalkers)
       call sacasemilla(irnmaster)
       threads = 32
       blocks = (2*nwalkers + threads - 1) / threads
       call k_split_seeds<<<blocks,threads>>>(2*nwalkers, irnmaster, irn_walkers_d)
       irn_walkers = irn_walkers_d
     end block
     call inicializa_pipeline(2*nwalkers)
     ! ---- hb2m/b (v3-cuda-optimizacion/fase2-medicion-mejoras/
     ! aos-to-soa.md): constantes fisicas por atomo/walker, fijadas UNA
     ! VEZ en iniwalkers (mmontecarlo.f90) y nunca modificadas despues
     ! -- el MISMO valor en wsim(1) vale para cualquier walker/indice,
     ! incluso tras reparto (el reparto solo copia el valor, nunca lo
     ! cambia). Se empaquetan y copian a device aqui, una sola vez para
     ! toda la corrida, en vez de en cada paso. ----
     block
       real(kind=r8) :: hb2m_h_once(2*nwalkers,natom), b_h_once(2*nwalkers)
       integer(kind=i4) :: iw2
       do iw2 = 1, 2*nwalkers
         hb2m_h_once(iw2,:) = wsim(1)%hb2m(:)
         b_h_once(iw2) = wsim(1)%b
       enddo
       hb2m_p = hb2m_h_once
       b_p = b_h_once
     end block
     iniciado = .true.
   endif

   ! ---- empaquetar wsim(1:nwpaso) -> arrays SoA host ----
   call tiempos_tic(tt0)
   do iwalker = 1, nwpaso
     do iatom = 1, natom
       atom_h(iwalker,iatom) = wsim(iwalker)%atom(iatom)
       dwf_h(iwalker,iatom)  = wsim(iwalker)%dwf(iatom)
     enddo
     sprop_h(iwalker,:) = wsim(iwalker)%sprop(:)
     wf_h(iwalker)      = real(wsim(iwalker)%lw%wf,r8)
     kin_h(iwalker)     = wsim(iwalker)%lw%kin
     pot_h(iwalker)     = wsim(iwalker)%lw%pot
     ene_h(iwalker)     = wsim(iwalker)%lw%ene
     dphi_h(iwalker,:)  = wsim(iwalker)%dphi
   enddo
   t_pack7=t_pack7+tiempos_toc(tt0)

   call tiempos_tic(tt0)
   atom_p(1:nwpaso,:) = atom_h; sprop_p(1:nwpaso,:) = sprop_h
   wf_p(1:nwpaso) = wf_h
   ! kin_p/pot_p: NO se copian a device (ver stall-.../aos-to-soa.md,
   ! mismo caso ya resuelto para eimp/erot) -- ni k_fase_a ni k_fase_d
   ! los reciben como argumento, y k_derananum_join_t/k_vpot_3warp_t
   ! los sobrescriben con el valor fresco de ESTE paso antes de que
   ! nadie los lea. kin_h/pot_h se mantienen empaquetados (arriba) solo
   ! para el volcado forense de mas abajo, que si necesita el valor de
   ! ENTRADA real.
   ene_p(1:nwpaso) = ene_h
   dwf_p(1:nwpaso,:) = dwf_h; dphi_p(1:nwpaso,:) = dphi_h
   irn_p(1:nwpaso) = irn_walkers(1:nwpaso)
   t_h2d7=t_h2d7+tiempos_toc(tt0)

   ! ---- buffer forense: copia del estado de ENTRADA a este paso,
   ! sobrescrito en cada llamada (solo el ultimo antes de un posible
   ! colapso se llega a escribir a disco, ver mas abajo) ----
   if (.not. volcado_hecho) then
     if (allocated(dump_atom)) deallocate(dump_atom, dump_sprop, dump_hb2m, dump_b, &
         dump_wf, dump_wfhe4, dump_wfhe3, dump_wfm, dump_wfx, &
         dump_kin, dump_eimp, dump_erot, dump_pot, dump_ene, &
         dump_dwf, dump_dphi, dump_irn)
     allocate(dump_atom(nwpaso,natom), dump_sprop(nwpaso,3), dump_hb2m(nwpaso,natom), dump_b(nwpaso), &
         dump_wf(nwpaso), dump_wfhe4(nwpaso), dump_wfhe3(nwpaso), dump_wfm(nwpaso), dump_wfx(nwpaso), &
         dump_kin(nwpaso), dump_eimp(nwpaso), dump_erot(nwpaso), dump_pot(nwpaso), dump_ene(nwpaso), &
         dump_dwf(nwpaso,natom), dump_dphi(nwpaso,2), dump_irn(nwpaso))
     dump_atom = atom_h; dump_sprop = sprop_h
     dump_wf = wf_h
     dump_kin = kin_h; dump_pot = pot_h; dump_ene = ene_h
     dump_dwf = dwf_h; dump_dphi = dphi_h; dump_irn = irn_walkers(1:nwpaso)
     dump_nwpaso = nwpaso
     ! hb2m/b/wfhe4/wfhe3/wfm/wfx/eimp/erot: ya no llegan frescos por
     ! _h (aos-to-soa.md -- hb2m/b se copian una sola vez, wfhe4/wfhe3/
     ! wfm/wfx ya no viajan, eimp/erot solo se traen de vuelta, no se
     ! empaquetan). driver_replay.f90/dmc2_hd no las necesita como
     ! entrada (son salidas de derananum, no entradas -- mismo
     ! razonamiento que la eliminacion en si), pero se guardan tal
     ! cual estan en wsim para no romper el formato del volcado. ----
     do iwalker = 1, nwpaso
       dump_hb2m(iwalker,:) = wsim(iwalker)%hb2m(:)
       dump_b(iwalker)      = wsim(iwalker)%b
       dump_wfhe4(iwalker)  = real(wsim(iwalker)%lw%wfhe4,r8)
       dump_wfhe3(iwalker)  = real(wsim(iwalker)%lw%wfhe3,r8)
       dump_wfm(iwalker)    = real(wsim(iwalker)%lw%wfm,r8)
       dump_wfx(iwalker)    = real(wsim(iwalker)%lw%wfx,r8)
       dump_eimp(iwalker)   = wsim(iwalker)%lw%eimp
       dump_erot(iwalker)   = wsim(iwalker)%lw%erot
     enddo
   endif

   ! ---- lanzamiento del grafo de 7 fases (ya construido, solo se
   ! actualiza nw_actual y se relanza) ----
   call tiempos_tic(tt0)
   call lanza_pipeline(nwpaso)
   t_kernel7=t_kernel7+tiempos_toc(tt0)

   call tiempos_tic(tt0)
   atom_h = atom_p(1:nwpaso,:); sprop_h = sprop_p(1:nwpaso,:)
   wf_h = wf_p(1:nwpaso)
   kin_h = kin_p(1:nwpaso); eimp_h = eimp_p(1:nwpaso); erot_h = erot_p(1:nwpaso)
   pot_h = pot_p(1:nwpaso); ene_h = ene_p(1:nwpaso)
   dwf_h = dwf_p(1:nwpaso,:); dphi_h = dphi_p(1:nwpaso,:)
   nsons = nsons_p(1:nwpaso)
   irn_walkers(1:nwpaso) = irn_p(1:nwpaso)
   t_d2h7=t_d2h7+tiempos_toc(tt0)

   ! ---- desempaquetar de vuelta en wsim(1:nwpaso) ----
   call tiempos_tic(tt0)
   do iwalker = 1, nwpaso
     do iatom = 1, natom
       wsim(iwalker)%atom(iatom) = atom_h(iwalker,iatom)
       wsim(iwalker)%dwf(iatom)  = dwf_h(iwalker,iatom)
     enddo
     wsim(iwalker)%sprop(:)    = sprop_h(iwalker,:)
     wsim(iwalker)%lw%wf       = wf_h(iwalker)
     wsim(iwalker)%lw%kin      = kin_h(iwalker)
     wsim(iwalker)%lw%eimp     = eimp_h(iwalker)
     wsim(iwalker)%lw%erot     = erot_h(iwalker)
     wsim(iwalker)%lw%pot      = pot_h(iwalker)
     wsim(iwalker)%lw%ene      = ene_h(iwalker)
     wsim(iwalker)%dphi        = dphi_h(iwalker,:)
   enddo
   t_unpack7=t_unpack7+tiempos_toc(tt0)

   call tiempos_tic(tt0)
   ! ---- reparticion/compactacion de la poblacion: MISMA logica que
   ! pasodmc/pasodmc_gpu, con una correccion (ver comparacion-final.md,
   ! "hallazgo: colapso de poblacion por semillas clonadas"): cada COPIA
   ! nueva de un walker que se reproduce (isons=2..nsons) heredaba la
   ! semilla irn LITERAL de su padre -- como irn determina todos los
   ! sorteos futuros, dos clones con el mismo irn se mueven identicos
   ! para siempre, sin decorrelar jamas. Con miles de pasos y
   ! reproduccion constante, la poblacion entera acaba descendiendo de
   ! una sola trayectoria aleatoria (confirmado: en el colapso del
   ! bloque 97, los 1936 walkers compartian el MISMO irn, no eran 1936
   ! muestras independientes). El walker que SIGUE existiendo (la
   ! primera copia, indice nwfin) no es un clon nuevo, mantiene su
   ! propio irn tal cual; solo las copias EXTRA (isons=2..nsons) se
   ! decorrelan aqui con rand1p_gpu -- el mismo generador que ya usa
   ! k_split_seeds para separar semillas, aplicado una vez por copia. ----
   nwfin=0
   nwrep=0
   do iwalker=1,nwpaso
     if(nsons(iwalker).gt.0) then
       nwfin=nwfin+1
       wsim(nwfin)=wsim(iwalker)
       irn_walkers(nwfin)=irn_walkers(iwalker)
       do isons=2,nsons(iwalker)
         nwrep=nwrep+1
         if(nwpaso+nwrep.le.2*nwalkers) then
           wsim(nwpaso+nwrep)=wsim(iwalker)
           irn_walkers(nwpaso+nwrep)=irn_walkers(iwalker)
           ! isons-1 aplicaciones: cada hermano de la misma reproduccion
           ! (isons=2,3,4...) recibe un numero distinto de pasos de
           ! rand1p_gpu, para que tambien se decorrelen ENTRE si, no
           ! solo respecto al padre (mismo criterio que k_split_seeds:
           ! aplicar rand1p k veces segun el indice)
           do idecorrela=1,isons-1
             call rand1p_gpu(rn_decorrela, irn_walkers(nwpaso+nwrep))
           enddo
         endif
       enddo
     endif
   enddo

   do iwalker=1,nwrep
     if(nwfin+1.gt.2*nwalkers) exit
     if(nwpaso+iwalker.gt.2*nwalkers) exit
     nwfin=nwfin+1
     wsim(nwfin)=wsim(nwpaso+iwalker)
     irn_walkers(nwfin)=irn_walkers(nwpaso+iwalker)
   enddo

   ! ---- colapso de poblacion (todos los walkers murieron este paso,
   ! nwfin=0): con arrays de tamano fijo (2*nwalkers, Opcion B), a
   ! diferencia de pasodmc_gpu (arrays locales dimensionados por
   ! nwpaso, que con nwpaso=0 crashea alto y claro con un ALLOCATE
   ! error), aqui no hay ningun array que falle al reservar -- sin
   ! esta comprobacion, log(nwnew/nwold) con nwnew=0 da -Infinity, que
   ! se propaga en silencio como NaN en los pasos siguientes (visto en
   ! comparacion-final.md, colapso real de poblacion a partir del
   ! bloque 97 con nwalkers=1000, semilla 11 -- fenomeno real de DMC,
   ! no un fallo de fisica del pipeline: pasodmc_gpu con la MISMA
   ! semilla/config falla en el mismo paso exacto, con el mismo
   ! ALLOCATE error). Se detiene aqui, alto y claro, en vez de seguir
   ! en silencio. ----
   if (nwfin .eq. 0) then
     write(*,'(a,i0)') 'ERROR pasodmc_gpu_pipeline: colapso de poblacion (nwfin=0) partiendo de nwpaso=', nwpaso
     write(*,*) 'Todos los walkers murieron en este paso DMC (nsons=0 para todos).'
     write(*,*) 'Deteniendo aqui en vez de propagar NaN/Inf en silencio (log(0) en el calculo de egrow).'
     if (.not. volcado_hecho) then
       open(newunit=uvolcado, file='snapshot_colapso.dat', form='unformatted', &
            access='sequential', status='replace', action='write')
       write(uvolcado) dump_nwpaso, natom, ncmtras, dtau, etrial
       write(uvolcado) dump_atom, dump_sprop, dump_hb2m, dump_b
       write(uvolcado) dump_wf, dump_wfhe4, dump_wfhe3, dump_wfm, dump_wfx
       write(uvolcado) dump_kin, dump_eimp, dump_erot, dump_pot, dump_ene
       write(uvolcado) dump_dwf, dump_dphi, dump_irn
       close(uvolcado)
       volcado_hecho = .true.
       write(*,'(a,i0,a)') 'Volcado forense escrito en snapshot_colapso.dat (', dump_nwpaso, ' walkers, estado de entrada al paso que colapsa).'
     endif
     stop 1
   endif

   nwnew=nwfin
   nwold=nwpaso
   egrow=etrial-log(nwnew/nwold)/dtau
   ivez=ivez+1
   segrow=segrow+egrow
   if(ivez.eq.ncetrial) then
     etrial=0.50_r8*(etrial+segrow/ncetrial)
     ivez=0
     segrow=0.0_r8
   endif

   nwpaso=nwfin
   t_repart7=t_repart7+tiempos_toc(tt0)

   t_pasodmc_gpu_pipeline_body=t_pasodmc_gpu_pipeline_body+tiempos_toc(tt0body)

 end subroutine pasodmc_gpu_pipeline

! ---- pasodmc_cpu_gpurand: prueba de control (opcion=6), NO pensada
! como una via de produccion mas -- procesa los walkers de uno en uno,
! secuencial, en el host (mismo orden que pasodmc original), pero cada
! walker con su propia semilla independiente repartida con
! k_split_seeds (el MISMO mecanismo y las MISMAS semillas que usa
! pasodmc_gpu). Llama a dmc2_hd, la subrutina attributes(host,device)
! de mdmc2.cuf -- la MISMA que ejecuta k_dmc2 en el device, aqui
! simplemente invocada en el host, un walker cada vez.
!
! El objetivo es aislar la UNICA diferencia real entre pasodmc
! (original) y pasodmc_gpu: el reparto de aleatoriedad (una secuencia
! compartida y secuencial entre walkers, frente a una semilla propia
! por walker) -- no la paralelizacion en si. Si esta via (secuencial
! en host, semillas de GPU) coincide bit a bit con pasodmc_gpu
! (paralelo en device, mismas semillas), queda demostrado que
! paralelizar (pasar de un bucle secuencial a k_dmc2) no introduce
! ninguna diferencia por si solo -- la diferencia entera viene del
! reparto de semillas, ya sabido y documentado desde mrandom.md.
 subroutine pasodmc_cpu_gpurand(nwpaso,egrow,wsim)
  integer(kind=i4), intent (inout) :: nwpaso
  real(kind=r8), intent (out) :: egrow
  type(walker), intent (inout) :: wsim(2*nwalkers)
  real(kind=r8) :: nwnew,nwold
  integer(kind=i4) :: nwfin,nwrep
  integer(kind=i4) :: nsons
  integer(kind=i4) :: iwalker,isons,iatom
  integer(kind=i4), save :: ivez=0
  real(kind=r8), save :: segrow=0.0_r8
  integer(kind=i8), save, allocatable :: irn_walkers(:)
  logical, save :: iniciado=.false.
  integer(kind=i8) :: irnmaster
  integer(kind=i4) :: threads, blocks

  type(vec3) :: atom_l(natom), sprop_l(3), dwf_l(natom)
  real(kind=r8) :: hb2m_l(natom), b_l
  real(kind=r8) :: wf_l, wfhe4_l, wfhe3_l, wfm_l, wfx_l
  real(kind=r8) :: kin_l, eimp_l, erot_l, pot_l, ene_l
  real(kind=r8) :: dphi_l(2)

   call sincroniza_globales_gpu

   if (.not.iniciado) then
     allocate(irn_walkers(2*nwalkers))
     block
       integer(kind=i8), device :: irn_walkers_d(2*nwalkers)
       call sacasemilla(irnmaster)
       threads = 32
       blocks = (2*nwalkers + threads - 1) / threads
       call k_split_seeds<<<blocks,threads>>>(2*nwalkers, irnmaster, irn_walkers_d)
       irn_walkers = irn_walkers_d
     end block
     iniciado = .true.
   endif

   nwfin=0
   nwrep=0
   do iwalker=1,nwpaso
     do iatom=1,natom
       atom_l(iatom)=wsim(iwalker)%atom(iatom)
       dwf_l(iatom)=wsim(iwalker)%dwf(iatom)
     enddo
     sprop_l = wsim(iwalker)%sprop
     hb2m_l  = wsim(iwalker)%hb2m
     b_l     = wsim(iwalker)%b
     wf_l    = real(wsim(iwalker)%lw%wf,r8)
     wfhe4_l = real(wsim(iwalker)%lw%wfhe4,r8)
     wfhe3_l = real(wsim(iwalker)%lw%wfhe3,r8)
     wfm_l   = real(wsim(iwalker)%lw%wfm,r8)
     wfx_l   = real(wsim(iwalker)%lw%wfx,r8)
     kin_l   = wsim(iwalker)%lw%kin
     eimp_l  = wsim(iwalker)%lw%eimp
     erot_l  = wsim(iwalker)%lw%erot
     pot_l   = wsim(iwalker)%lw%pot
     ene_l   = wsim(iwalker)%lw%ene
     dphi_l  = wsim(iwalker)%dphi

     call dmc2_hd(atom_l, sprop_l, hb2m_l, b_l, &
                  wf_l, wfhe4_l, wfhe3_l, wfm_l, wfx_l, &
                  kin_l, eimp_l, erot_l, pot_l, ene_l, &
                  dwf_l, dphi_l, irn_walkers(iwalker), nsons)

     do iatom=1,natom
       wsim(iwalker)%atom(iatom)=atom_l(iatom)
       wsim(iwalker)%dwf(iatom)=dwf_l(iatom)
     enddo
     wsim(iwalker)%sprop    = sprop_l
     wsim(iwalker)%lw%wf    = wf_l
     wsim(iwalker)%lw%wfhe4 = wfhe4_l
     wsim(iwalker)%lw%wfhe3 = wfhe3_l
     wsim(iwalker)%lw%wfm   = wfm_l
     wsim(iwalker)%lw%wfx   = wfx_l
     wsim(iwalker)%lw%kin   = kin_l
     wsim(iwalker)%lw%eimp  = eimp_l
     wsim(iwalker)%lw%erot  = erot_l
     wsim(iwalker)%lw%pot   = pot_l
     wsim(iwalker)%lw%ene   = ene_l
     wsim(iwalker)%dphi     = dphi_l

     if(nsons.gt.0) then
       nwfin=nwfin+1
       wsim(nwfin)=wsim(iwalker)
       irn_walkers(nwfin)=irn_walkers(iwalker)
       do isons=2,nsons
         nwrep=nwrep+1
         if(nwpaso+nwrep.le.2*nwalkers) then
           wsim(nwpaso+nwrep)=wsim(iwalker)
           irn_walkers(nwpaso+nwrep)=irn_walkers(iwalker)
         endif
       enddo
     endif
   enddo

   do iwalker=1,nwrep
     if(nwfin+1.gt.2*nwalkers) exit
     if(nwpaso+iwalker.gt.2*nwalkers) exit
     nwfin=nwfin+1
     wsim(nwfin)=wsim(nwpaso+iwalker)
     irn_walkers(nwfin)=irn_walkers(nwpaso+iwalker)
   enddo

   nwnew=nwfin
   nwold=nwpaso
   egrow=etrial-log(nwnew/nwold)/dtau
   ivez=ivez+1
   segrow=segrow+egrow
   if(ivez.eq.ncetrial) then
     etrial=0.50_r8*(etrial+segrow/ncetrial)
     ivez=0
     segrow=0.0_r8
   endif

   nwpaso=nwfin

 end subroutine pasodmc_cpu_gpurand

 subroutine dmc2(w1,nsons)
  type(walker), intent (inout) :: w1
  integer(kind=i4), intent (out) :: nsons
  type(vec3) :: rtemp
  real(kind=r8) :: phix1,phiy,phix2
  real(kind=r8) :: gvar3(3)
  real(kind=r8) :: eold,wfold
  real(kind=r8) :: wftest
  real(kind=r8) :: gb
  integer(kind=i4) :: iatom
  integer(kind=i4) :: supold,sdwold

  integer(kind=i8t) :: tt0

   nsons=0

   eold=w1%lw%ene
   wfold=w1%lw%wf
   supold=w1%lw%signoup
   sdwold=w1%lw%signodw

   do iatom=1,ncmtras
     call tiempos_tic(tt0)
     call gauss3(gvar3)
     t_random=t_random+tiempos_toc(tt0)
     rtemp%comp(:)=w1%sigma1(iatom)*gvar3(:)
     rtemp=rtemp+0.50_r8*w1%sigma2(iatom)*w1%dwf(iatom)
     w1%atom(iatom)=w1%atom(iatom)+rtemp
   enddo
   if(rotamol) then
     call tiempos_tic(tt0)
     call gauss3(gvar3)
     t_random=t_random+tiempos_toc(tt0)
     phix1=w1%sig1hrot*gvar3(1)+0.50_r8*w1%sig2hrot*w1%dphi(1)
     phiy= w1%sig1rot*gvar3(2) +0.50_r8*w1%sig2rot*w1%dphi(2)
     phix2=w1%sig1hrot*gvar3(3)+0.50_r8*w1%sig2hrot*w1%dphi(1)
     call tiempos_tic(tt0)
     call rota(1,phix1,w1%sprop)
     call rota(2,phiy,w1%sprop)
     call rota(1,phix2,w1%sprop)
     t_rota=t_rota+tiempos_toc(tt0)
   endif
   call tiempos_tic(tt0)
   call hpsi(w1)
   t_hpsi=t_hpsi+tiempos_toc(tt0)
   if(supold.ne.w1%lw%signoup)  return
   if(sdwold.ne.w1%lw%signodw)  return
   wftest=(w1%lw%wf/wfold)**2
   if(wftest.lt.ratio) return

   do iatom=1,ncmtras
     rtemp=0.50_r8*w1%sigma2(iatom)*w1%dwf(iatom)
     w1%atom(iatom)=w1%atom(iatom)+rtemp
   enddo
   if(rotamol) then
     phix1= 0.50_r8*w1%sig2hrot*w1%dphi(1)
     phiy=  0.50_r8*w1%sig2rot*w1%dphi(2)
     phix2= 0.50_r8*w1%sig2hrot*w1%dphi(1)
     call tiempos_tic(tt0)
     call rota(1,phix1,w1%sprop)
     call rota(2,phiy,w1%sprop)
     call rota(1,phix2,w1%sprop)
     t_rota=t_rota+tiempos_toc(tt0)
   endif
   call tiempos_tic(tt0)
   call hpsi(w1)
   t_hpsi=t_hpsi+tiempos_toc(tt0)
   if(supold.ne.w1%lw%signoup)  return
   if(sdwold.ne.w1%lw%signodw)  return
   wftest=(w1%lw%wf/wfold)**2
   if(wftest.lt.ratio) return

   gb=exp(-(0.50_r8*(eold+w1%lw%ene)-etrial)*dtau)
   call tiempos_tic(tt0)
   nsons=int(gb+rn1())
   t_random=t_random+tiempos_toc(tt0)

   if(nsons.gt.10) nsons=0


 end subroutine dmc2

 subroutine pasomet(w1)
  type(walker), intent (inout) :: w1
  type(vec3) :: rtemp,etemp(3)
  type(vloc) :: ltemp
  real(kind=r8) :: rn3(3),rn
  real(kind=r8) :: cowf,prob
  real(kind=r8) :: phi
  real(kind=r8) :: wfxo
  integer (kind=i4) :: ipasodc
  integer (kind=i4) :: iatom,ic


   do ipasodc=1,npasosdc
     do iatom=1,ncmtras
       rtemp=w1%atom(iatom)
       ltemp=w1%lw
       call randv3(rn3)
       w1%atom(iatom)%comp(:)=rtemp%comp(:)+w1%delta(iatom)*(rn3(:)-0.50_r8)
       call iwavef(iatom,rtemp,w1,cowf)
!      prob=(w1%lw%wf/ltemp%wf)**2
       prob=cowf**2
       pmcvtot=pmcvtot+1.0_r8
       if(iatom.le.nhe4) then
         pmcvtothe4=pmcvtothe4+1.0_r8
       elseif(iatom.le.ngatom) then
         pmcvtothe3=pmcvtothe3+1.0_r8
       else
         pmcvtotx=pmcvtotx+1.0_r8
       endif
       if(prob.gt.rn1()) then
         pmcvacep=pmcvacep+1.0_r8
         if(iatom.le.nhe4) then
           pmcvacephe4=pmcvacephe4+1.0_r8
         elseif(iatom.le.ngatom) then
           pmcvacephe3=pmcvacephe3+1.0_r8
         else
           pmcvacepx=pmcvacepx+1.0_r8
         endif
       else
         w1%atom(iatom)=rtemp
         w1%lw=ltemp
       endif
     enddo
     if(rotamol) then
       do ic=1,2
         wfxo=w1%lw%wfx
         etemp(:)=w1%sprop(:)
         phi=w1%dangle*(rn1()-0.50_r8)
         call rota(ic,phi,w1%sprop)
         call ewavefx(etemp(3),w1,cowf)
!        prob=(w1%lw%wfx/wfxo)**2
         prob=cowf**2
         pmcvtot=pmcvtot+1.0_r8
         pmcvtotrot=pmcvtotrot+1.0_r8
         if(prob.gt.rn1()) then
           pmcvacep=pmcvacep+1.0_r8
           pmcvaceprot=pmcvaceprot+1.0_r8
!          w1%lw%wf=w1%lw%wf*(w1%lw%wfx/wfxo)
           w1%lw%wf=w1%lw%wf*cowf
         else
           w1%sprop(:)=etemp(:)
           w1%lw%wfx=wfxo
         endif
       enddo
     endif
   enddo

 end subroutine pasomet

end module msteps
