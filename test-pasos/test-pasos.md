# Comparación final: `hibrido/` (original) vs `hibrido_instrumentado/` (optimizado, opcion=5 y opcion=7)

Prueba de cierre de toda la investigación de rendimiento (`tiempo-ncu-resultado.md` Partes 1-13, `arquitectura-streams-kin-pot.md` Partes 1-14): comprobar que el trabajo acumulado de la sesión sigue dando **exactamente los mismos resultados físicos** que el código original, sin optimizar, y cuantificar la mejora real de tiempo — a una escala más grande que cualquier prueba anterior (1000 walkers, no 50).

## Condiciones de cada escenario

| Escenario | Motor | Ejecución | Física | RNG |
|---|---|---|---|---|
| `op4` | **CPU**, `gfortran -O2` (código original, `v1-cuda-desarrollo/ccuerpo/`, compilado aparte en `cpu-original-gfortran/`) | **Secuencial**: un walker detrás de otro, en un único hilo, bucle `do iwalker=1,nwpaso` | Original, sin portar (`hpsi`/`mwavef.f90`) | Generador propio, **una única `irn` global compartida** entre todos los walkers, consumida en el orden del bucle |
| `op7` | **GPU** (RTX 4060 Laptop), pipeline de 7 fases + CUDA Graph, `nvfortran -cuda -Kieee -Mnofma` | **Paralelo**: todos los walkers a la vez, un hilo CUDA por walker, orquestado desde host | Portada a CUDA (`dmc2.cuf`/`derananum`/`vpot`), matemáticamente equivalente a la original (validado en `dmc2.md` y en este documento) | **Una `irn` independiente por walker** (`k_split_seeds`), decorrelada al clonar (ver el hallazgo del bug de semillas, más abajo) |

La comparación es siempre "CPU secuencial, física original" contra "GPU paralela, física portada" — nunca se compara GPU contra GPU ni CPU contra CPU, salvo donde se indica explícitamente (p.ej. la comparación con `hibrido_op5`/`instrumentado_op5`, ambos GPU, para aislar el efecto de las optimizaciones).

**Corrección importante**: `op4` se compiló inicialmente con `nvfortran` (reutilizando el mismo binario `qmccluster_tiempos` que las vías GPU) por simple conveniencia de compilación conjunta — no era lo que se quería. Se corrigió compilando el código original con **`gfortran`** de verdad, en un binario aparte (`cpu-original-gfortran/qmccluster`), verificado **bit a bit idéntico** a la versión nvfortran a escala pequeña (mismo `diff` vacío en la tabla de bloques y en la energía total) — así que el cambio de compilador no altera ningún resultado ya validado, solo hace que la comparación de *tiempo* sea la correcta (`gfortran` resultó ser más rápido que `nvfortran` para este código, ver la progresión de abajo). La sección "Progresión de escalas" ya usa `gfortran`; las secciones anteriores de este documento (comparación de 4 vías, prueba a 220 pasos) son anteriores a esta corrección y siguen usando el `op4` compilado con `nvfortran` — se dejan como están, sin rehacer, y quedan marcadas aquí para que quede claro.

## Configuración común a las 3/4 vías

- **Configuración inicial idéntica**: `conf.20.00.HH` (la misma copia fresca de `v1-cuda-desarrollo/ccuerpo/conf.20.00.HH` usada en toda la sesión), copiada de nuevo antes de cada corrida (`finconfiguraciones` la reescribe).
- **Misma semilla aleatoria**: `0000000000000011` (fija en la plantilla `in.mcv`, sin tocar).
- **Mismos parámetros físicos**: `natom=20` He4, molécula H2 como impureza, `opot=4` (potencial He-H2+), sin cambios respecto al resto de la sesión.

## Las vías comparadas

| Vía | Directorio | Binario | Opción | Qué representa |
|---|---|---|---|---|
| `hibrido_op5` | `v2-cuda-integracion/hibrido/` | `qmccluster_hibrido` | 5 | Código original, **sin ninguna** de las optimizaciones de esta sesión (ni Parte 2 `EQUIVALENCE`, ni Parte 3 transpuesta, ni Parte 7 fases, ni nada) |
| `instrumentado_op5` | `hibrido_instrumentado/` | `qmccluster_tiempos` | 5 | Con todas las optimizaciones de `tiempo-ncu-resultado.md` (Partes 1-13) aplicadas — mismo kernel único `k_dmc2` |
| `instrumentado_op7` | `hibrido_instrumentado/` | `qmccluster_pipeline` | 7 | Pipeline de 7 fases + CUDA Graph (`arquitectura-streams-kin-pot.md` Parte 14) |
| `instrumentado_op4_cpu` | `hibrido_instrumentado/` | `qmccluster_tiempos` | 4 | Código CPU secuencial **original, nunca portado** — referencia de fondo. **RNG distinto** al de las otras 3 vías (usa el generador aleatorio original, no el reparto de semillas GPU) — solo comparable en estadística (energía media ± error), no bit a bit. |

`hibrido/compilar.sh` y `test-pasos/run_comparacion.py` son nuevos (ver `Ficheros`).

## Primera corrida: escala reducida (por qué)

