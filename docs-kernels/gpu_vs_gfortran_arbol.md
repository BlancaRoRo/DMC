# GPU vs. `gfortran`, en todo el árbol: ¿el mismo margen de error, o ninguno?

Este documento nace de una pregunta directa tras la prueba aislada de `ulp_aislado.md`: en `dcos`, la GPU coincidía con `gfortran` y era `nvfortran`-CPU quien se quedaba solo. ¿Pasa lo mismo en los kernels reales del proyecto? Todos los `test_*.cuf` ya comparaban **GPU contra CPU(`nvfortran`)** (con `|err|` calculado sobre los `double` reales, sin pasar por texto) y por separado imprimían la columna `gfortran` — pero nunca se había calculado explícitamente **GPU contra `gfortran`** ni se había mirado con suficiente precisión impresa.

## Aviso metodológico importante: la precisión impresa mentía por omisión

Los `write` de casi todos los tests usan formatos como `f18.10` (10 decimales) o `es16.8` (8 cifras significativas). Un `double` tiene ~15-17 cifras significativas — así que una diferencia real de `1e-13` o `1e-15` **no aparece en el texto impreso**, aunque el propio programa la calcule correctamente puertas adentro (el `|err|` sí se computa sobre los `double` en memoria, no sobre el texto). Por eso una primera pasada comparando texto impreso daba `0.0` en kernels donde sí había una discrepancia real de fondo.

**Corrección aplicada**: se añadieron líneas `write` adicionales con formato `es24.17` (suficientes cifras para representar un `double` sin pérdida) en los `test_*` de los kernels donde ya se sabía que había ULPs — sin quitar ni modificar ninguna línea existente, así que la salida ya documentada en cada `.md` sigue siendo válida tal cual. Se recompiló cada test tres veces (GPU+CPU-`nvfortran`, y CPU-`gfortran`) y se comparó con la precisión completa.

## Metodología, de hoja a raíz

Se recorre el árbol de kernels en el mismo orden en que se fueron portando (de las funciones sin dependencias hacia `vpot`), calculando en cada uno **tres distancias por pareja**: `|CPU(nvfortran) − GPU|`, `|CPU(nvfortran) − gfortran|`, `|GPU − gfortran|`.

### Hojas sin ninguna discrepancia detectada (ni siquiera a precisión completa)

| Kernel | CPU-GPU (ya conocido) | GPU vs. `gfortran` |
|---|---|---|
| `calpleg`/`calderpleg` | `0.00E+00` | `0.0` exacto (90 valores comparados) |
| `angle_scalar_vec` | `0.00E+00` | `0.0` exacto (15 valores comparados) |
| `wavefhe4`/`derwavefhe4` | `0.00E+00` | `0.0` exacto (51 valores comparados) |

Estos tres son aritmética pura (recurrencias polinómicas, productos escalares, sumas) sin ninguna función transcendental encadenada más de una vez — coherente con lo que ya se vio en la prueba aislada (`dexp` solo, sin nada alrededor, tampoco mostró diferencia con los valores probados).

### El resto del árbol: SÍ hay discrepancias reales a precisión completa, y no siguen un patrón fijo

Contando las filas con discrepancia no nula de la Tabla 1 (más abajo): en 9 de ellas CPU(`nvfortran`) y GPU coinciden exactamente y es `gfortran` quien se queda solo; en 2 coinciden GPU y `gfortran` (CPU el raro); en 2 coinciden CPU y `gfortran` (GPU el raro); y en al menos 1 (`He_dihydrogen`, walker 2, `ENERGY2`) **los tres difieren entre sí**. No hay un "raro" consistente — son tres implementaciones numéricas independientes (ver más abajo, "¿Se pueden cambiar de verdad esas bibliotecas?").

## Tabla 1 — sin flags de coma flotante

Por cada discrepancia: dónde está (kernel, función/expresión concreta), a qué se debe, y las tres distancias por pareja. "Mixta" significa que la expresión combina varias funciones transcendentales (`dcos`+`dsin`+`dexp` en la misma fórmula) y no se ha diseccionado variable a variable cuál es la responsable exacta — solo se ha hecho esa disección para `Vp_hehe` (única vez que hizo falta, ver `V_hehe_Vp_hehe.md` §9).

