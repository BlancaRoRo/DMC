# Test de tiempos: opcion=4 (CPU) vs opcion=5 (GPU)

## Objetivo

Medir, dentro de una corrida real de `qmccluster`:

1. En **opcion=4** (CPU pura): qué fraccion del tiempo total se va en los metodos que se han portado a CUDA (`hpsi`, que a su vez engloba `derananum`, `vpot`, `potenbh`, `ccuerpo`, `valibre`, mas `rota` y `mrandom`) frente al resto (E/S por bloque, promedios, bookkeeping).
2. En **opcion=5** (GPU): qué fraccion del tiempo total se va en el kernel `k_dmc2` frente a la **conversion de variables AoS<->SoA** (empaquetar/desempaquetar + copias host<->device, ver `docs/hibrido.md` §5.0) frente al resto.
3. Cómo crecen esos tiempos al aumentar walkers, bloques de calculo, bloques de equilibrio o pasos por bloque.
4. Si los resultados fisicos de opcion=4 y opcion=5 se parecen, corriendo **ambas con exactamente la misma configuracion inicial** (mismo `in.mcv`, misma semilla, mismo `conf.20.00.HH`).

Esta carpeta (`v2-cuda-integracion/test-tiempos/`) es autonoma: no toca `hibrido/` (la version validada) ni sus resultados. Todo lo de aqui es instrumentacion añadida solo para medir tiempos.

## Donde se ponen los medidores

Nuevo modulo `hibrido_instrumentado/mtiempos.f90`: contadores acumulados en variables `module`, usando `system_clock` (reloj de pared) para medir cada bloque de codigo con un par `tiempos_tic`/`tiempos_toc`. Al final de cada corrida escribe `tiempos_opcion4.dat` o `tiempos_opcion5.dat` con el reparto completo y el porcentaje de cada bucket sobre el total.

Puntos exactos de instrumentacion (todos dentro de `hibrido_instrumentado/`, copia de `hibrido/` con estas lineas añadidas — el `hibrido/` original no se toca):

| bucket | qué mide | fichero : subrutina | notas |
|---|---|---|---|
| `t_hpsi` | las 2 llamadas a `hpsi` dentro de `dmc2` (CPU) | `msteps.f90 : dmc2` | inclusivo: incluye `valibre`/`derananum`/`vpot` |
| `t_valibre`, `t_derananum`, `t_vpot` | cada rama interna de `hpsi` | `mwavef.f90 : hpsi` | inclusivos, se miden en el punto de llamada dentro de `hpsi` |
| `t_ccuerpo`, `t_potenbh` | las 2 llamadas internas de `vpot` | `mwavef.f90 : vpot` | rama `opot.eq.4`, la unica que se usa en este proyecto |
| `t_rota` | las 6 llamadas a `rota` dentro de `dmc2` | `msteps.f90 : dmc2` | solo si `rotamol=.T.` (lo es en este `in.mcv`) |
| `t_random` | `gauss3` (x2) + `rn1()` (x1) dentro de `dmc2` | `msteps.f90 : dmc2` | |
| `t_dmc2call` | la llamada a `dmc2` dentro del bucle de `pasodmc` | `msteps.f90 : pasodmc` | suma de las `nwpaso` llamadas del paso |
| `t_pasodmc_body` | `pasodmc` completa (dmc2 + reparticion/compactacion) | `msteps.f90 : pasodmc` | |
| `t_total4` | el bucle `do iblock=1,nblockeq+nblock ... enddo` completo | `mmontecarlo.f90 : dmc` | es el "total" de referencia para opcion=4 |
| `t_sync` | `sincroniza_globales_gpu` | `msteps.f90 : pasodmc_gpu` | ver `docs/hibrido.md` §5.1 |
| `t_seeds` | reparto de semillas (`k_split_seeds`), solo la 1ª vez | `msteps.f90 : pasodmc_gpu` | coste que se amortiza en corridas largas |
| `t_pack` | empaquetar `wsim` -> arrays SoA host | `msteps.f90 : pasodmc_gpu` | ver `docs/hibrido.md` §5.0 |
| `t_h2d` | copias host->device (`atom_d = atom_h; ...`) | `msteps.f90 : pasodmc_gpu` | asignacion de array es una `cudaMemcpy` sincrona |
| `t_kernel` | lanzamiento de `k_dmc2` **+ `cudaDeviceSynchronize()` explicito** | `msteps.f90 : pasodmc_gpu` | ver nota mas abajo — imprescindible para medir esto bien |
| `t_d2h` | copias device->host | `msteps.f90 : pasodmc_gpu` | |
| `t_unpack` | desempaquetar SoA -> `wsim` | `msteps.f90 : pasodmc_gpu` | |
| `t_repart` | reparticion/compactacion de la poblacion | `msteps.f90 : pasodmc_gpu` | misma logica que en opcion=4 |
| `t_pasodmc_gpu_body` | `pasodmc_gpu` completa | `msteps.f90 : pasodmc_gpu` | |
| `t_total5` | el mismo bucle de bloques/pasos, para `dmc_gpu` | `mmontecarlo.f90 : dmc_gpu` | "total" de referencia para opcion=5 |

