# Noveno kernel: `wavef` (con `wavefhe3`/`wavefm`)

Documentación de [`v1-cuda-desarrollo/wavef/wavef.cuf`](../wavef/wavef.cuf). Porta `wavef` de [`mwavef.f90`](../wavef/mwavef.f90): la función de onda total del sistema, producto de sus cuatro componentes (`wfhe4`, `wfhe3`, `wfm`, `wfx`). De paso porta también `wavefhe3` y `wavefm`, dos de esas cuatro componentes que aún no estaban en GPU.

---

## Parte 1 — Implementación

## 1. Qué se porta entero y qué no, y por qué

`wavef` llama incondicionalmente a `wavefhe4`, `wavefhe3`, `wavefm`, `wavefx` — a diferencia de `vpot` (que con `opot=4` corta con un `return` y deja código muerto de verdad), aquí no hay ningún `if` que salte ninguna de las cuatro llamadas. Con `nhe3=0` fijo en esta simulación (`in.mcv`), los bucles internos de `wavefhe3`/`wavefm` que recorren átomos de He3 tienen 0 iteraciones y dan siempre el mismo resultado trivial (`wfhe3=1.0`, `wfm=1.0`) — pero **se llaman siempre**, así que no es código muerto como `aziz_nuevo`/`vatomol`/`azizgen` en `vpot`: hay que portarlas.

Dentro de `wavefhe3` hay, sin embargo, una pieza que sí es código muerto de verdad: `slaterdet` (la antisimetrización de fermiones He3) entra siempre por `if(npart.le.1) then slater=1.0; return endif`, porque con `nhe3=0` los contadores `nhe3up`/`nhe3dw` (fermiones de cada espín) son siempre 0. La rama que construye la matriz y llama a `det()` (determinante NxN de `mlineal.f90`, con pivotaje parcial y un array local de tamaño variable) no se ejecuta nunca — y portarla sería un trabajo de bastante más entidad (algebra lineal genérica en GPU) para una rama sin ningún efecto en esta simulación. Criterio aplicado:

| Pieza | Coste de portar | Se ejecuta con `nhe3=0` | Decisión |
|---|---|---|---|
| `wavefm` | bajo (bucle simple, sin arrays de tamaño variable) | sí (con 0 iteraciones) | portada entera |
| `wavefhe3` (parte Jastrow + `rb`) | bajo (mismo patrón, buffer de tamaño fijo) | sí (con 0 iteraciones) | portada entera |
| `slaterdet` rama `npart>1` (matriz + `det()`) | alto (determinante genérico en device) | **nunca** | no portada, documentada como código muerto |

## 2. `wavefm`: sin cambios de fondo (en su momento)

Mismo patrón que `wavefhe4`/`duhe4x`: doble bucle sin ningún array de tamaño variable. Único cambio: `w1%atom(iatom)-w1%atom(jatom)` (operador `-` sobrecargado de `vec3`, solo host — ver `ccuerpo.md` §2) se sustituye por la resta componente a componente:

**Corrección posterior:** `rij**pmix(2)` sí necesitó `mypow` (exponente real, mismo motivo que en `d_uhex4.cuf`/`der_wavefhe4.cuf`) — verificado con `nhe3=2` (incluido contacto muy cercano y largo alcance), 75/75 exacto contra `gfortran`. Ver `derananum.md` §7 (`derwavefm`, que necesitó el mismo cambio, vive allí).

**Segunda corrección:** `wfm = exp(ujas)` se cambió a `wfm = myexp(ujas)`. No había ningún contraejemplo conocido para este `exp()` en concreto — la duda surgió al notar que `wavefm`/`wavefhe3` eran los únicos dos sitios del árbol que seguían llamando al `exp()` intrínseco en vez de a `myexp` (que sí se usa en `wavefhe4`/`wavefx`/`V_hehe`). Comprobado con `nm` sobre el objeto compilado: el `exp()` de nvfortran tiene **la misma partición fast/precise** que ya se había confirmado para `acos`/`pow` (`__fd_exp_1` sin flags, `__pd_exp_1` con `-Kieee`) — mismo riesgo estructural, aunque en los 3 `ujas` reales de `test_wavefm` (normal, contacto muy cercano, largo alcance) no llegara a manifestarse (ver §10). Se cambia de todas formas para no depender de que ningún valor futuro de `ujas` caiga en la zona donde sí diverge.
```fortran
attributes(host, device) subroutine wavefm(atom, wfm)
  type(vec3), intent (in)  :: atom(ngatom)
  real(kind=r8), intent (out) :: wfm
  ...
    do iatom = 1, nhe4
      do jatom = nhe4+1, ngatom
        rtemp%comp = atom(iatom)%comp - atom(jatom)%comp
        ...
```

