module mparalelo

 use mtipos
 use mrandom
 use mrandom2
 use mvaziz
 use mvmolecula
 use mparametros

 use mpi

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: i8=selected_int_kind(15)
 integer, private, parameter :: r8=selected_real_kind(15,9)


   integer(kind=i4), private,save :: nitem=1
   integer(kind=i4), private,save ::  ntids
   integer(kind=i4), private, save :: rank,size
   logical, private, save :: soydire

   integer(kind=i4) :: ierror

contains

 subroutine iniciaparalelo

   call mpi_init(ierror)
   call mpi_comm_rank(mpi_comm_world,rank,ierror)
   call mpi_comm_size(mpi_comm_world,size,ierror)
!   print *, "Hello, world, I am ", rank, " of ", size

   soydire=rank.eq.0

 end subroutine iniciaparalelo

 subroutine iniprocesos

   ntids=-1+size

   if(soydire) then
       write(6,'("calculo en paralelo con MPI")') 
       write(6,'("numero de calculos en paralelo",t40,i10)') size
       write(6,'("numero de ntids",t40,i10)') ntids
   endif

 end subroutine iniprocesos

 subroutine quiensoy(soydireval)
  logical, intent (out) :: soydireval

   soydireval=soydire

 end subroutine quiensoy

 subroutine cuantosparalelos(ncparval)
  integer(kind=i4), intent (out) :: ncparval

   ncparval=size

 end subroutine cuantosparalelos

 subroutine reparteentrada

   if(soydire) then
    write(6,'(/)')
    write(6,'("Enviando informacion del calculo a los procesadores")') 
   endif 

   call direreparteentrada
   if(.not.datosbien) call fincalculo

 end subroutine reparteentrada

 subroutine repartepotencial

   if(soydire) then
     write(6,'(/)')
     write(6,'("Enviando informacion del potencial a los procesadores")') 
   endif 
   call direrepartepotencial

 end subroutine repartepotencial

 subroutine compruebatodos
  real(kind=r8) :: semilla
  integer(kind=i8) :: irnpar
  integer(kind=i4) :: icpar
  integer(kind=i4) ::  nwaproc(0:size-1),mitproc(0:size-1)
  real(kind=r8) ::  semproc(0:size-1)

   call sacasemilla(irnpar)
   semilla=irnpar
   call mpi_gather(nwalkers,nitem,mpi_integer,nwaproc,nitem,mpi_integer,0,    &
  &                mpi_comm_world,ierror)
   call mpi_gather(rank,nitem,mpi_integer,mitproc,nitem,mpi_integer,0,    &
  &                mpi_comm_world,ierror)
   call mpi_gather(semilla,nitem,mpi_double_precision,semproc,nitem,       &
  &                mpi_double_precision,0,mpi_comm_world,ierror)

  if(soydire) then
    write(6,'(/)')
    write(6,*)"*****************************************************"
    write(6,*)"***Semillas e identificacion de los procesos*******"
    write(6,*)"*****************************************************"
    write(6,*) "------------------------------------------------"
    do icpar=1,size-1
      irnpar=semproc(icpar)
      write(6,*) 'proceso numero',icpar
      write(6,*) 'identificacion propia proceso      ',mitproc(icpar)
      write(6,*) 'numero de walkers en este proceso',nwaproc(icpar)
      write(6,*) 'semilla para este proceso',irnpar
      write(6,*)
    enddo
    icpar=0
    irnpar=semproc(icpar)
    write(6,*) 'proceso numero',icpar
    write(6,*) 'identificacion propia proceso      ',mitproc(icpar)
    write(6,*) 'dire: identificacion propia proceso  ',rank
    write(6,*) 'numero de walkers en este proceso',nwaproc(icpar)
    write(6,*) 'dire: numero de walkers en este proceso',nwalkers
    write(6,*) 'semilla para este proceso',irnpar
    call sacasemilla(irnpar)
    write(6,*) 'dire: semilla para este proceso',irnpar
  endif

 end subroutine compruebatodos

 subroutine distribuyesemillas
  real(kind=r8) :: rn
  integer(kind=i4) :: icpar
  integer(kind=i8) :: irnpar

   call sacasemilla(irnpar)

   do icpar=1,size-1
      call rand1p(rn,irnpar)
      if(rank.eq.icpar) call fijasemilla(irnpar)
   enddo
   call rand1p(rn,irnpar)

   if(soydire) call fijasemilla(irnpar)

 end subroutine distribuyesemillas

 subroutine direreparteentrada
  real(kind=r8) :: rirn

   if(soydire) rirn=irncal

    call mpi_bcast(datosbien,nitem,mpi_logical,0,mpi_comm_world,ierror)
    call mpi_bcast(libre,nitem,mpi_logical,0,mpi_comm_world,ierror)
    call mpi_bcast(impurfija,nitem,mpi_logical,0,mpi_comm_world,ierror)
    call mpi_bcast(rotamol,nitem,mpi_logical,0,mpi_comm_world,ierror)
    call mpi_bcast(mhe4,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(mhe3,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(nhe4,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(nhe3,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(namol,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(hb2he4,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(hb2he3,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(opot,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(ngatom,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(natom,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(ncmtras,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(mx,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(momi,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(hb2x,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(brot,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(impureza,nitem,mpi_logical,0,mpi_comm_world,ierror)
    call mpi_bcast(impurmol,nitem,mpi_logical,0,mpi_comm_world,ierror)

    call mpi_bcast(cintr,3*namol,mpi_double_precision,0,mpi_comm_world,ierror)

    call mpi_bcast(rirn,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(opcion,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(enermin,nitem,mpi_logical,0,mpi_comm_world,ierror)
    call mpi_bcast(deltahe4,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(deltahe3,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(deltax,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(deltaa,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(etrial,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dtau,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(nblockeq,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(npasosdc,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(nblock,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(npasos,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(nwalkers,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(ncetrial,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(nhe3up,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(nhe3dw,nitem,mpi_integer,0,mpi_comm_world,ierror)

    call mpi_bcast(alfahe4,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(bhe4,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(nuhe4,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(alfahe3,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(bhe3,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(nuhe3,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(bback,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(alfamix,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(bmix,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(numix,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dalfahe4,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dbhe4,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dnuhe4,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dalfahe3,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dbhe3,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dnuhe3,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dbback,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dalfamix,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dbmix,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dnumix,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(phe4,3,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(phe3,4,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(pmix,3,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(lxhe4,nitem,mpi_integer,0,mpi_comm_world,ierror)
    call mpi_bcast(lxhe3,nitem,mpi_integer,0,mpi_comm_world,ierror)


    call mpi_bcast(alfaxhe4,1+lxhe4,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(bxhe4,1+lxhe4,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(nuxhe4,1+lxhe4,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(p5xhe4,1+lxhe4,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(p4xhe4,1+lxhe4,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(alfaxhe3,1+lxhe3,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(bxhe3,1+lxhe3,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(nuxhe3,1+lxhe3,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(p5xhe3,1+lxhe3,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(p4xhe3,1+lxhe3,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dalfaxhe4,1+lxhe4,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dbxhe4,1+lxhe4,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dnuxhe4,1+lxhe4,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dp5xhe4,1+lxhe4,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dp4xhe4,1+lxhe4,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dalfaxhe3,1+lxhe3,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dbxhe3,1+lxhe3,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dnuxhe3,1+lxhe3,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dp5xhe3,1+lxhe3,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(dp4xhe3,1+lxhe3,mpi_double_precision,0,mpi_comm_world,ierror)

    call mpi_bcast(pxhe4,(1+lxhe4)*5,mpi_double_precision,0,mpi_comm_world,ierror)
    call mpi_bcast(pxhe3,(1+lxhe3)*5,mpi_double_precision,0,mpi_comm_world,ierror)

   if(.not.soydire) irncal=rirn

 end subroutine direreparteentrada

 subroutine direrepartepotencial

  select case (opot)
   case (0)
     call reparteaziz
   case (1)
     call repartepw
   case (2) 
     call repartehh
   case (3) 
     call repartekp
   case (4) 
     call repartebh
   case default
     if(soydire) then
       write(6,*) 'en direrepartepotencial'
       write(6,*) 'valor de opot no valido'
       write(6,*) 'valores validos ',0,1,2,3,4
       write(6,*) 'valor leido',opot
     endif
     call fincalculo
  end select

 end subroutine direrepartepotencial

 subroutine reparteaziz
  integer(kind=i4), parameter :: naziz=8
  real(kind=r8) :: paraziz(naziz)

   if(soydire) then
     call sacaaziz(paraziz)
     write(6,'("Transfiriendo Potencial AZIZ")') 
     write(6,'("parametros reales del potencial",t40,i10)') naziz
   endif

   call mpi_bcast(paraziz,naziz,mpi_double_precision,0,mpi_comm_world,ierror)

   if(.not.soydire) call meteaziz(paraziz)

 end subroutine reparteaziz

 subroutine repartepw
  integer(kind=i4), parameter :: npunpw=231,nlampw=37
  real(kind=r8) :: xapw(npunpw*nlampw),yapw(npunpw*nlampw),y2apw(npunpw*nlampw)
  integer(kind=i4) :: nenvia

   if(soydire) then
     call sacapw(xapw,yapw,y2apw)
     write(6,'("Transfiriendo Potencial PW")') 
     write(6,'("parametros reales del potencial",t40,i10)') 3*npunpw*nlampw
   endif

   call mpi_bcast(xapw,npunpw*nlampw,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(yapw,npunpw*nlampw,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(y2apw,npunpw*nlampw,mpi_double_precision,0,mpi_comm_world,ierror)

   if(.not.soydire) call metepw(xapw,yapw,y2apw)

 end subroutine repartepw

 subroutine repartehh
  integer(kind=i4), parameter :: n19=19,n13=13,n10=10
  integer(kind=i4) :: nplhh,nptshh,n_lamhh
  real(kind=r8) :: alphahh(n19*n13),xhh(n19),vxhh(n10),axhh(n10)


   if(soydire) then
     call sacahh(nplhh,nptshh,n_lamhh,alphahh,xhh,vxhh,axhh)
     write(6,'("Transfiriendo Potencial HH")') 
     write(6,'("parametros enteros del potencial",t40,i10)') 3
     write(6,'("parametros reales del potencial",t40,i10)') 2*n10+n19+n19*n13
   endif

   call mpi_bcast(nplhh,nitem,mpi_integer,0,mpi_comm_world,ierror)
   call mpi_bcast(nptshh,nitem,mpi_integer,0,mpi_comm_world,ierror)
   call mpi_bcast(n_lamhh,nitem,mpi_integer,0,mpi_comm_world,ierror)
   call mpi_bcast(vxhh,n10,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(axhh,n10,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(xhh,n19,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(alphahh,n19*n13,mpi_double_precision,0,mpi_comm_world,ierror)

   if(.not.soydire) call metehh(nplhh,nptshh,n_lamhh,alphahh,xhh,vxhh,axhh)

 end subroutine repartehh

 subroutine repartekp
  integer(kind=i4), parameter ::nn=50,maxpts=2000,nnn=nn*nn
  integer(kind=i4) :: m1kp,m2kp,m3kp,n2kp
  integer(kind=i4) :: ind2kp(maxpts),ind3kp(maxpts)
  real(kind=r8) :: x1akp(nn),x2akp(nn),x3akp(nn)
  real(kind=r8) :: yaekp(nn*nnn)

   if(soydire) then
     call sacakp(m1kp,m2kp,m3kp,n2kp,ind2kp,ind3kp,x1akp,x2akp,x3akp,yaekp)
     write(6,'("Transfiriendo Potencial KP")') 
     write(6,'("parametros enteros del potencial",t40,i10)') 4+2*maxpts
     write(6,'("parametros reales del potencial",t40,i10)') 3*nn+nn*nnn
   endif

   call mpi_bcast(m1kp,nitem,mpi_integer,0,mpi_comm_world,ierror)
   call mpi_bcast(m2kp,nitem,mpi_integer,0,mpi_comm_world,ierror)
   call mpi_bcast(m3kp,nitem,mpi_integer,0,mpi_comm_world,ierror)
   call mpi_bcast(n2kp,nitem,mpi_integer,0,mpi_comm_world,ierror)
   call mpi_bcast(ind2kp,maxpts,mpi_integer,0,mpi_comm_world,ierror)
   call mpi_bcast(ind3kp,maxpts,mpi_integer,0,mpi_comm_world,ierror)
   call mpi_bcast(x1akp,nn,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(x2akp,nn,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(x3akp,nn,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(yaekp,nn*nnn,mpi_double_precision,0,mpi_comm_world,ierror)

   if(.not.soydire) then
      call metekp(m1kp,m2kp,m3kp,n2kp,ind2kp,ind3kp,x1akp,x2akp,x3akp,yaekp)
   endif

 end subroutine repartekp

 subroutine repartebh
  real(kind=r8) :: dhcmbh
  integer(kind=i4) :: nenvia

   nenvia=1

   if(soydire) then
     call sacabh(dhcmbh)
     write(6,'("Transfiriendo Potencial BH")') 
     write(6,'("parametros reales del potencial",t40,i10)') nenvia
   endif

   call mpi_bcast(dhcmbh,nenvia,mpi_double_precision,0,mpi_comm_world,ierror)

   if(.not.soydire) call metebh(dhcmbh)

 end subroutine repartebh


 subroutine repartewalker(w1)
  type(walker), intent (inout) :: w1
  real(kind=r8) :: wfw,wfhe4w,wfhe3w,wfmw,wfxw
  real(kind=r8) :: kinw,potw,enew,erotw,eimpw
  real(kind=r8) :: atomw(3*natom),dwfw(3*natom)
  real(kind=r8) :: deltaw(natom),hb2mw(natom),sigma1w(natom),sigma2w(natom)
  real(kind=r8) :: spropw(9)
  real(kind=r8) :: danglew,bw,sig1rotw,sig2rotw,sig1hrotw,sig2hrotw
  real(kind=r8) :: dphiw(2)
  real(kind=r8) :: eje0w(3),pos0w(3)
  integer(kind=i4) :: signoupw,signodww
  integer(kind=i4) :: iatom,ic,jc,ipct

   if(soydire) then
     wfw=w1%lw%wf
     wfhe4w=w1%lw%wfhe4
     wfhe3w=w1%lw%wfhe3
     wfmw=w1%lw%wfm
     wfxw=w1%lw%wfx
     kinw=w1%lw%kin
     potw=w1%lw%pot
     enew=w1%lw%ene
     erotw=w1%lw%erot
     eimpw=w1%lw%eimp
     signoupw=w1%lw%signoup
     signodww=w1%lw%signodw
     ipct=0
     do iatom=1,natom
       do ic=1,3
         ipct=ipct+1
         atomw(ipct)=w1%atom(iatom)%comp(ic)
         dwfw(ipct)=w1%dwf(iatom)%comp(ic)
       enddo
       deltaw(iatom)=w1%delta(iatom)
       hb2mw(iatom)=w1%hb2m(iatom)
       sigma1w(iatom)=w1%sigma1(iatom)
       sigma2w(iatom)=w1%sigma2(iatom)
     enddo
     ipct=0
     do ic=1,3
       do jc=1,3
         ipct=ipct+1
         spropw(ipct)=w1%sprop(jc)%comp(ic)
       enddo
     enddo
     danglew=w1%dangle
     bw=w1%b
     sig1rotw=w1%sig1rot
     sig2rotw=w1%sig2rot
     sig1hrotw=w1%sig1hrot
     sig2hrotw=w1%sig2hrot
     do ic=1,2
       dphiw(ic)=w1%dphi(ic)
     enddo
     do ic=1,3
       eje0w(ic)=w1%eje0%comp(ic)
       pos0w(ic)=w1%pos0%comp(ic)
     enddo
   endif

   call mpi_bcast(wfw,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(wfhe4w,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(wfhe3w,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(wfmw,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(wfxw,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(kinw,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(potw,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(enew,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(erotw,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(eimpw,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(signoupw,nitem,mpi_integer,0,mpi_comm_world,ierror)
   call mpi_bcast(signodww,nitem,mpi_integer,0,mpi_comm_world,ierror)
   call mpi_bcast(spropw,9,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(danglew,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(bw,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(sig1rotw,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(sig2rotw,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(sig1hrotw,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(sig2hrotw,nitem,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(dphiw,2,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(eje0w,3,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(pos0w,3,mpi_double_precision,0,mpi_comm_world,ierror)


   call mpi_bcast(atomw,3*natom,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(dwfw,3*natom,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(deltaw,natom,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(hb2mw,natom,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(sigma1w,natom,mpi_double_precision,0,mpi_comm_world,ierror)
   call mpi_bcast(sigma2w,natom,mpi_double_precision,0,mpi_comm_world,ierror)

   if(.not.soydire) then
     w1%lw%wf=wfw
     w1%lw%wfhe4=wfhe4w
     w1%lw%wfhe3=wfhe3w
     w1%lw%wfm=wfmw
     w1%lw%wfx=wfxw
     w1%lw%kin=kinw
     w1%lw%pot=potw
     w1%lw%ene=enew
     w1%lw%erot=erotw
     w1%lw%eimp=eimpw
     w1%lw%signoup=signoupw
     w1%lw%signodw=signodww
     ipct=0
     do iatom=1,natom
       do ic=1,3
         ipct=ipct+1
         w1%atom(iatom)%comp(ic)=atomw(ipct)
         w1%dwf(iatom)%comp(ic)=dwfw(ipct)
       enddo
       w1%delta(iatom)=deltaw(iatom)
       w1%hb2m(iatom)=hb2mw(iatom)
       w1%sigma1(iatom)=sigma1w(iatom)
       w1%sigma2(iatom)=sigma2w(iatom)
     enddo
     ipct=0
     do ic=1,3
       do jc=1,3
         ipct=ipct+1
         w1%sprop(jc)%comp(ic)=spropw(ipct)
       enddo
     enddo
     w1%dangle=danglew
     w1%b=bw
     w1%sig1rot=sig1rotw
     w1%sig2rot=sig2rotw
     w1%sig1hrot=sig1hrotw
     w1%sig2hrot=sig2hrotw
     do ic=1,2
       w1%dphi(ic)=dphiw(ic)
     enddo
     do ic=1,3
       w1%eje0%comp(ic)=eje0w(ic)
       w1%pos0%comp(ic)=pos0w(ic)
     enddo
   endif

 end subroutine repartewalker


 subroutine otroenviareales(nval,pval)
  integer(kind=i4), intent (in) :: nval
  real(kind=r8), intent (in) :: pval(nval)
  integer(kind=i4) :: id=1

  call mpi_send(pval,nval,mpi_double_precision,0,id,mpi_comm_world,ierror)

 end subroutine otroenviareales

 subroutine direrecibereales(itid,nval,pval)
  integer(kind=i4), intent (in) ::  itid,nval
  real(kind=r8), intent (inout) :: pval(nval)
  integer(kind=i4) :: istatus(mpi_status_size)
  integer(kind=i4) :: id=1

   call mpi_recv(pval,nval,mpi_double_precision,itid,id,mpi_comm_world,istatus,ierror)

 end subroutine direrecibereales

 subroutine repartereales(ndim,rval)
  integer(kind=i4), intent (in) :: ndim
  real(kind=r8), intent (inout) :: rval(ndim)

   call mpi_bcast(rval,ndim,mpi_double_precision,0,mpi_comm_world,ierror)

 end subroutine repartereales

 subroutine sumareal(rval)
  real(kind=r8), intent (inout) :: rval
  real(kind=r8) :: rtid

   call mpi_reduce(rval,rtid,nitem,mpi_double_precision,mpi_sum,0,   &
 &                 mpi_comm_world,ierror)
   rval=rtid

 end subroutine sumareal

 subroutine sumareales(ndim,rval)
  integer(kind=i4), intent (in) :: ndim
  real(kind=r8), intent (inout) :: rval(ndim)
  real(kind=r8) :: rtid(ndim)

   call mpi_reduce(rval,rtid,ndim,mpi_double_precision,mpi_sum,0,  &
 &                 mpi_comm_world,ierror)
   rval=rtid

 end subroutine sumareales

 subroutine fincalculo

   call mpi_barrier(mpi_comm_world,ierror)
   call mpi_finalize(ierror)

 end subroutine fincalculo

end module mparalelo
