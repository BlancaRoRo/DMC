# Fase 1: hipótesis "1 bloque = 1 walker" (átomos repartidos entre hilos)

Prueba aislada, sin tocar `derananum`/`vpot` reales — misma metodología que `prueba_equipo_hilos/` de sesiones anteriores. Objetivo: comprobar si repartir los `natom` átomos de un walker entre los hilos de un bloque (en vez de que un solo hilo los recorra en bucle) aumenta de verdad la ocupación **y** reduce el tiempo, antes de decidir si merece la pena reescribir el código real.

## Diseño de la prueba

`test_bloque_walker.cuf`: mismo volumen de trabajo total (walkers × átomos × fórmula), 3 versiones:

- **`k_solo`**: arquitectura actual — 1 hilo = 1 walker, bucle secuencial sobre `natom=21` átomos dentro del hilo.
- **`k_bloque`**: 1 bloque = 1 walker, 32 hilos (solo los primeros 21 activos), cada uno calcula la contribución de un átomo en memoria compartida, barrera, **reducción en serie** (1 solo hilo suma los 21 valores).
- **`k_bloque_arbol`**: igual que `k_bloque` pero con **reducción en árbol** (5 pasos, todos los hilos activos participan en cada paso, no 1 solo).

Simplificación deliberada: la contribución de cada átomo es independiente (sin bucle de parejas O(n²) con escritura cruzada, como sí tiene `vpot`/parte de `derananum`) — para poder repartir un átomo por hilo sin condición de carrera. Si esta prueba hubiera dado positivo, la versión real con parejas necesitaría además resolver ese reparto — más trabajo, no cubierto aquí.

**Corrección verificada primero**: `k_solo` vs `k_bloque` bit a bit idénticos; `k_solo` vs `k_bloque_arbol` dentro de tolerancia numérica (1e-10 relativo — el orden de suma cambia con la reducción en árbol, así que no se espera bit a bit).

## Primer intento: kernel demasiado barato, resultado no fiable

Con una carga de 6 subtérminos por átomo, el kernel entero tardaba **~500 ns** — comparado con los ~21-38 ms del `k_derananum_t` real para un tamaño de problema parecido (**~40.000-80.000 veces más rápido que el caso real**). A esa escala, el coste fijo de `syncthreads()`/reducción puede dominar por completo sin decir nada sobre el caso real. Detectado por el propio usuario a mitad de la prueba — correcto: con esa carga, `k_bloque`/`k_bloque_arbol` salían ~24% más lentos que `k_solo`, un resultado no fiable por la desproporción de escala.

## Calibración: igualar el coste por walker al real

```
k_solo (6 subterminos):  268,5 ns/walker
k_derananum_t real (Fase 0): 7.014,6 ns/walker
factor de escalado necesario: 26,1x
```

Subido de 6 a **160 subtérminos por átomo** (26,1x) — con esto, `k_solo` calibrado tarda ~10,2 ms para 1.500 walkers, del mismo orden que el `k_derananum_t` real.

## Resultado, ya con carga realista

`nsys` (20 repeticiones, medición limpia sin overhead de profiler):

| Kernel | Tiempo medio | Registros/hilo | Waves/SM | Warps activos | SM throughput |
|---|---|---|---|---|---|
| `k_solo` (actual) | **10,21 ms** | 60 | 0,08 | 4,09% | 66,80% |
| `k_bloque` (reducción serie) | 10,76 ms (+5,4%) | 52 | 2,60 | 45,4-45,5% | 83,3% |
| `k_bloque_arbol` (reducción árbol) | 10,66 ms (+4,4%) | 52 | 2,60 | 45,54% | 83,80% |

**La ocupación mejora espectacularmente** (waves/SM x32, warps activos x11, throughput +17 puntos) **pero el tiempo real sigue siendo peor**, no mejor — un 4-5% más lento incluso con la reducción en árbol, la mejor de las dos variantes probadas.

## Conclusión

**La hipótesis, implementada con cuidado (reducción en árbol, carga calibrada al coste real), no da resultado en esta GPU para este patrón de cálculo.** Mejor ocupación no se tradujo en menos tiempo — el coste de sincronizar el bloque (`syncthreads()`, escritura/lectura de memoria compartida, la propia reducción) pesa más de lo que se gana en paralelismo, incluso a escala de coste por walker representativa del caso real.

