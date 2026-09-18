# Undécimo kernel: `vpot`

Documentación de [`v1-cuda-desarrollo/vpot/vpot.cuf`](../vpot/vpot.cuf). Porta `vpot` de [`mwavef.f90`](../vpot/mwavef.f90): la energía potencial total del walker. Es el punto donde confluyen `ccuerpo` y `potenbh`, ya portados por separado — `vpot` con `opot=4` es literalmente `call ccuerpo(...); call potenbh(...)`.

---

## Parte 1 — Implementación

## 1. El original

```fortran
subroutine vpot(w1)
  type(walker), intent (inout) :: w1
  ...
  if(opot.eq.4) then
      call ccuerpo(w1,rhe)
      call potenbh(ngatom,rhe,vpotbh)
      w1%lw%pot=vpotbh
   return
  endif

   w1%lw%pot=0.0_r8
   do iatom=1,ngatom-1
     do jatom=iatom+1,ngatom
       ...
       w1%lw%pot=w1%lw%pot+aziz_nuevo(rij)
     enddo
   enddo
   if(.not.impureza) return
   if(impurmol) then
     ...
     w1%lw%pot=w1%lw%pot+vatomol(opot,cmtok,rij,cth)
     ...
   else
     ...
     w1%lw%pot=w1%lw%pot+azizgen(rij)
   endif
end subroutine vpot
```

## 2. Qué se porta y qué no: `opot=4` fijo, el resto es código muerto de verdad

`in.mcv` fija `opot=4` ("He-H2⁺ Breton et al, Preprint 2023") para esta simulación. El `if(opot.eq.4)` del original termina con un `return` — así que **todo lo que viene después nunca se ejecuta** mientras `opot` no cambie: ni el bucle de `aziz_nuevo` (He-He puro, `opot=0`), ni `vatomol`/`azizgen` (otras impurezas, `opot=1,2,3`).

Esto es distinto del caso de `wavef` (`wavefm`/`wavefhe3` sí se llamaban siempre, solo con resultado trivial para `nhe3=0` — ver `wavef.md` §1): aquí no hay ninguna llamada que "de igual portar barata" porque **ni siquiera se ejecuta**. Es exactamente el mismo caso ya identificado para `vpot` antes de empezar a portar nada de esta zona del código (aziz_nuevo/vatomol/azizgen quedaron fuera desde el principio, junto con la parte de `slaterdet` que tampoco se porta en `wavef.cuf`). Por eso `vpot.cuf` **solo implementa la rama `opot==4`**:
```fortran
attributes(host, device) subroutine vpot(atom, sprop, pot)
  ...
    if (opot == 4) then
      call ccuerpo(atom, sprop, rhe(1:3*ngatom))
      call potenbh(ngatom, rhe(1:3*ngatom), vpotbh)
      pot = vpotbh
    endif
end subroutine vpot
```
El `if(opot==4)` se mantiene (no se asume `opot=4` a ciegas sin comprobarlo): es una comparación **uniforme para todos los walkers** (se fija una vez al arrancar, igual para todo el warp), coste cero de divergencia — mismo argumento que ya se usó para `GTEST` en `He_dihydrogen.md`. Pero no hay ninguna rama `else` que ejecutar: si algún día se necesitara otro `opot`, habría que portar `aziz_nuevo`/`vatomol`/`azizgen` de verdad (y, para `vatomol` con impurezas moleculares tipo OCS/CO, probablemente reaprovechando el patrón de Legendre de `duhe4x`/`d_uhex4`).

## 3. Variables a importar: `opot` sí, `cmtok` no

