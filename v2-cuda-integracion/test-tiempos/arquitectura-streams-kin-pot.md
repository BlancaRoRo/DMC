# Arquitectura propuesta: kernels separados en streams distintos para `kin` y `pot`

Plan de una prueba nueva, todavía sin implementar ni medir. Continúa la investigación de `tiempo-ncu-resultado.md` (Partes 1-13), pero es una idea arquitectónicamente distinta a las 3 estrategias de esa investigación (que repartían trabajo *dentro* de un mismo kernel, con hilos/warps coordinados por memoria compartida) — aquí el reparto es *entre* kernels distintos, coordinados por `streams` de CUDA.

## 1. Motivación: por qué esto es distinto de lo ya probado

En la Parte 13 se cerró la investigación de la Estrategia 3 (equipo de hilos dentro de un kernel) con un techo realista de ~7%, porque la pieza que se repartía (`derwavefhe4`+`derwavefx`, dentro de `derananum`) es solo el **16,21% del tiempo total de `k_dmc2`** (medido con `ncu`, ver Parte 13).

Mirando `hpsi_mod.cuf`:

```fortran
call derananum(atom, sprop, hb2m, b, wf, wfhe4, wfhe3, wfm, wfx, &
                kin, eimp, erot, dwf, dphi)
call vpot(atom, sprop, pot)
ene = kin + pot
```

`derananum` (que calcula `kin`, la energía cinética) y `vpot` (que calcula `pot`, la energía potencial, vía `ccuerpo`→`potenbh`→`He_dihydrogen`) son **independientes entre sí** — ninguna de las dos lee nada que escriba la otra, solo se juntan al final en `ene = kin + pot`. Hoy se ejecutan **una detrás de otra, dentro del mismo hilo**.

En la medición de la Parte 13, la rama `vpot` (`He_dihydrogen` 7,67% + `V_hehe`/`Vp_hehe` 7,71%+4,84%) pesa otro **~20% del tiempo de `k_dmc2`**, sin contar la parte de `mypow`/`myexp` que también usa. Si `derananum` y `vpot` pudieran ejecutarse **a la vez** (no una detrás de otra), el techo de mejora ya no sería el 16% de una sola pieza — sería la unión de las dos, bastante más grande.

## 2. Por qué esto SÍ podría solaparse de verdad (y el equipo de hilos no)

La Parte 10/11 repartía trabajo *dentro de un warp* — y ahí la GPU no ejecuta caminos de código distintos a la vez: todo el warp ejecuta la misma instrucción en cada ciclo (divergencia). Eso es una limitación dura del hardware, no un problema de diseño.

Lanzar **dos kernels distintos en dos streams distintos** es otra cosa: son dos programas separados, cada uno internamente uniforme (sin ninguna rama de "rol"), y el planificador de la GPU sí puede intercalar sus bloques en las SMs libres — no hay divergencia de warp posible entre dos kernels distintos, porque ni siquiera comparten warps. Con la ocupación real que hemos medido en toda la sesión (~2-6%), sobra capacidad en la GPU para que ambos kernels quepan sin pelearse por sitio.

## 3. Arquitectura concreta de la prueba

### 3.1. Kernels

Tres kernels nuevos, todos con el patrón "1 hilo = 1 walker" (sin roles, sin divergencia — a diferencia de las Partes 10-12):

| Kernel | Qué calcula | Lee | Escribe |
|---|---|---|---|
| `k_kin` | Pieza tipo `derananum` (física de juguete: bucle de parejas O(n²), como `derwavefhe4`/`derwavefx` de las pruebas anteriores) | `atom(natom,n)` | `kin(n)` en memoria global |
| `k_pot` | Pieza tipo `vpot`/`He_dihydrogen` (física de juguete distinta, para no depender de `mypow`/`myexp` reales) | `atom(natom,n)` | `pot(n)` en memoria global |
| `k_combina_ene` | `ene(i) = kin(i) + pot(i)` | `kin(n)`, `pot(n)` | `ene(n)` |

Y el kernel de referencia (arquitectura actual) para comparar:

| Kernel | Qué calcula |
|---|---|
| `k_secuencial` | 1 hilo = 1 walker, calcula `kin` y `pot` uno detrás de otro (como hace `hpsi` hoy) y escribe `ene(i)=kin+pot` directamente |

### 3.2. Bloques y warps de cada lanzamiento

Sin roles que agrupar (a diferencia de la Parte 11/12), la configuración es la misma "1 hilo = 1 walker" ya usada en `_solo`/`_solo_real`: **32 hilos/bloque (1 warp/bloque)**, `blocks = ceil(n/32)`. Se mantiene igual en los 4 kernels (`k_kin`, `k_pot`, `k_combina_ene`, `k_secuencial`) para que la comparación sea justa — la variable que se está probando es la concurrencia entre streams, no el tamaño de bloque.

