# Sexto kernel: `wavefhe4` / `derwavefhe4`

Documentación de [`v1-cuda-desarrollo/der_wavefhe4/der_wavefhe4.cuf`](../der_wavefhe4/der_wavefhe4.cuf). Porta el Jastrow He4-He4 y su derivada de [`mwavef.f90`](../der_wavefhe4/mwavef.f90). Es el primer kernel de este proyecto cuyo original recibe el **`type(walker)` completo** en vez de un escalar o un `vec3` suelto — y por eso es el primero que obliga a la conversión AoS→SoA de la que ya se habló al principio del port (ver §1).

---

## Parte 1 — Implementación

## 1. El problema de fondo: `type(walker)` no se puede llevar a la GPU

```fortran
type :: walker
  type (vloc) :: lw
  type (vec3), allocatable :: atom(:),dwf(:)
  real (kind=r8), allocatable :: delta(:),hb2m(:),sigma1(:),sigma2(:)
  ...
end type
```
A diferencia de `vec3` (un `real(3)` fijo, sin nada dinámico), `walker` tiene **componentes `allocatable`** (`atom(:)`, `dwf(:)`, `delta(:)`, `hb2m(:)`, `sigma1(:)`, `sigma2(:)`). Un tipo derivado con componentes `allocatable`/`pointer` no se puede usar como dato `device`: la GPU no puede gestionar esa reserva dinámica anidada dentro de cada elemento de un array de walkers de la misma forma que la CPU.

`wavefhe4`/`derwavefhe4` en realidad solo leen `w1%atom(:)` (las posiciones) y escriben `w1%lw%wfhe4` (un escalar) o `d1wf`/`d2wf` (que en el original **ya** son argumentos aparte, no van dentro de `w1`). Así que la interfaz se reduce a justo eso:

```fortran
! antes (original, mwavef.f90):
subroutine wavefhe4(w1)
  type(walker), intent (inout) :: w1
  ...
  w1%lw%wfhe4=exp(ujas)

! despues (der_wavefhe4.cuf):
attributes(host, device) subroutine wavefhe4(atom, wfhe4)
  type(vec3), intent (in)  :: atom(nhe4)
  real(kind=r8), intent (out) :: wfhe4
  ...
  wfhe4=exp(ujas)
```
`derwavefhe4` casi no cambia (ya escribía `d1wf`/`d2wf` como argumentos propios): solo `w1%atom(iatom)` pasa a ser `atom(iatom)`.

## 2. La conversión AoS→SoA, en la práctica

En el original, la posición del átomo `ia` del walker `iw` es `w1(iw)%atom(ia)` — cada walker con su propio array `atom(:)` reservado y anidado dentro de su propia estructura (*array of structs*, y cada struct con sus propios arrays — el caso más problemático para GPU). Al cambiar la interfaz para recibir directamente el array de posiciones, esa misma posición pasa a ser:
```fortran
type(vec3), device, intent (in) :: atom(nhe4,n)   ! k_wavefhe4 / k_derwavefhe4
```
`atom(ia,iw)` — **un único array grande y plano, compartido por todos los walkers, sin nada anidado** (*struct of arrays*). Es la misma transformación que se explicó al principio de este port ("sacar la dimensión de walker fuera de la estructura"), aplicada aquí por primera vez porque `wavefhe4`/`derwavefhe4` son las primeras funciones portadas cuyo original recibe el `walker` entero — todo lo anterior (`calpleg`, `V_hehe`/`Vp_hehe`, `angle_scalar_vec`, `duhe4x`) ya recibía escalares o `vec3` sueltos, sin ninguna estructura anidada de la que salir. De aquí en adelante, cualquier función que reciba el `walker` completo (`hpsi`, `derananum`, `vpot`, `wavef`...) necesitará el mismo tratamiento.

## 3. Las variables externas: mismo criterio que en `duhe4x`

- **`nhe4`** y **`phe4(3)`**: variables reales de `mparametros.f90` (`public`, sin `parameter` — comprobado), rellenadas una vez por `mentradatos.f90` al leer `in.mcv`. Mismo tratamiento que `lxhe4`/`pxhe4`: `device` a nivel de módulo, con una asignación explícita desde el host antes de lanzar los kernels.
- **`umax`, `umin`**: estas sí son `parameter` de verdad en el original (`real, private, parameter :: umax=200.0_r8, umin=-200.0_r8`, dentro de `mwavef.f90`) — se declaran tal cual, sin necesitar copia a la GPU, igual que las constantes de `param_atoms_bh.h`.
- **`vec3`**: se reutiliza `mtipos.f90` (`use mtipos, only: vec3`), sin retipear. Al igual que en `duhe4x`, el cuerpo de `wavefhe4`/`derwavefhe4` solo accede a `%comp` — nunca opera sobre un `vec3` entero — así que no hace falta preocuparse por los operadores sobrecargados de `mtipos.f90` (que son solo de host).