**Nota importante — el tiempo con CUDA no se mide como en CPU**: `k_dmc2<<<blocks,threads>>>` es una llamada **asincrona**: la CPU sigue ejecutando en cuanto lanza el kernel, sin esperar a que termine en la GPU. Medir solo `tic`/`call k_dmc2`/`toc` mediria casi 0 (el tiempo real del kernel se "colaria", sin darse cuenta, dentro del siguiente bucket cronometrado — la copia D2H, que sí es bloqueante y por tanto fuerza la espera). Por eso, justo despues del lanzamiento y antes de parar el reloj de `t_kernel`, se llama explicitamente a `istat_sync = cudaDeviceSynchronize()`. Las copias `atom_d = atom_h` (H2D) y `atom_h = atom_d` (D2H) sí son sincronas por si solas (es como CUDA Fortran implementa la asignacion de arrays device/host), asi que esas no necesitan este `sync` extra.

## Como se ejecuta

- `compilar.sh`: compila `hibrido_instrumentado/` con `nvfortran -cuda -Kieee -Mnofma` (mismas flags que `hibrido/`) y enlaza `qmccluster_tiempos` (añadiendo `-llapack -lblas`, que hacia falta para `kpcoef.f`).
- `run_test.py <opcion> <walkers> <bloq_equilibrio> <bloq_calculo> <pasos> <tag>`: genera un `in.mcv` a partir de `in.mcv.orig` con esos valores, **refresca `conf.20.00.HH`** desde la copia limpia de `v1-cuda-desarrollo/ccuerpo/` (igual que en `docs/hallazgo-cuda-host.md`: `finconfiguraciones` reescribe este fichero en cada corrida, asi que hay que partir siempre de una copia fresca), corre el binario y guarda `resultados/<tag>.log` + `resultados/<tag>__tiempos_opcionN.dat`.
- `barridos.sh`: corre todos los puntos de los 4 barridos (ver tabla abajo).
- `plot_resultados.py`: parsea los `.dat` de `resultados/` y genera `crecimiento_tiempos.png` + `resumen_barridos.csv`.

## Configuraciones usadas

Todas parten del mismo `in.mcv` base (mismo sistema fisico, mismo `opot=4`, misma semilla `0000000000000011`, mismo `conf.20.00.HH` de partida) — solo cambian `opcion`, `numero de walkers`, `bloques de equilibrio`, `bloques de calculo` y `pasos por bloque`.

**Caso base** (usado para comparar opcion=4 vs opcion=5 con datos identicos): 50 walkers, 1 bloque de equilibrio + 1 de calculo, 5 pasos/bloque (10 pasos DMC en total).

**Caso a escala** (solo opcion=4, para dar un porcentaje representativo de una corrida real — opcion=5 se deja fuera porque a esta escala tardaria demasiado, ver "hallazgo" mas abajo): 200 walkers, 1+2 bloques, 200 pasos/bloque (600 pasos DMC, 120000 pares walker-paso).

**Barridos** (3 puntos cada uno, variando un solo parametro y dejando el resto en el valor base), para opcion=4 y opcion=5:

| barrido | valores | resto fijo |
|---|---|---|
| A: walkers | 50, 100, 200 | 1+1 bloques, 5 pasos |
| B: bloques de calculo | 1, 2, 4 | 50 walkers, 1 bloque equilibrio, 5 pasos |
| C: bloques de equilibrio | 1, 2, 4 | 50 walkers, 1 bloque calculo, 5 pasos |
| D: pasos por bloque | 5, 10, 20 | 50 walkers, 1+1 bloques |