- **`opot`**: variable real de `mparametros.f90` (pública, sin `parameter`), fijada una vez al leer `in.mcv` — mismo tratamiento `device` que `ngatom`/`natom`/`nhe4` en kernels anteriores.
- **`cmtok`**: **es** un `PARAMETER` real (`mparametros.f90`, `= 2*pi*hbc*1e-7/kb`) — no necesitaría copia `device` aunque se usara. Pero en el original solo aparece en la llamada a `vatomol`, la rama que no se porta (§2) — así que **no hace falta importarla para nada** en esta versión.
- **`ngatom`/`natom`**: no se vuelven a declarar aquí — se reutilizan directamente las variables `device` que ya declaraba `mccuerpo` (`use mccuerpo, only: ccuerpo, ngatom, natom`), evitando una tercera copia del mismo dato (ya había una en `mccuerpo` y otra en `der_wavefx`/`der_wavefhe4` para otros kernels).
- **`natms`** (cota fija de átomos, `=30`): se trae con `include 'param_atoms_bh_freeform.h'`, igual que en `He_dihydrogen.f`, para dimensionar el buffer local `rhe` (ver §5).

## 4. `w1` se descompone igual que en `ccuerpo`/`wavef`

```fortran
attributes(host, device) subroutine vpot(atom, sprop, pot)
  type(vec3), intent (in) :: atom(natom), sprop(3)
  real(kind=r8), intent (out) :: pot
```
`w1%lw` (`type vloc`) no tiene ningún componente `allocatable` — a diferencia de `walker`, en principio *sí* se podría pasar entero a código `device` tal cual. Pero como `vpot` solo escribe un único campo (`pot`) y ningún otro kernel de este proyecto expone su `w1%lw` completo, se mantiene el mismo criterio que en `wavef`/`wavefx`: devolver `pot` como escalar de salida directo, interfaz mínima, en vez de arrastrar el tipo `vloc` entero por un solo campo.

## 5. `rhe`: mismo problema de siempre, misma solución de siempre

El original declara `rhe(3*ngatom)` como array local — `ngatom` es una variable `device` (tamaño solo conocido en tiempo de ejecución), así que un array local con ese tamaño no es válido en código `device` (el mismo problema que `R2(N,N)` en `He_dihydrogen` o `rb(3,nhe3)` en `wavef`). Se resuelve igual: un buffer de tamaño fijo, `rhe(3*natms)` (`natms=30`, el mismo límite que ya usa `He_dihydrogen.f` para sus propios arrays), pasando la sección contigua `rhe(1:3*ngatom)` a `ccuerpo`/`potenbh` (que sí aceptan `ngatom` como cota de un argumento mudo, sin problema).

## 6. Sin más `IF` que discutir

Fuera del `if(opot==4)` ya discutido en §2, `vpot` (en la forma portada) no tiene ninguna otra rama.

---

## Parte 2 — Pruebas

## 7. El programa de prueba

3 walkers, 4 átomos de He + 1 impureza (mismos datos sintéticos que en `ccuerpo`/`wavef`, para poder cruzar resultados si hiciera falta), `opot=4`, `dhcm=0.52943550d0` (real, de `heh2m.pot`).

La referencia de CPU es `vpot` de `mwavef.f90` **sin tocar** — a diferencia de `He_dihydrogen`/`potenbh` (subrutinas sueltas en `bh_heh2m.f`, sin módulo, por eso se importaban con `external`), `vpot` sí vive dentro de un módulo real (`module mwavef`) en el original, así que se importa con `use mwavef, only: vpot`, no con `external`. Internamente llama a su propio `ccuerpo`/`potenbh` (los de `msistref.f90`/`bh_heh2m.f`, no los módulos GPU), así que hace falta la cadena de compilación completa del original (`mvaziz`, `mvmolecula`, `mlineal`... todo lo que arrastra `mwavef.f90`, aunque `aziz_nuevo`/`vatomol`/`azizgen`/`det` no se lleguen a ejecutar).

Como en `potenbh.md`, `dhcm` viaja por un `COMMON /datosbh/` en el original — hay que declarar el mismo common en el programa de prueba para compartir esa memoria con `vpot`→`potenbh`.

### Cómo ejecutarlo