El plan original era `1000 walkers, 1 bloque equilibrio, 50 bloques cálculo, 100 pasos/bloque` (5.000 pasos totales). Se lanzó así, y **`hibrido_op5` llevaba 10 min 16 s de CPU sin terminar ni el primer bloque de 100 pasos** — extrapolado, ~8,7 horas solo para esa vía (coherente con el ~149x de mejora que dio el fix de `EQUIVALENCE` de la Parte 2 por sí solo). Impracticable para esta sesión.

**Se relanzaron las 3 con una escala reducida** (mismo `nwalkers=1000`, pero `1 bloque equilibrio + 3 bloques cálculo × 10 pasos` = 40 pasos totales) — suficiente para confirmar corrección y medir la mejora real, sin horas de espera.

## Resultado: bit a bit idéntico en las 3

`diff` entre los 3 logs (`resultados/hibrido_op5.log`, `instrumentado_op5.log`, `instrumentado_op7.log`): **solo difieren la etiqueta de opción, las marcas de tiempo, una línea nueva de `opcion=7` y el tiempo de CPU** — toda la física es idéntica:

- Energía total: `-640.0868202039 meV` (las 3)
- Evolución de población por bloque: `990.20 → 993.90 → 999.93` (las 3)
- Energía final de las configuraciones: `-615.5737694990` (las 3)
- Walker inicial elegido: `277`, semilla del proceso: `98330646220102` (las 3)

## Tiempos

| Vía | Tiempo de CPU | Mejora sobre `hibrido_op5` |
|---|---|---|
| `hibrido_op5` (original) | 419,58 s | — |
| `instrumentado_op5` (Partes 1-13) | 1,77 s | **~237x** |
| `instrumentado_op7` (pipeline, Parte 14) | 1,55 s | **~271x** (1,14x sobre `op5`) |

La mejora relativa `op7` vs `op5` (1,14x) es menor que la medida en la Parte 14 (3,1x) porque esta prueba es mucho más pequeña (40 pasos, no ~5.000) — con menos pasos, el peso relativo de la eliminación de `cudaMalloc` (Parte 14, Efecto 1) es menor sobre el total. Pendiente confirmar si a mayor escala (más pasos) esa proporción crece, como cabría esperar.

## Cuarta vía: `opcion=4`, código CPU original sin portar

Ejecutada a la misma escala reducida (1000w/1eq/3calc×10pasos). Tiempo de CPU: **8,19 s** — mucho más rápido de lo temido (no es GPU, pero tampoco hay 1153 `cudaMalloc` de por medio).

| Vía | Tiempo CPU | Energía total (meV) |
|---|---|---|
| `hibrido_op5` | 419,58 s | -640,09 ± 7,79 |
| `instrumentado_op4_cpu` | 8,19 s | -642,62 ± 8,48 |
| `instrumentado_op5` | 1,77 s | -640,09 ± 7,79 (bit-exacto con `hibrido_op5`) |
| `instrumentado_op7` | 1,55 s | -640,09 ± 7,79 (bit-exacto con `hibrido_op5`) |

**Consistencia estadística confirmada**: `opcion=4` (RNG distinto) da -642,62 ± 8,48 meV frente a -640,09 ± 7,79 meV de las otras tres — diferencia de 2,54 meV, bien dentro de las barras de error combinadas (~11,5 meV). La energía final de las configuraciones iniciales (`-615.5737694990`) sí es idéntica en las 4, como se esperaba (ese valor se fija antes de que el camino de cada vía diverja).

**Hallazgo llamativo**: el código GPU **sin optimizar** (`hibrido_op5`, 419,58 s) fue **~51x más lento que el CPU secuencial puro sin ningún paralelismo** (`instrumentado_op4_cpu`, 8,19 s). Antes de las optimizaciones de esta sesión, portar a GPU no solo no ayudaba — empeoraba considerablemente frente a no tocar nada. Las optimizaciones (Partes 1-14) son las que convierten esa GPU, de ser 51x más lenta que la CPU, en ser ~5,3x más rápida que ella (`instrumentado_op7`: 1,55 s vs `op4`: 8,19 s).

## A partir de aquí: solo `instrumentado_op4_cpu` vs `instrumentado_op7`

Decisión explícita del usuario: `hibrido_op5` (original sin fixes) e `instrumentado_op5` quedan fuera de las pruebas siguientes — ya está establecido que `op5` y `op7` son bit a bit idénticos entre sí (Partes anteriores de este documento), así que la comparación relevante de aquí en adelante es la única con **físicas independientes de verdad** (RNG distinto): `instrumentado_op4_cpu` (original, nunca portado) contra `instrumentado_op7` (pipeline).

**Aclaración importante**: `instrumentado_op4_cpu` está compilado con **`nvfortran`** (mismo `compilar.sh`, mismas flags `-Kieee -Mnofma`), no con `gfortran` — no hay ningún binario `gfortran` en este montaje. El criterio "GPU=CPU-nvfortran=gfortran" usado en `v1-cuda-desarrollo/` durante el porteo kernel a kernel era una comparación de otra fase del proyecto, no algo presente aquí.

### Prueba a más escala (220 pasos: 1 bloque equilibrio + 10 bloques cálculo × 20 pasos)

| Vía | Tiempo de CPU | Energía total (meV) |
|---|---|---|
| `instrumentado_op4_cpu_v2` | 25,96 s | -683,20 ± 6,17 |
| `instrumentado_op7_v2` | 12,10 s | -681,66 ± 6,06 |