## 3. `getcm`: necesaria para `wavefhe3`, sin cambios de fondo

`wavefhe3` empieza calculando el centro de masas del sistema (`getcm`). Se porta igual, recibiendo `atom(natom)` en vez de `w1`:
```fortran
attributes(host, device) subroutine getcm(atom, rcm)
  type(vec3), intent (in) :: atom(natom)
  real(kind=r8), intent (out) :: rcm(3)
  ...
```
Necesita `mhe4`, `mhe3`, `mx` (masas: variables reales de `mparametros.f90`, mismo tratamiento `device` que `phe4`/`pmix`).

## 4. `slaterdet_trivial`: la rama recortada

```fortran
attributes(host, device) subroutine slaterdet_trivial(npart, slater)
  integer(kind=i4), intent (in) :: npart
  real(kind=r8), intent (out) :: slater
    slater = 1.0_r8
end subroutine slaterdet_trivial
```
Solo implementa la rama `npart<=1` del original — la única alcanzable con `nhe3up=nhe3dw=0`. **Si algún día `nhe3up` o `nhe3dw` superaran 1**, esta rutina dejaría de ser válida (devolvería `1.0` en vez del determinante real) y habría que portar la matriz + `det()` de `mlineal.f90` de verdad. Se documenta aquí para que quede constancia de la limitación.

Efecto colateral de recortar `slaterdet`: el original también calcula `w1%lw%signoup`/`signodw` (el signo del determinante, para detectar cruces de nodo fermiónico) — con la rama recortada el signo es siempre `+1`, así que **no se devuelven** en esta versión. Si se implementara el determinante completo, habría que añadirlos de vuelta.

## 5. `wavefhe3`: parte Jastrow portada entera, buffer `rb` de tamaño fijo

```fortran
attributes(host, device) subroutine wavefhe3(atom, wfhe3)
  type(vec3), intent (in) :: atom(natom)
  real(kind=r8), intent (out) :: wfhe3
  ...
  real(kind=r8) :: rb(3, 2*nfermax)
  ...
    call getcm(atom, rcm)
    do iatom = nhe4+1, ngatom
      ...
      rb(:,ihe3) = atom(iatom)%comp - rcm(:)
    enddo
    ! ... doble bucle pairwise (Jastrow He3-He3 + correccion de rb) ...
    call slaterdet_trivial(nhe3up, slaterup)
    call slaterdet_trivial(nhe3dw, slaterdw)
    wfhe3 = myexp(ujas) * slaterup * slaterdw
end subroutine wavefhe3
```
`rb(3,nhe3)` era, en el original, un array local dimensionado con `nhe3` (variable en tiempo de ejecución) — el mismo problema de siempre en código `device`. Solución: un buffer de tamaño fijo `rb(3, 2*nfermax)`, reutilizando `nfermax=20` (`PARAMETER` real ya existente en `mparametros.f90`, el mismo límite que usa `slaterdet` en el original para su propia matriz — no se inventa ninguna constante nueva). Con `nhe3<=2*nfermax=40` (holgado para cualquier caso realista), el buffer siempre alcanza.

**Corrección posterior:** igual que en `wavefm` (§2), `exp(ujas)` → `myexp(ujas)`. Además, `rij**phe3(2)` (línea justo antes; exponente real de `mparametros.f90`, mismo motivo que `pmix(2)` en `wavefm`) → `mypow(rij,phe3(2))` — corregido también, ver §10. `phe3(4)/rij**3` (línea siguiente) **también se corrigió**, a `rij*rij*rij` (no a `mypow`) — ver §10 para la evidencia: el supuesto de que "exponente entero literal = sin riesgo" era **falso**.

