# Prueba 2: barrido de hilos por bloque (32 -> 128)

## Objetivo

La Prueba 1 (`v4-cuda-pruebas/prueba1-2000w-500pasos-bloque/`) encontró, con `ncu`, que el cuello de botella real del pipeline no son los registros (que llevamos toda `v3-cuda-optimización/myexp-optimizacion/` optimizando) sino que **el grid es demasiado pequeño para llenar la GPU** (0,33 "oleadas" por SM, ocupación conseguida 5,5% frente a un 33,3% teórico -- `ncu` estima hasta 83% de margen por este desequilibrio). Esto ya estaba señalado como pendiente en fases anteriores del proyecto: las 10 llamadas a kernel del pipeline usan **32 hilos/bloque fijo (1 warp/bloque)** en todas, y nunca se había probado con bloques más grandes.

## El cambio

Una sola línea en `dmc2_pipeline.cuf`:
```fortran
threads = 32     ! antes
threads = 128    ! ahora (4 warps/bloque)
blocks = (nmax + threads - 1) / threads   ! sin cambios, se recalcula solo
```
`blocks`/`threads` se reutilizan en las 10 llamadas a kernel del pipeline (`k_fase_a` hasta `k_fase_h`, `k_derananum_t`, `k_vpot_t`) -- un solo sitio que cambiar. Los propios kernels ya calculan su índice global de hilo de forma genérica (`(blockIdx%x-1)*blockDim%x+threadIdx%x`, comparado contra `nw_actual`), y ninguno usa memoria compartida (confirmado en el perfilado de la Prueba 1: `SHARED:0` en todos) -- así que es un cambio de **configuración de lanzamiento**, no de fórmula ni de física.

## Verificación

Pipeline completo, semilla 11, 1000 walkers, 59 bloques x 20 pasos: **energía bit a bit idéntica** a producción (`-679.3359577544`). Confirma que el cambio no altera el resultado, solo cómo se reparten los hilos.

## Resultado

### Ocupación (`ncu`, 2000 walkers, mismo perfilado corto que la Prueba 1)

| Métrica | 32 hilos/bloque (Prueba 1) | 128 hilos/bloque |
|---|---|---|
| Grid Size (bloques) | 125 | **32** |
| Registros/hilo | 126 / 106 | 126 / 106 (sin cambio) |
| Block Limit Registers | 16 | 4 |
| Waves per SM | 0,33 | 0,33 (sin cambio) |
| Ocupación teórica | 33,33% | 33,33% (sin cambio) |
| **Ocupación conseguida** | **5,56% / 5,52%** | **7,56% / 7,51%** |
| Warps activos por SM (conseguidos) | 2,67 / 2,65 | 3,63 / 3,61 |

La ocupación **conseguida** mejora un ~36% relativo (coincide en `k_derananum_t` y `k_vpot_t`). Sobre el papel, un buen indicio.

### Tiempo real (bit a bit idéntico a producción en las 4 escalas)

| Escala | REF (32 hilos/bloque) | 128 hilos/bloque | Diferencia |
|---|---|---|---|
| 500w | 26,39s | 30,31s | **+14,9%** (peor) |
| 1000w | 36,53s | 40,15s | **+9,9%** (peor) |
| 2000w | 58,11s | 59,18s | +1,8% (peor, cerca del ruido) |
| 3000w | 80,98s | 81,21s | +0,3% (neutro) |

**Resultado contraintuitivo: peor en las 4 escalas**, a pesar de que la ocupación conseguida mejora un 36%. La brecha se va cerrando según crecen los walkers (de +14,9% a +0,3%), lo que sugiere que a escalas mucho más grandes podría dejar de perjudicar -- pero en el rango probado (500-3000w), no hay ninguna escala donde 128 hilos/bloque gane.

### Por qué las métricas "por bloque" mejoran pero el tiempo total empeora (confirmado, no solo hipótesis)

Todas las métricas de "qué tan lleno va cada bloque mientras trabaja" mejoran con 128 hilos (ocupación conseguida, warps activos por SM). Pero hay una métrica distinta -- **qué fracción del tiempo total tiene alguna SM trabajando** -- que va en la dirección contraria y explica el resultado:

| | 32 hilos/bloque | 128 hilos/bloque |
|---|---|---|
| Elapsed Cycles (duración total) | 55.044.513 | 56.411.594 |
| SM Active Cycles (con trabajo real) | 43.724.557 | 33.359.998 |
| **% del tiempo con SMs realmente ocupadas** | **79,4%** | **59,1%** |

