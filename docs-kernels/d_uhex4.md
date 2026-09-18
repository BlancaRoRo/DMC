# Quinto kernel: `duhe4x` / `uhe4x`

Documentación de [`v1-cuda-desarrollo/d_uhex4.cuf/d_uhex4.cuf`](../d_uhex4.cuf/d_uhex4.cuf). Porta `duhe4x` y `uhe4x` de [`mangwavef.f90`](../d_uhex4.cuf/mangwavef.f90) — las derivadas y el valor del término angular impureza-He4 que usa `wavefx`/`derwavefx` (ver el diagrama de `dmc2`). Es el primer kernel de los que llevamos que recibe **tipos de datos derivados** (`type(vec3)`) en vez de solo escalares o arrays de reales, y el primero que depende de **variables de simulación** (no constantes) declaradas en otro módulo (`mparametros.f90`).

---

## Parte 1 — Implementación

## 1. Dos categorías de "variables ajenas" muy distintas

Ya nos habíamos encontrado con variables que vienen de fuera de la subrutina, pero hasta ahora siempre eran del mismo tipo: constantes de compilación. Aquí aparece la otra categoría, y merece la pena dejar las dos por escrito una al lado de la otra porque **se tratan de forma completamente distinta**:

| | Constantes de compilación (`param_atoms_bh.h`, en `V_hehe`/`Vp_hehe`) | Variables de simulación (`lxhe4`, `impurmol`, `pxhe4`, aquí) |
|---|---|---|
| Cómo se declaran en el original | `PARAMETER` dentro de un `INCLUDE` | Variables normales `public` en `mparametros.f90` (sin `parameter`) |
| ¿Cuándo se fija su valor? | En tiempo de **compilación** — el número está en el propio texto fuente | En tiempo de **ejecución** — `mentradatos.f90` las rellena una vez, al leer `in.mcv` |
| ¿Hace falta copiarlas a la GPU? | **No.** El compilador sustituye el valor directamente en el código máquina, tanto en host como en device | **Sí.** Son datos reales que solo existen en la memoria del proceso una vez arrancado el programa; hay que llevarlas a la GPU explícitamente |
| Cómo se resuelve en este proyecto | `include 'param_atoms_bh_freeform.h'` dentro de la función (ver `V_hehe_Vp_hehe.md` §2-3) | Variables `device` a nivel de **módulo**, con una asignación explícita desde el host antes de lanzar el kernel (§2 de este documento) |

En **este fichero concreto no se usa ninguna constante de compilación** (`duhe4x`/`uhe4x` no tocan `param_atoms_bh.h` para nada) — pero queda documentado aquí porque es el contraste que explica por qué `lxhe4`/`impurmol`/`pxhe4` necesitan un tratamiento que las constantes de `V_hehe` no necesitaban.

## 2. Por qué `lxhe4`, `impurmol` y `pxhe4` son variables `device` a nivel de módulo

En `mparametros.f90`, estas tres son variables `public` **sin** `parameter`:
```fortran
integer(kind=i4), public :: lxhe4,lxhe3          ! no es 'parameter'
logical :: impureza,impurmol                      ! tampoco
real(kind=r8), public :: pxhe4(5,0:lmax), ...      ! tampoco
```
`mentradatos.f90` las rellena **una sola vez**, al arrancar, leyendo `in.mcv` — y a partir de ahí se quedan fijas durante toda la simulación, pero siguen siendo variables de verdad, no texto sustituido en tiempo de compilación.

La razón de declararlas como `device` **a nivel de módulo** (líneas 15-17 de [`d_uhex4.cuf`](../d_uhex4.cuf/d_uhex4.cuf)) y no como argumento de cada kernel es que **son el mismo valor para los miles de walkers a la vez** — no varían por hilo, como sí varía `r` en `calpleg` o `rivec` aquí mismo. Pasarlas como argumento en cada llamada a `k_duhe4x`/`k_uhe4x` funcionaría, pero sería repetir en cada lanzamiento un dato que nunca cambia durante la simulación; declararlas a nivel de módulo imita exactamente la arquitectura del original (`mangwavef.f90` las lee vía `use mparametros`, sin que aparezcan en ninguna lista de argumentos de `duhe4x`/`uhe4x`).

Antes de dar esto por bueno se comprobó de forma aislada (fuera de este fichero) que una variable `device` de módulo se puede leer **tanto desde la compilación `host` como desde la `device`** de una subrutina `attributes(host,device)`, sin necesitar una copia dentro de la propia función — el compilador se encarga de la transferencia por debajo. Con eso confirmado, se declararon con el **mismo nombre** que usa el cuerpo original (`lxhe4`, `impurmol`, `pxhe4`), así que el cuerpo de `duhe4x`/`uhe4x` no tuvo que cambiar ni una línea por este motivo.