Esto no descarta que el reparto de trabajo *pueda* ayudar en algún otro punto del pipeline, pero sí **descarta esta técnica concreta** (repartir átomos entre hilos de un bloque con reducción en memoria compartida) como vía de mejora para `derananum`/`vpot`, con una prueba aislada, barata, y verificada — sin haber tocado ni una línea del código real.

**Nota honesta**: esta prueba usa una carga por átomo *sintética* (calibrada en magnitud, no en patrón exacto de instrucciones) y sin el patrón de parejas O(n²) real. Es razonablemente representativa para la pregunta "¿ayuda la ocupación aquí?", pero no es una réplica exacta de `derananum`/`vpot` — si en el futuro se quisiera una confirmación definitiva, haría falta la prueba sobre el kernel real (más cara de montar, con el problema añadido del reparto de parejas).

## Segundo intento: varios walkers por bloque — PRIMER RESULTADO POSITIVO

Hipótesis de por qué fallaba lo anterior: en "1 bloque = 1 walker", los hilos que sobran dentro de un bloque **no se pueden reaprovechar para otro walker** — están atados a ese walker, y si no hacen falta se quedan completamente ociosos. Con `atomos_por_hilo` creciente (`k_bloque_grupo`, prueba intermedia) esto se comprobó de forma extrema: a `atomos_por_hilo=21` (todo el trabajo en 1 solo hilo del bloque, los otros 31 sin hacer nada) el kernel fue **~20 veces más lento** que `k_solo` — un warp tarda lo mismo en ejecutar una instrucción tenga 1 hilo activo o 32, así que desperdiciar 31 de 32 carriles cuesta caro.

**`k_multiwalker`**: generaliza toda la familia con un parámetro `walkers_por_bloque` (W). Bloque fijo de 32 hilos, repartidos en `T=32/W` hilos por walker — los hilos "sobrantes" de un walker child ahora pertenecen a **otro** walker del mismo bloque, no se desperdician. `W=32` (T=1) reproduce `k_solo` exactamente; `W=1` (T=32) reproduce `k_bloque_arbol` exactamente. Reducción **segmentada**: cada grupo contiguo de T hilos se reduce solo entre sí (árbol de log2(T) pasos), no los 32 hilos del bloque a la vez.

Verificado bit a bit (`W=32`, `W=1`) o con tolerancia numérica (resto) contra `k_solo` en las 6 configuraciones antes de medir tiempo.

| `walkers_por_bloque` | hilos/walker | tiempo (`nsys`, 20 repeticiones) | vs `k_solo` (~10,5-11,5 ms) |
|---|---|---|---|
| 1 | 32 | 10,76 ms | ≈ igual |
| 2 | 16 | 10,77 ms | ≈ igual |
| 4 | 8 | 8,12 ms | ~28% más rápido |
| 8 | 4 | 8,13 ms | ~28% más rápido |
| **16** | **2** | **7,47 ms** | **~30-35% más rápido** |
| 32 | 1 (= `k_solo`) | 8,75 ms | caso degenerado, ver nota |

**`walkers_por_bloque=16` (2 hilos por walker, ~11 átomos cada uno) es el punto óptimo**: ~30-35% más rápido que `k_solo`, con muy poca dispersión entre repeticiones (<0,1%) — no es ruido.

`ncu` sobre el caso ganador (`W=16`) vs `k_solo`:

| | `k_solo` | `k_multiwalker` (W=16) |
|---|---|---|
| Registros/hilo | 60 | 64 |
| Grid size | 47 bloques | 94 bloques |
| Waves/SM | 0,08 | 0,16 (x2) |
| Warps activos | 4,09% | 8,19% (x2) |
| SM throughput | 66,79% | 83,79% |

A diferencia de `k_bloque_arbol` (que multiplicaba la ocupación x11 pero perdía por el coste de sincronización), aquí la ocupación solo sube x2 — pero el *throughput* de cómputo sube igualmente (66,79%→83,79%), señal de que cada warp activo está haciendo más trabajo útil por ciclo: dividir el bucle de 21 átomos en 2 mitades de ~11 da al compilador dos cadenas de cómputo independientes que solapar (esconder mejor la latencia de las funciones especiales `exp()`/`**`), sin pagar el coste de una reducción larga (con T=2 solo hace falta 1 paso de reducción, no 5 como con T=32).

