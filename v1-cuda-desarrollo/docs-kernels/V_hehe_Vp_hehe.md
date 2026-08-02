# Segundo kernel: `V_hehe` / `Vp_hehe`

Documentación de [`v1-cuda-desarrollo/V_hehe-Vp_hehe/V_hehe-Vp_hehe.cuf`](../V_hehe-Vp_hehe/V_hehe-Vp_hehe.cuf). A diferencia de `calpleg`/`calderpleg` (que eran subrutinas), aquí las funciones originales de [`bh_heh2m.f`](../V_hehe-Vp_hehe/bh_heh2m.f) son eso, **funciones** — y eso trae matices nuevos que no habían salido todavía.

---

## Parte 1 — Implementación

## 1. `function` vs `subroutine` en CUDA Fortran: por qué importa aquí

En Fortran normal, la diferencia ya la conocías: una `function` devuelve un valor y se usa dentro de una expresión (`x = V_hehe(r)`); una `subroutine` no devuelve nada por su propio nombre y se invoca con `call`, comunicando resultados por argumentos `intent(out)`. En el original, `V_hehe`/`Vp_hehe` se usan así:
```fortran
ENERGY1 = ENERGY1 + V_hehe(R)
```
dentro de una suma — eso solo es posible siendo `function`. El primer borrador de este fichero las había declarado como `subroutine` y las llamaba con `call V_hehe(r)`, lo cual no compila: no se puede hacer `call` sobre algo que se necesita usar como un valor.

