! test_legendre_gfortran.f90
!
! Mismos datos sinteticos que legendre_gpu.cuf (test_legendre), pero sin
! nada de CUDA: solo llama al mlegendre.f90 original, compilado con
! gfortran. Sirve para comprobar que la "referencia de confianza" en CPU
! no depende de si la compila nvfortran o gfortran -- es decir, que el
! oraculo contra el que comparamos la GPU es el mismo venga de donde venga.
!
! Compilar y ejecutar:
!
!   gfortran mlegendre.f90 test_legendre_gfortran.f90 -o test_legendre_gfortran
!   ./test_legendre_gfortran

program test_legendre_gfortran
 use mlegendre, only: calpleg, calderpleg
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i4), parameter :: l = 4
 integer(kind=i4), parameter :: n = 6
 real(kind=r8) :: x_h(n)
 real(kind=r8) :: pl_cpu(0:l), d1_cpu(0:l), d2_cpu(0:l)
 integer(kind=i4) :: i

  x_h = (/ -1.0_r8, -0.5_r8, 0.0_r8, 0.3_r8, 0.7_r8, 1.0_r8 /)

  do i = 1, n
    call calpleg(l, x_h(i), pl_cpu)
    call calderpleg(l, x_h(i), pl_cpu, d1_cpu, d2_cpu)

    write(*,*)
    write(*,'(a,i0,a,f8.4)') '--- walker ', i, '   x = ', x_h(i)
    write(*,'(a,5f14.8)') '  pl   gfortran:', pl_cpu
    write(*,'(a,5f14.8)') '  d1pl gfortran:', d1_cpu
    write(*,'(a,5f14.8)') '  d2pl gfortran:', d2_cpu
    write(*,'(a,5es24.17)') '  HP pl   gfortran:', pl_cpu
    write(*,'(a,5es24.17)') '  HP d1pl gfortran:', d1_cpu
    write(*,'(a,5es24.17)') '  HP d2pl gfortran:', d2_cpu
  enddo

end program test_legendre_gfortran
