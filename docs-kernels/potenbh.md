# Décimo kernel: `potenbh`

Documentación de [`v1-cuda-desarrollo/potenbh/potenbh.cuf`](../potenbh/potenbh.cuf). Porta `potenbh` de [`bh_heh2m.f`](../potenbh/bh_heh2m.f): la envoltura que prepara la geometría fija del dihidrógeno (`r_dih`/`rHH`/`orHH`, a partir de `dhcm`) y llama a `He_dihydrogen` para obtener la energía total del potencial He-H2⁺ (`vpotbh=energy1+energy2+energy3`). Es la pieza que falta entre `ccuerpo` (ya portado) y `vpot` — `vpot` con `opot=4` hace exactamente `call ccuerpo(w1,rhe); call potenbh(ngatom,rhe,vpotbh)` (ver la discusión de por qué `aziz_nuevo`/`vatomol`/`azizgen` no hacía falta portarlas, en la conversación de este mismo bloque de trabajo).

Partía de un borrador con varios problemas de fondo, no solo de sintaxis; esta documentación se centra en esos, no en typos sueltos.

---

## Parte 1 — Implementación

## 1. El original

```fortran
subroutine potenbh(nhe4,xhe4,vpotbh)
  integer nhe4
  real*8  xhe4(3*nhe4),ejemol(3),vpotbh
  ...
  real*8 dhcm
  common / datosbh / dhcm
  ...
   r_dih=0.0d0
   r_dih(3,1)= dhcm
   r_dih(3,2)=-dhcm
   ...
   test=.false.
   call He_dihydrogen(nhe4,r_dih,rHH,orHH,xhe4,vhe4,ENERGY1,ENERGY2,ENERGY3,TEST)
   vpotbh=(energy1+energy2+energy3)
end subroutine potenbh
```
`dhcm` (la mitad de la distancia H-H del dihidrógeno) no es una variable de módulo: es un `COMMON` block (`/datosbh/`), un mecanismo F77 de memoria compartida entre subrutinas — lo rellena `bh_leevheh2m` una sola vez, al leer `heh2m.pot` al arrancar la simulación, y se queda fijo el resto de la ejecución. `sacabh`/`metebh` son un getter/setter de ese mismo common, tampoco se ejecutan por walker.

## 2. Por qué el borrador no compilaba: tres problemas de fondo

Más allá de typos sueltos (una `implicit none` colocada antes de los `use`, que en Fortran tienen que ir primero; un espacio que falta en `attributes(host, device)subroutine`), había tres decisiones equivocadas que había que corregir:

**a) Un `COMMON` no tiene copia `device` automática.** El borrador dejaba `common / datosbh / dhcm` tal cual dentro de la subrutina `attributes(host,device)`. Un `COMMON` es una zona de memoria de host; no hay ninguna traducción automática a memoria de GPU, así que usarlo dentro de código `device` no funciona. Se sustituye por una variable `device` de módulo — mismo tratamiento que `nhe4`/`phe4`/`ngatom` en kernels anteriores, con la única diferencia de que aquí la fuente original es un `common`, no un `module` real:
```fortran
real(kind=r8), device :: dhcm
```

**b) El dummy `nhe4` chocaba con el `nhe4` real de otros módulos.** El borrador importaba `nhe4, nhe3, ngatom, natom, impureza` de `der_wavefx` y `wavefhe4`/`wavefx` de `der_wavefhe4`/`der_wavefx` — **ninguno de los cuatro hace falta**: `potenbh` no usa ningún `vec3`, no llama a `wavefx` ni a `wavefhe4`, solo llama a `He_dihydrogen` (ya portado en `He_dihydrogen/He_dihydrogen.f`, módulo `mHe_dihydrogen`). Además, llamar `nhe4` al primer argumento es engañoso: quien llama a `potenbh` de verdad (`vpot`, con `opot=4`) le pasa **`ngatom`**, no el `nhe4` real de la simulación — son cosas distintas (`ngatom=nhe4+nhe3`). Se renombra el dummy a `natoms`, evitando además que choque con cualquier variable `device` real llamada `nhe4` si en el futuro se importa algún módulo que la tenga.

