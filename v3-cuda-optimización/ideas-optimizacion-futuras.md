# Ideas de optimización futuras (no abordadas)

Backlog de vías identificadas durante esta sesión que no se han investigado a fondo
todavía — por alcance, por tiempo, o porque quedaron pendientes de una decisión.
Ninguna de estas tiene código ni medición propia; cuando se aborde alguna, debería
generar su propia carpeta con su propio `.md`, siguiendo el mismo criterio de todo
este árbol (medir primero, verificar bit a bit, documentar incluso si sale negativo).

## Memoria compartida como scratchpad de spill en `vpot` -- PROBADO, NEGATIVO

`k_vpot_t` sigue teniendo tráfico real a memoria local (~276-439 MB medidos según la
corrida, `v3-cuda-optimización/funciones-matematicas/optimización-mypow/optimizacion-mypow.md`,
`optimizacion-vpot/optimizacion-vpot.md`) -- a diferencia de `derananum`, cuyo split ya
movió sus arrays grandes a memoria global persistente (`wfhe4_s` y compañía),
`vpot`/`He_dihydrogen` no había recibido ese tratamiento.

**Probado en `optimizacion-vpot/split-he-dihidrogen.md`** (4 intentos: extracción
simple a subrutina, RDC + fichero separado, `BLOCK`/`END BLOCK`, memoria compartida
real -- micro-benchmark aislado Y cadena paralela completa en contexto real): los 4
dan **106 registros, sin cambio** frente a producción (memoria compartida SÍ bajaba
registros en aislamiento, -10,3%, pero el efecto desaparece por completo en el
contexto real de `k_vpot_t` -- el pico de registros no lo marca el bloque que se
probó a mover). Perfilado de refuerzo (`ncu --page source` sobre
`ncu_vpot_source2.csv`): el tráfico local dentro de `He_dihydrogen` está repartido
entre docenas de instrucciones SASS distintas (1-8 apariciones cada una), no
concentrado en ningún bloque -- confirma que no hay un "bloque grande" candidato
mejor que el ya probado.

**Intento 5** (split de `vpot`/`He_dihydrogen` en 2 kernels concurrentes,
He4-He4 pares vs He-impureza): mecánicamente viable (el pipeline ya tiene el
patrón de streams/eventos que haría falta) pero **2,4x más lento** -- separar
en piezas, aunque sean 2 kernels reales, le quita al compilador la vista de
conjunto que necesita para reutilizar memoria local/registros entre partes que
nunca están vivas a la vez (verificado con `nvdisasm --print-line-info-inline`:
el tamaño de pila reservado sube de 1.392 a 2.520 bytes, +81%, solo por partir
en dos funciones).

**Intento 6** (`e2terms` -- el único array real y grande de `He_dihydrogen`,
60 elementos, no probado en el Intento original -- en `SHARED`, código
completo sin tocar nada más): es el intento que más cerca estuvo de
funcionar -- **primera y única bajada real de registros de toda la
investigación (106→104)**. Pero el tiempo real no mejora (de hecho +1,1% más
lento, confirmado con el orden de medición invertido) -- mismo motivo que el
hallazgo de `maxregcount` de `perfilado-medicion/fase1-registros/`: la
ocupación de `k_vpot_t` no está limitada por registros a esta escala, así que
bajar el pico no libera ningún paralelismo que capturar, y memoria compartida
tiene su propio coste que aquí no compensa nada.

Los Intentos 1-6 (extracción a subrutina, RDC, `BLOCK`, memoria compartida
para variables escalares y para `e2terms`) se descartan por completo -- pero
un **Intento 7 y 8 posteriores** (ver más abajo) SÍ encontraron mejora real
por una vía distinta: no memoria compartida para reducir registros, sino
warps del mismo bloque para solapar latencia entre las partes ya
independientes de `He_dihydrogen`. Ver `optimizacion-vpot/split-he-dihidrogen.md`
para el detalle completo de los 8 intentos.

## Kernels persistentes + compactación de población en GPU