Desde `v1-cuda-desarrollo/vpot/`:
```bash
# 1) GPU + CPU(nvfortran) en el mismo binario
rm -f *.mod *.o
nvfortran -cuda -c mtipos.f90 mparametros.f90 mlegendre.f90 mangwavef.f90 mvaziz.f90
nvfortran -cuda -c modlegendre.f mhh_heocs.f90 kpcoef.f mkp_heco.f90 pw_heocs.f bh_heh2m.f
nvfortran -cuda -c mvmolecula.f90 mrotaciones.f90 mlineal.f90 msistref.f90 mwavef.f90
nvfortran -cuda -c angle_scalar_vec_mod.cuf mVheheVphehe_mod.cuf He_dihydrogen.f mccuerpo_mod.cuf mpotenbh_mod.cuf vpot.cuf
nvfortran -cuda mtipos.o mparametros.o mlegendre.o mangwavef.o mvaziz.o modlegendre.o mhh_heocs.o \
  kpcoef.o mkp_heco.o pw_heocs.o bh_heh2m.o mvmolecula.o mrotaciones.o mlineal.o msistref.o mwavef.o \
  angle_scalar_vec_mod.o mVheheVphehe_mod.o He_dihydrogen.o mccuerpo_mod.o mpotenbh_mod.o vpot.o \
  -o test_vpot -llapack -lblas
./test_vpot

# 2) Solo CPU, con gfortran
rm -f *.mod *.o
gfortran -c mtipos.f90 mparametros.f90 mlegendre.f90 mangwavef.f90 mvaziz.f90
gfortran -ffixed-line-length-132 -c modlegendre.f mhh_heocs.f90 kpcoef.f mkp_heco.f90 pw_heocs.f bh_heh2m.f
gfortran -c mvmolecula.f90 mrotaciones.f90 mlineal.f90 msistref.f90 mwavef.f90
gfortran mtipos.o mparametros.o mlegendre.o mangwavef.o mvaziz.o modlegendre.o mhh_heocs.o kpcoef.o \
  mkp_heco.o pw_heocs.o bh_heh2m.o mvmolecula.o mrotaciones.o mlineal.o msistref.o mwavef.o \
  test_vpot_gfortran.f90 -o test_vpot_gfortran -llapack -lblas
./test_vpot_gfortran
```

**Resultado real — 1) GPU + CPU(`nvfortran`)**:
```
--- walker 1
  pot CPU=    -23.6733760164   GPU=    -23.6733760164
  |err| max=  3.55E-15

--- walker 2
  pot CPU=    -90.5544524332   GPU=    -90.5544524332
  |err| max=  0.00E+00

--- walker 3
  pot CPU=    229.7590815666   GPU=    229.7590815666
  |err| max=  4.55E-13

 PASA: GPU y CPU coinciden dentro de tolerancia
```
Los valores no coinciden con los de `potenbh.md` para los mismos átomos (walker 3: `229.76` aquí, `-20.93` en `potenbh.md`) — y es lo esperado: en `potenbh.md` las posiciones de laboratorio se pasaban **directamente** a `potenbh` (saltándose `ccuerpo`), mientras que aquí pasan primero por la transformación al sistema de referencia del cuerpo (`ccuerpo`, usando `sprop`) antes de llegar a `potenbh` — es la cadena completa, no un atajo.

**Sobre las diferencias de ULP (`3.55E-15`, `4.55E-13`) — se probaron las flags, y aquí NO las eliminan del todo.** En `V_hehe_Vp_hehe.md` §9 se vio que `-Mnofma` (sola) hacía desaparecer por completo una discrepancia CPU-GPU muy parecida, aislada a una sola expresión de `Vp_hehe`. Aquí la cadena es mucho más larga (`ccuerpo`+`potenbh`+`He_dihydrogen`, con sus `dexp`/`dcos`/`dsin` en `ENERGY2`/`ENERGY3`), así que se repitió el experimento real en vez de asumir que se repetiría el mismo arreglo:

| Compilación | walker 1 | walker 2 | walker 3 |
|---|---|---|---|
| sin flags | `3.55E-15` | `0.00E+00` | `4.55E-13` |
| `-Mnofma` sola | `3.55E-15` | `0.00E+00` | `3.41E-13` |
| `-Kieee -Mnofma` juntas | `3.55E-15` | `1.42E-14` | `3.41E-13` |

