! test_derwavefhe4_gfortran.f90
!
! Mismos 3 walkers que test_derwavefhe4 (en el .cuf), pero sin nada de
! CUDA: llama a wavefhe4/derwavefhe4 de mwavef.f90 compilado con gfortran.
!
! Compilar y ejecutar:
!
!   gfortran -ffixed-line-length-132 modlegendre.f kpcoef.f pw_heocs.f bh_heh2m.f \
!     mtipos.f90 mparametros.f90 mlegendre.f90 mangwavef.f90 mvaziz.f90 \
!     mhh_heocs.f90 mkp_heco.f90 mvmolecula.f90 mrotaciones.f90 mlineal.f90 \
!     msistref.f90 mwavef.f90 test_derwavefhe4_gfortran.f90 \
!     -o test_derwavefhe4_gfortran -llapack -lblas
!   ./test_derwavefhe4_gfortran

program test_derwavefhe4_gfortran
 use mwavef, only: wavefhe4, derwavefhe4
 use mtipos, only: vec3, walker, allocatewalker
 use mparametros, only: nhe4, phe4
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i4), parameter :: n_atoms = 4
 integer(kind=i4), parameter :: n_walk  = 5
 real(kind=r8), parameter :: bhe4 = 3.139383d0, nuhe4 = 4.725025d0, alfahe4 = 0.009428d0

 type(vec3) :: atom_h(n_atoms,n_walk)
 type(vec3) :: d1wf(n_atoms)
 real(kind=r8) :: d2wf(n_atoms)
 type(walker) :: w1
 integer(kind=i4) :: iw, ia

  nhe4 = n_atoms
  phe4(1) = 0.50_r8*(bhe4**nuhe4)
  phe4(2) = nuhe4
  phe4(3) = alfahe4

  atom_h(1,1)%comp = (/  0.0d0,  0.0d0,  0.0d0 /)
  atom_h(2,1)%comp = (/  3.5d0,  0.0d0,  0.0d0 /)
  atom_h(3,1)%comp = (/  0.0d0,  4.0d0,  1.0d0 /)
  atom_h(4,1)%comp = (/ -2.0d0, -3.0d0,  2.5d0 /)

  atom_h(1,2)%comp = (/  1.0d0,  1.0d0,  1.0d0 /)
  atom_h(2,2)%comp = (/ -1.0d0,  2.0d0,  0.5d0 /)
  atom_h(3,2)%comp = (/  2.5d0, -1.5d0,  3.0d0 /)
  atom_h(4,2)%comp = (/  0.0d0,  0.0d0, -4.0d0 /)

  atom_h(1,3)%comp = (/  5.0d0,  0.0d0,  0.0d0 /)
  atom_h(2,3)%comp = (/  0.0d0,  5.0d0,  0.0d0 /)
  atom_h(3,3)%comp = (/  0.0d0,  0.0d0,  5.0d0 /)
  atom_h(4,3)%comp = (/  2.0d0,  2.0d0,  2.0d0 /)

  atom_h(1,4)%comp = (/  0.0d0,  0.0d0,  0.0d0 /)
  atom_h(2,4)%comp = (/  0.05d0,  0.0d0,  0.0d0 /)
  atom_h(3,4)%comp = (/  3.0d0,  3.0d0,  3.0d0 /)
  atom_h(4,4)%comp = (/ -2.0d0,  1.0d0, -1.0d0 /)

  atom_h(1,5)%comp = (/  0.0d0,  0.0d0,  0.0d0 /)
  atom_h(2,5)%comp = (/  1.0d0,  0.0d0,  0.0d0 /)
  atom_h(3,5)%comp = (/  1000.0d0,  0.0d0,  0.0d0 /)
  atom_h(4,5)%comp = (/  1.5d0,  1.5d0,  1.5d0 /)

  do iw = 1, n_walk
    call allocatewalker(w1, n_atoms)
    do ia = 1, n_atoms
      w1%atom(ia) = atom_h(ia,iw)
    enddo

    call wavefhe4(w1)
    call derwavefhe4(w1, d1wf, d2wf)

    write(*,*)
    write(*,'(a,i0)') '--- walker ', iw
    write(*,'(a,f20.12)') '  wfhe4 gfortran=', w1%lw%wfhe4
    write(*,'(a,es24.17)') '  HP wfhe4 gfortran=', w1%lw%wfhe4
    do ia = 1, n_atoms
      write(*,'(a,i0,a,3f18.10,a,f18.10)') '  atom ', ia, ' d1wf=', d1wf(ia)%comp, '  d2wf=', d2wf(ia)
      write(*,'(a,i0,a,3es24.17,a,es24.17)') '  HP atom ', ia, ' d1wf gfortran=', d1wf(ia)%comp, '  d2wf gfortran=', d2wf(ia)
    enddo
  enddo

end program test_derwavefhe4_gfortran
