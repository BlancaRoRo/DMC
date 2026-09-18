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

  ! ---- v3-cuda-optimizacion/tiempos-metodos-dmc: cronometraje de CADA
  ! metodo llamado desde dmc, para repetir (con el pipeline actual) el
  ! analisis original de la memoria del TFG (04b_AnalisisImplementacionCUDA.tex,
  ! "pasodmc concentra mas del 95% del tiempo total"). system_clock
  ! puro, sin depender de ningun modulo compartido -- instrumentacion
  ! solo de esta copia, no toca la referencia gfortran validada
  ! (../../../v2-cuda-integracion/cpu-original-gfortran/). ----
  integer(kind=8) :: c0,c1,tasa_reloj
  real(kind=r8) :: t_iniimagina=0, t_dmcnumprop=0, t_densgethis=0, t_difusgethis=0
  real(kind=r8) :: t_dmcescrini=0, t_dmcceroini=0, t_densceroini=0, t_difusceroini=0
  real(kind=r8) :: t_dmcceroblo=0, t_densceroblo=0, t_difusceroblo=0, t_difusfijaorigen=0
  real(kind=r8) :: t_pasodmc=0, t_dmcsumapaso=0, t_denssumapaso=0, t_difussumapaso=0
  real(kind=r8) :: t_dmcsumablo=0, t_denssumablo=0, t_difussumablo=0, t_dmcescrblopar=0
  real(kind=r8) :: t_dmcsumaproc=0, t_denssumaproc=0, t_difussumaproc=0
  real(kind=r8) :: t_dmcsumafin=0, t_dmcescrfin=0, t_denssumafin=0, t_densescrfin=0, t_difusfin=0
  real(kind=r8) :: t_total_dmc
  integer(kind=4) :: uverif

   call system_clock(count_rate=tasa_reloj)
   call system_clock(c0)

   call iniimagina(nombre,natom,dtau,hb2x,brot)
   call system_clock(c1); t_iniimagina=t_iniimagina+real(c1-c0,r8)/tasa_reloj; c0=c1

   call dmcnumprop(dmcnvalblo,dmcnvaltot)
   call system_clock(c1); t_dmcnumprop=t_dmcnumprop+real(c1-c0,r8)/tasa_reloj; c0=c1
   call densgethis(ndens1,nhis1,ndens2,nhis2)
   call system_clock(c1); t_densgethis=t_densgethis+real(c1-c0,r8)/tasa_reloj; c0=c1
   call difusgethis(npol,ndt)
   call system_clock(c1); t_difusgethis=t_difusgethis+real(c1-c0,r8)/tasa_reloj; c0=c1
   ndifus=min(ndt,npasos)

   nwpaso=nwalkers

   equilbr=.true.
   npasosblo=0.2*npasos
   ndifus=min(ndt,npasosblo)
   if(soydire) call dmcescrini(equilbr)
   call system_clock(c1); t_dmcescrini=t_dmcescrini+real(c1-c0,r8)/tasa_reloj; c0=c1

   call dmcceroini
   call system_clock(c1); t_dmcceroini=t_dmcceroini+real(c1-c0,r8)/tasa_reloj; c0=c1
   call densceroini
   call system_clock(c1); t_densceroini=t_densceroini+real(c1-c0,r8)/tasa_reloj; c0=c1
   call difusceroini
   call system_clock(c1); t_difusceroini=t_difusceroini+real(c1-c0,r8)/tasa_reloj; c0=c1
   do iblock=1,nblockeq+nblock
     if(iblock.eq.nblockeq+1) then
       equilbr=.false.
       npasosblo=npasos
       ndifus=min(ndt,npasosblo)
       if(soydire) call dmcescrini(equilbr)
       call system_clock(c1); t_dmcescrini=t_dmcescrini+real(c1-c0,r8)/tasa_reloj; c0=c1
       call dmcceroini
       call system_clock(c1); t_dmcceroini=t_dmcceroini+real(c1-c0,r8)/tasa_reloj; c0=c1
       call densceroini
       call system_clock(c1); t_densceroini=t_densceroini+real(c1-c0,r8)/tasa_reloj; c0=c1
       call difusceroini
       call system_clock(c1); t_difusceroini=t_difusceroini+real(c1-c0,r8)/tasa_reloj; c0=c1
     endif
     call dmcceroblo
     call system_clock(c1); t_dmcceroblo=t_dmcceroblo+real(c1-c0,r8)/tasa_reloj; c0=c1
     call densceroblo
     call system_clock(c1); t_densceroblo=t_densceroblo+real(c1-c0,r8)/tasa_reloj; c0=c1
     call difusceroblo
     call system_clock(c1); t_difusceroblo=t_difusceroblo+real(c1-c0,r8)/tasa_reloj; c0=c1
     call difusfijaorigen(nwpaso,wsim)
     call system_clock(c1); t_difusfijaorigen=t_difusfijaorigen+real(c1-c0,r8)/tasa_reloj; c0=c1
     do ipaso=1,npasosblo
       call pasodmc(nwpaso,egrow,wsim)
       call system_clock(c1); t_pasodmc=t_pasodmc+real(c1-c0,r8)/tasa_reloj; c0=c1
       call dmcsumapaso(nwpaso,egrow,wsim)
       call system_clock(c1); t_dmcsumapaso=t_dmcsumapaso+real(c1-c0,r8)/tasa_reloj; c0=c1
       call denssumapaso(nwpaso,wsim)
       call system_clock(c1); t_denssumapaso=t_denssumapaso+real(c1-c0,r8)/tasa_reloj; c0=c1
       if(ipaso.le.ndifus) call difussumapaso(ipaso,nwpaso,wsim)
       call system_clock(c1); t_difussumapaso=t_difussumapaso+real(c1-c0,r8)/tasa_reloj; c0=c1
     enddo
     call dmcsumablo
     call system_clock(c1); t_dmcsumablo=t_dmcsumablo+real(c1-c0,r8)/tasa_reloj; c0=c1
     call denssumablo
     call system_clock(c1); t_denssumablo=t_denssumablo+real(c1-c0,r8)/tasa_reloj; c0=c1
     call difussumablo(ndifus)
     call system_clock(c1); t_difussumablo=t_difussumablo+real(c1-c0,r8)/tasa_reloj; c0=c1
     call dmcescrblopar(dmcnvalblo)
     call system_clock(c1); t_dmcescrblopar=t_dmcescrblopar+real(c1-c0,r8)/tasa_reloj; c0=c1
   enddo

   call dmcsumaproc(dmcnvaltot)
   call system_clock(c1); t_dmcsumaproc=t_dmcsumaproc+real(c1-c0,r8)/tasa_reloj; c0=c1
   call denssumaproc(ndens1,nhis1,ndens2,nhis2)
   call system_clock(c1); t_denssumaproc=t_denssumaproc+real(c1-c0,r8)/tasa_reloj; c0=c1
   call difussumaproc(npol,ndifus)
   call system_clock(c1); t_difussumaproc=t_difussumaproc+real(c1-c0,r8)/tasa_reloj; c0=c1

   if(soydire) then
     call dmcsumafin
     call system_clock(c1); t_dmcsumafin=t_dmcsumafin+real(c1-c0,r8)/tasa_reloj; c0=c1
     call dmcescrfin(dtau,cmtok,k2mev_bh,opot)
     call system_clock(c1); t_dmcescrfin=t_dmcescrfin+real(c1-c0,r8)/tasa_reloj; c0=c1
     call denssumafin
     call system_clock(c1); t_denssumafin=t_denssumafin+real(c1-c0,r8)/tasa_reloj; c0=c1
     call densescrfin
     call system_clock(c1); t_densescrfin=t_densescrfin+real(c1-c0,r8)/tasa_reloj; c0=c1
     call difusfin(ndifus)
     call system_clock(c1); t_difusfin=t_difusfin+real(c1-c0,r8)/tasa_reloj; c0=c1
   endif

   t_total_dmc = t_iniimagina+t_dmcnumprop+t_densgethis+t_difusgethis+t_dmcescrini+ &
     t_dmcceroini+t_densceroini+t_difusceroini+t_dmcceroblo+t_densceroblo+t_difusceroblo+ &
     t_difusfijaorigen+t_pasodmc+t_dmcsumapaso+t_denssumapaso+t_difussumapaso+ &
     t_dmcsumablo+t_denssumablo+t_difussumablo+t_dmcescrblopar+t_dmcsumaproc+ &
     t_denssumaproc+t_difussumaproc+t_dmcsumafin+t_dmcescrfin+t_denssumafin+ &
     t_densescrfin+t_difusfin

   open(newunit=uverif, file='tiempos_metodos_dmc.dat', status='replace')
   write(uverif,'(a,f14.4,a)') 'tiempo total instrumentado (suma de metodos), s = ', t_total_dmc
   write(uverif,'(a)') ''
   write(uverif,'(a,f12.4,a,f7.3,a)') 'iniimagina        ', t_iniimagina,    ' s  (', 100*t_iniimagina/t_total_dmc,    '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'dmcnumprop        ', t_dmcnumprop,    ' s  (', 100*t_dmcnumprop/t_total_dmc,    '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'densgethis        ', t_densgethis,    ' s  (', 100*t_densgethis/t_total_dmc,    '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'difusgethis       ', t_difusgethis,   ' s  (', 100*t_difusgethis/t_total_dmc,   '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'dmcescrini        ', t_dmcescrini,    ' s  (', 100*t_dmcescrini/t_total_dmc,    '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'dmcceroini        ', t_dmcceroini,    ' s  (', 100*t_dmcceroini/t_total_dmc,    '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'densceroini       ', t_densceroini,   ' s  (', 100*t_densceroini/t_total_dmc,   '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'difusceroini      ', t_difusceroini,  ' s  (', 100*t_difusceroini/t_total_dmc,  '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'dmcceroblo        ', t_dmcceroblo,    ' s  (', 100*t_dmcceroblo/t_total_dmc,    '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'densceroblo       ', t_densceroblo,   ' s  (', 100*t_densceroblo/t_total_dmc,   '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'difusceroblo      ', t_difusceroblo,  ' s  (', 100*t_difusceroblo/t_total_dmc,  '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'difusfijaorigen   ', t_difusfijaorigen,' s  (', 100*t_difusfijaorigen/t_total_dmc,'%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'pasodmc           ', t_pasodmc,       ' s  (', 100*t_pasodmc/t_total_dmc,       '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'dmcsumapaso       ', t_dmcsumapaso,   ' s  (', 100*t_dmcsumapaso/t_total_dmc,   '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'denssumapaso      ', t_denssumapaso,  ' s  (', 100*t_denssumapaso/t_total_dmc,  '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'difussumapaso     ', t_difussumapaso, ' s  (', 100*t_difussumapaso/t_total_dmc, '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'dmcsumablo        ', t_dmcsumablo,    ' s  (', 100*t_dmcsumablo/t_total_dmc,    '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'denssumablo       ', t_denssumablo,   ' s  (', 100*t_denssumablo/t_total_dmc,   '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'difussumablo      ', t_difussumablo,  ' s  (', 100*t_difussumablo/t_total_dmc,  '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'dmcescrblopar     ', t_dmcescrblopar, ' s  (', 100*t_dmcescrblopar/t_total_dmc, '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'dmcsumaproc       ', t_dmcsumaproc,   ' s  (', 100*t_dmcsumaproc/t_total_dmc,   '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'denssumaproc      ', t_denssumaproc,  ' s  (', 100*t_denssumaproc/t_total_dmc,  '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'difussumaproc     ', t_difussumaproc, ' s  (', 100*t_difussumaproc/t_total_dmc, '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'dmcsumafin        ', t_dmcsumafin,    ' s  (', 100*t_dmcsumafin/t_total_dmc,    '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'dmcescrfin        ', t_dmcescrfin,    ' s  (', 100*t_dmcescrfin/t_total_dmc,    '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'denssumafin       ', t_denssumafin,   ' s  (', 100*t_denssumafin/t_total_dmc,   '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'densescrfin       ', t_densescrfin,   ' s  (', 100*t_densescrfin/t_total_dmc,   '%)'
   write(uverif,'(a,f12.4,a,f7.3,a)') 'difusfin          ', t_difusfin,      ' s  (', 100*t_difusfin/t_total_dmc,      '%)'
   close(uverif)

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
