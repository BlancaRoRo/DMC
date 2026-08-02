! test_angle_gfortran.f90
!
! Mismos 5 pares de vectores que test_angle_scalar_vec (en el .cuf), pero
! sin nada de CUDA: llama directamente a angle/scalar_product/vec_norm de
! bh_heh2m.f compilado con gfortran. Comprueba que la referencia de CPU
! no depende de si la compila nvfortran o gfortran.
!
! Compilar y ejecutar:
!
!   gfortran -ffixed-line-length-132 bh_heh2m.f test_angle_gfortran.f90 -o test_angle_gfortran
!   ./test_angle_gfortran

program test_angle_gfortran
 implicit none
 external :: angle, scalar_product, vec_norm

 integer, parameter :: n = 22
 double precision :: vec1_h(3,n), vec2_h(3,n)
 double precision :: ang_cpu, sprod_cpu, norm_cpu
 integer :: i

  vec1_h(:,1) = (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,1) = (/  1.0d0, 0.0d0, 0.0d0 /)
  vec1_h(:,2) = (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,2) = (/ -1.0d0, 0.0d0, 0.0d0 /)
  vec1_h(:,3) = (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,3) = (/  0.0d0, 1.0d0, 0.0d0 /)
  vec1_h(:,4) = (/ 1.0d0, 2.0d0, 3.0d0 /); vec2_h(:,4) = (/  4.0d0, 5.0d0, 6.0d0 /)
  vec1_h(:,5) = (/ 2.5d0,-1.3d0, 0.7d0 /); vec2_h(:,5) = (/ -0.4d0, 3.2d0, 1.1d0 /)
  vec1_h(:,6) = (/ 2.0d0, 2.0d0, 2.0d0 /); vec2_h(:,6) = (/  0.0d0, 0.0d0,-1.05887100d0 /)

  vec1_h(:,7) = (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,7) = (/ 1.0d-20, 1.0d0, 0.0d0 /)
  vec1_h(:,8) = (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,8) = (/ 0.05d0, 0.99874921777190940d0, 0.0d0 /)
  vec1_h(:,9) = (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,9) = (/ 0.3d0, 0.95393920141694566d0, 0.0d0 /)
  vec1_h(:,10)= (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,10)= (/ -0.3d0, 0.95393920141694566d0, 0.0d0 /)
  vec1_h(:,11)= (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,11)= (/ 0.6d0, 0.8d0, 0.0d0 /)
  vec1_h(:,12)= (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,12)= (/ -0.65d0, 0.75993420767853309d0, 0.0d0 /)
  vec1_h(:,13)= (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,13)= (/ 0.8d0, 0.59999999999999998d0, 0.0d0 /)
  vec1_h(:,14)= (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,14)= (/ -0.85d0, 0.52678268764263704d0, 0.0d0 /)
  vec1_h(:,15)= (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,15)= (/ 0.94d0, 0.34117444218463972d0, 0.0d0 /)
  vec1_h(:,16)= (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,16)= (/ 0.96d0, 0.28d0, 0.0d0 /)
  vec1_h(:,17)= (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,17)= (/ 0.99d0, 0.14106735979665894d0, 0.0d0 /)
  vec1_h(:,18)= (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,18)= (/ 0.999999d0, 0.0014142132088478148d0, 0.0d0 /)
  vec1_h(:,19)= (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,19)= (/ -0.99d0, 0.14106735979665894d0, 0.0d0 /)
  vec1_h(:,20)= (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,20)= (/ -0.999999d0, 0.0014142132088478148d0, 0.0d0 /)
  vec1_h(:,21)= (/ 1.0d150, 0.0d0, 0.0d0 /); vec2_h(:,21)= (/ 0.6d150, 0.8d150, 0.0d0 /)
  vec1_h(:,22)= (/ 1.0d-150, 0.0d0, 0.0d0 /); vec2_h(:,22)= (/ 0.6d-150, 0.8d-150, 0.0d0 /)

  do i = 1, n
    call angle(vec1_h(:,i), vec2_h(:,i), ang_cpu)
    call scalar_product(vec1_h(:,i), vec2_h(:,i), sprod_cpu)
    call vec_norm(vec1_h(:,i), norm_cpu)

    write(*,*)
    write(*,'(a,i0)') '--- par ', i
    write(*,'(a,f18.12)') '  angle  gfortran=', ang_cpu
    write(*,'(a,f18.12)') '  scalar gfortran=', sprod_cpu
    write(*,'(a,f18.12)') '  norm   gfortran=', norm_cpu
    write(*,'(a,es24.17)') '  HP angle  gfortran=', ang_cpu
    write(*,'(a,es24.17)') '  HP scalar gfortran=', sprod_cpu
    write(*,'(a,es24.17)') '  HP norm   gfortran=', norm_cpu
  enddo

end program test_angle_gfortran
