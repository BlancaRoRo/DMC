# Puerto de `dexp`/`dsin`/`dcos`/`dacos` de glibc 2.39

Documentación de [`v1-cuda-desarrollo/glibc_math/`](../glibc_math/): reimplementación en CUDA Fortran de las funciones transcendentales `exp`/`sin`/`cos` de precisión doble, copiando el algoritmo real de la `glibc` de esta máquina (2.39), en vez de usar las intrínsecas de Fortran (`dexp`/`dsin`/`dcos`).

## Por qué existe esto

En `gpu_vs_gfortran_arbol.md` y `ulp_aislado.md` se estableció que las discrepancias de ULP entre GPU, CPU-`nvfortran` y CPU-`gfortran` no vienen de una única causa: parte es FMA (controlable con flags), pero otra parte es que **CPU-`nvfortran` (`libnvcpumath`), GPU-`nvfortran` (`libdevice`) y `gfortran` (`libm`/glibc) tienen tres implementaciones de software distintas** de `exp`/`cos`/`sin`, cada una válida por su cuenta, sin ninguna flag que las unifique. La única vía real para que la GPU reproduzca *exactamente* lo que da `gfortran` es escribir esas tres funciones nosotros mismos, copiando el algoritmo de la `glibc` real de esta máquina, y usarlas en vez de las intrínsecas — no como aproximación, sino como transcripción fiel, verificada bit a bit.

Este documento cubre el trabajo de base (las tres funciones matemáticas en sí). Su uso dentro de los kernels de física (sustituir `dcos`/`dsin`/`dexp` por `mycos`/`mysin`/`myexp` en `He_dihydrogen`, `V_hehe`/`Vp_hehe`, `wavefx`, etc.) es el siguiente paso, no incluido aquí.

## Fuente

