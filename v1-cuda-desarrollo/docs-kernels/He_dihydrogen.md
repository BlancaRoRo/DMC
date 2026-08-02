# Séptimo kernel: `He_dihydrogen`

Documentación de [`v1-cuda-desarrollo/He_dihydrogen/He_dihydrogen.f`](../He_dihydrogen/He_dihydrogen.f). Porta el potencial He-dihidrógeno (energía + gradiente analítico) de [`bh_heh2m.f`](../He_dihydrogen/bh_heh2m.f). Es el primer fichero de este proyecto escrito en **Fortran fijo antiguo (F77, columnas)** en vez de formato libre — y también el primero que, por enlazar junto a su propio original para la comparación CPU/GPU, expone un problema de **símbolos duplicados en el enlazador** que no había aparecido hasta ahora.

---

## Parte 1 — Implementación

## 1. ¿Formato fijo o reescribir en libre?

`bh_heh2m.f` está escrito en Fortran fijo: columnas 1-5 para etiquetas, columna 6 para continuación, código a partir de la columna 7, comentarios con `C`/`*` en la columna 1. La duda inicial era si había que reescribir `He_dihydrogen` en formato libre (como todos los `.cuf` anteriores) para poder añadir `attributes(host,device)` y los `use` de los módulos ya portados.

La respuesta, comprobada de forma aislada antes de tocar el fichero real (misma metodología que en los kernels anteriores): **no hace falta**. `attributes(host,device)`, las declaraciones `use module, only: ...` y las funciones-sentencia (`F00(...)=...`, ver §3) funcionan igual en fijo que en libre — son solo sentencias Fortran normales, con la única restricción de las columnas. El único choque real de formato encontrado en todo el port (el `INCLUDE` de una cabecera fija dentro de un `.cuf` libre, para `V_hehe-Vp_hehe` y `angle_scalar_vec`) no aplica aquí, porque **el fichero entero se queda fijo** y puede seguir incluyendo `param_atoms_bh.h` (fijo) sin ninguna versión `_freeform`.

Por eso `He_dihydrogen.f` se mantiene en `.f` (fijo), a diferencia de todos los `.cuf` anteriores — se copia el cuerpo entero tal cual, sin reformatear ni una sola línea de continuación (`&` en columna 6), y solo se añaden/quitan las líneas mínimas descritas abajo.

## 2. Cambios concretos frente al original

Comparando con `He_dihydrogen` en `bh_heh2m.f` (sin tocar, usado como referencia de CPU — ver Parte 2):

**a) La cabecera de la subrutina:**
```fortran
! antes (bh_heh2m.f):
      SUBROUTINE He_dihydrogen (N, r_dih, rHH, orHH, X, V, ENERGY1,
     &                          ENERGY2, ENERGY3, GTEST)
      IMPLICIT NONE

! despues (He_dihydrogen.f):
      attributes(host,device) SUBROUTINE He_dihydrogen (N, r_dih, rHH,
     &                          orHH, X, V, ENERGY1,
     &                          ENERGY2, ENERGY3, GTEST)
      use mVheheVphehe, only: V_hehe, Vp_hehe
      use angle_scalar_vec, only: angle, scalar_product, vec_norm
      IMPLICIT NONE
```
`V_hehe`/`Vp_hehe` y `angle`/`scalar_product`/`vec_norm` son justo los kernels portados y probados en sesiones anteriores ([`V_hehe_Vp_hehe.md`](V_hehe_Vp_hehe.md), [`angle_scalar_vec.md`](angle_scalar_vec.md)) — aquí se reutilizan sin cambiar ni una línea de su implementación, solo importándolos.

**b) Los arrays locales `R2`/`G`, de tamaño `N` a tamaño `natms`:**
```fortran
! antes:
DOUBLE PRECISION ... R2(N,N), R, G(N,N), DUMMY,V_hehe,Vp_hehe, ...

! despues:
DOUBLE PRECISION ... R2(natms,natms), R, G(natms,natms), DUMMY, ...
```
Mismo problema de siempre en código `device`: un array automático local dimensionado con un valor que solo se conoce en tiempo de ejecución (`N`, el número de átomos que llega como argumento) no está permitido. La solución, igual que con `lmax_dev` en `calpleg`, es un tamaño fijo conocido en tiempo de compilación — pero aquí no hace falta inventarse ninguna constante nueva: **`natms` ya existe** como `PARAMETER (natms=30)` dentro de `param_atoms_bh.h`, que la subrutina ya incluye. Solo hay que usarlo en vez de `N` en la declaración de `R2`/`G`; el resto del cuerpo sigue usando `R2(J2,J1)`/`G(J2,J1)` con `J1,J2` acotados por el `N` real (≤30), así que ningún acceso se sale del array de 30×30 reservado.

**c) `V_hehe,Vp_hehe` desaparecen de la lista de tipos:**
La declaración original las incluía como `DOUBLE PRECISION ..., DUMMY,V_hehe,Vp_hehe, ...` — el estilo F77 de declarar el tipo de retorno de una función externa/statement sin más. Ahora que vienen de un `use, only:`, declararlas otra vez en la lista de tipos sería redefinir un nombre ya importado por `use` — error de compilación. Se han quitado de esa lista; el resto de nombres de la lista no cambia.

**d) Sin variables `device` nuevas a nivel de módulo.** A diferencia de `duhe4x` o `wavefhe4` (que necesitaban `nhe4`, `phe4`, `lxhe4`... copiadas explícitamente a `device` antes de lanzar el kernel), `He_dihydrogen` no tiene ese problema: todas las constantes físicas que usa (`natms`, `ndih`, `nHH`, `eps_HeHe`, `req_HeHe`, los coeficientes `a0,a1,a2,a3,b0...`, etc.) llegan por el `INCLUDE 'param_atoms_bh.h'`, y **todas son `PARAMETER`** — comprobado con `grep` en la cabecera —, no variables reales rellenadas en tiempo de ejecución. Un `PARAMETER` no necesita ninguna copia a la GPU: el compilador lo trata como una constante de compilación en ambos lados (host y device), igual que ya se documentó para `umax`/`umin` en `der_wavefhe4.md`.

## 3. Las funciones-sentencia (`F00`, `DFN2`...) — sin cambios

El original define un bloque de *statement functions* (una construcción F77 antigua, sustituida por funciones internas modernas, pero aún válida):
```fortran
F00(XDUMM)=...
F0(XDUMM)=...
...
FN1(XDUMM)=F0(XDUMM)+F1(XDUMM)+...+F6(XDUMM)
DFN1(XDUMM)=DF0(XDUMM)+...
FN2(XDUMM)=F0(XDUMM)+F1(XDUMM)+F2(XDUMM)
DFN2(XDUMM)=DF0(XDUMM)+DF1(XDUMM)+DF2(XDUMM)
```
Se comprobó de forma aislada (antes de tocar el fichero real) que las funciones-sentencia se compilan y ejecutan igual dentro de una subrutina `attributes(host,device)` que en una subrutina normal — no son una construcción incompatible con CUDA Fortran, simplemente azúcar sintáctico que el compilador expande inline en el mismo sitio donde se definen. No ha hecho falta tocar ni una línea de este bloque.

## 4. Los `IF` de `GTEST` (y los demás `IF` del cuerpo): por qué no se reestructuran

`He_dihydrogen` tiene tres bloques `IF (GTEST) THEN ... END IF` (uno por cada bloque de energía: `ENERGY1`, `ENERGY2`, `ENERGY3`), que calculan el gradiente (`V(...)`) solo cuando `GTEST=.true.`; si es `.false.` solo se calculan las energías. Además hay un `IF (fi.eq.1.d0) ... ELSE IF (fi.eq.-1.d0) ... ELSE ...` (protección de la derivada del ángulo cuando el átomo cae exactamente sobre el eje del dihidrógeno, evitando dividir por `sqrt(1-fi**2)=0`).

Mismo criterio ya aplicado y documentado en `der_wavefx.md` para los `IF` de esa subrutina, y que aplica igual aquí:
- **`GTEST`** es un argumento que llega igual para **todos los walkers** de una misma tanda (se decide una vez, al planificar el cálculo, no por walker) — con un hilo por walker, todos los hilos de un mismo warp evalúan `GTEST` con el mismo valor. No hay divergencia de warp posible por esta rama: o la toman todos los hilos, o ninguno.
- El `IF (fi.eq.1.d0)/(fi.eq.-1.d0)` sí depende de datos por walker (la geometría de cada uno), así que en teoría **sí** podría hacer que distintos hilos de un mismo warp tomen ramas distintas. Pero es una comparación barata (un `dsqrt` como mucho) dentro de un cuerpo dominado por llamadas a `V_hehe`/`Vp_hehe`/`angle`/potencias — el coste de la posible divergencia es marginal frente al resto del cálculo, y restructurarlo (p. ej. con `merge()`) solo tendría sentido si un perfilado real (`nsys`/`nvprof`) mostrara que es un cuello de botella, no de antemano.
- No hay ninguna estructura de control en este fichero que dependa de sumas/reducciones entre hilos ni de escritura compartida entre walkers — cada hilo lee y escribe únicamente sus propios `X`/`V`/`ENERGY*`, así que ningún `IF` obliga a reestructurar el reparto de trabajo (que sigue siendo un hilo por walker, igual que en todos los kernels anteriores).