---

## Parte 2 — Pruebas

## 4. Datos de prueba y resultado

3 walkers de prueba, 4 átomos de He4 cada uno (no hace falta que coincida con el `nhe4=20` real de la simulación — basta con que CPU y GPU usen el mismo valor), con posiciones sintéticas y los parámetros reales de `in.mcv` para el Jastrow He4-He4 (`b=3.139383`, `nu=4.725025`, `alfa=0.009428`), calculando `phe4(1)=0.5*b**nu` con la misma fórmula que `mentradatos.f90` en vez de teclearlo ya multiplicado.

La referencia de CPU es `mwavef.f90` sin tocar — a diferencia de la versión GPU, esta sí recibe el `type(walker)` completo, así que hace falta construir uno de verdad para la prueba, usando el `allocatewalker` de `mtipos.f90` para reservar `w1%atom(:)`.

### Cómo ejecutarlo

Desde `v1-cuda-desarrollo/der_wavefhe4/` (los dos toolchains no comparten `.mod`, hay que limpiar entre uno y otro):

```bash
# 1) GPU + CPU(nvfortran) en el mismo binario
rm -f *.mod *.o
nvfortran -cuda -c mtipos.f90 mparametros.f90 mlegendre.f90 mangwavef.f90 mvaziz.f90
nvfortran -cuda -c modlegendre.f mhh_heocs.f90 kpcoef.f mkp_heco.f90 pw_heocs.f bh_heh2m.f
nvfortran -cuda -c mvmolecula.f90 mrotaciones.f90 mlineal.f90 msistref.f90 mwavef.f90
nvfortran -cuda mtipos.o mparametros.o mlegendre.o mangwavef.o mvaziz.o modlegendre.o \
  mhh_heocs.o kpcoef.o mkp_heco.o pw_heocs.o bh_heh2m.o mvmolecula.o mrotaciones.o \
  mlineal.o msistref.o mwavef.o der_wavefhe4.cuf -o test_derwavefhe4 -llapack -lblas
./test_derwavefhe4

# 2) Solo CPU, con gfortran
rm -f *.mod *.o
gfortran -ffixed-line-length-132 -c modlegendre.f kpcoef.f pw_heocs.f bh_heh2m.f
gfortran -ffixed-line-length-132 -c mtipos.f90 mparametros.f90 mlegendre.f90 mangwavef.f90 \
  mvaziz.f90 mhh_heocs.f90 mkp_heco.f90 mvmolecula.f90 mrotaciones.f90 mlineal.f90 msistref.f90 mwavef.f90
gfortran -ffixed-line-length-132 mtipos.o mparametros.o mlegendre.o mangwavef.o mvaziz.o \
  modlegendre.o mhh_heocs.o kpcoef.o mkp_heco.o pw_heocs.o bh_heh2m.o mvmolecula.o mrotaciones.o \
  mlineal.o msistref.o mwavef.o test_derwavefhe4_gfortran.f90 -o test_derwavefhe4_gfortran -llapack -lblas
./test_derwavefhe4_gfortran
```