Código real de `glibc 2.39` (la versión instalada en esta máquina, confirmada con `ldd --version`), obtenido de [`sysdeps/ieee754/dbl-64/`](https://sourceware.org/git/?p=glibc.git;a=tree;f=sysdeps/ieee754/dbl-64;hb=glibc-2.39) — comprobado que no hay ningún override específico de `x86_64` para estas tres funciones (`sysdeps/x86_64/fpu/` solo tiene versiones `long double`), así que el código genérico `dbl-64` es exactamente el que se ejecuta en esta máquina. Licencia original: LGPL-2.1-or-later, (C) Free Software Foundation / IBM Accurate Mathematical Library.

| Función | Ficheros fuente |
|---|---|
| `dexp` → `myexp` | `e_exp.c`, `e_exp_data.c`, `math_config.h` |
| `dsin`/`dcos` → `mysin`/`mycos` | `s_sin.c` (`s_cos.c` es un alias del mismo fichero), `sincostab.c`, `usncs.h` |
| rango extremo (`\|x\|>=105414350`) | `branred.c`, `branred.h`, `dla.h` |
| `dacos` → `myacos` | `e_asin.c` (`acos` vive en el mismo fichero que `asin`), `asincos.tbl`, `root.tbl`, `powtwo.tbl`, `uasncs.h` |

---

## Parte 1 — Implementación

## 1. Un obstáculo de compilador antes de empezar: `TRANSFER` no enlaza en `-cuda`

Tanto `exp` como `sin`/`cos` manipulan directamente los bits de un `double` (reinterpretarlo como entero de 64 bits para extraer el exponente, indexar una tabla, etc. — lo que en C se hace con una `union`). En Fortran el equivalente es `TRANSFER`. La primera prueba aislada de esto:
```fortran
attributes(host, device) function real2int(x) result(i)
 real(kind=r8), intent(in) :: x
 integer(kind=8) :: i
 i = transfer(x, 1_8)
end function real2int
```
compila, pero **falla al enlazar** cuando se usa dentro de una función `attributes(host,device)` compilada con `-cuda`:
```
undefined reference to `__pgi_transfer_dbl2long'
```
Comprobado con `nm`/`find` en todo el SDK de `nvidia-hpc` instalado: ese símbolo de runtime no existe en ningún `.a`/`.so` de la instalación — no es un fallo nuestro, es un hueco real de esta versión de `nvfortran` (24.1) para `TRANSFER` escalar de 8 bytes en código dual host/device. Como `PARAMETER`s (constantes en tiempo de compilación) sí funcionan con `TRANSFER` sin problema, el hueco es específico de **valores en tiempo de ejecución**.

**Solución encontrada**: envolver el `TRANSFER` en un array de tamaño 1:
```fortran
attributes(host, device) function bits_of(x) result(ii)
  real(kind=r8), intent (in) :: x
  integer(kind=i8) :: ii
  integer(kind=i8) :: tmp(1)
    tmp = transfer( (/x/), tmp)
    ii = tmp(1)
end function bits_of
```
Esto usa un camino de código distinto en el compilador (la variante array de `TRANSFER`, no la escalar) que sí enlaza y da el resultado correcto, comprobado en host y en device por separado y lanzando un kernel real (`v1-cuda-desarrollo/glibc_math/` conserva las pruebas aisladas que lo confirmaron). Toda la reinterpretación de bits de este port pasa por esta técnica (`bits_of`/`real_of`).

## 2. `ISHFT` en Fortran es lógico, no aritmético — comprobado, no asumido

El algoritmo original usa desplazamientos a la derecha sobre enteros que, bit a bit, pueden tener el bit de signo puesto (representan un patrón de bits sin signo en C, `uint64_t`/`uint32_t`). Se comprobó explícitamente que `ISHFT` en Fortran (tanto `nvfortran` como `gfortran`) es un desplazamiento **lógico** (rellena con ceros) independientemente del signo del entero, igual que el `>>` de C sobre `uint64_t` — no hacía falta ningún truco adicional para las extracciones de exponente/mantisa.

## 3. `myexp`: puerto de `e_exp.c` (algoritmo ARM Optimized Routines, ~0.5 ULP)

Tabla de 256 enteros de 64 bits (`e_exp_data.c`, `N=128`) + 8 constantes escalares + el algoritmo de `__exp`: reduce `x` a `k/N * ln2 + r` con `k` entero (redondeo vía el truco del "número mágico" `1.5*2^52`), busca `2^(k/N)` en la tabla, y aproxima `exp(r)` con un polinomio de grado 5. Incluye la rama `specialcase` para `x` cerca de los límites de overflow/underflow (`|x|` entre ~512 y ~1024), portada entera — se comprobó con `x=±700` que la ejercita.

Todas las constantes (tabla incluida) se transcribieron con un script que parsea el `.c` original y genera literales `Z'...'` de Fortran vía `TRANSFER`, para no copiar 256 números a mano.

## 4. `mysin`/`mycos`: puerto de `s_sin.c` (IBM Accurate Mathematical Library, ~0.55 ULP)

Tabla de 440 `double` (`sincostab.c`, formato *little-endian*: cada valor son dos palabras de 32 bits consecutivas, comprobado comparando contra el bloque `BIG_ENDI` del mismo fichero) + ~15 constantes + cuatro piezas:
- `do_sin`/`do_cos`: seno/coseno de un argumento ya reducido a un rango pequeño, combinando una expansión de Taylor local con la tabla (fórmula de suma de ángulos).
- `reduce_sincos`: reduce `x` a un cuadrante (0-3) más un resto pequeño, válido para `|x| < 105414350`.
- `mysin`/`mycos`: los puntos de entrada, con las mismas ramas por rango de `x` que `__sin`/`__cos` originales.

**Detalle que habría sido un bug si no se hubiera comprobado**: `s_sin.c` tiene sus propias `sn3,sn5,cs2,cs4,cs6` (para el argumento ya reducido), **distintas** de las `s1..s5` de `usncs.h` (para el caso `|x|<0.126`, Taylor puro) — dos aproximaciones distintas para dos rangos distintos, con nombres parecidos pero ni los mismos valores ni el mismo propósito. Las dos se transcribieron por separado.

## 5. `branred.c`: reducción de rango tipo Payne-Hanek para `|x| >= 105414350`

Para argumentos tan grandes que ya no caben en la reducción "barata" de `reduce_sincos`, `glibc` usa una tabla de 75 valores (`toverp[]`, "2/π" en base 2²⁴) y aritmética de precisión extendida (técnica de Dekker: partir un `double` en dos para sumar/multiplicar sin perder precisión) para seguir reduciendo `x` a un cuadrante + resto exacto. Se portó entera (no se dejó fuera de alcance, a diferencia de otras ramas muertas de código de este proyecto): dado que aquí la función SÍ se llama para cualquier `x` real que un usuario le pase, dejarla sin portar habría sido un hueco real, no una rama inalcanzable como el `slaterdet` de `wavef.md`.

**Otro detalle que habría sido un bug real**: `branred.h` declara su **propia** constante `mp2`, con el mismo nombre que la `mp2` de `usncs.h` pero **bits distintos** (`...9740000000` frente a `...973c000000` — difieren en el redondeo del último grupo de bits). En el C original no chocan porque son ficheros `.c` distintos, cada uno con su `static const` de ámbito de fichero; al juntar todo en un único módulo Fortran hacía falta darles nombres distintos (`sc_mp2` vs. `br_mp2`) — se comprobó explícitamente byte a byte con Python en vez de asumir que "total, se llaman igual, deben ser la misma constante".

El bloque que `branred.c` repite dos veces seguidas (una vez para la parte alta de `x` tras partirla, otra para la parte baja) se factorizó en una subrutina (`branred_half`) en vez de duplicar ~25 líneas — sin cambiar ningún cálculo, solo para no copiar y pegar dos veces el mismo bloque.

---

## Parte 2 — Pruebas

## 6. `myexp`: 14 casos, coincidencia exacta

Valores probados: cero, positivos/negativos de magnitud normal, `1e-30` (caso "tan pequeño que `exp(x)≈1+x`"), `±20`, y `±700` (activa `specialcase`, `exp(700)≈10^304`, `exp(-700)≈10^-305`).

```bash
cd v1-cuda-desarrollo/glibc_math
nvfortran -cuda -Kieee -Mnofma glibc_exp.cuf -o test_glibc_exp && ./test_glibc_exp
gfortran -ffp-contract=off test_glibc_exp_gfortran.f90 -o test_glibc_exp_gfortran && ./test_glibc_exp_gfortran
```
**Resultado real**: los 14 casos coinciden dígito a dígito (17 cifras significativas) entre `myexp` CPU, `myexp` GPU, y `dexp` de `gfortran`.
```
 PASA: myexp (CPU y GPU) coincide EXACTO con dexp intrinseca
```

## 7. `mysin`/`mycos`: 23 casos, coincidencia exacta — incluido el rango extremo

Valores probados: cero, el límite `|x|<0.126` de Taylor puro (`0.126` exacto), los límites entre ramas (`0.855469`, `2.426265`), ángulos normales (`π/2`, `π`, valores negativos), y **6 casos que activan `branred`** cruzando el umbral `105414350` (`1.05e8` justo por debajo, `1.06e8` justo por encima, hasta `1e100` y `-1e20`).

```bash
nvfortran -cuda -Kieee -Mnofma glibc_exp_mod.cuf glibc_sincos.cuf test_glibc_sincos.cuf -o test_glibc_sincos
./test_glibc_sincos
gfortran -ffp-contract=off test_glibc_sincos_gfortran.f90 -o test_glibc_sincos_gfortran
./test_glibc_sincos_gfortran
```

**Resultado real, caso interesante** (`x=1e15`, ya en rango `branred`):
```
dcos intrinseca (nvfortran, CPU) = -5.13193737786970194E-01
mycos CPU                        = -5.13193737786970305E-01
mycos GPU                        = -5.13193737786970305E-01
dcos gfortran                    = -5.13193737786970305E-01
```
Aquí `mycos` (CPU y GPU) **no** coincide con la intrínseca de `nvfortran` — pero sí coincide exacto con `gfortran`, que es el objetivo real de este port (no "parecerse a `nvfortran`", sino "reproducir `glibc`"). Confirma, con un caso concreto, que esto no es casualidad: la intrínseca de `nvfortran` es una tercera implementación independiente, y la nuestra reproduce fielmente la de `glibc`, no la de `nvfortran`.

**Resultado agregado** (verificado con script, comparando las 4 columnas — `mysin`/`mycos` × CPU/GPU — contra `gfortran` en los 23 casos):
```
TODOS COINCIDEN EXACTOS con gfortran (incluidos los 6 casos extremos con branred): True
```

## 8. Siguiente paso (hecho parcialmente, ver Parte 3)

Sustituir `dcos`/`dsin`/`dexp` por `mycos`/`mysin`/`myexp` en los kernels ya portados (`He_dihydrogen`, `V_hehe`/`Vp_hehe`, `wavefx`, `wavefhe3`, `wavefm`...) y volver a verificar cada uno GPU-vs-`gfortran` con la nueva convención de flags (`-Kieee -Mnofma` / `-ffp-contract=off`) y la referencia `Original-VapFix`. Hecho para `V_hehe`/`Vp_hehe` (exacto) y `He_dihydrogen` (ver `He_dihydrogen.md`).

## Parte 3 — `myacos`: se añade la cuarta función, encontrada al cerrar `He_dihydrogen`

### 9. Por qué hace falta también `acos`

Durante la investigación de causa raíz del residuo de `ENERGY2`/`ENERGY3` en `He_dihydrogen` (ver `He_dihydrogen.md`, Parte 4), se dio por sentado — porque ningún caso probado hasta entonces lo había mostrado — que `dacos` **no** tenía el problema de las tres implementaciones independientes que sí tenían `exp`/`sin`/`cos`. Un caso real (walker 3, átomo 4 de la prueba de `He_dihydrogen`, `fi=-0.5773502691896258...`) demostró lo contrario: con `ror`, `onorm`, `rnorm` y `fi` bit a bit idénticos entre host y device de `nvfortran`, `dacos(fi)` daba resultados distintos (`...528393` en host, `...528437` en device).

Confirmado con las mismas herramientas que en la Parte 1:
- `nm -D` sobre el binario: el `dacos` de host de `nvfortran` resuelve a `__pd_acos_1@LIBNVCPUMATH_VERSION` (de `libnvcpumath.so`, la librería matemática propia de NVIDIA para CPU).
- `cuobjdump --dump-ptx`: el `dacos` de device no aparece como llamada a ninguna librería — está compilado **en línea** como una larga secuencia de instrucciones PTX (el intrínseco de `libdevice`).
- `gfortran` coincide con el host de `nvfortran` para ese caso concreto, no con el device.

Es exactamente el mismo patrón que `exp`/`sin`/`cos` (tres implementaciones de software independientes, ninguna flag las unifica) — solo que hasta ahora ningún caso de prueba había tocado un ángulo lo bastante "genérico" (no `0`, `π/2` o `π` exactos) para revelarlo.

### 10. `myacos`: puerto de `e_asin.c` (`__ieee754_acos`, IBM Accurate Mathematical Library, ~0.523 ULP)

`acos` vive en el mismo fichero fuente que `asin` en glibc (comparten polinomios y parte de las tablas); solo se porta la mitad de `acos` (`__ieee754_acos`), no `asin`. El algoritmo tiene **8 zonas** según `|x|`, cada una con su propio desarrollo polinómico y su propio trozo de tabla (`asncs.x[n..n+12]`, tabla de 2568 valores `double`, `asincos.tbl`):

| Zona (`\|x\|`) | Método |
|---|---|
| `< 2.78e-17` | devuelve `π/2` directamente |
| `2.78e-17` – `0.125` | Taylor puro (`f1`..`f6`) |
| `0.125` – `0.5`, `0.5`–`0.75`, `0.75`–`0.921875`, `0.921875`–`0.953125`, `0.953125`–`0.96875` | 5 subtramos con tabla (`asncs.x[n]`, distinto polinomio por tramo) |
| `0.96875` – `1` (cerca de la singularidad) | raíz cuadrada por Newton-Raphson con tablas `inroot`/`powtwo` (típico de fdlibm para evitar perder precisión cerca de `acos(±1)`) |
| `= 1` exacto | `0` o `2·(π/2)` |
| `> 1` | `NaN` (`(x-x)/(x-x)`, fuera de dominio) |

Igual que en `mysin`/`mycos`, el `m>0` del C (signo del entero de 32 bits que representa la mitad alta de `x`) se sustituye por comprobar directamente el signo de `x` en Fortran (`x > 0.0_r8`) — válido en todo el rango que alcanzan estas ramas, mismo razonamiento que ya se aplicó y verificó en `glibc_sincos.cuf`. Igual que con `myexp`, el `TRANSFER` escalar se evita reutilizando `bits_of`/`real_of` (ya definidas en `glibc_exp_mod.cuf`, wrapeadas en array de tamaño 1).

Las tablas `inroot` (128 valores) y `powtwo` (28 valores) se copiaron como literales decimales (igual que el resto de constantes de este proyecto — la conversión decimal→binario es determinista y correctamente redondeada en compiladores conformes, así que el texto decimal basta para reproducir el mismo patrón de bits que produce el compilador de `glibc`). La tabla `asncs.x` (2568 valores) se extrajo de los pares hexadecimales de `asincos.tbl` (variante `LITTLE_ENDI`) con un script Python, igual que se hizo para `sincos_tab` en la Parte 1.

### 11. Pruebas: 26 casos, coincidencia exacta — incluidas las 8 zonas y el caso real de `He_dihydrogen`

Valores probados: los bordes exactos (`0`, `±1`), dos valores por cada una de las 8 zonas de tabla (incluida la zona cercana a la singularidad, `0.99`/`-0.999999`), los valores de `fi` reales de `He_dihydrogen` (walkers 1/2/3, todos los átomos) — incluido **el valor exacto que causaba la divergencia** (`fi=-0.5773502691896258`, walker 3 átomo 4).

```bash
nvfortran -cuda -Kieee -Mnofma glibc_exp_mod.cuf glibc_acos.cuf test_glibc_acos.cuf -o test_glibc_acos
./test_glibc_acos
gfortran -ffp-contract=off test_glibc_acos_gfortran.f90 -o test_glibc_acos_gfortran
./test_glibc_acos_gfortran
```

**Resultado en el caso que motivó todo esto** (`x=-5.77350269189625842E-01`):
```
dacos intrinseca (nvfortran, CPU) = 2.18627603546528393E+00
myacos CPU                        = 2.18627603546528393E+00
myacos GPU                        = 2.18627603546528393E+00
dacos gfortran                    = 2.18627603546528393E+00
```
Antes del puerto, `dacos` intrínseca de GPU daba `2.18627603546528437E+00` para esta misma entrada — un valor distinto tanto de `gfortran` como del host de `nvfortran`. Con `myacos`, **las 26 combinaciones (CPU y GPU) coinciden exactas con `gfortran`**, sin ninguna excepción, en las 8 zonas del algoritmo.

```
TODOS COINCIDEN EXACTOS con gfortran (26/26 casos, CPU y GPU): True
```

### 12. Siguiente paso (hecho: ver `angle_scalar_vec.md` §5-6)

Sustituir `dacos` por `myacos` en `angle_scalar_vec_mod.cuf` — hecho, con una batería de 22 casos (8 zonas del algoritmo + extremos cerca de `±1` + magnitudes de `1e-150` a `1e150`), 66/66 exactos con flags. Ver `docs-kernels/angle_scalar_vec.md`.

## Parte 4 — `mypow`: quinta función portada (`pow(x,y)` con exponente real)

### 13. Por qué hacía falta

`rij**nu` (con `nu` real, no entero — un parámetro físico como `9.763290`) aparece en `duhe4x`/`uhe4x` (`d_uhex4.cuf`), `duhe3x`/`uhe3x` (`der_wavefx.cuf`) y `wavefhe4`/`derwavefhe4` (`der_wavefhe4.cuf`) — confirmado con `nm` (`He_dihydrogen.md` Parte 5, §13): el host de `nvfortran` enlaza `__fd_pow_1` ("rápido", sin `-Kieee`) o `__pd_pow_1` ("preciso", con `-Kieee`, y **este coincide con `gfortran`**), y el `pow` de GPU (`libdevice`) es una implementación totalmente independiente de ambos. A diferencia del exponente entero disfrazado de `He_dihydrogen` (`rnorm**6.d0`→`rnorm**6`), aquí el exponente **es genuinamente real** (`nu`), así que no hay forma de esquivar `pow()` reescribiendo el exponente — hace falta portarlo de verdad.

### 14. `mypow`: puerto de `e_pow.c`/`e_pow_log_data.c` (algoritmo ARM Optimized Routines, `log_inline`+`exp_inline`, ~0.54 ULP)

`__pow` de glibc se calcula como `exp(y*log(x))` en precisión extendida: `log_inline` (tabla de 128 entradas, `e_pow_log_data.c`) calcula `log(x)=hi+lo` con ~15 bits extra de precisión; `y*log(x)` se calcula partiendo `y` e `hi` en mitad alta/baja (evitando el error de redondeo de un único producto); y **`exp_inline` reutiliza literalmente las mismas tablas y constantes que `myexp`** (`exp_tab`, `exp_c2`-`exp_c5`, `exp_invln2N`, etc., importadas de `glibc_exp_mod.cuf` sin duplicar nada) — en la propia `glibc`, `__exp` y `__pow` comparten ese motor interno.

Un obstáculo nuevo: el algoritmo necesita un desplazamiento a la derecha **aritmético** (con signo) de 52 bits (`k = (int64_t)tmp >> 52`, para separar el exponente de un patrón de bits). `ISHFT` de Fortran es **lógico** (confirmado ya antes, §2) y, además, **`nvfortran` no reconoce el intrínseco estándar `SHIFTA`** (F2008) — comprobado con un programa suelto: `gfortran` sí lo acepta, `nvfortran` da `NVFORTRAN-S-0038-Symbol, shifta, has not been explicitly declared`. Se implementó a mano (`ashr52`): un desplazamiento aritmético a la derecha por `2^n` equivale matemáticamente a `floor(x/2^n)`; Fortran trunca hacia cero en vez de hacia `-infinito`, así que solo hace falta restar 1 cuando `x` es negativo y la división no es exacta — verificado contra `SHIFTA` de `gfortran` con casos de prueba antes de usarlo.

Se restringe el dominio al uso real del proyecto (`rij` siempre `>0`, `nu` siempre finito y normal) y **no se porta la rama de `x<0`** (lógica de entero par/impar para el signo de raíces impares) — `rij` nunca es negativo, mismo criterio que `aziz_nuevo`/`vatomol` en `vpot.cuf` (código genuinamente inalcanzable en este dominio).

### 15. Pruebas: 30 casos con los exponentes `nu` reales del proyecto, coincidencia exacta

Valores probados: los 4 `nu` reales de `in.mcv` (`9.763290`, `4.725025`, `3.155952`, `11.036848`, más el trivial `1.0`) cruzados con `rij` desde contacto muy cercano (`0.3`, y el `0.866025...` exacto de `der_wavefx.md` que causaba el problema original) hasta largo alcance (`50`), más extremos (`rij=1e-8`/`1e8`, `nu=100`/`0.001`) y un caso con exponente no entero "genérico" (`7.3**0.5`).

```bash
nvfortran -cuda -Kieee -Mnofma glibc_exp_mod.cuf glibc_pow.cuf test_glibc_pow.cuf -o test_glibc_pow
./test_glibc_pow
gfortran -ffp-contract=off test_glibc_pow_gfortran.f90 -o test_glibc_pow_gfortran
./test_glibc_pow_gfortran
```

**Resultado en el caso que motivó todo esto** (`x=0.86602540378443864`, `y=9.763290`, el `rij` real de `der_wavefx.md`):
```
x**y intrinseca (nvfortran, CPU, -Kieee) = 2.45523711823179613E-01
mypow CPU                                = 2.45523711823179613E-01
mypow GPU                                = 2.45523711823179613E-01
x**y gfortran                            = 2.45523711823179613E-01
```
Antes del puerto, `x**y` intrínseca de GPU daba `2.45523711823179641E-01` para esta misma entrada (distinto de `gfortran`). Con `mypow`, **los 30 casos coinciden exactos con `gfortran`, en CPU y GPU, con y sin `-Kieee -Mnofma`** (verificado explícitamente en ambas configuraciones — a diferencia de la intrínseca, `mypow` no depende de ninguna flag porque es código propio, sin ninguna librería externa de por medio):
```
TODOS COINCIDEN EXACTOS con gfortran (30/30 casos, CPU y GPU, con Y sin flags): True
```

### 16. Siguiente paso

Sustituir `rij**pxhe4(2,il)`/`rij**pxhe4(4,il)` (y sus equivalentes He3) por `mypow(rij, pxhe4(2,il))`/`mypow(rij, pxhe4(4,il))` en `d_uhex4.cuf`/`der_wavefx.cuf`, y `rij**phe4(2)` en `der_wavefhe4.cuf` — verificar primero con pruebas simples (mismos casos que ya usa cada kernel), aislar si falla algo (comprobar si es FMA u otra causa antes de asumir), y solo después pasar una batería extrema (misma rigurosidad que `angle_scalar_vec.md` §6).