**Nota sobre `W=32`**: en teoría es idéntico a `k_solo` (T=1, cada hilo un walker completo), pero en la práctica sale ~8,75 ms frente a los ~10,5-11,5 ms de `k_solo` — la única diferencia de código es que `k_multiwalker` sigue escribiendo su resultado en memoria compartida (`parcial(tid)=acumulado`) antes de leerlo de vuelta, aunque el bucle de reducción no llegue a ejecutarse (`stride` empieza en 0). Curioso, no investigado a fondo — no es el caso de interés (el interesante es `W=16`).

## Prueba de robustez: ¿se mantiene la mejora en otras escalas de walkers?

`barrido_robustez.sh`: repite `W={4,8,16,32}` en 5 escalas de walkers (500/1000/1500/2000/3000), no solo la escala original de 1.500 — para comprobar que la ganancia de la sección anterior no era un efecto puntual de esa única escala.

| Walkers | `k_solo` | W=4 | W=8 | W=16 | W=32 |
|---|---|---|---|---|---|
| 500 | 10,52 ms | **3,05 ms (3,45x)** | 3,17 ms (3,32x) | 5,14 ms (2,04x) | 7,83 ms (1,34x) |
| 1.000 | 11,49 ms | **5,58 ms (2,06x)** | 6,09 ms (1,89x) | 5,81 ms (1,98x) | 8,75 ms (1,31x) |
| 1.500 | 11,43 ms | 8,11 ms (1,42x) | 8,12 ms (1,40x) | **7,46 ms (1,53x)** | 8,75 ms (1,31x) |
| 2.000 | 14,32 ms | 10,89 ms (1,32x) | 11,16 ms (1,28x) | 11,16 ms (1,28x) | **11,09 ms (1,29x)** |
| 3.000 | 17,84 ms | 16,18 ms (1,08x) | 16,23 ms (1,13x) | **14,90 ms (1,23x)** | 14,25 ms (1,21x) |

**La mejora es real y se mantiene en las 5 escalas — nunca es peor que `k_solo`, ni una sola vez en 20 combinaciones.** Pero con dos matices importantes:

1. **La ganancia es mucho mayor cuanto menos walkers hay** (3,3-3,5x a 500 walkers, bajando a ~1,1-1,2x a 3.000). Coincide exactamente con el hallazgo de `test-walker.md`: la GPU rendía peor precisamente a esas escalas bajas (por debajo de 500 walkers, incluso perdía contra la CPU) — este patrón podría ser, al menos en parte, la explicación de por qué, y una vía real para mejorarlo justo donde más falta hace.
2. **El valor óptimo de W no es siempre el mismo**: W=4 gana claramente a 500-1.000 walkers, pero W=16 gana a 1.500 y 3.000, y a 2.000 walkers las 4 opciones están prácticamente empatadas (1,28x-1,32x). No hay un único "mejor W" universal — depende de la escala. Para el código real, esto sugeriría o bien fijar un valor razonablemente bueno en todo el rango (W=16 nunca es el peor, y es el mejor o casi el mejor en 3 de las 5 escalas), o hacerlo configurable.

## El problema de las parejas: probado, y el resultado es NEGATIVO

Todo lo anterior usaba contribuciones de átomo *independientes* — `derwavefhe4`/`derwavefx` (dentro de `derananum`) y `vpot` de verdad tienen un **bucle de parejas O(n²/2)** (`iatom=1,natom-1; jatom=iatom+1,natom`) donde cada pareja actualiza **los dos átomos a la vez** (`d1(iatom)` Y `d1(jatom)`, escritura cruzada). Se probó con una réplica fiel de ese patrón exacto (`test_parejas.cuf`, función `pieza_parejas`, mismo bucle que `derwavefhe4_mod.cuf`).

### Reparto sin condiciones de carrera (funciona, verificado)