`k_combina_ene` es tan barato (una suma por walker) que podría incluso fusionarse dentro de quien termine último, pero se deja como kernel aparte por claridad — es la pieza más barata de las tres, no debería pesar en la medición.

### 3.3. Streams: el orden de lanzamiento

```fortran
type(cudaStream) :: stream_kin, stream_pot
istat = cudaStreamCreate(stream_kin)
istat = cudaStreamCreate(stream_pot)

call k_kin<<<blocks,threads,0,stream_kin>>>(n, natom, atom_d, kin_d)
call k_pot<<<blocks,threads,0,stream_pot>>>(n, natom, atom_d, pot_d)

istat = cudaStreamSynchronize(stream_kin)
istat = cudaStreamSynchronize(stream_pot)

call k_combina_ene<<<blocks,threads>>>(n, kin_d, pot_d, ene_d)
```

Los dos primeros lanzamientos salen del host **sin esperar** el uno al otro (lanzamiento asíncrono, normal en CUDA) — es el planificador de la GPU quien decide si los solapa. `k_combina_ene` solo puede lanzarse después de que ambos hayan terminado (de ahí los dos `cudaStreamSynchronize`), porque depende de los resultados de los dos.

## 4. Ventajas

- **Cero divergencia de warp posible**: cada kernel es internamente uniforme, no hay ninguna rama de "rol" que dividir.
- **No hace falta memoria compartida ni barrera manual** (`syncthreads()`) — la sincronización la da la propia gestión de streams, más simple de razonar que el patrón de la Parte 11/12.
- **Cubre mucho más tiempo que el equipo de hilos**: si `derananum` (16,21%) y `vpot` (~20%, con su parte de `mypow`/`myexp`) se solapan de verdad, el techo teórico de mejora ya no está limitado a una pieza pequeña — es la suma de ambas, bastante más grande que el 7% calculado en la Parte 13.
- **Encaja con la ocupación real medida en toda la sesión** (2-6%): hay sitio de sobra en la GPU para que quepan dos kernels a la vez sin competir por recursos.

## 5. Inconvenientes / riesgos

- **Los resultados pasan por memoria global, no compartida**: `kin`/`pot` se escriben en global y se leen en `k_combina_ene` — una escritura y una lectura por walker, no el patrón de lectura-modificación-escritura repetido que causó el problema original de la Parte 3, pero hay que medirlo, no darlo por sentado.
- **Coste fijo de cada lanzamiento de kernel**: cada `<<<>>>` tiene un coste fijo (típicamente decenas de microsegundos). Con 3 kernels en vez de 1 (más si en el futuro se aplica también a la segunda llamada de `hpsi` dentro de `dmc2`, que se ejecuta dos veces por paso, Parte 13), ese coste se acumula — puede que no compense en un caso tan pequeño (50 walkers reales) como el de este proyecto.
- **La concurrencia entre streams no está garantizada solo por pedirla**: depende del planificador de la GPU y el driver — hay que comprobarlo con la herramienta correcta (ver §6), no asumir que "usar streams" implica solapamiento real.
- **No ataca el resto de `dmc2`**: los sorteos aleatorios y las rotaciones (Parte 13) siguen siendo secuenciales por naturaleza (el sorteo determina el movimiento antes de poder evaluarlo) — esta idea solo ataca la pareja `derananum`/`vpot` *dentro* de una llamada a `hpsi`, no el resto del paso DMC.

## 6. Qué esperamos ver, y con qué herramienta medirlo

**Importante, distingue esto de todo lo hecho hasta ahora**: `ncu` (Nsight Compute) perfila kernels **uno a uno** — no está pensado para mostrar si dos kernels se solapan en el tiempo. Para comprobar la concurrencia real entre `k_kin` y `k_pot` hace falta **`nsys` (Nsight Systems)**, con su vista de línea de tiempo por stream (`nsys profile --trace=cuda -o <salida> ./programa`, luego inspeccionar en `nsys-ui` o `nsys stats`) — se vería si las barras de `k_kin` y `k_pot` se solapan en el tiempo o van una detrás de otra.

- **Resultado esperado, caso favorable**: `k_kin` y `k_pot` se solapan en la línea de tiempo de `nsys`, y el tiempo total (`k_kin`+`k_pot`+`k_combina_ene` con streams) se acerca a `max(tiempo_kin, tiempo_pot)` en vez de `tiempo_kin + tiempo_pot` — comparado contra `k_secuencial`, una mejora sustancialmente mayor que el 7% de la Parte 13.
- **Resultado esperado, caso desfavorable**: los kernels no se solapan (por el motivo que sea: tamaño de los kernels, comportamiento del driver, límites de recursos no evidentes) y el resultado es prácticamente el mismo que `k_secuencial`, más el coste fijo de 2 lanzamientos extra — en ese caso, `_secuencial` seguiría siendo mejor.
- Verificación de corrección, como siempre en esta sesión: bit a bit, `ene` de `_secuencial` contra `ene` de la versión con streams, antes de mirar ningún tiempo.

