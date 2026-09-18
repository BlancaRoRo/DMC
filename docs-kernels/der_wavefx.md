# Séptimo kernel: `wavefx` / `derwavefx`

Documentación de [`v1-cuda-desarrollo/der_wavefx/der_wavefx.cuf`](../der_wavefx/der_wavefx.cuf). Porta el Jastrow impureza-He (con la expansión en polinomios de Legendre) y su derivada, de [`mwavef.f90`](../der_wavefx/mwavef.f90). Reutiliza `duhe4x`/`uhe4x` (ya portados en `d_uhex4.cuf`) y añade `duhe3x`/`uhe3x` (su gemelo para He3, necesario para que el código compile aunque `nhe3=0` haga que nunca se ejecute de verdad en este proyecto).

---

## Parte 1 — Implementación

## 1. Por qué no se tocan los `if` de `impureza`/`impurmol`

`wavefx`/`derwavefx` tienen varios `if(impureza)` / `if(impurmol)`, incluso dentro de bucles. Se planteó si convenía reestructurar el código para reducirlos, y la respuesta es que no, por dos motivos distintos:

**No hay divergencia de warp que evitar.** La divergencia ocurre cuando hilos *del mismo warp* discrepan en qué rama tomar — aquí `impureza` e `impurmol` son **el mismo valor para los 32 hilos de cualquier warp** (una bandera de toda la simulación, fijada una vez al leer `in.mcv`, no algo que varíe por walker como `x < D_HeHe` en `V_hehe`). Con un valor uniforme, todos los hilos de un warp toman siempre la misma rama a la vez — coste de divergencia real: cero.

**Se podría "subir" el `if` a un nivel más alto (decidirlo una vez en el host, antes de lanzar el kernel, o compilar dos variantes), pero no compensa.** El `if` en sí es una única instrucción de predicado compartida por todo el warp — comparado con el coste real de dentro (`exp`, `sqrt`, divisiones, la recurrencia de Legendre de `uhe4x`), es indetectable en cualquier perfilado. Reestructurar para ahorrar esto añadiría una segunda variante de kernel (o una rama en el host) a cambio de nada medible — la misma lógica de "no optimizar a ciegas" que ya se dejó anotada para el `merge()` de `V_hehe` (`V_hehe_Vp_hehe.md`, §4).

## 2. Las variables que hubo que cambiar para poder pasarlas a la GPU

El original recibe el `walker` completo (`w1`) en `wavefx`/`derwavefx`, pero — igual que en `wavefhe4` — `type(walker)` no se puede usar como dato `device` por sus componentes `allocatable` (`atom`, `dwf`, `delta`, `hb2m`, `sigma1`, `sigma2`). Aquí, además de `atom`, entran en juego otras dos piezas de `w1`:

| Campo de `w1` | Tipo | ¿Allocatable? | Qué se hizo |
|---|---|---|---|
| `w1%atom(:)` | `type(vec3), allocatable` | Sí | Se extrae como argumento `atom(natom)` — igual que en `wavefhe4` |
| `w1%sprop(3)` | `type(vec3) :: sprop(3)` — array **fijo**, no `allocatable` | No | `wavefx` solo lee `sprop(3)` (el tercer eje) → se pasa un único `vec3` (`sprop3`). `derwavefx` usa los tres (`sprop(1:3)`) → se pasa el array completo `sprop(3)` |
| `w1%lw%wfx` | `real(kind=r16)`, campo de `type(vloc)` — tampoco `allocatable` | No | Solo se escribe ese campo → se extrae como argumento de salida `wfx` (escalar), igual que `wfhe4` en `wavefhe4` |

El motivo de extraer `sprop3`/`wfx` en vez de pasar `sprop`/`lw` enteros no es que `vec3`/`vloc` tengan el problema de `walker` (no lo tienen, ninguno de los dos es `allocatable`) — es que, al ya estar cambiando la interfaz por culpa de `atom`, tiene sentido reducirla a exactamente lo que se lee y se escribe, en vez de arrastrar tipos completos por comodidad.