Se reparte el bucle **exterior** (`iatom`) en T trozos contiguos, uno por hilo del walker. Cada hilo acumula su trozo en un array **propio y completo** (`d1_local(natom)`, `d2_local(natom)`, inicializado a cero — no solo "sus" átomos, porque una pareja escribe en los dos, y un átomo puede recibir contribuciones de parejas repartidas a hilos distintos). Tras la barrera, se combinan los T arrays completos, elemento a elemento, vía memoria compartida. **Verificado correcto en las 6 configuraciones de `walkers_por_bloque` (1,2,4,8,16,32), con tolerancia numérica.**

### Pero el rendimiento es peor, no mejor — y empeora cuanto más se reparte

| `walkers_por_bloque` | hilos/walker | `k_multiwalker_parejas` | vs `k_solo_parejas` (~0,92 ms) |
|---|---|---|---|
| 1 | 32 | 2,72 ms | **2,97x más lento** |
| 2 | 16 | 2,36 ms | 2,57x más lento |
| 4 | 8 | 1,66 ms | 1,81x más lento |
| 8 | 4 | 1,27 ms | 1,39x más lento |
| 16 | 2 | 1,07 ms | 1,17x más lento |
| 32 | 1 (≈ `k_solo`) | 0,97 ms | 1,06x más lento (caso degenerado) |

**Exactamente la tendencia contraria** a la de átomos independientes: aquí cuantos más hilos por walker, peor — nunca gana, ni una sola configuración.

### Por qué: el coste de la reducción crece con el tamaño del dato, no solo con el número de hilos

Con átomos independientes, cada hilo solo tenía que dejar **1 número** en memoria compartida (su `kin` parcial) — la reducción combinaba escalares. Aquí, cada hilo tiene que dejar **un array completo de `natom`=21 posiciones, en 4 campos** (`d1x`,`d1y`,`d1z`,`d2` → 84 valores) porque el resultado de su trozo de parejas afecta a *todos* los átomos, no a uno propio. La reducción pasa de combinar 1 valor por hilo a combinar 84 — ese tráfico de memoria compartida adicional cuesta más de lo que se gana al repartir el cálculo, y cuantos más hilos participan (T más grande), más rondas de esa reducción cara hacen falta.

## Variante: suma atómica directa, sin array local ni fase de reducción aparte

Pregunta del usuario que motivó esta prueba: ¿por qué no sumar directamente en la posición del átomo correspondiente, en vez de que cada hilo se quede su propia copia completa y luego reducir? `k_multiwalker_parejas_atomic`: memoria compartida indexada solo por **átomo** (no por átomo × hilo, mucho menos memoria: `natom×W` en vez de `natom×32`), cada hilo sube su contribución con `atomicadd` directamente según va calculando cada pareja — sin array local propio, sin fase de reducción aparte (evita la barrera + recorrido de 84 valores × log2(T) de la versión anterior).

**Corrección verificada** en las 6 configuraciones (tolerancia numérica, el orden de las sumas atómicas no es determinista).

| `walkers_por_bloque` | `k_solo_parejas` | reducción (array completo) | atómico (directo) |
|---|---|---|---|
| 1 | 0,918 ms | 2,721 ms | **2,310 ms** (mejor que la reducción) |
| 2 | 0,918 ms | 2,362 ms | **2,215 ms** (mejor) |
| 4 | 0,886 ms | 1,606 ms | **1,539 ms** (mejor) |
| 8 | 0,918 ms | 1,271 ms | 1,435 ms (peor que la reducción) |
| 16 | 0,918 ms | 1,073 ms | 1,118 ms (peor) |
| 32 | 0,918 ms | 0,971 ms | 1,024 ms (peor) |

**La idea sí mejora las cosas, pero no lo suficiente**: gana a la reducción por array completo cuando hay muchos hilos por walker (T=32,16,8 → wpb=1,2,4), donde esa reducción era más cara — tiene sentido, ahí es donde el árbol de reducción tenía más rondas. Pero pierde frente a la reducción cuando hay pocos hilos (T=4,2,1 → wpb=8,16,32), donde el coste de serializar sumas atómicas (varios hilos intentando sumar al mismo átomo a la vez) empieza a pesar más que una reducción corta. **En ningún caso, ni con la mejor combinación, se le gana a `k_solo_parejas`** — el mejor resultado (`wpb=4`, atómico) sigue siendo ~1,74x más lento que la arquitectura actual.

