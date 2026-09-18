! test_pow_gfortran.f90
!
! Referencia REAL: x**y calculado por gfortran (la CPU original, el
! estandar de facto de todo el proyecto) -- mismos pares (rij,nu) que
! test_pow_gpu.cuf, para poder comparar linea a linea.
program test_pow_gfortran
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i4), parameter :: nrij = 20
 integer(kind=i4), parameter :: nnu = 3
 real(kind=r8) :: nus(nnu) = [4.725025_r8, 5.725025_r8, 9.763290_r8]
 real(kind=r8) :: rijs(nrij)
 integer(kind=i4) :: i, j
 real(kind=r8) :: r

  do i=1,nrij
    rijs(i) = 0.3_r8 + (i-1)*0.3_r8
  enddo

  write(*,'(a)') 'rij, nu, x**y_gfortran'
  do j=1,nnu
    do i=1,nrij
      r = rijs(i)**nus(j)
      write(*,'(f6.2,1x,f10.6,1x,es24.16)') rijs(i), nus(j), r
    enddo
  enddo

end program test_pow_gfortran