Además, se reutilizan directamente `duhe4x`/`uhe4x` y sus variables `device` (`lxhe4`, `pxhe4`, `impurmol`) de [`d_uhex4.cuf`](../d_uhex4.cuf/d_uhex4.cuf), y se añaden `duhe3x`/`uhe3x` con el mismo patrón exacto (mismas fórmulas que `duhe4x`/`uhe4x`, con `lxhe3`/`pxhe3` en vez de `lxhe4`/`pxhe4`) — necesarios porque `derwavefx`/`wavefx` los llaman, aunque con `nhe3=0` en este `in.mcv` esas llamadas caen siempre en un bucle vacío (`do jhe3=1,nhe3`, `do jatom=nhe4+1,ngatom` con `ngatom=nhe4`) y nunca se ejecutan de verdad. El resto de variables de simulación (`nhe4`, `nhe3`, `ngatom`, `natom`, `impureza`) siguen el mismo tratamiento ya visto: `device` a nivel de módulo, rellenadas una vez desde el host.

## 3. Cómo se portaron `duhe3x`/`uhe3x`, y un hueco real que se encontró al probarlos

`derwavefx` llama a `duhe3x` (bucle `do jhe3=1,nhe3`) y `wavefx` llama a `uhe3x` (bucle `do jatom=nhe4+1,ngatom`) — ninguna de las dos existía todavía en ningún sitio portado. Se escribieron **calcando exactamente el patrón de `duhe4x`/`uhe4x`** (mismo cuerpo, mismas fórmulas, cambiando `lxhe4`→`lxhe3` y `pxhe4`→`pxhe3`), y se declararon `lxhe3`/`pxhe3` como `device` a nivel de módulo, mismo tratamiento que el resto de variables de simulación. No hizo falta ninguna importación nueva: `calpleg`/`calderpleg` ya estaban disponibles vía `mlegendre_gpu` (la misma reutilización que usa `duhe4x`).

**El hueco:** con `nhe3=0` en este `in.mcv`, `ngatom=nhe4`, así que los dos bucles que llaman a `duhe3x`/`uhe3x` quedan **vacíos** en tiempo de ejecución — el código compila, pero la primera prueba (§4) nunca llegaba a ejecutarlos de verdad. Es decir: se había comprobado que `duhe3x`/`uhe3x` compilan, no que calculan bien. Se cerró ese hueco añadiendo dos kernels aparte (`k_duhe3x`, `k_uhe3x`, mismo patrón que `k_duhe4x`/`k_uhe4x` en `d_uhex4.cuf`) que las llaman **directamente**, con datos sintéticos, comparando contra `duhe3x`/`uhe3x` de `mwavef.f90` sin tocar — igual que se hizo con `duhe4x`/`uhe4x` en su momento. Los valores de `lxhe3`/`pxhe3` usados son los reales del bloque He3-impureza de `in.mcv` (`b=0.5, nu=0, alfa=1, p4=1, p5=0, lxhe3=0`) — el único término (`l=0`) que ese bloque define, aunque nunca se lea en el resto de la simulación con `nhe3=0`.

## 4. El fallo real: pasar `sprop(3,:)` (una sección con salto) a un kernel

El primer intento de `k_wavefx` recibía `sprop3(n)` como argumento separado, y se lanzaba así:
```fortran
call k_wavefx<<<blocks,threads>>>(n_walk, atom_d, sprop_d(3,:), wfx_d)
```
`sprop_d` es `type(vec3), device :: sprop_d(3,n)` — `sprop_d(3,:)` selecciona la fila 3 (fijando el primer índice, variando el segundo), que en memoria **no es contigua**: entre `sprop_d(3,1)` y `sprop_d(3,2)` hay dos elementos de por medio (`sprop_d(1,2)` y `sprop_d(2,2)`). Esa sección con salto, pasada como argumento de un lanzamiento `<<<...>>>`, provocó un `segmentation fault` en tiempo de ejecución — el kernel recibía un puntero de dispositivo que no apuntaba a donde debía.

**La solución fue no recortar nada en el host**: `k_wavefx` pasa a recibir el array `sprop(3,n)` completo (igual que ya hacía `k_derwavefx`), y selecciona el componente 3 **dentro** del kernel:
```fortran
call wavefx(atom(:,i), sprop(3,i), wfx_out(i))   ! dentro de k_wavefx, con sprop(3,n) completo
```
`sprop(3,i)` aquí es un acceso normal a un elemento (no una sección con salto cruzando el lanzamiento), y funciona sin problema. La lección general: **cualquier recorte de array que no sea contiguo, hecho en el host antes de `<<<...>>>`, es sospechoso** — mejor pasar el array completo y recortar dentro del kernel, donde ya no hay que cruzar la frontera CPU↔GPU.

---