## Conclusión general de la Fase 1

**El patrón "varios walkers por bloque" funciona de verdad para cálculos por átomo independientes** (~30-35% más rápido, W=16 óptimo) — pero **no sobrevive al bucle de parejas O(n²) que `derwavefhe4`/`derwavefx`/`vpot` tienen de verdad**. Con parejas, la misma técnica es siempre más lenta que la arquitectura actual (1,06x-2,97x más lenta según cuántos hilos se repartan), porque la reducción pasa de combinar 1 número por hilo a combinar un array completo de 84 valores (`natom`×4 campos) — ese coste de memoria compartida adicional se come la ganancia por completo, y empeora cuantos más hilos participan.

**Conclusión práctica para el código real**: dado que `derananum` (144 registros, 73,8% del tiempo de GPU en la Fase 0) y `vpot` (247 registros, 25,5%) son precisamente los kernels con bucles de parejas — la parte de su cómputo que domina el tiempo — **esta técnica no serviría para acelerarlos tal cual**. No se ha llevado a `derananum`/`vpot` reales porque la prueba aislada, más barata y más rápida de hacer, ya mostró que fallaría antes de arriesgar tocar código validado.

**Lo que sí queda de valor de esta fase**: si en el futuro apareciera en el pipeline algún cálculo por-átomo genuinamente independiente (sin parejas), esta técnica (W=16, reducción segmentada de 1 paso) es una opción real y verificada. Para `derananum`/`vpot` tal como están hoy, no.

## Cuarto intento: varios BLOQUES por walker (no varios hilos), con `atomicAdd` a memoria GLOBAL -- también NEGATIVO

Retomado el `18/08` a raíz de `v4-cuda-pruebas/prueba1-2000w-500pasos-bloque/` (hallazgo: `Waves Per SM=0,33`, el grid del pipeline real es demasiado pequeño para llenar la GPU) y `v4-cuda-pruebas/prueba2-threads-por-bloque/` (subir hilos/bloque no ayuda, porque no cambia el número de bloques). Idea nueva del usuario, distinta de todo lo anterior: en vez de repartir hilos **dentro de un bloque** (lo ya probado arriba, siempre con memoria compartida), repartir las parejas de **un solo walker entre varios bloques independientes**, sumando con `atomicAdd` **directo a memoria global** -- sin *array* local de 84 valores por hilo, sin reducción en memoria compartida. Como los bloques no pueden hacer `syncthreads()` entre sí, hace falta un kernel aparte para la combinación final:

- `k_multiblock_parejas_atomic`: `B` bloques × 32 hilos reparten las `B*32` porciones del bucle exterior de UN walker; cada hilo sube su contribución con `atomicAdd` directo al acumulador global del walker (`d1x_g`/`d1y_g`/`d1z_g`/`d2_g`, dimensionado `natom×n`).
- `k_cierre_multiblock`: kernel separado, lanzado después en el mismo *stream* (se ordena solo, sin necesitar sincronización de grid), que lee el acumulador ya completo y calcula `kin`.
- `k_zera_global`: pone a cero el acumulador antes de cada lanzamiento (memoria global no se auto-inicializa como la compartida de cada bloque).

Multiplica el grid por `B` -- ataca directamente el `Waves Per SM` bajo del pipeline real, algo que ninguna técnica anterior de esta fase probó (todas mantenían 1 bloque = 1 o varios walkers, nunca varios bloques para 1 walker).

**Corrección verificada** (`test_multiblock_parejas.cuf`, tolerancia numérica -- suma atómica, orden no determinista) en B=1,2,4,8,16, las 1.500 configuraciones dan resultados idénticos a `k_solo_parejas` dentro de tolerancia.

### Resultado (`nsys`, 20 repeticiones, 1.500 walkers)

| B (bloques/walker) | `k_solo_parejas` | `multiblock` (total, con `zera`+`cierre`) | Factor |
|---|---|---|---|
| 1 | 917.595 ns | 2.245.255 ns | 2,45x más lento |
| 2 | 917.487 ns | 2.328.512 ns | 2,54x más lento |
| 4 | 917.698 ns | 2.407.594 ns | 2,62x más lento |
| 8 | 919.290 ns | 2.468.531 ns | 2,69x más lento |
| 16 | 918.087 ns | 2.701.194 ns | 2,94x más lento |
| 32 | 877.685 ns | 3.906.342 ns | 4,45x más lento |

