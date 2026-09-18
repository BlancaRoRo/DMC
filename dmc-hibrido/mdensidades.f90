module mdensidades

 use msistref
 use mparametros
 use mtipos

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: r8=selected_real_kind(15,9)

 real(kind=r8), private, parameter :: rmax=20.0_r8
 integer(kind=i4), private, parameter :: nhr=2000
 real(kind=r8), private, save :: dhr=rmax/nhr
 real(kind=r8), private,  parameter :: cmax=6.0_r8
 integer(kind=i4), private,  parameter :: nhc=60
!real(kind=r8), private, parameter :: cmin=-cmax
!real(kind=r8), private, save :: dhc=(cmax-cmin)/(2*nhc)
 real(kind=r8), private, save :: dhc=cmax/nhc
 real(kind=r8), private, parameter :: smax=6.0_r8
 integer(kind=i4), private, parameter :: nhs=60
 real(kind=r8), private, save :: dhs=smax/nhs

  real(kind=r8), private,save :: den1,denb

  real(kind=r8), private,save :: dr144(nhr),dr244(nhr),drb44(nhr)
  real(kind=r8), private,save :: dr133(nhr),dr233(nhr),drb33(nhr)
  real(kind=r8), private,save :: dr143(nhr),dr243(nhr),drb43(nhr)
  real(kind=r8), private,save :: dr1i4(nhr),dr2i4(nhr),drbi4(nhr)
  real(kind=r8), private,save :: dr1i3(nhr),dr2i3(nhr),drbi3(nhr)
  real(kind=r8), private,save :: dr1ia(nhr),dr2ia(nhr),drbia(nhr)

  real(kind=r8), private,save :: d2he4(-nhc:nhc,nhs),d2bhe4(-nhc:nhc,nhs)
  real(kind=r8), private,save :: d2he3(-nhc:nhc,nhs),d2bhe3(-nhc:nhc,nhs)
  real(kind=r8), private,save :: d2he(-nhc:nhc,nhs),d2bhe(-nhc:nhc,nhs)

  real(kind=r8), private,save :: d2yhe4(-nhc:nhc,-nhs:nhs),d2ybhe4(-nhc:nhc,-nhs:nhs)
  real(kind=r8), private,save :: d2yhe3(-nhc:nhc,-nhs:nhs),d2ybhe3(-nhc:nhc,-nhs:nhs)
  real(kind=r8), private,save :: d2yhe(-nhc:nhc,-nhs:nhs),d2ybhe(-nhc:nhc,-nhs:nhs)