En resumen: **ningún `IF` de este fichero necesita reestructuración**, ni el de `GTEST` (uniforme, coste cero) ni el de `fi` (posible divergencia, coste marginal).

## 5. El bug del enlazador: `He_dihydrogen` duplicado entre `.o`

Al enlazar el test (Parte 2) junto al `bh_heh2m.o` original (necesario como referencia de CPU) apareció:
```
/usr/bin/ld: bh_heh2m.o: in function `he_dihydrogen_':
.../bh_heh2m.f:74: multiple definition of `he_dihydrogen_';
He_dihydrogen.o:.../He_dihydrogen.f:18: first defined here
```
Causa: `He_dihydrogen.f` (el port) y `bh_heh2m.f` (el original) definen una subrutina con el **mismo nombre**, y ninguna de las dos estaba dentro de un `module` — una subrutina externa "suelta" en Fortran se traduce a un símbolo de enlazador plano y sin cualificar (`he_dihydrogen_`). Al enlazar los dos `.o` en el mismo binario (imprescindible para comparar GPU contra la CPU de referencia), el enlazador ve el mismo símbolo definido dos veces.

Esto no había pasado con `V_hehe`/`Vp_hehe`/`angle`/`scalar_product`/`vec_norm` porque esas sí se envolvieron en un `module` desde el principio (`mVheheVphehe`, `angle_scalar_vec`) — un procedimiento dentro de un módulo se traduce a un símbolo cualificado con el nombre del módulo (p. ej. algo del estilo `mvhehevphehe_v_hehe_`), que no choca con la versión suelta del original.

**Corrección aplicada** — envolver también `He_dihydrogen` en un módulo:
```fortran
      module mHe_dihydrogen
      contains
      attributes(host,device) SUBROUTINE He_dihydrogen (N, r_dih, rHH,
     &                          orHH, X, V, ENERGY1,
     &                          ENERGY2, ENERGY3, GTEST)
      ...
      END SUBROUTINE He_dihydrogen
      end module mHe_dihydrogen
```
`module`/`contains`/`end module` son sentencias Fortran normales y válidas en formato fijo igual que en libre (respetando la columna 7 de inicio), así que este cambio no obliga a reformatear ni una línea del cuerpo — son 4 líneas nuevas alrededor de la subrutina ya escrita. Con esto, `k_He_dihydrogen.cuf` pasa de declarar un `interface` explícito para `He_dihydrogen` a simplemente:
```fortran
use mHe_dihydrogen, only: He_dihydrogen
```
que es más corto y evita mantener la firma duplicada a mano en dos sitios.

---

## Parte 2 — Pruebas

## 6. El kernel `k_He_dihydrogen` y el programa de prueba

[`k_He_dihydrogen.cuf`](../He_dihydrogen/k_He_dihydrogen.cuf): un hilo por walker, igual que en todos los kernels anteriores. `r_dih`, `rHH`, `orHH` son los mismos para todos los walkers (solo dependen de `dhcm`, la separación del dihidrógeno, no de la configuración de cada walker), mientras que `X`/`V`/`ENERGY1..3` sí van indexados por walker:
```fortran
attributes(global) subroutine k_He_dihydrogen(n_walk, natoms, r_dih, rHH, orHH, &
    X, V, energy1, energy2, energy3, gtest)
 ...
  i = (blockIdx%x - 1) * blockDim%x + threadIdx%x
  if (i <= n_walk) then
    call He_dihydrogen(natoms, r_dih, rHH, orHH, X(:,i), V(:,i), &
                        energy1(i), energy2(i), energy3(i), gtest)
  endif
```

[`test_He_dihydrogen.cuf`](../He_dihydrogen/test_He_dihydrogen.cuf): 3 walkers de prueba, 4 "átomos de He" cada uno, con `dhcm=0.52943550d0` (valor real tomado de `heh2m.pot`) y posiciones sintéticas. La referencia de CPU es `He_dihydrogen` de `bh_heh2m.f` **sin tocar**, declarada `external`. Como `bh_heh2m.f` no es un módulo, no hay `use` posible para ella; y como `k_He_dihydrogen_mod` sí expone (indirectamente, vía `mHe_dihydrogen`) un nombre `He_dihydrogen`, el test solo importa `k_He_dihydrogen` por nombre (`use k_He_dihydrogen_mod, only: k_He_dihydrogen`) para no chocar con el `external :: He_dihydrogen` de la CPU.

Se prueban **las dos ramas de `GTEST`** (`.false.` y `.true.`) en un bucle `do igt=0,1`, tal y como se pidió — no solo la que se había mirado en un principio.

### Cómo ejecutarlo

Desde `v1-cuda-desarrollo/He_dihydrogen/`:
```bash
# 1) GPU + CPU(nvfortran) en el mismo binario
nvfortran -cuda -c He_dihydrogen.f -o He_dihydrogen.o
nvfortran -cuda -c k_He_dihydrogen.cuf -o k_He_dihydrogen.o
nvfortran -cuda mVheheVphehe_mod.o angle_scalar_vec_mod.o He_dihydrogen.o k_He_dihydrogen.o \
  bh_heh2m.o test_He_dihydrogen.cuf -o test_He_dihydrogen -llapack -lblas
./test_He_dihydrogen

# 2) Solo CPU, con gfortran
gfortran -ffixed-form -c bh_heh2m.f -o bh_heh2m_gf.o
gfortran bh_heh2m_gf.o test_He_dihydrogen_gfortran.f90 -o test_He_dihydrogen_gfortran
./test_He_dihydrogen_gfortran
```
(`mVheheVphehe_mod.o`/`angle_scalar_vec_mod.o` son los módulos ya compilados en sesiones anteriores, reutilizados tal cual — ver [`V_hehe_Vp_hehe.md`](V_hehe_Vp_hehe.md) y [`angle_scalar_vec.md`](angle_scalar_vec.md).)

**Resultado real — 1) GPU + CPU(`nvfortran`)**:
```
=== GTEST = F

--- walker 1
  ENERGY1 CPU=     -0.6358371738   GPU=     -0.6358371738
  ENERGY2 CPU=    -11.4241944915   GPU=    -11.4241944915
  ENERGY3 CPU=    -56.3684301796   GPU=    -56.3684301796
  |err| max=  6.66E-15

--- walker 2
  ENERGY1 CPU=      8.5507148184   GPU=      8.5507148184
  ENERGY2 CPU=     58.1327900564   GPU=     58.1327900564
  ENERGY3 CPU=   -193.9690791110   GPU=   -193.9690791110
  |err| max=  1.42E-13

--- walker 3
  ENERGY1 CPU=     -0.6500470848   GPU=     -0.6500470848
  ENERGY2 CPU=     -2.9908823777   GPU=     -2.9908823777
  ENERGY3 CPU=    -17.2853879338   GPU=    -17.2853879338
  |err| max=  0.00E+00

=== GTEST = T

--- walker 1
  ENERGY1 CPU=     -0.6358371738   GPU=     -0.6358371738
  ENERGY2 CPU=    -11.4241944915   GPU=    -11.4241944915
  ENERGY3 CPU=    -56.3684301796   GPU=    -56.3684301796
  V(1:4) CPU=   16.44064122    6.14076851    6.16865172    0.01026996
  V(1:4) GPU=   16.44064122    6.14076851    6.16865172    0.01026996
  |err| max=  2.13E-14

--- walker 2
  ENERGY1 CPU=      8.5507148184   GPU=      8.5507148184
  ENERGY2 CPU=     58.1327900564   GPU=     58.1327900564
  ENERGY3 CPU=   -193.9690791110   GPU=   -193.9690791110
  V(1:4) CPU=  -39.87461118   36.75833884 -161.09126587   35.92937157
  V(1:4) GPU=  -39.87461118   36.75833884 -161.09126587   35.92937157
  |err| max=  2.42E-13

--- walker 3
  ENERGY1 CPU=     -0.6500470848   GPU=     -0.6500470848
  ENERGY2 CPU=     -2.9908823777   GPU=     -2.9908823777
  ENERGY3 CPU=    -17.2853879338   GPU=    -17.2853879338
  V(1:4) CPU=           NaN           NaN           NaN           NaN
  V(1:4) GPU=    2.30428396   -0.15419963   -0.15419963   -0.15419963
  |err| max=  0.00E+00

 PASA: GPU y CPU coinciden dentro de tolerancia
```
`ENERGY1`/`ENERGY2`/`ENERGY3` coinciden en los 3 walkers y en las dos ramas de `GTEST`, con diferencias de 1 a 2 ULPs (mismo tipo de discrepancia FMA ya visto y explicado en `V_hehe_Vp_hehe.md` §9 — no es un fallo nuevo). El `V(1:4)` de los walkers 1 y 2 también coincide dígito a dígito. **El walker 3 con `GTEST=T` es el caso interesante: la CPU da `NaN` en todo `V`, y la GPU da números finitos** — ver §8 para el porqué (spoiler: no es un bug del port).

