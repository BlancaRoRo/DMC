! test_ccuerpo_gfortran.f90
!
! Mismos 3 walkers que test_ccuerpo.cuf, pero sin nada de CUDA: llama a
! ccuerpo de msistref.f90 compilado con gfortran, en vez de con nvfortran.
!
! Compilar y ejecutar: ver el bloque de comandos en docs-kernels/ccuerpo.md

program test_ccuerpo_gfortran
 use msistref, only: ccuerpo
 use mtipos, only: vec3, walker, allocatewalker
 use mparametros, only: ngatom, natom
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i4), parameter :: n_gatom = 4
 integer(kind=i4), parameter :: n_atom  = n_gatom + 1
 integer(kind=i4), parameter :: n_walk  = 3

 type(vec3) :: atom_h(n_atom,n_walk), sprop_h(3,n_walk)
 real(kind=r8) :: rhesal(3*n_gatom,n_walk)
 type(walker) :: w1
 integer(kind=i4) :: iw, ia

  atom_h(1,1)%comp = (/  0.0d0,  0.0d0,  0.0d0 /)
  atom_h(2,1)%comp = (/  3.5d0,  0.0d0,  0.0d0 /)
  atom_h(3,1)%comp = (/  0.0d0,  4.0d0,  1.0d0 /)
  atom_h(4,1)%comp = (/ -2.0d0, -3.0d0,  2.5d0 /)
  atom_h(5,1)%comp = (/  1.0d0,  1.0d0,  1.0d0 /)

  atom_h(1,2)%comp = (/  1.0d0,  1.0d0,  1.0d0 /)
  atom_h(2,2)%comp = (/ -1.0d0,  2.0d0,  0.5d0 /)
  atom_h(3,2)%comp = (/  2.5d0, -1.5d0,  3.0d0 /)
  atom_h(4,2)%comp = (/  0.0d0,  0.0d0, -4.0d0 /)
  atom_h(5,2)%comp = (/  0.5d0, -0.5d0,  0.5d0 /)

  atom_h(1,3)%comp = (/  5.0d0,  0.0d0,  0.0d0 /)
  atom_h(2,3)%comp = (/  0.0d0,  5.0d0,  0.0d0 /)
  atom_h(3,3)%comp = (/  0.0d0,  0.0d0,  5.0d0 /)
  atom_h(4,3)%comp = (/  2.0d0,  2.0d0,  2.0d0 /)
  atom_h(5,3)%comp = (/  1.5d0,  1.5d0,  1.5d0 /)

  sprop_h(1,1)%comp = (/ 2.0d0, 0.0d0, 0.0d0 /)
  sprop_h(2,1)%comp = (/ 0.0d0, 1.5d0, 0.0d0 /)
  sprop_h(3,1)%comp = (/ 0.3d0, 0.4d0, 1.2d0 /)

  sprop_h(1,2)%comp = (/ 1.0d0, 0.2d0, 0.0d0 /)
  sprop_h(2,2)%comp = (/ 0.0d0, 1.0d0, 0.3d0 /)
  sprop_h(3,2)%comp = (/ 0.5d0, 0.0d0, 1.0d0 /)

  sprop_h(1,3)%comp = (/ 0.7d0, 0.7d0, 0.0d0 /)
  sprop_h(2,3)%comp = (/ -0.7d0, 0.7d0, 0.0d0 /)
  sprop_h(3,3)%comp = (/ 0.0d0, 0.0d0, 2.0d0 /)

  ngatom = n_gatom
  natom  = n_atom

  do iw = 1, n_walk
    call allocatewalker(w1, n_atom)
    do ia = 1, n_atom
      w1%atom(ia) = atom_h(ia,iw)
    enddo
    w1%sprop(1) = sprop_h(1,iw)
    w1%sprop(2) = sprop_h(2,iw)
    w1%sprop(3) = sprop_h(3,iw)

    call ccuerpo(w1, rhesal(:,iw))

    write(*,*)
    write(*,'(a,i0)') '--- walker ', iw
    write(*,'(a,3f16.8)') '  rhesal(1:3) gfortran=', rhesal(1:3,iw)
    write(*,'(a,3f16.8)') '  rhesal(4:6) gfortran=', rhesal(4:6,iw)
    write(*,'(a,3es24.17)') '  HP rhesal(1:3) gfortran=', rhesal(1:3,iw)
    write(*,'(a,3es24.17)') '  HP rhesal(4:6) gfortran=', rhesal(4:6,iw)
  enddo

end program test_ccuerpo_gfortran
