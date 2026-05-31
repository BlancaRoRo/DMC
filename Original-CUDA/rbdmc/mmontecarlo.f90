module mmontecarlo

 use mparametros
 use mconfiguraciones
 use mtipos
 use msteps
 use mwavef
 use msistref
 use mkp_heco
 use mdensidades
 use mimagina
 use mmcvpromedia
 use mdmcpromedia
 use mrandom
 use mparalelo
 use mtest_gpu
 use mderananum_gpu, only: derananum_gpu_init, derananum_gpu_alloc, aos_to_soa_da, &
                            d_wfhe4_soa_da, d_wfhe3_soa_da, d_wfm_soa_da,     &
                            d_wfx_soa_da, d_wf_soa_da, d_kin_soa_da
 use mvpot_gpu,      only: vpot_gpu_init, vpot_gpu_alloc, aos_to_soa_vp, d_pot_vp
 use mdmc2_gpu,      only: dmc2_gpu_init, dmc2_gpu_alloc, dmc2_gpu_run, &
                            aos_to_soa_d2, soa_to_aos_dmc_result, d_nsons_d2, &
                            apply_scatter
 use mhpsi_gpu,      only: hpsi_gpu_alloc_ene, hpsi_gpu_run, d_ene_hpsi
 use mgauss3_gpu,    only: gauss3_gpu_init_seeds
 use mvaziz,         only: sacaaziz

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: i8=selected_int_kind(15)
 integer, private, parameter :: r8=selected_real_kind(15,9)

 type (walker), private, save :: w1
 type (walker), private, save, allocatable :: wsim(:)
 integer(kind=i4), private, save :: nwsim

 logical, private, save :: soydire
 integer(kind=i4), private, save :: ncpar