## 6. `wavef`: `w1` se descompone igual que en `wavefx`/`wavefhe4`

```fortran
attributes(host, device) subroutine wavef(atom, sprop3, wf)
  type(vec3), intent (in) :: atom(natom)
  type(vec3), intent (in) :: sprop3
  real(kind=r8), intent (out) :: wf
  real(kind=r8) :: wfhe4, wfhe3, wfm, wfx

    call wavefhe4(atom(1:nhe4), wfhe4)
    call wavefhe3(atom, wfhe3)
    call wavefm(atom(1:ngatom), wfm)
    call wavefx(atom, sprop3, wfx)

    wf = wfhe4*wfhe3*wfm*wfx
end subroutine wavef
```
`atom(1:nhe4)` y `atom(1:ngatom)` son secciones contiguas (el primer tramo de un array 1D) — a diferencia de `sprop_d(3,:)` (ver §7), son válidas para pasarlas directas a una llamada `device`. Devuelve `wf` como escalar en vez de escribir en `w1%lw%wf`; `wfhe4`/`wfhe3`/`wfm`/`wfx` no se exponen por separado (si algún consumidor futuro los necesitara sueltos, es un cambio trivial de la interfaz).

## 7. Ensamblado de módulos y el bug de `sprop_d(3,:)`, otra vez

`wavef` necesita `wavefhe4` (módulo `der_wavefhe4`) y `wavefx` (módulo `der_wavefx`, que a su vez usa `d_uhex4` y `mlegendre_gpu`). Como esos ficheros ya incluyen su propio `program test_X` (siguiendo la convención de un solo fichero por kernel, ver `ccuerpo.md`), no se pueden `use` directamente sin duplicar el programa principal — se copian versiones **solo-módulo** (`der_wavefhe4_mod.cuf`, `der_wavefx_mod.cuf`, más `d_uhex4_mod.cuf`/`mlegendre_gpu.cuf`, ya solo-módulo de antes) a `wavef/`, igual que se hizo con `mVheheVphehe_mod.cuf`/`angle_scalar_vec_mod.cuf` para `He_dihydrogen`.

El módulo propio se llama `mwavef_gpu`, no `mwavef`: el original ya define `module mwavef`, y dos módulos con el mismo nombre generarían el mismo `mwavef.mod` y chocarían — mismo problema de fondo que `He_dihydrogen`/`ccuerpo`, esta vez a nivel de módulo entero en vez de una subrutina suelta.

En el kernel `k_wavef`, el borrador inicial pasaba `sprop_d(3,:)` en la llamada (una sección **no contigua**, fijando el primer índice y dejando libre el segundo) — el mismo bug que causó un segfault en `der_wavefx` (documentado allí). Se corrigió pasando el array `sprop` completo y el kernel indexa `sprop(3,i)` por dentro:
```fortran
attributes(global) subroutine k_wavef(n, atom, sprop, wf)
  type(vec3), device, intent (in)  :: atom(natom,n), sprop(3,n)
  ...
    call wavef(atom(:,i), sprop(3,i), wf(i))
```

---

## Parte 2 — Pruebas

## 8. Dos pruebas distintas, por la misma razón que con `duhe3x`/`uhe3x`

Igual que en `der_wavefx` (`duhe3x`/`uhe3x` nunca se ejercitan con `nhe3=0`, así que se les añadió una prueba directa aparte), aquí hacen falta dos pruebas:

1. **El caso real de la simulación** (`nhe4=4`, `nhe3=0`): ejercita `wavef` completo (las cuatro llamadas), pero `wavefhe3`/`wavefm` solo dan su resultado trivial.
2. **Prueba directa de `wavefhe3`/`wavefm`** con `nhe3=2` (`nhe3up=1`, `nhe3dw=1`, dentro del rango que `slaterdet_trivial` sigue cubriendo): dos kernels aparte, `k_wavefhe3`/`k_wavefm`, para que sus bucles pairwise iteren de verdad y se compare un resultado no trivial.

