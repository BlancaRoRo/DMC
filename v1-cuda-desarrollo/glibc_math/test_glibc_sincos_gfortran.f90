! test_glibc_sincos_gfortran.f90
!
! Compara dsin/dcos intrinsecas de gfortran (glibc 2.39 real de esta
! maquina) con los mismos valores que test_glibc_sincos.
!
! Compilar y ejecutar: ver docs-kernels/glibc_math.md
! gfortran -ffp-contract=off test_glibc_sincos_gfortran.f90 -o test_glibc_sincos_gfortran

program test_glibc_sincos_gfortran
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i4), parameter :: n = 23
 real(kind=r8) :: x_h(n)
 integer(kind=i4) :: i

  x_h = (/ 0.0_r8, 0.001_r8, 0.1_r8, 0.126_r8, 0.5_r8, 0.855469_r8, &
           1.0_r8, 1.5707963267948966_r8, 2.0_r8, 2.426265_r8, &
           3.14159265358979_r8, 5.0_r8, 10.0_r8, 100.0_r8, 1000.0_r8, &
           -1.5_r8, -3.14159265358979_r8, &
           1.05d8, 1.06d8, 1.0d9, 1.0d15, 1.0d100, -1.0d20 /)

  do i = 1, n
    write(*,*)
    write(*,'(a,i0,a,es24.17)') '--- #', i, '  x=', x_h(i)
    write(*,'(a,es24.17)') '  dsin gfortran =', dsin(x_h(i))
    write(*,'(a,es24.17)') '  dcos gfortran =', dcos(x_h(i))
  enddo

end program test_glibc_sincos_gfortran
