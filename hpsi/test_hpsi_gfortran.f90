! test_hpsi_gfortran.f90
!
! hpsi de mwavef.f90 ORIGINAL compilado con gfortran (sin nada de
! CUDA), para comparar frente a los mismos 5 walkers + 1 caso
! libre=.T. que test_hpsi (en hpsi.cuf). Mismas escenas que
! test_derananum_gfortran.f90 (caso real, nhe3=0, impureza=.T.),
! mas opot/dhcm (necesarios para vpot, al que hpsi llama cuando
! libre=.F.) y el bloque libre=.T. (valibre).
!
! Compilar y ejecutar: ver el bloque de comandos en docs-kernels/hpsi.md

program test_hpsi_gfortran
 use mwavef, only: hpsi
 use mtipos, only: vec3, walker, allocatewalker
 use mparametros, only: nhe4, nhe3, ngatom, natom, impureza, impurmol, &
                         lxhe4, pxhe4, lxhe3, pxhe3, phe4, phe3, pmix, &
                         nhe3up, nhe3dw, mhe4, mhe3, mx, impurfija, rotamol, &
                         opot, libre
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
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

 type(vec3) :: atom_h(n_atom,n_walk), sprop_h(3,n_walk)
 type(walker) :: w1
 integer(kind=i4) :: iw, ia

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

  ! walker 4 (extremo): impureza a contacto muy cercano de un atomo
  ! de He4 (rij~0.05) -- mismo caso que derananum.md §8/hpsi.cuf
  atom_h(1,4)%comp = (/  1.05d0,  1.0d0,  1.0d0 /)
  atom_h(2,4)%comp = (/ -1.0d0,  2.0d0,  0.5d0 /)
  atom_h(3,4)%comp = (/  2.5d0, -1.5d0,  3.0d0 /)
  atom_h(4,4)%comp = (/  0.0d0,  0.0d0, -4.0d0 /)
  atom_h(5,4)%comp = (/  1.0d0,  1.0d0,  1.0d0 /)

  ! walker 5 (extremo): impureza a largo alcance de los 4 atomos de
  ! He4 (rij~1000 en los 4 casos)
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

  write(*,*) '=== libre=.F. (caso real, con interaccion): 5 walkers ==='
  do iw = 1, n_walk
    call allocatewalker(w1, n_atom)
    do ia = 1, n_atom
      w1%atom(ia) = atom_h(ia,iw)
      w1%hb2m(ia) = merge(hb2he4_real, hb2x_real, ia <= n_he4)
    enddo
    w1%sprop(1) = sprop_h(1,iw)
    w1%sprop(2) = sprop_h(2,iw)
    w1%sprop(3) = sprop_h(3,iw)
    w1%b = brot_real

    call hpsi(w1)

    write(*,*)
    write(*,'(a,i0)') '--- walker ', iw
    write(*,'(a,es24.17)') '  HP kin  gfortran=', w1%lw%kin
    write(*,'(a,es24.17)') '  HP eimp gfortran=', w1%lw%eimp
    write(*,'(a,es24.17)') '  HP erot gfortran=', w1%lw%erot
    write(*,'(a,es24.17)') '  HP pot  gfortran=', w1%lw%pot
    write(*,'(a,es24.17)') '  HP ene  gfortran=', w1%lw%ene
    do ia = 1, n_atom
      write(*,'(a,i0,a,3es24.17)') '  atom ',ia,' dwf gfortran=', w1%dwf(ia)%comp
    enddo
    write(*,'(a,2es24.17)') '  dphi gfortran=', w1%dphi
  enddo

  ! ---- libre=.T. (sin interaccion): un solo caso, valibre ya
  ! validado por separado, solo se comprueba que hpsi despacha bien ----
  block
    type(walker) :: wc
    integer(kind=i4) :: ia2

     libre = .true.

     call allocatewalker(wc, n_atom)
     do ia2 = 1, n_atom
       wc%atom(ia2) = atom_h(ia2,1)
       wc%hb2m(ia2) = merge(hb2he4_real, hb2x_real, ia2 <= n_he4)
     enddo
     wc%sprop(1) = sprop_h(1,1)
     wc%sprop(2) = sprop_h(2,1)
     wc%sprop(3) = sprop_h(3,1)
     wc%b = brot_real

     call hpsi(wc)

     write(*,*)
     write(*,*) '=== libre=.T. (sin interaccion) ==='
     write(*,'(a,es24.17)') '  HP kin  gfortran=', wc%lw%kin
     write(*,'(a,es24.17)') '  HP pot  gfortran=', wc%lw%pot
     write(*,'(a,es24.17)') '  HP ene  gfortran=', wc%lw%ene
  end block

end program test_hpsi_gfortran
