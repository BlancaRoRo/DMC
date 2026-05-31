program test_rand1p
  implicit none
  integer, parameter :: i8 = selected_int_kind(15)
  integer, parameter :: r8 = selected_real_kind(15,9)

  integer(kind=i8) :: irn, mask24, mask48, m21, m22, is1, is2
  integer(kind=i8), parameter :: mult2 = 34522712143931_i8
  integer(kind=i8), parameter :: iadd2 = 55789347517_i8
  real(kind=r8) :: rn, twom48

  twom48 = 2.0_r8**(-48)
  irn = 11_i8

  mask24 = ishft(1_i8, 24_i8) - 1_i8
  mask48 = ishft(1_i8, 48_i8) - 1_i8
  m21    = iand(mult2, mask24)
  m22    = iand(ishft(mult2, -24_i8), mask24)

  is2 = iand(ishft(irn, -24_i8), mask24)
  is1 = iand(irn, mask24)
  irn = iand(ishft(iand(is1*m22+is2*m21, mask24), 24_i8)+is1*m21+iadd2, mask48)
  rn  = ior(irn, 1_i8) * twom48

  write(*,*) 'mask24=', mask24
  write(*,*) 'mask48=', mask48
  write(*,*) 'm21=', m21
  write(*,*) 'm22=', m22
  write(*,*) 'irn after 1 step from 11:', irn
  write(*,*) 'rn:', rn
end program test_rand1p