Ver la discusión completa en esta misma conversación (sin `.md` propio todavía).
Un kernel que hiciera varios pasos DMC seguidos sin volver a la CPU eliminaría el
coste fijo de relanzamiento por paso -- pero requiere mover a GPU el control de
población (qué walkers mueren, recompactar el array), que hoy vive enteramente en el
host (`pasodmc_gpu_pipeline`, `msteps.f90:310-591`).

**Por qué no se ha hecho**: la compactación en GPU necesita una suma de prefijos
paralela (*scan*, técnica estándar tipo Thrust/CUB) para evitar que la decisión de
"qué walkers sobreviven, en qué posición nueva" se serialice -- más el manejo de la
detección de errores/colapso de población y la sincronización de todo el grid entre
pasos (`cudaLaunchCooperativeKernel`, no un lanzamiento normal). Es un rediseño de
arquitectura real, con riesgo genuino de salir peor (más registros, más difícil de
depurar, pierdes visibilidad de progreso durante corridas largas) -- **alcance mayor
del que corresponde a un TFG**, decisión explícita de no perseguirlo esta sesión.

## Partir `vpot`/`He_dihydrogen` en 2 kernels separados -- PROBADO, NEGATIVO (pero ver más abajo)

Mismo mecanismo que funcionó con `derananum` (split en 3 kernels, ~2,6x más rápido).
`He_dihydrogen` sí tiene dos bucles genuinamente independientes (He4-He4 pares vs
He-impureza, confirmado sin dependencia cruzada), y el pipeline ya tiene el mecanismo
de streams/eventos necesario para lanzarlos concurrentes (mismo patrón que
`derananum`, confirmado leyendo `dmc2_pipeline.cuf`).

**Probado en `optimizacion-vpot/split-he-dihidrogen.md` (Intento 5)**: separar en 2
**kernels** (`k_test_hehe_t`/`k_test_impureza_t`, medidos con el mismo `atom_p`/`sprop_p`
reales) da **2,4x más lento** que la función fusionada (9,09 ms vs 3,74 ms, ambos
aislados), con más registros en el peor caso (112 vs 106) y +112% de instrucciones
ejecutadas / +40% de tráfico a memoria local. Se descartó que fuera por `G`/`R2`
(arrays de 900 elementos, verificado que el compilador ya los eliminaba por completo
gracias a `GTEST` ser constante de compilación -- quitarlos del código fuente no
cambió ni un registro ni una instrucción). Se evaluaron 3 técnicas para arreglarlo
(memoria compartida como *scratchpad*, `inline`+`block`, *unroll* a escalares): la
primera es inviable de tamaño para `G`/`R2` (230 KB/bloque, muy por encima del
límite), la segunda ya está contradicha por los Intentos 1 y 3 del mismo documento, la
tercera es matemáticamente inviable para arrays de 900 elementos. **Se descarta la vía
de 2 kernels separados por completo** -- causa raíz identificada: 2 lanzamientos
pagan prólogo/epílogo de pila por partida doble (+81% de pila) y no garantizan
co-residencia de ambos en el mismo SM.

**Corrección importante (Intentos 7 y 8, posteriores)**: la conclusión de "no hay
ninguna vía viable de paralelizar los bucles independientes de `He_dihydrogen`" era
**incorrecta** -- el problema no era paralelizar en sí, era usar **2 kernels** para
hacerlo. Repartir el mismo trabajo en **2 (o 3) warps del MISMO lanzamiento** (bloque
de 64 o 96 hilos en vez de 32) evita exactamente los dos problemas de raíz: una única
pila (un único lanzamiento) y co-residencia garantizada en el mismo SM (parte del
modelo de ejecución de warps de un bloque), lo que además permite al planificador
solapar la latencia de una rama con el trabajo de la otra. Resultado: **Intento 7**
(2 warps, He4-He4 vs He-impureza fusionado) ~25-35% más rápido según escala de
walkers, ya migrado a producción (14,2% más rápido en el pipeline completo);
**Intento 8** (3 warps, separando además dispersión de inducción) ~46-52% más
rápido que el original, ~30% más rápido que el propio Intento 7. Ver
`optimizacion-vpot/split-he-dihidrogen.md`, Intentos 7-8, para el detalle completo.

