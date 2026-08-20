module mimagina

 use mtipos
 use mlegendre

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: r8=selected_real_kind(15,9)

  integer(kind=i4), parameter :: npol=5
  integer(kind=i4), parameter :: ndt=200000

  real(kind=r8), save, private :: dcm1(ndt),dcm2(ndt),dcmb(ndt)
  real(kind=r8), save, private :: cjdt1(npol,ndt),cjdt2(npol,ndt),cjdtb(npol,ndt)
  real(kind=r8), save, private :: denob(ndt)
  real(kind=r8), save, private :: den1

  integer(kind=i4), save, private :: imolec
  real(kind=r8), save, private :: dt,lambda,brot

  character(len=15) :: fichdt,fichcl(npol)

 contains

  subroutine iniimagina(nombre,imolin,dtin,lain,brin)
   character(len=10), intent (in) :: nombre
   integer(kind=i4), intent(in) :: imolin
   real(kind=r8), intent(in) :: dtin,lain,brin
   character(len=1) :: jval
   integer(kind=i4) :: il

    imolec=imolin
    dt=dtin
    lambda=lain
    brot=brin

    fichdt=trim("C_CM."//nombre)
    do il=1,npol
      write(jval,'(i1)') il
      fichcl(il)=trim("C_"//jval//"."//nombre)
    enddo


  end subroutine iniimagina

  subroutine difusgethis(npolout,ndtout)
   integer(kind=i4), intent(out) :: npolout,ndtout

    npolout=npol
    ndtout=ndt

  end subroutine difusgethis

  subroutine difusceroini

   dcm1=0.0_r8
   dcm2=0.0_r8
   cjdt1=0.0_r8
   cjdt2=0.0_r8

   den1=0.0_r8

  end subroutine difusceroini

  subroutine difusceroblo

   dcmb=0.0_r8
   cjdtb=0.0_r8

   denob=0.0_r8

  end subroutine difusceroblo

  subroutine difusfijaorigen(nwpaso,wsim)
   integer(kind=i4), intent (in) :: nwpaso
   type(walker), intent (inout) :: wsim(nwpaso)
   integer(kind=i4) :: iwalker

    do iwalker=1,nwpaso
      wsim(iwalker)%eje0=wsim(iwalker)%sprop(3)
      wsim(iwalker)%pos0=wsim(iwalker)%atom(imolec)
    enddo

  end subroutine difusfijaorigen

  subroutine difussumapaso(idt,nwpaso,wsim)
   integer(kind=i4), intent (in) :: idt
   integer(kind=i4), intent (in) :: nwpaso
   type(walker), intent (in) :: wsim(nwpaso)
   type(vec3) :: rij
   real(kind=r8) :: r2,rirj,riri,rjrj
   real(kind=r8) :: ct,pl(0:npol)
   integer(kind=i4) :: iwalker
   integer(kind=i4) :: ipol

    do iwalker=1,nwpaso
      rij=wsim(iwalker)%atom(imolec)-wsim(iwalker)%pos0
      r2=dot_product(rij%comp,rij%comp)
      dcmb(idt)=dcmb(idt)+r2
      riri=dot_product(wsim(iwalker)%sprop(3)%comp,wsim(iwalker)%sprop(3)%comp)
      rjrj=dot_product(wsim(iwalker)%eje0%comp,wsim(iwalker)%eje0%comp)
      rirj=dot_product(wsim(iwalker)%sprop(3)%comp,wsim(iwalker)%eje0%comp)
      ct=rirj/sqrt(riri*rjrj)
      call  calpleg(npol,ct,pl)
      do ipol=1,npol
        cjdtb(ipol,idt)=cjdtb(ipol,idt)+pl(ipol)
      enddo
      denob(idt)=denob(idt)+1.0_r8
    enddo

  end subroutine difussumapaso

  subroutine difussumablo(ndifus)
   integer(kind=i4), intent (in) :: ndifus
   integer(kind=i4) :: idt,ipol

   do idt=1,ndifus
     dcmb(idt)=dcmb(idt)/denob(idt)
     dcm1(idt)=dcm1(idt)+dcmb(idt)
     dcm2(idt)=dcm2(idt)+dcmb(idt)**2
     do ipol=1,npol
       cjdtb(ipol,idt)=cjdtb(ipol,idt)/denob(idt)
       cjdt1(ipol,idt)=cjdt1(ipol,idt)+cjdtb(ipol,idt)
       cjdt2(ipol,idt)=cjdt2(ipol,idt)+cjdtb(ipol,idt)**2
     enddo
   enddo

   den1=den1+1.0_r8

  end subroutine difussumablo

  subroutine difusgetdatostot(ipol,ndifus,dens1v,dens1e)
  integer(kind=i4), intent (in) :: ipol,ndifus
  real(kind=r8), intent (out) :: dens1v(ndifus),dens1e(ndifus)
  integer(kind=i4) :: idifus

   select case(ipol)
     case (0)
       dens1v(1:ndifus)=dcm1(1:ndifus)
       dens1e(1:ndifus)=dcm2(1:ndifus)
     case (1:npol)
       do idifus=1,ndifus
         dens1v(idifus)=cjdt1(ipol,idifus)
         dens1e(idifus)=cjdt2(ipol,idifus)
       enddo
   end select

  end subroutine difusgetdatostot

  subroutine difusputdatostot(ipol,ndifus,dens1v,dens1e)
  integer(kind=i4), intent (in) :: ipol,ndifus
  real(kind=r8), intent (in) :: dens1v(ndifus),dens1e(ndifus)
  integer(kind=i4) :: idifus

   select case(ipol)
     case (0)
       dcm1(1:ndifus)=dens1v(1:ndifus)
       dcm2(1:ndifus)=dens1e(1:ndifus)
     case (1:npol)
       do idifus=1,ndifus
         cjdt1(ipol,idifus)=dens1v(idifus)
         cjdt2(ipol,idifus)=dens1e(idifus)
       enddo
   end select

  end subroutine difusputdatostot

  subroutine difusgetdeno(den1val)
   real(kind=r8), intent (out) :: den1val

     den1val=den1

  end subroutine difusgetdeno

  subroutine difusputdeno(den1val)
   real(kind=r8), intent (in) :: den1val

     den1=den1val

  end subroutine difusputdeno


  subroutine difusfin(ndifus)
   integer(kind=i4), intent (in) :: ndifus
   real(kind=r8) :: xdt,den2
   integer(kind=i4) :: idt
   integer(kind=i4) :: ipol
   integer(kind=i4) :: ifich

    ifich=40
    open(ifich,file=fichdt,status="unknown")
    do ipol=1,npol
      ifich=ifich+1
      open(ifich,file=fichcl(ipol),status="unknown")
    enddo

    den2=den1-1.0_r8
    den2=max(den1,1.0_r8)

    do idt=1,ndifus
      xdt=idt*dt
      dcm1(idt)=dcm1(idt)/den1
      dcm2(idt)=dcm2(idt)/den1
      dcm2(idt)=sqrt((dcm2(idt)-dcm1(idt)**2)/den2)
      do ipol=1,npol
        cjdt1(ipol,idt)=cjdt1(ipol,idt)/den1
        cjdt2(ipol,idt)=cjdt2(ipol,idt)/den1
        cjdt2(ipol,idt)=sqrt((cjdt2(ipol,idt)-cjdt1(ipol,idt)**2)/den2)
      enddo
      ifich=40
      write(ifich,'(i5,f10.5,2f20.10)') idt,xdt,dcm1(idt)/(6.0_r8*xdt*lambda),  &
 &                dcm2(idt)/(6.0_r8*xdt*lambda)
      do ipol=1,npol
        ifich=ifich+1
        write(ifich,'(f10.5,2f20.10)') xdt,cjdt1(ipol,idt),-log(cjdt1(ipol,idt))/xdt
      enddo
    enddo

    ifich=40
    close(ifich)
    do ipol=1,npol
      ifich=ifich+1
      close(ifich)
    enddo

  end subroutine difusfin

end module mimagina