**c) El kernel `k_potenbh` no tenía dimensión de walker.** El borrador declaraba `xhe4`/`vpotbh` sin ningún índice de walker (`n`), y además ponía `value` en un array (`real*8, value, xhe4(...)`) — `value` en CUDA Fortran es solo para escalares, nunca para arrays. Se reescribe con el patrón de un hilo por walker de siempre:
```fortran
attributes(global) subroutine k_potenbh(n, natoms, xhe4, vpotbh)
  integer(kind=i4), value :: n, natoms
  real(kind=r8), device, intent (in)  :: xhe4(3*natoms,n)
  real(kind=r8), device, intent (out) :: vpotbh(n)
  ...
    call potenbh(natoms, xhe4(:,i), vpotbh(i))
```

## 3. Limpieza menor: declaraciones muertas del original

`ejemol(3)` (dummy), y `vtot`, `dcont`, `zav`, `zor`, `iHatom`, `jHatom`, `icontHH` (locales) están declaradas en el `potenbh` original pero **no se usan en ningún punto del cuerpo** — ni se leen ni se escriben. Se quitan en el port; no cambian nada del cálculo, solo limpian declaraciones sin uso.

## 4. Sin ningún `IF` que discutir

`potenbh` es cuatro asignaciones y una llamada — no tiene ninguna rama condicional propia (el único `logical` es `gtest=.false.`, un valor fijo que se pasa a `He_dihydrogen`, ya documentado en `He_dihydrogen.md` §4).

## 5. Reutilización de `He_dihydrogen` sin tocar nada

`He_dihydrogen.f` (módulo `mHe_dihydrogen`) ya estaba portado y probado; aquí se reutiliza tal cual junto con sus dependencias (`mVheheVphehe_mod.cuf`, `angle_scalar_vec_mod.cuf`, `param_atoms_bh_freeform.h`), copiadas a `potenbh/` sin modificar ni una línea — mismo patrón de reutilización que en `wavef.cuf` con `der_wavefhe4`/`der_wavefx`.

---

## Parte 2 — Pruebas

## 6. El programa de prueba

3 walkers, 4 átomos (mismos valores de `X_h` que ya se usaron en `test_He_dihydrogen.cuf`, para poder comparar si hiciera falta), con `dhcm=0.52943550d0` (el valor real de `heh2m.pot`).

La referencia de CPU es `potenbh` de `bh_heh2m.f` **sin tocar**, que internamente llama a su propio `He_dihydrogen` (el original, no el portado). Al declararla `external`, hay que declarar también el mismo `COMMON /datosbh/` en el programa de prueba — es la forma en que dos unidades de programa distintas comparten esa zona de memoria en Fortran — y solo se importa `k_potenbh`/`dhcm` del módulo (no `potenbh`), para que el nombre no choque con el `external :: potenbh` de la CPU (mismo motivo que en `test_He_dihydrogen.cuf`).

### Cómo ejecutarlo

Desde `v1-cuda-desarrollo/potenbh/`:
```bash
# 1) GPU + CPU(nvfortran) en el mismo binario
rm -f *.mod *.o
nvfortran -cuda -Kieee -Mnofma -c glibc_exp_mod.cuf glibc_acos.cuf glibc_sincos.cuf \
  angle_scalar_vec_mod.cuf mVheheVphehe_mod.cuf He_dihydrogen.f bh_heh2m.f potenbh.cuf
nvfortran -cuda -Kieee -Mnofma glibc_exp_mod.o glibc_acos.o glibc_sincos.o \
  angle_scalar_vec_mod.o mVheheVphehe_mod.o He_dihydrogen.o bh_heh2m.o potenbh.o \
  -o test_potenbh -llapack -lblas
./test_potenbh

# 2) Solo CPU, con gfortran
rm -f *.mod *.o
gfortran -ffixed-form -ffp-contract=off -c bh_heh2m.f -o bh_heh2m_gf.o
gfortran -ffp-contract=off bh_heh2m_gf.o test_potenbh_gfortran.f90 -o test_potenbh_gfortran
./test_potenbh_gfortran
```