contains

 subroutine densgethis(ndens1,nhis1,ndens2,nhis2)
  integer(kind=i4), intent (out) :: ndens1,nhis1,ndens2,nhis2

   ndens1=6
   nhis1=nhr

   ndens2=3
   nhis2=(2*nhc+1)*nhs

 end subroutine densgethis

 subroutine densceroini

   den1=0.0_r8

   dr144=0.0_r8
   dr133=0.0_r8
   dr143=0.0_r8
   dr1i4=0.0_r8
   dr1i3=0.0_r8
   dr1ia=0.0_r8

   dr244=0.0_r8
   dr233=0.0_r8
   dr243=0.0_r8
   dr2i4=0.0_r8
   dr2i3=0.0_r8
   dr2ia=0.0_r8

   d2he4=0.0_r8
   d2he3=0.0_r8
   d2he=0.0_r8

   d2yhe4=0.0_r8
   d2yhe3=0.0_r8
   d2yhe=0.0_r8

 end subroutine densceroini

 subroutine densceroblo

   denb=0.0_r8

   drb44=0.0_r8
   drb33=0.0_r8
   drb43=0.0_r8
   drbi4=0.0_r8
   drbi3=0.0_r8
   drbia=0.0_r8

   d2bhe4=0.0_r8
   d2bhe3=0.0_r8
   d2bhe=0.0_r8

   d2ybhe4=0.0_r8
   d2ybhe3=0.0_r8
   d2ybhe=0.0_r8

 end subroutine densceroblo

 subroutine denssumapaso(nwpaso,wsim)
  integer(kind=i4), intent (in) :: nwpaso
  type(walker), intent (in) :: wsim(nwpaso)
  type(vec3) :: rtemp
  real(kind=r8) :: rij,cth,sth,dnor,cval,sval
  real(kind=r8) :: rhe(3*ngatom)
  integer(kind=i4) :: iatom,jatom
  integer(kind=i4) :: izatom
  integer(kind=i4) :: ihr,ihc,ihs
  integer(kind=i4) :: iwalker

   do iwalker=1,nwpaso

     denb=denb+1.0_r8

     do iatom=1,nhe4-1
       do jatom=iatom+1,nhe4
        rtemp=wsim(iwalker)%atom(iatom)-wsim(iwalker)%atom(jatom)
        rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
        ihr=int(rij/dhr)+1
        ihr=min(ihr,nhr)
        drb44(ihr)=drb44(ihr)+1.0_r8
       enddo
     enddo

     do iatom=nhe4+1,ngatom
       do jatom=iatom+1,ngatom
        rtemp=wsim(iwalker)%atom(iatom)-wsim(iwalker)%atom(jatom)
        rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
        ihr=int(rij/dhr)+1
        ihr=min(ihr,nhr)
        drb33(ihr)=drb33(ihr)+1.0_r8
       enddo
     enddo

     do iatom=1,nhe4
       do jatom=nhe4+1,ngatom
        rtemp=wsim(iwalker)%atom(iatom)-wsim(iwalker)%atom(jatom)
        rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
        ihr=int(rij/dhr)+1
        ihr=min(ihr,nhr)
        drb43(ihr)=drb43(ihr)+1.0_r8
       enddo
     enddo

     if(impureza) then
       if(impurmol) then
          dnor=sqrt(dot_product(wsim(iwalker)%sprop(3)%comp,wsim(iwalker)%sprop(3)%comp))
          call ccuerpo(wsim(iwalker),rhe)
          izatom=3
       endif
       do iatom=1,nhe4
         rtemp=wsim(iwalker)%atom(iatom)-wsim(iwalker)%atom(natom)
         rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
         ihr=int(rij/dhr)+1
         ihr=min(ihr,nhr)
         drbi4(ihr)=drbi4(ihr)+1.0_r8
         drbia(ihr)=drbia(ihr)+1.0_r8
         if(impurmol) then
           cval=dot_product(rtemp%comp,wsim(iwalker)%sprop(3)%comp)/dnor
           cth=cval/rij
           sth=sqrt(1.0_r8-cth**2)
           sval=rij*sth
           if(cval.gt.0.0_r8) then
             ihc=int(cval/dhc)+1
             ihc=min(ihc,nhc)
           else
             ihc=int(cval/dhc)-1
             ihc=max(ihc,-nhc)
           endif
           ihs=int(sval/dhs)+1
           ihs=min(ihs,nhs)
           d2bhe4(ihc,ihs)=d2bhe4(ihc,ihs)+1.0_r8/sth
           d2bhe(ihc,ihs)=d2bhe(ihc,ihs)+1.0_r8/sth

           if(rhe(izatom-1).lt.0.0_r8) then
             ihs=int(-sval/dhs)-1
             ihs=max(ihs,-nhs)
           endif
           d2ybhe4(ihc,ihs)=d2ybhe4(ihc,ihs)+1.0_r8/sth
           d2ybhe(ihc,ihs)=d2ybhe(ihc,ihs)+1.0_r8/sth
           izatom=izatom+3
         endif
       enddo

       do iatom=nhe4+1,ngatom
         rtemp=wsim(iwalker)%atom(iatom)-wsim(iwalker)%atom(natom)
         rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
         ihr=int(rij/dhr)+1
         ihr=min(ihr,nhr)
         drbi3(ihr)=drbi3(ihr)+1.0_r8
         drbia(ihr)=drbia(ihr)+1.0_r8
         if(impurmol) then
           cval=dot_product(rtemp%comp,wsim(iwalker)%sprop(3)%comp)/dnor
           cth=cval/rij
           sth=sqrt(1.0_r8-cth**2)
           sval=rij*sth
           if(cval.gt.0.0_r8) then
             ihc=int(cval/dhc)+1
             ihc=min(ihc,nhc)
           else
             ihc=int(cval/dhc)-1
             ihc=max(ihc,-nhc)
           endif
           ihs=int(sval/dhs)+1
           ihs=min(ihs,nhs)
           d2bhe3(ihc,ihs)=d2bhe3(ihc,ihs)+1.0_r8/sth
           d2bhe(ihc,ihs)=d2bhe(ihc,ihs)+1.0_r8/sth

           if(rhe(izatom-1).lt.0.0_r8) then
             ihs=int(-sval/dhs)-1
             ihs=max(ihs,-nhs)
           endif
           d2ybhe3(ihc,ihs)=d2ybhe3(ihc,ihs)+1.0_r8/sth
           d2ybhe(ihc,ihs)=d2ybhe(ihc,ihs)+1.0_r8/sth
           izatom=izatom+3
         endif
       enddo

     endif

   enddo

 end subroutine denssumapaso

 subroutine denssumablo

   den1=den1+1.0_r8

   drb44=drb44/denb
   dr144=dr144+drb44
   dr244=dr244+drb44**2

   drb33=drb33/denb
   dr133=dr133+drb33
   dr233=dr233+drb33**2

   drb43=drb43/denb
   dr143=dr143+drb43
   dr243=dr243+drb43**2

   if(impureza) then
     drbi4=drbi4/denb
     dr1i4=dr1i4+drbi4
     dr2i4=dr2i4+drbi4**2

     drbi3=drbi3/denb
     dr1i3=dr1i3+drbi3
     dr2i3=dr2i3+drbi3**2

     drbia=drbia/denb
     dr1ia=dr1ia+drbia
     dr2ia=dr2ia+drbia**2

     if(impurmol)  then
      d2bhe4=d2bhe4/denb
      d2he4=d2he4+d2bhe4

      d2bhe3=d2bhe3/denb
      d2he3=d2he3+d2bhe3

      d2bhe=d2bhe/denb
      d2he=d2he+d2bhe

      d2ybhe4=d2ybhe4/denb
      d2yhe4=d2yhe4+d2ybhe4

      d2ybhe3=d2ybhe3/denb
      d2yhe3=d2yhe3+d2ybhe3

      d2ybhe=d2ybhe/denb
      d2yhe=d2yhe+d2ybhe

     endif

   endif

 end subroutine denssumablo

 subroutine denssumafin
  real(kind=r8) :: den2

   den2=max(1.0_r8,den1-1.0_r8)

    dr144=dr144/den1
    dr244=dr244/den1
    dr244=sqrt(abs(dr244-dr144**2)/den2)

    dr133=dr133/den1
    dr233=dr233/den1
    dr233=sqrt(abs(dr233-dr133**2)/den2)

    dr143=dr143/den1
    dr243=dr243/den1
    dr243=sqrt(abs(dr243-dr143**2)/den2)

    if(impureza) then

      dr1i4=dr1i4/den1
      dr2i4=dr2i4/den1
      dr2i4=sqrt(abs(dr2i4-dr1i4**2)/den2)

      dr1i3=dr1i3/den1
      dr2i3=dr2i3/den1
      dr2i3=sqrt(abs(dr2i3-dr1i3**2)/den2)

      dr1ia=dr1ia/den1
      dr2ia=dr2ia/den1
      dr2ia=sqrt(abs(dr2ia-dr1ia**2)/den2)

       if(impurmol) then
         d2he4=d2he4/den1
         d2he3=d2he3/den1
         d2he=d2he/den1

         d2yhe4=d2yhe4/den1
         d2yhe3=d2yhe3/den1
         d2yhe=d2yhe/den1
      endif

    endif

 end subroutine denssumafin

 subroutine densgetdatostot(idens,nhis,densv,dense)
  integer(kind=i4), intent (in) :: idens,nhis
  real(kind=r8), intent (out) :: densv(nhis),dense(nhis)
  integer(kind=i4) :: ix,iy,ixy

   select case(idens)
     case (1)
       densv=dr144
       dense=dr244
     case (2)
       densv=dr133
       dense=dr233
     case (3)
       densv=dr143
       dense=dr243
     case (4)
       densv=dr1i4
       dense=dr2i4
     case (5)
       densv=dr1i3
       dense=dr2i3
     case (6)
       densv=dr1ia
       dense=dr2ia
     case (7)
       ixy=0
       do iy=1,nhs
         do ix=-nhc,nhc
           ixy=ixy+1
           densv(ixy)=d2he4(ix,iy)
           dense(ixy)=0.0_r8
         enddo
       enddo 
     case (8)
       ixy=0
       do iy=1,nhs
         do ix=-nhc,nhc
           ixy=ixy+1
           densv(ixy)=d2he3(ix,iy)
           dense(ixy)=0.0_r8
         enddo
       enddo 
     case (9)
       ixy=0
       do iy=1,nhs
         do ix=-nhc,nhc
           ixy=ixy+1
           densv(ixy)=d2he(ix,iy)
           dense(ixy)=0.0_r8
         enddo
       enddo 
     case (10)
       ixy=0
       do iy=-nhs,nhs
         do ix=-nhc,nhc
           ixy=ixy+1
           densv(ixy)=d2yhe4(ix,iy)
           dense(ixy)=0.0_r8
         enddo
       enddo 
     case (11)
       ixy=0
       do iy=-nhs,nhs
         do ix=-nhc,nhc
           ixy=ixy+1
           densv(ixy)=d2yhe3(ix,iy)
           dense(ixy)=0.0_r8
         enddo
       enddo 
     case (12)
       ixy=0
       do iy=-nhs,nhs
         do ix=-nhc,nhc
           ixy=ixy+1
           densv(ixy)=d2yhe(ix,iy)
           dense(ixy)=0.0_r8
         enddo
       enddo 
     case default
       densv=0
       dense=0
   end select

 end subroutine densgetdatostot

 subroutine densputdatostot(idens,nhis,densv,dense)
  integer(kind=i4), intent (in) :: idens,nhis
  real(kind=r8), intent (in) :: densv(nhis),dense(nhis)
  integer(kind=i4) :: ix,iy,ixy

   select case(idens)
     case (1)
       dr144=densv
       dr244=dense
     case (2)
       dr133=densv
       dr233=dense
     case (3)
       dr143=densv
       dr243=dense
     case (4)
       dr1i4=densv
       dr2i4=dense
     case (5)
       dr1i3=densv
       dr2i3=dense
     case (6)
       dr1ia=densv
       dr2ia=dense
     case (7)
       ixy=0
       do iy=1,nhs
         do ix=-nhc,nhc
           ixy=ixy+1
           d2he4(ix,iy)=densv(ixy)
         enddo
       enddo 
     case (8)
       ixy=0
       do iy=1,nhs
         do ix=-nhc,nhc
           ixy=ixy+1
           d2he3(ix,iy)=densv(ixy)
         enddo
       enddo 
     case (9)
       ixy=0
       do iy=1,nhs
         do ix=-nhc,nhc
           ixy=ixy+1
           d2he(ix,iy)=densv(ixy)
         enddo
       enddo 
     case (10)
       ixy=0
       do iy=-nhs,nhs
         do ix=-nhc,nhc
           ixy=ixy+1
           d2yhe4(ix,iy)=densv(ixy)
         enddo
       enddo 
     case (11)
       ixy=0
       do iy=-nhs,nhs
         do ix=-nhc,nhc
           ixy=ixy+1
           d2yhe3(ix,iy)=densv(ixy)
         enddo
       enddo 
     case (12)
       ixy=0
       do iy=-nhs,nhs
         do ix=-nhc,nhc
           ixy=ixy+1
           d2yhe(ix,iy)=densv(ixy)
         enddo
       enddo 
   end select

 end subroutine densputdatostot