**Conclusión de la línea "reducir presión de `vpot`/`He_dihydrogen`" en conjunto**:
las 6 formas de reducir *registros* (extracción a subrutina, RDC, `BLOCK`, memoria
compartida) dan resultado negativo o neutro -- pero la vía de **solapar warps dentro
del mismo bloque** (Intentos 7-8) sí funciona, y es con diferencia la mejora más
grande conseguida sobre `vpot` en toda la sesión (~50% en el kernel aislado, ~11-14%
en el pipeline completo migrado, frente al ~8,6% de la fusión `V_hehe`+`Vp_hehe`).

**Cierre de la vía "más warps" (Intentos 9-10, y el porqué)**: se probó seguir
partiendo -- `hehe` dentro de `vpot` (Intento 9) y el bucle de pares de
`derananum_he4` (Intento 10, territorio nuevo, misma estructura que `hehe`). Ambos
ganan claramente en N pequeño (hasta +42%) pero la ganancia decae con N y se anula
(Intento 9, a partir de N≈6000) o se vuelve negativa (Intento 10, a partir de
N≈4000) -- justo el rango de walkers de las corridas reales. Migrar el Intento 8 a
producción reveló además que `derananum_he4`/`resto` casi DUPLICAN su duración al
correr concurrentes con el nuevo `vpot` (91-99% más lentos) -- confirmado con
`ncu --metrics` (no solo inferido) que el cuello real es la SFU compartida
(`smsp__warps_issue_stalled_short_scoreboard`, 53-60% del tiempo de emisión de warps
en los 3 kernels implicados, frente a ~0% de `math_pipe_throttle`) -- un recurso por
SM compartido por CUALQUIER warp residente, del mismo kernel o de kernels distintos,
que ninguna coreografía de streams (concurrente/serial/escalonado, medido) consigue
esquivar. Con esto, la vía de "seguir añadiendo warps" para `vpot`/`derananum` se da
por **agotada para producción**.

**Alternativa probada: ILP dentro de un hilo en vez de más warps (Intento 11)**:
atacar `short_scoreboard` dando a cada hilo trabajo independiente que emitir
mientras espera un resultado SFU (desenrollar 2 átomos a la vez en
`He_dihydrogen_dispersion`), en vez de repartir en más warps. Sin ninguna ganancia
medible (diferencia de tiempo 0,06%, ruido) y con un coste real (+61% registros por
duplicar variables locales). Causa confirmada con SASS (`nvdisasm`), no supuesta:
`mycos`/`mysin`/`myexp`/`mypow_log`/`mypow_desde_log` son subrutinas `device`
reales, no inlineadas (70 `CALL.ABS.NOINC`, llamada síncrona y bloqueante) -- el ILP
a nivel de código fuente no puede solapar dos llamadas reales, sin importar el
orden en que se escriban. Se probó forzar el inline (`-Minline=name:...`): sin
efecto en código `device`. El inline manual (aplanar transitivamente ~200-400+
líneas por función) se evaluó y se descartó por desproporcionado frente al
beneficio esperado, con el mismo riesgo de presión de registros que ya cerró los
Intentos 9-10.

Ver `optimizacion-vpot/split-he-dihidrogen.md` para el detalle completo (Intentos
7-11 + investigación de contención SFU).

## Causa de la caída de aceleración del split de `derananum` a 3000w

`derananum-split-concurrente.md` documenta una caída de ~2,6x a ~2,1x de aceleración
en 3000w, sin causa confirmada. Se descartó que fuera `vpot` (su peso solo sube 1
punto porcentual entre escalas, ver `optimizacion-vpot.md` Medición 2). El candidato
que queda sin comprobar es el límite de heap de `device` (~3000-3500 walkers,
`v1-cuda-desarrollo/docs-kernels/derananum.md` Parte 9).

**Primer paso si se retoma**: medir el uso real de heap/memoria durante una corrida
del split a 3000w (con `ncu`/`nsys` o `cudaMemGetInfo` en algún punto intermedio) para
ver si se acerca a algún límite, en vez de seguir especulando.
