! test_derananum_gfortran.f90
!
! Compara derananum de mwavef.f90 ORIGINAL compilado con gfortran
! contra los mismos valores que test_derananum (CPU-nvfortran, en
! derananum.cuf). Mismas 2 escenas: caso real (nhe3=0, impureza=.T.) y
! prueba directa (nhe3=2, impureza=.F.).
!
! Compilar y ejecutar: ver docs-kernels/derananum.md

program test_derananum_gfortran
 use mwavef, only: derananum
 use mtipos, only: vec3, walker, allocatewalker
 use mparametros, only: nhe4, nhe3, ngatom, natom, impureza, impurmol, &
                         lxhe4, pxhe4, lxhe3, pxhe3, phe4, phe3, pmix, &
                         nhe3up, nhe3dw, mhe4, mhe3, mx, impurfija, rotamol
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
 real(kind=r8), parameter :: bhe4 = 3.139383d0, nuhe4 = 4.725025d0, alfahe4 = 0.009428d0
 real(kind=r8), parameter :: hb2he4_real = 0.5219359033034199_r8
 real(kind=r8), parameter :: hb2x_real   = 1.036440145869973_r8
 real(kind=r8), parameter :: brot_real   = 3.6975845184944736_r8

 type(vec3) :: atom_h(n_atom,n_walk), sprop_h(3,n_walk)
 type(walker) :: w1
 integer(kind=i4) :: iw, ia

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

  ! walker 4 (extremo): contacto muy cercano, walker 5 (extremo):
  ! largo alcance -- mismos casos que derananum.cuf
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

  write(*,*) '=== caso real de la simulacion: nhe3=0, impureza=.T. ==='
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

    call derananum(w1)

    write(*,*)
    write(*,'(a,i0)') '--- walker ', iw
    write(*,'(a,es24.17)') '  wf    gfortran=', real(w1%lw%wf,r8)
    write(*,'(a,es24.17)') '  wfhe4 gfortran=', real(w1%lw%wfhe4,r8)
    write(*,'(a,es24.17)') '  wfhe3 gfortran=', real(w1%lw%wfhe3,r8)
    write(*,'(a,es24.17)') '  wfm   gfortran=', real(w1%lw%wfm,r8)
    write(*,'(a,es24.17)') '  wfx   gfortran=', real(w1%lw%wfx,r8)
    write(*,'(a,es24.17)') '  kin   gfortran=', w1%lw%kin
    write(*,'(a,es24.17)') '  eimp  gfortran=', w1%lw%eimp
    write(*,'(a,es24.17)') '  erot  gfortran=', w1%lw%erot
    write(*,'(a,es24.17)') '  HP kin   gfortran=', w1%lw%kin
    write(*,'(a,es24.17)') '  HP eimp  gfortran=', w1%lw%eimp
    write(*,'(a,es24.17)') '  HP erot  gfortran=', w1%lw%erot
    do ia = 1, n_atom
      write(*,'(a,i0,a,3es24.17)') '  atom ',ia,' dwf gfortran=', w1%dwf(ia)%comp
    enddo
    write(*,'(a,2es24.17)') '  dphi gfortran=', w1%dphi
  enddo

  ! ---- prueba directa de derwavefm/derwavefhe3 con nhe3=2 ----
  block
    integer(kind=i4), parameter :: n_he4b = 4, n_he3b = 2, n_gatomb = n_he4b+n_he3b
    integer(kind=i4), parameter :: n_caseb = 3
    real(kind=r8), parameter :: bhe3 = 3.0d0, nuhe3 = 5.0d0, alfahe3 = 0.5d0, bback = 0.2d0
    real(kind=r8), parameter :: bmix = 2.5d0, numix = 4.0d0, alfamix = 0.3d0
    type(vec3) :: atomb_h(n_gatomb,n_caseb), spropb_h(3,n_caseb)
    type(walker) :: wb
    integer(kind=i4) :: ia2, icb

     nhe4 = n_he4b
     nhe3 = n_he3b
     ngatom = n_gatomb
     natom = n_gatomb
     impureza = .false.
     impurfija = .true.
     rotamol = .false.

     phe3(1) = 0.50_r8*(bhe3**nuhe3)
     phe3(2) = nuhe3
     phe3(3) = alfahe3
     phe3(4) = bback
     pmix(1) = 0.50_r8*(bmix**numix)
     pmix(2) = numix
     pmix(3) = alfamix
     nhe3up = 1
     nhe3dw = 1

     atomb_h(1,1)%comp = (/  0.0d0,  0.0d0,  0.0d0 /)
     atomb_h(2,1)%comp = (/  3.5d0,  0.0d0,  0.0d0 /)
     atomb_h(3,1)%comp = (/  0.0d0,  4.0d0,  1.0d0 /)
     atomb_h(4,1)%comp = (/ -2.0d0, -3.0d0,  2.5d0 /)
     atomb_h(5,1)%comp = (/  1.5d0,  1.5d0,  1.5d0 /)
     atomb_h(6,1)%comp = (/ -1.0d0,  2.2d0, -0.8d0 /)

     atomb_h(1,2)%comp = (/  0.0d0,  0.0d0,  0.0d0 /)
     atomb_h(2,2)%comp = (/  3.5d0,  0.0d0,  0.0d0 /)
     atomb_h(3,2)%comp = (/  0.0d0,  4.0d0,  1.0d0 /)
     atomb_h(4,2)%comp = (/ -2.0d0, -3.0d0,  2.5d0 /)
     atomb_h(5,2)%comp = (/  1.5d0,  1.5d0,  1.5d0 /)
     atomb_h(6,2)%comp = (/  1.5d0,  1.5d0,  1.55d0 /)

     atomb_h(1,3)%comp = (/  0.0d0,  0.0d0,  0.0d0 /)
     atomb_h(2,3)%comp = (/  3.5d0,  0.0d0,  0.0d0 /)
     atomb_h(3,3)%comp = (/  0.0d0,  4.0d0,  1.0d0 /)
     atomb_h(4,3)%comp = (/ -2.0d0, -3.0d0,  2.5d0 /)
     atomb_h(5,3)%comp = (/  1.5d0,  1.5d0,  1.5d0 /)
     atomb_h(6,3)%comp = (/  1.5d0,  1.5d0,  1001.5d0 /)

     do icb = 1, n_caseb
       spropb_h(1,icb)%comp = (/ 1.0d0, 0.0d0, 0.0d0 /)
       spropb_h(2,icb)%comp = (/ 0.0d0, 1.0d0, 0.0d0 /)
       spropb_h(3,icb)%comp = (/ 0.0d0, 0.0d0, 1.0d0 /)
     enddo

     do icb = 1, n_caseb
       call allocatewalker(wb, n_gatomb)
       do ia2 = 1, n_gatomb
         wb%atom(ia2) = atomb_h(ia2,icb)
         wb%hb2m(ia2) = hb2he4_real
       enddo
       wb%sprop(1) = spropb_h(1,icb)
       wb%sprop(2) = spropb_h(2,icb)
       wb%sprop(3) = spropb_h(3,icb)
       wb%b = 0.0_r8

       call derananum(wb)

       write(*,*)
       write(*,'(a,i0)') '=== prueba directa de derwavefm/derwavefhe3, nhe3=2, caso ', icb
       write(*,'(a,es24.17)') '  wfhe3 gfortran=', real(wb%lw%wfhe3,r8)
       write(*,'(a,es24.17)') '  wfm   gfortran=', real(wb%lw%wfm,r8)
       write(*,'(a,es24.17)') '  HP kin   gfortran=', wb%lw%kin
       do ia2 = 1, n_gatomb
         write(*,'(a,i0,a,3es24.17)') '  atom ',ia2,' dwf gfortran=', wb%dwf(ia2)%comp
       enddo
     enddo
  end block

end program test_derananum_gfortran
