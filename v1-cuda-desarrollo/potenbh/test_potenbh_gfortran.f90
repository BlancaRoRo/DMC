! test_potenbh_gfortran.f90
!
! Mismos 3 walkers que test_potenbh (en potenbh.cuf), pero sin nada de
! CUDA: llama a potenbh de bh_heh2m.f (el ORIGINAL, sin tocar)
! compilado con gfortran, en vez de con nvfortran.
!
! Compilar y ejecutar: ver el bloque de comandos en docs-kernels/potenbh.md

program test_potenbh_gfortran
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 external :: potenbh
 real(kind=r8) :: dhcm
 common / datosbh / dhcm

 integer(kind=i4), parameter :: natoms = 4
 integer(kind=i4), parameter :: n_walk = 3

 real(kind=r8) :: X_h(3*natoms,n_walk)
 real(kind=r8) :: vpotbh(n_walk)
 integer(kind=i4) :: iw

  dhcm = 0.52943550d0

  X_h(:,1) = (/ 3.0d0,0.0d0,0.0d0,  0.0d0,4.0d0,1.0d0, &
               -2.0d0,-3.0d0,2.5d0, 1.5d0,1.5d0,1.5d0 /)
  X_h(:,2) = (/ 1.0d0,1.0d0,1.0d0,  -1.0d0,2.0d0,0.5d0, &
                2.5d0,-1.5d0,3.0d0, 0.0d0,0.0d0,-4.0d0 /)
  X_h(:,3) = (/ 5.0d0,0.0d0,0.0d0,  0.0d0,5.0d0,0.0d0, &
                0.0d0,0.0d0,5.0d0,  2.0d0,2.0d0,2.0d0 /)

  do iw = 1, n_walk
    call potenbh(natoms, X_h(:,iw), vpotbh(iw))

    write(*,*)
    write(*,'(a,i0)') '--- walker ', iw
    write(*,'(a,f18.10)') '  vpotbh gfortran=', vpotbh(iw)
    write(*,'(a,es24.17)') '  HP vpotbh gfortran=', vpotbh(iw)
  enddo

end program test_potenbh_gfortran
