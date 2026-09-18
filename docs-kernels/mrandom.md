# Decimosexto kernel: `mrandom` (generador de números aleatorios)

Documentación de [`v1-cuda-desarrollo/mrandom/rand_gpu.cuf`](../mrandom/rand_gpu.cuf). Porta `rand1`/`rand1p` de [`mrandom2.f90`](../mrandom/mrandom2.f90) y `rn1`/`randv3`/`gauss3`/`fijasemilla` de [`mrandom.f90`](../mrandom/mrandom.f90), con un cambio de arquitectura de fondo (no solo de sintaxis) explicado en la Parte 1.

---

## Parte 1 — Por qué no es una transcripción directa

## 1. En la CPU, todos los walkers comparten una única secuencia

`irn` es una variable de módulo (`private, save`) en `mrandom.f90` — **una sola** semilla compartida por todos los walkers, que se procesan en un bucle secuencial (`msteps.f90`: `pasodmc`/`dmc2`/`pasomet`, `do iwalker=1,nwpaso`). Cada walker consume un número de sorteos que **depende de datos**: `dmc2` tiene varios `return` anticipados (test de aceptación de signo, `wftest<ratio`) que se saltan sorteos posteriores según el resultado de cálculos que a su vez dependen de sorteos anteriores. La posición exacta de cada walker dentro de la secuencia compartida solo se conoce ejecutando en orden, walker a walker.

En la GPU los walkers se procesan en paralelo, no en orden — no se puede reproducir esa secuencia entrelazada sin serializar. Esto se planteó explícitamente al usuario antes de empezar el port (ver discusión previa a este documento): **la trayectoria completa GPU no va a coincidir número a número con una ejecución CPU en serie**, independientemente de qué mecanismo se use para repartir semillas. Eso no es un defecto del port — es una consecuencia estructural de paralelizar un algoritmo con estado compartido secuencial.

## 2. Solución adoptada: `irn` explícito por walker, repartido con el mismo mecanismo que ya usa el código para MPI/PVM

Dado que la reproducción número-a-número de la CPU en serie no es alcanzable, cada walker de GPU recibe su **propio** estado `irn`, pasado como argumento explícito (`intent(inout)`) en vez de la variable de módulo compartida — mismo patrón de AoS→SoA ya usado en todo el árbol para el resto del estado del walker.

Para decorrelacionar esos estados iniciales, se decidió (elección explícita del usuario, no Philox) reutilizar el **mismo mecanismo que ya usa el código original para repartir semillas entre procesos MPI/PVM** (`mmpi.f90:129-142`, `distribuyesemillas`):

```fortran
call sacasemilla(irnpar)
do icpar=1,size-1
   call rand1p(rn,irnpar)
   if(rank.eq.icpar) call fijasemilla(irnpar)
enddo
call rand1p(rn,irnpar)
if(soydire) call fijasemilla(irnpar)
```

Es decir: el proceso de rango `icpar` recibe la semilla maestra tras aplicar `rand1p` (el **segundo** LCG de 48 bits de `mrandom2.f90`, distinto de `rand1` — el original ya lo reserva específicamente para repartir semillas, nunca para generar números de la simulación) `icpar` veces. `k_split_seeds` generaliza esto de "índice de proceso" a "índice de walker": la semilla del walker `iw` es `rand1p` aplicado `iw` veces a partir de una única semilla maestra. Cada hilo de GPU calcula su propia semilla de forma independiente, iterando desde el mismo punto de partida — sin dependencia entre hilos, coste O(n) por hilo (aceptable: se ejecuta una sola vez, al iniciar la simulación).

Se descartó Philox explícitamente: aunque es el estándar en DMC/QMC sobre GPU y más robusto estadísticamente que iterar un LCG, no reproduciría el mismo reparto que ya usa el código para MPI/PVM, y ya que la reproducción número-a-número de la trayectoria completa no es alcanzable de todas formas, se prefirió reutilizar el mecanismo existente antes que introducir uno nuevo sin precedente en este proyecto.

## 2bis. El código, antes y después