Con 128 hilos/bloque, las SMs pasan **casi el doble de tiempo relativo sin nada que hacer** que con 32. Es el efecto clásico de "cola larga" (*straggler*) en reparto de tareas: con 125 bloques pequeños, si uno tarda un poco más de lo normal, siempre hay otro bloque pequeño de repuesto para mantener ocupada a la SM que ya terminó -- el desequilibrio se diluye. Con solo 32 bloques grandes, cuando se agota el reparto y algún bloque tarda más (por variación real de carga entre walkers -- distintos vecinos, distintas ramas de la física), **no queda nada de repuesto**: las SMs que ya terminaron se quedan paradas esperando a que acabe el bloque más lento. Coincide exactamente con el aviso que ya había dado `ncu` en la Prueba 1 sobre "desequilibrios de carga... entre bloques".

### Interpretación (hipótesis, no confirmada a fondo)

`Waves Per SM` no cambia (0,33 en los dos casos) -- el grid sigue sin llenar la GPU ni una vez, eso es indiferente al tamaño de bloque. Lo que sí cambia es la **granularidad**: pasar de 125 bloques pequeños a 32 bloques grandes le da al planificador de la GPU **muchas menos unidades de trabajo que repartir** entre las SMs -- más difícil equilibrar la carga entre SMs con 32 piezas grandes que con 125 piezas pequeñas, aunque cada pieza individual (cuando le toca sitio) aproveche mejor su SM. El aumento de ocupación *conseguida* por bloque no compensa la pérdida de flexibilidad de reparto entre bloques.

Mismo patrón que ya vimos varias veces hoy con `myexp` (el cambio (b) con `GTEST` fijo+(a)): una métrica de recursos por hilo/bloque mejora de forma medible y real, pero el tiempo de pared se mueve en la dirección contraria -- la intuición de "ocupación más alta = más rápido" no se sostiene de forma fiable en este pipeline concreto, con grids tan pequeños.

### Análisis adicional: ¿cómputo, memoria, caché L1, o registros/spilling?

Preguntas concretas, respondidas con `ncu` sobre los mismos perfiles `--set full`:

**¿Cómputo o memoria saturados?** Ninguno de los dos, en ninguna de las 2 variantes:

| Métrica (`k_derananum_t`) | 32 hilos/bloque | 128 hilos/bloque |
|---|---|---|
| Compute (SM) Throughput | 5,60% | 5,47% |
| Memory Throughput | 9,25% | 9,18% |
| DRAM Throughput | 0,03% | 0,03% |
| L1/TEX Cache Throughput | 11,38% | 12,82% |

Todas las cifras muy por debajo de saturación, prácticamente iguales entre las 2 variantes -- no es un cuello de botella de cómputo ni de memoria ni de caché L1 (esta última sube un poco con más hilos, pero sigue lejísimos de saturarse).

**¿Más hilos = más registros reservados por hilo, o menos bloques por SM, o más *spilling*?**

| Métrica | 32 hilos/bloque | 128 hilos/bloque |
|---|---|---|
| Registros/hilo (`k_derananum_t`) | 126 | **126 (igual)** |
| Registros/hilo (`k_vpot_t`) | 106 | **106 (igual)** |
| Memoria local, carga (`k_derananum_t`) | 1,15 GB | 1,13 GB (igual) |
| Memoria local, escritura (`k_derananum_t`) | 698,22 MB | 687,56 MB (igual) |
| Memoria local, carga (`k_vpot_t`) | 275,72 MB | 277,01 MB (igual) |
| Memoria local, escritura (`k_vpot_t`) | 198,74 MB | 199,59 MB (igual) |

Los registros por hilo **no cambian** con el tamaño de bloque -- es una propiedad del kernel ya compilado (el compilador decide cuántos registros usar al compilar, antes de que en tiempo de ejecución se elija 32 o 128 hilos/bloque). Lo que sí cambia con el tamaño de bloque es cuántos *bloques* caben a la vez en una SM dado ese presupuesto fijo (`Block Limit Registers`: 16 con 32 hilos/bloque, baja a 4 con 128 -- ya visto en la sección de ocupación).

Y el hallazgo más importante: **ya hay *spilling* real y sustancial (~1,15 GB de tráfico de memoria local en `k_derananum_t`) en la configuración original de 32 hilos/bloque**, y no cambia prácticamente nada al subir a 128. Subir los hilos por bloque no crea ni empeora el *spilling* -- ya estaba ahí desde antes, es una característica del kernel compilado, no de esta prueba.

**Conclusión de este análisis**: el problema no es ni cómputo, ni memoria, ni caché L1, ni que subir hilos/bloque agrave el *spilling* (no lo agrava). Es específicamente el **tamaño del grid** (sección anterior, `Waves Per SM=0,33` en ambos casos) combinado con un *spilling* ya preexistente que ninguna de las 2 configuraciones de hilos soluciona -- ese *spilling* (~1,15 GB de tráfico por kernel) sería el siguiente candidato razonable a investigar, con `-Mcuda=maxregcount` o revisando qué variables locales de `derananum`/`He_dihydrogen` están forzando ese volumen.