**Negativo, y empeora de forma monótona y constante según sube B** -- justo la dirección contraria a la que se esperaba (más bloques = atacar `Waves Per SM`). Ya en B=1 (comparable casi directo al `k_multiwalker_parejas_atomic` con `wpb=1` de la sección anterior, memoria compartida en vez de global -- 2,25ms aquí vs 2,31ms allí, coherente) es 2,45x más lento que la arquitectura actual.

### Por qué

Con `B` bloques repartiendo las parejas de un mismo walker, todos escriben con `atomicAdd` sobre el mismo destino pequeño: solo `natom×4=84` posiciones de memoria global por walker. Cuantos más bloques activos a la vez apuntan a ese conjunto reducido de direcciones, más se serializan las escrituras atómicas -- y la latencia de memoria GLOBAL (mayor que la memoria compartida, que ya salía cara en la sección anterior) agrava el problema. La contrapartida que el propio usuario anticipó (contención en el `atomicAdd`) resultó ser el efecto dominante, sin que la ganancia de más bloques la compense en ningún punto probado.

### Conclusión de este intento

**Confirma y refuerza la conclusión general de la Fase 1**: ninguna variante de "repartir el bucle de parejas entre más unidades de ejecución paralelas" (hilos dentro de un bloque, o ahora bloques enteros) mejora sobre `k_solo_parejas`/la arquitectura actual -- el coste de combinar los resultados parciales (reducción en memoria compartida, o ahora contención de `atomicAdd` en memoria global) supera siempre la ganancia de paralelismo, y en el caso de `atomicAdd` global, empeora cuanto más se reparte, no al revés. El `Waves Per SM=0,33` del pipeline real sigue sin una vía de mejora encontrada dentro de esta familia de técnicas.

## Quinto intento (Fase 1.6): bucle de parejas en CUADRADO completo, sin escritura cruzada

Idea del usuario: en vez de repartir el bucle triangular O(n²/2) (que obliga a escritura cruzada entre átomos y por tanto a la reducción cara de 84 valores), calcular el CUADRADO completo O(n²) -- para cada átomo `iatom` que un hilo posee, evaluar su interacción con **todos** los demás átomos por separado (sin compartir el resultado con la pareja recíproca). El doble de evaluaciones de pareja, pero cada hilo escribe **solo en sus propios átomos** -- sin escritura cruzada, sin reducción de array, sin atómicas.

**Equivalencia física verificada antes de implementar**: para el par (i,j), `rtemp_ij=-rtemp_ji`, y `rij`/`ujasp`/`ujass` dependen solo de `|rtemp|` (mismo valor en ambos sentidos) -- evaluar (i,j) aporta a `d1(i)` exactamente lo mismo que aportaba el término cruzado del bucle triangular, y evaluar (j,i) por separado aporta a `d1(j)` lo mismo que el `d1(jatom) -= ...` del original.

**Implementación**: `pieza_parejas_full` + `k_multiwalker_parejas_full` en `test_parejas.cuf` -- mismo reparto W/T que las variantes anteriores, pero el hilo reduce su propio trozo directamente a **un escalar** (`d2(iatom)+|d1(iatom)|²` sumado sobre sus átomos), igual que el caso de átomos independientes que sí ganó al principio de esta fase -- no de 84 valores como `_parejas`/`_parejas_atomic`.

**Corrección verificada** (tolerancia numérica) en las 6 configuraciones de `walkers_por_bloque`.

### Resultado: mejora sobre las otras 2 variantes de reparto, pero sigue sin ganar a `k_solo_parejas`

| `walkers_por_bloque` | `k_solo_parejas` | reducción (array) | atómico | **cuadrado completo** |
|---|---|---|---|---|
| 1 | 918 μs | 2,97x más lento | 2,51x más lento | **2,39x más lento** |
| 2 | 918 μs | 2,57x más lento | 2,41x más lento | **2,38x más lento** |
| 4 | 918 μs | 1,81x más lento | 1,74x más lento (mejor) | **1,79x más lento** |
| 8 | 919 μs | 1,39x más lento | 1,56x más lento | **1,78x más lento** |
| 16 | 917 μs | 1,17x más lento (mejor) | 1,22x más lento | **1,64x más lento** |
| 32 | 869 μs | 1,06x más lento | 1,11x más lento | **1,92x más lento** |