**Resultado real — 1) GPU + CPU(`nvfortran`)**:
```
--- walker 1
  vpotbh CPU=    -68.4284618449   GPU=    -68.4284618449
  |err| max=  1.42E-14

--- walker 2
  vpotbh CPU=   -127.2855742362   GPU=   -127.2855742362
  |err| max=  1.42E-13

--- walker 3
  vpotbh CPU=    -20.9263173964   GPU=    -20.9263173964
  |err| max=  0.00E+00

 PASA: GPU y CPU coinciden dentro de tolerancia
```
Las diferencias (`1.42E-14`, `1.42E-13`) son del mismo orden de ULPs por FMA ya vistas y explicadas en `V_hehe_Vp_hehe.md`/`He_dihydrogen.md` — esperable, ya que `vpotbh` es literalmente `energy1+energy2+energy3` de `He_dihydrogen`, que ya tenía ese nivel de discrepancia.

**Resultado real — 2) solo CPU, con `gfortran`**:
```
--- walker 1
  vpotbh gfortran=    -68.4284618449

--- walker 2
  vpotbh gfortran=   -127.2855742362

--- walker 3
  vpotbh gfortran=    -20.9263173964
```
Idéntico dígito a dígito a la columna `CPU:`/`GPU:` de la prueba 1. Las tres vías coinciden: **GPU ≈ CPU(`nvfortran`) = CPU(`gfortran`)**, con la única discrepancia siendo el ULP por FMA ya conocido entre GPU y CPU (no entre los dos compiladores de CPU).

## 7. Re-verificación final: copias obsoletas de `He_dihydrogen` y comprobación de `energy1+energy2+energy3`

Al revisar el árbol completo (junto con `wavef`/`ccuerpo`/`valibre`) se encontró que `He_dihydrogen.f`, `angle_scalar_vec_mod.cuf` y `mVheheVphehe_mod.cuf` **copiados en esta carpeta eran versiones antiguas**, previas a los cambios `dacos→myacos`/`dexp→myexp`/`dsin→mysin`/`dcos→mycos` documentados en `He_dihydrogen.md`/`angle_scalar_vec.md`/`V_hehe_Vp_hehe.md` — el resultado del punto 6 de arriba viene de esa versión sin corregir. Se refrescan las copias desde `He_dihydrogen/` (fuente actual) junto con sus dependencias (`glibc_exp_mod.cuf`, `glibc_acos.cuf`, `glibc_sincos.cuf` y las tablas `.txt`), y se repite la prueba con `-Kieee -Mnofma` y `es24.17`.

**Sobre `vpotbh = energy1 + energy2 + energy3` (única línea de cálculo propia de `potenbh`, aparte de la llamada)**: se comprobó de forma aislada, con 3 tríos `(energy1,energy2,energy3)` representativos, si escribirla en una sola sentencia frente a 3 sentencias secuenciadas (`v=e1; v=v+e2; v=v+e3`) cambia algo — **resultado idéntico bit a bit en los dos casos, CPU y GPU, con y sin flags**. Es la misma conclusión que con `ul=` en `uhe4x`/`uhe3x` (`der_wavefx.md` §9b): una expresión autocontenida de pocos términos, sin acumulador entre iteraciones de un bucle, no reasocia distinto por escribirla de una forma u otra.

**Resultado con la versión actual de `He_dihydrogen`, `es24.17`, `-Kieee -Mnofma`:**
```
walker 1: CPU=-6.84284618448650974E+01   GPU=-6.84284618448651116E+01   gfortran=-6.84284618448651116E+01
walker 2: CPU=-1.27285574236189248E+02   GPU=-1.27285574236189291E+02   gfortran=-1.27285574236189291E+02
walker 3: CPU=-2.09263173963997211E+01   GPU=-2.09263173963997176E+01   gfortran=-2.09263173963997176E+01
```
En los 3 walkers, GPU coincide exacto con `gfortran`; CPU-`nvfortran`(host) difiere por 1-2 ULP de ambos, incluso con flags. Sin flags, CPU=GPU (coinciden entre sí) pero ambos difieren de `gfortran` en magnitud similar. **Es exactamente la misma familia de divergencia host/device-codegen ya documentada como inevitable en `He_dihydrogen.md` (Parte 4/5)** — la prueba de `energy1+energy2+energy3` (arriba) confirma que no se origina en esta suma, así que es 100% heredada de dentro de `He_dihydrogen` (`FN1`/`FN2`, ya en su propio suelo de precisión aceptado). **No hace falta ningún cambio de código** — ni en `potenbh` ni, por extensión, en `He_dihydrogen` (ya se documentó allí que ningún flag lo cierra).