**Divergencia entre bloques**: comparando la energía acumulada `<E_calculo>` bloque a bloque entre las dos vías, la diferencia máxima es de ~2,6 meV, sin ninguna tendencia sistemática (a veces una vía más alta, a veces la otra) — coherente con dos paseos aleatorios independientes que no divergen de forma anómala. La población también evoluciona casi igual en las dos (993→1098 en `op4`, 995→1094 en `op7`).

**Menor ventaja de tiempo que antes (~2,15x, no ~5,3x)**: la población creció sustancialmente durante la corrida (de ~995 a ~1098 walkers) — más trabajo por paso en los últimos bloques, que pesa más en el camino CPU secuencial (`op4`) que en el paralelo de GPU (`op7`).

## Progresión de escalas: 300 → 5.000 pasos totales (repetida con `op7` ya corregido)

### Primer intento: contaminado, descartado

La primera repetición de esta progresión (tras el arreglo de semillas) reutilizó la misma copia de `conf.20.00.HH` para las 5 escalas de `op7`, en vez de una copia fresca antes de cada corrida — el programa reescribe ese fichero al terminar, así que cada escala arrancaba desde la configuración final que había dejado la anterior, no desde el mismo punto de partida que `op4`. Se detectó porque `"energia final de las configuraciones"` (que depende solo de la configuración inicial) salía distinta en cada log de `op7` (-615,57 / -746,19 / -567,51 / -714,17 / -579,11) mientras que en `op4` era siempre la misma (-615,57 en las 5). Esa contaminación por sí sola explica la divergencia de 11-15σ que se había atribuido, incorrectamente, a "equilibración insuficiente" — **esa hipótesis era errónea**, tal y como confirma la repetición limpia de abajo.

### Repetición limpia: `conf.20.00.HH` fresco antes de CADA corrida individual

Script `relanzar_progresion_limpia.sh`: 10 corridas (5 escalas × `op4`/`op7`), copiando `conf.20.00.HH` recién antes de cada una — nunca reutilizado, ni siquiera entre dos corridas de la misma escala. `nwalkers=1000`, `pasos=20`/bloque, `bloques de equilibrio=1`, misma plantilla `in.mcv.orig` (semilla `0000000000000011`) en las 10.

**Verificación de que las 10 arrancan de la MISMA configuración de walkers** (no solo se asume, se comprueba en cada log):

| Comprobación | Valor en las 10 corridas |
|---|---|
| `energia final de las configuraciones` | `-615.5737694990` — idéntica en las 10 |
| `se usa esta semilla` (reparto de configuraciones iniciales) | `98330646220102` — idéntica en las 10 |
| `configuraciones iniciales totales` | `1000` — idéntica en las 10 |
| NaN o error en algún log | ninguno, en las 10 |

### Tabla comparativa: tiempo (`op4` recompilado con `gfortran`)

Repetida una segunda vez porque `op4` estaba usando `nvfortran` por error (ver "Corrección importante" al inicio del documento) — mismo binario CPU original, esta vez compilado de verdad con `gfortran -O2`, verificado bit a bit idéntico antes de relanzar:

| Pasos totales | `op4` (CPU, `gfortran`) | `op7` (GPU) | Aceleración |
|---|---|---|---|
| 300 | 25,05 s | 16,20 s | 1,55x |
| 600 | 39,62 s | 29,74 s | 1,33x |
| 1.200 | 79,99 s | 55,10 s | 1,45x |
| 2.500 | 175,22 s | 113,45 s | 1,54x |
| 5.000 | 334,65 s | 214,73 s | 1,56x |

**`gfortran` resultó más rápido que `nvfortran` para este código** (334,65 s vs 490,73 s a 5.000 pasos) — `nvfortran` con `-Kieee -Mnofma` renuncia a optimizaciones para garantizar reproducibilidad bit a bit con la GPU, mientras que `gfortran -O2` no tiene esa restricción. Consecuencia directa: la aceleración real de la GPU frente a la CPU con su compilador correcto es **~1,3x-1,6x**, más modesta que el ~2,0x-2,3x que se había medido (incorrectamente) contra `nvfortran`.

### Tabla comparativa: energía

| Pasos totales | `op4` E_total (meV) | `op7` E_total (meV) | Diferencia | Población final `op4` / `op7` |
|---|---|---|---|---|
| 300 | -687,75 ± 4,81 | -688,83 ± 5,02 | 1,08 (< 1σ) | 1111 / 1112 |
| 600 | -688,78 ± 2,49 | -689,69 ± 2,46 | 0,92 (< 1σ) | 1118 / 1119 |
| 1.200 | -678,11 ± 1,91 | -679,34 ± 2,02 | 1,23 (< 1σ) | 1096 / 1098 |
| 2.500 | -662,09 ± 1,71 | -662,70 ± 1,78 | 0,61 (< 1σ) | 1061 / 1065 |
| 5.000 | -649,09 ± 1,20 | -648,25 ± 1,29 | 0,84 (< 1σ) | 1035 / 1034 |

**Con la contaminación corregida, `op4` y `op7` coinciden dentro de 1 desviación estándar combinada en las 5 escalas**, sin excepción — y la población final (walkers vivos, columna independiente de la energía) también coincide de cerca en las 5. La divergencia de 11-15σ que se vio en el primer intento era enteramente un artefacto del bug de configuración contaminada de esta sesión de pruebas, no una limitación real de equilibración ni una diferencia de física entre `op4` y `op7`. La energía no cambia al pasar `op4` de `nvfortran` a `gfortran` (misma física, mismo binario en esencia, solo compilador distinto).

