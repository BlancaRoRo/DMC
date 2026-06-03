module msteps

 use mparametros
 use mtipos
 use mrandom
 use mwavef
 use mrotaciones
 use mmcvpromedia

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

   nwfin=0
   nwrep=0
   do iwalker=1,nwpaso
     call dmc2(wsim(iwalker),nsons)
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

 end subroutine pasodmc

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

   nsons=0

   eold=w1%lw%ene
   wfold=w1%lw%wf
   supold=w1%lw%signoup
   sdwold=w1%lw%signodw

   do iatom=1,ncmtras
     call gauss3(gvar3)
     rtemp%comp(:)=w1%sigma1(iatom)*gvar3(:)
     rtemp=rtemp+0.50_r8*w1%sigma2(iatom)*w1%dwf(iatom)
     w1%atom(iatom)=w1%atom(iatom)+rtemp
   enddo  
   if(rotamol) then
     call gauss3(gvar3)
     phix1=w1%sig1hrot*gvar3(1)+0.50_r8*w1%sig2hrot*w1%dphi(1)
     phiy= w1%sig1rot*gvar3(2) +0.50_r8*w1%sig2rot*w1%dphi(2)
     phix2=w1%sig1hrot*gvar3(3)+0.50_r8*w1%sig2hrot*w1%dphi(1)
     call rota(1,phix1,w1%sprop)
     call rota(2,phiy,w1%sprop)
     call rota(1,phix2,w1%sprop)
   endif
   call hpsi(w1)
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
     call rota(1,phix1,w1%sprop)
     call rota(2,phiy,w1%sprop)
     call rota(1,phix2,w1%sprop)
   endif
   call hpsi(w1)
   if(supold.ne.w1%lw%signoup)  return
   if(sdwold.ne.w1%lw%signodw)  return
   wftest=(w1%lw%wf/wfold)**2
   if(wftest.lt.ratio) return

   gb=exp(-(0.50_r8*(eold+w1%lw%ene)-etrial)*dtau)
   nsons=int(gb+rn1())

   if(nsons.gt.10) nsons=0


 end subroutine dmc2

 subroutine pasomet(w1)
  type(walker), intent (inout) :: w1
  type(vec3) :: rtemp,etemp(3)
  type(vloc) :: ltemp
  real(kind=r8) :: rn3(3),rn
  real(kind=r8) :: cowf,prob
  real(kind=r8) :: phi
  real(kind=r8) :: log_wfxo, dlog
  integer (kind=i4) :: ipasodc
  integer (kind=i4) :: iatom,ic
  logical :: acepta


   do ipasodc=1,npasosdc
     do iatom=1,ncmtras
       rtemp=w1%atom(iatom)
       ltemp=w1%lw          ! guarda log_wfx antiguo en ltemp%log_wfx
       call randv3(rn3)
       w1%atom(iatom)%comp(:)=rtemp%comp(:)+w1%delta(iatom)*(rn3(:)-0.50_r8)
       call iwavef(iatom,rtemp,w1,cowf)  ! actualiza w1%lw%log_wfx y devuelve cowf
       pmcvtot=pmcvtot+1.0_r8
       if(iatom.le.nhe4) then
         pmcvtothe4=pmcvtothe4+1.0_r8
       elseif(iatom.le.ngatom) then
         pmcvtothe3=pmcvtothe3+1.0_r8
       else
         pmcvtotx=pmcvtotx+1.0_r8
       endif
       ! Para el CM de la impureza (iatom==natom): aceptación en espacio log
       ! usando log_wfx (sin underflow ni clamping). Para los demás átomos
       ! (He4/He3), cowf=che4×cmix×cimp ya contiene la ratio completa.
       if (impureza .and. iatom == natom) then
         dlog = w1%lw%log_wfx - ltemp%log_wfx
         rn   = rn1()
         acepta = (rn <= 0.0_r8 .or. 2.0_r8*dlog >= log(rn))
       else
         prob   = cowf**2
         acepta = (prob > rn1())
       end if
       if(acepta) then
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
         w1%lw=ltemp        ! restaura log_wfx antiguo
       endif
     enddo
     if(rotamol) then
       do ic=1,2
         log_wfxo=w1%lw%log_wfx
         etemp(:)=w1%sprop(:)
         phi=w1%dangle*(rn1()-0.50_r8)
         call rota(ic,phi,w1%sprop)
         call ewavefx(etemp(3),w1,cowf)  ! actualiza w1%lw%log_wfx
         dlog = w1%lw%log_wfx - log_wfxo
         rn   = rn1()
         acepta = (rn <= 0.0_r8 .or. 2.0_r8*dlog >= log(rn))
         pmcvtot=pmcvtot+1.0_r8
         pmcvtotrot=pmcvtotrot+1.0_r8
         if(acepta) then
           pmcvacep=pmcvacep+1.0_r8
           pmcvaceprot=pmcvaceprot+1.0_r8
         else
           w1%sprop(:)=etemp(:)
           w1%lw%log_wfx=log_wfxo
           w1%lw%wfx=exp(log_wfxo)
         endif
       enddo
     endif
   enddo

 end subroutine pasomet

end module msteps