**Revisión adicional (walker2/`ENERGY2`, el único residuo GPU-vs-`gfortran` de `He_dihydrogen`):** al preparar esta revisión se encontró que `F2`...`F6` (usadas por `FN1`, que alimenta `ENERGY2`) tenían `**N` con exponente entero literal sin revisar — el mismo patrón que sí causaba divergencia real en `wavefhe3`. Se probó sustituirlo por multiplicación explícita y se confirmó con SASS real (`cuobjdump --dump-sass`) que el cambio no lo arregla (mismo valor GPU bit a bit) y desplaza el residuo a otro walker — confirmación de bajo nivel de que la causa es reasignación de registros por PTXAS, no la fórmula en sí. Revertido.

**Cierre definitivo**: tras descartar también FMA (CPU y GPU), límite de registros y agresividad de PTXAS (ningún ajuste de compilador movía el resultado — tabla completa en `He_dihydrogen.md` §18), se cerró el residuo cambiando el algoritmo: suma compensada de Kahan en la acumulación de `ENERGY2`. **9/9 exacto** con `-Kieee -Mnofma`, verificado contra `bh_heh2m.f` sin modificar. Detalle completo en `He_dihydrogen.md` Parte 6-7 (§15-20).

## 8. Re-verificación de `potenbh` tras el cierre de Kahan

Con `He_dihydrogen.f` ya corregido (Kahan en `ENERGY2`), se repite la prueba propia de `potenbh` (`vpotbh=ENERGY1+ENERGY2+ENERGY3`, 3 walkers, `es24.17`), GPU vs. `bh_heh2m.f` sin modificar:

```
con -Kieee -Mnofma:
  walker1: GPU=-6.84284618448651116E+01   gfortran=-6.84284618448651116E+01   EXACTO
  walker2: GPU=-1.27285574236189291E+02   gfortran=-1.27285574236189291E+02   EXACTO
  walker3: GPU=-2.09263173963997176E+01   gfortran=-2.09263173963997176E+01   EXACTO
```
**3/3 exacto** — igual que antes del cambio de Kahan. Esto confirma lo que ya se había visto en §7: el ULP de `ENERGY2`/walker2 **nunca llegó a manifestarse en `vpotbh`** (se perdía en el redondeo de la suma de las tres energías, de magnitud mucho mayor). El valor de arreglar `He_dihydrogen.f` con Kahan no está en `potenbh` en sí — que ya daba exacto — sino en `ENERGY2` como magnitud individual, relevante para cualquier otro consumidor de `He_dihydrogen` que la use suelta (y para la corrección de fondo del algoritmo, más allá de si un caso concreto la enmascara al sumarla).

**Sin flags**: 1/3 exacto (walker2 — el que curiosamente coincide sin necesitar flags), residuo `~1E-15` en walkers 1 y 3 — mismo patrón "cierra con flags" de siempre, sin relación con el cambio de Kahan.

**Corrección posterior, más de fondo**: se encontró que `atheta`/`btheta`/`c6theta`/`rnorm**6`/`rnorm**7` en `He_dihydrogen.f` usaban exponente **entero** (`**6`), cuando el original (`bh_heh2m.f`) usa exponente **real** (`**6.d0`, invoca `pow()` de verdad) — un error heredado de un porteo anterior a esta sesión, no algo introducido aquí. Corregido con `mypow` (ya portado, validado bit a bit contra `pow()` real) en vez de multiplicación explícita. Al aplicarlo apareció un segundo bug: `mypow` solo soporta base positiva (nunca hizo falta la rama `x<0` en usos previos, siempre con `rij`), y `mycos(theta)`/`mysin(theta)` sí pueden ser negativos — corregido con `abs()`/`SIGN()`. Detalle completo, incluida la investigación que encontró ambos bugs, en `He_dihydrogen.md` Parte 8 (§25-29).