## Parte 2 — Pruebas

## 5. Datos de prueba y resultado

3 walkers de prueba (4 átomos de He4 + 1 impureza), con marcos moleculares `sprop` no ortonormales a propósito (`derwavefx` normaliza cada eje por separado, así que no hace falta que ya vengan normalizados) y, en el walker 3, un caso de contacto cercano a propósito (el átomo 4 y la impureza a ~0.87 bohr) como prueba de estrés numérico.

**Resultado real — GPU + CPU(`nvfortran`)** (recortado; se repite para los 3 walkers):
```
--- walker 1
  wfx CPU=      0.000000000000   GPU=      0.000000000000
  atom 1 d1wf CPU=      3.17980927      2.83192177      0.04882180  d2wf CPU=     -3.20350466
  atom 1 d1wf GPU=      3.17980927      2.83192177      0.04882180  d2wf GPU=     -3.20350466
  ...
  |err| max=  0.00E+00

--- walker 3
  wfx CPU=      0.000000000000   GPU=      0.000000000000
  atom 4 d1wf CPU=   2132.69621145   2132.69621145   2184.81723579  d2wf CPU=****************
  atom 4 d1wf GPU=   2132.69621145   2132.69621145   2184.81723579  d2wf GPU=****************
  ...
  |err| max=  0.00E+00

 PASA: GPU y CPU coinciden dentro de tolerancia
```
Dos cosas que llaman la atención y no son fallos:
- **`wfx=0.0` en los tres walkers**: `ujas` (la suma que va dentro del `exp`) es muy negativa, así que `exp(ujas)` hace *underflow* a cero exacto en `double` — igual en CPU y en GPU, coincide dígito a dígito (`0.0 = 0.0`).
- **`d2wf` mostrado como `****************`** en el walker 3: es el formato de Fortran cuando un número no cabe en el ancho fijo del campo (`f16.8`) — el valor real es enorme (consecuencia del contacto cercano a propósito), pero **coincide exactamente** entre CPU y GPU pese a su magnitud — un buen caso de estrés que sigue dando `|err| max = 0.00E+00`.

**Resultado real — CPU(`gfortran`)** ([`test_derwavefx_gfortran.f90`](../der_wavefx/test_derwavefx_gfortran.f90), mismos 3 walkers):
```
--- walker 1
  wfx gfortran=      0.000000000000
  atom 1 d1wf gfortran=      3.17980927      2.83192177      0.04882180  d2wf gfortran=     -3.20350466
  ...

--- walker 3
  wfx gfortran=      0.000000000000
  atom 4 d1wf gfortran=   2132.69621145   2132.69621145   2184.81723579  d2wf gfortran=****************
  ...
```
Comparando dígito a dígito contra la columna `CPU:` de la prueba con `nvfortran`: **valores idénticos**. Las tres vías coinciden: **GPU = CPU(`nvfortran`) = CPU(`gfortran`)**, incluso en el caso de contacto cercano del walker 3.

## 6. Prueba directa de `duhe3x`/`uhe3x` (cerrando el hueco del §3)

3 vectores `rivec` sintéticos, con el marco molecular `smol` sin rotar y los valores reales de `in.mcv` para el bloque He3-impureza (`lxhe3=0`, `pxhe3(:,0)` con `b=0.5, nu=0, alfa=1, p4=1, p5=0`) — esta vez llamando a `duhe3x`/`uhe3x` **directamente** (`k_duhe3x`/`k_uhe3x`), no a través de `wavefx`/`derwavefx` (que con `nhe3=0` nunca llegan a ellas).

**Resultado real — GPU + CPU(`nvfortran`)**:
```
=== prueba directa de duhe3x/uhe3x (nhe3=0 no las ejercita arriba) ===

--- rivec3 1
  d1ux%comp CPU=     -1.00000000      0.00000000      0.00000000
  d1ux%comp GPU=     -1.00000000      0.00000000      0.00000000
  d2ux  CPU=     -0.66666667   GPU=     -0.66666667
  uhe3x CPU=     -3.50000000   GPU=     -3.50000000

--- rivec3 2
  d1ux%comp CPU=      0.00000000     -0.97014250     -0.24253563
  d1ux%comp GPU=      0.00000000     -0.97014250     -0.24253563
  d2ux  CPU=     -0.48507125   GPU=     -0.48507125
  uhe3x CPU=     -4.62310563   GPU=     -4.62310563

--- rivec3 3
  d1ux%comp CPU=     -0.60057081      0.45042811     -0.66062789
  d1ux%comp GPU=     -0.60057081      0.45042811     -0.66062789
  d2ux  CPU=     -0.60057081   GPU=     -0.60057081
  uhe3x CPU=     -3.83016516   GPU=     -3.83016516
  |err| max duhe3x/uhe3x =  4.44E-16

 PASA: GPU y CPU coinciden dentro de tolerancia
```
`4.44E-16` es ruido de coma flotante de la familia ya vista en `V_hehe`/`angle` (del orden de la precisión de `double`), no un error — sigue muy por debajo de la tolerancia (`1.0d-9`).