**Velocidad**: ~1,3x-1,6x en todo el rango con `op4`/`gfortran` (frente al ~2,0x-2,3x medido antes contra `op4`/`nvfortran`, ver más arriba) — la GPU sigue siendo más rápida en las 5 escalas, aunque con un margen más modesto que el reportado inicialmente por el error de compilador.

**Conclusión final de esta progresión**: con el arreglo de semillas, el compilador correcto en la CPU (`gfortran`) y una metodología de prueba limpia, `op7` (GPU) reproduce la física de `op4` (CPU, código original) dentro del margen de error estadístico en las 5 escalas, sin ningún colapso ni resultado inválido, con una aceleración real de ~1,3x-1,6x.

## Hallazgo: colapso de población real, no un bug de física

`op7` dio **NaN** en la energía a partir de las 2.500/5.000 pasos. Investigado a fondo:

1. El NaN aparece **exactamente en el mismo bloque (97, `nwpaso=1936`)** en las corridas de 2.500 y 5.000 pasos — determinista, no aleatorio.
2. **`op5`** (kernel original, muy validado) **también falla en el mismo punto exacto**, con un síntoma distinto: `0: ALLOCATE: 0 bytes requested; not enough memory: 0`. Comparado bit a bit con `op7` hasta ahí: **idéntico**, confirmando que el pipeline no tiene ningún error de física.
3. **`op4`** (código original, generador de números aleatorios propio) **no sufre el colapso** en la misma región — población estable (~1074-1078).
4. **Prueba directa** (pedida explícitamente): `opcion=6` (`dmc-cpu-secuencial-con-semillas-gpu` — CPU secuencial, pero con el *mismo* mecanismo de reparto de semillas de GPU que `op5`/`op7`) se ejecutó a la misma escala. Resultado: **bit a bit idéntico a `op5` y `op7`**, incluido el mismo NaN en el mismo bloque 97 con los mismos valores exactos (`diff` vacío, tres formas de comparación distintas, cero diferencias).

**Conclusión, confirmada con datos, no solo inferida**: es un **colapso de población real** (`nwfin=0` — todos los walkers mueren en el mismo paso DMC), un fenómeno conocido y posible en DMC cuando el factor de ramificación produce, por pura casualidad estadística, ceros para toda la población a la vez. Es **100% determinista y depende únicamente de la secuencia de números aleatorios** del mecanismo de reparto de semillas de GPU (`k_split_seeds`) con la semilla maestra `11` — completamente independiente de si el código corre en GPU o CPU (`op5`, `op6` y `op7` lo sufren igual; solo `op4`, con un generador distinto, lo esquiva). No es un bug de la física portada ni del pipeline.

## La diferencia real: cómo reacciona cada implementación

- **`op5`** (arrays locales, dimensionados por `nwpaso` en cada llamada): con `nwpaso=0`, el siguiente `pasodmc_gpu` intenta reservar un array de tamaño 0 → **crashea alto y claro**.
- **`op7`** (arrays de tamaño fijo `2*nwalkers`, Opción B): con `nwpaso=0`, no hay ningún array que falle al reservar → **seguía corriendo en silencio, propagando NaN**. Esto sí era un fallo real de robustez (no de física) — peor que el crash de `op5`, no mejor.

### Fix aplicado

`msteps.f90`, `pasodmc_gpu_pipeline`: comprobación explícita de `nwfin.eq.0` justo antes del cálculo de `egrow` (que es donde `log(nwnew/nwold)` con `nwnew=0` da `-Infinity` y arranca la cascada de NaN) — para con un mensaje claro (`ERROR pasodmc_gpu_pipeline: colapso de poblacion...`) en vez de continuar en silencio.

**Verificado**:
- Caso normal (1000w/1/3/10, sin colapso): bit a bit idéntico al resultado ya validado — el fix no cambia nada fuera del caso límite.
- Caso de colapso (1000w/1/98/20): para limpio con el mensaje, en vez de seguir con NaN.

## Soluciones posibles para el colapso en sí (no solo detectarlo)

Discutidas, no implementadas — son cambios de **algoritmo/física de DMC**, fuera del alcance de esta sesión (portado y rendimiento en CUDA), coherente con el criterio de no tocar física sin que se pida explícitamente:

1. **Reintentar con otra semilla** — el más simple; si es un suceso raro ligado a esta secuencia concreta, cambiarla debería esquivarlo la mayoría de las veces.
2. **Acelerar la corrección de `etrial`** — hoy se actualiza cada `ncetrial` pasos con una mezcla lenta (`etrial=0.5*(etrial+segrow/ncetrial)`); una corrección más rápida/agresiva reduciría el riesgo de que la población se desvíe demasiado antes de corregirse.
3. **Poner un suelo a la población** (la solución estándar en DMC real): forzar que sobreviva al menos 1 walker cuando el cálculo de `nsons` daría población vacía.
4. **Reducir `dtau`** — pasos más pequeños, factor de ramificación menos extremo, a cambio de más pasos para el mismo tiempo físico.

## Cierre definitivo: las 4 combinaciones posibles, probadas