## 7. La tercera vía: `gfortran`, sin nada de GPU

[`test_He_dihydrogen_gfortran.f90`](../He_dihydrogen/test_He_dihydrogen_gfortran.f90) repite los mismos 3 walkers, llamando directamente a `He_dihydrogen` de `bh_heh2m.f` compilado con `gfortran` en vez de con `nvfortran`:

```
=== GTEST = F
--- walker 1
  ENERGY1 gfortran=     -0.6358371738
  ENERGY2 gfortran=    -11.4241944915
  ENERGY3 gfortran=    -56.3684301796
--- walker 2
  ENERGY1 gfortran=      8.5507148184
  ENERGY2 gfortran=     58.1327900564
  ENERGY3 gfortran=   -193.9690791110
--- walker 3
  ENERGY1 gfortran=     -0.6500470848
  ENERGY2 gfortran=     -2.9908823777
  ENERGY3 gfortran=    -17.2853879338

=== GTEST = T
--- walker 1
  ENERGY1 gfortran=     -0.6358371738
  ENERGY2 gfortran=    -11.4241944915
  ENERGY3 gfortran=    -56.3684301796
  V(1:4) gfortran=   17.26374300    6.00664113    5.56085444   -0.31871224
--- walker 2
  ENERGY1 gfortran=      8.5507148184
  ENERGY2 gfortran=     58.1327900564
  ENERGY3 gfortran=   -193.9690791110
  V(1:4) gfortran=  -39.80170195   36.83124806 -160.72671974   35.45969326
--- walker 3
  ENERGY1 gfortran=     -0.6500470848
  ENERGY2 gfortran=     -2.9908823777
  ENERGY3 gfortran=    -17.2853879338
  V(1:4) gfortran=    2.84005517   -0.15419963   -0.68997083   -0.15419963
```
Las energías coinciden dígito a dígito con la columna `CPU:`/`GPU:` de §6 en los tres walkers, en las dos ramas de `GTEST` — sin sorpresas ahí.

## 8. Reaparece el bug de `Vap` — y esta vez con pruebas de sobra