contains

 subroutine dmc
  real(kind=r8) :: egrow
  integer(kind=i4) :: iblock,ipaso
  integer(kind=i4) :: nwpaso
  integer(kind=i4) :: dmcnvalblo,dmcnvaltot
  integer(kind=i4) :: ndens1,nhis1,ndens2,nhis2
  integer(kind=i4) :: npol,ndt
  integer(kind=i4) :: ndifus,npasosblo
  logical :: equilbr

   call iniimagina(nombre,natom,dtau,hb2x,brot)

   call dmcnumprop(dmcnvalblo,dmcnvaltot)
   call densgethis(ndens1,nhis1,ndens2,nhis2)
   call difusgethis(npol,ndt)
   ndifus=min(ndt,npasos)

   nwpaso=nwalkers

   equilbr=.true.
   npasosblo=0.2*npasos
   ndifus=min(ndt,npasosblo)
   if(soydire) call dmcescrini(equilbr)

   call dmcceroini
   call densceroini
   call difusceroini
   do iblock=1,nblockeq+nblock
     if(iblock.eq.nblockeq+1) then
       equilbr=.false.
       npasosblo=npasos
       ndifus=min(ndt,npasosblo)
       if(soydire) call dmcescrini(equilbr)
       call dmcceroini
       call densceroini
       call difusceroini
     endif
     call dmcceroblo
     call densceroblo
     call difusceroblo
     call difusfijaorigen(nwpaso,wsim)
     do ipaso=1,npasosblo
       call pasodmc(nwpaso,egrow,wsim)
       call dmcsumapaso(nwpaso,egrow,wsim)
       call denssumapaso(nwpaso,wsim)
       if(ipaso.le.ndifus) call difussumapaso(ipaso,nwpaso,wsim)
     enddo
     call dmcsumablo
     call denssumablo
     call difussumablo(ndifus)
     call dmcescrblopar(dmcnvalblo)
   enddo

   call dmcsumaproc(dmcnvaltot)
   call denssumaproc(ndens1,nhis1,ndens2,nhis2)
   call difussumaproc(npol,ndifus)

   if(soydire) then
     call dmcsumafin
     call dmcescrfin(dtau,cmtok,k2mev_bh,opot)
     call denssumafin
     call densescrfin
     call difusfin(ndifus)
   endif

 end subroutine dmc

 subroutine mcv(emcv)
 
  integer(kind=i4), parameter :: nwmcv=1
  real(kind=r8), intent (out) :: emcv(2)
  integer(kind=i4) :: iblock,ipaso
  integer(kind=i4) :: iwalker,iatom
  integer(kind=i4) :: mcvnvalblo,mcvnvaltot
  integer(kind=i4) :: ndens1,nhis1,ndens2,nhis2
  integer(kind=i4) :: nwsamp
  logical :: equilbr
  logical :: iniguarda


   call mcvnumprop(mcvnvalblo,mcvnvaltot)
   if(opcion.eq.1) call densgethis(ndens1,nhis1,ndens2,nhis2)

   iwalker=nwalkers*rn1()+1
   w1=wsim(iwalker)
   call hpsi(w1)
   do iwalker=1,nwalkers
     wsim(nwalkers+iwalker)=wsim(iwalker)
   enddo

   equilbr=.true.
   if(soydire) call mcvescrini(equilbr)
   call mcvceroini
   if(opcion.eq.1) call densceroini
   iniguarda=.true.
   nwsamp=nblockeq*npasos

   do iblock=1,nblockeq+nblock
     if(iblock.eq.nblockeq+1) then
       equilbr=.false.
       if(soydire) call mcvescrini(equilbr)
       call mcvceroini
       if(opcion.eq.1) call densceroini
       iniguarda=.true.
       nwsamp=nblock*npasos
     endif
     call mcvceroblo
     if(opcion.eq.1) call densceroblo
     do ipaso=1,npasos
       call pasomet(w1)
       call hpsi(w1)
       call mcvfiltra
       call mcvsumapaso(w1%lw)
       if(opcion.eq.1) then
         wsim(nwalkers+nwmcv)=w1
         call denssumapaso(nwmcv,wsim(nwalkers+nwmcv))
       endif
       call mcvguardaconf(iniguarda,nwsamp)
     enddo
     call mcvsumablo
     if(opcion.eq.1) call denssumablo
     call mcvescrblopar(mcvnvalblo)
   enddo
   nwsim=nwalkers

   call mcvsumaproc(mcvnvaltot)
   if(opcion.eq.1) call denssumaproc(ndens1,nhis1,ndens2,nhis2)

   if(soydire) then
     call mcvsumafin(emcv)
     call mcvescrfin(cmtok,k2mev_bh,opot)
     if(opcion.eq.1) then 
       call denssumafin
       call densescrfin
     endif
   endif

   if(opcion.eq.2) call repartereales(2,emcv)

 end subroutine mcv

 subroutine dmcescrblopar(dmcnvalblo)
  integer(kind=i4), intent (in) :: dmcnvalblo
  real(kind=r8) :: pval(dmcnvalblo)
  integer(kind=i4) :: icpar

   if(soydire) then
     do icpar=1,ncpar-1
       call direrecibereales(icpar,dmcnvalblo,pval)
       call dmcescrblo(icpar,ncpar,pval)
     enddo
     icpar=ncpar
     call dmcgetdatosblo(pval)
     call dmcescrblo(icpar,ncpar,pval)
   else
      call dmcgetdatosblo(pval)
      call otroenviareales(dmcnvalblo,pval)
   endif 

 end subroutine dmcescrblopar

 subroutine mcvescrblopar(mcvnvalblo)
  integer(kind=i4), intent (in) :: mcvnvalblo
  real(kind=r8) :: pval(mcvnvalblo)
  integer(kind=i4) :: icpar

   if(soydire) then
     do icpar=1,ncpar-1
       call direrecibereales(icpar,mcvnvalblo,pval)
       call mcvescrblo(icpar,ncpar,pval)
     enddo
     icpar=ncpar
     call mcvgetdatosblo(pval)
     call mcvescrblo(icpar,ncpar,pval)
   else
      call mcvgetdatosblo(pval)
      call otroenviareales(mcvnvalblo,pval)
   endif 

 end subroutine mcvescrblopar

 subroutine dmcsumaproc(dmcnvaltot)
  integer(kind=i4), intent (in) :: dmcnvaltot 
  real(kind=r8) :: pval(dmcnvaltot)

   call dmcgetdatostot(pval)
   call sumareales(dmcnvaltot,pval)
   if(soydire) call dmcputdatostot(pval)

 end subroutine dmcsumaproc

 subroutine mcvsumaproc(mcvnvaltot)
  integer(kind=i4), intent (in) :: mcvnvaltot 
  real(kind=r8) :: pval(mcvnvaltot)

   call mcvgetdatostot(pval)
   call sumareales(mcvnvaltot,pval)
   if(soydire) call mcvputdatostot(pval)

 end subroutine mcvsumaproc

 subroutine denssumaproc(ndens1,nhis1,ndens2,nhis2)
  integer(kind=i4), intent (in) :: ndens1,nhis1,ndens2,nhis2
  real(kind=r8) :: dens1v(nhis1),dens1e(nhis1)
  real(kind=r8) :: dens2v(nhis2),dens2e(nhis2)
  real(kind=r8) :: den1
  integer(kind=i4) :: idens

   call densgetdeno(den1)
   call sumareal(den1)
   if(soydire) call densputdeno(den1)
   do idens=1,ndens1
      call densgetdatostot(idens,nhis1,dens1v,dens1e)
      call sumareales(nhis1,dens1v)
      call sumareales(nhis1,dens1e)
      if(soydire) call densputdatostot(idens,nhis1,dens1v,dens1e)
   enddo

   do idens=ndens1+1,ndens1+ndens2
      call densgetdatostot(idens,nhis2,dens2v,dens2e)
      call sumareales(nhis2,dens2v)
      if(soydire) call densputdatostot(idens,nhis2,dens2v,dens2e)
   enddo

 end subroutine denssumaproc

 subroutine difussumaproc(npol,ndifus)
  integer(kind=i4), intent (in) :: npol,ndifus
  real(kind=r8) :: dens1v(ndifus),dens1e(ndifus)
  real(kind=r8) :: den1
  integer(kind=i4) :: idifus,ipol

   call difusgetdeno(den1)
   call sumareal(den1)
   if(soydire) call difusputdeno(den1)
   do ipol=0,npol
      call difusgetdatostot(ipol,ndifus,dens1v,dens1e)
      call sumareales(ndifus,dens1v)
      call sumareales(ndifus,dens1e)
      if(soydire) call difusputdatostot(ipol,ndifus,dens1v,dens1e)
   enddo

 end subroutine difussumaproc

 subroutine mcvguardaconf(iniguarda,nwsamp)
  logical, intent (inout) :: iniguarda
  integer(kind=i4), intent (in) :: nwsamp
  real(kind=r8), save :: faltan
  integer(kind=i4), save :: ndispon,nrepite,nwsave
  integer(kind=i4) :: irepite
  real(kind=r8) :: prob

   if(iniguarda) then
     ndispon=nwsamp
     nrepite=nwalkers/ndispon
     nwsave=0
     faltan=nwalkers-nrepite*ndispon
     iniguarda=.false.
   endif

   if(nwsave.eq.nwalkers) return

   do irepite=1,nrepite
     nwsave=nwsave+1
     wsim(nwsave)=w1
   enddo

   prob=faltan/ndispon
   if(prob.gt.rn1()) then
     nwsave=nwsave+1
     wsim(nwsave)=w1
     faltan=faltan-1.0_r8
   endif
   ndispon=ndispon-1

 end subroutine mcvguardaconf

 subroutine mcvfiltra
   integer(kind=i4) :: ivez,nvez=20
   integer(kind=i4) :: iwalker
       
    if(abs(w1%lw%ene).lt.grande) return

    do ivez=1,nvez
      iwalker=2*nwalkers*rn1()+1
      w1=wsim(iwalker)
      call hpsi(w1)
      if(abs(w1%lw%ene).lt.grande) return
    enddo

 end subroutine mcvfiltra

 subroutine corrsamp(inicia,emcv)
  logical, intent (in) :: inicia
  real(kind=r8), intent (out) :: emcv(2)
  real(kind=r8)  :: oemcv(2),semcv(2),pemcv(2)
  real(kind=r8) :: peso
  real(kind=r8) :: sumw1,sumw2,sumwe
  integer(kind=i4) :: iwalker

   sumw1=0.0_r8
   sumw2=0.0_r8
   sumwe=0.0_r8
   do iwalker=1,nwalkers
     w1=wsim(iwalker)
     call hpsi(w1)
     if(inicia) wsim(iwalker)=w1
     peso=(w1%lw%wf)**2/(wsim(iwalker)%lw%wf)**2
     sumw1=sumw1+peso
     sumw2=sumw2+peso**2
     sumwe=sumwe+peso*w1%lw%ene
  enddo
  emcv(1)=sumwe/sumw1
  emcv(2)=sumw1**2/sumw2

  call sumareales(2,emcv)
  emcv(1)=emcv(1)/ncpar
  call repartereales(2,emcv)

 end subroutine corrsamp

 subroutine checkder
  integer(kind=i4) :: iwalker,iatom

   if(soydire) then
  
     write(6,*) '*****Comprobacion numerica de las derivadas**********'
     write(6,*) '*****y calculo de funciones de onda y potencial******'

      iwalker=nwalkers*rn1()+1    
      w1=wsim(iwalker)
      call dernumeri(w1)
      call derananum(wsim(iwalker))
      write(6,'("valores numericos  de grad_i(ln(psi_T))")')
      write(6,'("valores analiticos de grad_i(ln(psi_T))")')
      do iatom=1,natom
        write(6,'("ipart",i5,3es15.6)') iatom,w1%dwf(iatom)
        write(6,'("ipart",i5,3es15.6)') iatom,wsim(iwalker)%dwf(iatom)
      enddo
      write(6,'("valores numericos  de grad_phi(ln(psi_T))")')
      write(6,'("valores analiticos de grad_phi(ln(psi_T))")')
      write(6,'("phi_x,phi_y",2es15.6)') w1%dphi
      write(6,'("phi_x,phi_y",2es15.6)') wsim(iwalker)%dphi
      write(6,'("ekin numerico",t20,es15.6)')  w1%lw%kin
      write(6,'("ekin analitico",t20,es15.6)') wsim(iwalker)%lw%kin
      write(6,'("eimp numerico",t20,es15.6)')  w1%lw%eimp
      write(6,'("eimp analitico",t20,es15.6)') wsim(iwalker)%lw%eimp
      write(6,'("erot numerico",t20,es15.6)')  w1%lw%erot
      write(6,'("erot analitico",t20,es15.6)') wsim(iwalker)%lw%erot
   
     write(6,*) '*****************************************************'

     call dibuja

     call hpsi(w1)
     write(*,*) wsim(iwalker)%lw%pot
     write(*,*) w1%lw%pot

   endif

   nwsim=nwalkers

 end subroutine checkder

 subroutine inimontecarlo

   call quiensoy(soydire)
   call cuantosparalelos(ncpar)

   if(opot.eq.3) call kp_iniciavheco

   call fijasemilla(irncal)
   call distribuyesemillas

 end subroutine inimontecarlo


 subroutine iniwalkers
  real(kind=r8) :: xwalker(3*natom*nwalkers)
  real(kind=r8) :: ewalker(3*nwalkers)
  real(kind=r8) :: gvar3(3),dnor
  real(kind=r8) :: emed
  integer(kind=i4) :: iwalker,iatom,ic
  integer(kind=i4) :: ireg,jreg

     
   call allocatewalker(w1,natom)
   allocate (wsim(2*nwalkers))
   do iwalker=1,2*nwalkers
      call allocatewalker(wsim(iwalker),natom)
   enddo

   if(soydire) then
     call iniconfiguraciones(nombre,impurmol,impurfija,rotamol,    &
  &                          nwalkers,natom,ngatom,nhe4,           &                          
  &                          deltahe4,deltahe3,deltax,xwalker,     &
  &                          ewalker)
     ireg=0
     jreg=0
     emed=0.0_r8
     do iwalker=1,nwalkers
       do iatom=1,nhe4
         do ic=1,3
           ireg=ireg+1
           w1%atom(iatom)%comp(ic)=xwalker(ireg)
         enddo
         w1%delta(iatom)=deltahe4
         w1%hb2m(iatom)=hb2he4
         w1%sigma1(iatom)=sqrt(2.0_r8*hb2he4*dtau)
         w1%sigma2(iatom)=2.0_r8*hb2he4*dtau
       enddo
       do iatom=nhe4+1,ngatom
         do ic=1,3
           ireg=ireg+1
           w1%atom(iatom)%comp(ic)=xwalker(ireg)
         enddo
         w1%delta(iatom)=deltahe3
         w1%hb2m(iatom)=hb2he3
         w1%sigma1(iatom)=sqrt(2.0_r8*hb2he3*dtau)
         w1%sigma2(iatom)=2.0_r8*hb2he3*dtau
       enddo
       if(impureza) then
         do ic=1,3
           ireg=ireg+1
           w1%atom(natom)%comp(ic)=xwalker(ireg)
         enddo
         w1%delta(natom)=deltax
         w1%hb2m(natom)=hb2x
         w1%sigma1(natom)=sqrt(2.0_r8*hb2x*dtau)
         w1%sigma2(natom)=2.0_r8*hb2x*dtau
         if(impurmol) then
           do ic=1,3
             jreg=jreg+1
             w1%sprop(3)%comp(ic)=ewalker(jreg)
           enddo
           call gauss3(gvar3)
           dnor=sqrt(sum(gvar3**2))
           do ic=1,3
             w1%sprop(2)%comp(ic)=gvar3(ic)/dnor
           enddo
           w1%sprop(1)=w1%sprop(2)*w1%sprop(3)
           dnor=sqrt(sum(w1%sprop(1)%comp**2))
           w1%sprop(1)%comp(:)=w1%sprop(1)%comp(:)/dnor
           w1%sprop(2)=w1%sprop(3)*w1%sprop(1)
           w1%dangle=deltaa
           w1%b=brot
           w1%sig1rot=sqrt(2.0_r8*brot*dtau)
           w1%sig2rot=2.0_r8*brot*dtau
           w1%sig1hrot=sqrt(2.0_r8*brot*0.50_r8*dtau)
           w1%sig2hrot=2.0_r8*brot*0.50_r8*dtau
           w1%eje0=w1%sprop(3)
           w1%pos0=w1%atom(natom)
         endif
       endif
       if(.not.impurfija) then
         call restacm(w1)
         w1%pos0=w1%atom(natom)
       endif
       call hpsi(w1)
       emed=emed+w1%lw%ene
       wsim(iwalker)=w1
     enddo
     emed=emed/nwalkers
   endif

   do iwalker=1,nwalkers
     w1=wsim(iwalker)
     call repartewalker(w1)
     wsim(iwalker)=w1
   enddo

   nwsim=nwalkers

   if(soydire) then
     write(6,'("configuraciones iniciales totales",t40,i10)') nwsim
     write(6,'("energia media",t40,f20.10)') emed
     iwalker=nwalkers*rn1()+1
     w1=wsim(iwalker)
     write(6,'("elegimos el walker",t40,i10)') iwalker
     write(6,'("energia del walker",t40,f20.10)') w1%lw%ene
     write(6,'("e poten del walker",t40,f20.10)') w1%lw%pot
     write(6,'(/,a)') ' DIAG CPU walker 1 (mwavef.f90):'
     write(6,'(a,es20.10)') '   wfhe4  = ', wsim(1)%lw%wfhe4
     write(6,'(a,es20.10)') '   wfhe3  = ', wsim(1)%lw%wfhe3
     write(6,'(a,es20.10)') '   wfm    = ', wsim(1)%lw%wfm
     write(6,'(a,es20.10)') '   wfx    = ', wsim(1)%lw%wfx
     write(6,'(a,es20.10)') '   wf     = ', wsim(1)%lw%wf
     write(6,'(a,es20.10)') '   ekin   = ', wsim(1)%lw%kin
     write(6,'(a,es20.10)') '   epot   = ', wsim(1)%lw%pot
     write(6,'(a,es20.10)') '   etotal = ', wsim(1)%lw%ene
     write(6,*)"*****************************************************"
    call flush(6)
  endif

 end subroutine iniwalkers

 subroutine finwalkers
  real(kind=r8) :: xwalker(3*natom*nwalkers),ewalker(3*nwalkers)
  real(kind=r8) :: raenmol(3*namol*nwalkers)
  real(kind=r8) :: emed
  integer(kind=i4) :: iwalker,iatom,jatom,ic
  integer(kind=i4) :: ireg,jreg,kreg

   if(soydire) then
     ireg=0
     jreg=0
     kreg=0
     emed=0.0_r8
     do iwalker=1,nwsim
       if(.not.impurfija) then
         call restacm(wsim(iwalker))
       endif
       do iatom=1,natom
         do ic=1,3
           ireg=ireg+1
           xwalker(ireg)=wsim(iwalker)%atom(iatom)%comp(ic)
         enddo
       enddo
       if(impurmol) then
         do ic=1,3
           jreg=jreg+1
           ewalker(jreg)=wsim(iwalker)%sprop(3)%comp(ic)
         enddo
         call cespacio(wsim(iwalker),raenmol(kreg+1))
         kreg=kreg+3*namol
       endif
       emed=emed+w1%lw%ene
     enddo
     emed=emed/nwsim

     call finconfiguraciones(nombre,impurmol,nwsim,natom,nhe4,namol,xwalker,ewalker,raenmol)
     write(6,'("energia final de las configuraciones",t40,f20.10)') emed
     write(6,*) 'numero de walkers que tengo finales',nwsim
     write(6,*) 'numero de walkers de partida en la simulacion',nwalkers
   endif

   call deallocatewalker(w1)

   do iwalker=1,2*nwalkers
     call deallocatewalker(wsim(iwalker))
   enddo
   deallocate (wsim)

 end subroutine finwalkers

 !=============================================================================
 ! test_gpu_methods (opcion=5)
 !
 ! Punto de entrada para la verificacion GPU vs CPU.
 ! Vive en mmontecarlo para tener acceso directo a wsim y nwalkers.
 ! Los tests individuales estan en mtest_gpu.cuf.
 !
 ! Para activar un nuevo test cuando implementes el metodo:
 !   1. Escribe test_XXXX en mtest_gpu.cuf
 !   2. Descomenta la llamada correspondiente aqui
 !=============================================================================
 !=============================================================================
 ! init_gpu_dmc_modules
 ! Inicializa los modulos GPU y sube TODOS los datos de wsim al SOA
 ! una unica vez. A partir de aqui el SOA es la representacion primaria
 ! del estado de los walkers -- no se necesita subir nada mas por paso.
 !=============================================================================
 subroutine init_gpu_dmc_modules()
   use mrandom, only: sacasemilla
   real(kind=r8) :: aziz_params(8), dhcm
   integer(kind=i8) :: base_seed
   external :: sacabh

   call sacaaziz(aziz_params)
   dhcm = 0.0_r8;  if (opot == 4) call sacabh(dhcm)

   ! --- Inicializar parametros en device (escalaras, sin transferencia de datos) ---
   call derananum_gpu_init(nhe4, nhe3, ngatom, natom, nhe3up, nhe3dw, lxhe4, lxhe3, &
                            mhe4, mhe3, mx, phe4, phe3, pmix,                        &
                            pxhe4(1:5,0:lxhe4), pxhe3(1:5,0:lxhe3),                  &
                            impureza, impurmol, impurfija, rotamol)
   call vpot_gpu_init(opot, ngatom, natom, impureza, impurmol, dhcm, aziz_params)
   call dmc2_gpu_init(ncmtras, rotamol, etrial, dtau, ratio)

   ! --- Reservar SOA para 2*nwalkers walkers ---
   call derananum_gpu_alloc(2*nwalkers, natom)
   call vpot_gpu_alloc(2*nwalkers, natom)
   call hpsi_gpu_alloc_ene(2*nwalkers)
   call dmc2_gpu_alloc(2*nwalkers, natom)

   ! --- Inicializar componentes allocatables de wsim para slots de replicacion ---
   ! iniwalkers solo aloca wsim(1..nwalkers). Las posiciones nwalkers+1..2*nwalkers
   ! existen en el array pero sus campos atom/dwf/delta etc. NO estan allocados.
   ! soa_to_aos_dmc_result escribe en wsim(iw)%atom cuando iw > nwalkers
   ! (walkers replicados), lo que causaria segfault. Se alocan aqui.
   block
     integer(kind=i4) :: iw_extra
     do iw_extra = nwalkers+1, 2*nwalkers
       if (.not. allocated(wsim(iw_extra)%atom)) &
         call allocatewalker(wsim(iw_extra), natom)
     end do
   end block

   ! --- TRANSFERENCIA UNICA: todos los campos de wsim al SOA ---
   call aos_to_soa_da(wsim, nwalkers, natom)
   call aos_to_soa_d2(wsim, nwalkers, natom)
   call aos_to_soa_vp(wsim, nwalkers, natom)
   call hpsi_gpu_run(nwalkers, libre)

   if (soydire) then
     block
       real(r8) :: h_wfhe4, h_wfhe3, h_wfm, h_wfx, h_wf, h_kin, h_pot, h_ene
       h_wfhe4 = d_wfhe4_soa_da(1);  h_wfhe3 = d_wfhe3_soa_da(1)
       h_wfm   = d_wfm_soa_da(1);    h_wfx   = d_wfx_soa_da(1)
       h_wf    = d_wf_soa_da(1);     h_kin   = d_kin_soa_da(1)
       h_pot   = d_pot_vp(1);        h_ene   = d_ene_hpsi(1)
       write(6,'(/,a)') ' DIAG GPU walker 1 (mderananum_gpu.cuf):'
       write(6,'(a,es20.10)') '   wfhe4  = ', h_wfhe4
       write(6,'(a,es20.10)') '   wfhe3  = ', h_wfhe3
       write(6,'(a,es20.10)') '   wfm    = ', h_wfm
       write(6,'(a,es20.10)') '   wfx    = ', h_wfx
       write(6,'(a,es20.10)') '   wf     = ', h_wf
       write(6,'(a,es20.10)') '   ekin   = ', h_kin
       write(6,'(a,es20.10)') '   epot   = ', h_pot
       write(6,'(a,es20.10)') '   etotal = ', h_ene
     end block
   end if

   call sacasemilla(base_seed)
   call gauss3_gpu_init_seeds(base_seed, 2*nwalkers)

 end subroutine init_gpu_dmc_modules

 !=============================================================================
 ! pasodmc_gpu -- SOA PERSISTENTE
 !
 ! El SOA ya esta en GPU desde el paso anterior (o desde init).
 ! Por paso solo se transfieren:
 !   D2H: nsons(nwpaso)         ~ 20 KB para 5000 walkers
 !   H2D: new_index(nwfin)      ~ 20 KB para 5000 walkers
 ! Los datos de los walkers NUNCA bajan/suben por paso.
 !
 ! Branching:
 !   CPU calcula new_index[1..nwfin] = indice origen en el SOA viejo
 !   GPU scatter_soa_kernel reorganiza el SOA en base a ese indice
 !=============================================================================
 subroutine pasodmc_gpu(nwpaso, egrow)
   integer(kind=i4), intent(inout) :: nwpaso
   real(kind=r8),    intent(out)   :: egrow
   integer(kind=i4), save :: ivez   = 0
   real(kind=r8),    save :: segrow = 0.0_r8
   integer(kind=i4), allocatable :: h_nsons(:)
   integer(kind=i4) :: nwfin, nwrep, iwalker, isons
   real(kind=r8)    :: nwnew, nwold

   allocate(h_nsons(nwpaso))

   ! 1. GPU: paso DMC completo
   call dmc2_gpu_run(nwpaso, libre)

   ! 2. D2H nsons (tiny) + estado actual de walkers
   h_nsons(1:nwpaso) = d_nsons_d2(1:nwpaso)
   call soa_to_aos_dmc_result(wsim, nwpaso, natom)  ! descarga nwpaso walkers al CPU

   ! 3. CPU branching: reordenacion exacta del pasodmc original.
   ! Evita la race condition del scatter GPU in-place (cuando nsons=0
   ! compacta posiciones y genera escrituras/lecturas simultaneas al mismo
   ! slot del SOA desde distintos warps sin sincronizacion entre bloques).
   nwfin = 0;  nwrep = 0
   do iwalker = 1, nwpaso
     if (h_nsons(iwalker) > 0) then
       nwfin = nwfin + 1
       ! Guard: evitar self-assignment (nwfin==iwalker) que libera y
       ! luego lee el mismo puntero en copiawalker -> use-after-free
       if (nwfin /= iwalker) call copiawalker(wsim(nwfin), wsim(iwalker))
       do isons = 2, h_nsons(iwalker)
         nwrep = nwrep + 1
         if (nwpaso + nwrep <= 2*nwalkers) call copiawalker(wsim(nwpaso+nwrep), wsim(iwalker))
       end do
     end if
   end do
   do iwalker = 1, nwrep
     if (nwfin + 1 > 2*nwalkers) exit
     if (nwpaso + iwalker > 2*nwalkers) exit   ! igual que pasodmc original
     nwfin = nwfin + 1
     if (nwfin /= nwpaso + iwalker) call copiawalker(wsim(nwfin), wsim(nwpaso+iwalker))
   end do

   ! Colapso de poblacion: todos los walkers murieron (nwfin==0).
   ! Ocurre cuando la configuracion inicial es mala (E_L >> etrial) y el
   ! walker muere por branching. Se rescata 1 walker del paso anterior para
   ! evitar el crash en allocate(h_nsons(0)) del siguiente paso.
   ! En produccion esto no debe ocurrir si etrial y el conf inicial son correctos.
   if (nwfin == 0) then
     write(6,'("AVISO pasodmc_gpu: todos los walkers murieron (nwpaso=",i6,"). Rescatando 1.")') nwpaso
     nwfin = 1
   end if

   ! 4. H2D: subir la nueva poblacion reorganizada al SOA GPU
   call aos_to_soa_da(wsim, nwfin, natom)
   call aos_to_soa_vp(wsim, nwfin, natom)
   call aos_to_soa_d2(wsim, nwfin, natom)

   ! 5. Recompute hpsi para actualizar d_ene_hpsi con las posiciones reales.
   ! Sin esto, save_state_kernel del siguiente paso lee eold incorrecto
   ! (del walker que estaba en esa posicion antes del branching), lo que
   ! produce gb incorrecto y explosion de la poblacion.
   call hpsi_gpu_run(nwfin, libre)

   ! 5. Actualizar egrow y etrial
   nwnew = nwfin;  nwold = nwpaso
   deallocate(h_nsons)
   egrow = etrial - log(nwnew/nwold)/dtau
   ivez   = ivez + 1;  segrow = segrow + egrow
   if (ivez == ncetrial) then
     etrial = 0.50_r8*(etrial + segrow/ncetrial)
     ivez = 0;  segrow = 0.0_r8
   end if
   nwpaso = nwfin

 end subroutine pasodmc_gpu

 subroutine dmc_gpu
   real(kind=r8) :: egrow
   integer(kind=i4) :: iblock, ipaso, nwpaso
   integer(kind=i4) :: dmcnvalblo, dmcnvaltot
   integer(kind=i4) :: ndens1, nhis1, ndens2, nhis2
   integer(kind=i4) :: npol, ndt, ndifus, npasosblo
   logical :: equilbr

   call iniimagina(nombre, natom, dtau, hb2x, brot)
   call dmcnumprop(dmcnvalblo, dmcnvaltot)
   call densgethis(ndens1, nhis1, ndens2, nhis2)
   call difusgethis(npol, ndt)

   nwpaso = nwalkers;  equilbr = .true.
   npasosblo = 0.2*npasos;  ndifus = min(ndt, npasosblo)
   if (soydire) call dmcescrini(equilbr)

   call init_gpu_dmc_modules()   ! inicializacion GPU una sola vez

   call dmcceroini;  call densceroini;  call difusceroini
   do iblock = 1, nblockeq + nblock
     if (iblock == nblockeq+1) then
       equilbr = .false.;  npasosblo = npasos;  ndifus = min(ndt, npasosblo)
       if (soydire) call dmcescrini(equilbr)
       call dmcceroini
       call densceroini
       call difusceroini
     end if
     call dmcceroblo;  call densceroblo;  call difusceroblo
     call difusfijaorigen(nwpaso, wsim)
     do ipaso = 1, npasosblo
       call pasodmc_gpu(nwpaso, egrow)
       call dmcsumapaso(nwpaso, egrow, wsim)
       call denssumapaso(nwpaso, wsim)
       if (ipaso <= ndifus) call difussumapaso(ipaso, nwpaso, wsim)
     end do
     call dmcsumablo;  call denssumablo;  call difussumablo(ndifus)
     call dmcescrblopar(dmcnvalblo)
   end do

   call dmcsumaproc(dmcnvaltot)
   call denssumaproc(ndens1, nhis1, ndens2, nhis2)
   call difussumaproc(npol, ndifus)
   if (soydire) then
     call dmcsumafin
     call dmcescrfin(dtau, cmtok, k2mev_bh, opot)
     call denssumafin;  call densescrfin
     call difusfin(ndifus)
   end if

   ! nwsim is already set to nwalkers by iniwalkers and must stay that way:
   ! finwalkers allocates xwalker(3*natom*nwalkers) and iterates do iwalker=1,nwsim,
   ! so setting nwsim > nwalkers causes a buffer overflow. CPU dmc never changes nwsim.
 end subroutine dmc_gpu

 subroutine test_gpu_methods

   if (soydire) then
     write(6,'(//,a)') ' ============================================='
     write(6,'(a)')    ' VERIFICACION GPU vs CPU  (opcion=5)'
     write(6,'(a,/)')  ' ============================================='

     call test_derwavefm(wsim, nwalkers)
     call test_wavefm(wsim, nwalkers)
     call test_wavefhe4(wsim, nwalkers)
     call test_derwavefhe4(wsim, nwalkers)
     call test_wavefhe3(wsim, nwalkers)
     call test_wavefx(wsim, nwalkers)
     call test_wavef(wsim, nwalkers)
     call test_derwavefhe3(wsim, nwalkers)
     call test_derwavefx(wsim, nwalkers)
     call test_derananum(wsim, nwalkers)
     call test_dmc2_fixed_gauss(wsim, nwalkers)
     call test_dmc2_1walker(wsim, nwalkers)
     call test_gauss3_rns(wsim, nwalkers)
     call test_debug_rechazos(wsim, nwalkers)
     call test_lcg_internos(wsim, nwalkers)
     call test_rng_paso(wsim, nwalkers)
     call test_wftest_distribucion(wsim, nwalkers)
     call test_gauss3(wsim, nwalkers)
     call test_rota(wsim, nwalkers)
     call test_hpsi(wsim, nwalkers)
     call test_dmc2(wsim, nwalkers)
     call test_valibre(wsim, nwalkers)
     call test_vpot(wsim, nwalkers)
     call test_ccuerpo(wsim, nwalkers)
     call test_potenbh(wsim, nwalkers)
     call test_hedihydrogen(wsim, nwalkers)
     call test_bhutils(wsim, nwalkers)

     write(6,'(/,a,/)') ' Fin verificacion GPU.'
   end if

   nwsim = nwalkers
 end subroutine test_gpu_methods

end module mmontecarlo