**Resultado real — 1) GPU + CPU(`nvfortran`)**, con el detalle por átomo de `d1wf`/`d2wf`:
```
--- walker 1
  wfhe4 CPU=      0.407378476016   GPU=      0.407378476016
  atom 1 d1wf CPU=     -0.3481988672     -0.0749180013     -0.0937705016  d2wf CPU=     -0.5451841016
  atom 1 d1wf GPU=     -0.3481988672     -0.0749180013     -0.0937705016  d2wf GPU=     -0.5451841016
  atom 2 d1wf CPU=      0.4099210956     -0.0177493099     -0.0044423293  d2wf CPU=     -0.3013062687
  atom 2 d1wf GPU=      0.4099210956     -0.0177493099     -0.0044423293  d2wf GPU=     -0.3013062687
  atom 3 d1wf CPU=     -0.0166146970      0.1581605064      0.0412951444  d2wf CPU=     -0.1521331729
  atom 3 d1wf GPU=     -0.0166146970      0.1581605064      0.0412951444  d2wf GPU=     -0.1521331729
  atom 4 d1wf CPU=     -0.0451075313     -0.0654931952      0.0569176864  d2wf CPU=     -0.1020052444
  atom 4 d1wf GPU=     -0.0451075313     -0.0654931952      0.0569176864  d2wf GPU=     -0.1020052444
  |err| max=  0.00E+00

--- walker 2
  wfhe4 CPU=      0.054125989527   GPU=      0.054125989527
  atom 1 d1wf CPU=      3.8256548308     -1.7194364819      0.8153919908  d2wf CPU=     10.3854138352
  atom 1 d1wf GPU=      3.8256548308     -1.7194364819      0.8153919908  d2wf GPU=     10.3854138352
  atom 2 d1wf CPU=     -3.9976681942      2.0173915550     -0.9659122051  d2wf CPU=     13.4889309323
  atom 2 d1wf GPU=     -3.9976681942      2.0173915550     -0.9659122051  d2wf GPU=     13.4889309323
  atom 3 d1wf CPU=      0.1685143075     -0.2742499928      0.2148252948  d2wf CPU=     -0.2848380426
  atom 3 d1wf GPU=      0.1685143075     -0.2742499928      0.2148252948  d2wf GPU=     -0.2848380426
  atom 4 d1wf CPU=      0.0034990559     -0.0237050803     -0.0643050805  d2wf CPU=     -0.0754257609
  atom 4 d1wf GPU=      0.0034990559     -0.0237050803     -0.0643050805  d2wf GPU=     -0.0754257609
  |err| max=  0.00E+00

--- walker 3
  wfhe4 CPU=      0.466396836029   GPU=      0.466396836029
  atom 1 d1wf CPU=      0.1049966126     -0.0705216335     -0.0705216335  d2wf CPU=     -0.1393195639
  atom 1 d1wf GPU=      0.1049966126     -0.0705216335     -0.0705216335  d2wf GPU=     -0.1393195639
  atom 2 d1wf CPU=     -0.0705216335      0.1049966126     -0.0705216335  d2wf CPU=     -0.1393195639
  atom 2 d1wf GPU=     -0.0705216335      0.1049966126     -0.0705216335  d2wf GPU=     -0.1393195639
  atom 3 d1wf CPU=     -0.0705216335     -0.0705216335      0.1049966126  d2wf CPU=     -0.1393195639
  atom 3 d1wf GPU=     -0.0705216335     -0.0705216335      0.1049966126  d2wf GPU=     -0.1393195639
  atom 4 d1wf CPU=      0.0360466545      0.0360466545      0.0360466545  d2wf CPU=     -0.4381989542
  atom 4 d1wf GPU=      0.0360466545      0.0360466545      0.0360466545  d2wf GPU=     -0.4381989542
  |err| max=  0.00E+00

 PASA: GPU y CPU coinciden dentro de tolerancia
```
El `|err| max` de cada walker incluye tanto `wfhe4` como todas las componentes de `d1wf`/`d2wf` de los 4 átomos — **cero exacto en los tres casos**, sin necesitar ninguna flag especial (`-Kieee`/`-Mnofma`), a diferencia de lo que pasó con `Vp_hehe` y `angle`.

**Resultado real — 2) solo CPU, con `gfortran`** ([`test_derwavefhe4_gfortran.f90`](../der_wavefhe4/test_derwavefhe4_gfortran.f90), mismos 3 walkers):
```
--- walker 1
  wfhe4 gfortran=      0.407378476016
  atom 1 d1wf=     -0.3481988672     -0.0749180013     -0.0937705016  d2wf=     -0.5451841016
  atom 2 d1wf=      0.4099210956     -0.0177493099     -0.0044423293  d2wf=     -0.3013062687
  atom 3 d1wf=     -0.0166146970      0.1581605064      0.0412951444  d2wf=     -0.1521331729
  atom 4 d1wf=     -0.0451075313     -0.0654931952      0.0569176864  d2wf=     -0.1020052444

--- walker 2
  wfhe4 gfortran=      0.054125989527
  atom 1 d1wf=      3.8256548308     -1.7194364819      0.8153919908  d2wf=     10.3854138352
  atom 2 d1wf=     -3.9976681942      2.0173915550     -0.9659122051  d2wf=     13.4889309323
  atom 3 d1wf=      0.1685143075     -0.2742499928      0.2148252948  d2wf=     -0.2848380426
  atom 4 d1wf=      0.0034990559     -0.0237050803     -0.0643050805  d2wf=     -0.0754257609

--- walker 3
  wfhe4 gfortran=      0.466396836029
  atom 1 d1wf=      0.1049966126     -0.0705216335     -0.0705216335  d2wf=     -0.1393195639
  atom 2 d1wf=     -0.0705216335      0.1049966126     -0.0705216335  d2wf=     -0.1393195639
  atom 3 d1wf=     -0.0705216335     -0.0705216335      0.1049966126  d2wf=     -0.1393195639
  atom 4 d1wf=      0.0360466545      0.0360466545      0.0360466545  d2wf=     -0.4381989542
```
Comparando dígito a dígito contra la columna `CPU:` del test 1 (mismo `wfhe4`, mismos `d1wf`/`d2wf`): **valores idénticos**. Las tres vías coinciden: **GPU = CPU(`nvfortran`) = CPU(`gfortran`)**.