Quedaba una pregunta abierta: todas las pruebas del colapso (`op5`, `op6`, `op7`) usaban la física **portada** (`dmc2`, la de `dmc2.cuf`/`derananum`/`vpot`) — nunca la física **original** (la `dmc2` de `msteps.f90:609`, que usa `hpsi(w1)`/`mwavef.f90`, nunca tocada por el porteo a CUDA). Faltaba la única combinación sin probar: **física original + semillas de GPU**.

### El obstáculo: la física original no tiene por dónde meter una semilla externa

`gauss3()` (original, `mrandom.f90`) no recibe ningún argumento de semilla — usa una variable de módulo `irn` privada y global, compartida implícitamente por todos los walkers. `gauss3_gpu()` (la que usan `op5`/`op6`/`op7`) sí recibe la semilla explícita del walker. Son el **mismo generador subyacente** (`rand1`/`rand1_gpu` son, comprobado, idéntico algoritmo) — la diferencia real es "una semilla global compartida" vs "una semilla independiente por walker", no el generador en sí.

### La prueba: duplicar la carpeta, sin tocar la referencia

Siguiendo la propuesta del usuario, se duplicó `hibrido_instrumentado/` → `Original-Semilla/`, y **solo ahí** se añadió una subrutina nueva `dmc2_original_semilla` (copia exacta de la `dmc2` original, con la única diferencia de recibir `irn` explícito y llamar a `gauss3_gpu`/`rand1_gpu` en vez de `gauss3`/`rn1()`), más `pasodmc_original_semilla`/`dmc_original_semilla`/`opcion=8` para orquestarla. La `dmc2` original (usada por `opcion=4`) **no se tocó, ni siquiera en la copia**.

### Resultado: bit a bit idéntico, colapso incluido

`opcion=8` (física original + semillas de GPU), misma escala y semilla que las pruebas anteriores (1000w/1eq/98calc/20pasos, semilla `11`):

- **Coincide bit a bit con `op7` desde el primer bloque** (confirma, de paso, que la física original y la portada son matemáticamente equivalentes — la misma validación de siempre, "GPU=CPU-nvfortran=gfortran", ahora extendida a este caso).
- **Colapsa en el mismo bloque 97 exacto**, con los mismos valores exactos (`-613.70337191 -654.09363905 NaN 1009.76`) que `op5`, `op6` y `op7`.
- `diff` completo contra `op6` (física portada + semillas de GPU + CPU secuencial): **vacío, cero diferencias**.

### Las 4 combinaciones, tabla final

| Física | Semillas | ¿Colapsa en el paso 1.936? |
|---|---|---|
| Original | Generador original (`op4`) | No |
| Original | GPU (`op8`, nuevo) | **Sí — idéntico a op5/6/7** |
| Portada | GPU, CPU secuencial (`op6`) | Sí |
| Portada | GPU, paralelo (`op5`/`op7`) | Sí |

**Conclusión, ya sin ninguna pregunta abierta**: el colapso depende única y exclusivamente de la secuencia de números que produce `k_split_seeds` a partir de la semilla maestra `11` — es completamente indiferente qué física se use (original o portada) o dónde se ejecute (CPU secuencial o GPU paralela). No es un bug de ninguna de las dos físicas, ni del porteo, ni de la GPU — es una propiedad estadística de esa secuencia aleatoria concreta.

## Prueba forense final: recalcular en CPU pura los datos exactos que vio la GPU

Todas las pruebas anteriores (op6, op8) demuestran equivalencia reconstruyendo la trayectoria completa desde el paso 1 con otro mecanismo (bucle secuencial en host). Quedaba una última duda posible: ¿podría alguna diferencia sutil, no capturada por el resumen por bloque, haberse acumulado en 96 bloques hasta parecer casualmente el mismo colapso? Esta prueba lo cierra sin ese resquicio: coge los números **literales** que estaban en la memoria de la GPU justo antes del paso que colapsa (op7, ejecución paralela real con `k_dmc2`/CUDA Graph) y los recalcula en CPU pura, sin reconstruir nada.

### Instrumentación añadida

**`hibrido_instrumentado/msteps.f90`, `pasodmc_gpu_pipeline`** (opcion=7): justo antes de `call lanza_pipeline(nwpaso)` (la llamada que lanza el grafo de GPU), se guarda una copia en buffers `save, allocatable` (`dump_atom`, `dump_sprop`, `dump_hb2m`, `dump_b`, `dump_wf*`, `dump_kin/eimp/erot/pot/ene`, `dump_dwf`, `dump_dphi`, `dump_irn`) de exactamente los mismos arrays SoA que se acaban de empaquetar como entrada real del grafo — se sobrescribe en cada paso, así que solo sobrevive el último antes de un posible colapso. Justo donde ya existía la comprobación `if (nwfin.eq.0)` (el fix de la sección anterior), si el volcado no se ha hecho aún se escribe ese buffer a `snapshot_colapso.dat` (fichero binario sin formatear), junto con `natom`, `ncmtras`, `dtau` y **`etrial`** (este último es el que cambia paso a paso — imprescindible capturarlo con su valor real en ese instante, no el inicial).

