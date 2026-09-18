! test_dmc2_gfortran.f90
!
! dmc2 de msteps.f90 ORIGINAL compilado con gfortran (sin nada de
! CUDA), mismos 5 walkers que test_dmc2.cuf.
!
! Compilar y ejecutar: ver docs-kernels/dmc2.md

program test_dmc2_gfortran
 use mwavef, only: hpsi
 use msteps, only: dmc2
 use mrandom, only: fijasemilla
 use mrandom2, only: rand1p
 use mtipos, only: vec3, walker, allocatewalker
 use mparametros, only: nhe4, nhe3, ngatom, natom, impureza, impurmol, &
                         lxhe4, pxhe4, lxhe3, pxhe3, phe4, phe3, pmix, &
                         nhe3up, nhe3dw, mhe4, mhe3, mx, impurfija, rotamol, &
                         opot, libre, ncmtras, dtau, etrial
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: i8 = selected_int_kind(15)
 integer, parameter :: r8 = selected_real_kind(15,9)

 real(kind=r8) :: dhcm
 common / datosbh / dhcm

 integer(kind=i4), parameter :: n_he4  = 4
 integer(kind=i4), parameter :: n_atom = n_he4 + 1
 integer(kind=i4), parameter :: n_walk = 5

 real(kind=r8), parameter :: bxhe4(0:4)    = (/ 1.680309d0, 0.000000d0, 3.033954d0, 0.000000d0, 0.732198d0 /)
 real(kind=r8), parameter :: nuxhe4(0:4)   = (/ 9.763290d0, 1.000000d0, 3.155952d0, 1.000000d0, 11.036848d0 /)
 real(kind=r8), parameter :: alfaxhe4(0:4) = (/ 0.643208d0, 0.000000d0, 0.004908d0, 0.000000d0, 0.078598d0 /)
 real(kind=r8), parameter :: p4xhe4(0:4)   = (/ 0.129298d0, 0.000000d0, 0.084248d0, 0.000000d0, 0.096948d0 /)
 real(kind=r8), parameter :: p5xhe4(0:4)   = (/ 13.568705d0, 0.000000d0, 0.000706d0, 0.000000d0, 0.020823d0 /)
 real(kind=r8), parameter :: bhe4 = 3.139383d0, nuhe4 = 4.725025d0, alfahe4 = 0.009428d0
 real(kind=r8), parameter :: hb2he4_real = 0.5219359033034199_r8
 real(kind=r8), parameter :: hb2x_real   = 1.036440145869973_r8
 real(kind=r8), parameter :: brot_real   = 3.6975845184944736_r8
 real(kind=r8), parameter :: dhcm_real   = 0.52943550d0
 real(kind=r8), parameter :: dtau_val    = 1.0d-3
 real(kind=r8), parameter :: etrial_val  = -150.0d0
 integer(kind=i8), parameter :: seed0    = 123456789013_i8

 type(vec3) :: atom_h(n_atom,n_walk), sprop_h(3,n_walk)
 real(kind=r8) :: hb2m_h(n_atom,n_walk), b_h(n_walk)
 type(walker) :: w1
 integer(kind=i4) :: iw, ia, nsons
 integer(kind=i8) :: irn_ref
 real(kind=r8) :: rn_ref

  libre = .false.
  nhe4 = n_he4
  nhe3 = 0
  ngatom = n_he4
  natom = n_atom
  impureza = .true.
  impurmol = .true.
  impurfija = .false.
  rotamol = .true.
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
  phe4(1) = 0.50_r8*(bhe4**nuhe4)
  phe4(2) = nuhe4
  phe4(3) = alfahe4
  phe3 = 0.0_r8
  pmix(1) = 0.0_r8
  pmix(2) = 1.0_r8
  pmix(3) = 0.0_r8
  nhe3up = 0
  nhe3dw = 0
  mhe4 = 4.00260_r8
  mhe3 = 3.01604_r8
  mx   = 2.01565006_r8
  opot = 4
  dhcm = dhcm_real
  ncmtras = n_atom
  dtau = dtau_val
  etrial = etrial_val

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

  atom_h(1,4)%comp = (/  1.05d0,  1.0d0,  1.0d0 /)
  atom_h(2,4)%comp = (/ -1.0d0,  2.0d0,  0.5d0 /)
  atom_h(3,4)%comp = (/  2.5d0, -1.5d0,  3.0d0 /)
  atom_h(4,4)%comp = (/  0.0d0,  0.0d0, -4.0d0 /)
  atom_h(5,4)%comp = (/  1.0d0,  1.0d0,  1.0d0 /)

  atom_h(1,5)%comp = (/ 1000.0d0,    0.0d0,    0.0d0 /)
  atom_h(2,5)%comp = (/    0.0d0, 1000.0d0,    0.0d0 /)
  atom_h(3,5)%comp = (/    0.0d0,    0.0d0, 1000.0d0 /)
  atom_h(4,5)%comp = (/-1000.0d0,    0.0d0,    0.0d0 /)
  atom_h(5,5)%comp = (/    0.0d0,    0.0d0,    0.0d0 /)

  sprop_h(1,1)%comp = (/ 2.0d0, 0.0d0, 0.0d0 /)
  sprop_h(2,1)%comp = (/ 0.0d0, 1.5d0, 0.0d0 /)
  sprop_h(3,1)%comp = (/ 0.3d0, 0.4d0, 1.2d0 /)

  sprop_h(1,2)%comp = (/ 1.0d0, 0.2d0, 0.0d0 /)
  sprop_h(2,2)%comp = (/ 0.0d0, 1.0d0, 0.3d0 /)
  sprop_h(3,2)%comp = (/ 0.5d0, 0.0d0, 1.0d0 /)

  sprop_h(1,3)%comp = (/ 0.7d0, 0.7d0, 0.0d0 /)
  sprop_h(2,3)%comp = (/ -0.7d0, 0.7d0, 0.0d0 /)
  sprop_h(3,3)%comp = (/ 0.0d0, 0.0d0, 2.0d0 /)

  sprop_h(1,4)%comp = (/ 1.0d0, 0.2d0, 0.0d0 /)
  sprop_h(2,4)%comp = (/ 0.0d0, 1.0d0, 0.3d0 /)
  sprop_h(3,4)%comp = (/ 0.5d0, 0.0d0, 1.0d0 /)

  sprop_h(1,5)%comp = (/ 0.7d0, 0.7d0, 0.0d0 /)
  sprop_h(2,5)%comp = (/ -0.7d0, 0.7d0, 0.0d0 /)
  sprop_h(3,5)%comp = (/ 0.0d0, 0.0d0, 2.0d0 /)

  do iw = 1, n_walk
    do ia = 1, n_he4
      hb2m_h(ia,iw) = hb2he4_real
    enddo
    hb2m_h(n_atom,iw) = hb2x_real
    b_h(iw) = brot_real
  enddo

  do iw = 1, n_walk
    call allocatewalker(w1, n_atom)
    do ia = 1, n_atom
      w1%atom(ia) = atom_h(ia,iw)
      w1%hb2m(ia) = hb2m_h(ia,iw)
      w1%sigma1(ia) = sqrt(2.0_r8*w1%hb2m(ia)*dtau_val)
      w1%sigma2(ia) = 2.0_r8*w1%hb2m(ia)*dtau_val
    enddo
    w1%sprop(1) = sprop_h(1,iw)
    w1%sprop(2) = sprop_h(2,iw)
    w1%sprop(3) = sprop_h(3,iw)
    w1%b = b_h(iw)
    w1%sig1rot  = sqrt(2.0_r8*w1%b*dtau_val)
    w1%sig2rot  = 2.0_r8*w1%b*dtau_val
    w1%sig1hrot = sqrt(w1%b*dtau_val)
    w1%sig2hrot = w1%b*dtau_val

    call hpsi(w1)

    irn_ref = seed0
    do ia = 1, iw
      call rand1p(rn_ref, irn_ref)
    enddo
    call fijasemilla(irn_ref)

    call dmc2(w1, nsons)

    write(*,*)
    write(*,'(a,i0)') '--- walker ', iw
    write(*,'(a,i0)') '  nsons gfortran=', nsons
    write(*,'(a,es24.17)') '  HP ene gfortran=', w1%lw%ene
    write(*,'(a,es24.17)') '  HP kin gfortran=', w1%lw%kin
    write(*,'(a,es24.17)') '  HP pot gfortran=', w1%lw%pot
    do ia = 1, n_atom
      write(*,'(a,i0,a,3es24.17)') '  atom ',ia,' gfortran=', w1%atom(ia)%comp
    enddo
  enddo

end program test_dmc2_gfortran