**Corrección posterior — a precisión completa (`es24.17`) sí había un residuo real.** La comparación de arriba se hizo a `f18.10`/`f20.12` (10-12 decimales), que no llega a mostrar diferencias de última cifra. `rij**phe4(2)` (línea 42, `wavefhe4`) y `rij**(phe4(2)+1)` (línea 72, `derwavefhe4`) usan exponente **real** (`phe4(2)=nuhe4=4.725025`, no entero) — mismo problema de `pow()` ya documentado en `d_uhex4.md` §5 y `glibc_math.md` Parte 4.

## 5. `mypow` + secuenciar `ujas`/`d2wf`

Mismos dos cambios que en `duhe4x`/`duhe3x`:

**a)** `rij**phe4(2)` → `mypow(rij,phe4(2))` (en `wavefhe4`); `rij**(phe4(2)+1)` → `mypow(rij,phe4(2)+1.0_r8)` (en `derwavefhe4`).

**b)** Secuenciar las acumulaciones de 2-3 términos en una sola sentencia:
```fortran
! wavefhe4, antes:            ujas=ujas-phe4(1)/mypow(rij,phe4(2))-phe4(3)*rij
! wavefhe4, despues:           ujas=ujas-phe4(1)/mypow(rij,phe4(2))
!                              ujas=ujas-phe4(3)*rij

! derwavefhe4, antes:          d2wf(iatom)=d2wf(iatom)+ujass+2.0_r8*ujasp
! derwavefhe4, despues:        d2wf(iatom)=d2wf(iatom)+ujass
!                              d2wf(iatom)=d2wf(iatom)+2.0_r8*ujasp
! (igual para d2wf(jatom))
```

## 6. Batería extrema + las dos tablas (con/sin flags, CPU-`nvfortran`-vs-GPU y GPU-vs-`gfortran`)

Se añaden 2 walkers a los 3 originales: **walker 4**, contacto muy cercano entre dos átomos (`rij≈0.05`, el análogo de "contacto cercano" para un Jastrow que solo depende de distancias, no de ángulos — `wavefhe4`/`derwavefhe4` no usan `cth`/`calpleg`, así que no hay "ángulos especiales" que probar aquí, solo el rango de `rij`); **walker 5**, largo alcance (`rij≈1000` entre un par). Cada walker tiene 4 átomos → 6 pares `rij` por walker, y se comparan `wfhe4` + `d1wf`/`d2wf` de los 4 átomos (17 valores por walker).

**Tabla 1 — CPU(`nvfortran`) vs GPU (mismo binario)**:

| walker | sin flags | con flags |
|---|---|---|
| 1 | `5.55E-17` | `0.00E+00` |
| 2 | `1.07E-14` | `6.94E-18` |
| 3 | `5.55E-17` | `0.00E+00` |
| 4 (contacto cercano) | `0.00E+00` | `0.00E+00` |
| 5 (largo alcance) | `1.42E-14` | `0.00E+00` |

**Tabla 2 — GPU (`nvfortran`) vs CPU-`gfortran`**:

| walker | sin flags | con flags |
|---|---|---|
| 1 | `2.78E-17` | `0.00E+00` |
| 2 | `6.94E-18` | `6.94E-18` |
| 3 | `0.00E+00` | `0.00E+00` |
| 4 (contacto cercano) | `7.11E-15` | `0.00E+00` |
| 5 (largo alcance) | `1.42E-14` | `0.00E+00` |

**Con `-Kieee -Mnofma`, 4 de los 5 walkers dan exacto `0.00E+00`** en ambas tablas — el único residuo persistente, con y sin flags, es el walker 2 (`~7E-18`, esencialmente 1 ULP): **CPU(`nvfortran`) coincide exacto con `gfortran`** en ese walker (comprobado directamente), así que el residuo es puramente GPU(device)-vs-el-resto — el mismo patrón de los dos backends de `nvfortran` divergiendo pese a código secuencial idéntico, ya documentado en `He_dihydrogen.md` Parte 4/5, sin que ninguna flag lo cambie. Los casos extremos (contacto muy cercano, largo alcance) **no introducen ningún residuo nuevo** — de hecho el walker 4 (contacto cercano) da `0.00E+00` en las dos tablas con flags, mejor que varios de los walkers "normales".