## 7. Siguiente paso

Construir la prueba aislada descrita en §3 (carpeta nueva, p.ej. `prueba_streams_kin_pot/`), verificar bit a bit, medir con `nsys` si hay solapamiento real y con eventos de CUDA (`cudaEventRecord`/`cudaEventElapsedTime`) el tiempo total — antes de plantear ningún cambio al código real de `hibrido_instrumentado/`.

---

## 8. Resultado de la prueba aislada: sin solapamiento real, sin mejora

`prueba_streams_kin_pot/test_streams.cuf`: `k_secuencial` (línea base) y `k_kin`+`k_pot`+`k_combina_ene` (streams), física de juguete a tamaño real (`natom=20`, `n=4000` walkers, para que cada kernel dure lo suficiente y `nsys` pueda mostrar con claridad si hay solapamiento). Verificado bit a bit idéntico.

### Primera medida (con `cudaEvent`): engañosa

`cudaEvent` dio `_secuencial`=3,72 ms, streams=2,24 ms (~1,66x) — pero `_secuencial` se lanzaba primero en el programa y absorbía el coste de arranque en frío del contexto CUDA (inicialización/JIT del primer kernel), no una mejora real. **Lección de esta prueba, aparte de la principal**: al medir tiempos de kernel con `cudaEvent`, hay que descartar el primer lanzamiento del programa (o hacer un lanzamiento de "calentamiento" antes de medir) — si no, el primer kernel medido sale artificialmente penalizado.

### Medida correcta (con `nsys`, trazas GPU reales)

`nsys profile --trace=cuda` + `nsys stats --report cuda_gpu_trace` (`resultado_streams.nsys-rep`, y de nuevo `resultado_streams_nb.nsys-rep` tras probar streams no bloqueantes):

| Kernel | Stream | Inicio (ns) | Duración (ns) | Fin (ns) |
|---|---|---|---|---|
| `k_kin` | 13 | 1.141.554.901 | 1.459.367 | 1.143.014.268 |
| `k_pot` | 14 | 1.143.024.028 | 655.541 | 1.143.679.569 |

**`k_pot` empieza 9.760 ns (≈10 µs) después de que `k_kin` termine — cero solapamiento**, ni con `cudaStreamCreate` normal ni tras crear los streams con la bandera `cudaStreamNonBlocking` (se probaron los dos, mismo resultado en ambos casos, gap de ~10 µs consistente).

Duración real total: `k_secuencial` = 2.111.900 ns (2,11 ms); `k_kin`+`k_pot`+`k_combina_ene` = 2.116.988 ns (2,12 ms) — **prácticamente idénticas. Sin mejora real alguna.**

### Se descartó que fuera una limitación de hardware

Consultado directamente vía `cudaGetDeviceProperties` sobre esta GPU (RTX 4060 Laptop):

```
asyncEngineCount   = 2
concurrentKernels  = 1   (SI soportado)
multiProcessorCount = 24
```

La tarjeta sí soporta ejecución concurrente de kernels, y `k_kin` (125 bloques) solo ocupa ~5 de los 24 bloques/SM disponibles — sobra sitio de sobra para que `k_pot` hubiera podido empezar mientras `k_kin` seguía en marcha. El motivo exacto por el que el planificador de la GPU/driver decidió no solaparlos, con hardware capaz y recursos libres, **no se ha podido determinar con las herramientas usadas en esta prueba** — haría falta investigar más a fondo el comportamiento del driver (fuera del alcance razonable de esta prueba puntual).

## 9. Descarte sistemático con checklist de diagnóstico (barrera de stream 0)

Antes de dar la investigación por cerrada, se repasó una checklist de causas conocidas de falta de solapamiento, aplicada punto por punto al código real de la prueba:

1. **¿Streams explícitos en los lanzamientos de `k_kin`/`k_pot`?** Sí, confirmado en el código (`<<<blocks,threads,0,stream_kin>>>` / `...,stream_pot>>>`).
2. **¿Memoria *pinned* en las transferencias?** No aplica — esta prueba no usa `cudaMemcpyAsync` entre `k_kin`/`k_pot`, solo escriben directamente en arrays `device` ya reservados.
3. **¿Llamada síncrona oculta entre los dos lanzamientos?** **Sí, encontrada**: el código usaba `cudaEventRecord(ev0, 0)` — el **stream 0 (por defecto)** — justo antes de lanzar `k_kin`/`k_pot`. El stream por defecto puede imponer una barrera implícita con el resto de streams.
4. **¿Streams creados dentro de un bucle?** No, se crean una sola vez. No aplica.

### La corrección probada

Se reescribió la sección de medición para no tocar el stream 0 en ningún momento entre los dos lanzamientos: eventos grabados en **cada stream por separado** (`cudaEventRecord(ev_kin0, stream_kin)` / `..., stream_pot)`), un lanzamiento de calentamiento previo (para separar el coste de arranque en frío, que había contaminado la primera medida con `cudaEvent` de la §8), y un `cudaDeviceSynchronize()` explícito justo antes de la sección de streams para no arrastrar nada pendiente.

