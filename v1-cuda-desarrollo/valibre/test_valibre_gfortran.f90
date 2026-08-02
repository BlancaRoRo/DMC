! test_valibre_gfortran.f90
!
! Compara valibre de mwavef.f90 ORIGINAL compilado con gfortran contra
! los mismos valores que test_valibre (CPU-nvfortran, en valibre.cuf).
! No hay ninguna operacion aritmetica en valibre (solo constantes
! literales 1.0/0.0), asi que se espera coincidencia exacta trivial.
!
! Compilar y ejecutar: ver docs-kernels/valibre.md

program test_valibre_gfortran
 use mwavef, only: valibre
 use mtipos, only: walker, allocatewalker
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 integer(kind=i4), parameter :: n_atom = 5
 integer(kind=i4), parameter :: n_walk = 3
 type(walker) :: w1
 integer(kind=i4) :: iw, ia

  do iw = 1, n_walk
    call allocatewalker(w1, n_atom)
    call valibre(w1)

    write(*,*)
    write(*,'(a,i0)') '--- walker ', iw
    write(*,'(a,es24.17)') '  wf     gfortran=', real(w1%lw%wf,r8)
    write(*,'(a,es24.17)') '  wfhe4  gfortran=', real(w1%lw%wfhe4,r8)
    write(*,'(a,es24.17)') '  wfhe3  gfortran=', real(w1%lw%wfhe3,r8)
    write(*,'(a,es24.17)') '  wfm    gfortran=', real(w1%lw%wfm,r8)
    write(*,'(a,es24.17)') '  wfx    gfortran=', real(w1%lw%wfx,r8)
    write(*,'(a,es24.17)') '  kin    gfortran=', w1%lw%kin
    write(*,'(a,es24.17)') '  pot    gfortran=', w1%lw%pot
    write(*,'(a,es24.17)') '  ene    gfortran=', w1%lw%ene
    write(*,'(a,i0)')      '  signoup gfortran=', w1%lw%signoup
    write(*,'(a,i0)')      '  signodw gfortran=', w1%lw%signodw
    do ia = 1, n_atom
      write(*,'(a,i0,a,3es24.17)') '  dwf(',ia,') gfortran=', w1%dwf(ia)%comp
    enddo
    write(*,'(a,2es24.17)') '  dphi gfortran=', w1%dphi
  enddo

end program test_valibre_gfortran
