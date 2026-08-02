! test_rota_gfortran.f90
!
! rota de mrotaciones.f90 ORIGINAL compilado con gfortran (sin nada de
! CUDA), mismos 8 casos que test_rota (en rota.cuf).
!
! Compilar y ejecutar: ver docs-kernels/rota.md

program test_rota_gfortran
 use mrotaciones, only: rota
 use mtipos, only: vec3
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)
 real(kind=r8), parameter :: da = 1.d-4

 integer(kind=i4), parameter :: n_case = 8

 integer(kind=i4) :: i1_h(n_case)
 real(kind=r8) :: phi_h(n_case)
 type(vec3) :: ejes0(3,n_case), ejes(3)
 integer(kind=i4) :: ic, icomp

  i1_h(1)=1; phi_h(1)= da
  i1_h(2)=1; phi_h(2)=-da
  i1_h(3)=2; phi_h(3)= da
  i1_h(4)=2; phi_h(4)=-da
  i1_h(5)=3; phi_h(5)= da
  i1_h(6)=3; phi_h(6)=-da
  i1_h(7)=1; phi_h(7)=1.0d10
  i1_h(8)=1; phi_h(8)=1.0d-300

  do ic = 1, n_case
    ejes0(1,ic)%comp = (/  1.0d0,  0.2d0, -0.7d0 /)
    ejes0(2,ic)%comp = (/ -0.3d0,  1.0d0,  0.5d0 /)
    ejes0(3,ic)%comp = (/  0.8d0, -0.6d0,  1.0d0 /)
  enddo
  ejes0(1,7)%comp = (/  1.0d8,  2.0d8, -3.0d8 /)
  ejes0(2,7)%comp = (/ -4.0d8,  5.0d8,  6.0d8 /)
  ejes0(3,7)%comp = (/  7.0d8, -8.0d8,  9.0d8 /)

  do ic = 1, n_case
    ejes = ejes0(:,ic)
    call rota(i1_h(ic), phi_h(ic), ejes)

    write(*,*)
    write(*,'(a,i0,a,i0,a,es10.2)') '--- caso ', ic, ': i1=', i1_h(ic), ' phi=', phi_h(ic)
    do icomp = 1, 3
      write(*,'(a,i0,a,3es24.17)') '  eje ',icomp,' gfortran=', ejes(icomp)%comp
    enddo
  enddo

end program test_rota_gfortran
