module msteps

 use mparametros
 use mtipos
 use mrandom
 use mwavef
 use mrotaciones
 use mmcvpromedia
 use cudafor
 use dmc_gpu_params, only: d_etrial, gpu_soa_h2d, gpu_soa_d2h
 use dmc_gpu,        only: dmc2_gpu_kernel

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: i8=selected_int_kind(15)
 integer, private, parameter :: r8=selected_real_kind(15,9)

contains

 !============================================================
 ! pasodmc: un paso DMC con managed memory.
 !
 ! Con -gpu=managed los arrays SOA del device son accesibles desde
 ! CPU y GPU sin copias PCIe explicitas. El flujo es:
 !   1. CPU:  AOS wsim -> SOA managed  (aos_to_soa)
 !   2. GPU:  kernel lee/escribe SOA managed directamente
 !   3. CPU:  SOA managed -> AOS wsim  (soa_to_aos, tras sync)
 !   4. CPU:  gestion de walkers muertos/duplicados sobre wsim
 !============================================================
 subroutine pasodmc(nwpaso, egrow, wsim)
  integer(kind=i4), intent(inout) :: nwpaso
  real(kind=r8),    intent(out)   :: egrow
  type(walker),     intent(inout) :: wsim(2*nwalkers)

  integer(kind=i4) :: nwfin, nwrep, nsons
  integer(kind=i4) :: iwalker, isons
  real(kind=r8)    :: nwnew, nwold
  integer          :: hilos, bloques, istat
  integer(kind=i4), save :: ivez   = 0
  real(kind=r8),    save :: segrow = 0.0_r8

  ! 32 hilos/bloque: cada hilo tiene 2048 registros en CC8.9 -> sin spilling
  hilos   = 32
  bloques = (nwpaso + hilos - 1) / hilos

  ! Sincronizar etrial (puede cambiar entre pasos)
  d_etrial = etrial

  ! Paso 1: AOS -> host SOA
  call aos_to_soa(wsim, nwpaso, natom)
  ! Paso 2: host SOA -> device SOA managed (CPU memcpy, no PCIe gracias a managed)
  call gpu_soa_h2d(nwpaso, natom)

  ! Paso 3: Kernel GPU
  call dmc2_gpu_kernel<<<bloques, hilos>>>(nwpaso, natom)
  istat = cudaDeviceSynchronize()

  ! Paso 4: device SOA managed -> host SOA (CPU memcpy) -> AOS
  call gpu_soa_d2h(nwpaso, natom)
  call soa_to_aos(wsim, nwpaso, natom)

  ! --- Paso 4: Gestion de walkers sobre AOS en CPU ---
  nwfin = 0
  nwrep = 0

  do iwalker = 1, nwpaso
     nsons = wsim(iwalker)%nsons

     if (nsons > 0) then
       nwfin = nwfin + 1
       wsim(nwfin) = wsim(iwalker)

       do isons = 2, nsons
         nwrep = nwrep + 1
         if (nwpaso + nwrep <= 2*nwalkers) then
           wsim(nwpaso + nwrep) = wsim(iwalker)
         endif
       enddo
     endif
  enddo

  do iwalker = 1, nwrep
    if (nwfin + 1 > 2*nwalkers) exit
    nwfin = nwfin + 1
    wsim(nwfin) = wsim(nwpaso + iwalker)
  enddo

  nwnew = real(nwfin, r8)
  nwold = real(nwpaso, r8)
  egrow = etrial - log(nwnew / nwold) / dtau

  ivez   = ivez + 1
  segrow = segrow + egrow

  if (ivez == ncetrial) then
    etrial = 0.50_r8 * (etrial + segrow / ncetrial)
    ivez   = 0
    segrow = 0.0_r8
  endif

  nwpaso = nwfin

 end subroutine pasodmc

 !============================================================
 ! dmc2: version CPU (mantenida para referencia / tests)
 ! En produccion con GPU solo se usa pasodmc -> dmc2_gpu_kernel
 !============================================================
 subroutine dmc2(w1, nsons)
  type(walker), intent(inout) :: w1
  integer(kind=i4), intent(out) :: nsons
  type(vec3) :: rtemp
  real(kind=r8) :: phix1, phiy, phix2
  real(kind=r8) :: gvar3(3)
  real(kind=r8) :: eold, wfold
  real(kind=r8) :: wftest
  real(kind=r8) :: gb
  integer(kind=i4) :: iatom
  integer(kind=i4) :: supold, sdwold

   nsons = 0

   eold   = w1%lw%ene
   wfold  = w1%lw%wf
   supold = w1%lw%signoup
   sdwold = w1%lw%signodw

   do iatom = 1, ncmtras
     call gauss3(gvar3)
     rtemp%comp(:) = w1%sigma1(iatom)*gvar3(:)
     rtemp = rtemp + 0.50_r8*w1%sigma2(iatom)*w1%dwf(iatom)
     w1%atom(iatom) = w1%atom(iatom) + rtemp
   enddo
   if (rotamol) then
     call gauss3(gvar3)
     phix1 = w1%sig1hrot*gvar3(1) + 0.50_r8*w1%sig2hrot*w1%dphi(1)
     phiy  = w1%sig1rot *gvar3(2) + 0.50_r8*w1%sig2rot *w1%dphi(2)
     phix2 = w1%sig1hrot*gvar3(3) + 0.50_r8*w1%sig2hrot*w1%dphi(1)
     call rota(1, phix1, w1%sprop)
     call rota(2, phiy,  w1%sprop)
     call rota(1, phix2, w1%sprop)
   endif
   call hpsi(w1)
   if (supold /= w1%lw%signoup) return
   if (sdwold /= w1%lw%signodw) return
   wftest = (w1%lw%wf / wfold)**2
   if (wftest < ratio) return

   do iatom = 1, ncmtras
     rtemp = 0.50_r8 * w1%sigma2(iatom) * w1%dwf(iatom)
     w1%atom(iatom) = w1%atom(iatom) + rtemp
   enddo
   if (rotamol) then
     phix1 = 0.50_r8 * w1%sig2hrot * w1%dphi(1)
     phiy  = 0.50_r8 * w1%sig2rot  * w1%dphi(2)
     phix2 = 0.50_r8 * w1%sig2hrot * w1%dphi(1)
     call rota(1, phix1, w1%sprop)
     call rota(2, phiy,  w1%sprop)
     call rota(1, phix2, w1%sprop)
   endif
   call hpsi(w1)
   if (supold /= w1%lw%signoup) return
   if (sdwold /= w1%lw%signodw) return
   wftest = (w1%lw%wf / wfold)**2
   if (wftest < ratio) return

   gb    = exp(-(0.50_r8*(eold + w1%lw%ene) - etrial) * dtau)
   nsons = int(gb + rn1())
   if (nsons > 10) nsons = 0

 end subroutine dmc2

 subroutine pasomet(w1)
  type(walker), intent(inout) :: w1
  type(vec3)  :: rtemp, etemp(3)
  type(vloc)  :: ltemp
  real(kind=r8) :: rn3(3), rn
  real(kind=r8) :: cowf, prob
  real(kind=r8) :: phi
  real(kind=r8) :: wfxo
  integer(kind=i4) :: ipasodc
  integer(kind=i4) :: iatom, ic


   do ipasodc = 1, npasosdc
     do iatom = 1, ncmtras
       rtemp   = w1%atom(iatom)
       ltemp   = w1%lw
       call randv3(rn3)
       w1%atom(iatom)%comp(:) = rtemp%comp(:) + w1%delta(iatom)*(rn3(:) - 0.50_r8)
       call iwavef(iatom, rtemp, w1, cowf)
       prob = cowf**2
       pmcvtot = pmcvtot + 1.0_r8
       if (iatom <= nhe4) then
         pmcvtothe4 = pmcvtothe4 + 1.0_r8
       elseif (iatom <= ngatom) then
         pmcvtothe3 = pmcvtothe3 + 1.0_r8
       else
         pmcvtotx = pmcvtotx + 1.0_r8
       endif
       if (prob > rn1()) then
         pmcvacep = pmcvacep + 1.0_r8
         if (iatom <= nhe4) then
           pmcvacephe4 = pmcvacephe4 + 1.0_r8
         elseif (iatom <= ngatom) then
           pmcvacephe3 = pmcvacephe3 + 1.0_r8
         else
           pmcvacepx = pmcvacepx + 1.0_r8
         endif
       else
         w1%atom(iatom) = rtemp
         w1%lw          = ltemp
       endif
     enddo
     if (rotamol) then
       do ic = 1, 2
         wfxo     = w1%lw%wfx
         etemp(:) = w1%sprop(:)
         phi      = w1%dangle*(rn1() - 0.50_r8)
         call rota(ic, phi, w1%sprop)
         call ewavefx(etemp(3), w1, cowf)
         prob = cowf**2
         pmcvtot    = pmcvtot    + 1.0_r8
         pmcvtotrot = pmcvtotrot + 1.0_r8
         if (prob > rn1()) then
           pmcvacep    = pmcvacep    + 1.0_r8
           pmcvaceprot = pmcvaceprot + 1.0_r8
           w1%lw%wf    = w1%lw%wf * cowf
         else
           w1%sprop(:) = etemp(:)
           w1%lw%wfx   = wfxo
         endif
       enddo
     endif
   enddo

 end subroutine pasomet

end module msteps