### Cómo ejecutarlo

Desde `v1-cuda-desarrollo/wavef/`:
```bash
# 1) GPU + CPU(nvfortran) en el mismo binario
rm -f *.mod *.o
nvfortran -cuda -c mtipos.f90 mparametros.f90 mlegendre.f90 mangwavef.f90 mvaziz.f90
nvfortran -cuda -c modlegendre.f mhh_heocs.f90 kpcoef.f mkp_heco.f90 pw_heocs.f bh_heh2m.f
nvfortran -cuda -c mvmolecula.f90 mrotaciones.f90 mlineal.f90 msistref.f90 mwavef.f90
nvfortran -cuda -c mlegendre_gpu.cuf d_uhex4_mod.cuf der_wavefx_mod.cuf der_wavefhe4_mod.cuf
nvfortran -cuda -c wavef.cuf
nvfortran -cuda mtipos.o mparametros.o mlegendre.o mangwavef.o mvaziz.o modlegendre.o \
  mhh_heocs.o kpcoef.o mkp_heco.o pw_heocs.o bh_heh2m.o mvmolecula.o mrotaciones.o mlineal.o \
  msistref.o mwavef.o mlegendre_gpu.o d_uhex4_mod.o der_wavefx_mod.o der_wavefhe4_mod.o \
  wavef.o -o test_wavef -llapack -lblas
./test_wavef

# 2) Solo CPU, con gfortran
rm -f *.mod *.o
gfortran -c mtipos.f90 mparametros.f90 mlegendre.f90 mangwavef.f90 mvaziz.f90
gfortran -ffixed-line-length-132 -c modlegendre.f mhh_heocs.f90 kpcoef.f mkp_heco.f90 pw_heocs.f bh_heh2m.f
gfortran -c mvmolecula.f90 mrotaciones.f90 mlineal.f90 msistref.f90 mwavef.f90
gfortran mtipos.o mparametros.o mlegendre.o mangwavef.o mvaziz.o modlegendre.o mhh_heocs.o \
  kpcoef.o mkp_heco.o pw_heocs.o bh_heh2m.o mvmolecula.o mrotaciones.o mlineal.o msistref.o \
  mwavef.o test_wavef_gfortran.f90 -o test_wavef_gfortran -llapack -lblas
./test_wavef_gfortran
```

**Resultado real — 1) GPU + CPU(`nvfortran`)**:
```
 === caso real de la simulacion: nhe3=0 ===

--- walker 1
  wf CPU=      0.000000000000   GPU=      0.000000000000
  |err| max=  0.00E+00

--- walker 2
  wf CPU=      0.000000000000   GPU=      0.000000000000
  |err| max=  0.00E+00

--- walker 3
  wf CPU=      0.000000000000   GPU=      0.000000000000
  |err| max=  0.00E+00

 === prueba directa de wavefhe3/wavefm, nhe3=2 ===
  wfhe3 CPU=      0.136300456199   GPU=      0.136300456199
  wfm   CPU=      0.000015360881   GPU=      0.000015360881
  |err| max=  0.00E+00

 PASA: GPU y CPU coinciden dentro de tolerancia
```
**`wf=0.0` en los tres walkers no es un fallo**: ya se documentó en `der_wavefx.md` que, con estas mismas posiciones sintéticas y los parámetros reales de `pxhe4`, `wfx` hace *underflow* a cero exacto en `double` (`ujas` muy negativo dentro del `exp`). Como `wf=wfhe4*wfhe3*wfm*wfx`, hereda el mismo cero — y, como allí, **coincide exactamente** entre CPU y GPU, que es lo que de verdad se está comprobando. La prueba directa de `wavefhe3`/`wavefm` con `nhe3=2` sí da valores no triviales y también coincide exacta.

