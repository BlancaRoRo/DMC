# test-walker: escalado con el número de walkers

Continuación de `test-pasos/` (que varía el número total de pasos DMC). Aquí la única variable que cambia es el **número de walkers** — todo lo demás (bloques de equilibrio, bloques de cálculo, pasos por bloque) se mantiene fijo, para aislar el efecto de este único parámetro sobre el tiempo y la energía.

## Condiciones de cada escenario

| Escenario | Motor | Ejecución | Física | RNG |
|---|---|---|---|---|
| `op4` | **CPU**, `gfortran -O2` (código original, `v1-cuda-desarrollo/ccuerpo/`, compilado en `../cpu-original-gfortran/`) | **Secuencial**: un walker detrás de otro, en un único hilo, bucle `do iwalker=1,nwpaso` | Original, sin portar (`hpsi`/`mwavef.f90`) | Generador propio, **una única `irn` global compartida** entre todos los walkers, consumida en el orden del bucle |
| `op7` | **GPU** (RTX 4060 Laptop), pipeline de 7 fases + CUDA Graph, `nvfortran -cuda -Kieee -Mnofma` | **Paralelo**: todos los walkers a la vez, un hilo CUDA por walker, orquestado desde host | Portada a CUDA (`dmc2.cuf`/`derananum`/`vpot`), matemáticamente equivalente a la original | **Una `irn` independiente por walker** (`k_split_seeds`), decorrelada al clonar (ver `test-pasos.md`, hallazgo del bug de semillas) |

`op4` está verificado bit a bit idéntico a una versión anterior compilada con `nvfortran` (ver `test-pasos.md`) — el cambio de compilador no afecta a la física, solo al tiempo.

## Qué se varía y qué se mantiene fijo

| Parámetro | Valor |
|---|---|
| **Número de walkers** (variable) | 250 / 500 / 1.000 / 2.000 / 3.000 |
| Bloques de equilibrio | 1 (fijo) |
| Bloques de cálculo | 59 (fijo) |
| Pasos por bloque | 20 (fijo) |
| Pasos de cálculo totales | 1.180 (fijo, igual en las 5 corridas) |
| Semilla | `0000000000000011` (fija) |
| `conf.20.00.HH` | copia fresca antes de **cada** corrida individual (10 en total) |

Con bloques/pasos fijos, el único trabajo que cambia entre corridas es el número de walkers procesados por paso — la dimensión que interesa aislar aquí.

## Límite encontrado: fallaba a partir de ~3.500 walkers — causa identificada y corregida

Antes de lanzar la batería completa se hizo una comprobación rápida (2 bloques de cálculo) subiendo el número de walkers: 1.500, 2.000, 2.500 y 3.000 funcionaban sin problema; **3.500 y 4.000 fallaban** con:

```
FATAL ERROR: FORTRAN AUTO ALLOCATION FAILED
0: cudaMemcpy2D (...) FAILED: 719(unspecified launch failure)
```

**Investigado a fondo después** (rastreo con `compute-sanitizer`, ver `v1-cuda-desarrollo/docs-kernels/derananum.md` Parte 9 para el análisis completo): la causa era el heap de `malloc` de `device` (8 MB por defecto, compartido por toda la GPU) agotándose — `derananum` declara localmente 8 arrays dimensionados en tiempo de ejecución (`d1wfhe4(nhe4)`, `d1wfx(natom)`, etc.), lo que obliga a reservarlos dinámicamente de ese heap compartido; con miles de hilos (walkers) pidiendo a la vez, se agota. No era un límite de memoria total de la GPU (que tiene 7,8 GB libres) sino del tamaño de ese heap concreto.

**Corregido**: se subió el límite a 512 MB (`cudaDeviceSetLimit(cudaLimitMallocHeapSize, ...)` en `inicializa_pipeline`, `dmc2_pipeline.cuf`) — verificado que 4.000 walkers, que antes fallaba siempre, ahora corre limpio. Los datos de esta batería (250-3.000 walkers) siguen siendo válidos tal cual (no se han vuelto a lanzar con el límite nuevo, ya que estaban por debajo del umbral de fallo). Queda pendiente, si se quiere, repetir el barrido con walkers por encima de 3.500 ahora que el pipeline lo soporta.