También se comprobó con `gfortran` (mismo bloque añadido a [`test_derwavefx_gfortran.f90`](../der_wavefx/test_derwavefx_gfortran.f90)): **valores idénticos** a la columna CPU de arriba, confirmado con `diff`. Las tres vías coinciden también aquí: **GPU ≈ CPU(`nvfortran`) = CPU(`gfortran`)**.

## 7. `mypow` + secuencializar `d1ux`/`d2ux`: el mismo cierre que en `d_uhex4.md`

`duhe3x`/`uhe3x` tienen **la misma estructura exacta** que `duhe4x`/`uhe4x` (con `pxhe3` en vez de `pxhe4`), así que se les aplicaron los dos mismos cambios, verificados por separado (ver `d_uhex4.md` §5 para el detalle de por qué hacen falta los dos, no solo uno):

**a) `rij**pxhe3(2,il)`/`rij**pxhe3(4,il)` → `mypow(rij,pxhe3(2,il))`/`mypow(rij,pxhe3(4,il))`** en `duhe3x` y en `uhe3x` (3 sitios en total) — mismo motivo que `d_uhex4.md`: exponente real (`nu`/`p4` de `in.mcv`), `pow()` con implementaciones independientes en host/GPU (`glibc_math.md` Parte 4).

**b) Secuenciar la acumulación de `d1ux%comp`/`d2ux` dentro del bucle `do il=0,lxhe3`:**
```fortran
! antes (una sola sentencia, 2 y 3 terminos respectivamente):
d1ux%comp=d1ux%comp+pl(il)*grul%comp+ulx*grpl%comp
d2ux=d2ux+pl(il)*ulxs+ulx*lapl+2.0_r8*dot_product(grul%comp,grpl%comp)

! despues (cada sumando en su propia sentencia):
d1ux%comp=d1ux%comp+pl(il)*grul%comp
d1ux%comp=d1ux%comp+ulx*grpl%comp
d2ux=d2ux+pl(il)*ulxs
d2ux=d2ux+ulx*lapl
d2ux=d2ux+2.0_r8*dot_product(grul%comp,grpl%comp)
```
Sin esto, incluso con `mypow` ya integrada, `nvfortran` y `gfortran` pueden reagrupar la suma de los 2-3 términos de forma distinta y dar el último bit diferente — la misma reasociación ya documentada en `He_dihydrogen.md` Parte 4 y en `d_uhex4.md` §5.

## 8. Batería extrema: contacto muy cercano, largo alcance, y los 3 ángulos "especiales"

Se añaden 5 `rivec3` más a los 3 originales (mismos valores que en `d_uhex4.md` §6, reutilizados para que ambos kernels — He4 y He3 — se prueben con la misma geometría): contacto muy cercano (`(0.1,0,0)`), largo alcance (`(0,0,1000)`), y `cth=+1,-1,0` exactos.

**Resultado — GPU vs CPU-`gfortran`, 8 `rivec3` × 4 cantidades (`d1ux` ×3, `d2ux`) = 32 comparaciones:**
```
rivec3 1: EXACTO   rivec3 2: EXACTO   rivec3 3: EXACTO   rivec3 4: EXACTO
rivec3 5: EXACTO   rivec3 6: EXACTO   rivec3 7: EXACTO   rivec3 8: EXACTO
```
**32/32 exactas**, incluidos los 5 casos extremos (contacto cercano, largo alcance, bordes de dominio de `calpleg`). El residuo `4.44E-16` de la prueba original (§6, GPU-vs-CPU-`nvfortran`) **desaparece del todo** tras `mypow`+la secuencialización: el mismo test (ahora con 8 casos) da `|err| max duhe3x/uhe3x = 0.00E+00` — GPU y CPU(`nvfortran`) coinciden exactos entre sí, y ambos coinciden exactos con `gfortran`, en los 8 casos.

