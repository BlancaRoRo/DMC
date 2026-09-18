# test-bloques: escalado con los pasos por bloque

Continuación de `test-pasos/` (que varía el número de **bloques** de cálculo, con pasos-por-bloque fijo en 20) y `test-walker/` (que varía el número de walkers). Aquí la variable que cambia es la **granularidad del bloque**: cuántos pasos DMC entran en cada bloque de estadística, mantenido el número de bloques fijo — es la dimensión complementaria a `test-pasos`, que aísla el efecto de bloques más largos/cortos en vez del volumen total de trabajo.

## Condiciones de cada escenario

| Escenario | Motor | Ejecución | Física | RNG |
|---|---|---|---|---|
| `op4` | **CPU**, `gfortran -O2` (código original, `v1-cuda-desarrollo/ccuerpo/`, compilado en `../cpu-original-gfortran/`) | **Secuencial**: un walker detrás de otro, en un único hilo, bucle `do iwalker=1,nwpaso` | Original, sin portar (`hpsi`/`mwavef.f90`) | Generador propio, **una única `irn` global compartida** entre todos los walkers, consumida en el orden del bucle |
| `op7` | **GPU** (RTX 4060 Laptop), pipeline de 7 fases + CUDA Graph, `nvfortran -cuda -Kieee -Mnofma` | **Paralelo**: todos los walkers a la vez, un hilo CUDA por walker, orquestado desde host | Portada a CUDA (`dmc2.cuf`/`derananum`/`vpot`), matemáticamente equivalente a la original | **Una `irn` independiente por walker** (`k_split_seeds`), decorrelada al clonar (ver `test-pasos.md`, hallazgo del bug de semillas) |

`op4` está verificado bit a bit idéntico a una versión anterior compilada con `nvfortran` (ver `test-pasos.md`) — el cambio de compilador no afecta a la física, solo al tiempo.

## Qué se varía y qué se mantiene fijo

| Parámetro | Valor |
|---|---|
| **Pasos por bloque** (variable) | 5 / 10 / 20 / 40 / 80 |
| Bloques de cálculo | 59 (fijo) |
| Bloques de equilibrio | 1 (fijo) |
| Número de walkers | 1.000 (fijo) |
| Pasos de cálculo totales | 295 / 590 / 1.180 / 2.360 / 4.720 (varía como consecuencia directa, no es la variable controlada) |
| Semilla | `0000000000000011` (fija) |
| `conf.20.00.HH` | copia fresca antes de **cada** corrida individual (10 en total) |

**Nota sobre el nombre**: el número de *bloques* (59) es lo que se mantiene fijo aquí — lo que varía es cuánto trabajo entra en cada uno. Es la dimensión que faltaba frente a `test-pasos` (bloques variables, pasos/bloque=20 fijo) y `test-walker` (walkers variable, todo lo demás fijo).

## Verificación de limpieza

`energia final de las configuraciones` — idéntica en las 10 corridas (`-615.5737694990`). `se usa esta semilla` y ningún NaN/error en ninguna de las 10. El punto `pasos_por_bloque=20` coincide, como comprobación cruzada, exactamente con el punto `1.000 walkers` de `test-walker/` y el punto `1.200 pasos` de `test-pasos/` — son literalmente la misma configuración (bloq_eq=1, bloq_calc=59, pasos=20, nwalkers=1000) ejecutada de forma independiente en las 3 baterías, y da la misma energía en las 3 (`op4`: -678,11 ± 1,91 meV) — confirma reproducibilidad entre baterías.

## Tabla comparativa: tiempo y energía

| Pasos/bloque | Pasos totales | `op4` tiempo | `op7` tiempo | Aceleración | `op4` E_total (meV) | `op7` E_total (meV) | Diferencia |
|---|---|---|---|---|---|---|---|
| 5 | 295 | 20,36 s | 16,16 s | 1,26x | -687,26 ± 2,44 | -688,26 ± 2,53 | 1,00 (< 1σ) |
| 10 | 590 | 41,09 s | 27,51 s | 1,49x | -688,33 ± 1,84 | -689,43 ± 1,81 | 1,10 (< 1σ) |
| 20 | 1.180 | 79,49 s | 54,06 s | 1,47x | -678,11 ± 1,91 | -679,34 ± 2,02 | 1,23 (< 1σ) |
| 40 | 2.360 | 157,04 s | 106,37 s | 1,48x | -663,14 ± 2,46 | -663,76 ± 2,57 | 0,62 (< 1σ) |
| 80 | 4.720 | 304,98 s | 209,01 s | 1,46x | -650,08 ± 2,46 | -648,74 ± 2,68 | 1,34 (< 1σ) |

Energías dentro de 1σ combinada en las 5 — sin excepción. Población final: 1.000/1.000 en las 10 corridas (sin colapsos).

## Tabla final: cómo evoluciona la aceleración con los pasos por bloque

| Pasos/bloque | Aceleración (`op4`/`op7`) |
|---|---|
| 5 | 1,26x |
| 10 | 1,49x |
| 20 | 1,47x |
| 40 | 1,48x |
| 80 | 1,46x |

## Conclusiones

1. **La aceleración es prácticamente constante (~1,46x-1,49x) a partir de 10 pasos por bloque** — la granularidad del bloque (más allá de un mínimo) no cambia significativamente el rendimiento relativo GPU/CPU, a diferencia de lo que ocurre al variar walkers (`test-walker.md`) o el volumen total de trabajo (`test-pasos.md`).
2. **Con bloques muy cortos (5 pasos) la aceleración baja algo (1,26x)** — con menos pasos entre operaciones de estadística por bloque (`dmcsumablo`, `dmcescrblopar`, E/S), el coste fijo de esas operaciones (idéntico en CPU y GPU, no paralelizado) pesa relativamente más frente al trabajo por paso, reduciendo la ventaja relativa de la GPU. Es un efecto pequeño pero medible.
3. **La física es correcta en todo el rango**: energías dentro de 1σ, sin colapsos, en las 5 configuraciones.
4. **Comparado con `test-pasos`** (que varía el número de bloques con pasos/bloque fijo): la aceleración ahí sí crecía claramente con la escala (1,55x→1,56x... realmente con un rango más amplio en la versión intermedia); aquí, variando solo la granularidad del bloque a volumen de trabajo creciente pero número de bloques fijo, la aceleración se estabiliza rápido — confirma que el factor dominante de la aceleración es el **volumen total de trabajo por corrida** (pasos × walkers), no cómo se reparte en bloques.

## Ficheros

- `lanzar_test_bloques.sh`: script original (op4 nvfortran + op7 GPU) — su mitad de `op4` quedó obsoleta.
- `lanzar_test_bloques_op7.sh`: script usado en la práctica para la mitad GPU (ejecutado en paralelo con el rehecho de `op4`, directorios distintos, sin conflicto).
- `op7_{5,10,20,40,80}pasosbloque.log`: salidas GPU, válidas tal cual.
- `op4_{5,10,20,40,80}pasosbloque.log`: salidas CPU, generadas con `gfortran` por `../cpu-original-gfortran/rehacer_op4_gfortran.sh`.
- `wall_times_op7.log`: tiempos de las 5 corridas GPU.
- `../cpu-original-gfortran/rehacer_op4_gfortran_wall.log`: tiempos de las 5 corridas CPU (`gfortran`) de esta batería (y de las otras dos).
