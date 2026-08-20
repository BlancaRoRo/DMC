# Fase 3: arquitecturas alternativas

Punto de partida (`README.md` del proyecto): con la Fase 1 agotada (repartir trabajo dentro de un kernel no dio resultado para `derananum`/`vpot`), tocaba explorar arquitecturas distintas — empezando por comprobar si el "kernel persistente" que proponía el plan original tenía sentido, con datos reales antes de construir nada.

## 1. Descartado: el coste de relanzar el grafo cada paso es insignificante

`nsys` sobre `qmccluster_pipeline` a 250 walkers (104 pasos DMC): `cudaGraphLaunch` es el **0,15%** del tiempo total. La hipótesis de partida del plan (que relanzar el grafo cada paso sale caro) no se sostiene — construir un kernel persistente para evitarlo atacaría un problema que casi no existe.

## 2. El 39,7% "invisible para CUDA" — de dónde viene de verdad

`nsys` no puede medir código Fortran que no llama a CUDA — a 250 walkers, el **39,7%** del tiempo total no pasa por ninguna API de CUDA. Instrumentado con el mismo framework de tiempos ya usado en `opcion=5` (`mtiempos.f90`: `t_pack`, `t_h2d`, `t_kernel`, `t_d2h`, `t_unpack`, `t_repart`), extendido a `pasodmc_gpu_pipeline` (`opcion=7`, que no lo tenía) y a las 3 rutinas de estadísticas por paso (`dmcsumapaso`, `denssumapaso`, `difussumapaso`, llamadas desde `mmontecarlo.f90`, tampoco instrumentadas antes):

| Componente | 250 walkers | 2.500 walkers |
|---|---|---|
| `lanza_pipeline` (GPU real) | 61,2% | 47,4% |
| `sincroniza_globales_gpu` | 15,9% | 19,6% |
| `denssumapaso` (O(n²)) | 13,8% | 20,0% |
| Traspaso AoS↔SoA (pack+H2D+D2H+unpack) | 5,4% | 9,9% |
| Reparto/compactación | 0,8% | 1,2% |
| `dmcsumapaso` + `difussumapaso` | 0,2% | 0,5% |

**Ni la hipótesis del usuario (el traspaso CPU↔GPU) ni la mía (solo `denssumapaso`) acertaban del todo** — el traspaso resultó ser el más pequeño de los tres "no-GPU" grandes, y `sincroniza_globales_gpu` (que ninguno de los dos había señalado) resultó pesar tanto como `denssumapaso`.

## 3. `sincroniza_globales_gpu`: arreglado, pero la ganancia real fue mucho menor de lo esperado

### El diagnóstico inicial (parcialmente incorrecto)

`sincroniza_globales_gpu` sincroniza 25 variables escalares `device` desde sus equivalentes en `mparametros` — de esas 25, **24 son constantes físicas fijadas una vez al leer `in.mcv`/`heh2m.pot` y nunca cambian durante la simulación**; solo `etrial` se actualiza paso a paso de verdad. Sin embargo, la rutina original sincronizaba las 25, **en cada paso DMC**.

### El arreglo

`msync_gpu.cuf`: se separó en dos rutinas nuevas, **sin tocar `sincroniza_globales_gpu`** (que sigue usándola tal cual `pasodmc_gpu`/`opcion=5` y `pasodmc_cpu_gpurand`/`opcion=6`, ya validadas):

- `sincroniza_constantes_gpu`: las 24 fijas — se llama **una sola vez**, reutilizando el bloque `if (.not.iniciado)` que `pasodmc_gpu_pipeline` (`msteps.f90`) ya tenía para el reparto de semillas y la construcción del grafo — ningún mecanismo nuevo.
- `sincroniza_etrial_gpu`: solo `etrial` — se sigue llamando en cada paso.

**Verificado bit a bit idéntico** (1000w/1eq/2calc/20pasos) antes de medir.

### La sorpresa: casi todo el coste era arranque de CUDA, no las copias redundantes

`nsys cuda_api_sum` antes y después del arreglo:

| | Llamadas `cudaMemcpyToSymbol` | Tiempo total | De las cuales: 1 llamada de arranque | El resto |
|---|---|---|---|---|
| Antes | 2.829 | 299,6 ms | 268,5 ms | 31,1 ms (las 24 copias/paso) |
| Después | 254 | 277,5 ms | 270,6 ms (sin cambios) | 6,9 ms |