**Resultado real — 2) solo CPU, con `gfortran`**:
```
 === caso real de la simulacion: nhe3=0 ===

--- walker 1
  wf gfortran=      0.000000000000

--- walker 2
  wf gfortran=      0.000000000000

--- walker 3
  wf gfortran=      0.000000000000

 === prueba directa de wavefhe3/wavefm, nhe3=2 ===
  wfhe3 gfortran=      0.136300456199
  wfm   gfortran=      0.000015360881
```
Idéntico a la columna `CPU:`/`GPU:` de la prueba 1, incluido el `0.0` por underflow. Las tres vías coinciden: **GPU = CPU(`nvfortran`) = CPU(`gfortran`)**.

## 9. `getcm`: verificado aparte, con `nhe4=20` real y magnitudes extremas

`getcm` (§ implementación, usada por `wavefhe3` para el centro de masas) solo tiene sumas de **un** término por sentencia (`rcm=rcm+masa*atom(iatom)%comp`, dentro de un `do`) — en apariencia ya "segura" frente a reasociación, sin el patrón de varios sumandos en una sola línea que sí daba problemas en otros sitios (`He_dihydrogen`, `d_uhex4`). Se verificó en vez de asumirlo: [`test_getcm.cuf`](../wavef/test_getcm.cuf) usa `nhe4=20` (el valor **real** de la simulación, no 4 como en el resto de pruebas de este árbol, para que la suma tenga tantos términos como en producción) y 3 casos, incluidos dos extremos:

- **Caso 1**: posiciones "normales".
- **Caso 2** (extremo): posiciones con signos alternos y magnitud `~10^8`, para forzar cancelación fuerte en la suma corrida.
- **Caso 3** (extremo): todas las posiciones `~10^-150` (cerca del suelo de los normales de `double`).

**Resultado — con `-Kieee -Mnofma`/`-ffp-contract=off`**: **`0.00E+00` en los 3 casos**, en las tres vías (GPU, CPU-`nvfortran`, `gfortran`) — comprobado con [`test_getcm_gfortran.f90`](../wavef/test_getcm_gfortran.f90).

**Sin flags**, sí aparece un residuo real (no solo en teoría) para los casos con más cancelación:
```
caso 1: GPU=...213594E+00   gfortran=...213683E+00   (distinto, ULP)
caso 2: GPU=-2.80579650851037819E+06   gfortran=-2.80579650851038378E+06   (distinto)
caso 3: identico (magnitudes tan pequeñas que no hay cancelación que reasociar)
```
Mismo patrón que en el resto del árbol (`calpleg`, `V_hehe`, `d_uhex4`...): sin las flags, `nvfortran` puede reasociar la suma corrida de forma distinta a `gfortran`; con ellas, desaparece del todo. No hizo falta ningún cambio de código (a diferencia de `d_uhex4`/`der_wavefx`, donde la reasociación persistía incluso con flags y hubo que secuenciar a mano) — aquí bastó con activar `-Kieee -Mnofma`, consistente con que `getcm` ya estaba escrita en la forma "segura" desde el principio.

**Nota sobre `slaterdet_trivial`**: no se revisa aparte — es la rama recortada de `slaterdet` (§ implementación de `wavef.cuf`), estática por construcción (`slater=1.0` siempre, código muerto en el resto salvo `npart<=1`, ver comentario en el propio fichero) — no tiene ninguna operación que pueda reasociar ni ninguna función transcendente, así que no aporta nada nuevo que verificar.

## 10. `exp` → `myexp` en `wavefm`/`wavefhe3`: por qué, aunque no hubiera fallado

`wavefm` y `wavefhe3` eran los dos únicos sitios de todo el árbol que seguían llamando al `exp()` intrínseco en vez de a `myexp` (ya portado y usado en `wavefhe4`/`wavefx`/`V_hehe`/`Vp_hehe`). La pregunta que motivó la revisión: si no había aparecido ningún caso de divergencia con `exp()` aquí, ¿tenía sentido tocarlo?

**Aclaración previa (`dexp` vs `exp`)**: comprobado con un programa aislado (gfortran y nvfortran, mismo valor real de `ujas`) que `exp(x)` y `dexp(x)` con `x` de tipo `real(kind=r8)` dan resultado bit a bit idéntico — no son dos precisiones distintas, `dexp` es solo el nombre específico F77 de la misma rutina de doble precisión que `exp` (genérico) selecciona automáticamente. El propio original (`mwavef.f90`) ya usa `exp()`, no `dexp`, en todos los sitios.