## 9. `wavefx`/`derwavefx`: revisión de `exp`, la fórmula `ul=` de `uhe4x`/`uhe3x`, y `dot_product` en `derwavefx`

Al revisar `wavefx`/`derwavefx` con el mismo criterio aplicado al resto del árbol (`wavef.md` §10), aparecen tres puntos:

**a) `wfx=exp(ujas)` (línea 152 de `wavefx`): corregido, `wfx=myexp(ujas)`.** Mismo `exp()` intrínseco sin `myexp`, mismo riesgo de partición fast/precise (`__fd_exp_1`/`__pd_exp_1`) ya confirmado en `wavefm`/`wavefhe3` (`wavef.md` §10) — con el agravante de que aquí `impureza=.true.` es la configuración **real** de producción, no un caso de prueba aislado como `nhe3=2`. Se añade `use glibc_exp_mod, only: myexp` al módulo `der_wavefx`. Resultado tras el cambio (ver §10 para la batería completa): exacto en las 3 vías con `-Kieee -Mnofma`.

**b) `ul=` en `uhe4x`/`uhe3x` (3 términos en una sola sentencia): revisado, no hace falta ningún cambio.** Es la misma familia de patrón que obligó a secuenciar `d1ux`/`d2ux` en `duhe4x`/`duhe3x` (§7), así que se sospechaba que pudiera necesitar lo mismo. Dos comprobaciones:

- **Comparación de `uhe3x` a `es24.17`** (8 casos ya existentes en `test_derwavefx.cuf`/`test_derwavefx_gfortran.f90`, incluidos los extremos de §8): sin flags, 1 de 8 casos (`rivec3 3`, geometría normal, no un extremo) muestra una diferencia de 1-2 ULP entre `nvfortran` (CPU y GPU **coinciden entre sí**) y `gfortran` — **cierra del todo con `-Kieee -Mnofma`** (0/8 diferencias). Es el patrón habitual de FMA suelto, no el de reasociación-a-través-de-iteraciones que sí persistía con flags en `d_uhex4` (rivec4).
- **Prueba aislada dedicada**: se calculó `ul` de dos formas — la actual (`ul = -p1/mypow(rij,p2) - p3*mypow(rij,p4) - p5*log(rij)`, un término) y una versión secuenciada a mano (3 sentencias separadas) — para 5 valores de `rij` (incluidos contacto muy cercano `0.1` y largo alcance `1000`) con los `pxhe4(:,0)` reales del proyecto. **Resultado: `ul_single` y `ul_seq` dan el bit exactamente igual en los 5 casos, en CPU y GPU, con y sin flags** — secuenciar no cambia nada. A diferencia de `d1ux%comp=d1ux%comp+A+B` (que SÍ reasocia, porque son sumas de aportaciones de iteraciones sucesivas del bucle `il`), `ul=A-B-C` es una expresión autocontenida que se evalúa igual sea cual sea el orden de escritura — no hay ningún acumulador de por medio. Conclusión: **no hace falta tocar `ul=`.**

**c) `dot_product` en `derwavefx` (líneas `d2wf(iatom)=d2wf(iatom)+dot_product(d1wf(iatom)%comp,d1wf(iatom)%comp)` y el equivalente para `d2zwf`): revisado, no hace falta ningún cambio de código.** Prueba: los 3 walkers reales de `test_derwavefx.cuf`/`_gfortran.f90` (config real, `impureza=.true.`), comparando `d2wf`/`d2zwf` a `es24.17` en las tres vías:

- **Sin flags**: residuos reales, hasta `5.59E-09` (walker 3, `d2wf` de magnitud `~1.4E7` — o sea, unas pocas ULP relativas) entre GPU/CPU-`nvfortran` (coinciden entre sí) y `gfortran`.
- **Con `-Kieee -Mnofma`**: cierra por completo en walkers 2 y 3. En el walker 1, queda un residuo minúsculo (`~3.5E-15`, 1-2 ULP) pero esta vez **entre CPU-`nvfortran`(host) y GPU-`nvfortran`(device)** — ya no hay divergencia frente a `gfortran` (GPU y `gfortran` coinciden exactos; solo el host con flags se separa por 1-2 ULP del device). Es la misma categoría ya documentada y aceptada en `He_dihydrogen.md` (Parte 4/5) y en `der_wavefhe4.md` §6 (walker 2): una divergencia de contexto host/device-codegen que ningún flag cierra, y que no depende de si el `dot_product` se sustituye por sumas manuales — es el mismo suelo de precisión de todo el árbol, no un defecto de `dot_product` en sí. No se propone ningún cambio.

