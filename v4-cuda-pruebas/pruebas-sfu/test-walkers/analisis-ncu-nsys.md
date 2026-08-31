# test-walkers: análisis `nsys`/`ncu` -- ciclos, instrucciones, stall y ocupación

## 1. Objetivo

Con las 10 corridas de `test-walkers` completas (ver `README.md` para tiempos/datos de energía), se perfila cada escala (500-2500w) con `nsys` (desglose de tiempo por kernel) y `ncu` (ciclos, instrucciones totales/FMA/XU, motivo de stall, registros, ocupación -- mismo nivel de detalle que el resto de `v3-cuda-optimización/`) para ver qué cambia con la escala y si hay algo nuevo que atacar.

## 2. Desglose de tiempo por kernel (`nsys --cuda-graph-trace=node`)

| Kernel | 500w | 1000w | 1500w | 2000w | 2500w |
|---|---|---|---|---|---|
| `k_derananum_he4_t` | 33% | 34% | 33% | 33% | 32% |
| `k_vpot_3warp_t` | 30% | 32% | 32% | 32% | 32% |
| `k_derananum_resto_t` | 29% | 29% | 32% | 32% | 31% |
| `k_fase_h` | 2% | 1% | 1% | 1% | 1% |
| `k_fase_a` | 2% | 1% | 0% | 0% | 1% |
| resto (`join`/`fase_d/g/f/c`) | <1% cada uno | | | | |

Reparto estable en las 5 escalas -- los 3 kernels concurrentes (`he4`/`vpot`/`resto`) siguen dominando (~95-97%), mismo patrón que `control-final-cpu-vs-gpu.md` a 2000w.

## 3. Ciclos, instrucciones y stall por kernel (`ncu`, media de 2-3 lanzamientos)

| Walkers | Kernel | Registros | Ocupación | Ciclos | Instr. totales | FMA | XU (SFU) | Stall dominante |
|---|---|---|---|---|---|---|---|---|
| 500 | `k_vpot_3warp_t` | 94 | 6,2% | 999.296 | 1.649.222 | 163.292 | 13.248 | MIO 55,8% |
| 500 | `k_derananum_he4_t` | 90 | 2,1% | 1.199.054 | 989.088 | 144.816 | 15.200 | MIO 73,0% |
| 500 | `k_derananum_resto_t` | 111 | 2,1% | 1.083.422 | 977.728 | 121.152 | 7.792 | MIO 68,5% |
| 500 | `k_fase_h` | 94 | 2,1% | 226.958 | 200.848 | 26.880 | 4.352 | MIO 70,9% |
| 1000 | `k_vpot_3warp_t` | 94 | 8,8% | 1.602.867 | 3.298.435 | 326.574 | 26.496 | MIO 64,0% |
| 1000 | `k_derananum_he4_t` | 90 | 2,8% | 1.293.448 | 1.978.163 | 289.629 | 30.400 | MIO 73,5% |
| 1000 | `k_derananum_resto_t` | 111 | 2,8% | 1.204.218 | 1.955.444 | 242.301 | 15.584 | MIO 69,0% |
| 1000 | `k_fase_h` | 94 | 2,9% | 263.190 | 401.682 | 53.757 | 8.704 | MIO 72,4% |
| 1500 | `k_vpot_3warp_t` | 94 | 14,7% | 2.307.898 | 4.845.368 | 479.734 | 38.916 | MIO 70,5% |
| 1500 | `k_derananum_he4_t` | 90 | 5,0% | 1.525.674 | 2.905.446 | 425.397 | 44.650 | MIO 74,7% |
| 1500 | `k_derananum_resto_t` | 111 | 5,0% | 1.418.407 | 2.872.076 | 355.884 | 22.889 | MIO 71,7% |
| 1500 | `k_fase_h` | 94 | 5,0% | 327.750 | 589.991 | 78.960 | 12.784 | MIO 75,3% |
| 2000 | `k_vpot_3warp_t` | 94 | 16,7% | 2.312.488 | 6.494.263 | 642.991 | 52.164 | MIO 71,2% |
| 2000 | `k_derananum_he4_t` | 90 | 5,8% | 1.522.172 | 3.894.521 | 570.210 | 59.850 | MIO 75,2% |
| 2000 | `k_derananum_resto_t` | 111 | 5,8% | 1.422.402 | 3.849.792 | 477.033 | 30.681 | MIO 72,8% |
| 2000 | `k_fase_h` | 94 | 5,8% | 333.681 | 790.825 | 105.837 | 17.136 | MIO 75,8% |
| **2500** | `k_vpot_3warp_t` | 94 | 20,5% | **4.448.265** | 8.108.437 | 802.837 | 65.136 | MIO 69,8% |
| **2500** | `k_derananum_he4_t` | 90 | 7,1% | 2.695.502 | 4.852.713 | 710.504 | 74.575 | MIO 77,0% |
| **2500** | `k_derananum_resto_t` | 111 | 7,1% | 2.528.699 | 4.796.978 | 594.402 | 38.230 | MIO 75,2% |
| **2500** | `k_fase_h` | 94 | 7,1% | 613.062 | 991.673 | 132.717 | 21.488 | MIO 76,6% |