**Comprobación con los `ujas` reales del árbol**: usando los 3 valores de `ujas` que aparecen en `test_wavefm` (normal=`-11.0836864775290`, contacto cercano=`-3125009.70`, largo alcance=`-1205.39`), se comparó `exp()` aislado host-nvfortran vs device-nvfortran vs gfortran: **coinciden exactamente en los 3, con y sin flags** (dos de ellos subyacen a `0.0` exacto por underflow, el tercero — el único no trivial — también coincide bit a bit).

**Pero, mirando los símbolos del objeto compilado**:
```
sin flags:   U __fd_exp_1   (variante "fast")
con -Kieee:  U __pd_exp_1   (variante "precise")
```
`exp()` en nvfortran tiene **la misma partición fast/precise** ya confirmada para `acos` y `pow` — el mismo riesgo estructural, aunque no se disparara para estos 3 valores concretos. Es exactamente el mismo patrón de "suerte" que en `angle_scalar_vec` (5/6 pares sin error hasta que apareció el sexto contraejemplo real). No hay (todavía) un valor de `ujas` conocido que demuestre la divergencia para `wavefm`/`wavefhe3` en concreto — a diferencia de `dacos`/`pow`, donde sí hubo un contraejemplo real — pero dado que `myexp` ya está portado, verificado bit-exacto contra `gfortran`, y su coste de integración es mínimo, se cambia de todas formas para cerrar el riesgo en vez de confiar en que ningún valor futuro de `ujas` caiga en la zona donde sí divergiría.

**Resultado tras el cambio** (`test_wavef`, prueba directa `nhe3=2`, `es24.17`):
```
con -Kieee -Mnofma:
  HP wfhe3 CPU= 1.36300456199365594E-01   GPU= 1.36300456199365594E-01
  HP wfm   CPU= 1.53608809629764358E-05   GPU= 1.53608809629764358E-05
  HP wfhe3 gfortran= 1.36300456199365594E-01
  HP wfm   gfortran= 1.53608809629764358E-05

sin flags:
  HP wfhe3 CPU= 1.36300456199365594E-01   GPU= 1.36300456199365594E-01
  HP wfm   CPU= 1.53608809629764358E-05   GPU= 1.53608809629764358E-05
```
**Exacto en las tres vías, con y sin flags**, para este caso. La prueba dedicada de `wavefm`/`derwavefm` ([`test_wavefm.cuf`](../derananum/test_wavefm.cuf), 3 casos × 25 valores, incluidos los extremos de contacto muy cercano y largo alcance) se repitió tras el cambio: **75/75 exacto con flags** (idéntico resultado que antes del cambio de `exp` — ver `derananum.md` §7 —, la sustitución no introduce ninguna regresión ni cambia el patrón de residuo sin flags, que sigue siendo puramente de reasociación/FMA, ya cerrado con `-Kieee -Mnofma`).

**Hallazgo corregido: `rij**phe3(2)` → `mypow`**. Revisando `wavefhe3` para el cambio de `exp` se vio que `ujas = ujas - phe3(1)/rij**phe3(2)` (línea justo antes) usaba `**` con `phe3(2)` real, sin `mypow` — el mismo patrón exacto ya corregido en `pmix(2)` de `wavefm`. Se corrige igual: `mypow(rij,phe3(2))`.

Esta línea es una asignación de un solo término (`ujas = ujas - ...`), no una suma de varios sumandos en una sola sentencia — no hace falta secuenciar nada, solo la sustitución de `**` por `mypow`.

**Segundo hallazgo: `rij**3` (exponente entero literal) SÍ tenía riesgo, al contrario de lo asumido.** El criterio usado hasta ahora en todo el árbol (`d_uhex4`, `der_wavefx`, `der_wavefhe4`) era "un exponente entero literal se compila como multiplicación repetida, sin llamada a biblioteca, luego no hace falta `mypow`" — nunca verificado con `nm`, solo asumido por analogía. Al revisar `etaij = phe3(4)/rij**3` se comprobó, y el supuesto era **falso**:

