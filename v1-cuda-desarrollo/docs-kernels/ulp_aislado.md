# Prueba aislada: FMA vs. funciones transcendentales (`dexp`/`dcos`/`dsin`)

Documentación de [`v1-cuda-desarrollo/ulp_aislado/ulp_aislado.cuf`](../ulp_aislado/ulp_aislado.cuf). No es un kernel de la simulación — es un experimento aparte, sin ninguna física del DMC de por medio, para comprobar de forma controlada la explicación que se dio sobre por qué las diferencias de ULP en `vpot`/`potenbh`/`He_dihydrogen` no desaparecen con `-Kieee -Mnofma` (a diferencia de lo que pasaba con `Vp_hehe` en solitario, ver `V_hehe_Vp_hehe.md` §9).

Pregunta a responder: ¿la fusión FMA y las funciones transcendentales (`dexp`/`dcos`/`dsin`) son la misma causa, o dos causas independientes? Se aíslan las dos por separado, sin nada alrededor, y se comparan **tres vías**: CPU(`nvfortran`), GPU(`nvfortran`), CPU(`gfortran`) — con y sin `-Mnofma`.

## Máquina de prueba

```
GPU: NVIDIA GeForce RTX 4060 Laptop GPU, driver 580.159.03
CUDA: 12.3 (nvcc V12.3.103)
```
Esto no es un problema de esta tarjeta en concreto: `libdevice` (la biblioteca que resuelve `dexp`/`dcos`/`dsin` en GPU, ver más abajo) viene fijada por la versión del SDK de CUDA instalado, no por el modelo físico de GPU — cualquier GPU NVIDIA compatible con este mismo CUDA 12.3 (incluida la de una VM que use el mismo SDK) reproduciría exactamente el mismo comportamiento.

## El experimento

[`ulp_aislado.cuf`](../ulp_aislado/ulp_aislado.cuf) prueba, con 8 valores genéricos cada una (magnitudes parecidas a distancias/ángulos reales del proyecto):
- **`fma_expr(a,b,c) = a*b+c`**: la misma forma de expresión que se aisló en `Vp_hehe` (`V_hehe_Vp_hehe.md` §9), pero sin nada de física alrededor — control para comprobar si la fusión FMA por sí sola sigue reproduciéndose con datos genéricos.
- **`dexp(x)`, `dcos(x)`, `dsin(x)`**: cada función llamada sola, sin ninguna multiplicación/suma alrededor que pueda mezclar su resultado con otra fuente de error.

### Cómo ejecutarlo

Desde `v1-cuda-desarrollo/ulp_aislado/`:
```bash
nvfortran -cuda ulp_aislado.cuf -o test_sinflags && ./test_sinflags
nvfortran -cuda -Mnofma ulp_aislado.cuf -o test_nofma && ./test_nofma
gfortran test_ulp_aislado_gfortran.f90 -o test_gfortran && ./test_gfortran
```

## Resultado 1: la FMA, con estos datos, no muestra asimetría CPU-GPU — pero sí revela algo nuevo

```
=== FMA aislada: y = a*b+c === (sin flags)
  #1  CPU=    6.3526889661567187  GPU=    6.3526889661567187  |err|= 0.00E+00
  ... (los 8 casos dan |err|=0.00E+00)

=== FMA aislada: y = a*b+c === (-Mnofma)
  #1  CPU=    6.3526889661567179  GPU=    6.3526889661567179  |err|= 0.00E+00
  ... (los 8 casos dan |err|=0.00E+00, igual que sin flags)
```
Con estos 8 valores concretos, CPU y GPU **coinciden siempre**, con o sin `-Mnofma` — a diferencia de `Vp_hehe`, donde la asimetría sí aparecía. Esto confirma algo ya apuntado en la conversación: la fusión FMA depende de los bits concretos de cada operación (si el resultado con y sin fusión cae en el mismo `double` más cercano o no), no es un fallo que aparezca siempre que se usa `a*b+c` — con `Vp_hehe` se tuvo suerte (o mala suerte) de dar con una combinación que sí lo mostraba; con estos 8 valores genéricos, no.