### Análisis adicional: motivos de stall, predicación, y timeline de `nsys`

**Motivos de espera por instrucción** (`ncu`, métricas `smsp__average_warps_issue_stalled_*`):

| Motivo | `k_derananum_t` 32h | `k_derananum_t` 128h | `k_vpot_t` 32h | `k_vpot_t` 128h |
|---|---|---|---|---|
| `long_scoreboard` (memoria L1TEX/global) | 12,92 | 13,34 | 7,51 | 7,62 |
| `short_scoreboard` (memoria MIO) | 1,36 | 1,53 | **7,11** | **9,06** |
| `not_selected` (competencia entre warps) | 0,00 | 0,00 | 0,00 | 0,00 |
| Ramas uniformes (branch efficiency) | 100% | 100% | 99,82% | 99,82% |

`not_selected=0,00` en los 4 casos confirma que el planificador de la GPU **nunca** tiene que elegir entre varios warps listos compitiendo -- casi nunca hay más de uno disponible, coherente con la ocupación tan baja ya vista. El motivo dominante es la latencia de memoria (`long_scoreboard`+`short_scoreboard`), y en `k_vpot_t` el stall por `short_scoreboard` sube un 27% con 128 hilos (7,11→9,06) -- pista concreta y específica de ese kernel.

`Avg. Not Predicated Off Threads Per Warp`: **17,28 de 32** (32h) / **17,81 de 32** (128h) -- en promedio solo ~17-18 de los 32 carriles de cada warp hacen trabajo real (el resto va predicado/apagado, no por divergencia de rama real -- eso sigue al 100%). Real y sustancial, pero casi idéntico entre las 2 configuraciones -- no es lo que explica la diferencia 32 vs 128, es una ineficiencia aparte que ya existía.

**El dato que sí explica directamente por qué 128 hilos es más lento pese a mejorar la ocupación**: `SM Active Cycles / Elapsed Cycles` -- con 32 hilos/bloque las SMs están ocupadas el **79,4%** del tiempo total del kernel; con 128 hilos, solo el **59,1%** (ver más arriba). Con tan pocos warps activos por SM (2,6-3,6), no hay suficientes de repuesto para tapar la espera de memoria cambiando de uno a otro -- el mecanismo normal de la GPU para ocultar latencia apenas funciona aquí.

**Timeline (`nsys --cuda-graph-trace=node`)**: se generaron capturas cortas para las 2 configuraciones (`nsys_32hilos.nsys-rep`, `nsys_128hilos.nsys-rep`, en esta carpeta) -- confirman que `k_derananum_t`/`k_vpot_t` arrancan casi simultáneamente en sus 2 streams (la horquilla fork-join funciona como está diseñada), y que `k_derananum_t` se llama 2 veces por paso DMC (una por cada evaluación de `hpsi`). El hueco medio entre iteraciones de pipeline salió menor con 128 hilos en la muestra corta capturada, lo contrario de lo que cabría esperar dado el resultado final -- con una muestra tan pequeña (5 iteraciones) no es una lectura fiable, así que no se saca conclusión de ahí. Sin entorno gráfico disponible en esta sesión no se puede inspeccionar el timeline visualmente -- los `.nsys-rep` quedan guardados para abrirlos con la interfaz de Nsight Systems si se dispone de ella.

### Conclusión

**No se lleva a producción.** Empeora en todas las escalas probadas (500-3000w). Queda documentado como resultado negativo real -- útil saberlo antes de intentarlo en la corrida larga real, no después. Si se quisiera seguir tirando de este hilo, los candidatos naturales serían: (a) probar 64 hilos/bloque (un punto intermedio, menos drástico); (b) probar en la escala de la Prueba 1 (2000w con bloques de 500+ pasos, más cercana al uso real) por si el efecto cambia con corridas más largas; (c) investigar si el problema de fondo (grid pequeño) tiene otra solución -- por ejemplo, procesar varios pasos DMC por lanzamiento de kernel en vez de relanzar el grafo cada paso (ya apuntado como idea en fases anteriores del proyecto).

## Ficheros

- `gpu-threads128/`: copia aislada con el cambio, no toca producción.
- `ncu_threads128.ncu-rep`, `ncu_threads128_detalle.txt`, `ncu_threads128_stdout.log`: perfil de ocupación.
- `comparar_threads128.sh`, `resultados/`: script y logs completos de la comparación de 4 escalas.
- `nsys_32hilos.nsys-rep`, `nsys_128hilos.nsys-rep` (+ `.sqlite` generados al analizarlos): capturas de timeline con Nsight Systems, para inspeccionar en la interfaz gráfica si se dispone de ella.
- `traza_32hilos_muestra.csv`, `traza_128hilos_muestra.csv`: primeras filas de la traza cronológica en texto (`nsys stats --report cuda_gpu_trace`).