| Kernel | Dónde (función/expresión) | Causa | CPU-GPU | CPU-`gfortran` | GPU-`gfortran` |
|---|---|---|---|---|---|
| `calpleg`/`calderpleg` | — (recurrencia polinómica pura) | — (sin discrepancia) | `0.0` | `0.0` | `0.0` |
| `angle_scalar_vec` | — (`dot_product` + `dacos`) | — (sin discrepancia) | `0.0` | `0.0` | `0.0` |
| `wavefhe4`/`derwavefhe4` | — (`rij**p` + `dexp`) | — (sin discrepancia) | `0.0` | `0.0` | `0.0` |
| `V_hehe` (par 1, `r=2.0`) | término "add-in", `dsin(Ba·(x-xx1)-pi12)` | **`dsin`** | `0.00e+00` | `2.17e-19` | `2.17e-19` |
| `Vp_hehe` (par 1, `r=2.0`) | `Vbp = A·(...)·dexp(...)` (FMA en la multiplicación) | **FMA** | `1.73e-18` | `1.73e-18` | `0.00e+00` |
| `Vp_hehe` (par 2/3, dentro ventana) | `Vap = Aa·Ba·dcos(Ba·(x-xx1)-pi12)` | **`dcos`** | `0.00e+00` | `~5e-21` | `~5e-21` |
| `Vp_hehe` (par 1/4/5, fuera ventana) | `Vap` sin inicializar en el original | **bug `Vap`** | `1.73e-18` (por casualidad pequeño) | ver Tabla 2 (crece mucho con `-Kieee`) | — |
| `duhe3x`/`uhe3x` (rivec 1) | `dot_product` interno (sin ninguna trascendente) | **FMA** | `4.44e-16` | `0.00e+00` | `4.44e-16` |
| `duhe3x`/`uhe3x` (rivec 3) | `dot_product` interno | **FMA** | `0.00e+00` | `4.44e-16` | `4.44e-16` |
| `He_dihydrogen` (`ENERGY1/2/3`, varios walkers) | `atheta`/`btheta`/`c6theta` y sus derivadas (`F0..F6`,`DF0..DF6`, todas con `dcos`/`dsin`/`dexp` mezclados) | **mixta** (`dcos`+`dsin`+`dexp`) | `0.00e+00` a `1.42e-13` | `2.22e-16` a `1.35e-13` | `4.44e-16` a `8.53e-14` |
| `He_dihydrogen` (walker 3, `GTEST=T`, `V(1:4)`) | `Vp_hehe`/`Vap` del `bh_heh2m.f` **interno** (no el módulo corregido) | **bug `Vap`** | `NaN` vs. finito | finito ≠ CPU ≠ GPU | — |
| `potenbh` (3 walkers) | hereda de `He_dihydrogen` | **mixta** | `0.00e+00` a `1.42e-13` | `3.55e-15` a `4.26e-14` | `3.55e-15` a `9.95e-14` |
| `vpot` (3 walkers) | hereda de `ccuerpo`(exacto)+`potenbh` | **mixta** | `0.00e+00` a `4.55e-13` | `3.55e-15` a `2.27e-13` | `0.00e+00` a `2.27e-13` |

## Tabla 2 — con `-Kieee -Mnofma`

| Kernel | Dónde | Causa | Sin flags (recordatorio) | Con flags |
|---|---|---|---|---|
| `Vp_hehe` (par 1, fuera ventana) | `Vap` sin inicializar | **bug `Vap`** | `1.73e-18` (CPU-GPU) | **`2.86e-09`** con `-Kieee` (CPU-GPU) — `-Mnofma` sola sí da `0.00e+00` |
| `Vp_hehe` (par 2, dentro ventana) | `Vap` real, `dcos` | **`dcos`** | `0.00e+00` (CPU-GPU) | `0.00e+00` — sin cambio, `-Kieee` no toca esto |
| `He_dihydrogen` (`ENERGY1/2/3`, todos los walkers) | mixta (`dcos`/`dsin`/`dexp`) | **mixta** | máx. `1.42e-13` (CPU-GPU) | máx. `7.11e-15` (CPU-GPU) — mejora un orden de magnitud, no llega a cero |
| `vpot` (walker 2) | mixta | **mixta** | `0.00e+00` (CPU-GPU, sin flags) | `1.42e-14` con `-Kieee -Mnofma` — **empeora** frente a sin flags |
| `vpot` (walker 3) | mixta | **mixta** | `4.55e-13` (CPU-GPU) | `3.41e-13` con `-Mnofma` sola o combinada — mejora, no llega a cero |