### Resultado: el hueco persiste, prácticamente idéntico

Con `nsys stats --report cuda_gpu_trace` sobre la corrida corregida:

| Kernel | Stream | Inicio (ns) | Fin (ns) |
|---|---|---|---|
| `k_kin` | 13 | 1.141.501.508 | 1.142.961.418 |
| `k_pot` | 14 | 1.142.973.865 | 1.143.629.149 |

**Hueco: 12.447 ns** — el mismo orden que el medido antes de la corrección (~10 µs). Quitar la barrera del stream 0 **no cambió nada**: descarta el Punto 1 de la checklist como causa real en este caso.

### Un detalle que apunta más allá de "latencia de lanzamiento de CPU"

El propio diagrama de diagnóstico distingue "huecos vacíos → latencia de CPU" (Escenario B) de "apilados sin huecos → saturación de recursos" (Escenario A). Pero hay un matiz que el hueco medido no explica por sí solo: el comando de lanzamiento de `k_pot` sale de la CPU en microsegundos, justo después del de `k_kin` (no hay ningún cálculo de CPU entre medias) — mientras `k_kin` corre 1,46 ms en la GPU, el comando de `k_pot` ya lleva ahí un buen rato esperando en la cola de su stream. Si el cuello de botella fuera la CPU tardando en despachar la orden (Escenario B puro), `k_pot` podría haber empezado en cualquier punto *durante* la ejecución de `k_kin`. En cambio, empieza justo cuando `k_kin` termina — eso indica que es la propia GPU/planificador quien decide no solaparlos, con el trabajo ya disponible y esperando, no que la CPU vaya tarde.

## 10. Batería final: aislar recursos, precisión y contenido del kernel, cada uno por separado

Con el hueco de ~10-12 µs ya confirmado y no explicado por el stream 0, se probaron 3 hipótesis más, cada una con su propia prueba aislada y medida con `nsys`:

### Hipótesis A: saturación de ocupación/recursos (grid grande llenando las SMs)

`prueba_streams_kin_pot/test_streams_sweep.cuf`: mismos `k_kin`/`k_pot`, pero con `n` leído de la línea de comandos, para repetir la medida con grids muy distintas — desde 1 solo bloque (`n=32`, una fracción mínima de 1 SM de las 24) hasta 125 bloques (`n=4000`, repartidos por las 24 SMs):

| `n` | Bloques | Hueco medido |
|---|---|---|
| 32 | 1 | 9.824 ns |
| 256 | 8 | 9.856 ns |
| 1.000 | 32 | 9.823 ns |
| 4.000 | 125 | 6.528 ns |

**El hueco es el mismo, prácticamente constante, con 1 bloque que con 125.** Si fuera saturación de recursos, un único bloque (que deja 23 de 24 SMs completamente libres) debería haber permitido que `k_pot` empezara al instante. No lo hizo. **Hipótesis A descartada con datos, en todo el rango de tamaños.**

### Hipótesis B: saturación de las ALUs de FP64 (las GPU GeForce tienen muy poca capacidad de doble precisión)

`prueba_streams_kin_pot/test_streams_minimal.cuf`, segunda parte: mismas fórmulas de `k_kin`/`k_pot`, reescritas en `real(kind=4)` (precisión simple) en vez de `real(kind=8)`:

| Precisión | Hueco medido |
|---|---|
| FP64 (`real*8`, la prueba original) | 6.528-9.856 ns (según `n`) |
| FP32 (`real*4`) | 5.952 ns |

**Mismo orden de magnitud con FP32 que con FP64.** Si el cuello de botella fueran las ALUs de doble precisión (muy escasas en una GeForce), la versión FP32 —que usa unidades mucho más abundantes— debería haber solapado con más facilidad. No lo hizo. **Hipótesis B descartada con datos.**

### Prueba sintética mínima: sin física en absoluto, solo enteros

`prueba_streams_kin_pot/test_streams_minimal.cuf`, primera parte: `k_dummy_i4`, un kernel de 1 solo bloque que solo hace una suma de enteros en un bucle — sin una sola operación en punto flotante, sin `sqrt`, sin `exp`, sin nada que pudiera saturar ninguna unidad de cálculo especializada:

**Hueco medido: 6.496 ns.** Prácticamente igual que con la física real. Esto descarta que el motivo tenga que ver con **el contenido** del kernel en absoluto — ni FP64, ni FP32, ni funciones matemáticas, ni tamaño de grid. El hueco aparece igual entre dos kernels vacíos que entre dos kernels con física real.

## 11. Conclusión final: hueco fijo, independiente de todo lo probado

Resumen de las 8 mediciones independientes de esta investigación (checklist de la §9 + batería de la §10):

