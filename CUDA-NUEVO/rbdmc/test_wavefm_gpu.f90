! ============================================================
! test_wavefm_gpu.f90
!
! Compara wavefm() CPU (mwavef.f90) con wavefm_gpu() (GPU).
!
! Flujo:
!   1. Inicializa variables de mparametros (nhe4, pmix, ...)
!   2. Crea T_NW walkers con posiciones aleatorias
!   3. Llama wavefm(w) de mwavef.f90 para cada walker -> wfm_cpu
!   4. Convierte walkers a SOA y llama wavefm_gpu     -> wfm_gpu
!   5. Compara wfm_cpu vs wfm_gpu
!
! Compilación:
!   make -f Makefile.cuda test_wavefm_gpu
! ============================================================
program test_wavefm_gpu

  use gpu_wavefm   ! trae mtipos y mparametros
  use mwavef       ! para wavefm(w1)
  implicit none

  ! Parámetros con prefijo T_ para no chocar con mparametros
  integer, parameter :: T_NW   = 8
  integer, parameter :: T_NHE4 = 3
  integer, parameter :: T_NHE3 = 2
  integer, parameter :: T_NGAT = T_NHE4 + T_NHE3

  type(walker)     :: w(T_NW)
  type(walkers_soa):: soa
  real(8) :: wfm_cpu(T_NW), wfm_gpu_out(T_NW)
  real(8) :: tmp
  integer :: iw, ia
  logical :: ok

  ! ----------------------------------------------------------
  ! Inicializar variables de mparametros que usa wavefm()
  ! ----------------------------------------------------------
  nhe4   = T_NHE4
  nhe3   = T_NHE3
  ngatom = T_NGAT
  natom  = T_NGAT
  pmix(1) = 2.2d0
  pmix(2) = 5.0d0
  pmix(3) = 0.3d0

  ! ----------------------------------------------------------
  ! Crear walkers con posiciones aleatorias
  ! ----------------------------------------------------------
  call random_seed()
  do iw = 1, T_NW
    call allocatewalker(w(iw), T_NGAT)
    do ia = 1, T_NGAT
      call random_number(tmp); w(iw)%atom(ia)%comp(1) = (tmp - 0.5d0) * 10.d0
      call random_number(tmp); w(iw)%atom(ia)%comp(2) = (tmp - 0.5d0) * 10.d0
      call random_number(tmp); w(iw)%atom(ia)%comp(3) = (tmp - 0.5d0) * 10.d0
    enddo
  enddo

  write(*, '(A)') "=== Test wavefm: CPU (mwavef.f90) vs GPU ==="
  write(*, '(A,I3,2(A,I2))') "  T_NW=", T_NW, "  T_NHE4=", T_NHE4, "  T_NHE3=", T_NHE3

  ! ----------------------------------------------------------
  ! CPU: wavefm(w) de mwavef.f90, walker por walker
  ! ----------------------------------------------------------
  do iw = 1, T_NW
    call wavefm(w(iw))
    wfm_cpu(iw) = real(w(iw)%lw%wfm, 8)
  enddo

  ! ----------------------------------------------------------
  ! Conversión AOS (walker) -> SOA
  ! walkers_to_soa usa natom de mparametros (= T_NGAT)
  ! ----------------------------------------------------------
  call walkers_to_soa(w, int(T_NW, 4), soa)

  ok = .true.
  do iw = 1, T_NW
    do ia = 1, T_NGAT
      if (soa%x(iw,ia) /= w(iw)%atom(ia)%comp(1) .or. &
          soa%y(iw,ia) /= w(iw)%atom(ia)%comp(2) .or. &
          soa%z(iw,ia) /= w(iw)%atom(ia)%comp(3)) ok = .false.
    enddo
  enddo
  write(*, '(A,A)') "  AOS(walker)->SOA: ", merge("[PASS]", "[FAIL]", ok)

  ! ----------------------------------------------------------
  ! GPU: wavefm_gpu sobre el SOA
  ! ----------------------------------------------------------
  call wavefm_gpu(soa, pmix, int(T_NHE4, 4), int(T_NGAT, 4))
  call soa_to_array_wfm(soa, wfm_gpu_out)

  ! ----------------------------------------------------------
  ! Comparación CPU vs GPU
  ! ----------------------------------------------------------
  ok = all(abs(wfm_gpu_out - wfm_cpu) <= 1.d-12 * abs(wfm_cpu))
  write(*, '(A,A)') "  CPU vs GPU:       ", merge("[PASS]", "[FAIL]", ok)
    write(*, '(A)') "  iw  wfm_cpu              wfm_gpu              err_rel"
    do iw = 1, T_NW
      write(*, '(I4,2ES22.14,ES12.3)') iw, wfm_cpu(iw), wfm_gpu_out(iw), &
            abs(wfm_gpu_out(iw) - wfm_cpu(iw)) / abs(wfm_cpu(iw))
    enddo
  

  ! ----------------------------------------------------------
  ! Limpieza
  ! ----------------------------------------------------------
  do iw = 1, T_NW
    call deallocatewalker(w(iw))
  enddo
  call free_soa(soa)

end program test_wavefm_gpu
