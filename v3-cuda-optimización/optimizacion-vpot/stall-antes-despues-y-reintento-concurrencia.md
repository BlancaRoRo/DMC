# Stall antes/después de los 9 fixes de SFU, y por qué toca reintentar la concurrencia `vpot`/`derananum`

## 1. Objetivo

Con `mapa-sfu-produccion.md` ya sin ningún método "No visto", quedaban dos preguntas abiertas: (1) ¿ha bajado de verdad el stall de warps tras los 9 fixes de esta línea de trabajo? y (2) `split-he-dihidrogen.md` (Intento 8) cerró la vía de concurrencia `vpot`/`derananum` explícitamente por falta de margen "sin reducir el número real de instrucciones SFU... fuera de alcance de esa investigación" -- ¿sigue cerrada esa vía ahora que sí se ha hecho ese trabajo?

## 2. Antes/después: reconstrucción del binario pre-fixes

Los 10 ficheros tocados en toda la línea `optimizacion-vpot` (funciones nativas + 8 recíprocos/CSE) estaban sin commitear -- `git HEAD` (antes de commitear, commit `f4598d7`) es exactamente el estado "antes de todo esto". Reconstruido con `git show HEAD:<fichero>` sobre una copia aislada, recompilado, y verificado bit a bit idéntico a la producción actual (`-676.8178220759` en semilla 11) -- confirma que la cadena completa de 9 fixes es, en conjunto, bit a bit indistinguible del original en la física real.

**Aviso de alcance**: ese `git HEAD` todavía tenía el `k_vpot_t` de un solo warp (el split a 3 warps de `split-he-dihidrogen.md` también estaba sin commitear, mismo momento) -- así que la comparación de `vpot` mezclaría dos cambios distintos (arquitectura de warps + fixes de SFU). Los 3 kernels de `derananum`/`k_fase_h` sí dan una comparación limpia (misma arquitectura antes y después, solo cambian las fórmulas).

## 3. Resultado: menos trabajo total, pero más stall proporcional en SFU

Medido con `ncu` (`--section WarpStateStats` + `sm__inst_executed_pipe_xu.sum`/`sm__inst_executed.sum`/`gpc__cycles_elapsed.avg`), mismo protocolo que toda la línea de trabajo:

| Kernel | Ciclos antes → después | Instr. XU antes → después | Instr. totales antes → después | Stall MIO/`short_scoreboard` antes → después |
|---|---|---|---|---|
| `k_derananum_he4_t` | 2.492.057 → 1.521.014 (**−39,0%**) | 59.850 → 59.850 (sin cambio -- aquí pesó más el paso a funciones nativas que los recíprocos propios) | 11.055.353 → 3.894.521 (**−64,8%**) | 53,3% → 75,1% |
| `k_derananum_resto_t` | 2.931.791 → 1.430.616 (**−51,2%**) | 105.399 → 30.681 (**−70,9%**) | 11.770.530 → 3.849.792 (**−67,3%**) | 60,0% → 72,7% |
| `k_fase_h` | 454.259 → 335.277 (**−26,2%**) | 34.083 → 17.136 (**−49,7%**) | 1.102.234 → 804.181 (**−27,0%**) | 75,9% → 76,0% |
| `vpot` (`k_vpot_t`→`k_vpot_3warp_t`, arquitectura distinta, no comparación limpia) | 11.178.186 → 2.659.692 | 326.795 → 52.866 | 26.757.333 → 7.538.289 | 37,4% → 65,3% |

**El % de stall atribuido a MIO ha subido, no bajado, en los 3 kernels comparables limpiamente.** No es un resultado contradictorio: las instrucciones totales han caído mucho más (−65% a −67%) que los ciclos (−26% a −51%), porque los 9 fixes eliminaron sobre todo trabajo "de relleno" (multiplicaciones/divisiones redundantes, llamadas a `log`/`mypow` duplicadas) que antes ocupaba emisión sin depender de la SFU. Al quitar ese relleno, lo que queda por ejecutar es proporcionalmente **más** SFU que antes -- se ha exprimido la parte fácil, y el cuello de botella real (esperar el resultado de la SFU) queda más expuesto, no menos.

