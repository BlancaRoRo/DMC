! test_glibc_exp_gfortran.f90
!
! Compara dexp intrinseca de gfortran (glibc 2.39 real de esta maquina)
! con los mismos valores que test_glibc_exp (en glibc_exp.cuf).
!
! Compilar y ejecutar: ver docs-kernels/glibc_math.md
! gfortran -ffp-contract=off test_glibc_exp_gfortran.f90 -o test_glibc_exp_gfortran

program test_glibc_exp_gfortran
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i4), parameter :: n = 14
 real(kind=r8) :: x_h(n)
 integer(kind=i4) :: i

  x_h = (/ 0.0_r8, 1.0_r8, -1.0_r8, 0.5_r8, -0.5_r8, 2.71828182845905_r8, &
           -3.33333333333333_r8, 1.0d-30, -1.0d-30, 20.0_r8, -20.0_r8, &
           700.0_r8, -700.0_r8, 1.5707963267948966_r8 /)

  do i = 1, n
    write(*,*)
    write(*,'(a,i0,a,es24.17)') '--- #', i, '  x=', x_h(i)
    write(*,'(a,es24.17)') '  dexp gfortran =', dexp(x_h(i))
  enddo

end program test_glibc_exp_gfortran
