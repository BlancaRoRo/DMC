module mtiempos
! Modulo de instrumentacion SOLO para test-tiempos/ -- no forma parte
! del hibrido/ validado. Acumula tiempos de pared (system_clock) en
! contadores globales por metodo, y escribe un informe de reparto al
! final de cada bloque calculo+equilibrio. Ver docs/test-tiempos.md.

 implicit none
 integer, parameter :: i8t=selected_int_kind(15)
 integer, parameter :: r8t=selected_real_kind(15,9)

 integer(kind=i8t), save :: tasa=0_i8t

! ---- opcion=4 (CPU): jerarquia real de llamadas dentro de dmc2 ----
 real(kind=r8t), save :: t_hpsi=0.0_r8t
 real(kind=r8t), save :: t_valibre=0.0_r8t
 real(kind=r8t), save :: t_derananum=0.0_r8t
 real(kind=r8t), save :: t_vpot=0.0_r8t
 real(kind=r8t), save :: t_potenbh=0.0_r8t
 real(kind=r8t), save :: t_ccuerpo=0.0_r8t
 real(kind=r8t), save :: t_rota=0.0_r8t
 real(kind=r8t), save :: t_random=0.0_r8t
 real(kind=r8t), save :: t_dmc2call=0.0_r8t
 real(kind=r8t), save :: t_pasodmc_body=0.0_r8t
 real(kind=r8t), save :: t_total4=0.0_r8t

! ---- opcion=5 (GPU): puente AoS<->SoA + kernel ----
 real(kind=r8t), save :: t_sync=0.0_r8t
 real(kind=r8t), save :: t_seeds=0.0_r8t
 real(kind=r8t), save :: t_pack=0.0_r8t
 real(kind=r8t), save :: t_h2d=0.0_r8t
 real(kind=r8t), save :: t_kernel=0.0_r8t
 real(kind=r8t), save :: t_d2h=0.0_r8t
 real(kind=r8t), save :: t_unpack=0.0_r8t
 real(kind=r8t), save :: t_repart=0.0_r8t
 real(kind=r8t), save :: t_pasodmc_gpu_body=0.0_r8t
 real(kind=r8t), save :: t_total5=0.0_r8t

! ---- opcion=7 (GPU, pipeline de 7 fases): mismo puente AoS<->SoA que
! opcion=5, mas las 3 rutinas de estadisticas por paso (dmcsumapaso,
! denssumapaso, difussumapaso), que en opcion=5 no se instrumentaban
! porque viven fuera de pasodmc_gpu, en el bucle de mmontecarlo.f90.
! Ver v3-cuda-optimizacion/fase3-arquitecturas-alternativas: el 39.7%
! de tiempo "invisible para CUDA" medido con nsys hay que repartirlo
! entre estas piezas para saber cual pesa de verdad. ----
 real(kind=r8t), save :: t_sync7=0.0_r8t
 real(kind=r8t), save :: t_pack7=0.0_r8t
 real(kind=r8t), save :: t_h2d7=0.0_r8t
 real(kind=r8t), save :: t_kernel7=0.0_r8t
 real(kind=r8t), save :: t_d2h7=0.0_r8t
 real(kind=r8t), save :: t_unpack7=0.0_r8t
 real(kind=r8t), save :: t_repart7=0.0_r8t
 real(kind=r8t), save :: t_pasodmc_gpu_pipeline_body=0.0_r8t
 real(kind=r8t), save :: t_dmcsumapaso=0.0_r8t
 real(kind=r8t), save :: t_denssumapaso=0.0_r8t
 real(kind=r8t), save :: t_difussumapaso=0.0_r8t
 real(kind=r8t), save :: t_total7=0.0_r8t

