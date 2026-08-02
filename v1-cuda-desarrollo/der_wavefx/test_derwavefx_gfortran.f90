! test_derwavefx_gfortran.f90
!
! Mismos 3 walkers que test_derwavefx (en el .cuf), pero sin nada de
! CUDA: llama a wavefx/derwavefx de mwavef.f90 compilado con gfortran.
!
! Compilar y ejecutar: ver el bloque de comandos en docs-kernels/der_wavefx.md

program test_derwavefx_gfortran
 use mwavef, only: wavefx, derwavefx, duhe3x, uhe3x
 use mtipos, only: vec3, walker, allocatewalker
 use mparametros, only: nhe4, nhe3, ngatom, natom, impureza, impurmol, &
                         lxhe4, pxhe4, lxhe3, pxhe3
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i4), parameter :: n_he4  = 4
 integer(kind=i4), parameter :: n_atom = n_he4 + 1
 integer(kind=i4), parameter :: n_walk = 5

 real(kind=r8), parameter :: bxhe4(0:4)    = (/ 1.680309d0, 0.000000d0, 3.033954d0, 0.000000d0, 0.732198d0 /)
 real(kind=r8), parameter :: nuxhe4(0:4)   = (/ 9.763290d0, 1.000000d0, 3.155952d0, 1.000000d0, 11.036848d0 /)
 real(kind=r8), parameter :: alfaxhe4(0:4) = (/ 0.643208d0, 0.000000d0, 0.004908d0, 0.000000d0, 0.078598d0 /)
 real(kind=r8), parameter :: p4xhe4(0:4)   = (/ 0.129298d0, 0.000000d0, 0.084248d0, 0.000000d0, 0.096948d0 /)
 real(kind=r8), parameter :: p5xhe4(0:4)   = (/ 13.568705d0, 0.000000d0, 0.000706d0, 0.000000d0, 0.020823d0 /)

 type(vec3) :: atom_h(n_atom,n_walk), sprop_h(3,n_walk)
 type(vec3) :: d1wf(n_atom)
 real(kind=r8) :: d2wf(n_atom), d1zwf(2), d2zwf
 type(walker) :: w1
 integer(kind=i4) :: iw, ia

  nhe4 = n_he4
  nhe3 = 0
  ngatom = n_he4
  natom = n_atom
  impureza = .true.
  impurmol = .true.
  lxhe4 = 4
  do ia = 0, 4
    pxhe4(1,ia) = 0.50_r8*(bxhe4(ia)**nuxhe4(ia))
    pxhe4(2,ia) = nuxhe4(ia)
    pxhe4(3,ia) = alfaxhe4(ia)
    pxhe4(4,ia) = p4xhe4(ia)
    pxhe4(5,ia) = p5xhe4(ia)
  enddo
  lxhe3 = 0
  pxhe3 = 0.0_r8
  pxhe3(1,0) = 0.50_r8*(0.5d0**0.0d0)
  pxhe3(2,0) = 0.0d0
  pxhe3(3,0) = 1.0d0
  pxhe3(4,0) = 1.0d0
  pxhe3(5,0) = 0.0d0

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

  ! walker 4 (extremo): contacto muy cercano, walker 5 (extremo): largo
  ! alcance -- mismos casos que test_derwavefx.cuf
  atom_h(1,4)%comp = (/  1.05d0,  1.0d0,  1.0d0 /)
  atom_h(2,4)%comp = (/ -1.0d0,  2.0d0,  0.5d0 /)
  atom_h(3,4)%comp = (/  2.5d0, -1.5d0,  3.0d0 /)
  atom_h(4,4)%comp = (/  0.0d0,  0.0d0, -4.0d0 /)
  atom_h(5,4)%comp = (/  1.0d0,  1.0d0,  1.0d0 /)
  sprop_h(1,4)%comp = (/ 1.0d0, 0.2d0, 0.0d0 /)
  sprop_h(2,4)%comp = (/ 0.0d0, 1.0d0, 0.3d0 /)
  sprop_h(3,4)%comp = (/ 0.5d0, 0.0d0, 1.0d0 /)

  atom_h(1,5)%comp = (/ 1000.0d0,    0.0d0,    0.0d0 /)
  atom_h(2,5)%comp = (/    0.0d0, 1000.0d0,    0.0d0 /)
  atom_h(3,5)%comp = (/    0.0d0,    0.0d0, 1000.0d0 /)
  atom_h(4,5)%comp = (/-1000.0d0,    0.0d0,    0.0d0 /)
  atom_h(5,5)%comp = (/    0.0d0,    0.0d0,    0.0d0 /)
  sprop_h(1,5)%comp = (/ 0.7d0, 0.7d0, 0.0d0 /)
  sprop_h(2,5)%comp = (/ -0.7d0, 0.7d0, 0.0d0 /)
  sprop_h(3,5)%comp = (/ 0.0d0, 0.0d0, 2.0d0 /)

  do iw = 1, n_walk
    call allocatewalker(w1, n_atom)
    do ia = 1, n_atom
      w1%atom(ia) = atom_h(ia,iw)
    enddo
    w1%sprop(1) = sprop_h(1,iw)
    w1%sprop(2) = sprop_h(2,iw)
    w1%sprop(3) = sprop_h(3,iw)

    call wavefx(w1)
    call derwavefx(w1, d1wf, d2wf, d1zwf, d2zwf)

    write(*,*)
    write(*,'(a,i0)') '--- walker ', iw
    write(*,'(a,f20.12)') '  wfx gfortran=', w1%lw%wfx
    write(*,'(a,es24.17)') '  HP wfx gfortran=', w1%lw%wfx
    do ia = 1, n_atom
      write(*,'(a,i0,a,3f16.8,a,f16.8)') '  atom ',ia,' d1wf gfortran=', d1wf(ia)%comp, '  d2wf gfortran=', d2wf(ia)
      write(*,'(a,i0,a,3es24.17,a,es24.17)') '  HP atom ',ia,' d1wf gfortran=', d1wf(ia)%comp, '  d2wf gfortran=', d2wf(ia)
    enddo
    write(*,'(a,2f16.8)') '  d1zwf gfortran=', d1zwf
    write(*,'(a,f16.8)')  '  d2zwf gfortran=', d2zwf
    write(*,'(a,2es24.17)') '  HP d1zwf gfortran=', d1zwf
    write(*,'(a,es24.17)')  '  HP d2zwf gfortran=', d2zwf
  enddo

  ! --- prueba directa de duhe3x/uhe3x (nhe3=0 no las ejercita arriba) ---
  block
    integer(kind=i4), parameter :: n_he3test = 8
    type(vec3) :: rivec3_h(n_he3test), smol3_h(3)
    type(vec3) :: d1ux3
    real(kind=r8) :: d2ux3, d1zux3(2), d2zux3, uhe3x_v, rij3, cth3
    integer(kind=i4) :: it

    smol3_h(1)%comp = (/ 1.0d0, 0.0d0, 0.0d0 /)
    smol3_h(2)%comp = (/ 0.0d0, 1.0d0, 0.0d0 /)
    smol3_h(3)%comp = (/ 0.0d0, 0.0d0, 1.0d0 /)

    rivec3_h(1)%comp = (/ 3.0d0, 0.0d0, 0.0d0 /)
    rivec3_h(2)%comp = (/ 0.0d0, 4.0d0, 1.0d0 /)
    rivec3_h(3)%comp = (/ 2.0d0,-1.5d0, 2.2d0 /)
    rivec3_h(4)%comp = (/  0.1d0,  0.0d0,  0.0d0 /)
    rivec3_h(5)%comp = (/  0.0d0,  0.0d0, 1000.0d0 /)
    rivec3_h(6)%comp = (/  0.0d0,  0.0d0,  5.0d0 /)
    rivec3_h(7)%comp = (/  0.0d0,  0.0d0, -5.0d0 /)
    rivec3_h(8)%comp = (/  5.0d0,  0.0d0,  0.0d0 /)

    write(*,*)
    write(*,*) '=== prueba directa de duhe3x/uhe3x ==='
    do it = 1, n_he3test
      rij3 = sqrt(dot_product(rivec3_h(it)%comp, rivec3_h(it)%comp))
      cth3 = rivec3_h(it)%comp(3) / rij3

      call duhe3x(rivec3_h(it), smol3_h, d1ux3, d2ux3, d1zux3, d2zux3)
      uhe3x_v = uhe3x(rij3, cth3)

      write(*,*)
      write(*,'(a,i0)') '--- rivec3 ', it
      write(*,'(a,3f16.8)') '  d1ux%comp gfortran=', d1ux3%comp
      write(*,'(a,f16.8)') '  d2ux  gfortran=', d2ux3
      write(*,'(a,f16.8)') '  uhe3x gfortran=', uhe3x_v
      write(*,'(a,3es24.17)') '  HP d1ux%comp gfortran=', d1ux3%comp
      write(*,'(a,es24.17)') '  HP d2ux  gfortran=', d2ux3
      write(*,'(a,es24.17)') '  HP uhe3x gfortran=', uhe3x_v
    enddo
  end block

end program test_derwavefx_gfortran