| Variable cambiada | Rango probado | Hueco medido |
|---|---|---|
| Barrera de stream 0 | con / sin | ~10-12 µs en ambos casos |
| Streams no bloqueantes | con / sin | ~10 µs en ambos casos |
| Tamaño de grid (`n`) | 32 a 4.000 walkers (1 a 125 bloques) | 6.500-9.900 ns, sin tendencia |
| Precisión | FP64 / FP32 | ~6-10 µs en ambos casos |
| Contenido del kernel | física real / solo enteros | ~6,5 µs en ambos casos |

**El hueco no depende de nada de lo que hemos podido variar** — ni de recursos, ni de precisión, ni de contenido, ni de configuración de streams. Es un valor fijo de bajo nivel (6-12 µs) que aparece entre cualquier par de lanzamientos consecutivos de kernel en este sistema concreto (GPU RTX 4060 Laptop + driver + entorno de ejecución de `nvfortran`/CUDA Fortran de este equipo), no una consecuencia de ninguna decisión de diseño de la prueba.

Con las 3 causas del checklist original (stream 0, recursos, CPU) y las 3 hipótesis adicionales (ocupación, precisión, contenido) descartadas una a una con medidas reales, la explicación que mejor encaja con todos los datos es un **suelo fijo de solapamiento en este entorno concreto** — muy probablemente ligado al driver o a cómo el runtime de CUDA Fortran gestiona el cierre/apertura de contexto entre lanzamientos, no a nada corregible desde el código de la prueba. Confirmarlo del todo requeriría comparar contra un lanzamiento equivalente en CUDA C/C++ puro (fuera del alcance razonable de esta investigación puntual).

A diferencia de la Estrategia 3 (Parte 11-12), donde sí se encontró un mecanismo real y aprovechable (eliminar la divergencia de warp), aquí el mecanismo esperado (concurrencia entre streams) no se manifiesta en la práctica en este entorno, con todas las causas plausibles descartadas mediante pruebas directas, no solo teoría. No se lleva al código real. Queda documentado como resultado negativo, exhaustivamente acotado.

## 12. Descubrimiento posterior: CUDA Graphs SÍ solapa — la conclusión de la §11 queda revisada

La solución C sugerida en el diagnóstico (empaquetar `k_kin`/`k_pot` en un **CUDA Graph**, patrón "horquilla" con `cudaStreamBeginCapture`/`cudaStreamWaitEvent`, en vez de dos lanzamientos sueltos) **sí elimina el hueco fijo** descrito en la §11 — probado con datos reales, no solo con la topología declarada.

### La prueba

`prueba_streams_kin_pot/test_streams_graph.cuf`: mismos `k_kin`/`k_pot` de siempre, capturados en un grafo con una horquilla real (el evento de bifurcación se graba **antes** de lanzar `k_kin`, no después — un primer borrador de este fichero lo grababa después, lo que habría mantenido la dependencia secuencial dentro del propio grafo; corregido antes de medir). Perfilado con `nsys --cuda-graph-trace=node` (necesario para ver los kernels dentro del grafo — sin ese flag no aparecen en la traza):

| Kernel | Inicio (ns) | Duración (ns) | Fin (ns) |
|---|---|---|---|
| `k_kin` | 1.117.295.802 | 2.000.910 | 1.119.296.712 |
| `k_pot` | 1.117.302.746 | 1.324.052 | 1.118.626.798 |

**`k_pot` empieza 6.944 ns después de `k_kin` — prácticamente a la vez — y termina 669.914 ns *antes* de que `k_kin` acabe: su ejecución completa queda contenida dentro de la de `k_kin`.** Solapamiento real, confirmado dos veces en la misma traza (el lanzamiento de calentamiento mostró lo mismo: 96 ns de diferencia de inicio).

Duración total real (`k_kin` inicio → `k_combina_ene` fin): 2.004.365 ns. Si no hubieran solapado: 3.324.962 ns. **Ganancia: 39,7%** — muy cerca del caso ideal `max(t_kin, t_pot)` descrito como "resultado esperado, caso favorable" en el §6 original.

### Por qué el grafo sí lo consigue y el lanzamiento suelto no

No se ha podido determinar la causa exacta a nivel de driver (fuera del alcance de esta prueba, como ya se anotó en la §11) — pero el patrón encaja con la intuición del diagnóstico original: un `cudaGraphLaunch` entrega al hardware la **topología completa de una vez** (una tabla de ejecución ya resuelta), mientras que dos `<<<>>>` sueltos dependen de que el planificador del driver decida, lanzamiento a lanzamiento, si merece la pena solaparlos — y en este entorno, esa decisión en tiempo real resultó ser sistemáticamente "no" (hueco fijo de 6-12 µs, §10-11), independientemente de recursos libres, precisión o contenido.

### La conclusión de la §11 queda revisada, no la investigación entera

La afirmación "no se lleva al código real... arquitectura descartada" (§11) se apoyaba en que el *mecanismo* (streams sueltos) no se manifestaba en la práctica. Con CUDA Graphs sí se manifiesta. **La arquitectura kin/pot solapados deja de estar descartada** — el camino correcto de implementación pasa por CUDA Graphs, no por streams sueltos.

