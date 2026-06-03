module mtiempos_pasodmc
  use cudafor
    implicit none
  ! Las variables declaradas aquí son globales para quien use el módulo
  real(kind=8) :: t_total_aos_soa = 0.0_8
  real(kind=8) :: t_total_gpu     = 0.0_8
  real(kind=8) :: t_total_gestion = 0.0_8
  
  type(cudaEvent) :: g_start, g_stop
  logical :: profiler_init = .false.

contains
  subroutine init_profiler()
    integer :: istat
    if (.not. profiler_init) then
      istat = cudaEventCreate(g_start)
      istat = cudaEventCreate(g_stop)
      profiler_init = .true.
    endif
  end subroutine

  subroutine print_profile_results()
    print *, "--- RESUMEN FINAL DE TIEMPOS ---"
    print *, "AOS <-> SOA (CPU): ", t_total_aos_soa, " s"
    print *, "GPU (Kernels):     ", t_total_gpu,     " s"
    print *, "Gestión (CPU):     ", t_total_gestion, " s"
  end subroutine
end module