En el `program` de prueba, se rellenan una vez antes de lanzar los kernels:
```fortran
lxhe4 = 4
impurmol = .true.
do il = 0, 4
  pxhe4(1,il) = 0.50_r8*(bxhe4(il)**nuxhe4(il))   ! misma formula que mentradatos.f90
  ...
enddo
```
con los valores **reales** de `lxhe4`/`b`/`nu`/`alfa`/`p4`/`p5` de este `in.mcv`, calculando `pxhe4` con la misma fórmula que usa `mentradatos.f90` en vez de teclear el resultado ya multiplicado a mano (mismo criterio que en los kernels anteriores: cuantos menos números se retranscriban a mano, menos ocasión de error).

## 3. La llamada a `mtipos` (`vec3`) y a `calpleg`/`calderpleg`

**`use mtipos, only: vec3`**: se reutiliza la definición real del tipo, sin retipearla. Esto funciona en código `device` porque `duhe4x`/`uhe4x` **nunca operan sobre un `vec3` entero** — siempre acceden a `%comp` (el `real(kind=r8) :: comp(3)` de dentro) y hacen aritmética normal de arrays. Esto importa porque `mtipos.f90` define operadores sobrecargados (`+`, `-`, `=`) para `vec3` (`interface operator(+)`, `interface assignment(=)`...), y esos procedimientos son **solo de host** (sin ningún `attributes`) — si el código hubiera escrito `grz = smol(3) - rivec` (el `vec3` entero, disparando el operador `-` sobrecargado) en vez de `grz%comp = smol(3)%comp - rivec%comp`, habría fallado en GPU con el mismo error que ya vimos con `V_hehe`/`Vp_hehe` ("Calls from device code to a host subroutine/function are not allowed"). De hecho, se encontró y corrigió exactamente un sitio donde faltaba el `%comp`:
```diff
- grz=0.0_r8
+ grz%comp=0.0_r8
```
(en la rama `else` de `impurmol` — una asignación de un escalar a un `vec3` entero, que solo funciona a través del operador `assignment(=)` sobrecargado de `mtipos.f90`, que es de host).

**`use mlegendre_gpu, only: calpleg => calplegd, calderpleg => calderplegd, lmax_dev`**: en vez de volver a escribir `calpleg`/`calderpleg` en este fichero, se reutilizan directamente las versiones ya portadas y probadas en [`calpleg-calderpleg/legendre_gpu.cuf`](../calpleg-calderpleg/legendre_gpu.cuf) (copiadas a este directorio como `mlegendre_gpu.cuf`, sin el `program` de prueba de aquel test, solo el módulo). Se renombran al importar (`calpleg => calplegd`) para que el cuerpo de `duhe4x`/`uhe4x` — que llama a `calderpleg`/`calpleg` con esos nombres, igual que el original — no tenga que cambiar nada. Es la primera vez que un kernel de este proyecto se construye reutilizando *otro* kernel ya hecho, en vez de partir de cero — exactamente la idea de ir subiendo el árbol de llamadas de abajo hacia arriba.

Un efecto colateral de reutilizar `calpleg`/`calderpleg` así: `pl(0:lxhe4)`, `d1pl(0:lxhe4)` y `d2pl(0:lxhe4)` eran arrays locales de tamaño variable en tiempo de ejecución (ahora que `lxhe4` es una variable `device`, no una constante) — el mismo problema que ya resolvimos en `calpleg`. Se corrigió igual: buffer local de tamaño fijo `pl(0:lmax_dev)`, pasando el trozo `pl(0:lxhe4)` a `calderpleg`/`calpleg`.

---

## Parte 2 — Pruebas

## 4. Datos de prueba y resultado

4 vectores `rivec` (posición relativa He4-impureza, en bohr) con un marco molecular `smol` sin rotar (ejes cartesianos estándar), y `lxhe4=4`/`pxhe4` con los valores reales de `in.mcv` (§2). La referencia de CPU es `mangwavef.f90` sin tocar — al ser un módulo de verdad (a diferencia de `bh_heh2m.f`), se importa con `use mangwavef, only: duhe4x_cpu => duhe4x, uhe4x_cpu => uhe4x`, sin necesitar `external`.

**Resultado real de la ejecución** (`nvfortran -cuda mtipos.o mparametros.o mlegendre.o mangwavef.o mlegendre_gpu.o d_uhex4.cuf -o test_duhe4x && ./test_duhe4x`):
```
--- rivec 1
  d1ux%comp CPU=   -3.738351443394    0.000000000000    0.000000000000
  d1ux%comp GPU=   -3.738351443394    0.000000000000    0.000000000000
  d2ux  CPU=   -2.043206770393   GPU=   -2.043206770393
  uhe4x CPU=  -16.505170549889   GPU=  -16.505170549889
  |err| max=  0.00E+00

--- rivec 2
  d1ux%comp CPU=    0.000000000000   -3.174528901222    0.000000000000
  d1ux%comp GPU=    0.000000000000   -3.174528901222    0.000000000000
  d2ux  CPU=   -1.005503375009   GPU=   -1.005503375009
  uhe4x CPU=  -19.977239830616   GPU=  -19.977239830616
  |err| max=  0.00E+00

--- rivec 3
  d1ux%comp CPU=   -1.612976030816   -1.612976030816   -2.278199656314
  d1ux%comp GPU=   -1.612976030816   -1.612976030816   -2.278199656314
  d2ux  CPU=   -0.827686631158   GPU=   -0.827686631158
  uhe4x CPU=  -20.298389279965   GPU=  -20.298389279965
  |err| max=  0.00E+00

--- rivec 4
  d1ux%comp CPU=    1.102556953779   -1.837594922965    2.222675679538
  d1ux%comp GPU=    1.102556953779   -1.837594922965    2.222675679538
  d2ux  CPU=   -0.742622398764   GPU=   -0.742622398764
  uhe4x CPU=  -20.940989657112   GPU=  -20.940989657112
  |err| max=  0.00E+00

 PASA: GPU y CPU coinciden dentro de tolerancia
```
**Cero de diferencia exacto en los 4 casos** — a diferencia de `Vp_hehe` y `angle`, aquí no ha aparecido ningún resto de 1 ULP con las flags por defecto (sin `-Kieee` ni `-Mnofma`). No hay ninguna garantía de que eso se mantenga siempre (son operaciones parecidas: sumas, productos, un `log` en vez de `exp`/`dacos`), pero para los 4 casos de prueba, con la precisión mostrada, no ha hecho falta ninguna flag especial.

