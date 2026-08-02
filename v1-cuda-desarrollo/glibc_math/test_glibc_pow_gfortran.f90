! test_glibc_pow_gfortran.f90
!
! Compara x**y intrinseca de gfortran (glibc 2.39 real de esta
! maquina) con los mismos valores que test_glibc_pow (en
! glibc_pow.cuf).
!
! Compilar y ejecutar: ver docs-kernels/glibc_math.md
! gfortran -ffp-contract=off test_glibc_pow_gfortran.f90 -o test_glibc_pow_gfortran

program test_glibc_pow_gfortran
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i4), parameter :: n = 30
 real(kind=r8) :: x_h(n), y_h(n)
 integer(kind=i4) :: i

  x_h( 1)=0.3d0;    y_h( 1)=9.763290d0
  x_h( 2)=0.5d0;    y_h( 2)=9.763290d0
  x_h( 3)=0.86602540378443864d0; y_h( 3)=9.763290d0
  x_h( 4)=1.0d0;    y_h( 4)=9.763290d0
  x_h( 5)=2.0d0;    y_h( 5)=9.763290d0
  x_h( 6)=5.0d0;    y_h( 6)=9.763290d0
  x_h( 7)=20.0d0;   y_h( 7)=9.763290d0
  x_h( 8)=50.0d0;   y_h( 8)=9.763290d0

  x_h( 9)=0.3d0;    y_h( 9)=4.725025d0
  x_h(10)=0.86602540378443864d0; y_h(10)=4.725025d0
  x_h(11)=2.0d0;    y_h(11)=4.725025d0
  x_h(12)=20.0d0;   y_h(12)=4.725025d0

  x_h(13)=0.3d0;    y_h(13)=3.155952d0
  x_h(14)=0.86602540378443864d0; y_h(14)=3.155952d0
  x_h(15)=2.0d0;    y_h(15)=3.155952d0
  x_h(16)=20.0d0;   y_h(16)=3.155952d0

  x_h(17)=0.3d0;    y_h(17)=11.036848d0
  x_h(18)=0.86602540378443864d0; y_h(18)=11.036848d0
  x_h(19)=2.0d0;    y_h(19)=11.036848d0
  x_h(20)=20.0d0;   y_h(20)=11.036848d0

  x_h(21)=0.86602540378443864d0; y_h(21)=1.0d0
  x_h(22)=2.0d0;    y_h(22)=1.0d0

  x_h(23)=1.0d-8;   y_h(23)=9.763290d0
  x_h(24)=1.0d8;    y_h(24)=9.763290d0
  x_h(25)=1.0d-3;   y_h(25)=11.036848d0
  x_h(26)=1.0d3;    y_h(26)=11.036848d0
  x_h(27)=0.86602540378443864d0; y_h(27)=100.0d0
  x_h(28)=0.86602540378443864d0; y_h(28)=0.001d0
  x_h(29)=1.0d0;    y_h(29)=1.0d0
  x_h(30)=7.3d0;    y_h(30)=0.5d0

  do i = 1, n
    write(*,*)
    write(*,'(a,i0,a,es16.8,a,es16.8)') '--- #', i, '  x=', x_h(i), '  y=', y_h(i)
    write(*,'(a,es24.17)') '  x**y gfortran=', x_h(i)**y_h(i)
  enddo

end program test_glibc_pow_gfortran
