! test_hehe_gfortran.f90
!
! Mismos 7 valores de r que test_V_hehe_Vp_hehe (en el .cuf), pero sin
! nada de CUDA: llama directamente a V_hehe/Vp_hehe de bh_heh2m.f
! compilado con gfortran. Comprueba que la referencia de CPU no depende
! de si la compila nvfortran o gfortran.
!
! Compilar y ejecutar:
!
!   gfortran -ffixed-line-length-132 bh_heh2m.f test_hehe_gfortran.f90 -o test_hehe_gfortran
!   ./test_hehe_gfortran

program test_hehe_gfortran
 implicit none
 double precision :: V_hehe, Vp_hehe
 external :: V_hehe, Vp_hehe

 integer, parameter :: n = 7
 double precision :: r_h(n)
 integer :: i

  r_h = (/ 2.0d0, 3.0d0, 4.0d0, 5.0d0, 6.0d0, 8.0d0, 12.0d0 /)

  do i = 1, n
    write(*,*)
    write(*,'(a,i0,a,f8.4)') '--- par ', i, '   r = ', r_h(i)
    write(*,'(a,es16.8)') '  V_hehe  gfortran:', V_hehe(r_h(i))
    write(*,'(a,es16.8)') '  Vp_hehe gfortran:', Vp_hehe(r_h(i))
    write(*,'(a,es24.17)') '  HP V_hehe  gfortran:', V_hehe(r_h(i))
    write(*,'(a,es24.17)') '  HP Vp_hehe gfortran:', Vp_hehe(r_h(i))
  enddo

end program test_hehe_gfortran