**Lectura de la Tabla 2:** las flags tienen dos efectos completamente distintos según la fila. Para el **bug de `Vap`** (memoria sin inicializar), `-Kieee` no "arregla" nada — cambia la reutilización de pila/registros y hace que la basura que cae en esa variable sea mucho más grande que antes; es un efecto secundario de las flags sobre un bug real, no una propiedad numérica. Para las discrepancias **mixtas** (`dcos`/`dsin`/`dexp`/FMA genuinos), las flags reducen la magnitud en general pero de forma **no monótona** — a veces mejoran, a veces empeoran una fila concreta, porque cambian el redondeo de docenas de operaciones encadenadas a la vez, no de una causa aislada y controlable.

## ¿Se pueden cambiar de verdad esas bibliotecas?

Comprobado con `ldd`/`objdump`, no solo argumentado:

```
nvfortran (binario de CPU):  libnvcpumath.so (NVIDIA, propia)  +  libm.so.6 (glibc)
gfortran  (binario de CPU):  libm.so.6 (glibc) únicamente
```

`libnvcpumath.so` exporta sus **propias** implementaciones de `cos`/`sin`/`exp` con nombres internos como `__fd_exp_2m`, `__fs_cos_8_mn`, `__fsz_exp_vex`, `__fvscos_gh` (variantes escalares y vectorizadas para AVX2/AVX-512/FMA4) — `nvfortran` genera código que llama a estos símbolos propios, no a los de `glibc`, aunque `libm.so.6` también esté enlazado (como respaldo para lo que `libnvcpumath` no cubra). Esto es la confirmación definitiva de algo que hasta ahora solo se había argumentado: **no son "CPU vs. GPU", son tres implementaciones matemáticas independientes** — `libnvcpumath` (host de `nvfortran`), `libdevice` (GPU de `nvfortran`) y `libm`/glibc (`gfortran`) — cada una con su propio código para `cos`/`sin`/`exp`, ninguna de las tres derivada de las otras dos.

**¿Se puede forzar a que usen la misma?** No mediante ningún flag de compilación (no existe un `-Kmath=glibc` ni equivalente en `nvfortran`, ni forma de enlazar código x86 de `glibc` dentro de un kernel de GPU — son arquitecturas de instrucciones distintas). La única vía real seguiría siendo la ya comentada: escribir a mano una implementación propia de `cos`/`sin`/`exp` como función `attributes(host,device)`, y sustituir las llamadas a las intrínsecas en los puntos concretos donde importe. Pero no las tres bibliotecas son igual de accesibles para eso:

- **`libm`/`glibc` (la de `gfortran`): sí es viable.** Su código es público (licencia LGPL), y sus funciones derivan históricamente de `fdlibm` (Sun Microsystems, licencia mucho más permisiva, pensada explícitamente para copiarse y modificarse). Se podría transliterar ese algoritmo (reducción de rango + polinomio minimax) a Fortran `attributes(host,device)` — mismo tipo de trabajo de port que el resto de este proyecto, aplicado a una función matemática en vez de a física.
- **`libnvcpumath`/`libdevice` (las de NVIDIA): no.** Son bibliotecas cerradas, sin código fuente publicado — lo único accesible es el binario ya compilado (los símbolos `__fd_exp_2m`, etc., vistos arriba con `objdump`). Reconstruir el algoritmo a partir de ensamblador optimizado con SIMD sería ingeniería inversa: laborioso, de fiabilidad dudosa, y probablemente contrario a la licencia de uso del SDK.

**Y aun portando `fdlibm` perfectamente, no se "unifican" las tres** — se añade una **cuarta** implementación que coincide con `gfortran` por construcción, pero seguiría sin garantizar coincidencia con `nvfortran`-CPU (`libnvcpumath`, no copiable) ni con la GPU si en algún punto se siguiera llamando a la intrínseca nativa en vez de a la versión portada. Sería una vía genuinamente efectiva si el objetivo fuera "la GPU debe reproducir exactamente la referencia de `gfortran`" — pero, como con las flags, el residuo (`1e-9` a `1e-21` según el caso, y el `1e-9` gordo es enteramente el bug de `Vap`, no las bibliotecas) sigue muy por debajo del ruido estadístico de cualquier DMC real como para justificar el esfuerzo.