```
sin flags:   (ningún símbolo pow; inlined como multiplicación)
con -Kieee:  U __pd_powi_1   <- llamada real a biblioteca
```

Con un programa aislado (`rij=1000.123d0`, representativo de un caso real no trivial):
```
gfortran:            rij**3 = 1.00036904538886094E+09
nvfortran sin flags:  rij**3 = 1.00036904538886094E+09   (= gfortran)
nvfortran -Kieee:     rij**3 = 1.00036904538886106E+09   (!= gfortran, 1 ULP)
GPU (device), con o sin -Kieee:      = 1.00036904538886094E+09   (= gfortran siempre)
rij*rij*rij, en cualquier combinación de compilador/flags: = 1.00036904538886094E+09   (siempre exacto)
```
Es decir: **`-Kieee` en el HOST introduce una divergencia que no existe sin flags** — justo lo contrario del patrón habitual en el resto del árbol, donde `-Kieee` cierra divergencias en vez de abrirlas. El dispositivo (GPU) nunca pasa por `__pd_powi_1`: siempre multiplica directo, coincidiendo con gfortran en las dos variantes de flags.

**Por qué exactamente**: `rij` es una variable que cambia en cada llamada — el valor solo puede calcularlo el procesador en tiempo de ejecución, no el compilador de antemano (a diferencia de `dx**2` en `derwavefhe3`, ver `derananum.md` §3). Pero para llegar a ese cálculo en tiempo de ejecución, el compilador puede elegir **dos caminos** distintos para traducir `rij**3`: (A) instrucciones de multiplicación directa, `rij*rij*rij`; o (B) una llamada a una función de biblioteca matemática (`__pd_powi_1`, escrita por Nvidia/PGI). gfortran y el device de nvfortran toman siempre el camino (A). nvfortran en HOST, con `-Kieee`, decide tomar el camino (B) para ser "estricto" con la norma IEEE — y esa rutina de biblioteca, al usar internamente un algoritmo distinto (p.ej. registro extendido o aproximación genérica para exponentes cualesquiera, en vez de multiplicar dos veces seguidas), redondea el último bit de forma distinta. No es que “calculen distinto en tiempo real”: el chip siempre ejecuta en tiempo de ejecución para una variable — lo que cambia es a qué herramienta de software recurre el compilador para decirle al procesador cómo hacerlo.

**Corrección**: `phe3(4)/rij**3` → `phe3(4)/(rij*rij*rij)` — multiplicación explícita, no `mypow`. Se descarta `mypow` aquí a propósito: `mypow` se apoya en `exp(y*log(x))` (motor válido para el `y` real general, ya verificado contra `pow()` de glibc), pero un exponente entero exacto como `3` se resuelve con multiplicación directa tanto en gfortran como en el device de nvfortran — pasar por `mypow` sería más caro y, peor, **no está verificado que `mypow(x,3.0_r8)` reproduzca el `x**3` de gfortran bit a bit** (son dos algoritmos distintos por construcción). La multiplicación explícita sí está verificada exacta en las 4 combinaciones (gfortran / nvfortran-host sin flags / nvfortran-host con `-Kieee` / GPU).

Repetida la prueba de 3 casos (contacto cercano / largo alcance) tras el cambio: mismo resultado exacto que antes (§ tabla más arriba) — `etaij` no llegó a estar en la zona sensible para estos casos concretos, pero la corrección se aplica igualmente por el mismo principio que ha guiado todo este árbol: que una prueba no falle no es garantía de que no pueda fallar.

**Nota para el resto del árbol**: `d_uhex4.cuf`/`der_wavefx.cuf` tienen el mismo patrón (`.../rij**2` en `ulxs`), con el mismo supuesto sin verificar — pendiente de revisar aparte (no se toca aquí, fuera del alcance de este cambio).