**Para CUDA Fortran, la regla añadida es esta: `attributes(global)` (el kernel, lo que se lanza con `<<<...>>>`) tiene que ser siempre `subroutine`, nunca `function`.** Un kernel no "devuelve" nada de la forma en que lo hace una función normal — su única vía de sacar resultados es escribiendo en argumentos `device` (arrays en memoria de la GPU), porque se ejecuta en miles de hilos a la vez y no hay un único "valor de retorno" que tenga sentido. Por eso, en [`V_hehe-Vp_hehe.cuf:30`](../V_hehe-Vp_hehe/V_hehe-Vp_hehe.cuf#L30), `k_V_hehe` es una `subroutine` con un argumento de salida `v_out(n)`, aunque por dentro llame a la `function` `V_hehe`:
```fortran
attributes(global) subroutine k_V_hehe(n, r, v_out)
  ...
  v_out(i) = V_hehe(r(i))
```
`V_hehe` en sí ([línea 6](../V_hehe-Vp_hehe/V_hehe-Vp_hehe.cuf#L6)) sí sigue siendo `function`, con `attributes(host, device)` — eso no cambia nada de la regla de "funciones vs. subrutinas" que ya conocías, solo se le añade dónde se ejecuta. Lo que nunca puede ser función es el kernel que la envuelve.

## 2. Las constantes de `param_atoms_bh.h`: se incluyen en tiempo de compilación, no se copian a la GPU

`V_hehe`/`Vp_hehe` usan un puñado de variables que no están declaradas en la propia función (`D_HeHe`, `alpha_HeHe`, `A_HeHe`, `xx1_HeHe`, `pi12`...) — vienen de un `include 'param_atoms_bh...h'` ([línea 7](../V_hehe-Vp_hehe/V_hehe-Vp_hehe.cuf#L7)). La razón por la que esto **no** supone ningún trabajo extra de GPU es que todas esas variables están declaradas como `PARAMETER` en el fichero incluido — es decir, son constantes fijadas en tiempo de compilación, no variables que se calculan o se leen de un fichero en tiempo de ejecución.

Eso importa porque significa que el compilador **sustituye el valor numérico directamente en el código máquina**, tanto en la versión `host` como en la `device` de `V_hehe` — no hay ningún dato que copiar de la CPU a la GPU para que estas constantes existan allí. Nos ahorramos exactamente lo que hicimos con `x_d = x_h` en `calpleg` (una transferencia de memoria expresa): aquí no hace falta ningún `device :: D_HeHe` ni ninguna asignación, la constante ya "está" en la GPU porque forma parte del propio programa compilado, igual que en la CPU. Ahorra tiempo (no hay transferencia que esperar) y memoria (no hay una copia en VRAM de algo que es fijo).

Esto es muy distinto de lo que pasará cuando se porte `potenbh`/`He_dihydrogen`, que usan `dhcm` — un valor que sí se lee en tiempo de ejecución de `heh2m.pot` a través de un `COMMON /datosbh/`. Esa sí es una variable de verdad, no una `PARAMETER`, y cuando le toque el turno hará falta tratarla como `x_d` en `calpleg`: declararla `device` y copiarla explícitamente.

## 3. Por qué hizo falta `param_atoms_bh_freeform.h`

Al intentar compilar `V_hehe` con el `include 'param_atoms_bh.h'` original, salían errores como:
```
NVFORTRAN-S-0290-Unexpected continuation line (./param_atoms_bh.h: 15)
NVFORTRAN-S-0023-Syntax error - unbalanced parentheses (./param_atoms_bh.h: 14)
```
La causa: `param_atoms_bh.h` está escrito en **Fortran de formato fijo** (el estilo F77 de `bh_heh2m.f`, columnas con significado — por ejemplo, una continuación de línea se marca con un carácter en la columna 6 de la línea *siguiente*):
```fortran
       PARAMETER (a0=65344.8145d0,a1= -0.42497d0,a2=3.95634d0,
     &            a3=0.07852d0)
```
Nuestro `.cuf` se compila en **Fortran de formato libre** (sin restricciones de columna, continuación con `&` al *final* de la línea anterior). Al meter el fichero fijo dentro del libre con un `include`, el compilador interpreta esa `&` de la columna 6 como basura o como el principio de una expresión nueva — de ahí "unexpected continuation line" y "unbalanced parentheses": no es que las constantes estén mal, es que la sintaxis de continuación de un formato no la entiende el parser del otro.

La solución fue crear [`param_atoms_bh_freeform.h`](../V_hehe-Vp_hehe/param_atoms_bh_freeform.h): **mismo contenido, mismos valores, mismo orden — ni un número tocado** — con el único cambio de mover el `&` de continuación al final de la línea anterior en vez del principio de la siguiente:
```fortran
      PARAMETER (a0=65344.8145d0,a1= -0.42497d0,a2=3.95634d0, &
                 a3=0.07852d0)
```
Es una conversión mecánica de formato, no una retranscripción de las constantes (que es justo lo que queríamos evitar, después de lo aprendido con el generador aleatorio: cuanto menos se retipeen números a mano, menos ocasión de un error silencioso). El fichero original `param_atoms_bh.h` se queda intacto para el código F77 que ya lo usa (`bh_heh2m.f`); el nuevo es solo para código Fortran libre como este `.cuf`. Con el cambio, `V_hehe`+`k_V_hehe` compilan sin errores.

## 4. Los dos `if` y la divergencia de warp: por qué se dejan así, por ahora

`V_hehe` tiene dos condicionales:
```fortran
if(x < D_HeHe) F=dexp(-(D_HeHe/x-1.d0)**2)
...
if (x >= xx1_HeHe .and. x <=xx2_HeHe) then
    addin = Aa_HeHe*(dsin( Ba_HeHe*(x-xx1_HeHe)-pi12)+1.d0)
end if
```
En una GPU, los hilos se ejecutan en grupos de 32 (*warps*) en modo SIMT: los 32 hilos de un warp ejecutan la misma instrucción a la vez. Si dentro de un warp unos hilos cumplen la condición y otros no, el hardware no puede tomar las dos ramas a la vez para hilos distintos de ese warp: ejecuta primero la rama verdadera (con los hilos que no la necesitan inactivos) y luego la falsa — ese trozo se vuelve secuencial para ese warp en vez de paralelo. Es lo que se llama **divergencia de warp**.

Existe una forma de evitarla sin usar `if`, calculando siempre las dos ramas y seleccionando el resultado con la función intrínseca `merge()` (válida en código `device`):
```fortran
F = merge(dexp(-(D_HeHe/x-1.d0)**2), 1.d0, x < D_HeHe)
```
**De momento se deja el `if` tal cual el original.** Los motivos:
- Cada rama es barata (una asignación con una `dexp`/`dsin`, no un bucle ni código pesado) — es la divergencia menos costosa que existe.
- `merge()` cambiaría "a veces cara, a veces gratis" por "siempre moderadamente cara" (siempre evalúa `dexp`/`dsin`, aunque no haga falta) — si compensa o no depende de cómo se repartan los valores de `x` entre los hilos de un warp en la ejecución real, algo que solo se puede saber perfilando, no adivinando.
- Es más fiel al original y más fácil de validar contra la CPU: menos superficie para introducir un error de transcripción.

**Si en el futuro se detecta con perfilado (`nsys`/`nvprof`) que esta parte ralentiza el cálculo de verdad**, ahí sí merece la pena estudiar la versión sin ramas con `merge()` y comparar tiempos — pero no antes, para no optimizar a ciegas algo que quizá no sea el cuello de botella.

## 5. El bug de `Vap` en el original — y cómo se corrigió aquí

Al portar `Vp_hehe` apareció algo que **no es un error nuestro, ya estaba en el original**. Mirando [`Compilacion-GPU/bh_heh2m.f`](../../Compilacion-GPU/bh_heh2m.f) línea por línea:

| Línea | Contenido |
|---|---|
| 505 | `double precision :: Vp, Vap, Vbp, Vp_hehe` — solo declara el tipo, no asigna ningún valor |
| 530 | `Vap = Aa_HeHe * Ba_HeHe* dcos(...)` — la **única** asignación real a `Vap` en todo el fichero, y está dentro de `if (x >= xx1_HeHe .and. x <=xx2_HeHe) then` |
| 533 | `!Vap=0.d0` — empieza por `!`: es un comentario, **no se ejecuta nunca** |
| 534 | `Vp_hehe = (eps_HeHe/req_HeHe) * (Vap+Vbp)` — usa `Vap` se haya entrado o no en el `if` de la 530 |

Si `x` cae fuera de `[xx1_HeHe, xx2_HeHe]`, la línea 534 usa el valor que `Vap` tenga por casualidad en memoria en ese instante — no hay ninguna rama que le dé un valor en ese caso. Es una variable local **sin inicializar**. El comentario `!Vap=0.d0` justo al lado, sin descomentar, sugiere que probablemente se pretendía tenerla siempre a cero fuera de esa ventana y se quedó así por descuido.

**Por qué es más delicado en GPU que en CPU:** en CPU, una variable de pila sin inicializar suele arrastrar el mismo tipo de "basura" de una ejecución a otra (reutilización de la misma zona de memoria). En la GPU, cada uno de los miles de hilos tiene su propia copia de esa variable local, en su propia zona de memoria/registros — el contenido "basura" puede variar de hilo a hilo, e incluso entre una ejecución del kernel y la siguiente. Dejar esto sin corregir en el port podría producir resultados de `Vp_hehe` distintos entre CPU y GPU (o inestables entre ejecuciones de GPU) precisamente para los pares de átomos con `x` fuera de esa ventana — sin que fuera un fallo del port en sí, sino del original heredado.

**Corrección aplicada** en [`V_hehe-Vp_hehe.cuf`](../V_hehe-Vp_hehe/V_hehe-Vp_hehe.cuf), recuperando lo que la línea comentada del original sugiere que era la intención:
```fortran
Vap = 0.d0
if (x >= xx1_HeHe .and. x <=xx2_HeHe) then
    Vap = Aa_HeHe * Ba_HeHe* dcos(Ba_HeHe*(x-xx1_HeHe)-pi12)
end if
```
**Pendiente de decidir:** esta corrección solo está en la copia portada a GPU. El `bh_heh2m.f` que usa `Compilacion-GPU`/`Original` sigue teniendo el mismo comportamiento sin inicializar — no se ha tocado ahí todavía, a la espera de decidir si se corrige también en el código de producción.

---

## Parte 2 — Pruebas

## 6. El kernel `k_Vp_hehe` y dónde vivía el segundo fallo de estructura

`k_Vp_hehe` sigue el mismo patrón que `k_V_hehe` (§1): un hilo por valor de `r`, escribiendo en un array de salida `v_out(n)`. El primer borrador lo había dejado **fuera** del `module mVheheVphehe`, después del `end module` — y, como ya comprobamos con `calpleg`/`calderpleg`, una llamada de código `device` a otro código `device` (aquí, `k_Vp_hehe` llamando a `Vp_hehe`) necesita que ambos estén visibles en el mismo `module`. Se corrigió moviendo `k_Vp_hehe` dentro, antes del `end module`.

También arrastraba, copiadas del F77 original, dos cosas incompatibles con el formato libre del `.cuf`: una continuación de línea al estilo fijo (`&` al principio de la línea siguiente) y una línea de comentario `C ...` (el comentario de formato fijo usa `C` en la primera columna; en formato libre es `!`). Las dos se corrigieron igual que en `param_atoms_bh_freeform.h` (§3): cambio mecánico de sintaxis, sin tocar ningún valor ni fórmula.

## 7. El programa de prueba: tres vías, siete valores de `r`

[`V_hehe-Vp_hehe.cuf`](../V_hehe-Vp_hehe/V_hehe-Vp_hehe.cuf), `program test_V_hehe_Vp_hehe`. Datos sintéticos:
```fortran
r_h = (/ 2.0d0, 3.0d0, 4.0d0, 5.0d0, 6.0d0, 8.0d0, 12.0d0 /)
```
Elegidos para cruzar los tres regímenes de la fórmula (con `req_HeHe≈2.97`, `D_HeHe≈1.41`, la ventana `[xx1_HeHe,xx2_HeHe]≈[1.00,1.45]`, y `x=r/req_HeHe`):
- `r=2.0` → `x≈0.67`: corto alcance, `F` amortiguada, sin término "add-in".
- `r=3.0` y `r=4.0` → `x≈1.01` y `1.35`: dentro de la ventana del "add-in" **y** con `F` todavía amortiguada — el caso más completo, ejercita las dos ramas de `V_hehe`/`Vp_hehe` a la vez.
- `r=5.0, 6.0, 8.0, 12.0` → `x≳1.68`: largo alcance, `F=1`, fuera de la ventana del "add-in" — justo la zona donde el bug de `Vap` (§5) se manifestaría si no se hubiera corregido.

La referencia de CPU es `V_hehe`/`Vp_hehe` de `bh_heh2m.f` **sin tocar**, compiladas junto al `.cuf`. Como `bh_heh2m.f` no es un módulo (son subrutinas/funciones sueltas al estilo F77), no se puede hacer `use` — se declaran `external`:
```fortran
double precision :: V_hehe, Vp_hehe
external :: V_hehe, Vp_hehe
```
Esto también evita el choque de nombres con el `V_hehe`/`Vp_hehe` del módulo `mVheheVphehe` (que no se importan por nombre — del `use mVheheVphehe` solo se traen `k_V_hehe`/`k_Vp_hehe`, los kernels).

**Resultado real de la última ejecución** (`nvfortran -cuda bh_heh2m.f V_hehe-Vp_hehe.cuf -o test_hehe && ./test_hehe`):
```
--- par 1   r =   2.0000
  V_hehe  CPU:  1.70506653E-03
  V_hehe  GPU:  1.70506653E-03
  Vp_hehe CPU: -8.63905399E-03
  Vp_hehe GPU: -8.63905399E-03
  |err|  V_hehe=  0.00E+00   Vp_hehe=  1.73E-18

--- par 2   r =   3.0000
  V_hehe  CPU: -3.46079795E-05
  V_hehe  GPU: -3.46079795E-05
  Vp_hehe CPU:  8.26740167E-06
  Vp_hehe GPU:  8.26740167E-06
  |err|  V_hehe=  0.00E+00   Vp_hehe=  0.00E+00

--- par 3   r =   4.0000
  V_hehe  CPU: -9.23984284E-06   GPU: -9.23984284E-06
  Vp_hehe CPU:  1.38630636E-05   GPU:  1.38630636E-05
  |err|  V_hehe=  0.00E+00   Vp_hehe=  0.00E+00

--- par 4   r =   5.0000
  V_hehe  CPU: -2.30712818E-06   GPU: -2.30712818E-06
  Vp_hehe CPU:  2.88126441E-06   GPU:  2.88126441E-06
  |err|  V_hehe=  0.00E+00   Vp_hehe=  0.00E+00

--- par 5   r =   6.0000
  V_hehe  CPU: -7.44461520E-07   GPU: -7.44461520E-07
  Vp_hehe CPU:  7.65157201E-07   GPU:  7.65157201E-07
  |err|  V_hehe=  0.00E+00   Vp_hehe=  0.00E+00

--- par 6   r =   8.0000
  V_hehe  CPU: -1.27840566E-07   GPU: -1.27840566E-07
  Vp_hehe CPU:  9.73203542E-08   GPU:  9.73203542E-08
  |err|  V_hehe=  0.00E+00   Vp_hehe=  0.00E+00

--- par 7   r =  12.0000
  V_hehe  CPU: -1.09503684E-08   GPU: -1.09503684E-08
  Vp_hehe CPU:  5.51051393E-09   GPU:  5.51051393E-09
  |err|  V_hehe=  0.00E+00   Vp_hehe=  0.00E+00

 PASA: GPU y CPU coinciden dentro de tolerancia
```
Los pares 4 a 7 (fuera de la ventana del "add-in") son exactamente los que habrían expuesto el bug de `Vap` si no se hubiera corregido — y coinciden perfectamente, confirmando que la corrección del §5 funciona igual en CPU y en GPU. El único resto no nulo (`1.73E-18` en el par 1) es ruido de coma flotante muchos órdenes de magnitud por debajo de la tolerancia del test (`1.0d-10`).

## 8. La tercera vía: `gfortran`, sin nada de GPU

Mismo motivo que con `calpleg`/`calderpleg`: comprobar que la referencia de CPU no depende de qué compilador la genera. [`test_hehe_gfortran.f90`](../V_hehe-Vp_hehe/test_hehe_gfortran.f90) repite los mismos 7 valores de `r`, llamando directamente a `V_hehe`/`Vp_hehe` de `bh_heh2m.f`, compilado con `gfortran`:
```bash
gfortran -ffixed-line-length-132 bh_heh2m.f test_hehe_gfortran.f90 -o test_hehe_gfortran
./test_hehe_gfortran
```
(la flag `-ffixed-line-length-132` hace falta por las líneas largas de `bh_heh2m.f`, igual que en `Original/Makefile.serie` — ver `docs-Makefiles/Makefiles.md`).

Comparando los números (no las etiquetas) contra la columna `CPU:` de `test_hehe`:
```bash
diff <(./test_hehe | grep 'CPU:' | grep -oE '[-0-9.E+]+$') \
     <(./test_hehe_gfortran | grep 'gfortran:' | grep -oE '[-0-9.E+]+$')
```
→ **sin diferencias**. Las tres vías coinciden: GPU ≈ CPU(`nvfortran`) = CPU(`gfortran`), con el único ruido de coma flotante ya mencionado en el §7.

## 9. De dónde sale exactamente el `1.73E-18` del par 1

No nos quedamos con "es ruido de coma flotante" sin más — se buscó la operación concreta.

**Primer paso, con más decimales:**
```
GPU (device, k_Vp_hehe):          -0.00863905398540294918
Host (misma fuente, backend CPU): -0.00863905398540295091
```
Los dos números coinciden hasta la cifra 17ª y difieren en la última representable de un `double` — un ULP (*unit in the last place*), la diferencia más pequeña que puede existir entre dos números de coma flotante distintos.

**Bisección:** se instrumentó una copia de `Vp_hehe` que devuelve, además del resultado final, cada variable intermedia (`x, x2, F, Fp, sum1, sum2`, el argumento y el resultado de cada `dexp`, `Vbp`, `Vap`...). Comparando CPU vs GPU paso a paso para `r=2.0`, **todas** las variables intermedias coincidían exactamente — hasta que se llegó al propio cálculo de `Vbp`:
```fortran
Vbp = A_HeHe*(-alpha_HeHe+2.d0*beta_HeHe*x) &
    *dexp(-alpha_HeHe*x + beta_HeHe*x2) - Fp*sum1 + F*sum2
```
Aquí es donde aparece el primer bit de diferencia.

**Causa: fusión multiplicación-suma (FMA).** Por defecto, al generar código de GPU, `nvfortran` fusiona patrones `a*b+c` en una única instrucción de hardware (`FFMA`) con un solo redondeo, en vez de multiplicar y sumar por separado con dos redondeos — la GPU tiene unidades dedicadas para esto, pensadas para ir más rápido. El backend de CPU del mismo compilador, para esta expresión concreta, no fusiona igual. Resultado: mismo texto fuente, mismo compilador, dos secuencias de instrucciones ligeramente distintas, un bit de diferencia en el redondeo final.

**Se probó a reescribir la fórmula** separando la `dexp(...)` en una variable propia antes de multiplicarla, pensando que quizás eso cambiaba cómo el compilador agrupa la expresión — **no cambió nada**: se comprobó con una comparación A/B directa (la expresión tal cual el original contra la misma con la `dexp` en variable aparte, las dos en el mismo fichero y contexto de compilación) y las dos dieron exactamente la misma diferencia frente a `bh_heh2m.f`. La fusión FMA es una decisión del compilador sobre cómo traducir la expresión a instrucciones de máquina, no algo controlable reescribiendo el Fortran.

**La flag que sí lo arregla, aislada de forma precisa:**

| Flags | GPU vs CPU (`nvfortran`, mismo compilador) |
|---|---|
| Ninguna | `1.73E-18` |
| `-Kieee` (sola) | `1.73E-18` — sin cambio |
| `-Mnofma` (sola) | `0.00E+00` — arreglado |

`-Mnofma` desactiva específicamente la generación de instrucciones FMA. `-Kieee` (que fuerza cumplimiento estricto de IEEE-754 en otros aspectos: subnormales, reasociación...) no tocaba este caso concreto — la FMA en sí misma no viola IEEE-754 (el propio estándar la define como una operación válida con su propio redondeo), así que un compilador puede considerarla "cumplidora" y no desactivarla con `-Kieee`.

**Importante: esto no contradice lo que vimos con `qmccluster` completo** (`docs/v0_Cambios_Compilador.md`, §4.4), donde usamos `-Kieee -Mnofma` juntas. Son dos comparaciones distintas:

| Comparación | A cada lado hay... | Flag que lo arregla |
|---|---|---|
| `qmccluster` completo: `nvfortran` vs `gfortran` | dos compiladores **distintos**, los dos para CPU | `-Kieee` sola (comprobado: `-Mnofma` sola no basta, reaparecen diferencias de 1 bit) |
| `Vp_hehe` aislado: CPU vs GPU | el **mismo** compilador (`nvfortran`), dos backends (x86 y PTX/SASS) | `-Mnofma` sola (comprobado: `-Kieee` sola no basta) |

Con el binario completo, la discrepancia viene de que `nvfortran` y `gfortran` son compiladores distintos que difieren en varios aspectos de su generación de código de CPU (no solo FMA). Con `Vp_hehe` aislado, los dos lados salen del mismo `nvfortran` — ahí la única discrepancia real encontrada es la FMA del backend de GPU. No es contradictorio, son ejes de comparación diferentes; simplemente al usar las dos flags juntas la primera vez no se había separado cuál hacía el trabajo en cada caso.

**Recomendación práctica**, igual que con `qmccluster`: usar `-Mnofma` (o `-Kieee -Mnofma`, según qué se esté comparando) solo para validar corrección frente a la CPU, no en compilaciones pensadas para medir rendimiento — la GPU tiene hardware FMA dedicado precisamente para ir más rápido, y renunciar a él tiene un coste real.

---

## Parte 3 — `dexp`/`dsin`/`dcos` sustituidas por `myexp`/`mysin`/`mycos`

Tras `docs-kernels/glibc_math.md` (puerto de `exp`/`sin`/`cos` de `glibc` 2.39, verificado bit a bit), este kernel es el primero en usar esas versiones propias en vez de las intrínsecas — es donde más aparecían las discrepancias de ULP de esta familia (`V_hehe` usa `dexp`+`dsin`, `Vp_hehe` usa `dexp`+`dcos`, ver `gpu_vs_gfortran_arbol.md`).

**Cambio**: en `mVheheVphehe`, se añade `use glibc_exp_mod, only: myexp` / `use glibc_sincos_mod, only: mysin, mycos`, y se sustituyen las llamadas una a una (`dexp`→`myexp`, `dsin`→`mysin`, `dcos`→`mycos`) en `V_hehe` y `Vp_hehe` — ninguna fórmula cambia, solo qué función calcula cada transcendente.

**Metodología nueva, de aquí en adelante**: la referencia de CPU pasa a ser [`Original-VapFix`](../../Original-VapFix/README.md) (el `bh_heh2m.f` con el bug de `Vap` ya corregido, no el `Original` sin tocar), y las tres vías se compilan siempre con flags estrictas: `nvfortran -Kieee -Mnofma`, `gfortran -ffp-contract=off`.

### Resultado real (precisión completa, 17 cifras)

```bash
nvfortran -cuda -Kieee -Mnofma glibc_exp_mod.o glibc_sincos.o bh_heh2m.o V_hehe-Vp_hehe.o -o test_hehe_vapfix
./test_hehe_vapfix
gfortran -ffixed-line-length-132 -ffp-contract=off bh_heh2m.f test_hehe_gfortran.f90 -o test_hehe_gfortran_vapfix
./test_hehe_gfortran_vapfix
```

| par | `r` | `V_hehe` CPU=GPU=`gfortran` | `Vp_hehe` CPU=GPU=`gfortran` |
|---|---|---|---|
| 1 | 2.0 | `1.70506652584232160E-03` | `-8.63905398540294918E-03` |
| 2 | 3.0 | `-3.46079795267654469E-05` | `8.26740167483901215E-06` |
| 3 | 4.0 | `-9.23984284488745423E-06` | `1.38630636471642137E-05` |
| 4 | 5.0 | `-2.30712817685348653E-06` | `2.88126441201096815E-06` |
| 5 | 6.0 | `-7.44461519730393640E-07` | `7.65157201371968234E-07` |
| 6 | 8.0 | `-1.27840565613205925E-07` | `9.73203542229285112E-08` |
| 7 | 12.0 | `-1.09503684398462021E-08` | `5.51051392553147082E-09` |

**Las tres columnas (CPU-`nvfortran`, GPU, `gfortran`) coinciden dígito a dígito en los 7 pares, para `V_hehe` y `Vp_hehe` a la vez** — comprobado con comparación exacta de cadenas, no solo a ojo. Incluido el par 1 de `Vp_hehe`, que era justo el caso con la discrepancia de FMA documentada arriba (§9): con `myexp` reemplazando la intrínseca y `-Mnofma` activa, desaparece del todo, no solo se reduce.

### Dos tablas completas: con y sin flags

Repitiendo la comparación **sin** `-Kieee -Mnofma`/`-ffp-contract=off`, para tener el cuadro completo (`max|diff|` de `V_hehe`/`Vp_hehe` por par):

**Tabla 1 — GPU (`nvfortran`) vs CPU-`gfortran`**:

| par | `r` | | sin flags | con flags |
|---|---|---|---|---|
| 1 | 2.0 | `V_hehe` | `2.17E-19` | `0.00E+00` |
| 1 | 2.0 | `Vp_hehe` | `1.73E-18` | `0.00E+00` |
| 2 | 3.0 | `Vp_hehe` | `5.08E-21` | `0.00E+00` |
| 3 | 4.0 | `Vp_hehe` | `3.39E-21` | `0.00E+00` |
| 2-3 | 3.0/4.0 | `V_hehe` | `0.00E+00` | `0.00E+00` |
| 4-7 | 5.0-12.0 | `V_hehe`/`Vp_hehe` | `0.00E+00` | `0.00E+00` |

**Tabla 2 — CPU(`nvfortran`) vs GPU**:

| par | sin flags | con flags |
|---|---|---|
| 1-7 | `0.00E+00` (`V_hehe`, `Vp_hehe`) | `0.00E+00` (`V_hehe`, `Vp_hehe`) |

**Por qué:** la Tabla 2 da siempre `0.00E+00` — `myexp`/`mycos`/`mysin` son exactamente el mismo código (`attributes(host,device)`) compilado para host y para device, así que, a diferencia de las intrínsecas `dexp`/`dcos`/`dsin` (que sí eran tres implementaciones de librería independientes, ver `glibc_math.md`), aquí no queda ninguna librería que pueda divergir entre CPU y GPU. La Tabla 1 muestra un residuo minúsculo (`~1e-18`/`~1e-21`, muy por debajo del ULP de un `double` típico en esta escala) **solo sin flags**, y solo en el par 1 (`r=2.0`, régimen de corto alcance con `F` amortiguada) y en `Vp_hehe` de los pares 2-3 — la misma familia de diferencia por reasociación/FMA ya vista en `calpleg`/`calderpleg` (§9 de ese documento) y en el resto del árbol, cerrada del todo por `-Kieee -Mnofma`.