contains

 subroutine tiempos_tic(c0)
  integer(kind=i8t), intent(out) :: c0
   if(tasa.eq.0_i8t) call system_clock(count_rate=tasa)
   call system_clock(c0)
 end subroutine tiempos_tic

 function tiempos_toc(c0) result(dt)
  integer(kind=i8t), intent(in) :: c0
  real(kind=r8t) :: dt
  integer(kind=i8t) :: c1
   call system_clock(c1)
   dt=real(c1-c0,r8t)/real(tasa,r8t)
 end function tiempos_toc

 subroutine tiempos_reset
   t_hpsi=0.0_r8t; t_valibre=0.0_r8t; t_derananum=0.0_r8t; t_vpot=0.0_r8t
   t_potenbh=0.0_r8t; t_ccuerpo=0.0_r8t; t_rota=0.0_r8t; t_random=0.0_r8t
   t_dmc2call=0.0_r8t; t_pasodmc_body=0.0_r8t; t_total4=0.0_r8t
   t_sync=0.0_r8t; t_seeds=0.0_r8t; t_pack=0.0_r8t; t_h2d=0.0_r8t
   t_kernel=0.0_r8t; t_d2h=0.0_r8t; t_unpack=0.0_r8t; t_repart=0.0_r8t
   t_pasodmc_gpu_body=0.0_r8t; t_total5=0.0_r8t
   t_sync7=0.0_r8t; t_pack7=0.0_r8t; t_h2d7=0.0_r8t; t_kernel7=0.0_r8t
   t_d2h7=0.0_r8t; t_unpack7=0.0_r8t; t_repart7=0.0_r8t
   t_pasodmc_gpu_pipeline_body=0.0_r8t
   t_dmcsumapaso=0.0_r8t; t_denssumapaso=0.0_r8t; t_difussumapaso=0.0_r8t
   t_total7=0.0_r8t
 end subroutine tiempos_reset

 subroutine tiempos_escribe4(fichero)
  character(len=*), intent(in) :: fichero
  real(kind=r8t) :: otros

   open(97,file=fichero,status='replace')
   write(97,'(a)') 'reparto de tiempos, opcion=4 (CPU)'
   write(97,'(a,f14.4)') 'tiempo total (bucle bloques+pasos), s = ', t_total4
   write(97,*)
   write(97,'(a)') 'jerarquia real de llamadas dentro de dmc2 (tiempos INCLUSIVOS, no sumar entre niveles):'
   call escribe(97,'  hpsi',t_hpsi,t_total4)
   call escribe(97,'    valibre',t_valibre,t_total4)
   call escribe(97,'    derananum',t_derananum,t_total4)
   call escribe(97,'    vpot',t_vpot,t_total4)
   call escribe(97,'      ccuerpo',t_ccuerpo,t_total4)
   call escribe(97,'      potenbh',t_potenbh,t_total4)
   write(97,*)
   call escribe(97,'rota (todas las llamadas)',t_rota,t_total4)
   call escribe(97,'mrandom (gauss3+rn1)',t_random,t_total4)
   write(97,*)
   call escribe(97,'dmc2 (bucle sobre walkers)',t_dmc2call,t_total4)
   call escribe(97,'pasodmc completo (dmc2+reparticion)',t_pasodmc_body,t_total4)
   otros=t_total4-t_pasodmc_body
   call escribe(97,'otros (E/S por bloque, promedios...)',otros,t_total4)
   close(97)

 end subroutine tiempos_escribe4

 subroutine tiempos_escribe5(fichero)
  character(len=*), intent(in) :: fichero
  real(kind=r8t) :: conversion, otros

   open(97,file=fichero,status='replace')
   write(97,'(a)') 'reparto de tiempos, opcion=5 (GPU)'
   write(97,'(a,f14.4)') 'tiempo total (bucle bloques+pasos), s = ', t_total5
   write(97,*)
   call escribe(97,'sincroniza_globales_gpu',t_sync,t_total5)
   call escribe(97,'reparto de semillas (1 vez)',t_seeds,t_total5)
   call escribe(97,'empaquetar AoS->SoA (host)',t_pack,t_total5)
   call escribe(97,'copia host->device (H2D)',t_h2d,t_total5)
   call escribe(97,'kernel k_dmc2 (device)',t_kernel,t_total5)
   call escribe(97,'copia device->host (D2H)',t_d2h,t_total5)
   call escribe(97,'desempaquetar SoA->AoS (host)',t_unpack,t_total5)
   call escribe(97,'reparticion/compactacion',t_repart,t_total5)
   write(97,*)
   conversion=t_pack+t_h2d+t_d2h+t_unpack
   call escribe(97,'CONVERSION AoS<->SoA total (pack+H2D+D2H+unpack)',conversion,t_total5)
   call escribe(97,'pasodmc_gpu completo',t_pasodmc_gpu_body,t_total5)
   otros=t_total5-t_pasodmc_gpu_body
   call escribe(97,'otros (E/S por bloque, promedios...)',otros,t_total5)
   close(97)

 end subroutine tiempos_escribe5

 subroutine tiempos_escribe7(fichero)
  character(len=*), intent(in) :: fichero
  real(kind=r8t) :: conversion, stats, otros

   open(97,file=fichero,status='replace')
   write(97,'(a)') 'reparto de tiempos, opcion=7 (GPU, pipeline de 7 fases)'
   write(97,'(a,f14.4)') 'tiempo total (bucle bloques+pasos), s = ', t_total7
   write(97,*)
   write(97,'(a)') '-- dentro de pasodmc_gpu_pipeline --'
   call escribe(97,'sincroniza_globales_gpu',t_sync7,t_total7)
   call escribe(97,'empaquetar AoS->SoA (host)',t_pack7,t_total7)
   call escribe(97,'copia host->device (H2D)',t_h2d7,t_total7)
   call escribe(97,'lanza_pipeline (grafo CUDA, device)',t_kernel7,t_total7)
   call escribe(97,'copia device->host (D2H)',t_d2h7,t_total7)
   call escribe(97,'desempaquetar SoA->AoS (host)',t_unpack7,t_total7)
   call escribe(97,'reparticion/compactacion',t_repart7,t_total7)
   write(97,*)
   write(97,'(a)') '-- fuera de pasodmc_gpu_pipeline, en el bucle de pasos --'
   call escribe(97,'dmcsumapaso (energias)',t_dmcsumapaso,t_total7)
   call escribe(97,'denssumapaso (densidades, O(natom^2)/walker)',t_denssumapaso,t_total7)
   call escribe(97,'difussumapaso (difusion, solo primeros ndifus pasos)',t_difussumapaso,t_total7)
   write(97,*)
   conversion=t_pack7+t_h2d7+t_d2h7+t_unpack7
   call escribe(97,'CONVERSION AoS<->SoA total (pack+H2D+D2H+unpack)',conversion,t_total7)
   stats=t_dmcsumapaso+t_denssumapaso+t_difussumapaso
   call escribe(97,'ESTADISTICAS total (dmcsuma+denssuma+difussuma)',stats,t_total7)
   call escribe(97,'pasodmc_gpu_pipeline completo',t_pasodmc_gpu_pipeline_body,t_total7)
   otros=t_total7-t_pasodmc_gpu_pipeline_body-stats
   call escribe(97,'otros (E/S por bloque, promedios...)',otros,t_total7)
   close(97)

 end subroutine tiempos_escribe7

 subroutine escribe(u,etiqueta,t,ttotal)
  integer, intent(in) :: u
  character(len=*), intent(in) :: etiqueta
  real(kind=r8t), intent(in) :: t,ttotal
   write(u,'(a,t55,f12.4,a,f7.3,a)') trim(etiqueta),t,' s  (',100.0_r8t*t/ttotal,' % del total)'
 end subroutine escribe

end module mtiempos
