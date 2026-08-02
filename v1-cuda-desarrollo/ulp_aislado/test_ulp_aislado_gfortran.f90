! test_ulp_aislado_gfortran.f90
!
! Mismos valores que test_ulp_aislado (en ulp_aislado.cuf), pero
! compilado con gfortran -- sin nada de CUDA, tercera pata de CPU.
!
! Compilar y ejecutar: ver el bloque de comandos en
! docs-kernels/ulp_aislado.md

program test_ulp_aislado_gfortran
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i4), parameter :: n = 8
 real(kind=r8) :: a_h(n), b_h(n), c_h(n), x_h(n)
 real(kind=r8) :: y(n), e(n), co(n), si(n)
 integer(kind=i4) :: i

  a_h = (/ 1.234567891011_r8, 7.13500000001_r8, 0.98765432101_r8, &
           15.632178901234_r8, -3.33333333333_r8, 2.71828182845_r8, &
           0.10000000001_r8, 9.99999999999_r8 /)
  b_h = (/ 2.345678910111_r8, -0.928400000002_r8, 4.5678901234_r8, &
           0.500000000001_r8, 6.66666666667_r8, -1.41421356237_r8, &
           8.88888888889_r8, 0.00001000001_r8 /)
  c_h = (/ 3.456789101112_r8, 15.6321000003_r8, -2.3456789012_r8, &
           7.777777777_r8, 0.33333333333_r8, 3.14159265359_r8, &
           -0.5000000001_r8, 1.00000000001_r8 /)
  x_h = (/ 0.1_r8, 0.5_r8, 1.0_r8, 1.5707963267948966_r8, &
           3.14159265358979_r8, 2.71828182845905_r8, -0.987654321_r8, 5.0_r8 /)

  do i = 1, n
    y(i)  = a_h(i)*b_h(i) + c_h(i)
    e(i)  = dexp(x_h(i))
    co(i) = dcos(x_h(i))
    si(i) = dsin(x_h(i))
  enddo

  write(*,*) '=== FMA aislada: y = a*b+c ==='
  do i = 1, n
    write(*,'(a,i0,a,f22.16)') '  #',i,'  gfortran=',y(i)
  enddo

  write(*,*)
  write(*,*) '=== dexp(x) aislada ==='
  do i = 1, n
    write(*,'(a,i0,a,f22.16)') '  #',i,'  gfortran=',e(i)
  enddo

  write(*,*)
  write(*,*) '=== dcos(x) aislada ==='
  do i = 1, n
    write(*,'(a,i0,a,f22.16)') '  #',i,'  gfortran=',co(i)
  enddo

  write(*,*)
  write(*,*) '=== dsin(x) aislada ==='
  do i = 1, n
    write(*,'(a,i0,a,f22.16)') '  #',i,'  gfortran=',si(i)
  enddo

end program test_ulp_aislado_gfortran