Para probarlo se extendió la prueba directa `nhe3=2` de `wavef.cuf`/`test_wavef_gfortran.f90` (antes 1 solo caso) a **3 casos**, variando esta vez el `rij` **He3-He3** (el que usa `phe3(2)`, distinto del `rij` He4-He3 de `pmix(2)` ya cubierto en `test_wavefm.cuf`):

- Caso 1: geometría normal (la de siempre).
- Caso 2 (extremo): par He3-He3 a contacto muy cercano (`rij≈0.05`).
- Caso 3 (extremo): par He3-He3 a largo alcance (`rij≈1000`).

**Resultado (`es24.17`), con y sin flags, GPU / CPU-`nvfortran` / `gfortran`:**

| caso | `wfhe3` | `wfm` |
|---|---|---|
| 1 (normal) | `1.36300456199365594E-01` — exacto en las 3 vías, con y sin flags | `1.53608809629764358E-05` — ídem |
| 2 (contacto cercano) | `1.38389652673673756E-87` — ídem | `2.79721668864446584E-05` — ídem |
| 3 (largo alcance) | `1.38389652673673756E-87` — ídem | `0.00000000000000000E+00` — ídem |

**6/6 exacto, en las tres vías, con Y sin flags** — a diferencia de otros sitios del árbol, aquí ni siquiera aparece el residuo típico de FMA/reasociación sin flags, porque es una sola operación (`mypow` + una resta), sin sumas de varios términos que reasociar. Nota: `wfhe3` da el mismo valor en los casos 2 y 3 porque `ujas` satura contra el suelo `umin=-200` en ambos extremos (el término `-phe3(3)*|rb(:,1)-rb(:,2)|`, que depende del centro de masas, se dispara en los dos casos) — es el `min`/`max` de saturación ya existente en el código original, no un artefacto del cambio.

## 11. `wavef`: la única instrucción propia, `wf = wfhe4*wfhe3*wfm*wfx`

`wavef` (§6) no calcula nada por sí mismo salvo esta línea — el resto son llamadas a `wavefhe4`/`wavefhe3`/`wavefm`/`wavefx`, cada una ya verificada por separado. Una cadena de 4 multiplicaciones en una sola sentencia no tiene el patrón de riesgo de las sumas (no hay acumulador de por medio, se evalúa izquierda-a-derecha), pero nunca se había comprobado a alta precisión — el test de `wf` (`test_wavef.cuf`/`test_wavef_gfortran.f90`, walker-level) solo tenía salida `f20.12`, y los 3 valores reales de `wf` resultan ser del orden de `1E-30` a `1E-178` — **redondeados a `0.000000000000` en las tres vías**, exactamente el mismo enmascaramiento por precisión que se corrigió en `der_wavefx.md` §10 para `wfx`. Se añade `es24.17`.

**Resultado, con `-Kieee -Mnofma`:**

| walker | CPU-`nvfortran` | GPU | `gfortran` |
|---|---|---|---|
| 1 | `5.77761590529023112E-30` | `5.77761590529023112E-30` | `5.77761590529023112E-30` |
| 2 | `2.95902462387761814E-31` | `2.95902462387761770E-31` | `2.95902462387761814E-31` |
| 3 | `1.27904417273776839E-178` | `1.27904417273776839E-178` | `1.27904417273776839E-178` |

Walkers 1 y 3: exacto en las tres vías. Walker 2: CPU-`nvfortran` coincide exacto con `gfortran`; el GPU (device) difiere de ambos por 1-2 ULP, **incluso con flags** — es la misma divergencia de contexto host/device-codegen ya documentada y aceptada en `He_dihydrogen.md` (Parte 4/5), `der_wavefhe4.md` §6 y `der_wavefx.md` §9c: no depende de esta multiplicación (el residuo ya viene de dentro de `wfhe3`/`wfm`, que este mismo walker ya mostraba con ese nivel de discrepancia en sus pruebas dedicadas — ver §8/§10), la multiplicación solo lo transporta sin añadir nada nuevo. Sin flags, mismo patrón: walkers 1/3 con un residuo FMA que cierra con las flags, walker 2 sin cambios. No hace falta ningún cambio de código.
