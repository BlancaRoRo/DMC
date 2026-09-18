! test_He_dihydrogen_gfortran.f90
!
! Mismos 3 walkers que test_He_dihydrogen.cuf, pero sin nada de CUDA:
! llama a He_dihydrogen de bh_heh2m.f (el ORIGINAL, sin tocar) compilado
! con gfortran, en vez de con nvfortran. Sirve de tercera pata
! independiente: si nvfortran tuviera algun problema propio compilando
! codigo de CPU, esta comparacion (gfortran vs. gfortran) no lo veria,
! pero al cruzarla con los numeros "CPU" ya impresos por
! test_He_dihydrogen (compilados con nvfortran) se descarta esa
! posibilidad.
!
! Compilar y ejecutar: ver el bloque de comandos en docs-kernels/He_dihydrogen.md

program test_He_dihydrogen_gfortran
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 external :: He_dihydrogen

 integer(kind=i4), parameter :: natoms = 4
 integer(kind=i4), parameter :: n_walk = 3
 real(kind=r8), parameter :: dhcm = 0.52943550d0

 real(kind=r8) :: r_dih(3,2), rHH(3,1), orHH(3,1)
 real(kind=r8) :: X_h(3*natoms,n_walk)
 real(kind=r8) :: V_cpu(3*natoms,n_walk)
 real(kind=r8) :: e1_cpu(n_walk), e2_cpu(n_walk), e3_cpu(n_walk)

 integer(kind=i4) :: iw, igt
 logical :: gtest

  ! r_dih/rHH/orHH: iguales para todos los walkers (solo dependen de
  ! dhcm), calculados exactamente como en potenbh (bh_heh2m.f:17-22)
  r_dih = 0.0d0
  r_dih(3,1) =  dhcm
  r_dih(3,2) = -dhcm
  rHH = 0.0d0
  orHH = 0.0d0
  orHH(3,1) = -2.0d0*dhcm

  ! mismos 3 walkers que test_He_dihydrogen.cuf
  X_h(:,1) = (/ 3.0d0,0.0d0,0.0d0,  0.0d0,4.0d0,1.0d0, &
               -2.0d0,-3.0d0,2.5d0, 1.5d0,1.5d0,1.5d0 /)
  X_h(:,2) = (/ 1.0d0,1.0d0,1.0d0,  -1.0d0,2.0d0,0.5d0, &
                2.5d0,-1.5d0,3.0d0, 0.0d0,0.0d0,-4.0d0 /)
  X_h(:,3) = (/ 5.0d0,0.0d0,0.0d0,  0.0d0,5.0d0,0.0d0, &
                0.0d0,0.0d0,5.0d0,  2.0d0,2.0d0,2.0d0 /)

  do igt = 0, 1
    gtest = (igt == 1)

    write(*,*)
    write(*,'(a,l1)') '=== GTEST = ', gtest

    do iw = 1, n_walk
      call He_dihydrogen(natoms, r_dih, rHH, orHH, X_h(:,iw), &
                          V_cpu(:,iw), e1_cpu(iw), e2_cpu(iw), e3_cpu(iw), gtest)

      write(*,*)
      write(*,'(a,i0)') '--- walker ', iw
      write(*,'(a,f18.10)') '  ENERGY1 gfortran=', e1_cpu(iw)
      write(*,'(a,f18.10)') '  ENERGY2 gfortran=', e2_cpu(iw)
      write(*,'(a,f18.10)') '  ENERGY3 gfortran=', e3_cpu(iw)
      write(*,'(a,es24.17)') '  HP ENERGY1 gfortran=', e1_cpu(iw)
      write(*,'(a,es24.17)') '  HP ENERGY2 gfortran=', e2_cpu(iw)
      write(*,'(a,es24.17)') '  HP ENERGY3 gfortran=', e3_cpu(iw)
      if (gtest) then
        write(*,'(a,4f14.8)') '  V(1:4) gfortran=', V_cpu(1:4,iw)
      endif
    enddo
  enddo

end program test_He_dihydrogen_gfortran