Mejora sobre la reducción de array cuando hay **muchos hilos por walker** (ahí la reducción de 84 valores era más cara, evitarla compensa parte del doble de cómputo), pero es **peor que las otras 2 variantes cuando hay pocos hilos** (ahí la reducción ya era barata, así que pagar el doble de trabajo sale caro sin nada que lo compense). En ningún punto del barrido le gana a `k_solo_parejas`.

### Barrido adicional: más hilos por walker (T>32) y más walkers (N)

Generalizado `test_parejas.cuf` para soportar bloques >32 hilos (`threads_por_bloque` como argumento nuevo, `blockDim%x` en vez de `32` hardcodeado dentro de los kernels) -- así se puede probar T=64 y T=128 hilos por walker (más allá del máximo de 32 que permite un bloque de 1 solo warp), y N=3000 walkers además de los 1.500 habituales.

**Aviso de medición**: generalizar `k_multiwalker_parejas` (reducción de array) obligó a doblar su memoria compartida estática reservada (de `(natom,32)` a `(natom,64)`, indexada directamente por `tid`) para que T=64 no escriba fuera de rango -- esto reduce la ocupación **incluso en T=32**, donde la mitad extra nunca se usa. Los valores de T=32 de esta tabla no son comparables en absoluto a los de la tabla anterior (2,97x); la comparación **dentro de esta serie** (T=32 vs 64 vs 128, mismo array reservado en los tres) sigue siendo válida. Por encima de T=64, la propia reducción de array escribiría fuera de rango (`illegal memory access`, confirmado) -- se salta su lanzamiento en T=128, con aviso.

| N | T | reducción array | atómica | cuadrado completo | `k_solo_parejas` |
|---|---|---|---|---|---|
| 1500 | 32 | 4,43x | 2,52x | 2,11x | 919 μs |
| 1500 | **64** | 4,65x | **2,21x** | **1,87x** (mejor de toda la fase) | 909 μs |
| 1500 | 128 | (saltada, T>64) | 2,53x | 2,34x | 918 μs |
| 3000 | 32 | 5,27x | 2,50x | 2,38x | 1.419 μs |
| 3000 | 64 | 5,92x | 2,64x | 2,35x | 1.420 μs |
| 3000 | 128 | (saltada, T>64) | 3,24x | 3,06x | 1.420 μs |

**Hallazgos**: T=64 es un óptimo local para `atómica` y `cuadrado completo` a N=1500 (mejora sobre T=32 y T=128), pero esa mejora se diluye o desaparece a N=3000. T=128 siempre empeora en las 3 variantes y las 2 escalas -- coherente con la física: `natom_real=21`, así que con 128 hilos/walker la mayoría (107 de 128) no tiene ningún átomo asignado, puro desperdicio de carriles del warp. La reducción de array empeora monótonamente con T en ambas escalas (más pasos de reducción sobre el array de 84 valores). **En ninguna de las 18 combinaciones probadas (3 variantes × 3 T × 2 N) ninguna variante le gana a `k_solo_parejas`** -- el mejor caso general (cuadrado completo, T=64, N=1500) sigue siendo 1,87x más lento.

### Conclusión de la Fase 1.6

Confirma, con dos ejes más explorados (granularidad del bucle de parejas, y número de hilos/walkers), la conclusión ya establecida de toda la Fase 1: repartir el bucle de parejas entre hilos de un bloque -- sea con reducción de array, con atómicas, o evitando la escritura cruzada con el doble de cómputo -- pierde siempre contra la arquitectura actual (`k_solo_parejas`), en las 24 configuraciones distintas probadas en total entre las 3 variantes.

## Ficheros