## 4. Por qué esto reabre la vía de concurrencia `vpot`/`derananum`

`split-he-dihidrogen.md`, tras migrar el Intento 8 (`vpot` a 3 warps) a producción, probó 3 coreografías de streams (concurrencia total / serial / escalonada) sobre `k_derananum_he4_t`+`k_derananum_resto_t`+`k_vpot_3warp_t` corriendo a la vez -- las 3 dieron el mismo tiempo de GPU (<1% de diferencia), confirmado con *stall reasons* que el cuello real era la SFU compartida (`short_scoreboard` 53-60% en los tres). Conclusión textual de esa investigación:

> "no hay margen adicional por esta vía **sin reducir el número real de instrucciones SFU** (`myexp`/`mypow`/etc.), un cambio de fórmulas mucho más invasivo, **fuera de alcance de esta investigación**"

Esa condición ya no se cumple: se ha reducido el número real de instrucciones SFU (−49,7% a −70,9% XU dinámicas en los 3 kernels que compiten por la SFU), y la sección 3 de este documento muestra que el % de stall atribuible a la SFU, lejos de diluirse, se ha concentrado más. Si antes la SFU compartida ya era el cuello de botella con menos presión relativa sobre ella, con más presión relativa ahora el margen para que una coreografía de streams distinta (escalonar en vez de lanzar los 3 a la vez) marque una diferencia real debería ser, si acaso, mayor que antes -- justo lo contrario de lo que se encontró en 2026-08-20.

## 5. Plan para el reintento (en marcha)

Repetir exactamente el experimento de `split-he-dihidrogen.md` §"Migración del Intento 8... contención de SFU", pero sobre el binario de producción actual (con los 9 fixes ya aplicados):

1. Copia aislada del `hibrido_instrumentado/` actual (ya con `k_vpot_3warp_t` + los 9 fixes).
2. Construir las 3 variantes de coreografía sobre `dmc2_pipeline.cuf`, mismo mecanismo de eventos (`cudaEventRecord`/`cudaStreamWaitEvent`) que la investigación original:
   - **Concurrente** (la actual en producción, sin cambios): `vpot` (stream_b) se lanza justo tras `ev_fork1`/`ev_fork2`, sin esperar a nada más.
   - **Escalonada**: `vpot` espera solo a que termine `k_derananum_he4_t` (evento nuevo `ev_he4_1`/`ev_he4_2`), sigue solapando con la cola de `resto`.
   - **Serial**: `vpot` espera a que terminen `he4` Y `resto` (reordenando el registro de `ev_resto1`/`ev_resto2` antes del lanzamiento de `vpot`).
3. Medir con `nsys --cuda-graph-trace=node` (tiempo real de GPU por kernel, no `ncu`, que serializa y no puede ver solape real) las 3 variantes, mismo protocolo (`conf.20.00.HH` fresco, 2000w).
4. Si alguna coreografía baja el camino crítico de forma clara y repetible, verificar bit a bit y migrar a producción; si las 3 siguen dando el mismo tiempo (<1% de diferencia, igual que en 2026-08-20), confirma que el techo real sigue siendo el throughput físico de la unidad SFU (no la forma de solaparse), y se documenta como negativo igual que la vez anterior -- con el añadido de que ahora se sabe que ni reduciendo el número de instrucciones SFU un ~50-70% se abre margen por esta vía.

## 6. Resultado del reintento: concurrente sigue ganando, y por más margen que antes

Construidas las 3 variantes sobre el binario actual (mismo mecanismo de eventos que la investigación original, verificado bit a bit idéntico entre las 3: `-676.8178220759`). Medido el timer interno del pipeline (`tiempo total opcion7`), 4 rondas con orden alternado (la última invertida, `serial→stagger→concurrente`, para descartar sesgo de posición/térmico):

