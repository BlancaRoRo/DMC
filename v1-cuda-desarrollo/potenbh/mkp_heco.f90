module mkp_heco

 implicit none
 integer, parameter, private :: i4=selected_int_kind(9)
 integer, parameter, private :: r8=selected_real_kind(15,9)

  real(kind=r8), parameter, private :: r1e=2.13220_r8   !en unidades atomicas
  real(kind=r8), parameter, private :: rbohr=0.529177210670_r8
  integer(kind=i4), parameter, private :: numterms=4
  integer(kind=i4), parameter, private ::nn=50,maxpts=2000,nnn=nn*nn
  real(kind=r8), private, save :: x1a(NN),x2a(NN),x3a(NN)
  real(kind=r8), private, save :: ya(nn,nnn)
  integer(kind=i4), private, save :: m1,m2,m3,n2
  integer(kind=i4), private, save :: ind2(maxpts),ind3(maxpts)


contains

 subroutine kp_leevheco(fichpot)
  real(kind=r8), parameter :: dtorad=3.1415926535897930_r8/180.0_r8
  character*(*), intent (in) :: fichpot
  character(len=120) :: label
  integer(kind=i4) :: np,inn,i,j,k
  character(len=50) :: referencia

   open(10,file=fichpot,status="old",form="formatted")
   read(10,'(a120)') label
   write(6,'(a25)') label
   write(6,'(1x,"kpcoef: polynomial fit degree=    ",i4)') numterms
   write(6,'(1x,"CO bond distance in the fit in au",f10.5)') r1e
   write(6,'(1x,"CO bond distance in the fit in A",f10.5)') r1e*rbohr

   ind2=0
   ind3=0
   x1a=0.0_r8
   x2a=0.0_r8
   x3a=0.0_r8
   ya=0.0_r8

   read (10,*) m1,m2,m3
   n2=m2*m3
   np=0
   do i=1,m1
     inn=0
     do j=1,m2
       do k=1,m3
         inn=inn+1
         np=np+1
         read(10,*) x1a(i),x2a(j),x3a(k),ya(i,inn)
         ind2(np)=j
         ind3(np)=k
       enddo
     enddo
   enddo

   close (10)

   do k=1,m3
       x3a(k)=(1.0_r8-cos(dtorad*x3a(k)))/2.0_r8
   enddo

   referencia="He-CO Peterson and McBane,  JCP 123, 084314 (2005)"
   write(6,'("Referencia potencial ",t30,a)') trim(referencia)

 end subroutine kp_leevheco

 subroutine kp_iniciavheco

  call ajusta(m1,m2,m3,n2,numterms,ind2,ind3,r1e,x1a,x2a,x3a,ya)

 end subroutine kp_iniciavheco

 function hecokp2d(r,ct)     !r anstroms , hecokp2d en cm-1
  real(kind=r8) :: hecokp2d
  real(kind=r8), intent (in) :: r,ct
  real(kind=r8) :: vr1coef(numterms)
  real(kind=r8) :: rau
  real(kind=r8), parameter :: rv=0.007760_r8,r2v=0.004140_r8,r3v=0.000120_r8  !v=0
! real(kind=r8), parameter :: rv=0.023320_r8,r2v=0.012840_r8,r3v=0.000770_r8  !v=1
! real(kind=r8), parameter :: rv=0.039070_r8,r2v=0.022160_r8,r3v=0.002110_r8  !v=2

   rau=r/rbohr
   call kpcoef(rau,ct,vr1coef)  !r unidades atomicas, hecokp2d en cm-1


    hecokp2d=vr1coef(1)+rv*vr1coef(2)+r2v*vr1coef(3)+r3v*vr1coef(4)

 end function hecokp2d

 subroutine sacakp(m1kp,m2kp,m3kp,n2kp,ind2kp,ind3kp,x1akp,x2akp,x3akp,yaekp)
  integer(kind=i4), intent (out) ::m1kp,m2kp,m3kp,n2kp
  integer(kind=i4), intent (out) ::ind2kp(maxpts),ind3kp(maxpts)
  real(kind=r8), intent (out) ::x1akp(nn),x2akp(nn),x3akp(nn),yaekp(nn*nnn)
  integer(kind=i4) :: ii,iii,jj

   m1kp=m1
   m2kp=m2
   m3kp=m3
   n2kp=n2
   ind2kp=ind2
   ind3kp=ind3
   x1akp=x1a
   x2akp=x2a
   x3akp=x3a
   jj=0
   do iii=1,nnn
     do ii=1,nn
       jj=jj+1
       yaekp(jj)=ya(ii,iii)
     enddo
   enddo


 end subroutine sacakp   


 subroutine metekp(m1kp,m2kp,m3kp,n2kp,ind2kp,ind3kp,x1akp,x2akp,x3akp,yaekp)
  integer(kind=i4), intent (in) ::m1kp,m2kp,m3kp,n2kp
  integer(kind=i4), intent (in) ::ind2kp(maxpts),ind3kp(maxpts)
  real(kind=r8), intent (in) ::x1akp(nn),x2akp(nn),x3akp(nn),yaekp(nn*nnn)
  integer(kind=i4) :: ii,iii,jj

   m1=m1kp
   m2=m2kp
   m3=m3kp
   n2=n2kp
   ind2=ind2kp
   ind3=ind3kp
   x1a=x1akp
   x2a=x2akp
   x3a=x3akp
   jj=0
   do iii=1,nnn
     do ii=1,nn
       jj=jj+1
       ya(ii,iii)=yaekp(jj)
     enddo
   enddo

 end subroutine metekp   

end module mkp_heco
