! test_glibc_acos_gfortran.f90
!
! Compara dacos intrinseca de gfortran (glibc 2.39 real de esta
! maquina) con los mismos valores que test_glibc_acos (en
! glibc_acos.cuf).
!
! Compilar y ejecutar: ver docs-kernels/glibc_math.md
! gfortran -ffp-contract=off test_glibc_acos_gfortran.f90 -o test_glibc_acos_gfortran

program test_glibc_acos_gfortran
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i4), parameter :: n = 26
 real(kind=r8) :: x_h(n)
 integer(kind=i4) :: i

  x_h = (/ &
    0.0_r8, 1.0_r8, -1.0_r8, &
    0.05_r8, -0.05_r8, &
    0.3_r8, -0.3_r8, &
    0.6_r8, -0.6_r8, &
    0.8_r8, -0.8_r8, &
    0.94_r8, -0.94_r8, &
    0.96_r8, -0.96_r8, &
    0.99_r8, -0.99_r8, 0.999999_r8, -0.999999_r8, &
    0.1052984383_r8, -0.1052984383_r8, &
    -0.4612990046_r8, -0.6666100579_r8, &
    -0.5773502691896258_r8, &
    1.0d-30, -1.0d-30 /)

  do i = 1, n
    write(*,*)
    write(*,'(a,i0,a,es24.17)') '--- #', i, '  x=', x_h(i)
    write(*,'(a,es24.17)') '  dacos gfortran =', dacos(x_h(i))
  enddo

end program test_glibc_acos_gfortran