| Ronda | Concurrente | Escalonada | Serial |
|---|---|---|---|
| 1 | 16,5674 s | 17,3900 s | 17,2826 s |
| 2 | 16,7669 s | 17,3855 s | 17,1555 s |
| 3 | 16,5467 s | 17,5780 s | 17,2150 s |
| 4 (orden invertido) | 16,6145 s | 17,3206 s | 17,3856 s |
| **Media** | **16,624 s** | **17,419 s** | **17,260 s** |

**Concurrente gana con claridad: −4,8% frente a escalonada, −3,8% frente a serial, consistente en las 4 rondas incluida la de orden invertido -- no es sesgo de medición.** Contradice la hipótesis de la sección 4 de este mismo documento: más presión relativa de SFU **no** abre margen para una coreografía distinta -- si acaso, la ventaja de la concurrencia total sobre las alternativas ha crecido (de <1% en 2026-08-20 a ~4-5% ahora), no se ha reducido.

### Por qué: el patrón de contención por kernel sigue igual de fuerte, en términos relativos

Con `nsys --cuda-graph-trace=node` (duración propia de cada kernel, media de 2368 lanzamientos):

| Kernel | Concurrente (compitiendo) | Escalonada/Serial (`he4`/`resto` sin `vpot` compitiendo) | Penalización por contención |
|---|---|---|---|
| `k_derananum_he4_t` | 3,897 ms | 2,015 ms | **+93%** |
| `k_derananum_resto_t` | 3,770 ms | 1,867 ms | **+102%** |
| `k_vpot_3warp_t` | 3,817 ms | 2,048 ms | **+86%** |

Prácticamente la misma magnitud de penalización que medía `split-he-dihidrogen.md` en 2026-08-20 (+91,7%/+99,2% para `resto`/`he4`) -- **la contención relativa por SFU no ha bajado**, solo se ha reducido el tiempo absoluto de cada kernel (los 9 fixes hicieron cada kernel más rápido, pero no cambiaron la proporción de tiempo que cada uno pasa esperando la SFU cuando compite con los otros dos). Con esa penalización todavía tan alta, obligar a `vpot` a esperar a `he4`/`resto` (escalonada/serial) sigue perdiendo más tiempo del que ahorra en contención -- el mismo cálculo que ya hacía correcta la concurrencia total en la investigación original sigue siendo correcto aquí, con números más favorables todavía a la concurrencia.

## 7. Barrido de walkers (500-7000): la ventaja de concurrente se diluye con N, pero no desaparece hasta 6000-7000w

A petición del usuario, se repitió la comparación de las 3 coreografías subiendo el número de walkers hasta 7000 (mismo `conf.20.00.HH` fresco por corrida, `bloq_calc=59`/`pasos=20` fijos, solo varía `nwalkers`):

| Walkers | Concurrente | Escalonada | Serial | Concurrente vs escalonada |
|---|---|---|---|---|
| 500 | 5,618 s | 6,562 s | 6,603 s | +16,8% |
| 1000 | 8,748 s | 9,765 s | 9,791 s | +11,6% |
| 2000 | 16,124 s | 16,744 s | 16,781 s | +3,8% |
| 3000 | 25,657 s | 28,317 s | 28,272 s | +10,4% |
| 4000 | 33,035 s | 33,771 s | 33,399 s | +2,2% |
| 5000 | 42,139 s | 43,214 s | 42,503 s | +2,6% |
| 6000 | 49,745 s | 49,275 s | 51,273 s | −0,9% (escalonada gana, dentro de ruido) |
| 7000 | 57,205 s | 57,556 s | 59,844 s | +0,6% (empate) |