### Recalculando el techo de Amdahl con el mecanismo que sí funciona

La Parte 13 de `tiempo-ncu-resultado.md` calculó un techo de ~7% para la Estrategia 3 (equipo de hilos), porque esa estrategia solo repartía `derananum` (16,21% del tiempo de `k_dmc2`). Aquí el solapamiento cubre **`derananum` (16,21%) + `vpot`/`He_dihydrogen`/`V_hehe`/`Vp_hehe` (20,22%) = 36,43% del tiempo total** — mucho más:

```
fraccion_hoy (secuencial)  = 0,1621 + 0,2022 = 0,3643
fraccion_si_solapan_del_todo = max(0,1621; 0,2022) = 0,2022   (la mas corta se esconde dentro de la mas larga)

speedup_total = 1 / (1 - 0,3643 + 0,2022) ≈ 1,193x  →  ~19,3% mas rapido en k_dmc2 completo
```

**Techo realista: ~19% más rápido en `k_dmc2` completo** — casi 3 veces el techo de la Estrategia 3, y con un mecanismo ya demostrado (no solo teórico) en esta GPU concreta.

### Qué haría falta comprobar antes de tocar el código real

- Repetir la prueba con el tamaño real de walkers de este proyecto (50, no los 4.000 de esta prueba) — un grafo tan pequeño podría comportarse distinto; hay que medirlo, no asumirlo (mismo criterio de siempre).
- `derananum` y `vpot` reales usan `mypow`/`myexp`/`He_dihydrogen` de verdad, no física de juguete — confirmar que el solapamiento se mantiene con el peso real de esas funciones.
- `dmc2` llama a `hpsi` dos veces por paso (Parte 13) — habría que capturar las 2 llamadas en el grafo, o evaluar si merece la pena solo para una.
- La construcción del grafo (`cudaStreamBeginCapture`/`cudaGraphInstantiate`) tiene su propio coste — pero se paga **una vez**, no en cada paso DMC, si el grafo se reutiliza con `cudaGraphLaunch` en cada iteración del bucle de `pasodmc_gpu` (habría que verificar que la topología no cambia paso a paso, lo cual es cierto aquí: mismos kernels, mismos tamaños, solo cambian los datos).

## 13. Confirmación con tamaños y funciones reales (`n=50`, `nhe4=20`/`natom=21`, `mypow`/`myexp` de verdad)

Antes de tocar `dmc2.cuf`, se repitió la prueba cerrando las 2 diferencias que la §12 dejaba con la física de juguete: tamaños **distintos** (`k_kin` con `nhe4=20` átomos, como `derwavefhe4` dentro de `derananum`; `k_pot` con los `natom=21` completos, como `vpot`/`He_dihydrogen`) y **`mypow`/`myexp` reales** (`glibc_pow.cuf`/`glibc_exp_mod.cuf`, copiados tal cual de `hibrido_instrumentado/`, no aproximaciones con `**`/`exp()` intrínsecos). `n=50`, el tamaño real de este proyecto.

`prueba_streams_kin_pot/test_streams_graph_real.cuf`. Verificado bit a bit idéntico (`_secuencial` vs grafo, 50 walkers). Perfilado con `nsys --cuda-graph-trace=node`:

| Kernel | Duración (ns) |
|---|---|
| `k_kin` (`nhe4=20`, `mypow` real) | 661.113 |
| `k_pot` (`natom=21`, `myexp` real) | 932.728 |

`k_pot` empieza 6.527 ns después de `k_kin` — y esta vez es **`k_pot` el más largo** (al revés que en la §12, donde `k_kin` tardaba más) — confirmando que el solapamiento no depende de qué kernel se escriba primero en el código: el más corto siempre queda contenido dentro del más largo, sin ordenar nada a mano.

Duración total real (grafo): 942.359 ns. `_secuencial`: 1.580.466 ns. **Ganancia: 40,4%** — igual o mejor que la física de juguete de la §12, con tamaños distintos y las funciones más caras de todo el árbol (`mypow`/`myexp`, Parte 2 de `tiempo-ncu-resultado.md`) de por medio.

### Conclusión de este paso intermedio

Las 2 diferencias que quedaban con el código real (tamaños distintos, funciones caras reales) **no rompen el solapamiento** — al contrario, con `n=50` y física real el resultado es igual de sólido que con la física de juguete. Con esto, el camino para diseñar el cambio real sobre `dmc2.cuf`/`hpsi_mod.cuf`/`msteps.f90` queda razonablemente despejado — el siguiente paso ya sería el cambio arquitectónico real señalado en la §12 (partir `dmc2` en varios kernels, capturar el grafo, verificar bit a bit contra `dmc2.md`).

## 14. Implementación real: Opción 1 completa en `hibrido_instrumentado`, `opcion=7`