Ninguna combinación lo deja en `0.00E+00` en los tres walkers a la vez — con las dos flags juntas incluso **empeora** el walker 2 (de exacto a `1.42E-14`). Esto encaja con que la causa ya no es (solo) la fusión FMA de una expresión concreta como en `Vp_hehe`: con tantas llamadas a `dexp`/`dcos`/`dsin` acumuladas en la cadena, entran en juego además las implementaciones de esas funciones transcendentales en el hardware de GPU frente a la biblioteca matemática de CPU, que pueden diferir en el último bit sin que ninguna de las dos sea "incorrecta" — algo que `-Kieee`/`-Mnofma` no fuerzan a igualar. La compilación final se deja **sin flags** (igual que `He_dihydrogen`/`potenbh`): el error residual (`~1e-13` sobre valores de decenas/cientos) está muchos órdenes de magnitud por debajo de cualquier tolerancia física relevante, y las flags no lo mejoran de forma consistente como para justificar el coste de rendimiento de desactivar FMA en producción.

**Resultado real — 2) solo CPU, con `gfortran`**:
```
--- walker 1
  pot gfortran=    -23.6733760164

--- walker 2
  pot gfortran=    -90.5544524332

--- walker 3
  pot gfortran=    229.7590815666
```
Idéntico dígito a dígito a la columna `CPU:` de la prueba 1. Las tres vías coinciden: **GPU ≈ CPU(`nvfortran`) = CPU(`gfortran`)**, con la única discrepancia el ULP por FMA ya conocido entre GPU y CPU.

## 8. Re-verificación tras el cierre de `He_dihydrogen` (Kahan + `rnorm**6`/`atheta`)

Esta sección (y la §7 de arriba) son de **antes** de toda la investigación de `dacos`/`pow`/reasociación/Kahan documentada en `He_dihydrogen.md` — la conclusión de "no se puede cerrar del todo, se deja sin flags" quedó obsoleta. Al retomar la verificación se encontró además que **`He_dihydrogen.f`/`angle_scalar_vec_mod.cuf`/`mVheheVphehe_mod.cuf` en esta carpeta eran copias muy obsoletas** (la versión previa a `myexp`/`mycos`/`mysin`/`myacos`, con funciones-sentencia sin secuenciar) — refrescadas desde `He_dihydrogen/`.

Con las copias al día y `-Kieee -Mnofma`, `test_vpot` daba **2/3 exacto** (walker2 con un residuo de `~3E-16`, no cerraba con flags). Se investigó a fondo (trazado átomo a átomo, ver `He_dihydrogen.md` Parte 8) y se encontró primero una hipótesis parcial (`rnorm**6`/`atheta` con exponente entero literal, mismo mecanismo `__pd_powi_1` que `wavefhe3`) — pero al comparar contra el original de verdad (`bh_heh2m.f`) se descubrió la causa real: **el original usa exponente REAL (`**6.d0`), no entero, en estos ~20 sitios** — un error heredado de un porteo anterior a esta sesión. La multiplicación explícita "arreglaba" `vpot` por coincidencia (dos aproximaciones erróneas cancelándose), no por replicar el algoritmo correcto.

**Corrección de fondo**: `mypow(x, N.0d0)` (ya portado y validado contra `pow()` real) en vez de multiplicación. Al aplicarlo apareció un segundo bug — `mypow` no soporta base negativa (nunca hizo falta antes, siempre `rij`>0), y `mycos(theta)`/`mysin(theta)` sí pueden serlo — corregido con `abs()`/`SIGN()`.

**Resultado tras la corrección real**: `vpot` walker2 pasa a **CPU(host)=GPU(device) exacto** (el bug de dominio/algoritmo, cerrado); queda un residuo de `~1.6E-16` relativo frente al `gfortran` real (sin tocar) — mismo suelo de precisión ya aceptado en el resto del árbol, no el bug que se venía persiguiendo. Detalle completo, incluida la comprobación de que no era un problema de orden de suma (`treesum` daba el mismo resultado que `kahansum`) y el balance frente a la batería de `He_dihydrogen.md` (walker2 vuelve a ser el que diverge, como en el cierre original de la Parte 5) en `He_dihydrogen.md` Parte 8, §25-29.