**Confirmado con 2 rondas adicionales en 6000/7000w** (la primera limpia, la segunda contaminada por un solape accidental con otro experimento y descartada -- ver nota de metodología más abajo): 6000w da 50,365s vs 50,354s (−0,02%, empate exacto), 7000w da 59,693s vs 60,046s (+0,59%). Confirma que el empate en la cola alta no es ruido de una sola corrida -- la ventaja de la concurrencia total se diluye de forma consistente al subir walkers, hasta desaparecer del todo en el rango 6000-7000w (por encima del rango de uso real de esta simulación). No cambia la conclusión de la sección 6: en ningún punto del barrido gana una coreografía distinta a la concurrente por un margen claro y sostenido -- como mucho, empata.

**Nota de metodología**: durante este barrido se detectó y corrigió un solape accidental entre dos tareas en segundo plano (la confirmación de 6000/7000w y un experimento posterior, sección 8) que compartían GPU durante unos minutos, inflando los tiempos de la ronda afectada un 24-44% -- descartada esa ronda, se repitió limpia. Mencionado aquí porque es la razón de que la tabla de esta sección solo tenga una repetición en la mayoría de escalas (500-5000w): con el patrón ya consistente y monótono (la ventaja decae suavemente con N sin cambios de signo hasta 6000w), no se consideró necesario repetir cada punto 3 veces como sí se hizo en la sección 8 (donde el patrón resultó no monótono y sí hacía falta más repetición para separar señal de ruido).

## 8. Intento adicional: revivir el 4º warp de `vpot` (Intento 9 original) con el código actual

`split-he-dihidrogen.md` Intento 9 (partir `hehe` en 2 warps por paridad de `J1`, dando `k_vpot_4warp_t` de 128 hilos) fue positivo en N pequeño pero se anulaba a partir de N≈6000-8000, y no se migró a producción. Con la SFU reducida un 50-90% en las funciones que ese intento toca (`V_and_Vp_hehe`, vía `He_dihydrogen_hehe`/`_mitad`), vale la pena repetirlo: el balance de registros/ocupación que explicaba la caída con N puede haber cambiado.

### Implementación

`He_dihydrogen_hehe_mitad(N, X, ENERGY1, PARIDAD)` añadida a `He_dihydrogen.f` (mismo código que el Intento 9 original, filtra por `MOD(J1,2).eq.PARIDAD`) y `k_vpot_4warp_t` añadido a `dmc2_pipeline.cuf` (bloque de 128 hilos: warps 0/1 parten `hehe`, warp 2 dispersión, warp 3 inducción), sustituyendo la llamada a `k_vpot_3warp_t` en las 2 horquillas. Verificado bit a bit idéntico a producción (`-676.8178220759`, semilla 11).

### Resultado: patrón irregular, no la caída suave del Intento 9 original

Barrido 500-7000w, con repetición (3 medidas por punto en los casos dudosos, tras una primera pasada de 1 medida cada uno):

| Walkers | 3warp (media) | 4warp (media) | Diferencia | ¿Fiable? |
|---|---|---|---|---|
| 500 | 5,561 s | 5,598 s | −0,7% | Empate |
| 1000 | 8,839 s | 9,463 s | **−7,1%** | Sí -- negativo en las 3 rondas |
| 2000 | 16,057 s | 15,503 s | **+3,5%** | Sí -- positivo en las 3 rondas |
| 3000 | 26,26 s | 24,34 s | **+5 a +7%** | Sí -- positivo en las 3 (un outlier de `3warp` en una ronda) |
| 4000 | 33,047 s | 33,039 s | ~0% | Empate |
| 5000 | 41,381 s | 41,830 s | −1,1% | Sí, pequeño pero consistente en las 3 |
| 6000 | 50,486 s | 49,538 s | +1,9% | No -- el signo se invierte entre rondas |
| 7000 | 58,799 s | 57,659 s | +1,9% | No -- el signo se invierte entre rondas |

A diferencia del Intento 9 original (caída monótona y suave de +20% a ~0% según sube N), aquí el patrón **no es monótono**: gana con claridad en 2000-3000w, pierde con claridad en 1000w, y el resto es ruido o empate. La hipótesis más plausible es que los fixes de SFU cambiaron el perfil de registros de `He_dihydrogen_hehe_mitad` (menos divisiones dentro de `V_and_Vp_hehe`), desplazando el punto de cuantización de oleadas de bloques/SM (el mismo mecanismo que causaba la "anomalía de N=2000" del Intento 9 original) a un punto distinto -- no se investigó a fondo el porqué exacto, dado el resultado final.

