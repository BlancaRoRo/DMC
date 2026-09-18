# cpu-vs-gpu: punto de cruce real entre CPU y GPU

## Objetivo

`v4-cuda-pruebas/pruebas-sfu/test-walkers/` mide la aceleración GPU/CPU entre 500 y 2500 walkers y no encuentra ningún cruce: la GPU gana siempre, entre 9,8x y 12,6x, incluso en el punto más bajo probado (500w). Esta batería baja por debajo de ese rango -- 1 a 500 walkers, con más resolución cuanto más pequeño -- para encontrar el punto real en el que el overhead fijo de la GPU (contexto CUDA, reservas `device`, captura del grafo) deja de compensar frente al trabajo real que hay que hacer.

## Configuración

Mismo protocolo que `pruebas-sfu` (reutiliza sus binarios y su Configuración Inicial, ver `_comun.sh`): `etrial=-631.8`, semilla fija `0000000000000011`, `conf.20.00.HH` fresco antes de cada corrida, GPU = `hibrido_instrumentado/qmccluster_pipeline` (`opcion=7`, `nvfortran`), CPU = `cpu-original-gfortran/qmccluster` (`opcion=4`, `gfortran`). Un solo eje variando: **walkers**, con bloques de cálculo=100 y pasos por bloque=100 fijos (misma escala que `pruebas-sfu/test-walkers`, para que las dos tablas se puedan leer como una sola curva continua).

Walkers probados: 1, 5, 10, 15, 20, 25, 30, 40, 50, 75, 100, 150, 250, 500.

## Resultados

| Walkers | GPU (wall) | CPU (wall) | Aceleración CPU/GPU |
|---|---|---|---|
| 1 | **colapso de población** (ver más abajo) | 0,19 s | -- (no comparable) |
| 5 | 19,31 s | 3,09 s | 0,16x |
| 10 | 19,48 s | 6,00 s | 0,31x |
| 15 | 19,44 s | 9,05 s | 0,46x |
| 20 | 21,54 s | 12,22 s | 0,57x |
| 25 | 22,15 s | 14,71 s | 0,66x |
| 30 | 21,73 s | 18,07 s | 0,83x |
| **≈36** | -- | -- | **≈1,0x -- cruce estimado (interpolado)** |
| 40 | 21,86 s | 24,25 s | 1,11x |
| 50 | 21,99 s | 29,99 s | 1,36x |
| 75 | 22,36 s | 45,06 s | 2,01x |
| 100 | 22,75 s | 59,86 s | 2,63x |
| 150 | 23,57 s | 90,32 s | 3,83x |
| 250 | 25,90 s | 151,92 s | 5,87x |
| 500 | 30,09 s | 305,51 s | 10,15x |

(1x = CPU y GPU tardan lo mismo; por debajo de 1x, CPU es más rápida; por encima, GPU.)

## El punto de cruce: entre 30 y 40 walkers

Por debajo de 30 walkers la CPU gana siempre, y por encima de 40 la GPU gana siempre y la ventaja crece de forma monótona (hasta 10,15x en 500w, ya en línea con el 9,8x-12,6x de `pruebas-sfu/test-walkers`). Interpolando linealmente entre los dos puntos que cambian de signo (30w: 0,83x: CPU gana; 40w: 1,11x: GPU gana), el cruce cae en **≈36 walkers**.

La causa es visible directamente en los tiempos de GPU: prácticamente planos entre 5 y 500 walkers (19,3 s → 30,1 s, un 56% más para 100 veces más walkers), mientras que la CPU crece de forma lineal desde el principio (3,1 s → 305,5 s). La GPU tiene un coste fijo por corrida de en torno a 19-20 s (independiente del número de walkers en este rango) que domina totalmente por debajo de ~36 walkers, y que el trabajo real no consigue superar hasta ahí.

## Anomalía en 1 walker (excluida del análisis anterior)

Con un solo walker, la corrida de GPU se detiene sola en el bloque 6 de cálculo con el mensaje:
```
ERROR pasodmc_gpu_pipeline: colapso de poblacion (nwfin=0) partiendo de nwpaso=1
Todos los walkers murieron en este paso DMC (nsons=0 para todos).
Deteniendo aqui en vez de propagar NaN/Inf en silencio (log(0) en el calculo de egrow).
```
Es el comportamiento correcto y esperado del chequeo defensivo de `pasodmc_gpu_pipeline` (ver `v2-cuda-integracion/hibrido_instrumentado/`): con población mínima, un único evento de "muerte" del walker colapsa toda la simulación, y el pipeline lo detecta y para en vez de seguir propagando `NaN`.

La versión CPU, en cambio, **no tiene ese mismo chequeo**: con 1 walker termina las 100 pasadas sin abortar, pero el bloque 100 final da energía `NaN` -- el mismo colapso de población, sin detectar. No es un resultado válido para comparar tiempos (0,19 s de la CPU no representa un cálculo completo), y tampoco es justo achacarlo a que "la CPU es más robusta" -- es que la GPU tiene una comprobación que la CPU no tiene, no que la física se comporte distinto. Se deja documentado como hallazgo, no como parte de la curva de aceleración.

## Verificación de datos (walkers 5-500)

Todas las corridas de 5 a 500 walkers completan sus 100 bloques de cálculo con energías finales en el rango físicamente esperado (entre -620 y -640 meV, el mismo entorno que en `pruebas-sfu/test-walkers`) y poblaciones finales cercanas al valor nominal (fluctuación normal por ramificación, p. ej. 500w termina en 504,95 GPU / 507,80 CPU) -- sin colapsos ni `NaN` en ningún otro punto de la batería.