**Stall dominante siempre `MIO` (memory input/output, la misma familia que `short_scoreboard`)** -- confirma otra vez, a esta escala pequeña también, el mismo diagnóstico de toda la sesión: el cuello de botella real es esperar el resultado de la SFU compartida, no la emisión ni la memoria global. Sube con walkers (55,8%→70-77%) porque la ocupación mejora (más warps para solapar), lo que reduce el resto de esperas más rápido que la propia SFU -- mismo mecanismo ya visto en `stall-antes-despues-y-reintento-concurrencia.md`.

## 4. Anomalía real: algo pasa entre 2000w y 2500w, no es ruido de una sola medida

Ciclos de `k_vpot_3warp_t` por walker (para aislar el efecto de escala pura):

| Walkers | Ciclos/walker | Tendencia |
|---|---|---|
| 500 | 1.998,6 | -- |
| 1000 | 1.602,9 | mejora (más ocupación) |
| 1500 | 1.538,6 | mejora |
| 2000 | **1.156,2** | mejora fuerte |
| 2500 | **1.779,3** | **empeora de golpe, peor que 1500w** |

La eficiencia por walker mejora de forma consistente de 500 a 2000w (más ocupación, mejor solape de latencia) y **se rompe bruscamente en 2500w** -- no es una desviación pequeña, es peor que la de 1500w con más walkers y más ocupación teórica disponible. Esto **coincide exactamente** con la anomalía de varianza ya detectada por `nsys` en la sección anterior (`StdDev` ~10x mayor a 2500w, con lanzamientos puntuales de más del doble del tiempo medio) -- dos métricas independientes (`nsys` y `ncu`, medidas en corridas separadas) señalan el mismo punto de la escala.

**Hipótesis más probable: cuantización de oleadas de bloques** (mismo mecanismo ya confirmado en `split-he-dihidrogen.md`, Intento 9, para la anomalía de N=2000 en `k_vpot_4warp_t`). Con `k_vpot_3warp_t` a 94 registros/hilo y bloques de 96 hilos, el número de bloques residentes por SM es fijo -- al subir walkers, el número total de bloques (`blocks_vpot=ceil(2·nwalkers/32)`) puede cruzar un múltiplo del límite de bloques/SM justo entre 2000w y 2500w, dejando una última oleada parcial mal aprovechada. **No se confirmó la causa exacta** (no estaba en el alcance de esta batería -- requeriría medir `Achieved Occupancy`/`Waves Per SM` exactas con `ncu --set full`, que no se lanzó para no alargar más esta sesión de perfilado), pero el patrón encaja.

**Relevancia para la corrida final del TFG**: la corrida final usa 2000 walkers (justo el punto más eficiente de este barrido) con 128 bloques -- la anomalía de 2500w probablemente no aplica ahí, pero si en algún momento se prueba con más walkers, vale la pena remedir en vez de asumir que la eficiencia sigue mejorando monótonamente.

## 5. Ocupación: confirma el límite ya conocido, sin sorpresas nuevas

Ocupación lograda sube de 2,1% (500w) a 20,5% (2500w) en `k_vpot_3warp_t` -- consistente con el diseño de rejilla (`blocks=ceil(2·nwalkers/32)`, `nw_actual` real usa solo la mitad de los slots lanzados). Sigue muy por debajo de saturar la GPU en todo el rango -- mismo diagnóstico que `split-he-dihidrogen.md` (Intento 6/7: la ocupación de estos kernels no está limitada por registros, está limitada por el tamaño del problema). No hay margen de optimización de código aquí -- ya se investigó a fondo (memoria compartida, más warps, fusión de kernels) sin éxito repetible.

## 6. Conclusión

- El reparto de tiempo entre fases es estable en todo el rango 500-2500w -- ninguna fase nueva que atacar.
- El stall sigue siendo SFU (`MIO`) en el 100% de los casos medidos -- confirma el techo ya diagnosticado, no revela una vía de código nueva.
- **Hallazgo real**: anomalía de eficiencia en 2500w (ciclos/walker peor que a 1500w, coincide con alta varianza en `nsys`) -- posible cuantización de oleadas de bloques, no confirmada del todo. No afecta a la config real del TFG (2000w), pero merece nota si se escala por encima de eso en el futuro.

## Ficheros

- `nsys_${w}w.nsys-rep` en cada subcarpeta `test-${w}w/` (abrir con `nsys-ui` para la traza completa).
- Perfiles `ncu` no persistidos (quedaron en `/tmp`, reproducibles con los `in.mcv-gpu`/binarios ya guardados en cada subcarpeta).