Con el paso intermedio de la §13 confirmado, se implementó la Opción 1 completa (las 7 fases de `dmc2` + el grafo en horquilla para `derananum`/`vpot`) directamente en `hibrido_instrumentado/`, como una vía nueva y paralela — `dmc2.cuf`/`hpsi_mod.cuf`/`msteps.f90`'s `pasodmc_gpu` **originales no se tocan**, siguen siendo `opcion=5`, sirviendo de referencia de corrección (mismo criterio que cuando se añadió `opcion=5` sin tocar `opcion=4`).

### Ficheros nuevos

- **`dmc2_pipeline.cuf`**: las 7 fases (`k_fase_a`, `k_derananum_t`, `k_vpot_t`, `k_fase_c`, `k_fase_d`, `k_fase_f`, `k_fase_g`), los arrays persistentes (`atom_p`, `dwf_p`, `activo_p`, `eold_p`, `wfold_p`, etc., dimensionados a `2*nwalkers` — la "Opción B" acordada), y `inicializa_pipeline`/`lanza_pipeline` (construcción del grafo una vez, relanzamiento con `cudaGraphLaunch` cada paso).
- **`msteps.f90`**: `pasodmc_gpu_pipeline`, nueva, mismo algoritmo que `pasodmc_gpu` (empaquetado/desempaquetado de `wsim`, repartición de población según `nsons`) pero usando los arrays persistentes y lanzando el grafo en vez de `k_dmc2`.
- **`mmontecarlo.f90`**: `dmc_gpu_pipeline`, mismo esqueleto que `dmc_gpu`, llamando a `pasodmc_gpu_pipeline`.
- **`qmccluster.f90`**: `case (7): call dmc_gpu_pipeline`.
- **`compilar_pipeline.sh`**: script de compilación aparte, genera `qmccluster_pipeline` (no toca `qmccluster_tiempos`).

Detalles de implementación reales que no eran evidentes desde el diseño:
- `k_derananum_t`/`k_vpot_t` son versiones **nuevas**, con el layout SoA transpuesto `(nmax,natom)` y "libreta" local — las `k_derananum`/`k_vpot` que ya existían en `derananum_mod.cuf`/`vpot_mod.cuf` usaban el layout AoS antiguo `(natom,n)` (de antes de la Parte 3) y se habrían reintroducido el problema de acceso no coalescido si se hubieran reutilizado tal cual.
- Las fases A y D solo necesitan "libreta" para `sprop` (que `rota` exige contiguo) — los accesos a `atom(i,iatom)` elemento a elemento no la necesitan, al no llamar a ninguna subrutina que exija un array `natom`-contiguo.

### Verificación: bit a bit idéntico, dos veces

`python3 run_test_pipeline.py 7 50 1 1 5 ...` y `... 7 50 1 3 20 ...` (config corta y una más larga, para ejercitar cambios reales de población entre pasos), comparado con `run_test.py 5 ...` con la misma configuración: **`diff` solo mostró la etiqueta de opción, marcas de tiempo y tiempo de CPU** — toda la física (energías, población, todo) idéntica.

### Resultado de rendimiento: 3,1x más rápido, y por qué (dos efectos, no uno)

| | `opcion=5` | `opcion=7` (pipeline) |
|---|---|---|
| Tiempo de CPU (config 50w/3blo/20pasos) | 3,96 s | **1,27 s — ~3,1x** |

Antes de atribuir esto solo al solapamiento `derananum`/`vpot`, se perfiló con `nsys --trace=cuda,osrt` para descomponerlo:

**Efecto 1 — `cudaMalloc` eliminado**: `pasodmc_gpu` (original) declara sus arrays `device` como variables locales automáticas — se reservan y liberan en memoria de la GPU **en cada paso DMC**. Medido: 1.153 llamadas a `cudaMalloc`, **285 ms totales (~19% del tiempo total)**. `pasodmc_gpu_pipeline`, con arrays persistentes (Opción B), reduce esto a 22 llamadas, **1,9 ms** — prácticamente eliminado. Este efecto **no tiene nada que ver con el solapamiento** — es un problema preexistente de `opcion=5` que este diseño corrige como efecto colateral.

**Efecto 2 — el kernel en sí es más rápido**: comparando el tiempo real de ejecución en GPU por paso (`cudaDeviceSynchronize`/`cudaStreamSynchronize`): `opcion=5` ≈ **17,13 ms/paso**, `opcion=7` ≈ **10,90 ms/paso** — **36,3% menos**, ya con la ganancia de la horquilla incluida.

**Confirmación directa del solapamiento, en el pipeline real** (no la prueba aislada): traza de `nsys --cuda-graph-trace=node` de un paso real:

| Kernel | Duración | Registros |
|---|---|---|
| `k_derananum_t` | 6.450.662 ns | 144 |
| `k_vpot_t` | 4.090.171 ns | 247 |