`He_dihydrogen` (tanto el original como el port) llama a `Vp_hehe(R)` para **todos** los pares de átomos de He, siempre (línea `G(J2,J1)=Vp_hehe(R)/R`, fuera de cualquier `IF (GTEST)`) — pero `G` solo se usa para calcular `V(...)` dentro de los bloques `IF (GTEST)`. Esto es justo el escenario que expone el bug ya documentado en [`V_hehe_Vp_hehe.md` §5](V_hehe_Vp_hehe.md#5-el-bug-de-vap-en-el-original--y-cómo-se-corrigió-aquí): en la `Vp_hehe` **original** de `bh_heh2m.f`, la variable local `Vap` solo se asigna dentro de un `if (x >= xx1_HeHe .and. x <= xx2_HeHe)`, y se usa después sin ninguna rama que la inicialice fuera de esa ventana — para los pares de átomos cuya distancia cae fuera de `[xx1_HeHe, xx2_HeHe]`, `Vp_hehe` devuelve lo que `Vap` tenga por casualidad en memoria en ese momento.

Comparando las tres columnas para `GTEST=T` (§6 y §7):

| | walker 1, `V(1)` | walker 2, `V(1)` | walker 3, `V(1:4)` |
|---|---|---|---|
| CPU `nvfortran` (original) | 16.44064122 | -39.87461118 | `NaN NaN NaN NaN` |
| CPU `gfortran` (original) | 17.26374300 | -39.80170195 | 2.84005517 &nbsp;-0.15419963 &nbsp;-0.68997083 &nbsp;-0.15419963 |
| GPU (módulo corregido) | 16.44064122 | -39.87461118 | 2.30428396 &nbsp;-0.15419963 &nbsp;-0.15419963 &nbsp;-0.15419963 |

Tres observaciones que, juntas, confirman que esto **no es un fallo del port**, sino el bug ya conocido manifestándose de tres formas distintas:

1. **Walker 3, `GTEST=T`: el original da `NaN` con `nvfortran` y un valor finito (pero distinto) con `gfortran`**, mientras que la GPU (que usa el módulo `mVheheVphehe` ya corregido con `Vap=0.d0`) da un resultado estable. Leer una variable de pila sin inicializar es comportamiento indefinido: el bit que le toque en memoria depende del compilador, las optimizaciones y el estado previo de la pila — perfectamente compatible con que un compilador vea un patrón de bits que interpreta como `NaN` y el otro vea un número finito cualquiera.
2. **Walkers 1 y 2, `GTEST=T`: el original da valores *finitos pero distintos* entre `nvfortran` y `gfortran`** (`16.44` vs `17.26` en el walker 1, `-39.87` vs `-39.80` en el walker 2) — algo que nunca pasa en `GTEST=F` (donde `Vp_hehe` se calcula pero no se usa) ni en ningún otro kernel de este proyecto sin el bug de `Vap`. Dos compiladores distintos compilando el mismo código fuente sin ningún dato realmente aleatorio de por medio solo pueden dar números distintos si en algún punto se está leyendo memoria sin inicializar.
3. **Dentro del propio walker 3, las componentes `V(2)` y `V(4)` sí coinciden exactamente entre `gfortran` y GPU** (`-0.15419963` en ambas), mientras que `V(1)` y `V(3)` no. Esto encaja con la estructura del cálculo: `V(J3)` es una suma ponderada por `G(J4,J1)` sobre **todos** los pares de átomos (bucle `DUMMY=DUMMY+G(J4,J1)*(...)`); si para este walker solo algunos pares de He cumplen `x` fuera de `[xx1_HeHe,xx2_HeHe]` (los que exponen el bug) y otros no, es esperable que unas componentes de `V` salgan afectadas y otras no.

**Conclusión:** la discrepancia del walker 3 (y las diferencias más pequeñas en los walkers 1 y 2) no delatan ningún error en `He_dihydrogen.f`, `k_He_dihydrogen.cuf` ni en el módulo `mVheheVphehe` — al contrario, confirman que la corrección `Vap=0.d0` aplicada en su día a la versión GPU (§5 de `V_hehe_Vp_hehe.md`) es necesaria y funciona: es precisamente la versión GPU la que da el mismo resultado en todas las ejecuciones, y las dos CPUs con el bug original las que son mutuamente inconsistentes. Sigue pendiente (igual que se dejó anotado en `V_hehe_Vp_hehe.md`) decidir si el fix `Vap=0.d0` se traslada también al `bh_heh2m.f` de producción — aquí no se ha tocado, porque se usa deliberadamente como referencia de CPU "tal cual viene".

---

## Parte 3 — `dexp`/`dcos`/`dsin` sustituidas por `myexp`/`mycos`/`mysin`

Igual que en `V_hehe_Vp_hehe.md` (Parte 3): tras `docs-kernels/glibc_math.md`, se añade `use glibc_exp_mod, only: myexp` / `use glibc_sincos_mod, only: mysin, mycos` y se sustituyen una a una las 20 llamadas a `dexp`/`dcos`/`dsin` de este fichero (`F00` y las tres llamadas de `ENERGY2` usan `myexp`; `atheta`/`btheta`/`c6theta` y sus derivadas usan `mycos`/`mysin`) — ninguna fórmula cambia. También se actualiza la copia de `mVheheVphehe_mod.cuf` reutilizada aquí, ya que `V_hehe`/`Vp_hehe` (de las que depende `He_dihydrogen`) se corrigieron primero (Parte 3 de `V_hehe_Vp_hehe.md`). Referencia de CPU: `Original-VapFix`; flags siempre: `-Kieee -Mnofma` / `-ffp-contract=off`.

### Resultado real: mejora completa en `ENERGY1`, sustancial (no total) en `ENERGY2`/`ENERGY3`

Comparando GPU (con `myexp`/`mycos`/`mysin`) contra `gfortran` puro, a precisión completa:

| | `ENERGY1` | `ENERGY2` | `ENERGY3` |
|---|---|---|---|
| walker 1 | **exacto** | `7.11E-15` | **exacto** |
| walker 2 | **exacto** | `7.11E-15` | `5.68E-14` |
| walker 3 | **exacto** | `8.88E-16` | `3.55E-15` |

`ENERGY1` (que solo usa `V_hehe`/`Vp_hehe`, ya verificadas exactas por separado en `V_hehe_Vp_hehe.md`) da **coincidencia exacta en los tres walkers** — la sustitución elimina del todo su discrepancia. `ENERGY2`/`ENERGY3` (que además de `myexp`/`mycos`/`mysin` tienen sumas de potencias como `a1*(mycos(theta))**2.d0+a2*(mycos(theta))**4.d0+a3*(mycos(theta))**6.d0`) mejoran sustancialmente frente a lo documentado en la Parte 2 (hasta `1.42E-13` sin este cambio) pero **no llegan a cero**: quedan residuos de `~1e-14` a `~1e-15`.

**Por qué no llega a cero del todo:** ya se comprobó que `mycos`/`mysin`/`myexp` en sí mismas coinciden bit a bit con `gfortran` (`glibc_math.md`). El residuo que queda aquí no viene de las funciones transcendentes — viene de la aritmética *alrededor* de ellas (las sumas de potencias, los productos con `rnorm`/`btheta`...), donde `nvfortran` y `gfortran` pueden seguir reordenando/redondeando de forma distinta una expresión con varios términos, incluso con `-Kieee -Mnofma`/`-ffp-contract=off` activas — el mismo tipo de diferencia "no solo FMA" que ya se documentó para `nvfortran` vs. `gfortran` en el binario completo (`docs/v0_Cambios_Compilador.md` §4.4). Perseguir ese último residuo exigiría controlar también el orden de evaluación de sumas con varios términos, no solo qué función calcula cada transcendente.

## Parte 4 — Causa raíz del residuo: reasociación en sumas de varios términos

### 9. Investigación sistemática (bisección real, no en aislado)

Siguiendo el método pedido (confirmar que los pasos previos dan 0, listar variables que afectan a `ENERGY2`/`ENERGY3`, descartar las estáticas, comparar las calculadas contra `gfortran`):

- `V_hehe`/`Vp_hehe` (de las que depende `ENERGY1`, y también `atheta`/`btheta`/`c6theta`... no, en realidad `ENERGY2`/`ENERGY3` no llaman a `V_hehe`/`Vp_hehe`): confirmado exacto por separado, no es la fuente.
- `angle`, `scalar_product`, `vec_norm` (`angle_scalar_vec_mod.cuf`, de donde salen `rnorm`, `onorm`, `theta`, `ror`, `fi`): revisadas — **ya acumulan con sentencias secuenciales dentro de un `DO`** (`sprod=sprod+x1*x2`, etc.), no con una expresión de varios términos en una sola línea. No son la fuente del residuo.
- Quedan como sospechosas las expresiones de varios términos en una sola sentencia dentro de `He_dihydrogen` mismo: `atheta`/`btheta`/`c6theta`, las funciones-sentencia `FN1`/`FN2` (ya identificadas en la Parte 3 de la investigación previa), `Ex0`/`Ey0`/`Ez0` y la propia acumulación `ENERGY2=ENERGY2+...-...` / `ENERGY3=ENERGY3+...+...+...`.
- Bisección con una copia temporal sin `attributes(host,device)` (`He_dihydrogen_dbg.f`, ya eliminada tras el uso) confirmó que `FN1` y `c6theta` divergían de forma distinta según el átomo — es decir, el problema no era una única fórmula sino varias sumas de varios términos repartidas por todo el cuerpo del kernel.

### 10. La causa raíz: funciones-sentencia con varios términos no se pueden forzar a un orden fijo

`FN1`/`DFN1`/`FN2`/`DFN2` (Parte 1, §3) eran **funciones-sentencia** (`FN1(XDUMM)=F0(XDUMM)+F1(XDUMM)+...+F6(XDUMM)`, siete términos). Una función-sentencia es una construcción heredada de Fortran 66/77: solo puede tener **una única expresión**, sin variables locales ni sentencias intermedias — el estándar no da ninguna forma de "trocearla" en pasos, así que el compilador es libre de agrupar los siete sumandos en el orden que prefiera (asociatividad no garantizada en punto flotante: `(a+b)+c ≠ a+(b+c)` en general). Por eso, aunque `gfortran` y `nvfortran` reciban la misma expresión matemática, cada uno puede elegir un árbol de sumas distinto — y sus últimos bits difieren, sin que sea un bug de ninguno de los dos, solo una licencia que el estándar concede.

La solución no es "sumar en varias veces dentro de la función-sentencia" (no se puede: una función-sentencia es una única expresión, no admite `x=x+termino` como sentencias separadas). La solución es **convertirlas en funciones reales** (`FUNCTION`/`END FUNCTION`), donde sí se puede escribir la suma como sentencias secuenciales:

```fortran
attributes(host,device) FUNCTION FN1(XDUMM)
IMPLICIT NONE
DOUBLE PRECISION FN1, XDUMM
FN1=F0(XDUMM)
FN1=FN1+F1(XDUMM)
FN1=FN1+F2(XDUMM)
FN1=FN1+F3(XDUMM)
FN1=FN1+F4(XDUMM)
FN1=FN1+F5(XDUMM)
FN1=FN1+F6(XDUMM)
END FUNCTION FN1
```

Cada `FN1=FN1+F_i(XDUMM)` es una sentencia completa e independiente: el resultado de la suma anterior queda fijado en `FN1` **antes** de que empiece la siguiente suma, así que no hay ninguna expresión de varios términos que el compilador pueda reagrupar — el orden de las siete sumas queda forzado de izquierda a derecha, igual en `gfortran` que en `nvfortran`, tanto en CPU como en GPU. `F00`-`DF6` (que solo tienen 1-2 operaciones, no sumas de varios términos) se dejaron como funciones-sentencia sin cambios, ya que no son ambiguas.

Se aplicó el mismo principio, sin necesidad de convertir a función (ya estaban dentro del cuerpo de `He_dihydrogen`, no compartidas entre subprogramas), a las demás sumas de varios términos: `atheta`, `btheta` (las dos apariciones), `c6theta`, `Ex0`, `Ey0`, `Ez0`, y la acumulación `ENERGY2=ENERGY2+a0*myexp(...)` / `ENERGY2=ENERGY2-FN1(...)*c6theta/...` y `ENERGY3=ENERGY3+Ex0*Ex0` / `+Ey0*Ey0` / `+Ez0*Ez0`, todas partidas en sentencias `x=x+termino` separadas.

### 11. Resultado final: GPU vs. `gfortran`, 8 de 9 exactos bit a bit

Con `FN1`/`DFN1`/`FN2`/`DFN2` convertidas a funciones reales de acumulación secuencial, y `atheta`/`btheta`/`c6theta`/`Ex0`/`Ey0`/`Ez0`/`ENERGY2`/`ENERGY3` partidas en sentencias separadas, comparando GPU (nvfortran, `-Kieee -Mnofma`) contra `gfortran` puro (`-ffp-contract=off`), CPU `Original-VapFix`:

| | `ENERGY1` | `ENERGY2` | `ENERGY3` |
|---|---|---|---|
| walker 1 | **exacto** | **exacto** | **exacto** |
| walker 2 | **exacto** | **exacto** | **exacto** |
| walker 3 | **exacto** | `rel. ~2.97E-16` (≈1 ULP) | **exacto** |

8 de las 9 combinaciones walker×energía coinciden ahora **bit a bit**. Solo queda un residuo de un ULP en `ENERGY2` del walker 3 — muchos órdenes de magnitud por debajo de lo que se había documentado antes de esta ronda (`~1E-14`/`~1E-15`), y sin ninguna fórmula de varios términos identificable ya como sospechosa (todas las sumas relevantes están secuencializadas). Es razonable atribuirlo a un redondeo de última cifra dentro de `myexp`/`FN1` para esa combinación concreta de entradas, no reproducible por reordenación (ya no hay ninguna que aplicar) — y, de nuevo, muchos órdenes de magnitud por debajo del ruido estadístico del DMC.

**Dato adicional, no esperado:** comparando también CPU (nvfortran, backend *host*, mismo binario) contra `gfortran`, el resultado es **peor** que el de GPU vs. `gfortran` (solo 3 de 9 exactos, con residuos de 1 a 3 ULP en el resto) — es decir, el backend *device* de `nvfortran` reproduce el redondeo de `gfortran` mejor que su propio backend *host* para este kernel. Esto confirma que la reasociación de sumas no es solo "GPU vs. CPU": los dos backends del mismo compilador nvfortran (host y device), compilando el mismo fichero con las mismas flags, pueden tratar una expresión de varios términos de forma distinta entre sí — otra razón más para eliminar la ambigüedad en la fuente en vez de perseguir un backend concreto.

## Parte 5 — Dos causas raíz más: `dacos` y `pow` con exponente real

Al preguntar por qué seguía quedando 1 valor sin coincidir tras la Parte 4 (walker 3, `ENERGY2`), se investigó ese caso concreto con la misma rigurosidad — bisección con diagnósticos device→host, no suposiciones — y aparecieron dos causas raíz genuinas más, ninguna relacionada con reasociación.

### 12. `dacos` es una quinta función con implementaciones independientes host/device

Instrumentando `He_dihydrogen` (array de diagnóstico copiado de vuelta al host) para el walker 3, los 4 átomos dieron esto para `theta`:

| átomo | `fi` | ¿especial? |
|---|---|---|
| 1, 2 | `0.0` exacto | sí — `acos(0)` |
| 3 | `-1.0` exacto | sí — borde de dominio |
| 4 | `-0.5773502691896258...` | **no**, ángulo genérico |

Para los átomos 1/2/3 (`fi` en un valor "especial") GPU y host daban `theta` idéntico. Para el átomo 4 (el único con `fi` genérico), con `ror`, `onorm`, `rnorm` y `fi` **bit a bit idénticos** entre host y device, `dacos(fi)` daba resultados distintos: `2.18627603546528393` (host) vs. `2.18627603546528437` (device). Confirmado con las mismas herramientas que en la Parte 1 (`nm -D`, `cuobjdump --dump-ptx`): el `dacos` de host resuelve a `__pd_acos_1@LIBNVCPUMATH_VERSION` (de `libnvcpumath.so`), el de device está compilado en línea (intrínseco de `libdevice`, sin símbolo de librería) — la misma situación que `exp`/`sin`/`cos` antes de portarlas, solo que ningún caso de prueba anterior había tocado un ángulo "genérico" para revelarlo.

**Fix:** se porta `__ieee754_acos` de glibc 2.39 (`sysdeps/ieee754/dbl-64/e_asin.c`, "IBM Accurate Mathematical Library", ~0.523 ULP) como `myacos`, en `glibc_math/glibc_acos.cuf` — documentación completa del puerto (las 8 zonas de tabla, las 3 tablas nuevas `asincos.tbl`/`root.tbl`/`powtwo.tbl`) en `glibc_math.md` Parte 3. Probado en aislado con 26 casos (las 8 zonas, los bordes exactos, y el valor real que falló aquí) — **26/26 exactos** GPU/CPU/`gfortran`. Integrado sustituyendo `dacos` por `myacos` en `angle_scalar_vec_mod.cuf`.

### 13. `**N.d0` (exponente real) llama a `pow()` — sexta función con el mismo problema

Con `dacos` corregido, el residuo de walker 3 se redujo pero no desapareció. Instrumentación más fina (comparando término a término la acumulación de `ENERGY2`, con `FN1`/`c6theta`/`rnorm` ya confirmados idénticos bit a bit) aisló el problema en `eterm2=FN1(rnorm*btheta)*c6theta/rnorm**6.d0`:

```
x**6.d0  (exponente REAL)  ->  HOST=1.72799999999999932E+03   GPU=1.72799999999999955E+03   (DISTINTO)
x**6     (exponente ENTERO) ->  HOST=1.72799999999999932E+03   GPU=1.72799999999999932E+03   (IGUAL)
```

Todo el fichero escribía los exponentes enteros como literales reales (`**2.d0`, `**3.d0`... `**7.d0`) — una costumbre habitual en Fortran heredado, pero que en Fortran fuerza al compilador a usar la exponenciación *general* (`x**y` con `y` real), normalmente implementada vía `pow()`/`exp(y*log(x))`, en vez de la multiplicación repetida que usa `x**n` con `n` entero. `pow()` con exponente real resulta ser una **sexta función con implementaciones independientes** en `libnvcpumath.so` (host) vs. `libdevice` (device) — confirmado con la prueba aislada de arriba, y con `gfortran` coincidiendo con el host de `nvfortran` (`1.72799999999999932E+03`), igual que en todos los casos anteriores.

**Fix:** ya que los exponentes son siempre pequeños enteros conocidos en tiempo de compilación (nunca hace falta `pow()` general aquí), se sustituyeron todas las apariciones de `**N.d0` por `**N` en `He_dihydrogen.f` (`atheta`/`btheta`/`c6theta`, sus derivadas, `eterm2`, `dvdR`, `dvdtheta`) — no fue necesario portar `pow()` de glibc, con exponente entero `x**n` se compila como multiplicación repetida, que es determinista e idéntica en host, device y `gfortran` sin ninguna librería de por medio.

### 14. Resultado final: 8/9 exactos, con el mismo caso "movido" a otro walker

Con `myacos` y los exponentes enteros integrados, el walker 3 (antes el único con residuo) pasó a coincidir **exacto en las 3 energías**. Pero el walker 2/`ENERGY2`, que antes coincidía exacto, pasó a tener un residuo nuevo (`rel. ~1.22E-16`, de nuevo ~1 ULP):

| | `ENERGY1` | `ENERGY2` | `ENERGY3` |
|---|---|---|---|
| walker 1 | **exacto** | **exacto** | **exacto** |
| walker 2 | **exacto** | `rel. ~1.22E-16` (≈1 ULP) | **exacto** |
| walker 3 | **exacto** | **exacto** | **exacto** |

Se investigó este nuevo residuo con la misma herramienta de diagnóstico (`diag_core`, una subrutina `attributes(host,device)` compartida byte a byte entre la prueba de host y el kernel de GPU, para eliminar cualquier riesgo de transcripción). Resultado inesperado: **la reproducción aislada de la fórmula da el valor CORRECTO** (coincide con `gfortran`) tanto en host como en GPU — pero el kernel de producción real (`He_dihydrogen` completo, con todo su código alrededor) da un valor GPU ligeramente distinto para la *misma* entrada.

Esto apunta a una causa distinta de las cinco anteriores (que eran todas cuestión de *qué código fuente se escribe*): aquí, la *misma* expresión, compilada dentro de un kernel con mucho más contexto (más variables vivas, más presión de registros), recibe un tratamiento de optimización distinto por parte de PTXAS (el ensamblador de GPU de NVIDIA, de código cerrado) que cuando se compila en un kernel diminuto y aislado. Es decir: el resultado de una prueba aislada no garantiza el comportamiento del kernel real para esa misma fórmula — la única prueba fiable es siempre el binario de producción completo.

**Actualización (Parte 7): este residuo SÍ se cerró después**, no con flags de compilador (los cinco experimentos de la Parte 6/7 confirman que ninguno lo movía) sino cambiando el algoritmo de acumulación de `ENERGY2` a suma compensada de Kahan — ver §18-20. Se deja el razonamiento original de cierre tal cual, como registro fiel de en qué punto se decidió (correctamente, con la información de entonces) que no había más causas de código que perseguir con las herramientas probadas hasta ese momento.

**Se decide cerrar aquí** (en el momento de escribir esto, antes de la Parte 7). Motivos:
- Se han identificado y corregido **cuatro causas raíz reales y generalizables**: reasociación de sumas de varios términos (funciones-sentencia y expresiones de varios términos, Parte 4), `dacos` como quinta función con implementación host/device independiente (§12), y `pow()` con exponente real como sexta (§13). Las cuatro están corregidas, documentadas, y verificadas en aislado.
- El residuo que queda (walker 2/`ENERGY2`, ~1 ULP) no tiene ya ninguna causa identificable a nivel de código fuente — es una decisión de bajo nivel de PTXAS dependiente del contexto de compilación, fuera del control de las flags disponibles (`-Kieee -Mnofma`/`-gpu=nofma` no cambian el PTX generado para este patrón, confirmado con `cuobjdump --dump-ptx` con y sin `-gpu=nofma`, diff vacío).
- Seguir persiguiéndolo tiene forma de "topo": arreglar un walker concreto puede desplazar el residuo a otro walker/energía, sin garantía de cerrarlo del todo — no es una causa raíz única y estable como las cuatro anteriores.
- 8 de 9 combinaciones exactas bit a bit, y el residuo (~1 ULP) sigue estando muchos órdenes de magnitud por debajo del ruido estadístico del DMC.

**Nota sobre la validación original (`docs/v0_Cambios_Compilador.md`):** esa verificación (CPU-`gfortran` vs. CPU-`nvfortran`, con `-Kieee -Mnofma`, "todo coincide bit a bit") comparó **una única trayectoria Monte Carlo completa** (semilla fija, 10 bloques × 1000 pasos), no una batería de casos aislados — el propio documento lo advierte explícitamente ("el ruido de 1 bit... no llegó a cambiar ninguna decisión... pero no hay garantía de que eso se mantenga en una tirada mucho más larga"). Los casos que sí hemos encontrado divergentes aquí (`dacos` con ángulo genérico, `pow` con exponente real en un `rnorm` concreto) son exactamente el tipo de valor "no especial" que una única trayectoria con semilla fija tiene muchas posibilidades de no visitar nunca — no contradice esa validación, solo confirma que su alcance era una trayectoria concreta, no una garantía general.

## Parte 6 — Confirmación con SASS real: por qué walker2/`ENERGY2` no tiene causa de código

Al revisar `potenbh` (que llama a `He_dihydrogen`) se encontró que `F2`...`F6` (usadas por `FN1`, que alimenta `ENERGY2`) tienen `(XDUMM)**2`...`**6` — exponente entero literal, el mismo patrón que en otros kernels del árbol (`wavefhe3`, `d_uhex4`) sí resultó divergir bajo `-Kieee` en el HOST (llamada a `__pd_powi_1`). Doce operaciones de este tipo alimentan `ENERGY2` (`F2`-`F6`, `DF2`-`DF6`, `atheta`/`btheta`/`c6theta`, `rnorm**6`) y nunca se habían revisado — se decidió comprobarlo a fondo en vez de asumir que el cierre de la Parte 5 seguía siendo válido sin más.

### 15. El experimento: sustituir `**N` por multiplicación explícita, y ver qué pasa

Se sustituyeron las 12 operaciones por multiplicación explícita (`XDUMM*XDUMM`, etc., mismo patrón que en `wavefhe3`) y se repitió la comparación GPU vs. `gfortran`:

| | `ENERGY1` | `ENERGY2` | `ENERGY3` |
|---|---|---|---|
| walker 1 | exacto | exacto | exacto |
| walker 2 | exacto | **sigue divergiendo, valor idéntico bit a bit al de antes del cambio** | exacto |
| walker 3 | exacto | **empieza a divergir** (antes exacto) | exacto |

**El cambio no arregla walker2 y rompe walker3**: 7/9 en vez de 8/9. El valor de walker2/`ENERGY2` en GPU no cambia ni un bit con la sustitución — coherente con que el *device* de nvfortran siempre multiplica directo para `**N` (nunca pasa por `__pd_powi_1`, eso solo ocurre en el *host* bajo `-Kieee`, ver `wavef.md` §10), así que el cambio no podía tocarlo. Y sin embargo walker3 sí cambia — la prueba misma de que el efecto es indirecto, no de la fórmula tocada.

### 16. Evidencia SASS: mismo número de instrucciones aritméticas, registros reasignados desde el principio de la función

Para no quedarse en la explicación plausible, se comparó el ensamblador real generado por PTXAS (`cuobjdump --dump-sass`, con `-gpu=lineinfo -O3`) de las dos versiones para la función `He_dihydrogen` completa (~18000 líneas de SASS cada una):

- **Recuento de instrucciones aritméticas de doble precisión, idéntico entre las dos versiones**: `DADD`=948, `DFMA`=985, `DMUL`=997, `FFMA`=130 en ambas. La forma de fusionar multiplicación+suma no cambia.
- **La versión con multiplicación explícita tiene 152 `MOV` y 77 `IMAD` de más** — tráfico de registros/direccionamiento, no aritmética nueva.
- **Diff instrucción a instrucción**: la primera divergencia aparece en el preámbulo de la función, en el volcado a pila de los registros que llevan los contadores de los bucles `DO J1=1,N` — **antes de que se ejecute una sola línea de `atheta`/`F2`-`F6`**. A partir de ahí, valores que en una versión viven en `R70`/`R71` viven en la otra en `R62`/`R63`, y así sucesivamente durante el resto de la función.
- **`-gpu=nofma` no cambia el resultado numérico** en ninguna de las dos versiones (mismos 9 valores bit a bit con y sin el flag) — descarta que sea específicamente el fundido FMA activándose/desactivándose; es la asignación de registros y la planificación de instrucciones de PTXAS, sensibles al código fuente que rodea a la expresión, no al fundido en sí.

**Conclusión**: el residuo de walker2/`ENERGY2` no tiene ninguna causa a nivel de código fuente que se pueda corregir escribiendo la expresión de otra forma — cualquier cambio, incluso en una parte no relacionada del fichero, puede desplazar qué registro guarda qué valor y, con ello, el orden exacto de acumulación de una suma en coma flotante (no asociativa) en un bucle completamente distinto. Es una confirmación de bajo nivel, con SASS real, de lo que la Parte 5 ya concluía por descarte: no hay más causas raíz de código que perseguir aquí.

**Se revierte el cambio de las 12 operaciones `**N`** (no mejora nada, y empeora ligeramente el recuento de exactas) — `He_dihydrogen.f` queda tal como estaba al cierre de la Parte 5.

### 17. Cuantificando el spill de registros con `-gpu=ptxinfo`, y el experimento de forzar FMA en la CPU

**a) `-gpu=ptxinfo`** (equivalente en `nvfortran` de `-Xptxas -v`) da el tamaño real de pila y bytes de *spill* (registros que no caben en el banco de registros y se vuelcan a memoria local/pila) por función:

```
mhe_dihydrogen_he_dihydrogen_ (funcion principal):
  version A (**N):          8184 bytes stack frame, 912 bytes spill stores, 1016 bytes spill loads
  version B (multiplicacion): 8184 bytes stack frame, 912 bytes spill stores, 1016 bytes spill loads   <- IDÉNTICO

mhe_dihydrogen_fn1_/dfn1_ (version standalone, sin inlinear):
  version A: 96/84/84 y 120/100/100 bytes (stack/spill-store/spill-load)
  version B: 88/76/76 y 112/92/92 bytes   <- 8 bytes MENOS de spill en cada una
```

Esto matiza (y precisa) la Parte 6: **el volumen total de spill de la función principal no cambia ni un byte** entre las dos versiones — no es que la versión con multiplicación explícita presione más el banco de registros en conjunto. Lo que confirma el diff de SASS (§16) es que, con el mismo presupuesto de spill, PTXAS **reparte qué valor va a cada registro/hueco de pila de forma distinta** — por ejemplo, las instrucciones de guardado iniciales:

```
Version A: STL [R1+0x1e78],R69   STL [R1+0x1e74],R68   STL [R1+0x1e70],R63   STL [R1+0x1e6c],R62
Version B: STL [R1+0x1e80],R71   STL [R1+0x1e7c],R70   STL [R1+0x1e78],R69   STL [R1+0x1e74],R68
```
(offsets de pila reales, tomados de `cuobjdump --dump-sass`, antes de que se ejecute una sola línea de `atheta`/`F2`-`F6`). Es aquí, en el preámbulo de la función, donde queda constancia física de que los dos compilados asignan los mismos huecos de pila a variables distintas — el mecanismo mecánico detrás del cambio de walker3.

