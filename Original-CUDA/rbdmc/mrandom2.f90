module mrandom2

   implicit none
   integer, private, parameter :: i4=selected_int_kind(9)
   integer, private, parameter :: i8=selected_int_kind(15)
   integer, private, parameter :: r8=selected_real_kind(15,9)

contains
   subroutine rand1(rn,irn)
    integer(kind=i8), intent (inout) :: irn
    real(kind=r8), intent (out) :: rn

    integer(kind=i8),  parameter :: mask24 = ishft(1_i8,24)-1
    integer(kind=i8),  parameter :: mask48 = ishft(1_i8,48_i8)-1_i8
    real(kind=r8),  parameter :: twom48=2.0_r8**(-48)
    integer(kind=i8),  parameter :: mult1 = 44485709377909_i8
    integer(kind=i8),  parameter :: m11 = iand(mult1,mask24)
    integer(kind=i8),  parameter :: m12 = iand(ishft(mult1,-24),mask24)
    integer(kind=i8),  parameter :: iadd1 = 96309754297_i8

    integer(kind=i8) :: is1,is2

     is2=iand(ishft(irn,-24),mask24)
     is1=iand(irn,mask24)
     irn=iand(ishft(iand(is1*m12+is2*m11,mask24),24)+is1*m11+iadd1,mask48)
     rn=ior(irn,1_i8)*twom48

   end subroutine rand1

   subroutine rand1p(rn,irn)
    integer(kind=i8), intent (inout) :: irn
    real(kind=r8), intent (out) :: rn

    integer(kind=i8),  parameter :: mult2 = 34522712143931_i8
    integer(kind=i8),  parameter :: iadd2 = 55789347517_i8
    real(kind=r8),     parameter :: twom48 = 2.0_r8**(-48)
    integer(kind=i8) :: mask24, mask48, m21, m22, is1, is2

    mask24 = ishft(1_i8, 24_i8) - 1_i8
    mask48 = ishft(1_i8, 48_i8) - 1_i8
    m21    = iand(mult2, mask24)
    m22    = iand(ishft(mult2, -24_i8), mask24)

    is2 = iand(ishft(irn, -24_i8), mask24)
    is1 = iand(irn, mask24)
    irn = iand(ishft(iand(is1*m22+is2*m21, mask24), 24_i8)+is1*m21+iadd2, mask48)
    rn  = ior(irn, 1_i8) * twom48

   end subroutine rand1p

end module mrandom2
