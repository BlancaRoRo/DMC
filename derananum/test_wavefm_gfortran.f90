! test_wavefm_gfortran.f90
!
! Mismos 3 casos que test_wavefm.cuf, pero sin nada de CUDA: llama a
! wavefm/derwavefm de mwavef.f90 compilado con gfortran.
!
! Compilar y ejecutar: ver docs-kernels/derananum.md

program test_wavefm_gfortran
 use mwavef, only: wavefm, derwavefm
 use mtipos, only: vec3, walker, allocatewalker
 use mparametros, only: nhe4, nhe3, ngatom, natom, impureza, pmix
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i4), parameter :: n_he4 = 4, n_he3 = 2
 integer(kind=i4), parameter :: n_atom = n_he4 + n_he3
 integer(kind=i4), parameter :: n_case = 3

 real(kind=r8), parameter :: bmix = 2.5d0, numix = 4.0d0, alfamix = 0.3d0

 type(vec3) :: atom_h(n_atom,n_case)
 type(vec3) :: d1wf(n_atom)
 real(kind=r8) :: d2wf(n_atom)
 type(walker) :: w1
 integer(kind=i4) :: ia, ic

  nhe4 = n_he4
  nhe3 = n_he3
  ngatom = n_atom
  natom = n_atom
  impureza = .false.
  pmix(1) = 0.50_r8*(bmix**numix)
  pmix(2) = numix
  pmix(3) = alfamix

  atom_h(1,1)%comp = (/  0.0d0,  0.0d0,  0.0d0 /)
  atom_h(2,1)%comp = (/  3.5d0,  0.0d0,  0.0d0 /)
  atom_h(3,1)%comp = (/  0.0d0,  4.0d0,  1.0d0 /)
  atom_h(4,1)%comp = (/ -2.0d0, -3.0d0,  2.5d0 /)
  atom_h(5,1)%comp = (/  1.5d0,  1.5d0,  1.5d0 /)
  atom_h(6,1)%comp = (/ -1.0d0,  2.2d0, -0.8d0 /)

  atom_h(1,2)%comp = (/  0.0d0,  0.0d0,  0.0d0 /)
  atom_h(2,2)%comp = (/  3.5d0,  0.0d0,  0.0d0 /)
  atom_h(3,2)%comp = (/  0.0d0,  4.0d0,  1.0d0 /)
  atom_h(4,2)%comp = (/ -2.0d0, -3.0d0,  2.5d0 /)
  atom_h(5,2)%comp = (/  0.05d0,  0.0d0,  0.0d0 /)
  atom_h(6,2)%comp = (/ -1.0d0,  2.2d0, -0.8d0 /)

  atom_h(1,3)%comp = (/  0.0d0,  0.0d0,  0.0d0 /)
  atom_h(2,3)%comp = (/  3.5d0,  0.0d0,  0.0d0 /)
  atom_h(3,3)%comp = (/  0.0d0,  4.0d0,  1.0d0 /)
  atom_h(4,3)%comp = (/ -2.0d0, -3.0d0,  2.5d0 /)
  atom_h(5,3)%comp = (/  1000.0d0,  0.0d0,  0.0d0 /)
  atom_h(6,3)%comp = (/ -1.0d0,  2.2d0, -0.8d0 /)

  do ic = 1, n_case
    call allocatewalker(w1, n_atom)
    do ia = 1, n_atom
      w1%atom(ia) = atom_h(ia,ic)
    enddo
    call wavefm(w1)
    call derwavefm(w1, d1wf, d2wf)

    write(*,*)
    write(*,'(a,i0)') '--- caso ', ic
    write(*,'(a,es24.17)') '  HP wfm  gfortran=', real(w1%lw%wfm,r8)
    do ia = 1, n_atom
      write(*,'(a,i0,a,3es24.17,a,es24.17)') '  HP atom ',ia,' d1wf gfortran=', d1wf(ia)%comp, '  d2wf gfortran=', d2wf(ia)
    enddo
  enddo

end program test_wavefm_gfortran