**Límite honesto de esta comprobación**: se intentó correlacionar estas instrucciones con la línea fuente exacta (`-gpu=lineinfo` + `nvdisasm -g` sobre el cubin extraído) para señalar la instrucción concreta de `ENERGY2=ENERGY2+eterm1`, pero esta combinación de herramientas (`nvfortran`+`cuobjdump`+`nvdisasm`, en esta instalación) no genera una tabla de líneas utilizable — no se puede afirmar con certeza cuál es, instrucción por instrucción, la suma que cambia de orden dentro del bucle `DO J1=1,N`. Lo que sí está confirmado con evidencia dura es el mecanismo (reasignación de registros con presupuesto de spill idéntico) y el efecto final (walker2/`ENERGY2` no cambia, walker3 sí) — no la línea de código SASS exacta donde ocurre la reordenación de la suma.

**b) Forzar FMA en la CPU** (`gfortran -O2 -mfma -ffp-contract=fast`, frente al control `-O2 -ffp-contract=off`): confirmado que el flag SÍ tiene efecto real — `ENERGY1` (que usa `V_hehe`/`Vp_hehe`) cambia de valor con FMA forzado. Pero **`ENERGY2`/`ENERGY3` no cambian ni un bit**, con o sin FMA forzado en la CPU, y `gfortran`-con-FMA sigue sin coincidir con el valor de GPU en walker2. Combinado con que `-gpu=nofma` tampoco cambia nada en la GPU (§16): la variable que decide este residuo concreto no es "FMA sí/no" en ninguno de los dos lados — es más específico, consistente con la reasignación de registros de (a).

## Parte 7 — Cierre definitivo: suma compensada de Kahan

### 18. Resumen de todos los experimentos de bisección probados

Antes de llegar a la solución, se descartaron sistemáticamente cinco hipótesis con experimentos directos (no por intuición):

| Hipótesis / variable probada | Experimento | Resultado | Conclusión |
|---|---|---|---|
| Exponente entero literal (`**N`) sin `mypow` | `F2`-`F6`/`atheta`/`btheta`/`c6theta`/`rnorm**6` reescritas con multiplicación explícita (§15) | GPU walker2 no cambia ni un bit; walker3 (antes exacto) empieza a divergir — 7/9 en vez de 8/9 | Descartado: no es la fórmula `**N`; el cambio solo desplaza el residuo por reasignación de registros |
| Uso de FMA (`DFMA`) | CPU: `gfortran -O2 -mfma -ffp-contract=fast` · GPU: `-gpu=nofma` (§16, §17b) | Cero cambio en `ENERGY2`/`ENERGY3` en ambos sentidos (aunque el flag de CPU sí es efectivo, cambia `ENERGY1`) | Descartado: no es la presencia/ausencia de fusión multiplicación-suma |
| Límite de registros | GPU: `-gpu=maxregcount:255` (§17, respuesta a este hilo) | Cero cambio (`8184/912/1016` bytes, idéntico al default) | Descartado: la GPU ya usaba, de facto, el máximo práctico de registros del chip (SM 8.9); no había límite artificial que subir |
| Optimizador y volumen de *spill* | GPU: `-Xptxas -O1` | *Spill* bajó un 40% (`912→544`/`1016→584` bytes, confirmado con `-gpu=ptxinfo`) pero **0 bits de cambio** en `ENERGY2`/`ENERGY3` | Descartado: la deriva no depende de cuánta memoria local se use, solo de cómo se reparte |
| Reasignación de registros (mecanismo) | Diff de SASS instrucción a instrucción, versión `**N` vs multiplicación (§16) | Mismo número exacto de `DFMA`/`DMUL`/`DADD`/`FFMA`; registros distintos desde el preámbulo de la función (`STL` a offsets de pila distintos) | Confirmado como mecanismo, pero sin remedio a nivel de flags de compilador — hacía falta actuar sobre el propio algoritmo |

