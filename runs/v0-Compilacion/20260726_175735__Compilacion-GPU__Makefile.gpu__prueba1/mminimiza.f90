module mminimiza

 use mparametros 
 use mmontecarlo
 use mentradatos
 use mparalelo

 implicit none
  integer, private, parameter :: i4=selected_int_kind(9)
  integer, private, parameter :: i8=selected_int_kind(15)
  integer, private, parameter :: r8=selected_real_kind(15,9)

  real(kind=r8), private, parameter :: ftol=1.d-4
  real(kind=r8), private, parameter :: rincs=0.25_r8

  integer (kind=i4), private, parameter :: nmax=60
  logical, private, save :: soydire
  logical, private, save :: inimcv
  real(kind=r8), private, save :: neffmin

contains

 subroutine calmin
  real(kind=r8) :: pmin(nmax),dpmin(nmax)
  real(kind=r8) :: fmin
  real(kind=r8) :: emcv(2),emcv2(2)
  integer(kind=i4) :: ndim
  integer(kind=i4) :: iter
  integer(kind=i4) :: ncpar
  logical :: empieza

   empieza=.true.

   call quiensoy(soydire)

   if(soydire) then
     write(6,'("-----------------------------------------------------------------")')
     write(6,'(t15,"Optimizacion de la funcion de onda")')
     if(opcion.eq.2) then
        if(enermin) then
           write(6,'(t15,"Minimiza con Metropolis la energia")')
        else
           write(6,'(t15,"Minimiza con Metropolis la varianza")')
        endif
     else
        write(6,'(t15,"Minimiza con correlated sampling la energia")')
        write(6,'(t15,"calculo inicial MCV metropolis")')
     endif
     write(6,'("-----------------------------------------------------------------")')
   endif

   call setparam(ndim,pmin,dpmin)

   if(soydire) then
     write(6,'("numero de parametros libres",t30,i10)') ndim
     open(30,file="minpar."//trim(nombre),status="unknown")
     if(opcion.eq.2) then
       if(enermin) then
          write(30,'(t20,"Minimiza con Metropolis la energia")')
       else
          write(30,'(t20,"Minimiza con Metropolis a la varianza")')
       endif
     else
       write(30,'(t20,"Minimiza con correlated sampling la energia")')
     endif
   endif

   if(opcion.eq.3) then
     call cuantosparalelos(ncpar)
     neffmin=rincs*(ncpar*nwalkers)
     call mcv(emcv2)
     inimcv=.true.
     call corrsamp(inimcv,emcv)
     inimcv=.false.
     if(soydire)  then
       write(30,'(t20,"poblacion efectiva minima",t50,f10.3)') neffmin
       write(6,'("Coeficiente poblacion efectiva minima",t40,f10.5)')rincs
       write(6,'("Poblacion correlated sampling",t40,i10)') ncpar*nwalkers
       write(6,'("correlated sampling inicial")') 
       write(6,'("Metrop MCV correlated sampling",t40,f16.8,f12.6)')emcv2
       write(6,'("Energia correlated sampling",t40,f16.8)')emcv(1)
       write(6,'("Poblacion efectiva correlated sampling",t40,f10.3)')emcv(2)
       write(6,'("Poblacion efectiva minima",t40,f10.3)') neffmin
     endif
   endif

   call simplex(ndim,pmin,dpmin,iter)

   if(soydire) then
     write(6,'("numero de iteraciones hasta el minimo",t40,i10)') iter
     write(6,'("tolerancia hasta el minimo",t40,f10.7)') ftol
     write(30,'(t30,"Iteracion final")')
   endif

   call calfun(ndim,pmin,fmin)


   empieza=.false.
   if(soydire) call escribein(empieza)

   if(soydire) close(30)

 end subroutine calmin

 subroutine calfun(ndim,pval,fx)
  integer(kind=i4), intent (in) :: ndim
  real(kind=r8), intent (inout) :: pval(ndim)
  real(kind=r8), intent (out) :: fx
  real(kind=r8) :: emcv(2),emcv2(2)
  integer(kind=i4), save :: ivez=0
  integer(kind=i4) :: il

   if(soydire) write(6,'(//)')

   pval=abs(pval)

   call getparam(ndim,pval)

   phe4(1)=0.50_r8*(bhe4**nuhe4)
   phe4(2)=nuhe4
   phe4(3)=alfahe4
   phe3(1)=0.50_r8*(bhe3**nuhe3)
   phe3(2)=nuhe3
   phe3(3)=alfahe3
   phe3(4)=bback
   pmix(1)=0.50_r8*(bmix**numix)
   pmix(2)=numix
   pmix(3)=alfamix
   if(namol.ne.0) then
     do il=0,lxhe4
       pxhe4(1,il)=0.50_r8*(bxhe4(il)**nuxhe4(il))
       pxhe4(2,il)=nuxhe4(il)
       pxhe4(3,il)=alfaxhe4(il)
       pxhe4(4,il)=p4xhe4(il)
       pxhe4(5,il)=p5xhe4(il)
     enddo
     do il=0,lxhe3
       pxhe3(1,il)=0.50_r8*(bxhe3(il)**nuxhe3(il))
       pxhe3(2,il)=nuxhe3(il)
       pxhe3(3,il)=alfaxhe3(il)
       pxhe3(4,il)=p4xhe3(il)
       pxhe3(5,il)=p5xhe3(il)
     enddo
   endif

   if(soydire)  then
     write(6,'("Parametros he4:    0.5*(b**nu),nu,alfa",t42,3f12.5)') phe4
     write(6,'("Parametros he3:    0.5*(b**nu),nu,alfa,bb",t42,4f12.5)') phe3
     write(6,'("Parametros mezcla: 0.5*(b**nu),nu,alfa",t42,4f12.5)') pmix
     if(namol.ne.0) then
       write(6,'("Parametros impureza he4: 0.5*(b**nu),nu,alfa,p4,p5")') 
       do il=0,lxhe4
         write(6,'("l=",i3,t21,5f12.5)') il,pxhe4(:,il)
       enddo
       write(6,'("Parametros impureza he3: 0.5*(b**nu),nu,alfa,p4,p5")') 
       do il=0,lxhe3
         write(6,'("l=",i3,t21,5f12.5)') il,pxhe3(:,il)
       enddo
     endif
   endif

   if(opcion.eq.2) then
     call mcv(emcv)
     if(enermin) then
       fx=emcv(1)
     else
       fx=emcv(2)
     endif
   else
     call corrsamp(inimcv,emcv)
     if(emcv(2).lt.neffmin) then
       if(soydire) then
         write(6,'(t10,"no valido correlated sampling")') 
         write(6,'("correlated sampling itermin",t40,i5)') ivez+1
         write(6,'("Poblacion efectiva correlated sampling",t50,f10.3)') emcv(2)
         write(6,'("Poblacion efectiva correlated sampling minima",t50,f10.3)') neffmin
         write(6,'("Energia correlated sampling",t40,f16.8)') emcv(1)
         write(6,'(t10,"se hace un calculo MCV metropolis")')
       endif
       call mcv(emcv2)
       inimcv=.true.
       call corrsamp(inimcv,emcv)
       inimcv=.false.
       if(soydire)  then
         write(6,'("Metrop MCV correlated sampling",t40,f16.8,f12.6)') emcv2
         write(6,'("Energia correlated sampling",t40,f16.8)') emcv(1)
         write(6,'("Poblacion efectiva correlated sampling",t40,f10.3)') emcv(2)
       endif
     endif
     fx=emcv(1)
   endif


   if(soydire)  then
     ivez=ivez+1
     write(6, '("itermin",t10,i5,2f15.8)')ivez,emcv
     write(30,'("parametros",t15,60f10.6)') pval
     write(30,'("itermin",t10,i5,2f15.8)')ivez,emcv
     write(30,*)
     call flush(30)
   endif
     
 end subroutine calfun

 subroutine setparam(ndim,pmin,dpmin)
  integer(kind=i4), intent (out) :: ndim
  real(kind=r8), intent (out) :: pmin(nmax),dpmin(nmax)
  integer(kind=i4) :: idim
  integer(kind=i4) :: il

   idim=0
   if(dbhe4.ne.0) then
     idim=idim+1
     pmin(idim)=bhe4
     dpmin(idim)=dbhe4
     if(soydire) write(6,'(t5,"se optimiza b he4",t35,f10.6)') bhe4
   endif
   if(dnuhe4.ne.0) then
     idim=idim+1
     pmin(idim)=nuhe4
     dpmin(idim)=dnuhe4
     if(soydire) write(6,'(t5,"se optimiza nu he4 he4",t35,f10.6)') nuhe4
   endif
   if(dalfahe4.ne.0) then
     idim=idim+1
     pmin(idim)=alfahe4
     dpmin(idim)=dalfahe4
     if(soydire) write(6,'(t5,"se optimiza alfa he4",t35,f10.6)') alfahe4
   endif
   if(dbhe3.ne.0) then
     idim=idim+1
     pmin(idim)=bhe3
     dpmin(idim)=dbhe3
     if(soydire) write(6,'(t5,"se optimiza b he3",t35,f10.6)') bhe3
   endif
   if(dnuhe3.ne.0) then
     idim=idim+1
     pmin(idim)=nuhe3
     dpmin(idim)=dnuhe3
     if(soydire) write(6,'(t5,"se optimiza nu he3 he3",t35,f10.6)') nuhe3
   endif
   if(dalfahe3.ne.0) then
     idim=idim+1
     pmin(idim)=alfahe3
     dpmin(idim)=dalfahe3
     if(soydire) write(6,'(t5,"se optimiza alfa he3",t35,f10.6)') alfahe3
   endif
   if(dbback.ne.0) then
     idim=idim+1
     pmin(idim)=bback
     dpmin(idim)=dbback
     if(soydire) write(6,'(t5,"se optimiza bb backflow",t35,f10.6)') bback
   endif
   if(dbmix.ne.0) then
     idim=idim+1
     pmin(idim)=bmix
     dpmin(idim)=dbmix
     if(soydire) write(6,'(t5,"se optimiza b mezclas",t35,f10.6)') bmix
   endif
   if(dnumix.ne.0) then
     idim=idim+1
     pmin(idim)=numix
     dpmin(idim)=dnumix
     if(soydire) write(6,'(t5,"se optimiza nu mezclas",t35,f10.6)') numix
   endif
   if(dalfamix.ne.0) then
     idim=idim+1
     pmin(idim)=alfamix
     dpmin(idim)=dalfamix
     if(soydire) write(6,'(t5,"se optimiza alfa mezclas",t35,f10.6)') alfamix
   endif
   if(impureza) then
     do il=0,lxhe4
       if(dbxhe4(il).ne.0) then
         idim=idim+1
         pmin(idim)=bxhe4(il)
         dpmin(idim)=dbxhe4(il)
         if(soydire)     &
  &      write(6,'(t5,"optimiza b impureza he4, il=",t45,i5,f10.6)') il,bxhe4(il)
       endif
       if(dnuxhe4(il).ne.0) then
         idim=idim+1
         pmin(idim)=nuxhe4(il)
         dpmin(idim)=dnuxhe4(il)
         if(soydire)     &
  &      write(6,'(t5,"se optimiza nu impureza he4, il=",t45,i5,f10.6)')il,nuxhe4(il)
       endif
       if(dalfaxhe4(il).ne.0) then
         idim=idim+1
         pmin(idim)=alfaxhe4(il)
         dpmin(idim)=dalfaxhe4(il)
         if(soydire)     &
  &      write(6,'(t5,"optimiza alfa impureza he4, il=",t45,i5,f10.6)') il,alfaxhe4(il)
       endif
       if(dp4xhe4(il).ne.0) then
         idim=idim+1
         pmin(idim)=p4xhe4(il)
         dpmin(idim)=dp4xhe4(il)
         if(soydire)     &
  &      write(6,'(t5,"se optimiza p4 impureza he4, il=",t45,i5,f10.6)')il,p4xhe4(il)
       endif
       if(dp5xhe4(il).ne.0) then
         idim=idim+1
         pmin(idim)=p5xhe4(il)
         dpmin(idim)=dp5xhe4(il)
         if(soydire)     &
  &      write(6,'(t5,"se optimiza p5 impureza he4, il=",t45,i5,f10.6)')il,p5xhe4(il)
       endif
     enddo
     do il=0,lxhe3
       if(dbxhe3(il).ne.0) then
         idim=idim+1
         pmin(idim)=bxhe3(il)
         dpmin(idim)=dbxhe3(il)
         if(soydire)     &
  &      write(6,'(t5,"optimiza b impureza he3, il=",t45,i5,f10.6)') il,bxhe3(il)
       endif
       if(dnuxhe3(il).ne.0) then
         idim=idim+1
         pmin(idim)=nuxhe3(il)
         dpmin(idim)=dnuxhe3(il)
         if(soydire)     &
  &      write(6,'(t5,"se optimiza nu impureza he3, il=",t45,i5,f10.6)')il,nuxhe3(il)
       endif
       if(dalfaxhe3(il).ne.0) then
         idim=idim+1
         pmin(idim)=alfaxhe3(il)
         dpmin(idim)=dalfaxhe3(il)
         if(soydire)     &
  &      write(6,'(t5,"optimiza alfa impureza he3, il=",t45,i5,f10.6)') il,alfaxhe3(il)
       endif
       if(dp4xhe3(il).ne.0) then
         idim=idim+1
         pmin(idim)=p4xhe3(il)
         dpmin(idim)=dp4xhe3(il)
         if(soydire)     &
  &      write(6,'(t5,"se optimiza p4 impureza he3, il=",t45,i5,f10.6)')il,p4xhe3(il)
       endif
       if(dp5xhe3(il).ne.0) then
         idim=idim+1
         pmin(idim)=p5xhe3(il)
         dpmin(idim)=dp5xhe3(il)
         if(soydire)     &
  &      write(6,'(t5,"se optimiza p5 impureza he3, il=",t45,i5,f10.6)')il,p5xhe3(il)
       endif
     enddo
   endif

   ndim=idim

 end subroutine setparam

 subroutine getparam(ndim,pmin)
  integer(kind=i4), intent (in) :: ndim
  real(kind=r8), intent (in) :: pmin(ndim)
  integer(kind=i4) :: idim
  integer(kind=i4) :: il

   idim=0
   if(dbhe4.ne.0) then
     idim=idim+1
     bhe4=pmin(idim)
   endif
   if(dnuhe4.ne.0) then
     idim=idim+1
     nuhe4=pmin(idim)
   endif
   if(dalfahe4.ne.0) then
     idim=idim+1
     alfahe4=pmin(idim)
   endif
   if(dbhe3.ne.0) then
     idim=idim+1
     bhe3=pmin(idim)
   endif
   if(dnuhe3.ne.0) then
     idim=idim+1
     nuhe3=pmin(idim)
   endif
   if(dalfahe3.ne.0) then
     idim=idim+1
     alfahe3=pmin(idim)
   endif
   if(dbback.ne.0) then
     idim=idim+1
     bback=pmin(idim)
   endif
   if(dbmix.ne.0) then
     idim=idim+1
     bmix=pmin(idim)
   endif
   if(dnumix.ne.0) then
     idim=idim+1
     numix=pmin(idim)
   endif
   if(dalfamix.ne.0) then
     idim=idim+1
     alfamix=pmin(idim)
   endif
   if(impureza) then
     do il=0,lxhe4
       if(dbxhe4(il).ne.0) then
         idim=idim+1
         bxhe4(il)=pmin(idim)
       endif
       if(dnuxhe4(il).ne.0) then
         idim=idim+1
         nuxhe4(il)=pmin(idim)
       endif
       if(dalfaxhe4(il).ne.0) then
         idim=idim+1
!        if(il.gt.0.and.pmin(idim).gt.1.0_r8) pmin(idim)=0.9+0.05*il
         alfaxhe4(il)=pmin(idim)
       endif
       if(dp4xhe4(il).ne.0) then
         idim=idim+1
         p4xhe4(il)=pmin(idim)
       endif
       if(dp5xhe4(il).ne.0) then
         idim=idim+1
         p5xhe4(il)=pmin(idim)
       endif
     enddo
     do il=0,lxhe3
       if(dbxhe3(il).ne.0) then
         idim=idim+1
         bxhe3(il)=pmin(idim)
       endif
       if(dnuxhe3(il).ne.0) then
         idim=idim+1
         nuxhe3(il)=pmin(idim)
       endif
       if(dalfaxhe3(il).ne.0) then
         idim=idim+1
!        if(il.gt.0.and.pmin(idim).gt.1.0_r8) pmin(idim)=0.9+0.05*il
         alfaxhe3(il)=pmin(idim)
       endif
       if(dp4xhe3(il).ne.0) then
         idim=idim+1
         p4xhe3(il)=pmin(idim)
       endif
       if(dp5xhe3(il).ne.0) then
         idim=idim+1
         p5xhe3(il)=pmin(idim)
       endif
     enddo
   endif


   if(soydire) then
     write(6,'("*****************************************************************")')
     write(6,'(t2,"Nueva Iteracion")') 
     write(6,'(t2,"Parametros en la iteracion")')
     write(6,'(t5,"b he4",t45,f10.6)') bhe4
     write(6,'(t5,"nu he4",t45,f10.6)') nuhe4
     write(6,'(t5,"alfa he4",t45,f10.6)') alfahe4
     write(6,'(t5,"b he3",t45,f10.6)') bhe3
     write(6,'(t5,"nu he3",t45,f10.6)') nuhe3
     write(6,'(t5,"alfa he3",t45,f10.6)') alfahe3
     write(6,'(t5,"bb backflow",t45,f10.6)') bback
     write(6,'(t5,"b mezclas",t45,f10.6)') bmix
     write(6,'(t5,"nu mezclas",t45,f10.6)') numix
     write(6,'(t5,"alfa mezclas",t45,f10.6)') alfamix
     if(impureza) then
       write(6,'("impureza-he4")')
       do il=0,lxhe4
         write(6,'(t5,"l=",i5,t15,"b he4",t45,f10.6)') il,bxhe4(il)
         write(6,'(t5,"l=",i5,t15,"nu he4",t45,f10.6)')il, nuxhe4(il)
         write(6,'(t5,"l=",i5,t15,"alfa he4",t45,f10.6)') il,alfaxhe4(il)
         write(6,'(t5,"l=",i5,t15,"p4 he4",t45,f10.6)') il,p4xhe4(il)
         write(6,'(t5,"l=",i5,t15,"p5 he4",t45,f10.6)') il,p5xhe4(il)
       enddo
       write(6,'("impureza-he3")')
       do il=0,lxhe3
         write(6,'(t5,"l=",i5,t15,"b he3",t45,f10.6)') il,bxhe3(il)
         write(6,'(t5,"l=",i5,t15,"nu he3",t45,f10.6)')il, nuxhe3(il)
         write(6,'(t5,"l=",i5,t15,"alfa he3",t45,f10.6)') il,alfaxhe3(il)
         write(6,'(t5,"l=",i5,t15,"p4 he3",t45,f10.6)') il,p4xhe3(il)
         write(6,'(t5,"l=",i5,t15,"p5 he3",t45,f10.6)') il,p5xhe3(il)
       enddo
     endif
   endif

 end subroutine getparam

   subroutine simplex(ndim,pmin,dpmin,iter)
    integer(kind=i4), intent (in) :: ndim
    real(kind=r8), intent (inout) :: pmin(ndim)
    real(kind=r8), intent (in) :: dpmin(ndim)
    integer(kind=i4), intent (out) :: iter
    real(kind=r8) ::  p(ndim+1,ndim),y(ndim+1)
    real(kind=r8) ::  aux(ndim)
    integer(kind=i4) :: idim,jdim

     do jdim=1,ndim+1
       do idim=1,ndim
         if(idim.eq.jdim) then
           p(jdim,idim)=pmin(idim)+dpmin(idim)
         else
           p(jdim,idim)=pmin(idim)
         endif
         aux(idim)=p(jdim,idim)
       enddo
       call calfun(ndim,aux,y(jdim))
     enddo
     call amoeba(ndim,p,y,iter)
     do idim=1,ndim
       pmin(idim)=p(1,idim)
     enddo
     if(soydire) write(6,*) 'valor minimo',y(1)
     iter=iter+ndim

   end subroutine simplex

  subroutine amoeba(ndim,p,y,iter)
   integer(kind=i4), intent (in) :: ndim
   real(kind=r8), intent (inout) :: p(ndim+1,ndim),y(ndim+1)
   integer(kind=i4), intent (out) :: iter
   real(kind=r8) :: psum(ndim)
   real(kind=r8) :: rtol,raux
   real(kind=r8) :: ytry,xfac
   integer(kind=i4) :: idim,jdim
   integer(kind=i4) :: ilo,ihi,inhi
   real(kind=r8), parameter :: eps=1.d-6
   integer(kind=i4), parameter :: itmax=300

    iter=0
    bucle_1: do
      do idim=1,ndim
        psum(idim)=0.0_r8
        do jdim=1,ndim+1
          psum(idim)=psum(idim)+p(jdim,idim)
        enddo
      enddo
      bucle_2: do
        ilo=1
        if(y(1).gt.y(2)) then
          ihi=1
          inhi=2
        else
          ihi=2
          inhi=1
        endif
        do idim=1,ndim+1
          if(y(idim).le.y(ilo)) ilo=idim
          if(y(idim).gt.y(ihi)) then
            inhi=ihi
            ihi=idim
          else
            if(y(idim).gt.y(inhi)) inhi=idim
          endif
        enddo
        rtol=2.0_r8*abs(y(ihi)-y(ilo))/(abs(y(ihi))+abs(y(ilo))+eps)

        if(rtol.lt.ftol) then
          raux=y(1)
          y(1)=y(ilo)
          y(ilo)=raux
          do idim=1,ndim
            raux=p(1,idim)
            p(1,idim)=p(ilo,idim)
            p(ilo,idim)=raux
          enddo
          if(soydire) then
            write(6,*)'se ha convergido en el simplex'
            write(6,*)'tolerancia y cota tolerancia',rtol,ftol
            write(6,*)'iteraciones y cota iteraciones',iter,itmax
            write(6,*)'paramos'
          endif
          exit bucle_1
        endif

        if(iter.gt.itmax) then
          if(soydire) then
            write(6,*)'no se ha convergido en el simplex'
            write(6,*)'iteraciones y cota iteraciones',iter,itmax
            write(6,*)'tolerancia y cota tolerancia',rtol,ftol
            write(6,*)'paramos'
          endif
          exit bucle_1
        endif

        iter=iter+2
        ytry=amotry(ndim,p,y,psum,ihi,-1.0_r8)
        if(ytry.le.y(ilo)) then
          ytry=amotry(ndim,p,y,psum,ihi,2.0_r8)
        elseif(ytry.ge.y(inhi)) then
          raux=y(ihi)
          xfac=0.5_r8
          ytry=amotry(ndim,p,y,psum,ihi,0.50_r8)
          if(ytry.ge.raux) then
            do idim=1,ndim+1
              if(idim.ne.ilo) then
                do jdim=1,ndim
                  psum(jdim)=0.50_r8*(p(idim,jdim)+p(ilo,jdim))
                  p(idim,jdim)=psum(jdim)
                enddo
                call calfun(ndim,psum,y(idim))
              endif
            enddo
            iter=iter+ndim
            exit bucle_2
          endif
        else
          iter=iter-1
        endif
      enddo bucle_2
    enddo bucle_1

  end subroutine amoeba

  function amotry(ndim,p,y,psum,ihi,xfac)
   integer(kind=i4), intent (in) :: ndim
   real(kind=r8) :: amotry
   real(kind=r8), intent (inout) :: p(ndim+1,ndim),y(ndim+1)
   real(kind=r8), intent (inout) :: psum(ndim)
   integer(kind=i4), intent (in) :: ihi
   real(kind=r8), intent (in) :: xfac
   real(kind=r8) :: xfac1,xfac2
   real(kind=r8) :: ptry(ndim),ytry
   integer(kind=i4) :: idim

    xfac1=(1.0_r8-xfac)/ndim
    xfac2=xfac1-xfac
    do idim=1,ndim
      ptry(idim)=xfac1*psum(idim)-xfac2*p(ihi,idim)
    enddo
    call calfun(ndim,ptry,ytry)
    if(ytry.lt.y(ihi)) then
      y(ihi)=ytry
      do idim=1,ndim
        psum(idim)=psum(idim)-p(ihi,idim)+ptry(idim)
        p(ihi,idim)=ptry(idim)
      enddo
    endif
    amotry=ytry

  end function amotry
   
end module mminimiza