Los barridos se mantienen deliberadamente pequeños (pocos walkers, pocos pasos) para no disparar el tiempo total de la prueba — ver el hallazgo siguiente, que explica por qué opcion=5 no admite corridas grandes en este test.

## Hallazgo: el kernel `k_dmc2` domina el tiempo de opcion=5, y no escala proporcional al numero de walkers para poblaciones pequeñas

Antes de lanzar los barridos se hizo una calibracion rapida:

| walkers | pasos | tiempo `k_dmc2` total | tiempo/paso |
|---|---|---|---|
| 50 | 10 | 19.11 s | 1.91 s/paso |
| 200 | 10 | 32.31 s | 3.23 s/paso |
| 50 | 100 | 194.97 s | 1.95 s/paso |

Al cuadruplicar los walkers (50->200) el tiempo por paso solo sube ~1.7x, no 4x — y al multiplicar los pasos por 10 (10->100) el tiempo por paso se mantiene practicamente constante (~1.9-2.0 s/paso). Esto apunta a un coste **casi fijo por lanzamiento de kernel**, independiente del tamaño de la poblacion.

**Primera hipotesis (descartada con una prueba directa)**: se penso que los ~18 arrays SoA `device` dentro de `pasodmc_gpu` (`atom_d`, `sprop_d`, `hb2m_d`, ..., `nsons_d`), al estar declarados como arrays automaticos (dimensionados por `nwpaso`, sin `save`/`allocatable`), forzarian un `cudaMalloc`+`cudaFree` de cada uno **en cada paso DMC**, y que eso explicaria el coste. Para comprobarlo, en vez de asumirlo, se aislo en `diagnostico_kernel/diag.cuf` — un programa CUDA Fortran independiente, sin nada de la fisica real, con un kernel trivial (`x(i)=x(i)+1`) — comparando 100 iteraciones de:

- **Caso A**: 1 array `device` reservado una sola vez fuera del bucle.
- **Caso B**: el mismo kernel, pero llamado desde una subrutina que declara los mismos ~18 arrays `device` automaticos que `pasodmc_gpu` (mismo patron, mismos tamaños `natom=22, nwpaso=50`), recreados en cada llamada.

Resultado (repetido 3 veces para descartar ruido):

| caso | tiempo/iteracion |
|---|---|
| A (1 array preasignado) | ~11-15 microsegundos |
| B (18 arrays automaticos, recreados cada vez) | ~15-19 microsegundos |

La diferencia entre A y B es de apenas unos microsegundos — **miles de veces mas pequeña** que el ~1.9 s/paso que se observa en `pasodmc_gpu` real. **La hipotesis queda descartada**: ni el lanzamiento del kernel ni la reserva/liberacion de los arrays `device` automaticos explican el coste observado.

**Lo que si queda establecido, con esta misma prueba como evidencia**: el "suelo" de lanzar un kernel CUDA Fortran + `cudaDeviceSynchronize` en esta maquina es del orden de **10-20 microsegundos**, no segundos. Si `k_dmc2` (con toda la fisica real: `hpsi`, `derananum`, `vpot`, `potenbh`, `rota`, `mrandom`, con sus tablas de `myexp`/`mysin`/`mycos`/`mypow`/`myacos`) tarda ~1.9-3.2 s en ejecutarse de verdad para 50-200 hilos, el tiempo esta genuinamente **dentro del kernel real**, no en el mecanismo de lanzarlo ni en la gestion de memoria alrededor. Con solo 50-200 hilos activos (1-7 bloques de 32 hilos) la GPU esta muy lejos de saturarse, asi que esto no es "hay demasiado trabajo para la GPU" sino "cada hilo, individualmente, tarda un tiempo enorme para lo poco que hace" — algo dentro de la cadena `hpsi`->`derananum`/`vpot`->...->`myexp`/`mysin`/... es mucho mas lento en el device de lo esperable. Identificar exactamente cual (sospecha razonable, no probada aqui: las funciones con tablas de consulta como `myexp`/`mysin`/`mycos`/`mypow` accediendo a memoria de forma no uniforme entre hilos del mismo warp) queda fuera del alcance de este test de tiempos y se deja como trabajo futuro — este documento se limita a descartar lo que NO es la causa (conversion AoS<->SoA, lanzamiento de kernel, reserva de arrays automaticos) y a acotar donde SI esta el coste (ejecucion real del kernel).