- `prueba_aislada/test_bloque_walker.cuf`: las 5 versiones de kernel (`k_solo`, `k_bloque`, `k_bloque_arbol`, `k_bloque_grupo`, `k_multiwalker`) + programa de prueba con verificación de corrección integrada (bit a bit o con tolerancia numérica según el caso).
- `prueba_aislada/nsys_bloque_vs_solo.nsys-rep`: primera medición (kernel sin calibrar, descartada por desproporción de escala).
- `prueba_aislada/nsys_bloque_vs_solo_calibrado.nsys-rep`: medición definitiva de `k_bloque`/`k_bloque_arbol`, con la carga ya calibrada.
- `prueba_aislada/ncu_calibrado2.csv`: registros/ocupación/throughput de `k_solo` vs `k_bloque_arbol` a carga calibrada.
- `prueba_aislada/nsys_grupo_apt{1,2,3,4,7,21}.nsys-rep`: barrido de `atomos_por_hilo` en `k_bloque_grupo` (1 walker/bloque) — resultado negativo, cuanto más alto peor.
- `prueba_aislada/nsys_multi_wpb{1,2,4,8,16,32}.nsys-rep`: barrido de `walkers_por_bloque` en `k_multiwalker` — **resultado positivo en W=16**.
- `prueba_aislada/ncu_multi_wpb16.csv`: registros/ocupación/throughput de `k_solo` vs `k_multiwalker` (W=16, el caso ganador).
- `prueba_aislada/barrido_robustez.sh`, `prueba_aislada/robustez/`: prueba de robustez — W={4,8,16,32} × 5 escalas de walkers (500-3.000), 20 corridas de `nsys`.
- `prueba_aislada/test_parejas.cuf`: réplica fiel del bucle de parejas O(n²) real (`pieza_parejas`, mismo patrón que `derwavefhe4_mod.cuf`) — `k_solo_parejas` (referencia), `k_multiwalker_parejas` (reparto + reducción de array completo) y `k_multiwalker_parejas_atomic` (reparto + suma atómica directa, sin reducción aparte). **Las dos variantes de reparto son más lentas que `k_solo_parejas`** en las 6 configuraciones probadas.
- `prueba_aislada/nsys_parejas_wpb{1,2,4,8,16,32}.nsys-rep`: medición del barrido de `walkers_por_bloque` con parejas (reducción de array completo) — siempre más lento que `k_solo_parejas`.
- `prueba_aislada/nsys_atomic_wpb{1,2,4,8,16,32}.nsys-rep`: medición de la variante con suma atómica directa — mejora sobre la reducción a T alto, pero tampoco le gana a `k_solo_parejas` en ningún caso.
- `prueba_aislada/test_multiblock_parejas.cuf`: `B` bloques por walker + `atomicAdd` a memoria global (en vez de varios hilos/walkers por bloque + memoria compartida) — `k_multiblock_parejas_atomic` (acumulación) + `k_zera_global` (inicialización) + `k_cierre_multiblock` (combinación final, kernel aparte por no poder `syncthreads()` entre bloques). **Resultado negativo, empeora de forma monótona según sube B** (2,45x más lento en B=1, hasta 4,45x en B=32).
- `prueba_aislada/multiblock/nsys_multiblock_B{1,2,4,8,16,32}.nsys-rep`: medición del barrido de B — confirma la contención de `atomicAdd` en memoria global como efecto dominante, sin que la ganancia de más bloques la compense en ningún punto.
- `prueba_aislada/test_parejas.cuf` (ampliado, Fase 1.6): añadida `pieza_parejas_full`/`k_multiwalker_parejas_full` (bucle en cuadrado completo, sin escritura cruzada, reducción a escalar) + `threads_por_bloque` como argumento nuevo (generaliza `k_multiwalker_parejas`/`_atomic`/`_full` a bloques >32 hilos vía `blockDim%x`).
- `prueba_aislada/nsys_full_wpb{1,2,4,8,16,32}.nsys-rep`: medición del barrido de `walkers_por_bloque` con la variante en cuadrado completo (T=32 fijo) -- mejora sobre `_parejas`/`_parejas_atomic` en T alto, pero no le gana a `k_solo_parejas` en ningún caso.
- `prueba_aislada/nsys_sweep_n{1500,3000}_T{32,64,128}.nsys-rep`: barrido de hilos/walker (T) y escala de walkers (N) sobre las 3 variantes -- T=64 es óptimo local a N=1500 (no se sostiene a N=3000), T=128 siempre peor, ninguna variante le gana nunca a `k_solo_parejas`.
