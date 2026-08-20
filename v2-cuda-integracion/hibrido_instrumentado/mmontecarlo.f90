module mmontecarlo

 use mparametros
 use mconfiguraciones
 use mtipos
 use msteps
 use mdmc2_pipeline, only: resetea_histogramas_gpu, vuelca_histogramas_gpu
 use mwavef
 use msistref
 use mkp_heco
 use mdensidades
 use mimagina
 use mmcvpromedia
 use mdmcpromedia
 use mrandom
 use mparalelo
 use mtiempos, only: i8t, tiempos_tic, tiempos_toc, tiempos_reset, &
&                     tiempos_escribe4, tiempos_escribe5, t_total4, t_total5, &
&                     tiempos_escribe7, t_total7, t_dmcsumapaso, t_denssumapaso, t_difussumapaso

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
  integer(kind=i8t) :: tt0run

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
   call tiempos_reset
   call tiempos_tic(tt0run)
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
   t_total4=t_total4+tiempos_toc(tt0run)
   call tiempos_escribe4('tiempos_opcion4.dat')

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

! ---- dmc_gpu: mismo esqueleto exacto que dmc, con pasodmc sustituido
! por pasodmc_gpu (msteps.f90) -- ver docs-kernels/hibrido.md Paso 5.
! dmc original (arriba) no se toca.
 subroutine dmc_gpu
  real(kind=r8) :: egrow
  integer(kind=i4) :: iblock,ipaso
  integer(kind=i4) :: nwpaso
  integer(kind=i4) :: dmcnvalblo,dmcnvaltot
  integer(kind=i4) :: ndens1,nhis1,ndens2,nhis2
  integer(kind=i4) :: npol,ndt
  integer(kind=i4) :: ndifus,npasosblo
  logical :: equilbr
  integer(kind=i8t) :: tt0run

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
   call tiempos_reset
   call tiempos_tic(tt0run)
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
       call pasodmc_gpu(nwpaso,egrow,wsim)
       call dmcsumapaso(nwpaso,egrow,wsim)
       call denssumapaso(nwpaso,wsim)
       if(ipaso.le.ndifus) call difussumapaso(ipaso,nwpaso,wsim)
     enddo
     call dmcsumablo
     call denssumablo
     call difussumablo(ndifus)
     call dmcescrblopar(dmcnvalblo)
   enddo
   t_total5=t_total5+tiempos_toc(tt0run)
   call tiempos_escribe5('tiempos_opcion5.dat')

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

 end subroutine dmc_gpu

! ---- dmc_gpu_pipeline (opcion=7): mismo esqueleto exacto que dmc_gpu,
! con pasodmc_gpu sustituido por pasodmc_gpu_pipeline (msteps.f90,
! Opcion 1 de arquitectura-streams-kin-pot.md Parte 12-13). dmc_gpu
! (arriba) no se toca.
 subroutine dmc_gpu_pipeline
  real(kind=r8) :: egrow
  integer(kind=i4) :: iblock,ipaso
  integer(kind=i4) :: nwpaso
  integer(kind=i4) :: dmcnvalblo,dmcnvaltot
  integer(kind=i4) :: ndens1,nhis1,ndens2,nhis2
  integer(kind=i4) :: npol,ndt
  integer(kind=i4) :: ndifus,npasosblo
  logical :: equilbr
  integer(kind=i8t) :: tt0run, tt0
  real(kind=r8) :: denb_local

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
   call tiempos_reset
   call tiempos_tic(tt0run)
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
     call resetea_histogramas_gpu
     denb_local=0.0_r8
     call difusceroblo
     call difusfijaorigen(nwpaso,wsim)
     do ipaso=1,npasosblo
       call pasodmc_gpu_pipeline(nwpaso,egrow,wsim)
       call tiempos_tic(tt0)
       call dmcsumapaso(nwpaso,egrow,wsim)
       t_dmcsumapaso=t_dmcsumapaso+tiempos_toc(tt0)
       ! denssumapaso (CPU) sustituida por la Fase H del pipeline (GPU,
       ! dentro del mismo grafo que pasodmc_gpu_pipeline ya lanzo arriba
       ! -- ver dmc2_pipeline.cuf, k_fase_h). Solo queda llevar la
       ! cuenta de walkers procesados (denb), que denssumapaso hacia
       ! sobre la marcha.
       denb_local=denb_local+real(nwpaso,r8)
       if(ipaso.le.ndifus) then
         call tiempos_tic(tt0)
         call difussumapaso(ipaso,nwpaso,wsim)
         t_difussumapaso=t_difussumapaso+tiempos_toc(tt0)
       endif
     enddo
     call tiempos_tic(tt0)
     call vuelca_histogramas_gpu
     call densputdenb(denb_local)
     t_denssumapaso=t_denssumapaso+tiempos_toc(tt0)
     call dmcsumablo
     call denssumablo
     call difussumablo(ndifus)
     call dmcescrblopar(dmcnvalblo)
   enddo
   t_total7=t_total7+tiempos_toc(tt0run)
   write(*,'(a,f12.4,a)') ' tiempo total opcion7 (pipeline): ', t_total7, ' s'
   call tiempos_escribe7('tiempos_opcion7.dat')

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

 end subroutine dmc_gpu_pipeline

! ---- dmc_cpu_gpurand: prueba de control (opcion=6, ver
! docs-kernels/hibrido.md), mismo esqueleto que dmc/dmc_gpu, llamando
! a pasodmc_cpu_gpurand -- walkers secuenciales en host, con las
! MISMAS semillas independientes por walker que usa dmc_gpu. Sirve
! para comprobar, de forma equitativa, si la UNICA diferencia real
! entre dmc y dmc_gpu es el reparto de aleatoriedad (esperado, ver
! mrandom.md) y no algo de la paralelizacion en si.
 subroutine dmc_cpu_gpurand
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
       call pasodmc_cpu_gpurand(nwpaso,egrow,wsim)
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

 end subroutine dmc_cpu_gpurand

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
!    write(6,*) 'wf',w1%lw%wf
!    write(6,*) 'wf he4',w1%lw%wfhe4
!    write(6,*) 'wf he3',w1%lw%wfhe3
!    write(6,*) 'wf mix',w1%lw%wfm
!    write(6,*) 'wf imp',w1%lw%wfx
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

end module mmontecarlo
