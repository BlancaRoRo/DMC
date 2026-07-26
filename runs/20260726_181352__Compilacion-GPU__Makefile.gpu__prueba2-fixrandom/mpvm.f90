module mparalelo

 use mtipos
 use mrandom
 use mrandom2
 use mvaziz
 use mvmolecula
 use mparametros

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: i8=selected_int_kind(15)
 integer, private, parameter :: r8=selected_real_kind(15,9)

   include 'fpvm3.h'

   integer(kind=i4), private,save :: nitem=1,stride=1
   integer(kind=i4) :: info,mstag

   integer(kind=i4), private,save ::  mitid,diretid,ntids
   integer(kind=i4), private, save, allocatable :: tids(:)
   integer(kind=i4), private,save ::  ncpar
   logical, private, save :: soydire

contains

 subroutine iniciaparalelo

   call pvmfmytid(mitid)
   call pvmfparent(diretid)

   soydire=diretid.eq.PVMNOPARENT

 end subroutine iniciaparalelo

 subroutine iniprocesos

   if(soydire) call direiniciaresto
    
   call reparteentero(ntids)
   if(.not.allocated(tids)) allocate (tids(ntids))
   call reparteenteros(ntids,tids)

   ncpar=ntids+1

   if(soydire) write(6,'("calculo en paralelo con PVM")') 
   if(soydire) write(6,'("numero de calculos en paralelo",t40,i10)') ncpar

 end subroutine iniprocesos

 subroutine quiensoy(soydireval)
  logical, intent (out) :: soydireval

   soydireval=soydire

 end subroutine quiensoy

 subroutine cuantosparalelos(ncparval)
  integer(kind=i4), intent (out) :: ncparval

   ncparval=ncpar

 end subroutine cuantosparalelos

 subroutine reparteentrada

   if(soydire) then
    write(6,'(/)')
    write(6,'("Enviando informacion del calculo a los procesadores")') 
     call direenviaentrada
   else
     call otrorecibeentrada
   endif 

   if(.not.datosbien) call fincalculo

 end subroutine reparteentrada

 subroutine repartepotencial

   if(soydire) then
     write(6,'(/)')
     write(6,'("Enviando informacion del potencial a los procesadores")') 
     call direenviapotencial
   else
     call otrorecibepotencial
   endif 

 end subroutine repartepotencial

 subroutine compruebatodos
  real(kind=r8) :: semilla
  integer(kind=i4) :: icpar
  integer(kind=i4) :: mitidval,diretidval,pvmnoval,nwalkersval
  integer(kind=i8) :: irnpar

  if(soydire) then
    write(6,'(/)')
    write(6,*)"*****************************************************"
    write(6,*)"***Semillas e identificacion de los procesos*******"
    write(6,*)"*****************************************************"
    write(6,*) "------------------------------------------------"
    do icpar=1,ncpar-1
      call direrecibeentero(icpar,nwalkersval)
      call direrecibereal(icpar,semilla)
      call direrecibeentero(icpar,mitidval)
      call direrecibeentero(icpar,diretidval)
      call direrecibeentero(icpar,pvmnoval)
      irnpar=semilla
      write(6,*) 'proceso numero',icpar
      write(6,*) 'numero de walkers en este proceso',nwalkersval
      write(6,*) 'semilla para este proceso',irnpar
      write(6,*) 'identificacion comun del proceso   ',tids(icpar)
      write(6,*) 'identificacion propia proceso      ',mitidval
      write(6,*) 'identificacion propia del dire     ',diretidval
      write(6,*) 'identificacion general del dire    ',pvmnoval
      write(6,*)
    enddo
    icpar=ncpar
    call sacasemilla(irnpar)
    write(6,*) 'dire: proceso numero',icpar
    write(6,*) 'dire: numero de walkers en este proceso',nwalkers
    write(6,*) 'dire: semilla para este proceso',irnpar
    write(6,*) 'dire: identificacion propia proceso  ',mitid
    write(6,*) 'dire: identificacion propia del dire ',diretid
    write(6,*) 'dire: identificacion general del dire',PVMNOPARENT
  else
    call sacasemilla(irnpar)
    semilla=irnpar
    pvmnoval=PVMNOPARENT
    call otroenviaentero(nwalkers)
    call otroenviareal(semilla)
    call otroenviaentero(mitid)
    call otroenviaentero(diretid)
    call otroenviaentero(pvmnoval)
  endif

 end subroutine compruebatodos

 subroutine distribuyesemillas
  real(kind=r8) :: rn
  integer(kind=i4) :: itid
  integer(kind=i8) :: irnpar

   call sacasemilla(irnpar)

   do itid=1,ntids
      call rand1p(rn,irnpar)
      if(mitid.eq.tids(itid)) call fijasemilla(irnpar)
   enddo
   call rand1p(rn,irnpar)

   if(soydire) call fijasemilla(irnpar)

 end subroutine distribuyesemillas

 subroutine reparteentero(nval)
  integer(kind=i4), intent (inout) :: nval
  integer(kind=i4) :: itid

   if(soydire) then
     do itid=1,ntids
       call direenviaentero(itid,nval)
     enddo
   else
      call otrorecibeentero(nval)
   endif

 end subroutine reparteentero

 subroutine reparteenteros(ndim,nval)
  integer(kind=i4), intent (in) :: ndim
  integer(kind=i4), intent (inout) :: nval(ndim)
  integer(kind=i4) :: itid

   if(soydire) then
     do itid=1,ntids
       call direenviaenteros(itid,ndim,nval)
     enddo
   else
      call otrorecibeenteros(ndim,nval)
   endif

 end subroutine reparteenteros

 subroutine repartereales(ndim,rval)
  integer(kind=i4), intent (in) :: ndim
  real(kind=r8), intent (inout) :: rval(ndim)
  integer(kind=i4) :: itid

   if(soydire) then
     do itid=1,ntids
       call direenviareales(itid,ndim,rval)
     enddo
   else
      call otrorecibereales(ndim,rval)
   endif

 end subroutine repartereales

 subroutine repartewalker(w1)
  type(walker), intent (inout) :: w1
  integer(kind=i4) :: itid

   if(soydire) then
     do itid=1,ntids
       call direenviawalker(itid,w1)
     enddo
   else
     call otrorecibewalker(w1)
   endif

 end subroutine repartewalker

 subroutine sumareal(rval)
  real(kind=r8), intent (inout) :: rval
  real(kind=r8) :: rtid
  integer(kind=i4) :: itid

   if(soydire) then
     do itid=1,ntids
       call direrecibereal(itid,rtid)
       rval=rval+rtid
     enddo
   else
     call otroenviareal(rval)
   endif

 end subroutine sumareal

 subroutine sumareales(ndim,rval)
  integer(kind=i4), intent (in) :: ndim
  real(kind=r8), intent (inout) :: rval(ndim)
  real(kind=r8) :: rtid(ndim)
  integer(kind=i4) :: itid

   if(soydire) then
     do itid=1,ntids
       call direrecibereales(itid,ndim,rtid)
       rval=rval+rtid
     enddo
   else
     call otroenviareales(ndim,rval)
   endif

 end subroutine sumareales

 subroutine direiniciaresto
  integer(kind=i4) :: nhosts,ihost
  integer(kind=i4) :: narch,velocidad(1),dtid(1)
  integer(kind=i4) :: icadapvm,itid
  integer(kind=i4) :: numt,numtin=1
  character(len=20) :: tarea="qmccluster"
  character (len=20) :: nombre(1),arch(1)

   ihost=1
   call pvmfconfig(nhosts,narch,dtid(1),nombre(1),arch(1),velocidad(1),info)
   ntids=nhosts*ncadapvm
   allocate (tids(ntids))

   write(6,'("numero de maquinas (solo PVM)",t40,i10)') nhosts
   write(6,'("numero de procesos a iniciar (solo PVM)",t40,i10)') ntids
   write(6,*) "maquina          codigo    nombre         arquitectura        velocidad"
   write(6,*)ihost,dtid(1),nombre(1),arch(1),velocidad(1)
   itid=0
   do icadapvm=1,ncadapvm
     itid=itid+1
     call pvmfspawn(tarea,PVMTASKHOST,nombre(1),numtin,tids(itid),numt)
   enddo

   do ihost=2,nhosts
     call pvmfconfig(nhosts,narch,dtid(1),nombre(1),arch(1),velocidad(1),info)
     write(6,*)ihost,dtid(1),nombre(1),arch(1),velocidad(1)
     do icadapvm=1,ncadapvm
       itid=itid+1
       call pvmfspawn(tarea,PVMTASKHOST,nombre(1),numtin,tids(itid),numt)
     enddo
   enddo
   write(6,'("procesos inicializados (solo PVM)",t40,i10)') itid

 end subroutine direiniciaresto

 subroutine direenviaentrada
  integer(kind=i4) :: itid
  integer(kind=i4) :: iamol,ilxhe
  real(kind=r8) :: rirn

   rirn=irncal

   call pvmfinitsend(PVMDEFAULT,info) 

    call pvmfpack(BYTE1,datosbien,nitem,stride,info)
    call pvmfpack(BYTE1,libre,nitem,stride,info)
    call pvmfpack(BYTE1,impurfija,nitem,stride,info)
    call pvmfpack(BYTE1,rotamol,nitem,stride,info)
    call pvmfpack(REAL8,mhe4,nitem,stride,info)
    call pvmfpack(REAL8,mhe3,nitem,stride,info)
    call pvmfpack(INTEGER4,nhe4,nitem,stride,info)
    call pvmfpack(INTEGER4,nhe3,nitem,stride,info)
    call pvmfpack(INTEGER4,namol,nitem,stride,info)
    call pvmfpack(REAL8,hb2he4,nitem,stride,info)
    call pvmfpack(REAL8,hb2he3,nitem,stride,info)
    call pvmfpack(INTEGER4,opot,nitem,stride,info)
    call pvmfpack(INTEGER4,ngatom,nitem,stride,info)
    call pvmfpack(INTEGER4,natom,nitem,stride,info)
    call pvmfpack(INTEGER4,ncmtras,nitem,stride,info)
    call pvmfpack(REAL8,mx,nitem,stride,info)
    call pvmfpack(REAL8,momi,nitem,stride,info)
    call pvmfpack(REAL8,hb2x,nitem,stride,info)
    call pvmfpack(REAL8,brot,nitem,stride,info)
    call pvmfpack(BYTE1,impureza,nitem,stride,info)
    call pvmfpack(BYTE1,impurmol,nitem,stride,info)

    do itid=1,ntids
      do iamol=1,namol
        call direenviareales(itid,3,cintr(1,iamol))
      enddo
    enddo
    
    call pvmfpack(REAL8,rirn,nitem,stride,info)
    call pvmfpack(INTEGER4,opcion,nitem,stride,info)
    call pvmfpack(BYTE1,enermin,nitem,stride,info)
    call pvmfpack(REAL8,deltahe4,nitem,stride,info)
    call pvmfpack(REAL8,deltahe3,nitem,stride,info)
    call pvmfpack(REAL8,deltax,nitem,stride,info)
    call pvmfpack(REAL8,deltaa,nitem,stride,info)
    call pvmfpack(REAL8,etrial,nitem,stride,info)
    call pvmfpack(REAL8,dtau,nitem,stride,info)
    call pvmfpack(INTEGER4,nblockeq,nitem,stride,info)
    call pvmfpack(INTEGER4,npasosdc,nitem,stride,info)
    call pvmfpack(INTEGER4,nblock,nitem,stride,info)
    call pvmfpack(INTEGER4,npasos,nitem,stride,info)
    call pvmfpack(INTEGER4,nwalkers,nitem,stride,info)
    call pvmfpack(INTEGER4,ncetrial,nitem,stride,info)
    call pvmfpack(INTEGER4,nhe3up,nitem,stride,info)
    call pvmfpack(INTEGER4,nhe3dw,nitem,stride,info)

    call pvmfpack(REAL8,alfahe4,nitem,stride,info)
    call pvmfpack(REAL8,bhe4,nitem,stride,info)
    call pvmfpack(REAL8,nuhe4,nitem,stride,info)
    call pvmfpack(REAL8,alfahe3,nitem,stride,info)
    call pvmfpack(REAL8,bhe3,nitem,stride,info)
    call pvmfpack(REAL8,nuhe3,nitem,stride,info)
    call pvmfpack(REAL8,bback,nitem,stride,info)
    call pvmfpack(REAL8,alfamix,nitem,stride,info)
    call pvmfpack(REAL8,bmix,nitem,stride,info)
    call pvmfpack(REAL8,numix,nitem,stride,info)
    call pvmfpack(REAL8,dalfahe4,nitem,stride,info)
    call pvmfpack(REAL8,dbhe4,nitem,stride,info)
    call pvmfpack(REAL8,dnuhe4,nitem,stride,info)
    call pvmfpack(REAL8,dalfahe3,nitem,stride,info)
    call pvmfpack(REAL8,dbhe3,nitem,stride,info)
    call pvmfpack(REAL8,dnuhe3,nitem,stride,info)
    call pvmfpack(REAL8,dbback,nitem,stride,info)
    call pvmfpack(REAL8,dalfamix,nitem,stride,info)
    call pvmfpack(REAL8,dbmix,nitem,stride,info)
    call pvmfpack(REAL8,dnumix,nitem,stride,info)
    call pvmfpack(REAL8,phe4,3,stride,info)
    call pvmfpack(REAL8,phe3,4,stride,info)
    call pvmfpack(REAL8,pmix,3,stride,info)
    call pvmfpack(INTEGER4,lxhe4,nitem,stride,info)
    call pvmfpack(INTEGER4,lxhe3,nitem,stride,info)

    mstag=2
    do itid=1,ntids
      call pvmfsend(tids(itid),mstag,info)
    enddo

   do itid=1,ntids
     call direenviareales(itid,1+lxhe4,alfaxhe4)
     call direenviareales(itid,1+lxhe4,bxhe4)
     call direenviareales(itid,1+lxhe4,nuxhe4)
     call direenviareales(itid,1+lxhe4,p5xhe4)
     call direenviareales(itid,1+lxhe4,p4xhe4)
     call direenviareales(itid,1+lxhe3,alfaxhe3)
     call direenviareales(itid,1+lxhe3,bxhe3)
     call direenviareales(itid,1+lxhe3,nuxhe3)
     call direenviareales(itid,1+lxhe3,p5xhe3)
     call direenviareales(itid,1+lxhe3,p4xhe3)
     call direenviareales(itid,1+lxhe4,dalfaxhe4)
     call direenviareales(itid,1+lxhe4,dbxhe4)
     call direenviareales(itid,1+lxhe4,dnuxhe4)
     call direenviareales(itid,1+lxhe4,dp5xhe4)
     call direenviareales(itid,1+lxhe4,dp4xhe4)
     call direenviareales(itid,1+lxhe3,dalfaxhe3)
     call direenviareales(itid,1+lxhe3,dbxhe3)
     call direenviareales(itid,1+lxhe3,dnuxhe3)
     call direenviareales(itid,1+lxhe3,dp5xhe3)
     call direenviareales(itid,1+lxhe3,dp4xhe3)
     do ilxhe=0,lxhe4
       call direenviareales(itid,5,pxhe4(1,ilxhe))
     enddo
     do ilxhe=0,lxhe3
       call direenviareales(itid,5,pxhe3(1,ilxhe))
     enddo
   enddo

 end subroutine direenviaentrada

 subroutine otrorecibeentrada
  integer(kind=i4) :: iamol,ilxhe
  real(kind=r8) :: rirn


   mstag=2

   call pvmfrecv(diretid,mstag,info)

   call pvmfunpack(BYTE1,datosbien,nitem,stride,info)
   call pvmfunpack(BYTE1,libre,nitem,stride,info)
   call pvmfunpack(BYTE1,impurfija,nitem,stride,info)
   call pvmfunpack(BYTE1,rotamol,nitem,stride,info)
   call pvmfunpack(REAL8,mhe4,nitem,stride,info)
   call pvmfunpack(REAL8,mhe3,nitem,stride,info)
   call pvmfunpack(INTEGER4,nhe4,nitem,stride,info)
   call pvmfunpack(INTEGER4,nhe3,nitem,stride,info)
   call pvmfunpack(INTEGER4,namol,nitem,stride,info)
   call pvmfunpack(REAL8,hb2he4,nitem,stride,info)
   call pvmfunpack(REAL8,hb2he3,nitem,stride,info)
   call pvmfunpack(INTEGER4,opot,nitem,stride,info)
   call pvmfunpack(INTEGER4,ngatom,nitem,stride,info)
   call pvmfunpack(INTEGER4,natom,nitem,stride,info)
   call pvmfunpack(INTEGER4,ncmtras,nitem,stride,info)
   call pvmfunpack(REAL8,mx,nitem,stride,info)
   call pvmfunpack(REAL8,momi,nitem,stride,info)
   call pvmfunpack(REAL8,hb2x,nitem,stride,info)
   call pvmfunpack(REAL8,brot,nitem,stride,info)
   call pvmfunpack(BYTE1,impureza,nitem,stride,info)
   call pvmfunpack(BYTE1,impurmol,nitem,stride,info)

   do iamol=1,namol
     call otrorecibereales(3,cintr(1,iamol))
   enddo


   call pvmfunpack(REAL8,rirn,nitem,stride,info)
   call pvmfunpack(INTEGER4,opcion,nitem,stride,info)
   call pvmfunpack(BYTE1,enermin,nitem,stride,info)
   call pvmfunpack(REAL8,deltahe4,nitem,stride,info)
   call pvmfunpack(REAL8,deltahe3,nitem,stride,info)
   call pvmfunpack(REAL8,deltax,nitem,stride,info)
   call pvmfunpack(REAL8,deltaa,nitem,stride,info)
   call pvmfunpack(REAL8,etrial,nitem,stride,info)
   call pvmfunpack(REAL8,dtau,nitem,stride,info)
   call pvmfunpack(INTEGER4,nblockeq,nitem,stride,info)
   call pvmfunpack(INTEGER4,npasosdc,nitem,stride,info)
   call pvmfunpack(INTEGER4,nblock,nitem,stride,info)
   call pvmfunpack(INTEGER4,npasos,nitem,stride,info)
   call pvmfunpack(INTEGER4,nwalkers,nitem,stride,info)
   call pvmfunpack(INTEGER4,ncetrial,nitem,stride,info)
   call pvmfunpack(INTEGER4,nhe3up,nitem,stride,info)
   call pvmfunpack(INTEGER4,nhe3dw,nitem,stride,info)

   call pvmfunpack(REAL8,alfahe4,nitem,stride,info)
   call pvmfunpack(REAL8,bhe4,nitem,stride,info)
   call pvmfunpack(REAL8,nuhe4,nitem,stride,info)
   call pvmfunpack(REAL8,alfahe3,nitem,stride,info)
   call pvmfunpack(REAL8,bhe3,nitem,stride,info)
   call pvmfunpack(REAL8,nuhe3,nitem,stride,info)
   call pvmfunpack(REAL8,bback,nitem,stride,info)
   call pvmfunpack(REAL8,alfamix,nitem,stride,info)
   call pvmfunpack(REAL8,bmix,nitem,stride,info)
   call pvmfunpack(REAL8,numix,nitem,stride,info)
   call pvmfunpack(REAL8,dalfahe4,nitem,stride,info)
   call pvmfunpack(REAL8,dbhe4,nitem,stride,info)
   call pvmfunpack(REAL8,dnuhe4,nitem,stride,info)
   call pvmfunpack(REAL8,dalfahe3,nitem,stride,info)
   call pvmfunpack(REAL8,dbhe3,nitem,stride,info)
   call pvmfunpack(REAL8,dnuhe3,nitem,stride,info)
   call pvmfunpack(REAL8,dbback,nitem,stride,info)
   call pvmfunpack(REAL8,dalfamix,nitem,stride,info)
   call pvmfunpack(REAL8,dbmix,nitem,stride,info)
   call pvmfunpack(REAL8,dnumix,nitem,stride,info)
   call pvmfunpack(REAL8,phe4,3,stride,info)
   call pvmfunpack(REAL8,phe3,4,stride,info)
   call pvmfunpack(REAL8,pmix,3,stride,info)
   call pvmfunpack(INTEGER4,lxhe4,nitem,stride,info)
   call pvmfunpack(INTEGER4,lxhe3,nitem,stride,info)


   call otrorecibereales(1+lxhe4,alfaxhe4)
   call otrorecibereales(1+lxhe4,bxhe4)
   call otrorecibereales(1+lxhe4,nuxhe4)
   call otrorecibereales(1+lxhe4,p5xhe4)
   call otrorecibereales(1+lxhe4,p4xhe4)
   call otrorecibereales(1+lxhe3,alfaxhe3)
   call otrorecibereales(1+lxhe3,bxhe3)
   call otrorecibereales(1+lxhe3,nuxhe3)
   call otrorecibereales(1+lxhe3,p5xhe3)
   call otrorecibereales(1+lxhe3,p4xhe3)
   call otrorecibereales(1+lxhe4,dalfaxhe4)
   call otrorecibereales(1+lxhe4,dbxhe4)
   call otrorecibereales(1+lxhe4,dnuxhe4)
   call otrorecibereales(1+lxhe4,dp5xhe4)
   call otrorecibereales(1+lxhe4,dp4xhe4)
   call otrorecibereales(1+lxhe3,dalfaxhe3)
   call otrorecibereales(1+lxhe3,dbxhe3)
   call otrorecibereales(1+lxhe3,dnuxhe3)
   call otrorecibereales(1+lxhe3,dp5xhe3)
   call otrorecibereales(1+lxhe3,dp4xhe3)
   do ilxhe=0,lxhe4
     call otrorecibereales(5,pxhe4(1,ilxhe))
   enddo
   do ilxhe=0,lxhe3
     call otrorecibereales(5,pxhe3(1,ilxhe))
   enddo

   irncal=rirn

 end subroutine otrorecibeetrada

 subroutine direenviapotencial

   select case (opot)
    case (0)
      call enviaaziz
    case (1)
      call enviapw
    case (2) 
      call enviahh
    case (3) 
      call enviakp
    case (4) 
      call enviabh
    case default
      write(6,*) 'en direenviapotencial'
      write(6,*) 'valor de opot no valido'
      write(6,*) 'valores validos ',0,1,2,3,4
      write(6,*) 'valor leido',opot
      call fincalculo
  end select

 end subroutine direenviapotencial

 subroutine otrorecibepotencial

   select case (opot)
    case (0)
      call recibeaziz
    case (1)
      call recibepw
    case (2) 
      call recibehh
    case (3) 
      call recibekp
    case (4) 
      call recibebh
    case default
      call fincalculo
  end select

 end subroutine otrorecibepotencial

 subroutine direenviawalker(itid,w1)
  integer(kind=i4), intent (in) :: itid
  type(walker), intent (in) :: w1
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

   mstag=3
   call pvmfinitsend(PVMDEFAULT,info) 

   call pvmfpack(REAL8,wfw,nitem,stride,info)
   call pvmfpack(REAL8,wfhe4w,nitem,stride,info)
   call pvmfpack(REAL8,wfhe3w,nitem,stride,info)
   call pvmfpack(REAL8,wfmw,nitem,stride,info)
   call pvmfpack(REAL8,wfxw,nitem,stride,info)
   call pvmfpack(REAL8,kinw,nitem,stride,info)
   call pvmfpack(REAL8,potw,nitem,stride,info)
   call pvmfpack(REAL8,enew,nitem,stride,info)
   call pvmfpack(REAL8,erotw,nitem,stride,info)
   call pvmfpack(REAL8,eimpw,nitem,stride,info)
   call pvmfpack(INTEGER4,signoupw,nitem,stride,info)
   call pvmfpack(INTEGER4,signodww,nitem,stride,info)
   call pvmfpack(REAL8,spropw,9,stride,info)
   call pvmfpack(REAL8,danglew,nitem,stride,info)
   call pvmfpack(REAL8,bw,nitem,stride,info)
   call pvmfpack(REAL8,sig1rotw,nitem,stride,info)
   call pvmfpack(REAL8,sig2rotw,nitem,stride,info)
   call pvmfpack(REAL8,sig1hrotw,nitem,stride,info)
   call pvmfpack(REAL8,sig2hrotw,nitem,stride,info)
   call pvmfpack(REAL8,dphiw,2,stride,info)
   call pvmfpack(REAL8,eje0w,3,stride,info)
   call pvmfpack(REAL8,pos0w,3,stride,info)

   call pvmfsend(tids(itid),mstag,info)

   call direenviareales(itid,3*natom,atomw)
   call direenviareales(itid,3*natom,dwfw)
   call direenviareales(itid,natom,deltaw)
   call direenviareales(itid,natom,hb2mw)
   call direenviareales(itid,natom,sigma1w)
   call direenviareales(itid,natom,sigma2w)

 end subroutine direenviawalker

 subroutine otrorecibewalker(w1)
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

   mstag=3

   call pvmfrecv(diretid,mstag,info)

   call pvmfunpack(REAL8,wfw,nitem,stride,info)
   call pvmfunpack(REAL8,wfhe4w,nitem,stride,info)
   call pvmfunpack(REAL8,wfhe3w,nitem,stride,info)
   call pvmfunpack(REAL8,wfmw,nitem,stride,info)
   call pvmfunpack(REAL8,wfxw,nitem,stride,info)
   call pvmfunpack(REAL8,kinw,nitem,stride,info)
   call pvmfunpack(REAL8,potw,nitem,stride,info)
   call pvmfunpack(REAL8,enew,nitem,stride,info)
   call pvmfunpack(REAL8,erotw,nitem,stride,info)
   call pvmfunpack(REAL8,eimpw,nitem,stride,info)
   call pvmfunpack(INTEGER4,signoupw,nitem,stride,info)
   call pvmfunpack(INTEGER4,signodww,nitem,stride,info)
   call pvmfunpack(REAL8,spropw,9,stride,info)
   call pvmfunpack(REAL8,danglew,nitem,stride,info)
   call pvmfunpack(REAL8,bw,nitem,stride,info)
   call pvmfunpack(REAL8,sig1rotw,nitem,stride,info)
   call pvmfunpack(REAL8,sig2rotw,nitem,stride,info)
   call pvmfunpack(REAL8,sig1hrotw,nitem,stride,info)
   call pvmfunpack(REAL8,sig2hrotw,nitem,stride,info)
   call pvmfunpack(REAL8,dphiw,2,stride,info)
   call pvmfunpack(REAL8,eje0w,3,stride,info)
   call pvmfunpack(REAL8,pos0w,3,stride,info)


   call otrorecibereales(3*natom,atomw)
   call otrorecibereales(3*natom,dwfw)
   call otrorecibereales(natom,deltaw)
   call otrorecibereales(natom,hb2mw)
   call otrorecibereales(natom,sigma1w)
   call otrorecibereales(natom,sigma2w)

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

 end subroutine otrorecibewalker

 subroutine direenviaentero(itid,ivalor)
  integer(kind=i4), intent (in) :: itid
  integer(kind=i4), intent (in) :: ivalor


   mstag=6
   call pvmfinitsend(PVMDEFAULT,info) 

   call pvmfpack(INTEGER4,ivalor,nitem,stride,info)

   call pvmfsend(tids(itid),mstag,info)

 end subroutine direenviaentero

 subroutine otrorecibeentero(ivalor)
  integer(kind=i4), intent (inout) :: ivalor

   mstag=6

   call pvmfrecv(diretid,mstag,info)

   call pvmfunpack(INTEGER4,ivalor,nitem,stride,info)

 end subroutine otrorecibeentero

 subroutine otroenviaentero(ivalor)
  integer(kind=i4), intent (in) :: ivalor

  mstag=7

  call pvmfinitsend(PVMDEFAULT,info) 
  call pvmfpack(INTEGER4,ivalor,nitem,stride,info)
  call pvmfsend(diretid,mstag,info)

 end subroutine otroenviaentero

 subroutine direrecibeentero(itid,ivalor)
  integer(kind=i4), intent (in) :: itid
  integer(kind=i4), intent (inout) :: ivalor

   mstag=7

   call pvmfrecv(tids(itid),mstag,info)
   call pvmfunpack(INTEGER4,ivalor,nitem,stride,info)

 end subroutine direrecibeentero

 subroutine direenviaenteros(itid,nval,ivalores)
  integer(kind=i4), intent (in) ::  itid
  integer(kind=i4), intent (in) :: nval
  integer(kind=i4), intent (in) :: ivalores(nval)

  mstag=8

  call pvmfinitsend(PVMDEFAULT,info) 
  call pvmfpack(INTEGER4,ivalores,nval,stride,info)
  call pvmfsend(tids(itid),mstag,info)

 end subroutine direenviaenteros

 subroutine otrorecibeenteros(nval,ivalores)
  integer(kind=i4), intent (in) ::  nval
  integer(kind=i4), intent (inout) :: ivalores(nval)

   mstag=8

   call pvmfrecv(diretid,mstag,info)
   call pvmfunpack(INTEGER4,ivalores,nval,stride,info)

 end subroutine otrorecibeenteros

 subroutine direenviareal(itid,rvalor)
  integer(kind=i4), intent (in) :: itid
  real(kind=r8), intent (in) :: rvalor

   mstag=9
   call pvmfinitsend(PVMDEFAULT,info) 
   call pvmfpack(REAL8,rvalor,nitem,stride,info)
   call pvmfsend(tids(itid),mstag,info)

 end subroutine direenviareal

 subroutine otrorecibereal(rvalor)
  real(kind=r8), intent (inout) :: rvalor

   mstag=9

   call pvmfrecv(diretid,mstag,info)
   call pvmfunpack(REAL8,rvalor,nitem,stride,info)

 end subroutine otrorecibereal

 subroutine otroenviareal(rvalor)
  real(kind=r8), intent (in) :: rvalor

  mstag=10

  call pvmfinitsend(PVMDEFAULT,info) 
  call pvmfpack(REAL8,rvalor,nitem,stride,info)
  call pvmfsend(diretid,mstag,info)

 end subroutine otroenviareal

 subroutine direrecibereal(itid,rvalor)
  integer(kind=i4), intent (in) ::  itid
  real(kind=r8), intent (inout) :: rvalor

   mstag=10

   call pvmfrecv(tids(itid),mstag,info)
   call pvmfunpack(REAL8,rvalor,nitem,stride,info)

 end subroutine direrecibereal

 subroutine direenviareales(itid,nval,pval)
  integer(kind=i4), intent (in) ::  itid
  integer(kind=i4), intent (in) :: nval
  real(kind=r8), intent (in) :: pval(nval)

  mstag=11

  call pvmfinitsend(PVMDEFAULT,info) 
  call pvmfpack(REAL8,pval,nval,stride,info)
  call pvmfsend(tids(itid),mstag,info)

 end subroutine direenviareales

 subroutine otrorecibereales(nval,pval)
  integer(kind=i4), intent (in) ::  nval
  real(kind=r8), intent (inout) :: pval(nval)

   mstag=11

   call pvmfrecv(diretid,mstag,info)
   call pvmfunpack(REAL8,pval,nval,stride,info)

 end subroutine otrorecibereales

 subroutine otroenviareales(nval,pval)
  integer(kind=i4), intent (in) :: nval
  real(kind=r8), intent (in) :: pval(nval)

  mstag=12

  call pvmfinitsend(PVMDEFAULT,info) 
  call pvmfpack(REAL8,pval,nval,stride,info)
  call pvmfsend(diretid,mstag,info)

 end subroutine otroenviareales

 subroutine direrecibereales(itid,nval,pval)
  integer(kind=i4), intent (in) ::  itid
  integer(kind=i4), intent (in) ::  nval
  real(kind=r8), intent (inout) :: pval(nval)

   mstag=12

   call pvmfrecv(tids(itid),mstag,info)
   call pvmfunpack(REAL8,pval,nval,stride,info)

 end subroutine direrecibereales

 subroutine enviaaziz
  integer(kind=i4), parameter :: naziz=8
  real(kind=r8) :: paraziz(naziz)
  integer(kind=i4) :: itid

   call sacaaziz(paraziz)

   do itid=1,ntids
      call direenviareales(itid,naziz,paraziz)
   enddo

 end subroutine enviaaziz

 subroutine recibeaziz
  integer(kind=i4), parameter :: naziz=8
  real(kind=r8) :: paraziz(naziz)


   call otrorecibereales(naziz,paraziz)

   call meteaziz(paraziz)

 end subroutine recibeaziz

 subroutine enviapw
  integer(kind=i4), parameter :: nsmax=40
  integer(kind=i4), parameter :: npunpw=231,nlampw=37
  real(kind=r8) :: xapw(npunpw*nlampw),yapw(npunpw*nlampw),y2apw(npunpw*nlampw)
  integer(kind=i4) :: nenvios,ienvio
  integer(kind=i4) :: nvec,ivec
  integer(kind=i4) :: itid

   call sacapw(xapw,yapw,y2apw)


   nenvios=npunpw*nlampw/nsmax
   nvec=npunpw*nlampw-nsmax*nenvios

   write(6,'("parametros del potencial a transferir",t40,i10)') 3*npunpw*nlampw
   write(6,'("numero bucles de envio",t40,i10)') nenvios
   write(6,'("vectores enviados cada vez",t40,i10)') 3
   write(6,'("vector enviado en cada bucle",t40,i10)') nsmax
   write(6,'("tamano del vector restante",t40,i10)')  nvec

   ivec=1
   do ienvio=1,nenvios
     do itid=1,ntids
        call direenviareales(itid,nsmax,xapw(ivec))
        call direenviareales(itid,nsmax,yapw(ivec))
        call direenviareales(itid,nsmax,y2apw(ivec))
     enddo
     ivec=ivec+nsmax
   enddo
   do itid=1,ntids
     call direenviareales(itid,nvec,xapw(ivec))
     call direenviareales(itid,nvec,yapw(ivec))
     call direenviareales(itid,nvec,y2apw(ivec))
   enddo

 end subroutine enviapw

 subroutine recibepw
  integer(kind=i4), parameter :: nsmax=40
  integer(kind=i4), parameter :: npunpw=231,nlampw=37
  real(kind=r8) :: xapw(npunpw*nlampw),yapw(npunpw*nlampw),y2apw(npunpw*nlampw)
  integer(kind=i4) :: nenvios,ienvio
  integer(kind=i4) :: nvec,ivec

   nenvios=npunpw*nlampw/nsmax
   nvec=npunpw*nlampw-nsmax*nenvios

   ivec=1
   do ienvio=1,nenvios
     call otrorecibereales(nsmax,xapw(ivec))
     call otrorecibereales(nsmax,yapw(ivec))
     call otrorecibereales(nsmax,y2apw(ivec))
     ivec=ivec+nsmax
   enddo
   call otrorecibereales(nvec,xapw(ivec))
   call otrorecibereales(nvec,yapw(ivec))
   call otrorecibereales(nvec,y2apw(ivec))

   call metepw(xapw,yapw,y2apw)

 end subroutine recibepw

 subroutine enviahh
  integer(kind=i4), parameter :: n19=19,n13=13,n10=10
  integer(kind=i4) :: nplhh,nptshh,n_lamhh
  real(kind=r8) :: alphahh(n19*n13),xhh(n19),vxhh(n10),axhh(n10)
  integer(kind=i4) :: nppot
  integer(kind=i4) :: itid


   call sacahh(nplhh,nptshh,n_lamhh,alphahh,xhh,vxhh,axhh)

   nppot=n19*n13+n19+n10+n10

   write(6,'("parametros del potencial a transferir",t40,i10)') nppot
   do itid=1,ntids
     call direenviaentero(itid,nplhh)
     call direenviaentero(itid,nptshh)
     call direenviaentero(itid,n_lamhh)
     call direenviareales(itid,n10,vxhh)
     call direenviareales(itid,n10,axhh)
     call direenviareales(itid,n19,xhh)
     call direenviareales(itid,n19*n13,alphahh)
   enddo

 end subroutine enviahh

 subroutine recibehh
  integer(kind=i4), parameter :: n19=19,n13=13,n10=10
  integer(kind=i4) :: nplhh,nptshh,n_lamhh
  real(kind=r8) :: alphahh(n19*n13),xhh(n19),vxhh(n10),axhh(n10)


  call otrorecibeentero(nplhh)
  call otrorecibeentero(nptshh)
  call otrorecibeentero(n_lamhh)
  call otrorecibereales(n10,vxhh)
  call otrorecibereales(n10,axhh)
  call otrorecibereales(n19,xhh)
  call otrorecibereales(n19*n13,alphahh)

   call metehh(nplhh,nptshh,n_lamhh,alphahh,xhh,vxhh,axhh)

 end subroutine recibehh

 subroutine enviakp
  integer(kind=i4), parameter ::nn=50,maxpts=2000,nnn=nn*nn
  real(kind=r8) :: x1akp(NN),x2akp(NN),x3akp(NN)
  real(kind=r8)  :: yaekp(nn*nnn)
  integer(kind=i4) :: m1kp,m2kp,m3kp,n2kp
  integer(kind=i4) :: ind2kp(maxpts),ind3kp(maxpts)
  integer(kind=i4) :: nptrans
  integer(kind=i4) :: itid

    call sacakp(m1kp,m2kp,m3kp,n2kp,ind2kp,ind3kp,x1akp,x2akp,x3akp,yaekp)

    nptrans=4+2*maxpts+3*nn+nn*nnn

     write(6,'("parametros del potencial a transferir",t40,i10)') nptrans

     do itid=1,ntids
       call direenviaentero(itid,m1kp)
       call direenviaentero(itid,m2kp)
       call direenviaentero(itid,m3kp)
       call direenviaentero(itid,n2kp)
       call direenviaenteros(itid,maxpts,ind2kp)
       call direenviaenteros(itid,maxpts,ind3kp)
       call direenviareales(itid,nn,x1akp)
       call direenviareales(itid,nn,x2akp)
       call direenviareales(itid,nn,x3akp)
       call direenviareales(itid,nn*nnn,yaekp)
     enddo

 end subroutine enviakp

 subroutine recibekp
  integer(kind=i4), parameter ::nn=50,maxpts=2000,nnn=nn*nn
  real(kind=r8) :: x1akp(NN),x2akp(NN),x3akp(NN)
  real(kind=r8)  :: yaekp(nn*nnn)
  integer(kind=i4) :: m1kp,m2kp,m3kp,n2kp
  integer(kind=i4) :: ind2kp(maxpts),ind3kp(maxpts)

   call otrorecibeentero(m1kp)
   call otrorecibeentero(m2kp)
   call otrorecibeentero(m3kp)
   call otrorecibeentero(n2kp)
   call otrorecibeenteros(maxpts,ind2kp)
   call otrorecibeenteros(maxpts,ind3kp)
   call otrorecibereales(nn,x1akp)
   call otrorecibereales(nn,x2akp)
   call otrorecibereales(nn,x3akp)
   call otrorecibereales(nn*nnn,yaekp)

    call metekp(m1kp,m2kp,m3kp,n2kp,ind2kp,ind3kp,x1akp,x2akp,x3akp,yaekp)

 end subroutine recibekp


 subroutine enviabh
  real(kind=r8) :: dhcmbh
  integer(kind=i4) :: nenvia
  integer(kind=i4) :: itid

   nenvia=1
   write(6,'("parametros del potencial a transferir",t40,i10)') nenvia

   call sacabh(dhcmbh)
   do itid=1,ntids
     call direenviareal(itid,dhcmbh)
   enddo

 end subroutine enviapw

 subroutine recibebh
  real(kind=r8) :: dhcmbh

   call otrorecibereal(dhcmbh)
    
   call metebh(dhcmbh)

 end subroutine recibebh



 subroutine fincalculo

   if(allocated(tids)) deallocate (tids)

!  call pvmfkill(mitid,info)
   call pvmfexit(info)

 end subroutine fincalculo

end module mparalelo