## Verificación de limpieza

`energia final de las configuraciones` (depende solo de la configuración inicial leída de `conf.20.00.HH`, no de la física del paso DMC) — idéntica en las 10 corridas hasta 15 cifras significativas (`-615.5737694990`, con una variación de 1 unidad en la última cifra a partir de 2.000 walkers, ruido de redondeo de punto flotante sin relevancia física). `se usa esta semilla` y ningún NaN/error en ninguna de las 10.

## Tabla comparativa: tiempo y energía

| Walkers | `op4` tiempo | `op7` tiempo | Aceleración | `op4` E_total (meV) | `op7` E_total (meV) | Diferencia |
|---|---|---|---|---|---|---|
| 250 | 20,00 s | 26,91 s | **0,74x** | -677,28 ± 3,41 | -677,66 ± 2,62 | 0,37 (< 1σ) |
| 500 | 40,06 s | 39,04 s | 1,03x | -678,56 ± 1,89 | -683,48 ± 1,94 | 4,92 (~1,8σ) |
| 1.000 | 79,63 s | 56,87 s | 1,40x | -678,11 ± 1,91 | -679,34 ± 2,02 | 1,23 (< 1σ) |
| 2.000 | 159,91 s | 89,83 s | 1,78x | -677,15 ± 1,94 | -676,30 ± 2,00 | 0,85 (< 1σ) |
| 3.000 | 237,44 s | 135,63 s | 1,75x | -676,27 ± 1,86 | -678,06 ± 1,81 | 1,79 (< 1σ) |

Energías consistentes entre `op4` y `op7` en las 5 (la de 500 walkers, ~1,8σ, es la más alejada pero sigue dentro de lo esperable por fluctuación estadística normal — 1 de 5 puntos por encima de 1σ no es sorprendente). Población final coincide exactamente con el número de walkers de entrada en los 10 casos (sin colapsos).

## Tabla final: cómo evoluciona la aceleración con el número de walkers

| Walkers | Aceleración (`op4`/`op7`) |
|---|---|
| 250 | 0,74x (**GPU más lenta que CPU**) |
| 500 | 1,03x (empate) |
| 1.000 | 1,40x |
| 2.000 | 1,78x |
| 3.000 | 1,75x |

## Conclusiones

1. **La GPU necesita un tamaño mínimo de problema para compensar su coste fijo.** Con solo 250 walkers, `op7` es más lento que la CPU secuencial (0,74x) — el coste de orquestar el grafo de CUDA (lanzamiento, sincronización) no se compensa con tan poco trabajo paralelo. El cruce de rentabilidad está entre 500 y 1.000 walkers para esta configuración.
2. **La aceleración crece con el número de walkers**, de 0,74x a ~1,75-1,78x, y empieza a aplanarse entre 2.000 y 3.000 — señal de que a esa escala la GPU ya está razonablemente ocupada y el margen de mejora adicional se reduce.
3. **La física es correcta en todo el rango probado** (250-3.000 walkers): energías dentro del margen de error estadístico, sin ningún colapso ni NaN.
4. **Límite práctico actual: ~3.000 walkers** con esta configuración de pipeline — por encima falla (ver arriba). No es una limitación de memoria, así que probablemente tiene arreglo, pero queda fuera del alcance de esta prueba.

## Ficheros

- `lanzar_test_walker.sh`: script original (op4 nvfortran + op7 GPU) — su mitad de `op4` quedó obsoleta, ver más abajo.
- `op7_{250,500,1000,2000,3000}walkers.log`: salidas GPU, válidas tal cual.
- `op4_{250,500,1000,2000,3000}walkers.log`: salidas CPU, **regeneradas con `gfortran`** por `../cpu-original-gfortran/rehacer_op4_gfortran.sh` (la primera versión, con `nvfortran`, quedó sobrescrita).
- `wall_times.log`: tiempos de la corrida original (op4 nvfortran + op7) — los tiempos de `op7` siguen siendo válidos, los de `op4` no (ver `../cpu-original-gfortran/rehacer_op4_gfortran_wall.log` para los tiempos correctos de `op4`/`gfortran`).