**Resumen**: de los tres puntos revisados, se corrige `exp(ujas)`→`myexp(ujas)`; `ul=` y `dot_product` se verifican seguros tal como están, sin ningún cambio de código.

## 10. Batería extrema de `wfx`/`derwavefx`: contacto muy cercano y largo alcance impureza-He4

Se añaden 2 walkers a los 3 ya existentes en `test_derwavefx.cuf`/`test_derwavefx_gfortran.f90` (config real, `impureza=.true.`), y una línea `HP wfx` (`es24.17`, antes solo `f20.12` — que redondeaba los 3 walkers originales a `0.000000000000`, aunque en realidad no lo eran: ver la nota de abajo):

- **Walker 4** (extremo): impureza a contacto muy cercano de un átomo de He4 (`rij≈0.05`). `ujas` se dispara muy negativo (del orden de `-10^14`), `wfx=myexp(ujas)` satura a `0.0` exacto por subdesbordamiento — se comprueba que el suelo es idéntico en las 3 vías.
- **Walker 5** (extremo): impureza a largo alcance de los 4 átomos de He4 (`rij≈1000` en los 4 casos). A diferencia de lo que cabría esperar, `ujas` **no** tiende a 0 con la distancia — los términos `-alfaxhe4(il)*rij**p4xhe4(il)` (exponente `p4xhe4>0`) y `-p5xhe4(il)*log(rij)` **crecen** en valor absoluto con `rij`, así que `ujas→-∞` tanto en contacto cercano como en largo alcance (el mínimo de `|ujas|` está en `rij≈2`, no en los extremos). Con `rij≈1000`, `ujas≈-382`, dando `wfx≈1.5E-166` — un valor de cola representable (no subdesborda), bueno para probar precisión real en vez de un simple `0.0`.

**Resultado (`es24.17`), GPU / CPU-`nvfortran` / `gfortran`:**

| walker | `wfx` | con flags | sin flags |
|---|---|---|---|
| 1 (normal) | `1.41824280010969048E-29` | exacto en las 3 vías | exacto en las 3 vías |
| 2 (normal) | `5.46692014266719004E-30` | exacto en las 3 vías | CPU/gfortran/GPU con 1 ULP de diferencia entre sí |
| 3 (normal) | `2.74239461748270962E-178` | exacto en las 3 vías | ídem, 1 ULP |
| 4 (contacto cercano) | `0.00000000000000000E+00` | exacto en las 3 vías | exacto en las 3 vías |
| 5 (largo alcance) | `1.50360957203982149E-166` | exacto en las 3 vías | **exacto en las 3 vías, incluso sin flags** |

Los dos extremos nuevos no introducen ningún residuo nuevo — el walker 4 (subdesbordamiento) y el walker 5 (cola representable) son exactos en las tres vías con y sin flags; los únicos residuos (walkers 2/3, ~1 ULP sin flags) son el patrón de FMA habitual, ya cerrado con `-Kieee -Mnofma`, y preexistente al cambio de `exp`→`myexp` (no lo introduce).

**`|err| max` global de `test_derwavefx` con flags**: `3.55E-15` (walker 1, viene de `dot_product` en `derwavefx`, ver punto (c) de §9 — no de `wfx`) — el resto de walkers, incluidos los 2 nuevos, dan `0.00E+00`. Sin flags, `FALLA: diferencia maxima = 5.59E-09` — mismo valor exacto que antes de tocar `exp`, confirmando que el residuo viene de `dot_product`/`d2wf` (§9c), no del cambio de esta sección.

**Nota**: los 3 walkers originales nunca habían mostrado su valor real de `wfx` — la única salida era `f20.12`, que redondea cualquier `wfx<5E-13` a `0.000000000000` (los 3 walkers están entre `1E-29` y `1E-178`). Al añadir `es24.17` se descubre que la prueba llevaba toda la sesión comparando dos ceros redondeados sin decir nada sobre si `exp()`/`myexp()` coincidían de verdad — el mismo patrón de "enmascaramiento por precisión" ya visto en otros kernels (`angle_scalar_vec.md`, `d_uhex4.md`...).
