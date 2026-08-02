module mrandom

 use mrandom2

  implicit none
  integer, private, parameter :: i4=selected_int_kind(9)
  integer, private, parameter :: i8=selected_int_kind(15)
  integer, private, parameter :: r8=selected_real_kind(15,9)

  integer(kind=i8), private, save :: irn = 1_i8

  real(kind=r8), private, parameter :: pi=3.1415926535897930_r8

 contains

  function rn1()
   real(kind=r8) :: rn1

    call rand1(rn1,irn)

  end function rn1

  subroutine  randv3(rn3)
   real(kind=r8), intent (out) :: rn3(3)

    rn3(1)=rn1()
    rn3(2)=rn1()
    rn3(3)=rn1()

  end subroutine randv3

  subroutine gauss3(gvar3)
   real(kind=r8), intent (out) :: gvar3(3)
   real(kind=r8) :: xl,arg

    arg=2.0_r8*pi*rn1()
    xl=sqrt(-2.0_r8*log(rn1()))
    gvar3(1)=xl*sin(arg)
    gvar3(2)=xl*cos(arg)
    arg=2.0_r8*pi*rn1()
    xl=sqrt(-2.0_r8*log(rn1()))
    gvar3(3)=xl*sin(arg)

  end subroutine gauss3


  subroutine fijasemilla(irnin)
   integer(kind=i8) :: mask48
   integer(kind=i8), intent(in) :: irnin

    mask48 = ishft(1_i8, 48_i8) - 1_i8
    irn=iand(irnin,mask48)

  end subroutine fijasemilla

  subroutine sacasemilla(irnout)
   integer(kind=i8), intent(out) :: irnout

    irnout=irn

  end subroutine sacasemilla

end module mrandom
