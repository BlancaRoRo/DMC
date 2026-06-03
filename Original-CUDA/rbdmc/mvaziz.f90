module mvaziz

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: r8=selected_real_kind(15,9)

  real(kind=r8), private, save :: a_aziz,alpha_aziz,c6_aziz,c7_aziz,c8_aziz, &
 &                                d_aziz,eps_aziz,rm_aziz

 contains

  function aziz_nuevo(r)
   real(kind=r8) :: aziz_nuevo
   real(kind=r8), intent (in) :: r
   real(kind=r8), parameter :: a=1.84431010d5
   real(kind=r8), parameter :: alpha=10.433295370_r8
   real(kind=r8), parameter :: c6=1.367452140_r8
   real(kind=r8), parameter :: c8=0.421238070_r8
   real(kind=r8), parameter :: c10=0.174733180_r8
   real(kind=r8), parameter :: beta=-2.279651050_r8
   real(kind=r8), parameter :: D=1.48260_r8
   real(kind=r8), parameter :: eps=10.9480_r8
   real(kind=r8), parameter :: rm=2.9630_r8

   real(kind=r8) :: x,f,vv

    x=r/rm
    if(x.lt.D)  then
      f=exp(-(d/x-1.0_r8)**2)
    else
      f=1.0_r8
    endif
    vv=a*exp(-alpha*x+beta*x**2)- f*(c6/x**6+c8/x**8+c10/x**10)
    aziz_nuevo=vv*eps

   end function aziz_nuevo

  function aziz_viejo(r)
   real(kind=r8) :: aziz_viejo
   real(kind=r8), intent (in) :: r
   real(kind=r8),parameter :: a=0.54485040d6
   real(kind=r8),parameter :: alpha=13.3533840_r8
   real(kind=r8),parameter :: c6=1.37324120_r8
   real(kind=r8),parameter :: c8=0.42537850_r8
   real(kind=r8),parameter :: c10=0.1781000_r8
   real(kind=r8),parameter :: d=1.2413140_r8
   real(kind=r8),parameter :: eps=10.80_r8
   real(kind=r8),parameter :: rm=2.96730_r8

   real(kind=r8) :: x,f,vv

    x=r/rm
    if(x.lt.D)  then
      f=exp(-(d/x-1.0_r8)**2)
    else
      f=1.0_r8
    endif
    vv=a*exp(-alpha*x)-f*(c6/x**6+c8/x**8+c10/x**10)
    aziz_viejo=vv*eps

  end function aziz_viejo
  
  function  azizgen(r)
   real(kind=r8) :: azizgen
   real(kind=r8),intent (in) :: r
   real(kind=r8) :: x,f,vv

    x=r/rm_aziz
    if(x.lt.d_aziz)  then
      f=exp(-(d_aziz/x-1.0_r8)**2)
    else
      f=1.0_r8
    endif
    vv=a_aziz*exp(-alpha_aziz*x)-f*(c6_aziz/x**6+c7_aziz/x**7+c8_aziz/x**8)
    azizgen=vv*eps_aziz

  end function azizgen

  subroutine leeazizgen(fichpot)
   character*(*), intent (in) ::  fichpot
   character(len=50) :: referencia

    open(unit=10,file=fichpot,status="old")
      read(10,'(a)') referencia
      read(10,*) a_aziz
      read(10,*) alpha_aziz
      read(10,*) c6_aziz
      read(10,*) c7_aziz
      read(10,*) c8_aziz
      read(10,*) d_aziz
      read(10,*) eps_aziz
      read(10,*) rm_aziz
    close(10)

    write(6,'("Referencia potencial ",t30,a)') trim(referencia)
    write(6,'("Azizpot a=",t20,f20.10)') a_aziz
    write(6,'("Azizpot alpha=",t20,f20.15)') alpha_aziz 
    write(6,'("Azizpot c6=",t20,f20.14)') c6_aziz 
    write(6,'("Azizpot c7=",t17,es25.18)') c7_aziz 
    write(6,'("Azizpot c8=",t20,f20.10)') c8_aziz 
    write(6,'("Azizpot d=",t20,f20.17)') d_aziz 
    write(6,'("Azizpot eps=",t20,f20.12)') eps_aziz
    write(6,'("Azizpot rm=",t20,f20.12)') rm_aziz 

  end subroutine leeazizgen

  subroutine sacaaziz(paraziz)
   integer(kind=i4) ,parameter :: naziz=8
   real(kind=r8), intent (out) :: paraziz(naziz)

      paraziz(1)=a_aziz
      paraziz(2)=alpha_aziz
      paraziz(3)=c6_aziz
      paraziz(4)=c7_aziz
      paraziz(5)=c8_aziz
      paraziz(6)=d_aziz
      paraziz(7)=eps_aziz
      paraziz(8)=rm_aziz

  end subroutine sacaaziz

  subroutine meteaziz(paraziz)
   integer(kind=i4) , parameter  :: naziz=8
   real(kind=r8), intent (in) :: paraziz(naziz)

      a_aziz=    paraziz(1)
      alpha_aziz=paraziz(2)
      c6_aziz=   paraziz(3)
      c7_aziz=   paraziz(4)
      c8_aziz=   paraziz(5)
      d_aziz=    paraziz(6)
      eps_aziz=  paraziz(7)
      rm_aziz=   paraziz(8)

  end subroutine meteaziz

 end module mvaziz