**Antes** (`mrandom.f90`): `irn` es una variable de módulo, `private, save` — un único número entero que vive fuera de cualquier función, compartido por todo el programa. `rn1()` no recibe ningún argumento: lee y modifica esa variable compartida por su cuenta, de forma implícita.

```fortran
module mrandom
  ...
  integer(kind=i8), private, save :: irn = 1_i8   ! <-- una sola semilla, para TODOS los walkers
 contains
  function rn1()
   real(kind=r8) :: rn1
    call rand1(rn1,irn)   ! <-- lee y modifica la irn compartida, sin recibirla como argumento
  end function rn1

  subroutine gauss3(gvar3)
   real(kind=r8), intent (out) :: gvar3(3)
   real(kind=r8) :: xl,arg
    arg=2.0_r8*pi*rn1()          ! <-- cada llamada a rn1() toca la MISMA irn de todos
    xl=sqrt(-2.0_r8*log(rn1()))
    gvar3(1)=xl*sin(arg)
    ...
```

Esto funciona en la CPU porque los walkers se procesan uno detrás de otro (bucle secuencial): cada llamada a `rn1()` avanza la única `irn` que existe, y el walker siguiente continúa exactamente donde lo dejó el anterior. Si dos walkers se ejecutaran **a la vez** y ambos llamaran a `rn1()`, los dos leerían/escribirían la misma `irn` sin ningún orden definido entre ellos — una carrera de datos, resultado no determinista y no reproducible.

**Después** (`rand_gpu.cuf`): `irn` deja de existir como variable de módulo. Pasa a ser un **argumento** (`intent(inout)`) de cada función — cada walker trae su propia copia, la modifica, y se la lleva, sin tocar la de ningún otro walker:

```fortran
module mrandgpu
  ...
  ! ya no hay ninguna "irn" declarada aqui a nivel de modulo
 contains
  attributes(host, device) subroutine rn1_gpu(irn, rn)
    integer(kind=i8), intent (inout) :: irn   ! <-- la semilla de ESTE walker, recibida como argumento
    real(kind=r8), intent (out) :: rn
      call rand1_gpu(rn, irn)
  end subroutine rn1_gpu

  attributes(host, device) subroutine gauss3_gpu(irn, gvar3)
    integer(kind=i8), intent (inout) :: irn   ! <-- misma idea: entra y sale por argumento
    real(kind=r8), intent (out) :: gvar3(3)
    real(kind=r8) :: xl, arg, rn
      call rand1_gpu(rn, irn); arg = 2.0_r8*pi*rn
      call rand1_gpu(rn, irn); xl = sqrt(-2.0_r8*log(rn))
      gvar3(1) = xl*mysin(arg)
      ...
```

Cada hilo de GPU (walker) llama a `gauss3_gpu` con **su propia variable `irn`** (declarada en su propio ámbito, no compartida) — dos hilos ejecutándose a la vez no se pisan porque cada uno lee y escribe una copia de memoria distinta. Es exactamente el mismo cambio de patrón que ya se aplicó en todo el árbol para el resto del estado del walker (AoS→SoA: lo que antes era un campo dentro de un único `type(walker) :: w1` implícito pasa a ser un argumento explícito por walker).

**El reparto de semillas iniciales**, para que cada walker no arranque con la misma `irn` (si no, generarían los mismos números):

```fortran
attributes(global) subroutine k_split_seeds(n, irnin, seeds)
  integer(kind=i4), value :: n
  integer(kind=i8), value :: irnin              ! <-- una unica semilla maestra, la misma para todos
  integer(kind=i8), device, intent (out) :: seeds(n)
  integer(kind=i8) :: irn
  real(kind=r8) :: rn
  integer(kind=i4) :: i, iw

  iw = (blockIdx%x - 1) * blockDim%x + threadIdx%x   ! <-- indice de este walker/hilo
  if (iw <= n) then
    irn = irnin
    do i = 1, iw
      call rand1p_gpu(rn, irn)    ! <-- rand1p (el 2o LCG) aplicado "iw" veces, solo por este hilo
    enddo
    seeds(iw) = irn               ! <-- la semilla propia de este walker, ya distinta de las demas
  endif
end subroutine k_split_seeds
```

