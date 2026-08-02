# Primer kernel: `calpleg` / `calderpleg`

Documentación de [`v1-cuda-desarrollo/calpleg-calderpleg/legendre_gpu.cuf`](../calpleg-calderpleg/legendre_gpu.cuf), el primer trozo de código que corre de verdad en la GPU en este proyecto. Es intencionadamente pequeño: solo porta las dos hojas más profundas del árbol de llamadas de `dmc2` (ver el diagrama de `dmc2`), sin tocar `qmccluster` ni `Makefile.gpu` todavía.

---

## Parte 1 — Implementación

### 1. Las dos versiones "iguales" CPU/GPU: `attributes(host,device)`

[`legendre_gpu.cuf:29`](../calpleg-calderpleg/legendre_gpu.cuf#L29) y [`legendre_gpu.cuf:44`](../calpleg-calderpleg/legendre_gpu.cuf#L44) declaran `calplegd` y `calderplegd`. El cuerpo es matemáticamente **idéntico** al `calpleg`/`calderpleg` de [`mlegendre.f90`](../calpleg-calderpleg/mlegendre.f90) — misma recurrencia, mismas variables, ni una fórmula cambiada. Lo único que cambia es la cabecera:

```fortran
attributes(host,device) subroutine calplegd(l, x, pl)
```

`attributes(host,device)` le dice a `nvfortran`: "compila esta subrutina **dos veces** — una para la CPU (código x86 normal) y otra para la GPU (código PTX/SASS)". Por eso se llaman "iguales": no son dos implementaciones que coincidan por casualidad, son literalmente el mismo texto fuente compilado dos veces para dos arquitecturas distintas. La ventaja práctica: si mañana corriges una fórmula aquí, se corrige a la vez en la versión que usa la CPU y en la que usa la GPU — no hay dos copias que puedan desincronizarse.

Nombré las versiones con sufijo `d` (`calplegd`, `calderplegd`) en vez de reusar `calpleg`/`calderpleg` a propósito: así conviven sin chocar con el módulo `mlegendre` original si algún día ambos se usan en el mismo sitio.

**Aclaración importante: la mitad "host" de `attributes(host,device)` no se usa en este fichero.** Un `grep` de `calplegd`/`calderplegd` en `legendre_gpu.cuf` da solo dos llamadas ([línea 74](../calpleg-calderpleg/legendre_gpu.cuf#L74) y [línea 91](../calpleg-calderpleg/legendre_gpu.cuf#L91)), y las dos están dentro de `k_calpleg`/`k_calderpleg` — es decir, las dos ocurren en contexto de GPU. La referencia de CPU de las pruebas (Parte 2) **no** sale de llamar a `calplegd` en modo host: sale de `mlegendre.f90`, el fichero original, importado aparte. Así que ahora mismo `calplegd`/`calderplegd` podrían haberse declarado solo `attributes(device)` y las pruebas darían exactamente el mismo resultado.

¿Por qué se dejó como `host,device` entonces? Dos razones, ninguna imprescindible para las pruebas actuales:
- Si el día de mañana `calpleg`/`calderpleg` necesitan vivir en un módulo compartido entre una versión de CPU que se sigue manteniendo y los kernels de GPU (como se hizo con `qmccluster` completo al comparar `nvfortran` con `gfortran`), ya estaría preparado sin tocar la cabecera.
- Deja abierta la puerta a una prueba distinta (no escrita todavía): comparar la compilación **host** de `calplegd` contra su propia compilación **device**, para comprobar que `nvfortran` no genera código distinto entre sus dos backends a partir del mismo texto — algo distinto de lo que valida la Parte 2.

Es una capacidad "por si acaso", no una necesidad de este fichero. Se podría simplificar a `attributes(device)` sin perder nada de lo que hoy se comprueba.

### 2. Los dos kernels: `k_calpleg` y `k_calderpleg`

[`legendre_gpu.cuf:65`](../calpleg-calderpleg/legendre_gpu.cuf#L65) y [`legendre_gpu.cuf:80`](../calpleg-calderpleg/legendre_gpu.cuf#L80). Son `attributes(global)`, es decir, el código que la CPU lanza y que se ejecuta en la GPU repartido en hilos. Cada uno hace tres cosas:

1. **Calcula qué hilo es él:**
   ```fortran
   i = (blockIdx%x - 1) * blockDim%x + threadIdx%x
   ```
   Es el sustituto de un `do iwalker=1,n`: en vez de que un bucle visite `i=1,2,3...`, se lanzan `n` hilos a la vez y cada uno se pregunta "¿cuál de los `n` soy yo?".

2. **Reserva su propia zona de trabajo local**: `pl_local` en `k_calpleg`; `pl_local`, `d1_local` y `d2_local` en `k_calderpleg` ([`legendre_gpu.cuf:69`](../calpleg-calderpleg/legendre_gpu.cuf#L69) y [`legendre_gpu.cuf:86`](../calpleg-calderpleg/legendre_gpu.cuf#L86)). Un matiz importante sobre estas variables: físicamente sí residen en la memoria de la GPU (la VRAM), pero **cada hilo tiene la suya propia, privada** — no es un array compartido donde los `n` hilos escriben a la vez. Es exactamente como una variable local dentro de una llamada normal de función: cada llamada (aquí, cada hilo) tiene su propia copia, invisible para las demás. Por eso el tamaño es fijo en tiempo de compilación (`lmax_dev=20`, la misma cota que ya usa `mparametros.f90` para `lxhe4`/`lxhe3`): cada uno de los miles de hilos necesita reservar esa memoria de golpe, y el compilador solo sabe hacerlo si el tamaño es una constante, no un valor que llega en tiempo de ejecución.

3. **Llama a la versión `device` y copia el resultado a la salida real:**
   ```fortran
   call calplegd(l, x(i), pl_local(0:l))
   pl_out(0:l, i) = pl_local(0:l)
   ```
   `pl_out` sí es un array **compartido de verdad** en la GPU (memoria global, pasado como argumento `device` desde el programa principal) — ahí es donde cada hilo `i` escribe su resultado en su propia columna, sin pisar la de los demás.

### 3. El programa: flujo de datos CPU↔GPU

En `program test_legendre` ([`legendre_gpu.cuf:102`](../calpleg-calderpleg/legendre_gpu.cuf#L102)) el flujo es:

1. **Se rellenan las variables normales de CPU** (`x_h`, línea 126) — los datos sintéticos, ver §5.
2. **Se declaran las variables gemelas de GPU** con el atributo `device` (`x_d`, `pl_d`, `d1_d`, `d2_d`, líneas 115-117) — mismo tamaño, mismo tipo, pero viven en la GPU.
3. **Se igualan por asignación** (`x_d = x_h`, línea 128): en CUDA Fortran, asignar una variable `device` desde una normal (o al revés) dispara la copia CPU↔GPU tú solo, sin llamar a ninguna función de copia explícita. Es un `=` normal de Fortran, pero el compilador sabe que uno de los dos lados está en otra memoria física y genera la transferencia por debajo.
4. **Se lanzan los kernels** (`<<<blocks, threads>>>`, líneas 133-134): aquí es donde de verdad se ejecuta el cálculo, en la GPU.
5. **Se copian los resultados de vuelta** (`pl_h = pl_d`, etc., líneas 136-138) — mismo mecanismo que el paso 3, en sentido contrario.
6. **Se compara**, ya en CPU, contra la versión de referencia — ver §6.

### 4. Por qué no hay "doble paralelización" (paralelizar también el bucle interno)

La recurrencia de Legendre (línea 38, y su réplica en 57-59) es:
```fortran
pl(il+1) = ((2.0_r8*il+1.0_r8)*x*pl(il) - il*pl(il-1)) / (il+1.0_r8)
```
Para calcular `pl(il+1)` hace falta ya tener calculados `pl(il)` y `pl(il-1)` — cada paso depende del resultado del paso anterior, como en Fibonacci. Eso es una **dependencia de datos real**, no una limitación de cómo está escrito el código: no existe una forma de calcular `pl(3)` sin haber calculado antes `pl(2)` y `pl(1)`. Repartir ese bucle entre varios hilos no es "difícil", es matemáticamente imposible sin cambiar el algoritmo por otro (existen técnicas de *scan* paralelo o potencias de matrices para recurrencias lineales, pero son mucho más complejas de implementar).

Y, sobre todo, **no compensaría el esfuerzo**: aquí `l` vale como mucho 20 (la cota del código, `lmax`), y en la práctica 4 (`lxhe4` en `in.mcv`). Un bucle de 4 pasos es tan barato que un solo hilo lo ejecuta en un puñado de ciclos de reloj — cualquier mecanismo para paralelizarlo (sincronización entre hilos, reparto de trabajo) costaría más que el propio cálculo. El paralelismo real y rentable de este problema está en los **miles de walkers** (miles de `x` distintos a la vez, un hilo por walker, como hace `k_calpleg`), no en trocear un bucle de un puñado de iteraciones. Es la misma idea que ya comentamos con el generador aleatorio: hay que gastar el paralelismo donde de verdad hay volumen de trabajo independiente, no en cada bucle que "en teoría" se podría repartir.

---

## Parte 2 — Pruebas

### 5. Datos sintéticos (comunes a las dos pruebas)

Tanto la prueba del `.cuf` (§6) como la de `gfortran` (§7) usan exactamente los mismos valores, para que sean comparables entre sí (§8):

```fortran
x_h = (/ -1.0_r8, -0.5_r8, 0.0_r8, 0.3_r8, 0.7_r8, 1.0_r8 /)
```

Seis valores de `x` (el `cth`, coseno de un ángulo — por eso el rango físico válido es `[-1,1]`), pensados a mano, no aleatorios:
- **`x=-1.0` y `x=1.0`**: los polinomios de Legendre tienen valor conocido en los extremos — `P_l(1)=1` para cualquier `l`, `P_l(-1)=(-1)^l`. Son los casos que, si algo estuviera mal en la recurrencia o en los límites del array, más probablemente fallarían primero.
- **`x=0.0`**: otro punto con valores analíticos conocidos y tabulados.
- **`-0.5, 0.3, 0.7`**: valores intermedios "normales", para no probar solo casos especiales.

`l=4` porque es el valor real de `lxhe4` en el `in.mcv` de este proyecto — no es un número inventado, es el caso que de verdad hay que portar.

### 6. Prueba con el `.cuf` (`nvfortran` + GPU)

```bash
nvfortran -cuda mlegendre.f90 legendre_gpu.cuf -o test_legendre
./test_legendre
```

La referencia de CPU sale de `mlegendre.f90`, el fichero original sin tocar, importado con renombrado para no chocar con el módulo `mlegendre_gpu`:
```fortran
use mlegendre, only: calpleg_cpu => calpleg, calderpleg_cpu => calderpleg
```
En vez de teclear a mano los valores esperados de cada `P_l(x)` (tedioso y fácil de equivocarse para `l=4`), el programa calcula la misma cantidad por el camino de siempre (CPU) y la resta contra lo que salió de la GPU. Si la diferencia máxima de los 6 casos es menor que `1.0d-12`, el test dice `PASA`.

**Salida real de la última ejecución**, con los números completos de los dos lados (no solo el error):

```
--- walker 1   x =  -1.0000
  pl   CPU:    1.00000000   -1.00000000    1.00000000   -1.00000000    1.00000000
  pl   GPU:    1.00000000   -1.00000000    1.00000000   -1.00000000    1.00000000
  d1pl CPU:    0.00000000    1.00000000   -3.00000000    6.00000000  -10.00000000
  d1pl GPU:    0.00000000    1.00000000   -3.00000000    6.00000000  -10.00000000
  d2pl CPU:    0.00000000    0.00000000    3.00000000  -15.00000000   45.00000000
  d2pl GPU:    0.00000000    0.00000000    3.00000000  -15.00000000   45.00000000
  max|err|  pl=  0.00E+00   d1pl=  0.00E+00   d2pl=  0.00E+00
```
(y así para los 6 valores de `x`, terminando con `PASA: GPU y CPU coinciden dentro de tolerancia`). Se puede comprobar a ojo el caso analítico `x=-1`: `pl = 1,-1,1,-1,1` es exactamente `P_l(-1)=(-1)^l` para `l=0..4`.

Los tres errores (`pl`, `d1pl`, `d2pl`) dan **cero exacto**, no solo "dentro de tolerancia" — esperable aquí porque toda la recurrencia son sumas, restas, productos y divisiones (`+ - * /`), operaciones que el estándar IEEE-754 obliga a redondear igual en cualquier hardware que lo cumpla. No hay ningún `exp`/`log`/`**` de por medio (a diferencia de lo que vimos al comparar `gfortran` con `nvfortran` en el binario completo de `qmccluster`), así que aquí sí se puede esperar coincidencia bit a bit siempre, no solo "muy parecido".

*Nota: en la primera versión de este test, el error de `d1pl` no se calculaba (solo se imprimía el de `d2pl`, y el veredicto final solo miraba `pl`) — quedaba sin verificar de verdad. Ya está corregido: los tres errores se calculan y los tres cuentan para el `PASA`/`FALLA`.*

### 7. Prueba con `gfortran` (sin GPU)

El test anterior usa `mlegendre.f90` como "verdad", pero ese fichero lo compila `nvfortran` (aunque no tenga nada de CUDA, es el compilador que enlaza `legendre_gpu.cuf`). Cabe una pregunta razonable: ¿y si `nvfortran` calculase `calpleg`/`calderpleg` de forma ligeramente distinta a como los calcularía `gfortran` — el compilador del código sin GPU (`Original/`, `Makefile.serie`)? Ya nos pasó una vez esta sesión (el bug de `ishft` en el generador aleatorio) que dos compiladores no coincidían donde deberían.

Para descartarlo, [`test_legendre_gfortran.f90`](../calpleg-calderpleg/test_legendre_gfortran.f90) repite exactamente los mismos 6 valores de `x` y el mismo `l=4` (§5), pero en un programa sin nada de CUDA, compilado con `gfortran`:
```bash
gfortran mlegendre.f90 test_legendre_gfortran.f90 -o test_legendre_gfortran
./test_legendre_gfortran
```
No se puede meter en el mismo binario que `legendre_gpu.cuf` — un ejecutable no puede mezclar código objeto de `gfortran` y de `nvfortran -cuda` (los ficheros `.mod` de un compilador no los entiende el otro, y el runtime de CUDA solo lo enlaza `nvfortran`) — por eso es un programa y un fichero aparte, que solo calcula la parte de CPU (no hay kernel que lanzar, no hay GPU implicada).

**Salida real de la última ejecución:**

```
--- walker 1   x =  -1.0000
  pl   gfortran:    1.00000000   -1.00000000    1.00000000   -1.00000000    1.00000000
  d1pl gfortran:    0.00000000    1.00000000   -3.00000000    6.00000000  -10.00000000
  d2pl gfortran:    0.00000000    0.00000000    3.00000000  -15.00000000   45.00000000
```
(y así para los 6 valores de `x`). Este programa no compara nada por sí solo — solo imprime; la comparación es el siguiente apartado.

### 8. Comparación entre la prueba del `.cuf` y la de `gfortran`

```bash
diff <(./test_legendre | grep 'CPU:') <(./test_legendre_gfortran | grep 'gfortran:')
```
→ **sin diferencias**.

Esto compara la columna `CPU:` de la prueba GPU (que es `mlegendre.f90` compilado por `nvfortran`) contra la salida de `test_legendre_gfortran` (el mismo `mlegendre.f90`, compilado por `gfortran`). Coinciden dígito a dígito para los 6 valores de `x` y las 5 componentes de `pl`/`d1pl`/`d2pl` de cada uno.

Es el resultado esperable — otra vez, solo hay `+ - * /` de por medio, sin `exp`/`**` — pero ahora está **comprobado en vez de asumido**: el "oráculo" de CPU contra el que se valida la GPU (§6) da los mismos números lo compile quien lo compile. Con el precedente del bug de `ishft` en el generador aleatorio, no bastaba con darlo por hecho.

**Matiz importante, encontrado más tarde (con precisión completa, no solo `f14.8`):** el `diff` de arriba compara a 8 decimales (`f14.8`) — a esa resolución, en efecto "sin diferencias". Pero repitiendo la comparación a precisión completa (`es24.17`, 17 cifras significativas) aparece un residuo minúsculo, invisible a 8 decimales, para los valores de `x` que no son "especiales" (`x=0.3`, `x=0.7`) — ver §9. No contradice lo de arriba (la comparación a `f14.8` sigue siendo cierta a esa resolución), solo la completa: "sin diferencias" solo era cierto hasta donde alcanzaba a ver el formato de impresión usado entonces.

### 9. Dos tablas completas: con y sin flags, GPU-vs-`gfortran` y CPU(`nvfortran`)-vs-GPU

Repitiendo §6/§7 con salida de precisión completa (`es24.17`) y comparando explícitamente con y sin `-Kieee -Mnofma` (`nvfortran`) / `-ffp-contract=off` (`gfortran`):

**Tabla 1 — GPU (`nvfortran`) vs CPU-`gfortran`** (`max|diff|` de las 5 componentes de cada cantidad, por walker):

| walker | `x` | | sin flags | con flags |
|---|---|---|---|---|
| 1 | `-1.0` | `pl`/`d1pl`/`d2pl` | `0.00E+00` | `0.00E+00` |
| 2 | `-0.5` | `pl`/`d1pl`/`d2pl` | `0.00E+00` | `0.00E+00` |
| 3 | `0.0` | `pl`/`d1pl`/`d2pl` | `0.00E+00` | `0.00E+00` |
| 4 | `0.3` | `pl` | `1.39E-17` | `0.00E+00` |
| 4 | `0.3` | `d1pl` | `2.22E-16` | `0.00E+00` |
| 5 | `0.7` | `pl` | `8.33E-17` | `0.00E+00` |
| 5 | `0.7` | `d1pl` | `5.55E-16` | `0.00E+00` |
| 6 | `1.0` | `pl`/`d1pl`/`d2pl` | `0.00E+00` | `0.00E+00` |

(`d2pl` da siempre `0.00E+00`, con y sin flags, en los 6 walkers.)

**Tabla 2 — CPU(`nvfortran`) vs GPU (mismo binario, mismo compilador)**:

| walker | `x` | sin flags | con flags |
|---|---|---|---|
| 1-6 | todos | `0.00E+00` (`pl`, `d1pl`, `d2pl`) | `0.00E+00` (`pl`, `d1pl`, `d2pl`) |

**Por qué:** toda la recurrencia (§1, línea 38) son sumas, restas, productos y divisiones — operaciones que IEEE-754 exige redondear de forma **idéntica** en cualquier hardware conforme, y que además ni siquiera dependen de ninguna librería matemática (a diferencia de `exp`/`sin`/`cos`/`acos`/`pow`, que sí viven en software y pueden implementarse de formas distintas — ver `glibc_math.md` y `He_dihydrogen.md` Parte 5). Por eso la **Tabla 2 da 0.00E+00 siempre**, con y sin flags: la CPU y la GPU de `nvfortran` compilan el mismo texto fuente (`attributes(host,device)`) con las mismas reglas de redondeo básico, sin ninguna librería de por medio que pudiera divergir.

La **Tabla 1** sí muestra un residuo — pero **solo sin flags**, y **solo** para `x=0.3`/`x=0.7` (los dos únicos valores "genéricos", ni `0`, `±1` ni `±0.5`). Es reasociación/FMA de la expresión `(2.0_r8*il+1.0_r8)*x*pl(il) - il*pl(il-1)` (un producto-menos-producto, patrón típico de fusión `a*b-c*d`): sin `-Kieee -Mnofma`, `nvfortran` puede reagrupar o fusionar esa resta de productos de forma distinta a como lo hace `gfortran` por defecto — la misma categoría de diferencia "no de librería, sino de asociatividad/FMA" ya documentada en `ulp_aislado.md` y `gpu_vs_gfortran_arbol.md`. Con `-Kieee -Mnofma` desaparece del todo (`0.00E+00` en las 6 combinaciones). Como la GPU siempre coincide exacta con la CPU de `nvfortran` (Tabla 2), este residuo de la Tabla 1 es, en realidad, un residuo "CPU-`nvfortran`-vs-`gfortran`" heredado sin cambios — no algo que la GPU añada por su cuenta.

### ¿Dónde están las salidas de las pruebas?

En ningún fichero: ambos programas solo hacen `write(*,...)`, que imprime **por la salida estándar (la terminal)**, cada vez que los ejecutas. No se guarda nada en disco a menos que lo redirijas tú mismo, por ejemplo:
```bash
./test_legendre > resultados_calpleg_gpu.txt
./test_legendre_gfortran > resultados_calpleg_gfortran.txt
```
Si en algún momento queréis conservar un historial de estas pruebas unitarias (no las de `qmccluster` completo, que ya usan `scripts/run_test.sh`), habría que decidir un sitio para guardarlas — de momento no existe.