! ---- Fase 3 (v3-cuda-optimizacion): getters de los acumuladores CRUDOS
! del bloque (drb44 etc., el resultado directo de denssumapaso, antes de
! dividir por denb en denssumablo) -- densgetdatostot solo expone
! dr144/dr244 (promedios de MUCHOS bloques ya terminados), no sirve para
! comparar bit a bit el resultado de una unica llamada a denssumapaso.
! Un getter por array, con su forma NATIVA (no aplanada) -- evita
! reproducir a mano la aritmetica de aplanado de densgetdatostot (que
! ademas tiene un tamano inconsistente para d2yhe*: densgethis reporta
! nhis2=(2*nhc+1)*nhs pero d2yhe4/d2yhe3/d2yhe son (2*nhc+1)*(2*nhs+1)
! -- por eso aqui cada getter usa la forma real de mtipos, sin pasar
! por nhis2). Solo lectura, no cambia denssumapaso ni ninguna otra
! rutina existente.
 subroutine densgetblo_r(idens,v)
  integer(kind=i4), intent (in) :: idens
  real(kind=r8), intent (out) :: v(nhr)

   select case(idens)
     case (1); v=drb44
     case (2); v=drb33
     case (3); v=drb43
     case (4); v=drbi4
     case (5); v=drbi3
     case (6); v=drbia
   end select

 end subroutine densgetblo_r

 subroutine densgetblo_c(idens,v)
  integer(kind=i4), intent (in) :: idens
  real(kind=r8), intent (out) :: v(-nhc:nhc,nhs)

   select case(idens)
     case (7); v=d2bhe4
     case (8); v=d2bhe3
     case (9); v=d2bhe
   end select

 end subroutine densgetblo_c

 subroutine densgetblo_y(idens,v)
  integer(kind=i4), intent (in) :: idens
  real(kind=r8), intent (out) :: v(-nhc:nhc,-nhs:nhs)

   select case(idens)
     case (10); v=d2ybhe4
     case (11); v=d2ybhe3
     case (12); v=d2ybhe
   end select

 end subroutine densgetblo_y