**Pero hay un hallazgo real e inesperado**: la columna **CPU cambia entre las dos compilaciones** (`6.3526889661567187` sin flags vs `...179` con `-Mnofma`, en el caso #1). Eso quiere decir que `-Mnofma` en `nvfortran` **no es una flag solo-GPU** — al ser `fma_expr` una función `attributes(host,device)`, `nvfortran` la compila dos veces desde el mismo fuente (una para host, otra para device), y `-Mnofma` afecta a **las dos** generaciones de código, no solo a la de GPU. Como cambia igual en ambos lados, CPU y GPU se mantienen sincronizados pase lo que pase con la flag — por eso `|err|=0.00E+00` en las dos compilaciones.

**Comparando contra `gfortran`** (que no tiene ningún control de FMA activado por defecto, no fusiona):
```
gfortran, caso #1: 6.3526889661567179
```
Coincide con `nvfortran -Mnofma` (`...179`), y difiere de `nvfortran` sin flags (`...187`, que sí fusiona por defecto). Es la misma historia que ya se vio en `qmccluster` completo (`V_hehe_Vp_hehe.md` §9): el `nvfortran` por defecto fusiona, `gfortran` no — y aquí se ve que basta `-Mnofma` (no hace falta `-Kieee`) para alinear el `nvfortran`-CPU con `gfortran`, al menos para esta expresión — porque `-Mnofma` desactiva la fusión también en el lado CPU de `nvfortran`.

## Resultado 2: `dcos` SÍ muestra una diferencia real, y es ajena a la FMA

```
=== dcos(x) aislada === (identico con y sin -Mnofma)
  #1  CPU=    0.9950041652780257  GPU=    0.9950041652780258  |err|= 1.11E-16
  #2  CPU=    0.8775825618903726  GPU=    0.8775825618903728  |err|= 1.11E-16
  #3 a #8: |err|=0.00E+00
```
Dos de los ocho valores (`x=0.1` y `x=0.5`) dan un bit distinto entre CPU y GPU en `nvfortran` — y **exactamente el mismo bit distinto**, tanto con `-Mnofma` como sin ella. Esto confirma directamente lo que se explicó en la conversación: esta diferencia **no tiene nada que ver con la fusión FMA** (la flag no la mueve ni un bit) — viene de que la CPU y la GPU calculan `cos(x)` con dos implementaciones de software distintas (la biblioteca de host de `nvfortran` frente a `libdevice` de NVIDIA para la GPU), cada una precisa a su manera, que no tienen por qué redondear exactamente igual.

**El giro interesante al añadir `gfortran`:**
```
caso #1 (x=0.1): nvfortran-CPU=0.9950041652780257   GPU=...258   gfortran=...258
caso #2 (x=0.5): nvfortran-CPU=0.8775825618903726   GPU=...728   gfortran=...728
```
Aquí **`gfortran` coincide con la GPU**, y es el propio backend de CPU de `nvfortran` el que se queda solo, distinto de los otros dos. No hay una "CPU" única de referencia: hay al menos **tres implementaciones distintas** de `cos(x)` en juego (biblioteca de host de `nvfortran`, `libdevice` de GPU, `libm` que usa `gfortran`), y para estos valores concretos dos de ellas coinciden por casualidad y la tercera no — no hay ningún patrón de "la GPU es la rara", puede ser cualquiera de las tres.

`dexp` y `dsin` dieron `0.00E+00` en las tres vías para estos 8 valores — no porque esas funciones sean inmunes al fenómeno, sino porque, igual que con la FMA, estos valores concretos no cayeron en un caso límite de redondeo para esas dos funciones.

## Conclusión

El experimento aislado confirma, con datos y no solo con argumentos, las dos piezas de la explicación por separado:
1. **La fusión FMA es real, pero depende de los datos** (no siempre se manifiesta, y en `nvfortran` afecta tanto al código de CPU como al de GPU generados en la misma compilación — no es un interruptor "solo GPU").
2. **Las funciones transcendentales tienen implementaciones genuinamente distintas** en cada combinación compilador+objetivo, con diferencias de 1 ULP independientes de cualquier flag de FMA — y no hay una única "CPU de referencia": `nvfortran`-CPU, `nvfortran`-GPU y `gfortran` son tres implementaciones distintas de `cos`/`exp`/`sin`, cada una válida por su cuenta.

Ninguna de las dos causas es un error de este proyecto ni de esta GPU en particular — son propiedades del ecosistema de compiladores y bibliotecas matemáticas de coma flotante, reproducibles en cualquier máquina con el mismo software.
