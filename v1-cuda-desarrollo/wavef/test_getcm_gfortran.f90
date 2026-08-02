! test_getcm_gfortran.f90
!
! Mismos 3 casos que test_getcm (en wavef.cuf), pero sin nada de CUDA:
! llama a getcm de mwavef.f90 compilado con gfortran.
!
! Compilar y ejecutar: ver docs-kernels/wavef.md

program test_getcm_gfortran
 use mwavef, only: getcm
 use mtipos, only: vec3, walker, allocatewalker
 use mparametros, only: nhe4, nhe3, ngatom, natom, impureza, mhe4, mhe3, mx
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i4), parameter :: n_he4 = 20
 integer(kind=i4), parameter :: n_atom = n_he4 + 1
 integer(kind=i4), parameter :: n_case = 3

 type(vec3) :: atom_h(n_atom,n_case)
 real(kind=r8) :: rcm(3)
 type(walker) :: w1
 integer(kind=i4) :: ia, ic

  nhe4 = n_he4
  nhe3 = 0
  ngatom = n_he4
  natom = n_atom
  impureza = .true.
  mhe4 = 4.00260_r8
  mhe3 = 3.01604_r8
  mx   = 2.01565006_r8

  do ia = 1, n_atom
    atom_h(ia,1)%comp = (/ 0.1d0*ia, -0.2d0*ia, 0.05d0*ia*ia /)
  enddo

  do ia = 1, n_atom
    if (mod(ia,2)==0) then
      atom_h(ia,2)%comp = (/  1.0d8*ia, -1.0d8*ia,  1.0d8 /)
    else
      atom_h(ia,2)%comp = (/ -1.0d8*ia,  1.0d8*ia, -1.0d8 /)
    endif
  enddo

  do ia = 1, n_atom
    atom_h(ia,3)%comp = (/ 1.0d-150*ia, -1.0d-150*ia, 1.0d-150 /)
  enddo

  do ic = 1, n_case
    call allocatewalker(w1, n_atom)
    do ia = 1, n_atom
      w1%atom(ia) = atom_h(ia,ic)
    enddo
    call getcm(w1, rcm)

    write(*,*)
    write(*,'(a,i0)') '--- caso ', ic
    write(*,'(a,3es24.17)') '  HP rcm gfortran=', rcm
  enddo

end program test_getcm_gfortran