! ---- Fase H (v3-cuda-optimizacion/fase3): setters -- inyectan el
! histograma YA acumulado por k_fase_h (GPU, todo un bloque) en los
! mismos acumuladores que denssumapaso llenaria a mano, para que
! denssumablo/denssumafin (mas abajo, sin tocar) sigan funcionando
! igual sin saber de donde vino el dato. Sustituyen la ASIGNACION
! completa (no suman) porque densceroblo ya puso estos arrays a cero
! al principio del bloque y, en la via GPU, denssumapaso no se llama
! paso a paso (ver mmontecarlo.f90, dmc_gpu_pipeline). ----
 subroutine densputblo_r(idens,v)
  integer(kind=i4), intent (in) :: idens
  real(kind=r8), intent (in) :: v(nhr)

   select case(idens)
     case (1); drb44=v
     case (2); drb33=v
     case (3); drb43=v
     case (4); drbi4=v
     case (5); drbi3=v
     case (6); drbia=v
   end select

 end subroutine densputblo_r

 subroutine densputblo_c(idens,v)
  integer(kind=i4), intent (in) :: idens
  real(kind=r8), intent (in) :: v(-nhc:nhc,nhs)

   select case(idens)
     case (7); d2bhe4=v
     case (8); d2bhe3=v
     case (9); d2bhe=v
   end select

 end subroutine densputblo_c

 subroutine densputblo_y(idens,v)
  integer(kind=i4), intent (in) :: idens
  real(kind=r8), intent (in) :: v(-nhc:nhc,-nhs:nhs)

   select case(idens)
     case (10); d2ybhe4=v
     case (11); d2ybhe3=v
     case (12); d2ybhe=v
   end select

 end subroutine densputblo_y

