! test_rand_gfortran.f90
!
! rand1/rand1p/gauss3 de mrandom.f90/mrandom2.f90 ORIGINALES,
! compilados con gfortran (glibc real -- confirmado con IFUNC que esta
! maquina ejecuta la variante _fma de log/exp/sin/cos/pow/acos, ver
! docs-kernels/mrandom.md). Mismos casos que test_rand.cuf: 20
! llamadas de rand1/rand1p desde la misma semilla, reparto de semilla
! por walker (mismo bucle que distribuyesemillas, mmpi.f90:129-142,
! generalizado a indice de walker) y 4 sorteos gauss3 para los
! walkers 1/2/3.

program test_rand_gfortran
 use mrandom2, only: rand1, rand1p
 use mrandom, only: gauss3, fijasemilla
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: i8 = selected_int_kind(15)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i8), parameter :: seed0 = 123456789013_i8
 integer(kind=i4), parameter :: n_call = 20
 integer(kind=i4), parameter :: n_walk = 10
 integer(kind=i4), parameter :: n_gauss = 4

 integer(kind=i8) :: irn, irn_p
 real(kind=r8) :: rn(n_call), rn_p(n_call)
 integer(kind=i8) :: seeds(n_walk)
 real(kind=r8) :: rn_ref
 real(kind=r8) :: gv(3,n_gauss)
 integer(kind=i4) :: ic, iw

  write(*,*) '=== 1) rand1/rand1p: ', n_call, ' llamadas encadenadas ==='
  irn = seed0
  irn_p = seed0
  do ic = 1, n_call
    call rand1(rn(ic), irn)
    call rand1p(rn_p(ic), irn_p)
  enddo
  write(*,'(a,es24.17)') '  HP rand1(1)  gfortran=', rn(1)
  write(*,'(a,es24.17)') '  HP rand1(20) gfortran=', rn(20)
  write(*,'(a,es24.17)') '  HP rand1p(1) gfortran=', rn_p(1)
  write(*,'(a,es24.17)') '  HP rand1p(20)gfortran=', rn_p(20)

  write(*,*)
  write(*,*) '=== 2) reparto de semilla, ', n_walk, ' walkers ==='
  do iw = 1, n_walk
    irn = seed0
    do ic = 1, iw
      call rand1p(rn_ref, irn)
    enddo
    seeds(iw) = irn
    write(*,'(a,i0,a,i0)') '  walker ', iw, ': gfortran=', seeds(iw)
  enddo

  write(*,*)
  write(*,*) '=== 3) gauss3: ', n_gauss, ' sorteos encadenados, walkers 1/2/3 ==='
  do iw = 1, 3
    call fijasemilla(seeds(iw))
    write(*,*)
    write(*,'(a,i0)') '--- walker ', iw
    do ic = 1, n_gauss
      call gauss3(gv(:,ic))
      write(*,'(a,i0,a,3es24.17)') '  sorteo ',ic,' gfortran=', gv(:,ic)
    enddo
  enddo

end program test_rand_gfortran
