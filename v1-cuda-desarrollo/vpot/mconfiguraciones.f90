module mconfiguraciones

 use mrandom

  implicit none
  integer, private, parameter :: i4=selected_int_kind(9)
  integer, private, parameter :: i8=selected_int_kind(15)
  integer, private, parameter :: r8=selected_real_kind(15,9)

   real(kind=r8), private, parameter :: bpot=2.90_r8

contains

 subroutine iniconfiguraciones(fichero,impurmol,impurfija,rotamol,  &
&                              nwalkers,natom,ngatom,nhe4,          &
&                              deltahe4,deltahe3,deltax,xwalker,    &
&                              ewalker)
  character(len=10), intent (in) :: fichero
  logical, intent (in) :: impurmol,impurfija,rotamol
  integer (kind=i4), intent (in) :: nwalkers,natom,ngatom,nhe4
  real (kind=r8), intent (in) :: deltahe4,deltahe3,deltax
  real(kind=r8), intent (out) :: xwalker(3*natom*nwalkers)
  real(kind=r8), intent (out) :: ewalker(3*nwalkers)
  real(kind=r8) :: xatom(3,ngatom)
  real (kind=r8) :: rn3(3),gvar3(3),dnor
  integer(kind=i4) :: nfichero,nleidas
  integer(kind=i4) :: iwalker,iatom,ic
  integer(kind=i4) :: ireg,jreg
  integer(kind=i4) :: iwalkerrep,iregrep,jregrep
  integer :: abre,leenw,leexv
  logical :: leefichero
  integer(kind=i8) :: irnu

    nfichero=0
    leefichero=.false.

    write(6,'(/)') 
    write(6,'("DATOS DE LAS CONFIGURACIONES INICIALES")')

    open(9,file="conf."//trim(fichero),status="old",iostat=abre)
    if(abre.eq.0) then
      read(9,'(i10)',iostat=leenw) nfichero
      if(leenw.eq.0) then
        write(6,'("configuraciones segun fichero",t40,i10)') nfichero
        nleidas=0
        ireg=0
        jreg=0
        bucle_pos : do iwalker=1,nfichero
          do iatom=1,natom
            if(ireg+1.gt.3*natom*nwalkers) exit bucle_pos
            if(ireg+2.gt.3*natom*nwalkers) exit bucle_pos
            if(ireg+3.gt.3*natom*nwalkers) exit bucle_pos
            read(9,'(3e20.10)',iostat=leexv)                              &
 &              xwalker(ireg+1),xwalker(ireg+2),xwalker(ireg+3)
            if(leexv.ne.0) exit bucle_pos
            ireg=ireg+3
          enddo
          if(jreg+1.gt.3*nwalkers) exit bucle_pos
          if(jreg+2.gt.3*nwalkers) exit bucle_pos
          if(jreg+3.gt.3*nwalkers) exit bucle_pos
          if(impurmol) then
            read(9,'(3e20.10)',iostat=leexv)                                &
 &               ewalker(jreg+1),ewalker(jreg+2),ewalker(jreg+3)
            if(leexv.ne.0) exit bucle_pos
            dnor=sqrt(ewalker(jreg+1)**2+ewalker(jreg+2)**2+ewalker(jreg+3)**2)
            ewalker(jreg+1)=ewalker(jreg+1)/dnor
            ewalker(jreg+2)=ewalker(jreg+2)/dnor
            ewalker(jreg+3)=ewalker(jreg+3)/dnor
            jreg=jreg+3
          endif
          nleidas=nleidas+1
        enddo bucle_pos
        nfichero=nleidas
        write(6,'(t5,"configuraciones leidas del fichero",t40,i10)') nfichero
        if(nfichero.le.nwalkers) leefichero=.true.
      endif
    endif
    close(9)

    if(nfichero.eq.0) leefichero=.false.

    if(leefichero) then
      write(6,'(t5,"Se usan las configuraciones del fichero")') 
      if(nfichero.lt.nwalkers) then
        write(6,'(t5,"en el fichero hay menos configuraciones de las necesarias")') 
        write(6,'("configuraciones que hay que repetir",t40,i10)') nwalkers-nfichero
        write(6,'("se eligen aleatoriamente las que se repiten",t40,i10)') 
        call sacasemilla(irnu)
        write(6,'("se usa esta semilla",t40,i16)') irnu
        do iwalker=nfichero+1,nwalkers
          iwalkerrep=rn1( )*nfichero+1
          ireg=3*natom*(iwalker-1)
          iregrep=3*natom*(iwalkerrep-1)
          do iatom=1,natom
            xwalker(ireg+1)=xwalker(iregrep+1)
            xwalker(ireg+2)=xwalker(iregrep+2)
            xwalker(ireg+3)=xwalker(iregrep+3)
            ireg=ireg+3
            iregrep=iregrep+3
          enddo
          jreg=3*(iwalker-1)
          jregrep=3*(iwalkerrep-1)
          ewalker(jreg+1)=ewalker(jregrep+1)
          ewalker(jreg+2)=ewalker(jregrep+2)
          ewalker(jreg+3)=ewalker(jregrep+3)
        enddo
      endif
    else
      write(6,'(t5,"Se generan todas las configuraciones aleatoriamente")') 
      call sacasemilla(irnu)
      write(6,'("se usa esta semilla",t40,i16)') irnu
      call ccubica(ngatom,xatom)
      ireg=0
      jreg=0
      do iwalker=1,nwalkers
        do iatom=1,nhe4
          call randv3(rn3)
          do ic=1,3
            ireg=ireg+1
            xwalker(ireg)=xatom(ic,iatom)+0.10_r8*deltahe4*(rn3(ic)-0.50_r8)
          enddo
        enddo
        do iatom=nhe4+1,ngatom
          call randv3(rn3)
          do ic=1,3
            ireg=ireg+1
            xwalker(ireg)=xatom(ic,iatom)+0.10_r8*deltahe3*(rn3(ic)-0.50_r8)
          enddo
        enddo
        do iatom=ngatom+1,natom
          if(impurfija) then
            do ic=1,3
              ireg=ireg+1
              xwalker(ireg)=0.0_r8
            enddo
          else
            call randv3(rn3)
            do ic=1,3
              ireg=ireg+1
              xwalker(ireg)=0.10_r8*deltax*(rn3(ic)-0.50_r8)
            enddo
          endif
          if(impurmol) then
            if(rotamol) then
              call gauss3(gvar3)
              dnor=sqrt(sum(gvar3**2))
            else
              gvar3(1)=0.0_r8
              gvar3(2)=0.0_r8
              gvar3(3)=1.0_r8
              dnor=1.0_r8
            endif
            do ic=1,3
              jreg=jreg+1
              ewalker(jreg)=gvar3(ic)/dnor
            enddo
          endif
        enddo
      enddo
    endif

  end subroutine iniconfiguraciones

  subroutine finconfiguraciones(fichero,impurmol,nwalkers,natom,nhe4,namol,  &
 &                              xwalker,ewalker,raenmol)
   integer(kind=i4), parameter :: nvmd=10
   character(len=10), intent (in) :: fichero
   logical, intent (in) :: impurmol
   integer(kind=i4), intent (in) :: nwalkers,natom,nhe4,namol
   real(kind=r8), intent (in) :: xwalker(3*natom*nwalkers)
   real(kind=r8), intent (in) :: ewalker(3*nwalkers)
   real(kind=r8), intent (in) :: raenmol(3*namol*nwalkers)
   real(kind=r8) :: dnor
   real(kind=r8) :: rij(3),dij(nvmd)
   integer(kind=i4) :: iwalker,iatom
   integer(kind=i4) :: ireg,jreg
   integer(kind=i4) :: ic

    open(9,file="conf."//trim(fichero),status="unknown")
    write(9,'(i10)') nwalkers
    ireg=0
    jreg=0
    do iwalker=1,nwalkers
      do iatom=1,natom
        write(9,'(3e20.10)') xwalker(ireg+1),xwalker(ireg+2),xwalker(ireg+3)
        ireg=ireg+3
      enddo
      if(impurmol) then
        dnor=sqrt(ewalker(jreg+1)**2+ewalker(jreg+2)**2+ewalker(jreg+3)**2)
        write(9,'(3e20.10,f12.8)') ewalker(jreg+1),ewalker(jreg+2),         &
 &                                 ewalker(jreg+3),dnor
        jreg=jreg+3
      endif
    enddo
    close(9)

    open(9,file="conf."//trim(fichero)//".xyz",status="unknown")
    write(9,'(i4)') natom-1+namol
    write(9,*) "posiciones de los atomos"
    ireg=0
    jreg=0
    do iwalker=1,min(nwalkers,nvmd)
      do iatom=1,natom-1
        write(9,'(a2,2x,3f15.8)') "He", xwalker(ireg+1),xwalker(ireg+2),xwalker(ireg+3)
        ireg=ireg+3
      enddo
      ireg=ireg+3
      do ic=1,3
        rij(ic)=raenmol(jreg+ic)-raenmol(jreg+3+ic)
      enddo
      dij(iwalker)=sqrt(dot_product(rij,rij))
      do iatom=1,namol
        write(9,'(a2,2x,3f15.8)') "H ", raenmol(jreg+1),raenmol(jreg+2),raenmol(jreg+3)
        jreg=jreg+3
      enddo
    enddo
    write(9,*)
    write(9,*)
    do iwalker=1,min(nwalkers,nvmd)
      write(9,'(a25,2x,f12.6)') "distancia enlace final",dij(iwalker)
    enddo
    close(9)
      

  end subroutine finconfiguraciones

  subroutine ccubica(ngatom,xatom)
   integer (kind=i4), intent (in) :: ngatom
   real (kind=r8), intent (out) :: xatom(3,ngatom)
   integer (kind=i4) :: patom(3,ngatom)
   integer (kind=i4) :: jval,mval
   integer (kind=i4) :: iatom

    jval=0 
    do
      mval=(2*jval+1)**3
      if(mval.ge.ngatom+1) exit
      jval=jval+1
    enddo

   call reticulo(jval,mval,ngatom,patom)

   do iatom=1,ngatom
     xatom(:,iatom)=bpot*patom(:,iatom)
   enddo
 end subroutine ccubica

 subroutine reticulo(jval,mval,ngatom,patom)
   integer (kind=i4), intent (in) :: jval,mval
   integer (kind=i4), intent (in) :: ngatom
   integer (kind=i4), intent (out) :: patom(3,ngatom)
   integer (kind=i4) :: posi(3,mval),dist(mval),iorden(mval)
   integer (kind=i4) :: iatom
   integer (kind=i4) :: ival,lval,ic1,ic2,ic3
   logical :: libre(mval)

   ival=0
   do ic1=-jval,jval
     do ic2=-jval,jval
       do ic3=-jval,jval
         ival=ival+1
         posi(1,ival)=ic1
         posi(2,ival)=ic2
         posi(3,ival)=ic3
         dist(ival)=ic1**2+ic2**2+ic3**2
       enddo
     enddo
   enddo
   iorden=dist

   call clasifica(mval,iorden)

   libre=.true.

   iatom=0
   do ival=2,mval
     bucle_l: do lval=1,mval
       if(libre(lval).and.(dist(lval).eq.iorden(ival))) exit bucle_l
     enddo bucle_l
     libre(lval)=.false.
     iatom=iatom+1
     patom(:,iatom)=posi(:,lval)
     if(iatom.eq.ngatom) exit
   enddo
     
  end subroutine reticulo

  subroutine clasifica(mval,iorden)
   integer (kind=i4), intent(in) :: mval
   integer (kind=i4), intent(inout) :: iorden(mval)
   integer (kind=i4) :: inc,i,j
   integer (kind=i4) :: v

   inc=1
   do
     inc=3*inc+1
     if(inc.gt.mval) exit
   end do

   do
     inc=inc/3
     do i=inc+1,mval
       v=iorden(i)
       j=i
       do
         if(iorden(j-inc).le.v) exit
         iorden(j)=iorden(j-inc)
         j=j-inc
         if(j.le.inc) exit
       end do
       iorden(j)=v
     end do
     if(inc.le.1) exit
   end do

  end subroutine clasifica

end module mconfiguraciones