Los cinco experimentos coinciden en lo mismo: **ningún ajuste de compilador (ni en CPU ni en GPU) mueve el resultado**. La única variable que sí lo hace es el **algoritmo de acumulación** en sí.

### 19. La solución: suma compensada de Kahan en `ENERGY2`

Se sustituye la acumulación simple (`ENERGY2=ENERGY2+eterm1` / `ENERGY2=ENERGY2-eterm2`, dentro de `DO J1=1,N`) por suma de Kahan, que guarda en una variable auxiliar (`c_e2`) el error de redondeo de cada paso y lo reintroduce en el siguiente — la hace insensible al orden exacto en que se sumen los términos, que es justo la variable que ninguno de los cinco experimentos anteriores conseguía controlar:

```fortran
       eterm1=a0*myexp(atheta-rnorm*btheta)
       eterm2=FN1(rnorm*btheta)*c6theta/rnorm**6
       y_e2=eterm1-c_e2
       t_e2=ENERGY2+y_e2
       c_e2=(t_e2-ENERGY2)-y_e2
       ENERGY2=t_e2
       y_e2=-eterm2-c_e2
       t_e2=ENERGY2+y_e2
       c_e2=(t_e2-ENERGY2)-y_e2
       ENERGY2=t_e2
```
(`c_e2=0.d0` inicializado justo antes del `DO J1=1,N`, junto con `ENERGY2=0.d0`).

**Primera comprobación, con cautela**: se probó primero aplicando Kahan a la vez en `He_dihydrogen.f` (el puerto) y en una copia de prueba de `bh_heh2m.f` (la referencia) — cerraba exacto, pero eso no demuestra nada por sí solo si hace falta tocar la referencia "intocable" para conseguirlo. **Segunda comprobación, la que cuenta**: se repitió comparando GPU-con-Kahan contra `bh_heh2m.f` **completamente sin modificar** (el original de verdad) — y coincide exacto igualmente. El cambio en la copia de la referencia resultó ser un no-operación numérica (la suma de solo 4 términos de `gfortran` ya coincidía con el resultado compensado, sin necesitar el cambio) — así que **el arreglo real es solo en el fichero portado, `He_dihydrogen.f`, sin tocar ningún fichero de referencia**.

### 20. Resultado final: 9/9 exacto con `-Kieee -Mnofma`

Repetida la batería completa (3 walkers × `ENERGY1`/`ENERGY2`/`ENERGY3`, `GTEST=.false.`, GPU vs. `gfortran` sobre `bh_heh2m.f` sin tocar):

| walker | `ENERGY1` | `ENERGY2` | `ENERGY3` |
|---|---|---|---|
| 1 | exacto | exacto | exacto |
| 2 | exacto | **exacto** (antes divergía) | exacto |
| 3 | exacto | exacto | exacto |

**9/9 exactas bit a bit** — el residuo de walker2/`ENERGY2` que sobrevivió a `myacos`, `mypow`, la secuencialización de `FN1`/`FN2`, y los cinco experimentos de la §18, queda cerrado.

**Sin flags** (`-Kieee -Mnofma` quitadas): aparecen residuos nuevos, pequeños (`~1E-15`, unas pocas ULP — incluido ahora en walker1/`ENERGY1`, como efecto colateral de que las variables nuevas de Kahan cambian la presión de registros de toda la función también sin flags). Es el mismo patrón "cierra con flags" ya visto en el resto del árbol — no es una regresión ni un problema nuevo, es la primera vez que se prueba esta parte sin flags con Kahan de por medio, y sigue el mismo comportamiento esperado.

**Aplicado a `He_dihydrogen.f`** (y sincronizado en la copia de `potenbh/`). No se toca `bh_heh2m.f` en ningún sitio del repositorio — sigue siendo la referencia original intacta.

## Parte 8 — `vpot`: un residuo nuevo, mismo apellido pero distinta causa

### 21. Copias obsoletas encontradas en `potenbh/` y `vpot/`

Al retomar la verificación de los kernels que dependen de `He_dihydrogen` (`potenbh`, `vpot`), se encontró que **las copias de `He_dihydrogen.f`/`angle_scalar_vec_mod.cuf`/`mVheheVphehe_mod.cuf` en ambas carpetas estaban obsoletas** — la de `vpot/` en particular era la versión *anterior a toda esta investigación* (funciones-sentencia `F00`...`DFN2`, `dexp`/`dcos`/`dsin`, sin secuenciar, sin Kahan). Se refrescan desde `He_dihydrogen/` (fuente actual) en las dos carpetas.

### 22. `vpot` (3 walkers, `es24.17`): 2/3 exacto, un residuo nuevo en walker2

Con las copias ya al día, `test_vpot` (GPU vs. `gfortran`, `-Kieee -Mnofma`) da walker1/3 exactos y **walker2 con un residuo de `~3E-16` relativo (1-2 ULP)**, que no cierra con flags. Como `ccuerpo` (ya probado, siempre exacto) alimenta a `potenbh`→`He_dihydrogen`, y el residuo de walker2/`ENERGY2` de la Parte 7 ya estaba cerrado (verificado 9/9 con Kahan), surge la pregunta obvia: **¿es el mismo residuo reaparecido, o uno distinto?**

### 23. Trazado: la geometría de `vpot` es distinta, y el punto de origen también

Se reconstruye a mano el `rhe` que `ccuerpo` genera para el walker2 de `vpot` (aplicando el mismo algoritmo, en Python) y se alimenta directamente a `He_dihydrogen` con `GTEST=.false.`, desglosando `ENERGY1`/`ENERGY2`/`ENERGY3` por separado (subrutina de diagnóstico aparte, no se toca la real):

```
ENERGY1: CPU=GPU=gfortran, exacto
ENERGY2: CPU=1.36406050562424337E+01  GPU=1.36406050562424479E+01  gf=1.36406050562424301E+01  <- las 3 distintas
ENERGY3: CPU=GPU=gfortran, exacto
```

Confirmado: **es `ENERGY2` otra vez**, pero en una geometría completamente distinta a los 3 walkers de `test_He_dihydrogen.cuf` — no el mismo caso reaparecido, sino una ocurrencia nueva de la misma familia.

**Primer experimento (control): ¿es de nuevo un problema de orden de suma?** Se probó `treesum` en vez de `kahansum` para este caso — **da el resultado idéntico bit a bit** al de `kahansum` (`GPU=1.36406050562424479E+01` en los dos). Que dos algoritmos de suma estructuralmente distintos (árbol binario vs. compensación de Kahan) den exactamente el mismo resultado es la prueba de que **esta vez el problema no está en el orden de acumulación** — está en otro sitio, dentro del cálculo de cada término.

### 24. Aislamiento átomo a átomo: `atheta` y `eterm2`, no la suma

Se instrumenta una subrutina de diagnóstico (`He_dihydrogen_diag`, temporal, solo para esta investigación) que expone `rnorm`/`theta`/`atheta`/`btheta`/`c6theta`/`eterm1`/`eterm2` **por átomo**, en vez de solo la suma final, para los 4 átomos del walker2 de `vpot`, comparando host-nvfortran vs. device-nvfortran (mismo binario, mismo `-Kieee`):

| átomo | `rnorm` | `theta` | `atheta` | `btheta` | `c6theta` | `eterm1` | `eterm2` |
|---|---|---|---|---|---|---|---|
| 1 | exacto | exacto | **diverge** | exacto | exacto | exacto | **diverge** |
| 2 | exacto | exacto | exacto | exacto | exacto | exacto | **diverge** |
| 3 | exacto | exacto | **diverge** | exacto | exacto | exacto | exacto |
| 4 | exacto | exacto | exacto | exacto | exacto | exacto | **diverge** |

Dos focos, no uno: `atheta` diverge en los átomos 1 y 3; `eterm2` diverge en los átomos 1, 2 y 4. `rnorm`/`theta`/`btheta`/`c6theta` — pese a compartir la misma fórmula que `atheta` en el caso de `btheta`, o el mismo tipo de cálculo que `eterm2` — están exactos en los 4 átomos: la divergencia no es sistemática, depende del valor concreto de entrada.

**Nota metodológica**: la primera comprobación de `atheta` en aislado dio "exacto" por error — se habían copiado a mano las constantes `a1`/`a2`/`a3` equivocadas (las de `der_wavefx`, no las reales de `He_dihydrogen`, que están en `param_atoms_bh.h`: `a0=65344.8145, a1=-0.42497, a2=3.95634, a3=0.07852`). Repetido con las constantes correctas, `atheta` sí diverge — se documenta el error para que quede constancia de que "no reproduce en aislado" solo es válido si la reproducción usa los datos reales, no una aproximación de memoria.

### 25. Primera hipótesis (`__pd_powi_1`, exponente entero) — comprobada, y luego corregida