**`hibrido_instrumentado/driver_replay.f90`** (programa nuevo, independiente de `qmccluster`): hace la misma inicialización de siempre (leer `in.mcv`/`conf.20.00.HH`, igual que cualquier opción) solo para tener `natom`/`rotamol`/etc. disponibles, y luego:
1. Lee `snapshot_colapso.dat`.
2. Fuerza `ncmtras`, `dtau` y `etrial` de `dmc2.cuf` a los valores exactos del volcado (sobre todo `etrial`, que evoluciona con la simulación).
3. Para cada uno de los 1936 walkers, llama a `dmc2_hd` — la **misma** subrutina `attributes(host,device)` de `dmc2.cuf` que ejecuta cada hilo de `k_dmc2` en el device, aquí invocada directamente en el host, un walker detrás de otro, sin lanzar ningún kernel.
4. Cuenta cuántos `nsons>0` (walkers vivos) y lo compara con lo que dio la GPU.

**`compilar_replay.sh`** (nuevo): mismo listado de ficheros que `compilar_pipeline.sh`, sustituyendo `qmccluster.f90` por `driver_replay.f90` como programa principal — no toca `qmccluster_pipeline` ni ningún otro binario.

### Objetivo

Confirmar, con los datos crudos reales de la ejecución paralela en GPU (no una reconstrucción aparte), que el mismo estado de entrada produce `nwfin=0` también cuando se recalcula en CPU pura, un walker cada vez, sin ningún kernel ni paralelismo.

### Resultado

```
=== driver_replay: snapshot leido ===
nwpaso  =         1936
natom   =           21
ncmtras (dump) =           21   (actual) =           21
dtau    (dump) =   1.0000000000000000E-004
etrial  (dump) =   -978.3735902799718   (inicial actual) =   -631.8000000000000
=== driver_replay: resultado ===
walkers de entrada           =         1936
walkers vivos (CPU pura)     =            0
CONFIRMADO: con los mismos datos exactos, la CPU pura (sin GPU, sin kernel,
un walker detras de otro) tambien da nwfin=0 -- el mismo colapso.
```

`etrial` en el volcado (`-978.37`) es muy distinto del valor inicial (`-631.8`), confirmando que efectivamente se capturó el estado real tras 96 bloques de evolución, no un valor por defecto. Con esos datos exactos, la CPU pura reproduce `nwfin=0` para los 1936 walkers — el mismo colapso.

**Conclusión**: no queda ningún resquicio de duda. No es una reconstrucción aparte que "casualmente" llega al mismo sitio — son los números que la GPU tenía en su memoria en ese instante, recalculados con la misma subrutina en un solo hilo de CPU. El colapso es una propiedad de esos datos (posiciones, función de onda, semillas), no del hardware ni del paralelismo que los procesa.

## CORRECCIÓN de la conclusión anterior: el colapso SÍ es un bug, y tiene arreglo

Todo lo anterior (op5/op6/op7/op8 colapsando idénticos, y la prueba forense de recálculo en CPU pura) demostraba que el colapso no dependía de la física ni de si se ejecuta en GPU o CPU. La conclusión de que era "un fenómeno estadístico real de DMC, no un bug" **era incorrecta** — faltaba una pregunta: ¿por qué unos números aleatorios *concretos* hacían que 1936 walkers, en teoría independientes, murieran exactamente a la vez? Esa probabilidad, si de verdad fueran independientes, es astronómicamente pequeña (miles de monedas independientes no salen todas cruz a la vez). Investigarla llevó a la causa real.

### Diagnóstico: por qué mueren, walker a walker

`dmc2` tiene tres caminos que acaban en `nsons=0`: (1)/(2) la configuración se descarta por `wftest=(wf/wfold)²<ratio` tras el 1er/2º `hpsi`, o (3) se llega al sorteo de ramificación y da `gb+rn<1` (muerte "normal"), o el caso especial `nsons>10` capado a 0. Se creó **`driver_diagnostico.f90`** (nuevo, reutiliza `snapshot_colapso.dat`), una copia diagnóstica de `dmc2` (`dmc2_diag`, sin tocar `dmc2.cuf`) que además de `nsons` devuelve por cuál camino murió cada walker. Resultado sobre los 1936 walkers del colapso:

```
return tras 1er wftest<ratio = 0
return tras 2o  wftest<ratio = 0
nsons>10 -> capado a 0        = 0
nsons=0 "normal" (gb+rn<1)    = 1936   <- los 1936, por el camino normal
```

Ningún valor extremo ni overflow en `hpsi`/`wftest`. Pero al imprimir los datos de entrada de varios walkers para ver la distribución de energías, salió esto:

```
walker=1  irn=181525762263593  atom1_x=1.1756988003  ene=-617.3030649940
walker=2  irn=181525762263593  atom1_x=1.1756988003  ene=-617.3030649940
...
walker=10 irn=181525762263593  atom1_x=1.1756988003  ene=-617.3030649940
irn distintos = 1 de 1936
```

**Los 1936 "walkers" no son 1936 muestras independientes: son 1936 copias exactas de una única trayectoria** (misma semilla, misma posición, misma energía, bit a bit). No fallaron 1936 monedas independientes — se lanzó una sola moneda y el resultado se multiplicó por 1936.

### La causa exacta

En `pasodmc_gpu_pipeline` (y también `pasodmc_gpu`/`pasodmc_cpu_gpurand`/`pasodmc_original_semilla`), cuando un walker se reproduce (`nsons>1`), cada copia nueva heredaba la semilla **literal** del padre:

```fortran
do isons=2,nsons(iwalker)
  wsim(nwpaso+nwrep)=wsim(iwalker)
  irn_walkers(nwpaso+nwrep)=irn_walkers(iwalker)   ! copia exacta, no independiente
enddo
```