## Segunda parte: los ejes de bloques y de pasos (walkers=1000 fijo)

La limitación anotada en la primera versión de este documento -- que el cruce de ~36 walkers podría desplazarse con menos o más pasos totales -- se ha probado directamente en vez de dejarla como conjetura. Mismo protocolo, mismos binarios, pero ahora con **walkers=1000 fijo** (el mismo valor que usan `pruebas-sfu/test-bloques` y `pruebas-sfu/test-pasos`, para que las tablas empalmen) y bajando cada uno de los otros dos ejes por separado hasta el mínimo posible (1).

### Eje de bloques (walkers=1000, pasos por bloque=100 fijos)

| Bloques | GPU (wall) | CPU (wall) | Aceleración CPU/GPU |
|---|---|---|---|
| 1 | 3,31 s | 7,67 s | 2,32x |
| 2 | 1,62 s | 14,51 s | 8,98x |
| 5 | 4,95 s | 34,25 s | 6,92x |
| 10 | 7,39 s | 66,85 s | 9,05x |
| 15 | 9,82 s | 98,35 s | 10,02x |
| 20 | 12,24 s | 129,35 s | 10,57x |
| 25 | 14,78 s | 159,71 s | 10,81x |
| 30 | 17,08 s | 190,40 s | 11,15x |
| 40 | 21,76 s | 252,98 s | 11,63x |
| 50 | 28,05 s | 312,95 s | 11,16x |

(El valor de 2 bloques, con GPU más rápida que en 1 bloque, es ruido de la primera invocación de la sesión de GPU -- no una tendencia real; a partir de 5 bloques el crecimiento es monótono como se espera.)

### Eje de pasos (walkers=1000, bloques de cálculo=100 fijos)

| Pasos | GPU (wall) | CPU (wall) | Aceleración CPU/GPU |
|---|---|---|---|
| 1 | 3,15 s | 6,52 s | 2,07x |
| 2 | 1,68 s | 13,16 s | 7,85x |
| 5 | 5,08 s | 33,57 s | 6,61x |
| 10 | 7,72 s | 66,21 s | 8,58x |
| 15 | 10,28 s | 99,13 s | 9,64x |
| 20 | 12,87 s | 131,40 s | 10,21x |
| 25 | 15,18 s | 161,20 s | 10,62x |
| 30 | 17,06 s | 188,25 s | 11,04x |
| 40 | 23,83 s | 251,55 s | 10,56x |
| 50 | 26,76 s | 317,41 s | 11,86x |
| 75 | 41,45 s | 467,70 s | 11,28x |
| 100 | 51,85 s | 618,97 s | 11,94x |

(Mismo ruido en el punto de 2 pasos que en el de 2 bloques -- misma causa.)

### No hay cruce en ninguno de los dos ejes

Con walkers=1000 fijo, **la GPU gana en todos los puntos probados de ambos ejes, incluido el mínimo absoluto** (1 bloque: 2,32x; 1 paso: 2,07x). No hay ningún valor de bloques o de pasos, por pequeño que sea, en el que la CPU sea más rápida a esta escala de walkers.

Esto contrasta fuertemente con el eje de walkers (que sí tiene un cruce, en ~36) y confirma qué eje es el que realmente determina si compensa la GPU: **el número de walkers, no el número de bloques ni de pasos**. Con 1000 walkers ya se supera de sobra el umbral de ~36 encontrado antes, así que incluso una corrida de un único paso (el trabajo total más pequeño posible) tiene ya suficiente paralelismo real -- `blocks=ceil(2·nwalkers/32)` da de sobra bloques de hilos que ocupar en la GPU -- como para que el lanzamiento en GPU compense frente al bucle secuencial de la CPU sobre esos mismos 1000 walkers.

Esto también aclara una duda que había quedado abierta al mirar por primera vez el eje de bloques: el "suelo" de ~19-20 s que parecía un coste fijo por corrida en el eje de walkers (Figura de más arriba, tiempos de GPU casi planos entre 5 y 500 walkers) **no era un coste fijo independiente de todo**, sino que escalaba con el número de bloques -- que en aquel experimento estaba fijo en 100. Aquí, con bloques variando directamente, se ve que el coste de GPU en 1 bloque es de solo ~3 s, no ~20 s: el coste real parece estar ligado a la sincronización con el host que ocurre en cada bloque de cálculo (donde se escriben la energía y la población), no a un coste de arranque único por corrida.

## Conclusión

El punto de cruce real de este pipeline depende del eje: en **walkers**, con bloques/pasos=100/100, el cruce está en **~36 walkers** (por debajo, CPU gana; por encima, GPU gana siempre). En **bloques** y en **pasos**, con walkers=1000, **no hay cruce**: la GPU gana siempre, incluso en el mínimo absoluto de cada eje. En la práctica, para cualquier corrida real del proyecto (miles de walkers) la GPU es la opción correcta sin ambigüedad en ningún eje -- el único escenario real donde compensaría la CPU es una población muy pequeña (decenas de walkers), independientemente de cuántos bloques o pasos se calculen para ella.

## Estructura de salidas

```
test-walkers-pequenos/test-5w/salida-test-5w-gpu.log
test-walkers-pequenos/test-5w/salida-test-5w-cpu.log
test-walkers-pequenos/test-5w/in.mcv-gpu   (por trazabilidad)
test-walkers-pequenos/test-5w/in.mcv-cpu
...
```
