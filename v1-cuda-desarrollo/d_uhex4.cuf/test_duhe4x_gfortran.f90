! test_duhe4x_gfortran.f90
!
! Mismos 4 rivec que test_duhe4x (en d_uhex4.cuf), pero sin nada de
! CUDA: llama a duhe4x/uhe4x de mangwavef.f90 compilado con gfortran.
! Cierra un hueco: este kernel (5, duhe4x/uhe4x) nunca se habia
! comparado contra gfortran, solo GPU-vs-CPU(nvfortran).
!
! Compilar y ejecutar: ver docs-kernels/d_uhex4.md

program test_duhe4x_gfortran
 use mangwavef, only: duhe4x, uhe4x
 use mtipos, only: vec3
 use mparametros, only: lxhe4, impurmol, pxhe4
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i4), parameter :: n = 9

 real(kind=r8), parameter :: bxhe4(0:4)    = (/ 1.680309d0, 0.000000d0, 3.033954d0, 0.000000d0, 0.732198d0 /)
 real(kind=r8), parameter :: nuxhe4(0:4)   = (/ 9.763290d0, 1.000000d0, 3.155952d0, 1.000000d0, 11.036848d0 /)
 real(kind=r8), parameter :: alfaxhe4(0:4) = (/ 0.643208d0, 0.000000d0, 0.004908d0, 0.000000d0, 0.078598d0 /)
 real(kind=r8), parameter :: p4xhe4(0:4)   = (/ 0.129298d0, 0.000000d0, 0.084248d0, 0.000000d0, 0.096948d0 /)
 real(kind=r8), parameter :: p5xhe4(0:4)   = (/ 13.568705d0, 0.000000d0, 0.000706d0, 0.000000d0, 0.020823d0 /)

 type(vec3) :: rivec_h(n), smol_h(3)
 type(vec3) :: d1ux_cpu
 real(kind=r8) :: d2ux_cpu, d1zux_cpu(2), d2zux_cpu, uhe4x_v
 real(kind=r8) :: rij_h(n), cth_h(n)
 integer(kind=i4) :: il, i

  lxhe4 = 4
  impurmol = .true.
  do il = 0, 4
    pxhe4(1,il) = 0.50_r8*(bxhe4(il)**nuxhe4(il))
    pxhe4(2,il) = nuxhe4(il)
    pxhe4(3,il) = alfaxhe4(il)
    pxhe4(4,il) = p4xhe4(il)
    pxhe4(5,il) = p5xhe4(il)
  enddo

  smol_h(1)%comp = (/ 1.0d0, 0.0d0, 0.0d0 /)
  smol_h(2)%comp = (/ 0.0d0, 1.0d0, 0.0d0 /)
  smol_h(3)%comp = (/ 0.0d0, 0.0d0, 1.0d0 /)

  rivec_h(1)%comp = (/  3.0d0,  0.0d0,  0.0d0 /)
  rivec_h(2)%comp = (/  0.0d0,  4.0d0,  0.0d0 /)
  rivec_h(3)%comp = (/  2.0d0,  2.0d0,  3.0d0 /)
  rivec_h(4)%comp = (/ -1.5d0,  2.5d0, -3.2d0 /)
  rivec_h(5)%comp = (/  0.1d0,  0.0d0,  0.0d0 /)
  rivec_h(6)%comp = (/  0.0d0,  0.0d0, 1000.0d0 /)
  rivec_h(7)%comp = (/  0.0d0,  0.0d0,  5.0d0 /)
  rivec_h(8)%comp = (/  0.0d0,  0.0d0, -5.0d0 /)
  rivec_h(9)%comp = (/  5.0d0,  0.0d0,  0.0d0 /)

  do i = 1, n
    rij_h(i) = sqrt(dot_product(rivec_h(i)%comp, rivec_h(i)%comp))
    cth_h(i) = rivec_h(i)%comp(3) / rij_h(i)
  enddo

  do i = 1, n
    call duhe4x(rivec_h(i), smol_h, d1ux_cpu, d2ux_cpu, d1zux_cpu, d2zux_cpu)
    uhe4x_v = uhe4x(rij_h(i), cth_h(i))

    write(*,*)
    write(*,'(a,i0)') '--- rivec ', i
    write(*,'(a,3es24.17)') '  HP d1ux%comp gfortran=', d1ux_cpu%comp
    write(*,'(a,es24.17)') '  HP d2ux  gfortran=', d2ux_cpu
    write(*,'(a,2es24.17)') '  HP d1zux gfortran=', d1zux_cpu
    write(*,'(a,es24.17)') '  HP d2zux gfortran=', d2zux_cpu
    write(*,'(a,es24.17)') '  HP uhe4x gfortran=', uhe4x_v
  enddo

end program test_duhe4x_gfortran