Cada hilo `iw` parte de la **misma** semilla maestra `irnin`, pero le aplica `rand1p` un número de veces **distinto** (`iw` veces) — así el walker 1 acaba con una semilla, el walker 2 con otra, etc., y cada hilo lo calcula por su cuenta, sin esperar ni depender de los demás hilos. Es el mismo mecanismo, generalizado de "índice de proceso" a "índice de walker", que `distribuyesemillas` (§2) ya usaba para repartir semillas entre procesos MPI/PVM — no es un algoritmo nuevo, es reutilizar uno que el proyecto ya tenía para exactamente este propósito (dar semillas distintas a ejecuciones paralelas).

Con esto, el flujo completo para `nwalkers` walkers en GPU es: (1) `k_split_seeds` una vez, al principio, da una semilla a cada walker; (2) cada walker guarda su `irn` junto al resto de su estado (igual que guarda `atom`, `sprop`, etc.); (3) en cada paso de la simulación, cada walker llama a `gauss3_gpu(su_irn, ...)`/`rn1_gpu(su_irn, ...)` con su propia semilla, que se va actualizando paso a paso, sin ninguna interacción con los demás walkers.

---

## Parte 2 — Implementación

## 3. `rand1`/`rand1p`: aritmética entera pura, sin ningún riesgo de ULP

```fortran
attributes(host, device) subroutine rand1_gpu(rn, irn)
  integer(kind=i8), intent (inout) :: irn
  real(kind=r8), intent (out) :: rn
  ...
   is2=iand(ishft(irn,-24_i8),mask24)
   is1=iand(irn,mask24)
   irn=iand(ishft(iand(is1*m12+is2*m11,mask24),24_i8)+is1*m11+iadd1,mask48)
   rn=ior(irn,1_i8)*twom48
end subroutine rand1_gpu
```

Transcripción literal de `mrandom2.f90`, solo con `attributes(host,device)` añadido — `iand`/`ishft`/multiplicación entera de 64 bits, operaciones que el estándar IEEE (para enteros, simplemente aritmética modular exacta) da bit a bit igual en cualquier plataforma. `rand1p_gpu` es idéntica, con las constantes del segundo LCG (`mult2`/`iadd2`).

## 4. `rn1`/`randv3`/`gauss3`: mismas fórmulas, `irn` explícito

```fortran
attributes(host, device) subroutine gauss3_gpu(irn, gvar3)
  integer(kind=i8), intent (inout) :: irn
  real(kind=r8), intent (out) :: gvar3(3)
  real(kind=r8) :: xl, arg, rn
    call rand1_gpu(rn, irn); arg = 2.0_r8*pi*rn
    call rand1_gpu(rn, irn); xl = sqrt(-2.0_r8*log(rn))
    gvar3(1) = xl*mysin(arg)
    gvar3(2) = xl*mycos(arg)
    call rand1_gpu(rn, irn); arg = 2.0_r8*pi*rn
    call rand1_gpu(rn, irn); xl = sqrt(-2.0_r8*log(rn))
    gvar3(3) = xl*mysin(arg)
end subroutine gauss3_gpu
```

`sin(arg)`/`cos(arg)` → `mysin(arg)`/`mycos(arg)` (mismo motivo que en `rota.cuf`: los intrínsecos de dispositivo/host de `nvfortran` no coinciden bit a bit con glibc). `sqrt` se deja intrínseco (correctamente redondeado por el estándar IEEE, sin ambigüedad posible). `log(rn)` se deja **intrínseco, sin puerto propio** — ver Parte 3, investigado a fondo y confirmado innecesario.

## 5. `k_split_seeds`

```fortran
attributes(global) subroutine k_split_seeds(n, irnin, seeds)
  integer(kind=i4), value :: n
  integer(kind=i8), value :: irnin
  integer(kind=i8), device, intent (out) :: seeds(n)
  integer(kind=i8) :: irn
  real(kind=r8) :: rn
  integer(kind=i4) :: i, iw
  iw = (blockIdx%x - 1) * blockDim%x + threadIdx%x
  if (iw <= n) then
    irn = irnin
    do i = 1, iw
      call rand1p_gpu(rn, irn)
    enddo
    seeds(iw) = irn
  endif
end subroutine k_split_seeds
```