`k_vpot_t` empieza 256 ns después de `k_derananum_t` y termina 2.360.235 ns *antes* — completamente contenido dentro, **38,8% de ganancia en esta horquilla concreta**, coherente con el 40,4% medido en aislado (§13). También se confirma algo que ya se apuntaba: `k_derananum_t` sola pesa 144 registros (menos que los 247 de siempre) — separarla de `vpot` sí alivia su presión de registros, aunque `vpot` siga cargando con el peso completo de `mypow`/`myexp`/`He_dihydrogen`.

### Conclusión

Los dos efectos son reales, independientes, y ambos medidos directamente (no inferidos): la eliminación de `cudaMalloc` explica una fracción significativa del ~19% de tiempo total, y el solapamiento `derananum`/`vpot` explica una reducción del ~36% en el tiempo de kernel por paso — juntos dan el 3,1x observado. La Opción 1 queda **implementada, verificada bit a bit y con la ganancia real confirmada con datos**, no solo estimada con Amdahl.

## Ficheros

- `prueba_streams_kin_pot/test_streams.cuf`: prueba aislada original (con la corrección de la barrera del stream 0 y el lanzamiento de calentamiento).
- `prueba_streams_kin_pot/test_streams_sweep.cuf`: variante con `n` configurable por línea de comandos (Hipótesis A).
- `prueba_streams_kin_pot/test_streams_minimal.cuf`: kernel sintético de enteros puros + variante FP32 de `k_kin`/`k_pot` (prueba sintética mínima + Hipótesis B).
- `resultado_streams.nsys-rep`, `resultado_streams_nb.nsys-rep`, `resultado_streams_fix.nsys-rep`: trazas de la prueba original (streams normales, no bloqueantes, sin barrera de stream 0).
- `resultado_sweep_n32.nsys-rep`, `resultado_sweep_n256.nsys-rep`, `resultado_sweep_n1000.nsys-rep`, `resultado_sweep_n4000.nsys-rep`: trazas del barrido de tamaño de grid.
- `resultado_minimal.nsys-rep`: traza del kernel sintético de enteros + la variante FP32.
- `/tmp/.../query_props.cuf` (fuera del repositorio, script puntual de diagnóstico de `cudaGetDeviceProperties` — no se conserva, resultado ya transcrito en la §8).
- `prueba_streams_kin_pot/test_streams_graph.cuf`: `k_kin`/`k_pot`/`k_combina_ene` capturados en un CUDA Graph con horquilla real (§12) — el resultado positivo que revisa la conclusión de la §11.
- `resultado_graph_node.nsys-rep`: traza con `--cuda-graph-trace=node` mostrando el solapamiento real dentro del grafo (necesario ese flag; sin él los kernels del grafo no aparecen en la traza).
- `prueba_streams_kin_pot/test_streams_graph_n50.cuf`: misma prueba que `test_streams_graph.cuf` pero con `n=50` (tamaño real del proyecto, §12) — confirma que el solapamiento se mantiene a esa escala pequeña.
- `resultado_graph_n50.nsys-rep`: traza de la prueba a `n=50`.
- `prueba_streams_kin_pot/test_streams_graph_real.cuf`: paso intermedio (§13) con `nhe4=20`/`natom=21` (tamaños distintos, como el código real) y `mypow`/`myexp` reales (copiados de `hibrido_instrumentado/`: `glibc_pow.cuf`, `glibc_exp_mod.cuf`, `exp_tab_fortran.txt`, `pow_log_tab_fortran.txt`).
- `resultado_graph_real.nsys-rep`: traza de la prueba con tamaños y funciones reales — confirma el 40,4% de mejora con solapamiento genuino.
- `hibrido_instrumentado/dmc2_pipeline.cuf` (§14): implementación real de la Opción 1 — las 7 fases, arrays persistentes, construcción/lanzamiento del grafo. Fichero nuevo, no modifica `dmc2.cuf`/`hpsi_mod.cuf`.
- `hibrido_instrumentado/msteps.f90`: `pasodmc_gpu_pipeline` añadida (no toca `pasodmc_gpu`).
- `hibrido_instrumentado/mmontecarlo.f90`: `dmc_gpu_pipeline` añadida (no toca `dmc_gpu`).
- `hibrido_instrumentado/qmccluster.f90`: `case(7)` añadido.
- `compilar_pipeline.sh`: script de compilación del binario `qmccluster_pipeline` (no toca `compilar.sh`/`qmccluster_tiempos`).
- `run_test_pipeline.py`: variante de `run_test.py` apuntando a `qmccluster_pipeline`.
- `resultados/pipeline_op7.log`, `resultados/baseline_op5_vs_pipeline.log`, `resultados/pipeline_op7_largo.log`, `resultados/baseline_op5_largo.log`: verificación bit a bit (config corta y larga).
- `/tmp/resultado_op5_real.nsys-rep`, `/tmp/resultado_op7_real.nsys-rep` (fuera del repositorio, trazas puntuales de la comparación final `opcion=5` vs `opcion=7` — resultado ya transcrito en la §14).