El número de llamadas bajó como se esperaba (×11), confirmando que el cambio funciona — pero **el 90% del coste medido era una única llamada de arranque** (con toda probabilidad, la carga perezosa del módulo CUDA compilado — un binario con 7 fases + las tablas de `myexp`/`mypow`/`mysin`/`mycos` tarda en cargarse la primera vez, sea cual sea el código que la dispare primero) — algo que ningún reparto de asignaciones puede evitar. **Ahorro real: 24,2 ms sobre ~3 s de corrida (~0,8%)**, no el 15-20% que sugería la medida inicial sin desglosar.

**Se mantiene el arreglo** (correcto, sin riesgo, gratis) pero queda claro que no era la palanca grande que parecía.

## 4. `denssumapaso`: réplica positiva, fusión propuesta y verificada

Con `sincroniza_globales_gpu` corregido y su magnitud real entendida, `denssumapaso` era el candidato más sólido: coste real y recurrente (no arranque), que además **crece con la escala** (13,8%→20,0%).

Réplica aislada del histograma más pesado (`drb44`, patrón nuevo: muchos walkers incrementan el MISMO histograma compartido vía `atomicadd`, a diferencia de todo lo probado en la Fase 1): **positiva y creciente con la escala** (7,3x a 250 walkers, 55,9x a 3.000, bit a bit exacto en las 5 escalas probadas).

Se identificó que portar el kernel tal cual exigiría un viaje CPU↔GPU extra cada paso (el reparto de población pasa en CPU, después de traer las posiciones de vuelta) — resuelto pesando cada walker por `nsons` **antes** del reparto (matemáticamente equivalente, ya que los clones son posiciones idénticas al padre), lo que permite fusionar el histograma como una fase más del mismo grafo CUDA (`k_fase_h`, justo después de `k_fase_g`, que ya calcula `nsons_p` sobre las posiciones finales) sin reparto en GPU ni copias H2D adicionales.

Verificado contra la `denssumapaso` real (no una reimplementación, ver `MEMORY.md`): el histograma dominante es bit a bit exacto; los histogramas angulares (que pesan por `1/sin(θ)`, no por `+1.0`) difieren en ~1e-14 relativo, confirmado como ruido de redondeo por reordenación de suma (no un fallo de lógica) — muy por debajo del error estadístico propio de la simulación DMC. Detalle completo en `prueba_denssumapaso/prueba_denssumapaso.md`.

**Implementado**: `k_fase_h` añadida como 8ª fase del mismo grafo CUDA (`dmc2_pipeline.cuf`, justo después de `k_fase_g`), con histogramas de device persistentes (reset una vez por bloque, no por paso). `denssumapaso` (CPU) ya no se llama paso a paso en `opcion=7`; se sustituye por una única copia D2H + inyección en los acumuladores reales al final de cada bloque (`vuelca_histogramas_gpu`, `mmontecarlo.f90`). `denssumapaso`/`mdensidades.f90` no se tocan (siguen intactas para `opcion=4/5/6`; solo se añadieron 6 getters/setters de solo lectura/escritura).

Medido en producción (`qmccluster_pipeline`, 250 walkers, mismo `in.mcv`): el coste de `denssumapaso` en el desglose de tiempos pasó de **0,382 s (10,6% del total) a 0,004 s (0,08%)** — ~95x. Sin errores, sin NaN, población final correcta (250 walkers). Los histogramas de conteo dan sus totales exactos esperados (190,0 para pares He4-He4, 20,0 para pares con la impureza) — confirmación adicional, independiente de la verificación unitaria previa, de que el pesado por `nsons` es correcto.

Ver `prueba_denssumapaso/prueba_denssumapaso.md` para el detalle completo (verificación unitaria contra `denssumapaso` real, hallazgo del redondeo en los histogramas angulares, y esta medición final).

## Ficheros

- `nsys_overhead_250w.nsys-rep`, `run_stdout.log`: primera medición con `nsys` (el 39,7% "en bruto", sin desglosar).
- `mtiempos.f90` (en `hibrido_instrumentado/`): contadores nuevos para `opcion=7` (`t_sync7`, `t_pack7`, `t_h2d7`, `t_kernel7`, `t_d2h7`, `t_unpack7`, `t_repart7`, `t_dmcsumapaso`, `t_denssumapaso`, `t_difussumapaso`) y `tiempos_escribe7`.
- `tiempos_opcion7_250w.dat`, `tiempos_opcion7_2500w.dat`: desglose fino ANTES del arreglo de `sincroniza_globales_gpu`.
- `msync_gpu.cuf` (en `hibrido_instrumentado/`): `sincroniza_constantes_gpu`/`sincroniza_etrial_gpu` nuevas, `sincroniza_globales_gpu` sin tocar.
- `tiempos_opcion7_250w_fix.dat`, `nsys_250w_fix.nsys-rep`: medición DESPUÉS del arreglo — confirma el ahorro real (~24 ms, no ~450 ms).