`eterm2=FN1(rnorm*btheta)*c6theta/rnorm**6` y `atheta=a1*(mycos(theta))**2+...` tienen el mismo patrón superficial: `**N`. Se sospechó primero el mismo mecanismo que en `wavef.md` §10 (`__pd_powi_1` en host bajo `-Kieee` vs. multiplicación directa en device) — confirmado en aislado que `rnorm**6` diverge host-vs-device en los átomos 1,2,4, y `(mycos(theta))**2/4/6` en los átomos 1,3. Se corrigió con multiplicación explícita, y **arregló el caso de `vpot`** (CPU=GPU exacto), a costa de mover un ULP a walker3 de la batería original (8/9 en vez de 9/9).

**Pero antes de dar esto por bueno, se revisó si `**N` seguía dando problemas en algún otro punto no tocado — y apareció un hallazgo mucho más de fondo.**

### 26. El hallazgo real: el exponente en el ORIGINAL es REAL (`.d0`), no entero — la multiplicación explícita replicaba la semántica equivocada

Revisando **todos** los `**N` de `bh_heh2m.f` (la referencia intacta) con `grep`, se encontró que **absolutamente todos** los de `atheta`/`btheta`/`c6theta`/`rnorm**6`/`rnorm**7` (y sus derivadas, en la rama `GTEST`) usan exponente **real literal** (`2.d0`, `3.d0`, `4.d0`, `5.d0`, `6.d0`, `7.d0`), nunca entero. Eso invoca `pow()` de verdad (vía `exp(y·log(x))`), un algoritmo distinto tanto de la potencia entera (`__pd_powi_1`/repeated-squaring) como de la multiplicación explícita.

Comprobado directamente: `mypow(rnorm, 6.0d0)` da **`1.72799999999999932E+03`**, exacto contra `gfortran` (`rnorm**6.d0` real); la multiplicación explícita daba **`1.72799999999999955E+03`** — **un valor distinto de los dos**. La multiplicación "arreglaba" `vpot` por coincidencia (dos aproximaciones erróneas cancelándose), no porque replicara el algoritmo correcto.

**Origen del error**: `He_dihydrogen.f` (el fichero portado) ya tenía `**6` (entero, sin `.d0`) desde **antes de esta sesión** — en algún porteo anterior se perdió el `.d0` en todo el fichero, silenciosamente cambiando la semántica de "potencia real" a "potencia entera" en más de 20 sitios. Ninguna de las dos correcciones de hoy (potencia entera heredada, o mi multiplicación) replicaba lo que el original calcula de verdad.

### 27. Corrección de fondo: `mypow` en los ~20 sitios con exponente real, y un segundo bug encontrado al aplicarla

Se revierte la multiplicación y se sustituyen **todos** los `**N` con `.d0` en el original por `mypow(x, N.0d0)` — en `atheta`/`btheta` (`ENERGY2` y su copia en `ENERGY3`), `c6theta`, `eterm2`, y toda la rama `GTEST` (`datheta`/`dbtheta`/`dc6theta`, `dvdR`, `dvdtheta`) — usando el `mypow` ya portado y validado bit a bit contra `pow()` real (`glibc_math.md` Parte 4).

**Al compilar y ejecutar, `ENERGY2`/`ENERGY3` dieron `NaN` en GPU** (no en host). Causa: `mypow` está **deliberadamente restringido a base > 0** — en todos sus usos anteriores en el proyecto la base era `rij`, una distancia, siempre positiva; nunca hizo falta portar la rama `x<0` de `pow()` (documentado explícitamente así en `glibc_math.md`/`d_uhex4.md`). Pero aquí la base es `mycos(theta)`/`mysin(theta)`, que **sí pueden ser negativos** — fuera del dominio soportado, produciendo `NaN` vía `log(negativo)`.

**Corrección**: para exponentes pares (2,4,6) se usa `mypow(abs(x), N.0d0)` — matemáticamente exacto, ya que `(-a)^{2n}=a^{2n}` para cualquier real `a`. Para los exponentes impares (3,5), solo en la rama `GTEST` (`datheta`/`dbtheta`/`dc6theta`), se reintroduce el signo: `SIGN(1.d0,x)*mypow(abs(x), N.0d0)`. `rnorm` no necesita esto (siempre positivo, distancia física).

### 28. Resultado final

**`vpot`**: `NaN` desaparece, **CPU(host)=GPU(device) exacto** para el caso que antes divergía (`ENERGY2=1.36406050562424337E+01` en las dos vías) — el bug de dominio/algoritmo queda cerrado. Frente al `gfortran` real (sin tocar): queda un residuo de `~1.4E-14` (`~1.6E-16` relativo, ~1 ULP) en `vpotbh` — mismo `nvfortran`(host=device) vs. `gfortran`, no host-vs-device — de la misma categoría de suelo ya aceptada en el resto del árbol.

**Batería original (3 walkers, GPU vs. `gfortran`, `-Kieee -Mnofma`):**

| walker | `ENERGY1` | `ENERGY2` | `ENERGY3` |
|---|---|---|---|
| 1 | exacto | exacto | exacto |
| 2 | exacto | **diverge** (el original, antes de cualquier arreglo de hoy) | exacto |
| 3 | exacto | exacto | exacto |

**8/9** — walker2 vuelve a ser el que diverge (como en el cierre original de la Parte 5, antes de Kahan), no walker3. El residuo de `ENERGY2`/walker2 no tiene ya ninguna causa de código identificable: `rnorm`/`theta`/`atheta`/`btheta`/`c6theta`/`eterm1` confirmados exactos por separado (§24 revisado con las constantes y la fórmula correctas), y `eterm2` — el único que queda — ya usa el algoritmo correcto (`mypow`) verificado exacto en aislado para valores sueltos. Es, de nuevo, el suelo de PTXAS/redondeo de bajo nivel, no un error de fórmula.

### 29. Lo que se descarta y lo que queda como corrección real

- ❌ **Descartado**: multiplicación explícita para `rnorm**6`/`atheta` — replicaba potencia entera, no la potencia real que el original calcula. Revertido.
- ✅ **Aplicado**: `mypow(x, N.0d0)` en los ~20 sitios con exponente real heredados del original, con `abs()`/`SIGN()` para las bases que pueden ser negativas (`mycos`/`mysin`, a diferencia de `rnorm`).
- ✅ Corrige de fondo un error de porteo **anterior a esta sesión** (exponente entero en vez de real), no solo un problema de reasociación — el port se acerca más al algoritmo real del original en todo el fichero (rama `GTEST` incluida, aunque `potenbh`/`vpot` solo ejercitan `GTEST=.false.`).
- El residuo de walker2/`ENERGY2` (8/9) es el mismo tipo de suelo ya documentado en el resto del árbol — no se persigue más.

**Aplicado a `He_dihydrogen.f`, sincronizado en `potenbh/` y `vpot/`** (además, `glibc_pow.cuf`/`pow_log_tab_fortran.txt` copiados a las dos carpetas — nueva dependencia).

### 30. El residuo de `vpot` frente a `gfortran` (§28): de dónde viene exactamente, con evidencia

Cabía la duda razonable de si el `~1E-14` que queda en `vpot` frente a `gfortran` (tras cerrar el bug de dominio de §27) fuera, después de todo, un fallo de `mypow` — ya que `mypow` se construyó y validó específicamente para reproducir `pow()` bit a bit. Se comprobó paso a paso, con los 4 átomos del caso de `vpot`, en vez de asumir que era "el mismo suelo de siempre":

**`atheta`, `btheta`, `c6theta`, `FN1(rnorm·btheta)`, `eterm1`, `eterm2` — los 6 valores, en los 4 átomos (24 comparaciones) — coinciden exactos bit a bit entre `nvfortran` y `gfortran`.** `mypow` no es la causa: reproduce `pow()` perfectamente aquí, como en todos los casos anteriores.

**La causa real**: con los mismos 8 valores exactos de `eterm1`/`eterm2` (uno por átomo), sumarlos con acumulación secuencial simple (`ENERGY2=ENERGY2+eterm1-eterm2` dentro del bucle — el algoritmo del `bh_heh2m.f` original, nunca tocado) da **`1.36406050562424301E+01`** en `gfortran` **y en `nvfortran`** — coinciden exactos. Sumar los mismos 8 valores con `treesum`/`kahansum` (la corrección de la Parte 7, deliberada, para cerrar el walker2 *original*) da **`1.36406050562424337E+01`** — distinto.

**Conclusión**: el residuo no es un fallo de ningún componente — es el precio de haber cambiado el algoritmo de suma. Kahan/árbol binario hacen la acumulación insensible al *orden* de suma (lo cual cerró el walker2 original, afectado por reasignación de registros de PTXAS), pero como cualquier cambio de algoritmo de suma, con las mismas entradas exactas puede dar un último bit distinto al de la acumulación secuencial simple que `gfortran` sigue usando. No hay contradicción: **cada pieza de la cadena es correcta y bit-exacta; es la combinación de piezas (qué algoritmo de suma) lo que determina el último bit**, y ese último bit no tiene un único valor "correcto" objetivo cuando el propio estándar IEEE754 no garantiza asociatividad.