! ---- denb: contador de walkers procesados en el bloque (denssumapaso
! lo incrementa +1.0 por walker por paso) -- en la via GPU no se llama
! denssumapaso paso a paso, asi que mmontecarlo.f90 lleva la cuenta en
! el host (sumar nwpaso cada paso, trivial) y la fija aqui una vez, al
! final del bloque. ----
 subroutine densputdenb(denbval)
  real(kind=r8), intent (in) :: denbval

    denb=denbval

 end subroutine densputdenb

 subroutine densgetdeno(den1val)
  real(kind=r8), intent (out) :: den1val

    den1val=den1

 end subroutine densgetdeno

 subroutine densputdeno(den1val)
  real(kind=r8), intent (in) :: den1val

    den1=den1val

 end subroutine densputdeno

 subroutine densescrfin
  real(kind=r8) :: dhr2,dhc2,dhs2
  real(kind=r8) :: rij,cval,sval
  integer(kind=i4) :: ihr,ihc,ihs

   dhr2=0.50_r8*dhr
   dhc2=0.50_r8*dhc
   dhs2=0.50_r8*dhs

   open(10,file="dhe4he4."//trim(nombre),status="unknown")
   do ihr=1,nhr
     rij=(ihr-1)*dhr+dhr2
     write(10,'(f10.5,2e20.10)') rij,dr144(ihr),dr244(ihr)
   enddo
   close(10)

   open(10,file="dhe3he3."//trim(nombre),status="unknown")
   do ihr=1,nhr
     rij=(ihr-1)*dhr+dhr2
     write(10,'(f10.5,2e20.10)') rij,dr133(ihr),dr233(ihr)
   enddo
   close(10)

   open(10,file="dhe4he3."//trim(nombre),status="unknown")
   do ihr=1,nhr
     rij=(ihr-1)*dhr+dhr2
     write(10,'(f10.5,2e20.10)') rij,dr143(ihr),dr243(ihr)
   enddo
   close(10)

   if(impureza) then

     open(10,file="dihe4."//trim(nombre),status="unknown")
     do ihr=1,nhr
       rij=(ihr-1)*dhr+dhr2
       write(10,'(f10.5,2e20.10)') rij,dr1i4(ihr),dr2i4(ihr)
     enddo
     close(10)

     open(10,file="dihe3."//trim(nombre),status="unknown")
     do ihr=1,nhr
       rij=(ihr-1)*dhr+dhr2
       write(10,'(f10.5,2e20.10)') rij,dr1i3(ihr),dr2i3(ihr)
     enddo
     close(10)

     open(10,file="dihe."//trim(nombre),status="unknown")
     do ihr=1,nhr
       rij=(ihr-1)*dhr+dhr2
       write(10,'(f10.5,2e20.10)') rij,dr1ia(ihr),dr2ia(ihr)
     enddo
     close(10)

     if(impurmol) then
       open(10,file="d2dhe."//trim(nombre),status="unknown")
       do ihc=-nhc,-1,1
         cval=ihc*dhc+dhc2
         do ihs=1,nhs
           sval=(ihs-1)*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2he(ihc,ihs)
         enddo
         write(10,*)
       enddo
       do ihc=1,nhc
         cval=(ihc-1)*dhc+dhc2
         do ihs=1,nhs
           sval=(ihs-1)*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2he(ihc,ihs)
         enddo
         write(10,*)
       enddo
       close(10)

       open(10,file="d2dhe4."//trim(nombre),status="unknown")
       do ihc=-nhc,-1,1
         cval=ihc*dhc+dhc2
         do ihs=1,nhs
           sval=(ihs-1)*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2he4(ihc,ihs)
         enddo
         write(10,*)
       enddo
       do ihc=1,nhc
         cval=(ihc-1)*dhc+dhc2
         do ihs=1,nhs
           sval=(ihs-1)*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2he4(ihc,ihs)
         enddo
         write(10,*)
       enddo
       close(10)

       open(10,file="d2dhe3."//trim(nombre),status="unknown")
       do ihc=-nhc,-1,1
         cval=ihc*dhc+dhc2
         do ihs=1,nhs
           sval=(ihs-1)*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2he3(ihc,ihs)
         enddo
         write(10,*)
       enddo
       do ihc=1,nhc
         cval=(ihc-1)*dhc+dhc2
         do ihs=1,nhs
           sval=(ihs-1)*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2he3(ihc,ihs)
         enddo
         write(10,*)
       enddo
       close(10)

       open(10,file="d2ydhe."//trim(nombre),status="unknown")
       do ihc=-nhc,-1,1
         cval=ihc*dhc+dhc2
         do ihs=-nhs,-1,1
           sval=ihs*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2yhe(ihc,ihs)
         enddo
         do ihs=1,nhs
           sval=(ihs-1)*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2yhe(ihc,ihs)
         enddo
         write(10,*)
       enddo
       do ihc=1,nhc
         cval=(ihc-1)*dhc+dhc2
         do ihs=-nhs,-1,1
           sval=ihs*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2yhe(ihc,ihs)
         enddo
         do ihs=1,nhs
           sval=(ihs-1)*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2yhe(ihc,ihs)
         enddo
         write(10,*)
       enddo
       close(10)

       open(10,file="d2ydhe4."//trim(nombre),status="unknown")
       do ihc=-nhc,-1,1
         cval=ihc*dhc+dhc2
         do ihs=-nhs,-1,1
           sval=ihs*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2yhe4(ihc,ihs)
         enddo
         do ihs=1,nhs
           sval=(ihs-1)*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2yhe4(ihc,ihs)
         enddo
         write(10,*)
       enddo
       do ihc=1,nhc
         cval=(ihc-1)*dhc+dhc2
         do ihs=-nhs,-1,1
           sval=ihs*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2yhe4(ihc,ihs)
         enddo
         do ihs=1,nhs
           sval=(ihs-1)*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2yhe4(ihc,ihs)
         enddo
         write(10,*)
       enddo
       close(10)

       open(10,file="d2ydhe3."//trim(nombre),status="unknown")
       do ihc=-nhc,-1,1
         cval=ihc*dhc+dhc2
         do ihs=-nhs,-1,1
           sval=ihs*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2yhe3(ihc,ihs)
         enddo
         do ihs=1,nhs
           sval=(ihs-1)*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2yhe3(ihc,ihs)
         enddo
         write(10,*)
       enddo
       do ihc=1,nhc
         cval=(ihc-1)*dhc+dhc2
         do ihs=-nhs,-1,1
           sval=ihs*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2yhe3(ihc,ihs)
         enddo
         do ihs=1,nhs
           sval=(ihs-1)*dhs+dhs2
           write(10,'(2f10.5,es20.10E3)') cval,sval,d2yhe3(ihc,ihs)
         enddo
         write(10,*)
       enddo
       close(10)
     endif

   endif

 end subroutine densescrfin


end module mdensidades