---

## Parte 3 — Investigación: ¿hace falta un `mylog` propio?

## 6. El hallazgo real: esta glibc ejecuta la rama `_fma` de `log`/`exp`/`sin`/`cos`/`pow`/`acos`

Antes de dar por buena la Parte 2, surgió la duda de si `log()` intrínseco (sin portar) podía divergir de glibc igual que en su día divergieron `sin`/`cos`/`exp`/`pow` (motivo original de `mysin`/`mycos`/`myexp`/`mypow`). Usando los símbolos de depuración de `libc6-dbg` (glibc 2.39-0ubuntu8.7, la misma que enlaza `gfortran` en esta máquina) y resolviendo directamente la función IFUNC de cada una (el mecanismo de glibc para elegir en tiempo de carga, según qué instrucciones soporta la CPU real, entre varias implementaciones compiladas):

```
log  -> __ieee754_log_fma
exp  -> __ieee754_exp_fma
sin  -> __sin_fma
cos  -> __cos_fma
pow  -> __ieee754_pow_fma
acos -> __ieee754_acos_fma
```

Las seis resuelven a su variante `_fma`, confirmado con `dlopen`+llamada directa al resolutor de cada símbolo (ver metodología completa en el historial de esta sesión). Para `log` en concreto, el código fuente real de `e_log.c` tiene una rama explícita `#if HAVE_FAST_FMA` que calcula el resto de la reducción de rango de dos formas genuinamente distintas (`r=fma(z,invc,-1.0)` frente a `r=(z-chi-clo)*invc` con tabla auxiliar) — no es un matiz de compilador.

Esto **contradice** el comentario de cabecera de `glibc_pow.cuf` (y, por el mismo criterio, `glibc_exp_mod.cuf`/`glibc_sincos.cuf`/`glibc_acos.cuf`), que afirma portar "la rama sin FMA, la única activa en x86_64 genérico" — una suposición no verificada con el mecanismo real de esta máquina, del mismo tipo que ya se había detectado y corregido antes en `wavef.md` (`rij**3` con `nm`).

## 7. Pero: verificado, y descartado como causa real aquí

El primer indicio de que esto importaba fue un residuo de `~1E-16` visto en `gauss3` (walker 1, sorteo 3) al comparar contra el `gauss3` original. Antes de construir un `mylog`, se exigió aislar la causa con el mismo rigor que el resto del árbol (valores fijos, no suposición) — y la conclusión cambió por completo:

**Prueba 1** ([`test_log_isolado.cuf`](../mrandom/test_log_isolado.cuf)): se extrajo el `rn` exacto de la llamada que parecía divergir (`4.06679192298678771E-01`) y se comparó `log(rn)` intrínseco en CPU-`nvfortran`-host contra GPU-device, aislado, sin nada alrededor. **Resultado: exacto, `0.00E+00`.** `log()` nativo (host y device) ya coincide consigo mismo — no hay ninguna divergencia host/device en `log`.

**Prueba 2** ([`test_gauss3_isolado.cuf`](../mrandom/test_gauss3_isolado.cuf)): se repitió `gauss3_gpu` completo (host vs. device, la misma función en los dos sitios) para el walker 1, 4 sorteos. **Resultado: exacto en los 4, incluido el sorteo 3 que parecía divergir.**

**Prueba 3** ([`test_sincos_isolado.cuf`](../mrandom/test_sincos_isolado.cuf)): entonces, ¿de dónde salía el `~1E-16` visto originalmente? Se aisló el `arg` exacto de esa misma llamada (`5.48129312826136950E+00`) y se comparó `sin(arg)`/`cos(arg)` **intrínsecos de `nvfortran`-host** (es decir, `libnvcpumath`, la librería matemática propia de NVIDIA para CPU) contra `mysin(arg)`/`mycos(arg)` (el port de glibc). **Ahí sí aparece la diferencia**: `1.11E-16` en ambos.