**Corrección posterior — esa comprobación se hizo con `f18.12` (12 decimales), no a precisión completa.** Con `es24.17` (17 cifras significativas) sí apareció un residuo real: `rij**pxhe4(2,il)` (línea 75 del original) usa un exponente **real** (`pxhe4(2,il)`, el `nu` de `in.mcv` — `9.763290`, `4.725025`... no enteros), lo que obliga a Fortran a usar `pow(x,y)` — y `pow()`, igual que `dacos`, tiene implementaciones independientes en host (`__fd_pow_1`/`__pd_pow_1` según `-Kieee`) y en GPU (`libdevice`), sin garantía de coincidir con `gfortran` (ver `He_dihydrogen.md` Parte 5, `glibc_math.md` Parte 4). Para `rivec 4` concretamente, la GPU (con `dacos`/`pow` intrínsecas) daba `d2ux=-7.42622398763958413E-01`, mientras que `gfortran` daba `-7.42622398763958302E-01` — distintos en el último dígito, invisibles a `f18.12` pero reales a `es24.17`.

## 5. El cierre real: `mypow` + secuenciar la acumulación de `d2ux`/`d1ux`

Dos cambios, verificados por separado:

1. **`rij**pxhe4(2,il)`/`rij**pxhe4(4,il)` → `mypow(rij,pxhe4(2,il))`/`mypow(rij,pxhe4(4,il))`** (`glibc_pow.cuf`, puerto de `__pow` de glibc 2.39 — ver `glibc_math.md` Parte 4, verificado en aislado con 30 casos exactos). Esto por sí solo **no bastó** para `rivec 4`: seguía dando `d2ux` distinto de `gfortran`, aunque ahora coincidiendo con el `pow` "preciso" del host (`-Kieee`) — la causa real no era `pow()`, sino la acumulación de `d2ux` en el bucle.
2. **`d2ux=d2ux+pl(il)*ulxs+ulx*lapl+2.0_r8*dot_product(...)`** (una suma de 3 términos en una sola sentencia) se parte en tres sentencias secuenciales (`d2ux=d2ux+pl(il)*ulxs`; `d2ux=d2ux+ulx*lapl`; `d2ux=d2ux+2.0_r8*dot_product(...)`) — misma técnica que en `He_dihydrogen.md` Parte 4. `d1ux%comp` se secuencia igual, por consistencia (no mostraba residuo, pero tampoco hacía falta que fuera una excepción).

Con los dos cambios, `rivec 4` pasa a coincidir exacto GPU-vs-`gfortran` (aunque aparece un residuo nuevo, minúsculo, entre el host y el device de `nvfortran` — `1.11E-16` — el mismo patrón ya documentado en `He_dihydrogen.md` Parte 4: los dos backends de `nvfortran` pueden reasociar distinto incluso con código secuencial idéntico. No afecta al objetivo real, que es coincidir con `gfortran`).

## 6. Batería extrema: contacto muy cercano, largo alcance, y los 3 ángulos "especiales" de `calpleg`

Se añaden 5 `rivec` más a los 4 originales: contacto muy cercano (`rivec=(0.1,0,0)`), largo alcance (`rivec=(0,0,1000)`), y los tres casos donde `cth` (coseno respecto al eje `smol(3)`) vale exactamente `+1`, `-1` y `0` — los bordes de dominio del polinomio de Legendre.

**Resultado — GPU vs CPU-`gfortran`, 9 `rivec` × 8 cantidades (`d1ux` ×3, `d2ux`, `d1zux` ×2, `d2zux`, `uhe4x`) = 72 comparaciones:**
```
rivec 1: EXACTO   rivec 2: EXACTO   rivec 3: EXACTO   rivec 4: EXACTO   rivec 5: EXACTO
rivec 6: EXACTO   rivec 7: EXACTO   rivec 8: EXACTO   rivec 9: EXACTO
```
**72/72 exactas**, incluidos los 5 casos extremos y los 3 bordes de dominio de `calpleg`. Ningún caso necesitó ninguna precaución especial más allá de `mypow` + la secuencialización ya aplicada.