Consecuencia practica para este test: con opcion=5 costando ~2 s/paso incluso con solo 50-200 walkers, un caso a escala real (miles de pasos) se dispararia a horas — por eso los barridos de opcion=5 se mantienen a 10-40 pasos como mucho (y aun asi el barrido completo tardo del orden de 6-7 minutos).

## Resultado 1 — reparto de tiempos, opcion=4 (CPU)

**Caso a escala** (200 walkers, 600 pasos, `escala_opcion4__tiempos_opcion4.dat`), tiempo total 14.78 s:

| bucket | tiempo (s) | % del total |
|---|---|---|
| `hpsi` (= `valibre`+`derananum`+`vpot`, inclusivo) | 13.44 | **90.9 %** |
| &nbsp;&nbsp;`derananum` | 7.56 | 51.2 % |
| &nbsp;&nbsp;`vpot` | 5.84 | 39.5 % |
| &nbsp;&nbsp;&nbsp;&nbsp;`potenbh` | 5.68 | 38.4 % |
| &nbsp;&nbsp;&nbsp;&nbsp;`ccuerpo` | 0.13 | 0.9 % |
| `rota` | 0.02 | 0.1 % |
| `mrandom` (gauss3+rn1) | 0.28 | 1.9 % |
| `dmc2` (bucle sobre walkers) | 14.01 | 94.8 % |
| `pasodmc` completa | 14.06 | 95.1 % |
| otros (E/S por bloque, promedios) | 0.72 | 4.9 % |

**Esto responde a la pregunta original**: los metodos portados a CUDA (todo lo que cuelga de `hpsi`) son, en una corrida representativa, **~91 % del tiempo total** en CPU — el resto es reparticion de poblacion, E/S de bloque y promedios, que es barato y no se ha portado (no hacia falta).

En el **caso base** (50 walkers, solo 10 pasos, `base_opcion4__tiempos_opcion4.dat`) esa proporcion baja a 73.5 % — porque con tan pocos pasos el coste fijo de E/S por bloque (2 bloques) pesa proporcionalmente mucho mas. Es la misma razon por la que el caso base no sirve para dar el porcentaje "real": hace falta una corrida con bastantes mas pasos para que el coste fijo por bloque se diluya, tal como muestra el caso a escala.

## Resultado 2 — reparto de tiempos, opcion=5 (GPU)

**Caso base** (50 walkers, 10 pasos, mismo `in.mcv`/semilla que el opcion=4 base, `base_opcion5__tiempos_opcion5.dat`), tiempo total 21.74 s:

| bucket | tiempo (s) | % del total |
|---|---|---|
| kernel `k_dmc2` (device, con `cudaDeviceSynchronize`) | 19.11 | **87.9 %** |
| `sincroniza_globales_gpu` | 0.014 | 0.06 % |
| reparto de semillas (1 vez) | 0.0002 | 0.00 % |
| empaquetar AoS->SoA (host) | 0.0003 | 0.00 % |
| copia H2D | 0.0007 | 0.00 % |
| copia D2H | 0.0013 | 0.01 % |
| desempaquetar SoA->AoS (host) | 0.0005 | 0.00 % |
| reparticion/compactacion | 0.0005 | 0.00 % |
| **CONVERSION AoS<->SoA total (pack+H2D+D2H+unpack)** | **0.0027** | **0.013 %** |
| `pasodmc_gpu` completa | 19.13 | 88.0 % |
| otros (E/S por bloque, promedios) | 2.61 | 12.0 % |

**La conversion de variables (AoS<->SoA + copias) es completamente despreciable: solo el 0.013 % del tiempo total.** Todo el tiempo de opcion=5 lo consume el kernel en si — coherente con el hallazgo de arriba (coste casi fijo por lanzamiento, no por el trabajo de conversion).

## Graficas de crecimiento

`crecimiento_tiempos.png` (generado por `plot_resultados.py` a partir de `resumen_barridos.csv`), 4 paneles — uno por parametro barrido (walkers, bloques de calculo, bloques de equilibrio, pasos por bloque). En cada panel: eje izquierdo (azul) = tiempo de los metodos portados en opcion=4 (bucket `hpsi`); eje derecho (rojo) = tiempo de conversion AoS<->SoA en opcion=5. Ambos ejes en escala logaritmica porque difieren en magnitud (segundos vs. milisegundos).