### Decisión: NO se migra a producción

**2000w es la escala real que usa la producción (`hibrido_instrumentado/in.mcv`), y ahí gana con un +3,5% sólido** -- pero el patrón irregular en el resto del rango (pérdida clara en 1000w, ruido en 6000-7000w) lo hace demasiado frágil para confiar en producción: cualquier cambio futuro en el número de walkers de una corrida real podría caer en una zona donde este cambio pierde en vez de ganar, sin ningún indicador visible de que eso está pasando. Mismo criterio que cerró los Intentos 9/10 originales -- una ganancia real pero dependiente de la escala, sin margen de seguridad claro, no compensa el riesgo. **No se toca producción.**

## 9. Intento adicional 2: fusionar `derananum` (`he4`+`resto`+`join`) en un kernel de 2 warps

Motivación distinta a la del 4º warp de `vpot` (§8): en vez de partir más una pieza ya de por sí concurrente, aplicar a `derananum` el mismo cambio que a `vpot` le funcionó muy bien (`split-he-dihidrogen.md`, Intentos 5→7) -- pasar de **varios kernels separados en streams distintos** (arquitectura actual de `derananum`: `k_derananum_he4_t`, `k_derananum_resto_t`, `k_derananum_join_t`) a **un solo kernel con varios warps** (como `k_vpot_3warp_t`). Precedente directo: para `vpot`, 2 kernels separados fue **negativo** (2,4x más lento) y 2 warps del mismo bloque fue **positivo** (+25-35%), porque el split en kernels duplicaba el preámbulo caro (`ccuerpo()`) y el merge en warps no.

### Implementación

`k_derananum_2warp_t` añadido a `derananum_split_mod.cuf`: bloque de 64 hilos (2 warps) -- warp 0 calcula `he4` (`wavef_derwavefhe4`, escribe a memoria compartida), warp 1 calcula `resto` (las 6 llamadas de siempre) y, tras `syncthreads()`, hace también la combinación final (misma lógica que `k_derananum_join_t`), leyendo `he4` de memoria compartida. Sustituye a los 3 kernels + 2 streams + eventos `ev_resto1`/`ev_resto2` en las 2 horquillas de `dmc2_pipeline.cuf`. Verificado bit a bit idéntico a producción en 4 semillas.

### Registros: mismo "pico, no suma" que `vpot`

| | Registros/hilo |
|---|---|
| `k_derananum_resto_t` (producción, la pieza más cara de las 2) | 111 |
| `k_derananum_2warp_t` (fusionado, incluye también la lógica de `join`) | **111** |

Igual que en `vpot`: fusionar no sube el pico de registros, ni siquiera al añadir la lógica de combinación dentro del mismo warp que calcula `resto`.

### Tiempo: resultado mixto, prácticamente empatado (a diferencia de `vpot`)

Barrido 500-7000w, 2 rondas por punto:

| Walkers | Original (media) | Fusionado (media) | Diferencia |
|---|---|---|---|
| 500 | 5,686 s | 5,705 s | −0,3% |
| 1000 | 9,425 s | 9,896 s | **−5,0%** |
| 2000 | 16,614 s | 16,144 s | +2,8% |
| 3000 | 26,273 s | 26,324 s | −0,2% |
| 4000 | 33,081 s | 32,467 s | +1,9% |
| 5000 | 41,142 s | 42,815 s | **−4,1%** |
| 6000 | 49,633 s | 48,429 s | +2,4% |
| 7000 | 57,958 s | 57,296 s | +1,1% |

Sin ganador claro -- pierde en 1000w y 5000w, gana modestamente en el resto, dentro de un rango de ±2-5% que no llega a ser una mejora sistemática como la de `vpot`.