Como `irn` determina todos los sorteos futuros (difusión, rotación, ramificación), dos clones con el mismo `irn` se mueven **idénticos para siempre** — nunca se separan. Con ~1940 pasos y reproducción constante, las familias de clones se fusionan hasta que la población entera desciende, en la práctica, de una sola trayectoria — y cuando esa trayectoria compartida saca `nsons=0`, se lleva a todas sus copias a la vez.

**Por qué el original (`op4`) no lo sufre**: no tiene "semilla por walker" que copiar — usa una única `irn` global consumida secuencialmente según el orden del bucle, así que cada walker (clon o no) recibe sorteos distintos según su posición. El bug es específico de la arquitectura de semillas-por-walker que se introdujo para paralelizar (`k_split_seeds`), y afecta por igual a `op5`, `op6`, `op7` y `op8` — coincidían bit a bit precisamente *porque* comparten este mismo fallo, no porque el porteo fuera perfecto en este punto.

### El arreglo

`msteps.f90`, `pasodmc_gpu_pipeline`: cada copia nueva (no el walker que sigue vivo, solo sus clones extra) se decorrela con `rand1p_gpu` — el mismo generador que ya usa `k_split_seeds` para separar semillas — aplicado tantas veces como el índice del hermano (`isons-1`), para que también se decorrelen entre sí, no solo respecto al padre:

```fortran
do isons=2,nsons(iwalker)
  wsim(nwpaso+nwrep)=wsim(iwalker)
  irn_walkers(nwpaso+nwrep)=irn_walkers(iwalker)
  do idecorrela=1,isons-1
    call rand1p_gpu(rn_decorrela, irn_walkers(nwpaso+nwrep))
  enddo
enddo
```

### Verificación

- **Caso normal** (1000w/1eq/3calc/10pasos): corre sin errores, energías de bloque en el rango físico esperado (-626 a -654, población ~990-1001) — el arreglo no rompe nada. (Ya no es bit a bit idéntico a `op5`/versión sin arreglo, como es de esperar: cambia deliberadamente qué semilla recibe cada clon.)
- **Prueba definitiva**: misma configuración y semilla exactas que colapsaban siempre (1000w/1eq/98calc/20pasos, semilla `11`) — **con el arreglo, termina limpio, sin NaN, sin parar**:

```
95   95   1   -637.66753258   -664.96207615   -664.98666189   1069.47
96   96   1   -639.08358432   -664.69250853   -664.77345590   1068.88
97   97   1   -636.95096732   -664.40651326   -664.49097200   1068.34
98   98   1   -640.02730801   -664.15774586   -664.13269312   1067.69
numero de walkers que tengo finales   1000
```

El bloque 97, que antes colapsaba siempre en esta semilla, ahora es un bloque normal más.

### Conclusión final (corregida)

El colapso no era una rareza estadística inevitable de DMC — era un bug real y corregible: **la falta de decorrelación de semillas al clonar walkers**, específico de la arquitectura paralela de semillas por walker. Con el arreglo aplicado (`pasodmc_gpu_pipeline`), la misma configuración que colapsaba de forma determinista deja de colapsar.

**Alcance de este arreglo**: se aplicó solo a `pasodmc_gpu_pipeline` (`opcion=7`, la vía de producción de esta sesión). El mismo patrón de copia sin decorrelar existe también en `pasodmc_gpu` (`opcion=5`), `pasodmc_cpu_gpurand` (`opcion=6`) y `pasodmc_original_semilla` (`opcion=8`) — deliberadamente sin tocar, para mantenerlos como referencia histórica del comportamiento con el bug. Si se quiere el mismo arreglo ahí, es el mismo cambio, en el mismo punto de la lógica de repartición.

## Riesgo residual tras el arreglo: aparcado, no pendiente

Pregunta explícita del usuario tras el arreglo: ¿sigue existiendo algo de fondo que pueda devolver NaN? Respuesta, para que quede fijada:

- La fórmula `egrow=etrial-log(nwnew/nwold)/dtau` sigue sin protección matemática: **si** `nwnew` llegara a ser exactamente 0, seguiría dando `-Infinito`/NaN. El arreglo de semillas no toca esa fórmula, solo restaura la independencia real entre walkers.
- Pero con walkers genuinamente independientes (ya sin el bug de clonación), la probabilidad de que los ~1936 mueran a la vez por pura casualidad es `(1-gb)^1936 ≈ 0.03^1936` — un número con más de mil ceros tras la coma, la misma probabilidad (despreciable) que ya asume implícitamente el código original (`op4`), que tampoco tiene protección ahí y nunca la ha necesitado.
- Además, ya existe una red de seguridad desde antes de encontrar esta causa: la comprobación `if (nwfin.eq.0) stop` en `pasodmc_gpu_pipeline` (ver más arriba) para limpio con un mensaje claro en vez de propagar NaN en silencio, cubriendo incluso ese caso residual si alguna vez ocurriera.
- La única forma de eliminar el caso **matemáticamente**, no solo hacerlo despreciable, es un **suelo de población** (forzar ≥1 walker superviviente) — la solución nº3 de la lista de más arriba. **Decisión explícita del usuario: se deja aparcada**, no se implementa en esta sesión — el riesgo real ya es, a efectos prácticos, cero.