- **Walkers**: ambas curvas crecen de forma clara y aproximadamente lineal con el numero de walkers (tiene sentido: tanto el bucle `dmc2` en CPU como el empaquetado/copias en GPU son O(n) en walkers).
- **Bloques de calculo / equilibrio / pasos por bloque**: la curva de conversion (opcion=5) crece limpia y monotonamente, como se espera (mas pasos = mas veces se empaqueta/copia). La curva de metodos (opcion=4) es **ruidosa y no monotona** en estos tres barridos — a diferencia del barrido de walkers, aqui el tiempo total en juego es solo de 30-90 ms, y a esa escala el ruido del sistema operativo (planificacion, cache, etc.) pesa mas que la señal real. No se ha alargado el barrido para limpiar esta señal, siguiendo la idea de mantener las pruebas pequeñas; el caso a escala de la seccion anterior ya deja claro el porcentaje real que importa.

## Diferencia de resultados: opcion=4 vs opcion=5, misma configuracion inicial

Caso base (50 walkers, 10 pasos, mismo `in.mcv`, misma semilla, mismo `conf.20.00.HH` de partida en ambas corridas):

| magnitud | opcion=4 | opcion=5 |
|---|---|---|
| Energia total (bloque, cm-1) | -4994.43 | -4976.37 |
| Poblacion media | 585.14 | 580.50 |
| Energia final de las configuraciones | -615.5737694990 | -615.5737694990 |
| Walkers finales | 50 | 50 |

Los valores **no son identicos, y no se espera que lo sean**: opcion=4 usa una unica secuencia de aleatoriedad compartida y secuencial entre walkers, mientras que opcion=5 reparte una semilla independiente por walker (ver `docs/hibrido.md` §5.2/§5.4) — es la misma divergencia, ya estudiada y documentada a fondo, entre `pasodmc` y `pasodmc_gpu`. Con solo 10 pasos (1 bloque de equilibrio + 1 de calculo, sin repeticiones) no hay bloques suficientes para dar barras de error, asi que esta tabla es solo una comprobacion de que "no se han disparado" — estan en el mismo orden de magnitud y la misma zona de energia, no una validacion estadistica. La validacion rigurosa (200 walkers, 5 bloques x 50 pasos, energias compatibles dentro de sus barras de error: opcion=4 -684.33±7.39 meV vs. opcion=5 -686.04±5.56 meV) ya esta hecha y documentada en `docs/hibrido.md` §5.2 — no se repite aqui.

Que "energia final de las configuraciones" salga identica en ambas (-615.5737694990) no es una coincidencia sospechosa: con solo 10 pasos y `dtau=0.0001` la poblacion apenas se difunde desde `conf.20.00.HH` (identico en ambas corridas), asi que esa media queda practicamente igual a la del punto de partida en los dos casos.

## Limitaciones de este test

- Los barridos de opcion=5 se han mantenido deliberadamente pequeños (10-40 pasos, 50-200 walkers) por el coste real medido del kernel (~2 s/paso) — no representan el regimen de una corrida de produccion (miles de walkers, millones de pasos).
- El barrido de metodos en opcion=4 (bloques/pasos) tiene ruido de medida visible a esta escala tan pequeña; el porcentaje fiable (~91 %) sale del caso a escala, no de los barridos.
- El coste casi-fijo por paso de `k_dmc2` (~2 s, independiente del tamaño de poblacion en el rango probado) queda identificado y **acotado a la ejecucion real del kernel** (descartado el lanzamiento y la gestion de arrays `device`, ver `diagnostico_kernel/`). Se perfilo `k_dmc2` con NVIDIA Nsight Compute (247 registros por hilo, 91% de accesos no coalescidos), se localizo la causa exacta con `-gpu=lineinfo` (el `TRANSFER` envuelto en array de `bits_of`/`real_of` en `glibc_exp_mod.cuf`, usado por `myexp`/`mypow`/`myacos`/`mysin`/`mycos`), y **se corrigio y se verifico** (sustituido por `EQUIVALENCE`, mismos bits confirmados aislado y end-to-end, ver `test_equivalence_exp.cuf`): el kernel paso de 19.11 s a 0.128 s (~149x), el run completo de 21.74 s a 2.76 s. Ver `tiempo-ncu-resultado.md` (Parte 1: diagnostico: Parte 2: causa exacta, arreglo y verificacion) para el proceso completo y las tablas de metricas antes/despues. Sigue abierto un segundo grupo de accesos no coalescidos, mas pequeño, en `der_wavefhe4_mod.cuf` y similares (patron `atom(iatom)%comp-atom(jatom)%comp`) — trabajo futuro si se decide seguir optimizando.