**Diagnóstico correcto**: la primera versión de este test comparaba `gauss3_gpu` (que llama a `mysin`/`mycos`, el port de glibc) contra el `gauss3` **original**, sin portar, de `mrandom.f90` — que llama a `sin`/`cos` intrínsecos, resueltos por `libnvcpumath` (no glibc) al compilarse con `nvfortran`. Son dos algoritmos distintos por diseño, no la misma función en host vs. device. El `~1E-16` no era un bug de `log()` ni de `mysin`/`mycos` — era la diferencia ya conocida y documentada en todo el árbol (`gpu_vs_gfortran_arbol.md`) entre `libnvcpumath` y glibc, la razón de ser misma de `mysin`/`mycos`.

**Confirmación final**: se corrigió `test_rand.cuf` (bloque 3) para comparar `gauss3_gpu` host vs. device (la misma función, sin la trampa metodológica), y se construyó [`test_rand_gfortran.f90`](../mrandom/test_rand_gfortran.f90), un binario `gfortran` real e independiente que ejecuta el `gauss3` original (con `sin`/`cos`/`log` intrínsecos = glibc real, confirmado en rama `_fma`). Las tres vías — GPU, CPU-`nvfortran`-host, `gfortran` real — coinciden **bit a bit** en los 3 walkers × 4 sorteos × 3 componentes.

**Conclusión**: `log()` no necesita ningún puerto propio (`mylog`) — el intrínseco ya reproduce glibc exacto para este dominio (los valores que produce `rand1`, en `(twom48, 1)`). El hallazgo de la rama `_fma` en sí es real y queda documentado aquí como referencia para el árbol (si algún día aparece un residuo de `exp`/`sin`/`cos`/`pow`/`acos` no explicado por ninguna causa ya conocida, esta es una hipótesis a comprobar, con la metodología de arriba como plantilla) — pero no tiene, de momento, ningún caso real que lo necesite: ni aquí, ni en `rota` (8/8 exacto), ni en `mypow` ("30/30 exacto", `glibc_math.md`).

---

## Parte 4 — Pruebas

### Cómo ejecutarlo

Desde `v1-cuda-desarrollo/mrandom/`:
```bash
# 1) GPU + CPU(nvfortran) en el mismo binario
rm -f *.mod *.o
nvfortran -cuda -Kieee -Mnofma -c mrandom2.f90 glibc_exp_mod.cuf glibc_sincos.cuf rand_gpu.cuf test_rand.cuf
nvfortran -cuda -Kieee -Mnofma mrandom2.o glibc_exp_mod.o glibc_sincos.o rand_gpu.o test_rand.o -o test_rand
./test_rand

# 2) Solo CPU, con gfortran
rm -f *.mod *.o
gfortran -ffp-contract=off -c mrandom2.f90 mrandom.f90
gfortran -ffp-contract=off mrandom2.o mrandom.o test_rand_gfortran.f90 -o test_rand_gfortran
./test_rand_gfortran
```

## 8. Resultado: exacto en las tres vías, en los 3 bloques

**Bloque 1 — `rand1`/`rand1p`, 20 llamadas encadenadas**: `|err| max = 0.00E+00` en ambos, GPU vs. CPU-`nvfortran` vs. `gfortran` (aritmética entera, sin ninguna sorpresa esperable).

**Bloque 2 — reparto de semilla, 10 walkers**: las 10 semillas repartidas por `k_split_seeds` coinciden exactas con el cálculo de referencia (`rand1p` iterado `iw` veces) en las tres vías.

**Bloque 3 — `gauss3`, 3 walkers × 4 sorteos × 3 componentes (36 valores)**: **exacto bit a bit en las tres vías** — GPU = CPU-`nvfortran`-host = `gfortran` real, incluidos los casos que en la primera versión (mal comparada) del test parecían divergir. `PASA` con margen (`0.00E+00`, no solo "dentro de tolerancia").

Es el segundo kernel de este árbol (junto con `rota`) que cierra completamente exacto en las tres vías sin ninguna reserva ni residuo de ~1 ULP aceptado — a diferencia de `He_dihydrogen`/`vpot`/`hpsi`, aquí no hay ninguna suma de 3+ términos de signo variable que pueda reasociar entre Kahan/`treesum` y suma secuencial.