### Por qué no repite el éxito de `vpot`: comprobado con instrucciones, no solo intuido

`ncu` sobre el kernel fusionado (aislado): 7.804.516 instrucciones totales, prácticamente idéntico a `he4`+`resto` sumados por separado (3.894.521+3.849.792=7.744.313, +0,8%) -- **la fusión no reduce el trabajo total**, a diferencia de `vpot` (que al fusionar bajó un ~44% las instrucciones ejecutadas, Intento 5→7). La diferencia de fondo: el split de `vpot` duplicaba una llamada cara (`ccuerpo()`) en los 2 kernels separados; el split de `derananum` nunca tuvo esa duplicación (`he4` solo copia los átomos de He4, `resto` copia todos pero hace física distinta) -- no había tanto desperdicio que recuperar al fusionar.

**Se revisó también un posible *bank conflict*** en la memoria compartida (`d1wfhe4_sh` indexada átomo-primero en vez de walker-primero, dando acceso no contiguo entre hilos del mismo warp) -- corregido (walker/lane como primer índice) y remedido: **sin cambio medible** (2.693.334 vs 2.691.858 ciclos, tiempo real igual dentro de ruido). Confirma que el problema no es un detalle de implementación corregible, es que no hay margen estructural que capturar por esta vía.

### Conclusión: NEGATIVO, no se migra

Mismo criterio que el Intento 9 de `vpot` (§8) y que los Intentos 9/10 de `split-he-dihidrogen.md`: sin una ganancia clara y sostenida, no compensa el riesgo de cambiar la arquitectura de producción. **No se toca producción.**

## 10. Conclusión

**Negativo en los tres reintentos, no se cambia la arquitectura de producción.** La reducción de instrucciones SFU de esta línea de trabajo (9 fixes, hasta −71% XU dinámicas en algún kernel) ha hecho el pipeline completo más rápido en términos absolutos, pero **no ha cambiado la conclusión arquitectónica** de `split-he-dihidrogen.md` en ninguna de las tres vías reintentadas:

- **Coreografía de streams** (§6-7): la concurrencia total sigue siendo la mejor opción en todo el rango de uso real (500-5000w, ventaja de +2% a +17%), diluyéndose hasta empatar solo en 6000-7000w -- por encima de la escala de producción real. La intuición de la sección 4 (más stall relativo en SFU → más margen para escalonar) resultó incorrecta al comprobarla con datos: lo que haría falta es reducir la propia penalización de contención (+86-102%), no reorganizar cuándo se lanza cada kernel.
- **4º warp en `vpot`** (§8): gana con claridad en 2000-3000w (justo la escala real de producción, +3,5% a +7%) pero pierde en 1000w y empata/ruido en el resto -- patrón irregular, no la caída suave del Intento 9 original, probablemente por un desplazamiento del punto de cuantización de oleadas. Se descarta por falta de margen de seguridad frente a cambios futuros en el número de walkers, aunque en el punto exacto de uso actual habría ganado.
- **Fusión de `derananum` en 2 warps** (§9): empata dentro de ±2-5% en todo el rango, sin el patrón de ganancia clara que dio la misma técnica en `vpot` -- confirmado con instrucciones ejecutadas (la fusión no reduce trabajo total aquí, a diferencia de `vpot`) que el split original de `derananum` nunca tuvo el desperdicio que sí tenía el de `vpot` (duplicar `ccuerpo()`), así que no había margen que capturar por esta vía en particular.

Ambos reintentos confirman, con datos y no con intuición, que el margen de mejora que sigue abierto en esta línea de trabajo no está en reorganizar el paralelismo existente -- está en seguir reduciendo el número real de instrucciones SFU (la vía que sí ha funcionado en las 9 iteraciones anteriores) o en un cambio más profundo de cómo se solapa la latencia de la SFU, fuera del alcance de ambos reintentos.

## Ficheros

- Verificación hecha directamente sobre copias de `hibrido_instrumentado/` -- no persistida (quedó en `/tmp`, no en el repo).