## Siguiente paso

Sin pendientes explícitos en este momento — la progresión de escalas quedó validada (tiempo y energía) con metodología limpia. Posibles líneas futuras, no solicitadas todavía: repetir con otra semilla maestra para tener una segunda muestra independiente, o extender la progresión más allá de 5.000 pasos.

## Ficheros

- `run_comparacion.py`: script de la prueba (genera `in.mcv` en cada directorio, copia `conf.20.00.HH` fresco, ejecuta cada binario).
- `v2-cuda-integracion/hibrido/compilar.sh`: script de compilación nuevo para `hibrido/` (no existía) — genera `qmccluster_hibrido`.
- `resultados/hibrido_op5.log`, `resultados/instrumentado_op5.log`, `resultados/instrumentado_op7.log`, `resultados/instrumentado_op4_cpu.log`: las 4 salidas completas de la primera corrida (40 pasos).
- `resultados/instrumentado_op4_cpu_v2.log`, `resultados/instrumentado_op7_v2.log`: la corrida a más escala (220 pasos).
- `resultados/op4_{300,600,1200,2500,5000}pasos.log`, `resultados/op7_{300,600,1200,2500,5000}pasos.log`: la progresión de 5 escalas.
- `resultados/op5_repro_check.log`, `resultados/op7_repro_bug.log`, `resultados/op6_mismas_semillas.log`: las 3 corridas de investigación del colapso (1000w/1eq/98calc/20pasos), bit a bit idénticas entre sí hasta el NaN del bloque 97.
- `resultados/op7_repro_bug_fixed.log`: corrida tras el fix, parando limpio en vez de propagar NaN.
- `hibrido_instrumentado/msteps.f90`: fix de detección de `nwfin=0` en `pasodmc_gpu_pipeline`.
- `test-tiempos/Original-Semilla/`: copia de `hibrido_instrumentado/` para la prueba de la cuarta combinación — `dmc2_original_semilla`/`pasodmc_original_semilla`/`dmc_original_semilla`/`opcion=8` añadidos ahí, la `dmc2` original (`opcion=4`) sin tocar ni en la copia.
- `test-tiempos/compilar_original_semilla.sh`: script de compilación de `qmccluster_original_semilla` (no toca ningún otro binario).
- `resultados/op8_sanity.log`, `resultados/op8_fisica_original_semillas_gpu.log`: verificación de sanidad y la prueba final (física original + semillas de GPU), bit a bit idéntica a `op6` incluido el colapso del bloque 97.
- `hibrido_instrumentado/msteps.f90`: instrumentación forense en `pasodmc_gpu_pipeline` (buffers `dump_*` + volcado a `snapshot_colapso.dat` cuando `nwfin=0`).
- `hibrido_instrumentado/driver_replay.f90`, `compilar_replay.sh`: programa standalone que recalcula en CPU pura (sin GPU, sin kernel) los datos exactos rescatados del colapso, llamando directamente a `dmc2_hd`.
- `resultados/driver_replay_cpu_pura.log`: resultado de la prueba forense — `nwfin=0` recalculado en CPU pura con los datos literales de la GPU, mismo colapso.
- `hibrido_instrumentado/driver_diagnostico.f90`, `compilar_diagnostico.sh`: desglosa por qué muere cada walker (`dmc2_diag`) y comprueba diversidad real de semillas — reveló `irn distintos=1 de 1936`, la causa raíz.
- `resultados/driver_diagnostico2.log`: salida completa del diagnóstico (desglose de motivos + comprobación de diversidad de semillas).
- `hibrido_instrumentado/msteps.f90`: arreglo aplicado en `pasodmc_gpu_pipeline` — decorrelación de la semilla de cada clon nuevo con `rand1p_gpu`.
- `resultados/op7_con_fix_semillas.log`: prueba definitiva del arreglo — misma configuración/semilla que colapsaba siempre (1000w/1eq/98calc/20pasos, semilla 11), ahora termina limpio sin NaN.
- `resultados/op7_fix_{300,600,1200,2500,5000}pasos.log`: primer intento de la progresión repetida con `op7` corregido — **contaminado** (`conf.20.00.HH` no se copiaba fresco entre escalas), descartado como comparación de energía, conservado como referencia de lo que NO hay que hacer.
- `relanzar_progresion_limpia.sh`: script de la repetición limpia (10 corridas, `conf.20.00.HH` fresco antes de cada una).
- `resultados/op4_limpio_{300,600,1200,2500,5000}pasos.log`, `resultados/op7_limpio_{300,600,1200,2500,5000}pasos.log`: las 10 salidas completas de la progresión limpia — base de las tablas de tiempo y energía final.
- `resultados/relanzar_progresion_limpia_wall.log`: tiempos de pared de las 10 corridas (**op4 aquí seguía siendo `nvfortran`**, ver corrección de abajo).
- `../cpu-original-gfortran/`: binario CPU original recompilado con **`gfortran`** de verdad (`compilar_gfortran.sh`), verificado bit a bit idéntico a la versión `nvfortran`. `rehacer_op4_gfortran.sh` relanza `op4` con este binario en las 3 baterías (`test-pasos`, `test-walker`, `test-bloques`); `resultados/op4_limpio_{300,600,1200,2500,5000}pasos.log` quedan **sobrescritos** con esta versión correcta (los tiempos de la tabla de arriba ya son los de `gfortran`).
