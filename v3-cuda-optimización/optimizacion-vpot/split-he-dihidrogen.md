# Extraer el término de dispersión de `He_dihydrogen` a una subrutina aparte

## Objetivo

`optimizacion-vpot.md` estableció que, tras migrar el split de `derananum` a
producción, `vpot`/`He_dihydrogen` pasa a dominar el pipeline (~53-54% del
tiempo, ver Medición 2). `He_dihydrogen` es la función más pesada de esa
cadena de llamadas (280 instrucciones, la mayor fuente de tráfico a memoria
local encontrado en la investigación de `vpot`).

Pregunta de esta investigación: si se saca un bloque autocontenido de
`He_dihydrogen` a su propia subrutina `attributes(host,device)`, de forma
que las variables intermedias de ese bloque solo estén vivas dentro de la
subrutina nueva (y no cuenten para el pico de registros de
`He_dihydrogen`), ¿baja la presión de registros de `He_dihydrogen` (y con
ella el `LOCAL` que le atribuye la investigación de `vpot`)?

## Motivación: el hallazgo inverso ya documentado

`fusion-angle-hehe.md` probó lo contrario -- **meter hacia dentro** una
llamada externa (`angle()`) en vez de mantenerla como subrutina aparte -- y
midió que los registros de `He_dihydrogen` **subieron** de 106 a 136.
Conclusión de esa investigación: una llamada a una subrutina separada tiene
su propia "ventana" de registros que no se solapa con la del llamador,
mientras que el código inlineado sí compite por los mismos registros que
todo lo demás en la función.

Si eso es así, el efecto contrario debería cumplirse: **sacar** código de
`He_dihydrogen` a una subrutina aparte debería bajar (no subir) su presión
de registros, por la misma razón en sentido inverso. Esta investigación
pone esa hipótesis a prueba, no la da por buena.

## El bloque elegido: término de dispersión (líneas 413-437)

Bloque autocontenido, ya identificado como candidato natural: recibe
`theta`/`rnorm` y devuelve `eterm1`/`eterm2`, sin más dependencia del resto
de `He_dihydrogen` que unas constantes de compilación.

```fortran
! He_dihydrogen.f, líneas 413-437 (bloque a extraer)
    call mypow_log(abs(mycos(theta)), coshi, coslo)
       cos2=mypow_desde_log(coshi,coslo,2.0d0)
       cos4=mypow_desde_log(coshi,coslo,4.0d0)
       cos6=mypow_desde_log(coshi,coslo,6.0d0)
       call mypow_log(abs(mysin(theta)), sinhi, sinlo)
       sin2=mypow_desde_log(sinhi,sinlo,2.0d0)
       sin4=mypow_desde_log(sinhi,sinlo,4.0d0)
       sin6=mypow_desde_log(sinhi,sinlo,6.0d0)
       call mypow_log(rnorm, normhi, normlo)
       norm6=mypow_desde_log(normhi,normlo,6.0d0)

       atheta=a1*cos2
       atheta=atheta+a2*cos4
       atheta=atheta+a3*cos6
       btheta=b0
       btheta=btheta+b1*cos2
       btheta=btheta+b2*cos4
       btheta=btheta+b3*cos6
       c6theta=c60
       c6theta=c6theta+c61*sin2
       c6theta=c6theta+c62*sin4
       c6theta=c6theta+c63*sin6

       eterm1=a0*myexp(atheta-rnorm*btheta)
       eterm2=FN1(rnorm*btheta)*c6theta/norm6
```

No se incluyen las líneas 438-444 (guardado en `e2terms(2*J1-1)`/`e2terms(2*J1)`)
porque ese indexado (`J1`) es contabilidad del bucle llamador, no parte del
cálculo del término de dispersión en sí.

**Entradas**: `theta`, `rnorm`.
**Constantes** (`a0,a1,a2,a3,b0,b1,b2,b3,c60,c61,c62,c63`): confirmado en
`param_atoms_bh.h` que son `PARAMETER` (constantes de compilación, no
argumentos en tiempo de ejecución) -- la subrutina nueva puede incluir el
mismo `.h` por su cuenta en vez de recibirlas como argumentos.

**Corrección tras revisar el uso real más allá de la línea 437** (no
asumir el análisis previo a la compactación de contexto -- se comprobó con
`grep` cada variable en todo el fichero, mismo criterio de
[[feedback_verificar_contra_original]]): de las 16 variables que parecían
puramente internas, **solo 6 lo son de verdad**:

- **Puramente internas** (locales a la subrutina nueva, ya no cuentan para
  el pico de registros de `He_dihydrogen`): `cos2,cos4,cos6,sin2,sin4,sin6`
  -- no se usan en ningún otro sitio del fichero tras la línea 434.
- **Deben salir como salidas adicionales** (se siguen usando después de la
  línea 437):
  - `btheta`: se usa **sin condición** en el término de inducción (líneas
    524-660, `Ex0`/`Ey0`/`Ez0`/`dExdx`/... -- ese bloque se ejecuta
    siempre, no depende de `GTEST`). No es opcional, tiene que salir.
  - `atheta,c6theta,norm6,coshi,coslo,sinhi,sinlo,normhi,normlo`: solo se
    reutilizan dentro del bloque `IF (GTEST) THEN` (líneas 445-489, para
    `cos3/cos5/sin3/sin5/norm7/dvdR/dvdtheta`). `GTEST` es
    `LOGICAL, PARAMETER :: GTEST = .false.` (línea 266, confirmado con
    `grep`) -- código muerto en tiempo de ejecución, pero el compilador
    igual tiene que compilarlo (no es un `#if` de preprocesador), así que
    estas variables también tienen que salir de la subrutina para que
    `He_dihydrogen` siga teniendo valores definidos ahí, aunque nunca se
    ejecuten.

**Salidas totales**: `eterm1, eterm2` (el resultado real) +
`btheta, atheta, c6theta, norm6, coshi, coslo, sinhi, sinlo, normhi, normlo`
(10 variables de paso, necesarias para que el resto de `He_dihydrogen`
siga compilando/siendo correcto) = 12 salidas en total.

Esto reduce el alcance real del experimento: de las 16 variables que se
pensaba mover, solo 6 (`cos2,cos4,cos6,sin2,sin4,sin6`) desaparecen de
verdad del ámbito de `He_dihydrogen`. Sigue siendo una prueba válida (esas
6 más las ventanas internas de `mypow_log`/`mypow_desde_log`/`myexp`
llamadas dentro de la subrutina nueva ya no comparten registros con el
resto de la función), pero el efecto esperado es más modesto que el
16-variables original.

## Diseño

```fortran
attributes(host, device) subroutine termino_dispersion(theta, rnorm,
     &     eterm1, eterm2, coshi, coslo, sinhi, sinlo, normhi, normlo,
     &     atheta, btheta, c6theta, norm6)
  use glibc_exp_mod, only: myexp
  use glibc_sincos_mod, only: mysin, mycos
  use glibc_pow_mod, only: mypow_log, mypow_desde_log
  implicit none
  include 'param_atoms_bh.h'
  double precision, intent(in)  :: theta, rnorm
  double precision, intent(out) :: eterm1, eterm2
  double precision, intent(out) :: coshi, coslo, sinhi, sinlo
  double precision, intent(out) :: normhi, normlo, atheta, btheta, c6theta, norm6
  double precision :: cos2,cos4,cos6,sin2,sin4,sin6
  ! ... cuerpo = líneas 413-437 tal cual ...
end subroutine termino_dispersion
```

En `He_dihydrogen.f`, las líneas 413-437 se sustituyen por:

```fortran
call termino_dispersion(theta, rnorm, eterm1, eterm2, coshi, coslo,
     &     sinhi, sinlo, normhi, normlo, atheta, btheta, c6theta, norm6)
```

(las líneas 438-444 se quedan igual donde están, sin tocar; las
declaraciones locales `cos2,cos4,cos6,sin2,sin4,sin6` se eliminan de
`He_dihydrogen` ya que no se usan fuera del bloque extraído).

## Protocolo de verificación (mismo criterio de siempre)

1. Copia aislada (worktree/carpeta separada), no tocar producción hasta
   verificar.
2. Verificar energía final bit a bit idéntica a producción sin tocar
   (2000w, semilla 11, conf fresco de `v1-cuda-desarrollo/ccuerpo/`).
3. `cuobjdump --dump-sass` sobre el binario real: confirmar que
   `termino_dispersion` aparece como `CALL.ABS.NOINC` real dentro de
   `He_dihydrogen` y no ha sido inlineada de vuelta por el compilador (si
   se inlinea, el experimento no prueba nada -- mismo método ya usado en
   `fusion-angle-hehe.md`).
4. Registros de `He_dihydrogen` y de la nueva `termino_dispersion`, medidos
   con `ncu --metrics launch__registers_per_thread` sobre el binario
   enlazado real (no `cuobjdump` sobre el `.o` intermedio -- no fiable con
   compilación separable, ver `derwavefx-split-concurrente.md`).
5. Tiempo real de `k_vpot_t` (rondas alternas, conf fresco) a 2000w.

## Implementación real

`termino_dispersion` se añadió como subrutina **hermana** de `He_dihydrogen`
dentro del mismo `module mHe_dihydrogen` (no en un módulo aparte): `FN1`
-- que la subrutina necesita llamar -- es también una función hermana
dentro de ese mismo módulo, sin `use` que la exponga fuera. Ponerla en un
módulo distinto habría obligado a un `use` circular
(`mterminodispersion` necesitaría `use mHe_dihydrogen, only: FN1`, y
`mHe_dihydrogen` necesitaría `use mterminodispersion` para llamarla) --
se intentó primero y se descartó antes de compilar nada, al ver que la
única forma de evitar el círculo sin tocar `FN1` era reinventar su cuerpo
a mano en el módulo nuevo, exactamente el tipo de "inventar en vez de
copiar" que hay que evitar.

## Verificación

- **Bit a bit**: `-615.5737694991` (2000w, semilla 11, conf fresco de
  `v1-cuda-desarrollo/ccuerpo/`), idéntico a producción en las 2 rondas de
  tiempo (ver más abajo) y en la corrida de verificación inicial.
- **Compilación**: sin errores ni warnings nuevos achacables al cambio
  (los warnings del build son preexistentes, de otros ficheros).

## Registros de `k_vpot_t`: sube, no baja

Medido con `ncu --metrics launch__registers_per_thread -k
"regex:mdmc2_pipeline_k_vpot_t_" -c 1` sobre el binario real (mismo
método que `derwavefx-split-concurrente.md` -- nunca `cuobjdump` sobre
`.o` intermedios, no fiables con compilación separable).

| | Registros/hilo de `k_vpot_t` |
|---|---|
| Producción (post-fusión `V_hehe`/`Vp_hehe`, referencia de `optimizacion-vpot.md` Medición 3) | **106** |
| Con `termino_dispersion` extraída | **120** |

**Sube 106→120**, no baja -- mismo patrón (dirección opuesta a la
esperada) que `fusion-angle-hehe.md` (106→136 al INLINEAR `angle()`
dentro de `He_dihydrogen`). Aquí se hizo lo contrario (EXTRAER) y aun así
subió, lo que apunta a que la hipótesis de partida no se cumple en este
caso: no se está consiguiendo un "ventana de registros" separada de
verdad.

## Por qué: `termino_dispersion` se inlinea de todas formas (verificado, no supuesto)

`cuobjdump --dump-sass` sobre el binario final enlazado (`qmccluster_pipeline`,
no el `.o` intermedio) muestra que, de todas las funciones del módulo
`mHe_dihydrogen` (`He_dihydrogen`, `FN1`, `DFN1`, `FN2`, `DFN2`, `F00`...`F6`,
`treesum`, `kahansum`, y ahora `termino_dispersion`), **la única que
aparece como símbolo de función independiente es `mhe_dihydrogen_he_dihydrogen_`**
-- ninguna de las demás, incluida la nueva, tiene su propio bloque SASS.
Todas están inlineadas dentro de `He_dihydrogen`, exactamente como ya
pasaba con `FN1`/`DFN1`/etc. *antes* de este cambio -- el compilador ya
venía inlineando agresivamente las funciones pequeñas de este módulo en
el paso de enlace de código device (optimización de programa completo a
nivel de `nvlink`), y `termino_dispersion` no escapa a ese mismo
comportamiento pese a ser una `SUBROUTINE` completa, no una función de una
línea.

Recuento de `CALL.ABS.NOINC` dentro del bloque SASS de `He_dihydrogen`
(mismo método de `fusion-angle-hehe.md`): **58**, frente a los **65** de
la referencia de producción citada en esa misma investigación -- bajó,
no subió, coherente con que no hay ninguna llamada nueva real (si la
hubiera habido, se esperaría 65+1=66, como pasó allí con `myacos`).

### Intento de forzar `noinline`: tampoco funciona

Se probó `!$pgi noinline` justo antes de la declaración de
`termino_dispersion` (pregunta directa del usuario en esta sesión, no
asumido de antemano):

- **Sí es una directiva real**: en el `.o` compilado por separado,
  `termino_dispersion` aparece como función propia junto con TODAS las
  demás del módulo (`FN1`, `F00`...) -- pero esto no prueba nada por sí
  solo, ya que en compilación separable **todas** las funciones de un
  módulo aparecen sueltas en su `.o` individual, inlineadas o no; la
  fusión real ocurre en el enlace.
- **En el binario final enlazado, no cambia nada**: sigue sin aparecer
  `termino_dispersion` como símbolo independiente, y los registros de
  `k_vpot_t` miden exactamente los mismos **120** con o sin la directiva.
  `!$pgi noinline` se respeta en la compilación por fichero pero se
  ignora en el paso de enlace de código device de este toolchain
  (`nvfortran` con `-cuda`) -- no es una vía viable para forzar esto aquí.

## Tiempo real (2000w, rondas alternas, conf fresco cada ronda)

| Ronda | Producción | Con extracción |
|---|---|---|
| 1 | 23,62 s | 24,52 s |
| 2 | 22,24 s | 22,10 s |
| **Media** | **22,93 s** | **23,31 s** |

Diferencia de medias: **+1,66%** -- pequeña y el orden se invierte entre
rondas (ronda 1 gana producción, ronda 2 gana la extracción), igual que
en `fusion-angle-hehe.md`: dentro del ruido térmico, no una diferencia
real y repetible. El resultado decisivo aquí es el de registros (medida
determinista, sin ruido), no el de tiempo.

## Conclusión de la extracción simple: NEGATIVO

La hipótesis motivadora (extraer código a una subrutina hermana separa su
"ventana" de registros de la del llamador, efecto inverso al de
`fusion-angle-hehe.md`) **no se cumple aquí** porque su premisa
implícita -- que la subrutina nueva se queda como una llamada real, no
inlineada -- no se cumple: el compilador la inlinea en el enlace de
código device igual que ya inlineaba `FN1`/`DFN1`/etc., y ni siquiera
`!$pgi noinline` lo evita. Con la función inlineada, el resultado pasa a
depender del mismo mecanismo de "pico, no suma" que `fusion-angle-hehe.md`
ya documentó: las 10 variables de paso que `He_dihydrogen` sigue
necesitando después de la línea 437 (`btheta` sin condición;
`atheta,c6theta,norm6,coshi,coslo,sinhi,sinlo,normhi,normlo` para el
bloque `IF(GTEST)` muerto en tiempo de compilación) tienen que estar
todas vivas a la vez justo en el punto de la llamada -- un patrón de
liveness peor, no mejor, que el código original secuencial.

Esto abrió 3 preguntas de seguimiento, probadas a continuación: ¿se puede
forzar una llamada real con RDC? ¿ayuda el scoping de bloque sin pasar por
una subrutina? ¿ayudaría meter las variables puramente locales en memoria
compartida en vez de dejar que floten entre registros y memoria local?

## Intento 2: forzar llamada real con `-gpu=rdc` (relocatable device code)

Motivación: RDC solo impide el inlining **entre ficheros** (el generador
de código de cada `.o` no ve el cuerpo de una función definida en otro
fichero) -- así que hace falta separar `termino_dispersion` a un fichero
distinto de verdad, no solo usar la bandera.

**Implementación**: `termino_dispersion` movida a `mterminodispersion_mod.cuf`
(módulo `mterminodispersion`), y `FN1` (que necesita) movida -- no
duplicada -- a `mFN1_mod.cuf` (módulo `mFN1`), para que ambos ficheros la
compartan sin depender uno del otro. Todo el proyecto compilado y enlazado
con `-gpu=lineinfo,rdc`.

**Verificación del mecanismo**: `cuobjdump --dump-sass` sobre el binario
final muestra ahora **3 símbolos de función independientes**:
`mfn1_fn1_`, `mterminodispersion_termino_dispersion_`,
`mhe_dihydrogen_he_dihydrogen_` -- RDC + fichero separado sí logra una
llamada real, a diferencia del intento 1 (mismo fichero, sin RDC).

**Verificación bit a bit**: `-615.5737694991`, idéntico a producción.

**Registros de `k_vpot_t`**: medido con `ncu` igual que antes.

| | Registros/hilo de `k_vpot_t` |
|---|---|
| Producción | **106** |
| Con RDC (llamada real confirmada) | **106** |

**Sin cambio** -- ni sube (como el intento 1, inlineado) ni baja. Una
llamada real de verdad no penaliza el pico de registros del llamador
(coherente con el mecanismo de "ventana separada" de `fusion-angle-hehe.md`),
pero tampoco lo reduce: el pico de 106 sigue estando marcado por otra
parte de la cadena, no por este bloque de 6 variables.

**Tiempo real** (rondas alternas, 2000w, conf fresco cada ronda):

| Ronda | Producción | Con RDC |
|---|---|---|
| 1 | 22,02 s | 24,92 s |
| 2 | 21,76 s | 21,67 s |
| 3 | 23,85 s | 22,09 s |
| **Media** | **22,54 s** | **22,89 s** |

+1,6% de media, orden se invierte entre las 3 rondas -- dentro del ruido
térmico, neutro.

**Conclusión intento 2**: neutro en registros y en tiempo. RDC consigue el
efecto técnico buscado (llamada real, sin penalización) pero no hay ningún
beneficio que capturar -- el techo de registros de `k_vpot_t` no lo marca
este bloque. No se lleva a producción (y además RDC es una bandera de
compilación global, cambiaría el comportamiento de inlining de TODO el
proyecto, no solo de esta función).

## Intento 3: `BLOCK`/`END BLOCK` (Fortran 2008), sin extraer a subrutina

Motivación: si el problema real es solo el ámbito de las variables
(scoping), quizás no hace falta ninguna subrutina -- Fortran 2008 permite
acotar el ámbito de variables con `BLOCK`/`END BLOCK` dentro de la misma
rutina.

**Implementación**: sobre `He_dihydrogen.f` SIN modificar (ni
`termino_dispersion` ni RDC), las líneas 413-437 originales se envuelven en
`BLOCK ... END BLOCK`, con `cos2,cos4,cos6,sin2,sin4,sin6` declaradas
dentro del bloque (eliminadas de la declaración externa de
`He_dihydrogen`).

**Verificación bit a bit**: `-615.5737694991`, idéntico a producción.

**Registros de `k_vpot_t`**: **106 -- sin cambio**, igual que producción.

**Conclusión intento 3**: neutro. El compilador ya hacía este análisis de
vida de variables automáticamente antes del cambio (asignación de
registros basada en el grafo de dependencias real del código compilado,
no en el scoping léxico del Fortran fuente) -- el `BLOCK` explícito no le
aporta ninguna información nueva al backend (`ptxas`). Confirma, en
sentido inverso, la misma "pico, no suma": el pico ya estaba en 106 antes
de cualquiera de estos 3 intentos, y ninguno lo mueve, porque ninguno
toca la parte del código que de verdad lo determina.

## Intento 4: memoria compartida como scratchpad de `cos2,cos4,cos6,sin2,sin4,sin6`

Motivación: distinta de los 3 intentos anteriores -- no busca cambiar el
patrón de inlining/scoping, sino sustituir el destino del posible
*spill* (memoria local, lenta, en DRAM) por memoria compartida (en el
propio chip). Ver `ideas-optimizacion-futuras.md`, idea ya identificada
antes de esta investigación concreta.

**Bloqueo real, no solo de sintaxis**: `SHARED` no está permitido en
subprogramas `host` (`NVFORTRAN-S-0134-Illegal attribute shared not
allowed in host subprograms`, error de compilación real, confirmado). Como
`termino_dispersion` -- y toda la cadena `He_dihydrogen`/`potenbh`/`vpot`/
`hpsi`/`dmc2` por encima -- es genuinamente `attributes(host, device)` (no
solo por costumbre: `msteps.f90:63` la llama de verdad desde
`pasodmc_cpu_gpurand`, la ruta CPU-secuencial-con-semillas-GPU de la
opción 6, confirmado forzando cada nivel a `device`-only uno a uno y
dejando que el enlazador señalara exactamente qué rompía en cada paso),
no se puede simplemente añadir `SHARED` a la subrutina existente.

Se comprobó también que `nvfortran` **no define `__CUDA_ARCH__`** (ni
ningún macro equivalente que distinga la pasada host de la device dentro
de una `attributes(host,device)`) -- confirmado con un error deliberado
dentro de un `#ifdef __CUDA_ARCH__` que nunca llegó a dispararse, y
listando todas las macros predefinidas (`nvfortran -cuda -Mpreprocess -dM
-E`): solo existe `_CUDA` (indica "este fichero usa CUDA Fortran", no
"esta es la pasada device"). Sin macro de diferenciación, la única forma
de usar memoria compartida aquí es una copia real, no una rama
condicional.

### Medida 1: micro-benchmark aislado (bypass total de la jerarquía)

Dos kernels `attributes(global)` mínimos, uno llamando a
`termino_dispersion` normal y otro a una copia `termino_dispersion_shared`
(`device`-only, `cos2,cos4,cos6,sin2,sin4,sin6` en `SHARED(32)`, indexadas
por `threadIdx%x`) -- un kernel nunca lo ve la CPU, así que no arrastra el
problema de dualidad host/device de la jerarquía real. Mismo `theta`/`rnorm`
de entrada en los dos, resultados numéricos verificados idénticos.

| Kernel | Registros/hilo | Memoria compartida |
|---|---|---|
| `k_test_dispersion` (normal) | 58 | 0 bytes |
| `k_test_dispersion_shared` | **52** | 1536 bytes/bloque (32×6×8 bytes, exacto) |

**-10,3% de registros, aislado.** Positivo, pero mide `termino_dispersion`
con muy poca presión de registros alrededor (kernel envoltorio casi
vacío) -- no representativo del contexto real de `k_vpot_t` (106
registros, con toda la cadena `He_dihydrogen`/`potenbh`/`vpot` compitiendo
por los mismos registros).

### Medida 2: contexto real, cadena paralela completa

Para medir el efecto dentro del contexto real sin tocar ni un carácter de
la cadena de producción (necesaria para la opción 6, ver arriba), se
construyó una cadena **paralela** enteramente nueva, `device`-only desde
el principio, reutilizando (con `use`, no reinventando) las variables
`device` ya inicializadas de los módulos reales en vez de duplicar su
inicialización:

- `He_dihydrogen_shared.f` (`module mHe_dihydrogen_shared`): copia íntegra
  de `He_dihydrogen.f`, `device`-only, llama a `termino_dispersion_shared`.
- `mpotenbh_shared_mod.cuf` (`module mpotenbh_shared`): copia de
  `potenbh`, `device`-only, reutiliza `dhcm` del módulo real
  (`use mpotenbh, only: dhcm`) en vez de una copia sin inicializar.
- `vpot_shared_mod.cuf` (`module mvpot_shared`): copia de `vpot` +
  `k_vpot_t` (mismo envoltorio de copia `atom_l`/`sprop_l` que el kernel
  real, para que la presión de registros de esa parte sea idéntica),
  reutiliza `opot` del módulo real (`use mvpot, only: opot`).
- `test_vpot_shared_launch.cuf`: lanza `k_vpot_shared_t` **una sola vez**,
  sobre `atom_p`/`sprop_p` reales (ya inicializados por la corrida real),
  justo después de que `dmc_gpu_pipeline` termine -- sin tocar el grafo
  CUDA capturado ni la corrida real (escribe a un array `pot_shared_p`
  descartable, nunca leído).

**Verificación bit a bit de la corrida real** (con el kernel de prueba
presente pero sin afectarla): `-615.5737694991`, idéntico a producción.
Resultados numéricos de `k_vpot_shared_t` verificados idénticos a
`k_vpot_t` en el micro-benchmark aislado.

**Registros, en contexto real** (`ncu`, mismo binario, misma corrida):

| Kernel | Registros/hilo | Memoria compartida |
|---|---|---|
| `k_vpot_t` (producción real) | 106 | 0 bytes |
| `k_vpot_shared_t` (cadena paralela con memoria compartida) | **106** | 1536 bytes/bloque |

**Sin ningún cambio.** El ahorro de -10,3% visto aislado **desaparece por
completo** en el contexto real: el pico de 106 registros lo fija otra
parte de la cadena (`He_dihydrogen`/`potenbh`/`vpot` tienen mucha más
presión de registros alrededor que absorbe sin más el pequeño ahorro de
estas 6 variables) -- mismo mecanismo de "pico, no suma" que en los
intentos 1-3. Además, memoria compartida es un recurso finito por SM,
igual que los registros: gastar 1536 bytes/bloque sin ningún beneficio de
registro medible es puro coste sin compensación.

**Conclusión intento 4**: negativo en el contexto que importa. El
micro-benchmark aislado (-10,3%) fue un espejismo de medir sin la presión
de registros real alrededor -- lección aplicable a cualquier
"optimización de una función" futura en este árbol: medir siempre en el
kernel real (`k_vpot_t`/`k_derananum_*_t`), nunca solo la función aislada.

## Conclusión general: NEGATIVO en los 4 intentos, no se lleva a producción

Ninguno de los 4 intentos (extracción simple, RDC, `BLOCK`, memoria
compartida) baja el techo de 106 registros de `k_vpot_t`. El patrón es
consistente: el pico de registros de `k_vpot_t` no lo determina el bloque
de dispersión de `He_dihydrogen` (ni sus 6 variables puramente locales,
ni su patrón de llamada) -- lo determina otra parte de la cadena
`He_dihydrogen`/`potenbh`/`vpot`, todavía sin identificar.

**Lección para futuros intentos de optimizar `He_dihydrogen`/`vpot`**:
antes de aislar cualquier bloque (por extracción, por scoping, o por
memoria compartida), hay que localizar primero **qué parte de la cadena
marca de verdad el pico de 106 registros** -- ninguno de los 4 intentos
de esta investigación lo hizo, todos asumieron que el bloque de dispersión
era un candidato razonable sin confirmarlo con datos primero.

## Comprobación final: ¿hay algún bloque "más grande" que sí sea candidato?

Pregunta directa tras el resultado negativo: si el bloque de dispersión
(8 líneas, 6 variables) no era el candidato correcto, ¿lo sería algún otro
bloque más grande de `He_dihydrogen`? Se reutilizó el CSV de perfilado ya
generado en la investigación original de `vpot`
(`v2-cuda-integracion/hibrido_instrumentado/ncu_vpot_source2.csv`,
`ncu --page source --import-source yes`) para desglosar, dentro de
`mhe_dihydrogen_he_dihydrogen_` (las 280 instancias de tráfico a memoria
`Local` ya identificadas como las más pesadas de toda la cadena, ver
`optimizacion-vpot.md`), qué instrucciones SASS concretas lo generan.

**Resultado: repartido, no concentrado.** Las cuentas van de 1 a 8
apariciones por instrucción (`ST.E.64`/`LD.E.64`/`STL.64`/`LDL.64`),
esparcidas por docenas de accesos distintos -- ninguna concentra una
fracción sustancial del total. No hay ningún bloque grande identificable
que domine el tráfico local dentro de `He_dihydrogen`, igual que ya se
vio a nivel de función completa (`optimizacion-vpot.md`: 280 en
`He_dihydrogen`, repartidas entre otras ~11 funciones más, ninguna
dominante por sí sola salvo `He_dihydrogen`).

Esto confirma, con datos y no con intuición, que **no existe un "bloque
más grande" candidato mejor que el de dispersión** -- el problema no es
que se eligiera mal el bloque a extraer, es que el techo de registros de
`He_dihydrogen` es una propiedad de la función completa (demasiadas
variables vivas a la vez en muchos puntos distintos, repartidas por todo
el cuerpo), no de ningún fragmento aislable. Extraer cualquier otro
bloque, con cualquiera de los 4 métodos ya probados, probablemente
tropezaría con la misma pared.

**Vía que sí quedaba abierta** (probada a continuación, Intento 5): en vez
de extraer una parte de `He_dihydrogen` para bajar registros, atacar el
problema por el lado de la ocupación/paralelismo -- dividir en kernels
concurrentes, al estilo `derananum-split-concurrente.md`.

## Intento 5: split en 2 kernels concurrentes (He4-He4 pares vs He-impureza)

### La idea y su verificación de independencia

`He_dihydrogen` tiene dos bucles que calculan cantidades físicas
distintas, leyendo la misma entrada (`X`, posiciones de los átomos de He)
pero sin que el segundo dependa de la salida del primero:

- **`DO J1=1,N-1 / DO J2=J1+1,N`** (líneas 312-325 originales):
  interacción par a par He4-He4 (`V_and_Vp_hehe`) -> `ENERGY1`.
- **`DO J1=1,N`** (líneas 374-675 originales): interacción de cada átomo
  de He con la molécula impureza (dispersión + inducción fusionadas) ->
  `ENERGY2`, `ENERGY3`.

Verificado con `grep` que el segundo bucle **no referencia `G` ni
`ENERGY1` en ningún punto** -- independencia real, no supuesta.

### Viabilidad de concurrencia real (confirmada con el código del pipeline)

`dmc2_pipeline.cuf` ya usa exactamente el mecanismo que haría falta:
`k_vpot_t` corre en su propio stream (`stream_b`), concurrente con
`k_derananum_he4_t` (stream_a) y `k_derananum_resto_t` (stream_c), y quien
consume `pot_p` después (`k_fase_c`) ya espera explícitamente a que
`k_vpot_t` termine vía `cudaEventRecord`/`cudaStreamWaitEvent` (líneas
228-229). Partir `k_vpot_t` en dos kernels concurrentes (uno por stream
nuevo) y hacer que `k_fase_c`/`k_fase_f` sumen `pot_hehe_p(i)+pot_impureza_p(i)`
en vez de un único `pot_p(i)` es mecánicamente el mismo patrón, no algo
nuevo -- confirmado leyendo el código real, no asumido.

### Arnés de medición: 2 subrutinas hermanas + kernels de prueba

`He_dihydrogen_hehe` y `He_dihydrogen_impureza` añadidas como subrutinas
hermanas `attributes(device)` dentro del mismo `module mHe_dihydrogen`
(reutilizan `FN1`/`FN2`/`treesum`/`kahansum` directamente, sin duplicar
nada). Kernels de prueba `k_test_hehe_t`/`k_test_impureza_t` (mismo
envoltorio `atom_l`/`sprop_l` que `k_vpot_t` real) más un kernel de
control `k_test_combined_t` que llama a `He_dihydrogen` **original sin
modificar**, para descartar sesgos del propio arnés de medición. Lanzados
20 veces cada uno sobre `atom_p`/`sprop_p` reales (ya inicializados por la
corrida real), fuera del grafo CUDA capturado, sin tocar la simulación
real -- bit a bit verificado idéntico (`-615.5737694991`) en todas las
variantes.

### Registros: el split sube el pico, no lo baja

| Kernel | Registros/hilo |
|---|---|
| `k_vpot_t` (real, combinado) | 106 |
| `k_test_hehe_t` (solo bucle He4-He4) | 94 |
| `k_test_impureza_t` (solo bucle impureza) | **112** |

El máximo de las dos piezas separadas (112) es **mayor** que el
combinado (106): al fusionar, el compilador puede reutilizar el mismo
presupuesto de registros entre las dos partes (nunca están vivas a la
vez); al separar en dos funciones/kernels independientes, cada una
resuelve su propia asignación sin visibilidad de la otra, y el resultado
conjunto es peor.

### Tiempo real: 2,4x más lento al separar (medido con `nsys`, no `ncu`)

| Kernel | Tiempo medio (20 lanzamientos, aislado, sin competir con derananum) |
|---|---|
| `k_test_combined_t` (control: `He_dihydrogen` original) | **3,74 ms** |
| `k_test_hehe_t` | 2,59 ms |
| `k_test_impureza_t` | 6,50 ms |
| **Suma hehe+impureza** | **9,09 ms** |
| `k_vpot_t` real (dentro del pipeline, compitiendo con derananum concurrente) | 5,65 ms |

El control (3,74 ms) confirma que el arnés de medición es correcto --
corre más rápido que el `k_vpot_t` real porque está aislado, sin competir
por SMs con `k_derananum_he4_t`/`resto_t`. Pero **hehe+impureza por
separado (9,09 ms) es 2,4x más que el control fusionado (3,74 ms)**,
ambos igual de aislados -- no es un artefacto de medición, es un coste
real de la separación.

### Por qué: más instrucciones ejecutadas y más tráfico local, no una
### diferencia de tamaño de bucle

Medido con `ncu` (`smsp__inst_executed.sum`,
`l1tex__t_sectors_pipe_lsu_mem_local_op_{ld,st}.sum`):

| Kernel | Instrucciones ejecutadas | Tráfico memoria local (LD+ST) |
|---|---|---|
| `k_test_combined_t` | 32.845.242 | 25.040.036 |
| `k_test_hehe_t` | 20.906.536 | 13.872.714 |
| `k_test_impureza_t` | 49.110.858 | 21.187.161 |
| **Suma hehe+impureza** | **70.017.394 (+112%)** | **35.059.875 (+40%)** |

`cuobjdump --dump-sass` descarta que sea una diferencia de desenrollado de
bucle: el tramo de la instrucción `BRA` de retroceso que cierra cada
bucle es **idéntico** en tamaño entre la versión aislada y la combinada
(bucle He4-He4: `0xE90` = 233 instrucciones en ambas; bucle impureza:
`0x3A70` = 934 instrucciones en ambas). El cuerpo del bucle no se
reestructura al separar -- lo que cambia es la presión de memoria
local/registros alrededor de él, que se traduce en más tráfico y, en la
GPU, en más instrucciones reemitidas (*replay*) por el pipeline de
memoria.

### Descartado: `G`/`R2` no son la causa (verificado, no confirma la primera hipótesis)

Hipótesis inicial: `G(natms,natms)`/`R2(natms,natms)` (900 elementos cada
una) del bucle He4-He4 solo se leen dentro del `IF(GTEST)` (código muerto,
`GTEST=.false.` fijo) -- ¿el compilador no las estaría eliminando?
**Prueba directa**: se quitó `G` por completo y se convirtió `R2` en
escalar (nunca se lee fuera de la misma iteración en la que se escribe,
en ningún punto del fichero) en `He_dihydrogen_hehe`, y se remidió.

**Resultado: CERO cambio** -- registros (94), instrucciones
(20.906.536), tráfico local LD (7.444.072) y ST (6.428.642) exactamente
iguales, bit por bit, al binario de antes del cambio. El compilador
**ya** eliminaba `G`/`R2` por completo gracias a `GTEST` ser una
constante de compilación -- la hipótesis inicial era incorrecta, esto no
era la causa del tráfico local extra (que viene de otro sitio, muy
probablemente del patrón de guardado/restauración de registros alrededor
de las llamadas reales a `V_and_Vp_hehe`, 190 veces por hilo -- no se
llegó a confirmar esto último con el mismo nivel de detalle, investigación
cerrada antes de esa comprobación).

### Evaluación de 3 técnicas propuestas para arreglarlo (sin implementar, análisis técnico)

Propuestas por el usuario para intentar hacer eficiente el split:

1. **Memoria compartida como *scratchpad* reutilizado entre las dos
   subrutinas**: viable de sintaxis (declarada en el kernel
   `attributes(global)`, pasada por argumento a subrutinas `device`-only,
   sin el problema de dualidad host/device de intentos anteriores) --
   pero **inviable de tamaño** para `G`/`R2`: 900 elementos/hilo x 32
   hilos/bloque x 8 bytes = 230 KB solo para `R2`, muy por encima del
   límite de memoria compartida por bloque de esta GPU. Sí sería viable
   para `e2terms` (60 elementos, ~15 KB) -- pero el problema de `G`/`R2`
   resultó no existir (ver arriba).
2. **`!$pgi inline` + `block`/`end block`**: contradicho por evidencia
   propia -- el Intento 1 ya mostró que forzar el reinlineado (sin
   `block`) da **peor** resultado (106->120), no igual; el Intento 3 ya
   mostró que `block` sin separar en subrutinas da **sin cambio**
   (106->106). La combinación exacta no se probó, pero la premisa de que
   "recupera el rendimiento de la función combinada" no está respaldada
   por los datos ya medidos.
3. **Desenrollado a escalares (*scalar replacement*)**: matemáticamente
   inviable para `G`/`R2` a 900 elementos (ningún hardware real tiene esa
   cantidad de registros/hilo); solo aplicable a arrays pequeños como
   `e2terms`, y requeriría que `N` fuera una constante de compilación en
   vez de un argumento en tiempo de ejecución como es ahora.

### Conclusión Intento 5: NEGATIVO, no se lleva a producción

Partir en 2 kernels concurrentes es **mecánicamente viable** (el
pipeline ya tiene el patrón de streams/eventos necesario, confirmado con
el código real) pero **contraproducente tal como se ha podido
implementar aquí**: 2,4x más lento que la función fusionada, con más
registros en el peor caso (112 vs 106) y +112% de instrucciones
ejecutadas. Las 3 técnicas propuestas para arreglarlo o son inviables de
tamaño (memoria compartida para `G`/`R2`) o ya están contradichas por
evidencia propia de intentos anteriores (`inline`+`block`) o son
matemáticamente inviables (*unroll* a escalares para arrays de 900
elementos). Incluso en un hipotético mejor caso (concurrencia perfecta,
sin ninguna penalización), el techo de mejora sería limitado: los dos
bucles no están equilibrados (2,6 ms vs 6,5 ms) como sí lo estaban
`he4`/`resto` en el split de `derananum` -- el límite teórico sería
`max(2,6, 6,5)=6,5 ms` frente a la suma secuencial actual, una mejora
acotada, no un salto grande como el de `derananum` (~2,6x).

**Lección**: el mecanismo de fondo de toda esta investigación (Intentos
1-5) es el mismo -- el optimizador de `nvfortran`/`ptxas` toma mejores
decisiones de registros y memoria local cuando ve el código completo de
una función que cuando lo ve repartido en piezas separadas, sea por
subrutina o por kernel. A diferencia del split de `derananum` (que
explotaba un desequilibrio real y limpio: `duhe4x` caro vs "resto" casi
gratis con `nhe3=0`), `vpot`/`He_dihydrogen` no tiene ese desequilibrio
tan claro entre sus partes, así que separar cuesta más de lo que se gana
en cualquiera de las formas probadas.

## Intento 6: memoria compartida para `e2terms`, código completo sin tocar nada más

Motivación: perfilado línea a línea (`nvdisasm --print-line-info-inline`,
sobre el binario real con `-gpu=lineinfo`, sin recompilar nada) de la
función `He_dihydrogen` **combinada real** de producción, filtrando las
líneas que solo generan spill dentro del bloque `IF(GTEST)` muerto
(nunca se ejecutan, `GTEST=.false.` fijo). De lo que sí se ejecuta
siempre, el candidato con más tráfico no probado todavía era la línea
`ENERGY2=treesum(e2terms,2*N)` (28 instrucciones `STL`/`LDL`) --
`e2terms(2*natms)` es un array real de 60 elementos que persiste durante
todo el bucle `DO J1=1,N` (se escribe 2 valores por iteración, se lee
completo al final), estructuralmente distinto de las 6 variables
escalares del Intento 4 (que dieron neutro).

**Implementación, código completo sin extraer nada**: a petición expresa
del usuario, `He_dihydrogen_shared.f` se reconstruyó desde cero a partir
del `He_dihydrogen.f` real de producción (no reutilizando ningún fichero
de los Intentos 1-4, que ya tenían `FN1`/`termino_dispersion` movidas a
módulos aparte) -- el único cambio es `e2terms(2*natms)` declarada
`SHARED(2*natms,32)` e indexada por `tid=threadIdx%x`, todo lo demás
(incluido el bloque de dispersión) se queda **inline, tal cual el
original**. Misma cadena paralela `device`-only de siempre
(`He_dihydrogen_shared`→`potenbh_shared`→`vpot_shared`, reutilizando
`dhcm`/`opot` de los módulos reales vía `use`) para poder usar `SHARED`
sin tocar la producción real.

**Verificación bit a bit**: `-615.5737694991`, idéntico a producción.

### Registros: primera bajada real de toda la investigación

| | Registros/hilo de `k_vpot_t` | Memoria compartida |
|---|---|---|
| Producción | 106 | 0 |
| Con `e2terms` en `SHARED` | **104** | 15.360 bytes/bloque (60×8×32, exacto) |

Baja de 106 a 104 -- pequeño, pero es la **primera vez en 6 intentos que
memoria compartida mueve el pico de registros de verdad**, ni neutro
(Intento 4) ni al alza (Intentos 1/inline).

### Pero el tiempo real no mejora -- de hecho empeora un poco

Control añadido en el mismo binario (`k_vpot_control_t`, llama al
`vpot`/`He_dihydrogen` originales sin ningún cambio, mismo envoltorio)
para comparar sin sesgo de compilación. 20 lanzamientos cada uno,
repetido con el orden invertido para descartar efecto de orden/deriva
térmica:

| Orden | `k_vpot_control_t` (original) | `k_vpot_shared_t` (`e2terms` shared) | Diferencia |
|---|---|---|---|
| control primero | 8.921,0 μs | 9.021,4 μs | +1,1% más lento |
| shared primero (invertido) | 8.907,8 μs | 9.004,7 μs | +1,1% más lento |

Consistente en ambos órdenes -- no es ruido ni efecto de calentamiento.
**Bajar 2 registros no se traduce en menos tiempo, y de hecho sale
ligeramente más lento.**

### Por qué: mismo hallazgo de `maxregcount` de siempre, esta vez confirmado con un caso real que sí bajaba registros

Coherente con el hallazgo ya establecido en `perfilado-medicion/fase1-registros/`:
la ocupación de `k_vpot_t` no está limitada por registros (grid de 125
bloques, muy por debajo de lo que el hardware podría sostener) --
`Waves/SM` no cambia entre 106 y 104 registros/hilo, así que bajar el
pico no libera ningún paralelismo adicional que capturar. Y el acceso a
memoria compartida, aunque más rápido que memoria local en teoría, tiene
su propio coste real (gestión del banco de memoria compartida,
sincronización implícita del *scheduler*) que aquí no tiene nada que
compensar -- de ahí el pequeño empeoramiento neto.

### Conclusión Intento 6: NEGATIVO, pese a ser el único que sí bajó registros

Es el intento más cercano a "funcionar" de toda la investigación (única
bajada real de registros, sin ningún efecto colateral de duplicar código
ni tocar nada más que una variable) -- y aun así no se traduce en mejora
de tiempo real, porque esta GPU a esta escala no está limitada por
registros. Confirma, con el caso más favorable posible, la misma
conclusión de fondo de toda la investigación: no hay margen de mejora
real bajando el pico de registros de `k_vpot_t`, con ninguna técnica.

## Intento 7: NO dividir en 2 kernels -- dividir en 2 WARPS del MISMO kernel

Idea del usuario, mecanismo distinto de todo lo probado hasta ahora. El
Intento 5 fracasó por duplicar prólogo/epílogo de pila al lanzar **2
kernels separados** -- pero eso es un problema de *lanzamiento*, no de
"dos bucles independientes en paralelo" en sí. La alternativa: **un
solo lanzamiento**, con un bloque de 64 hilos (2 warps) en vez de 32 --
warp 0 calcula `He4-He4` (`He_dihydrogen_hehe`, ya construida y
verificada en el Intento 5) para 32 walkers, warp 1 calcula
`He-impureza` (`He_dihydrogen_impureza`, ídem) para los MISMOS 32
walkers, combinando el resultado por memoria compartida + `syncthreads()`.

Por qué debería funcionar donde el Intento 5 no: dos warps del mismo
bloque tienen **residencia garantizada en el mismo SM** (parte del
modelo de ejecución de CUDA) y el planificador de warps puede
intercalar la emisión de instrucciones de uno mientras el otro está
parado esperando latencia (`myexp`/`mypow`) -- exactamente el mecanismo
que ya explica la ganancia de `W=16` en `fase1-bloque-por-walker.md`,
aquí aplicado por **rama de física** en vez de por átomo. Ni el coste
de duplicar prólogo/epílogo (sigue siendo un único lanzamiento, una
única pila) ni la falta de co-residencia garantizada (2 kernels
separados no la tienen) entran en juego.

**Implementación**: `k_vpot_2warp_t` en `test_2warp_mod.cuf`, reutiliza
`He_dihydrogen_hehe`/`He_dihydrogen_impureza` sin cambiarlas.
`tid=threadIdx%x`, `warp_id=(tid-1)/32`, `lane=mod(tid-1,32)+1`; cada
warp calcula su bucle y escribe en `hehe_s(32)`/`impureza_s(32)`
(memoria compartida, 512 bytes/bloque total); tras `syncthreads()`,
solo el warp 0 lee ambos y escribe `pot(i)=hehe_s(lane)+impureza_s(lane)`.

**Verificación bit a bit**: diferencia máxima `1,13686837721616030E-13`
frente a `k_vpot_control_t` (el `vpot`/`He_dihydrogen` original, mismo
binario) -- dentro de tolerancia numérica, confirmado con orden de
lanzamiento invertido para descartar sesgo.

### Registros: confirma "pico, no suma" con un caso real

| | Registros/hilo |
|---|---|
| `He_dihydrogen_hehe` sola (aislada) | 94 |
| `He_dihydrogen_impureza` sola (aislada) | 112 |
| `k_vpot_2warp_t` (las dos juntas, ramas mutuamente excluyentes por warp) | **112** |

No 94+112=206 -- el compilador toma el máximo de las dos ramas, no la
suma, porque nunca están vivas a la vez dentro del mismo hilo (cada
hilo solo ejecuta la rama de su propio warp).

### Tiempo: positivo y robusto en las 5 escalas probadas

`k_vpot_2warp_t` aislado vs `k_vpot_control_t` (original), 20
lanzamientos cada uno sobre `atom_p`/`sprop_p` reales:

| N walkers | Mejora |
|---|---|
| 500 | 35,1% más rápido |
| 1000 | 29,3% más rápido |
| 1500 | 25,7% más rápido |
| 2000 | 28,6% más rápido |
| 3000 | 28,4% más rápido |

No es un resultado aislado de una sola escala -- se mantiene en un
rango de 25-35% en las 5 escalas probadas.

### Migración a producción: confirmado en el pipeline completo

Migrado a `dmc2_pipeline.cuf` (`k_vpot_2warp_t`, bloque 64 hilos,
`nw_actual` en vez de `nmax` en las guardas -- a diferencia del test
aislado, la producción sí necesita respetar el conteo real de walkers
del paso DMC actual). Verificado bit a bit en el pipeline completo
(`-615.5737694991`, idéntico a producción) y medido con
`/usr/bin/time` sobre el binario real: **30,20 s (producción) vs
25,91 s (2warp) a 2000 walkers -- 14,2% más rápido en el pipeline
completo**, 1 ronda medida.

### Balance de carga entre los dos warps: NO están equilibrados

Medido con `clock64()` **dentro del propio kernel** (no en kernels
aislados por separado, que sufren de un contexto de registros/ocupación
distinto al concurrente): a N=3000 (188 bloques × 20 repeticiones),

| | Ciclos promedio/bloque |
|---|---|
| warp 0 (`hehe`, ENERGY1, O(N²/2)) | ~7,21M |
| warp 1 (`impureza`, ENERGY2+ENERGY3 fusionadas, O(N)) | ~12,21M |
| **ratio impureza/hehe** | **1,69x** |

El warp `hehe` termina en ~59% del tiempo que necesita `impureza` y se
queda inactivo en la barrera el resto -- el ~28% medido está limitado
por la mitad más lenta, no por un reparto equilibrado.

### Ocupación real: muy por debajo del límite de registros

`ncu --set full` sobre `k_vpot_2warp_t` a N=2000:

| Métrica | Valor |
|---|---|
| Registros/hilo | 112 |
| Memoria compartida estática | 512 bytes/bloque |
| Ocupación teórica (límite: registros, 8 bloques/SM) | 33,33% |
| **Ocupación lograda** | **10,50%** |

La brecha entre teórica y lograda indica que, a esta escala, la
rejilla (63 bloques a N=2000) no llega a saturar el límite de 8
bloques/SM que imponen los registros -- **sobra capacidad de warps
residentes sin usar por SM**, no estamos limitados por ocupación. Esto
directamente motiva el Intento 8.

### Conclusión Intento 7: POSITIVO -- mecanismo distinto al Intento 5, resultado opuesto

Confirma que "dividir en piezas independientes" no estaba mal en sí
(Intento 5 ya lo demostró: los dos bucles son independientes de
verdad, sin dependencia cruzada) -- lo que fallaba era **cómo**
dividir: 2 kernels separados pagan prólogo/epílogo por partida doble y
no garantizan co-residencia en el mismo SM; 2 warps del mismo
lanzamiento comparten pila, garantizan co-residencia, y permiten al
planificador solapar la latencia de una rama con el trabajo de la
otra. ~25-35% más rápido en el kernel aislado, 14,2% en el pipeline
completo, robusto en 5 escalas de walkers, bit a bit exacto.

## Intento 8: un TERCER warp -- separar dispersión de inducción (ya fusionadas)

Motivación directa de dos hallazgos del Intento 7: (1) los dos warps
NO están equilibrados (ratio 1,69x, `hehe` inactivo ~41% del tiempo en
la barrera) y (2) la ocupación lograda (10,5%) está muy por debajo del
límite teórico por registros (33,3%) -- sobra capacidad de warps
residentes por SM. Si hay hueco real, un tercer warp podría solaparse
con el tiempo que `hehe` pasa inactivo.

El candidato: el bloque `ENERGY2`+`ENERGY3` (dispersión+inducción) de
`He_dihydrogen_impureza` **ya estaba fusionado** en producción
precisamente porque ambos recorren el mismo rango de átomos y
necesitan el mismo `rvec`/`rnorm`/`onorm`/`theta`/`cos2`/`cos4`/`cos6`/
`btheta` (comentario explícito en `He_dihydrogen.f` real, línea ~346:
"rep+disp TT + Induction (FUSIONADOS)"). Separarlas en 2 warps
distintos **reintroduce ese cálculo duplicado** -- el experimento mide
si el solapamiento de latencia del tercer warp compensa ese recálculo.

**Implementación**: `He_dihydrogen_dispersion`/`He_dihydrogen_induccion`
añadidas como subrutinas hermanas nuevas en `He_dihydrogen.f`,
derivadas **directamente de la `He_dihydrogen` real sin fusionar**
(`v2-cuda-integracion/hibrido_instrumentado/He_dihydrogen.f`, no de la
versión ya fusionada) para no arrastrar ninguna modificación previa --
cada una recalcula el preámbulo completo (`vec_norm`×2, `angle`,
`scalar_product`, `mypow_log`+3×`mypow_desde_log` del coseno, `btheta`)
por su cuenta; `dispersion` añade además el seno, `norm6`, `myexp`,
`FN1` → `e2terms`/`treesum`; `induccion` añade `rh1`/`rh2`/`r0` + 6×`FN2`
→ `ENERGY3`. `k_vpot_3warp_t` en `test_3warp_mod.cuf`: bloque de 96
hilos (3 warps: 0=`hehe`, 1=`dispersion`, 2=`induccion`), combinadas
por 3 arrays en memoria compartida + `syncthreads()`.

**Verificación bit a bit**: diferencia máxima **0,0 exacta** frente al
control en las 5 escalas probadas (mejor incluso que el `1,14E-13` del
Intento 7 -- mismo orden de operaciones de punto flotante, sin ningún
reordenamiento).

### Tiempo: el mejor resultado de toda la investigación, robusto en 5 escalas

`k_vpot_3warp_t` vs `k_vpot_2warp_t` vs `k_vpot_control3_t` (original),
20 lanzamientos cada uno, mismo binario:

| N walkers | control | 2warp | 3warp | 3warp vs control | 3warp vs 2warp |
|---|---|---|---|---|---|
| 500 | 3,49 ms | 2,23 ms | 1,87 ms | 46,4% más rápido | 15,8% más rápido |
| 1000 | 5,14 ms | 3,58 ms | 2,61 ms | 49,1% más rápido | 27,1% más rápido |
| 1500 | 6,88 ms | 5,07 ms | 3,30 ms | 52,1% más rápido | 34,9% más rápido |
| 2000 | 9,09 ms | 6,39 ms | 4,35 ms | 52,1% más rápido | 31,9% más rápido |
| 3000 | 12,91 ms | 9,26 ms | 6,43 ms | 50,2% más rápido | 30,6% más rápido |

Patrón coherente: la ganancia de 3warp sobre 2warp crece de N=500 a
N=1500 (donde el coste fijo de lanzamiento pesa relativamente menos) y
se estabiliza en ~30-35% a partir de ahí. El coste de duplicar el
preámbulo trigonométrico entre `dispersion`/`induccion` queda
sobradamente compensado por aprovechar la ocupación libre que dejaba
el Intento 7.

### Conclusión Intento 8: POSITIVO, mejor resultado de toda la investigación

~50% más rápido que el original (frente al ~28% del Intento 7), ~30%
más rápido que el propio Intento 7, robusto en las 5 escalas de
walkers probadas, bit a bit exacto. Pendiente: remedir el balance de
carga entre los 3 warps (¿sigue siendo `hehe` el cuello de botella
tras el reparto?) y confirmar bloques residentes/SM reales antes de
comprometerse a este diseño para producción o escalar a más warps.

## Migración del Intento 8 a producción y el hallazgo de contención de SFU

Migrado `k_vpot_3warp_t` a `v2-cuda-integracion/hibrido_instrumentado/`
(`dmc2_pipeline.cuf`, `He_dihydrogen.f` con `He_dihydrogen_hehe`/
`_dispersion`/`_induccion` añadidas, `k_vpot_t` sin tocar como
referencia). Verificado bit a bit con conf inicial idéntica
(`-628.0111977886` en las dos versiones) y con orden alternado (4
corridas, original↔Intento8↔Intento8↔original) para descartar sesgo
térmico: pipeline completo **28,05 s → 25,01 s de media, ~11-14% más
rápido**, consistente en las 4 corridas.

### `derananum_he4`/`resto` casi duplican su duración al correr junto al nuevo vpot

Perfilado con `nsys --cuda-graph-trace=node` tras la migración:

| Kernel | Antes (`k_vpot_t` original) | Después (`k_vpot_3warp_t`) | Cambio |
|---|---|---|---|
| `k_vpot_(3warp)_t` | 5,52 ms | 4,97 ms | -9,9% (no el ~50% aislado) |
| `k_derananum_resto_t` | 2,50 ms | 4,79 ms | **+91,7%** |
| `k_derananum_he4_t` | 2,23 ms | 4,43 ms | **+99,2%** |

Confirmado con traza literal de solapamiento (`cuda_gpu_trace`): los 3
arrancan en la misma ventana de <400 ns y se solapan de verdad durante
~5 ms cada uno -- no es artefacto de medición. Descartado sesgo
térmico/de orden con 4 corridas alternadas (`original A/B` y
`intento8 A/B`): la corrida `original B` (medida última, GPU más
caliente) da el mismo tiempo que `original A` (medida primera, GPU
fría) -- el efecto depende de qué kernel corre, no de cuándo se mide.

### Ocupación real (muestreo `nsys --gpu-metrics-*`, no serializa como `ncu`)

Durante la ventana de solapamiento triple real (marcas de tiempo
exactas, ~5,16 ms):

| Métrica | Valor |
|---|---|
| SM Active | 79,7% |
| Warps activos (ocupación lograda) | 20,1% |
| **Warps sin asignar en SMs activos** | **59,6%** |
| Ancho de banda DRAM | <3% |

Descarta las dos hipótesis simples: no es saturación de ocupación (60%
de los huecos de warp siguen libres en el pico de solapamiento) ni de
ancho de banda DRAM (<3% de uso).

### Experimento de planificación: concurrencia total vs. serialización vs. escalonado

Se probaron 3 coreografías de streams sobre el mismo `k_vpot_3warp_t`
(copia aislada `v2-cuda-integracion/split-sfu-stagger-tmp/`, eventos
`cudaEventRecord`/`cudaStreamWaitEvent` nuevos, sin tocar los kernels):
concurrencia total (la actual), serialización total (`vpot` espera a
que terminen `he4` Y `resto`), y escalonado parcial (`vpot` espera
solo a `he4`, sigue solapando con la cola de `resto`). GPU-only
(tiempo de kernel `nsys`, no "tiempo de CPU" -- ese resultó
contaminado por carga de CPU compartida del portátil, hasta 20% de
ruido entre repeticiones del mismo binario, confirmado revisando
`nvidia-smi`/`ps aux`):

| Variante | `he4` | `resto` | `vpot` | Camino crítico (GPU) |
|---|---|---|---|---|
| Concurrente | 4,43 ms | 4,79 ms | 4,97 ms | **4,97 ms** |
| Serial | 2,13 ms | 2,33 ms | 2,64 ms | 2,33+2,64 = **4,97 ms** |
| Escalonado | 2,13 ms | 2,74 ms | 2,81 ms | **4,93 ms** |

Las tres dan prácticamente el mismo tiempo de GPU (<1% de diferencia).
Serializar recupera la velocidad aislada de cada kernel (`he4`/`resto`
casi vuelven a su tiempo en solitario) pero pierde todo el solape --
se cancela casi exactamente. Ninguna coreografía de streams mejora
sobre la concurrencia total ya en producción.

### Confirmación mediante *stall reasons* (`ncu`, no solo patrón indirecto)

Hipótesis del usuario: el cuello real es la unidad de función especial
(SFU/*pipe* XU), que ejecuta `myexp`/`mysin`/`mycos`/`mypow_log`/
`mypow_desde_log` -- muy pocas por SM (orden de magnitud menor que las
ALU normales), compartida por todos los warps residentes,
independientemente de si vienen del mismo kernel o de kernels
distintos. Medido con `ncu --metrics` sobre los 3 kernels por separado
(con su ocupación real, sin reducir grid -- esto SÍ lo puede medir
`ncu` en solitario, a diferencia de la contención cruzada entre
kernels concurrentes):

| Kernel | `short_scoreboard` | `long_scoreboard` | `wait` | `math_pipe_throttle` | Instrucciones XU |
|---|---|---|---|---|---|
| `he4` | **53,3%** | 15,8% | 14,4% | 0,000% | 59.850 |
| `resto` | **60,0%** | 11,2% | 14,4% | 0,001% | 105.399 |
| `vpot_3warp` | **55,3%** | 3,9% | 5,0% | 0,006% | 144.324 |

`smsp__warps_issue_stalled_short_scoreboard`: "cumulative # of warps
waiting for a scoreboard dependency on MIO" -- en esta arquitectura la
vía MIO también sirve los resultados de la pipe XU/SFU (distinta de
`long_scoreboard`, que es memoria global/local). `math_pipe_throttle`
(esperar puerto de emisión libre hacia la pipe) es ~0% en los tres --
por eso no se veía nada al medir esa métrica al principio. El cuello
real es esperar el RESULTADO de una operación SFU ya emitida, no poder
emitir una nueva -- dominante (53-60%) en los tres kernels, con código
y estructura distintos, no es casualidad de uno solo.

**Conclusión de la investigación de contención**: confirmado mediante
*stall reasons* medidos, no solo un patrón indirecto (ocupación/DRAM/
SM Issue) -- la SFU compartida es el límite real de trabajo total
concurrente. Ninguna coreografía de streams lo esquiva (ver
experimento de arriba). El Intento 8 se queda en producción tal cual
(concurrencia total, ~11-14% real) -- no hay margen adicional por esta
vía sin reducir el número real de instrucciones SFU (`myexp`/`mypow`/
etc.), un cambio de fórmulas mucho más invasivo, fuera de alcance de
esta investigación.

## Intento 9: partir `hehe` en 2 warps dentro de `k_vpot_3warp_t`

Motivación: con el balance de carga del Intento 8 confirmado
desequilibrado (`hehe` ~2x el tiempo de `dispersión`/`inducción` por
separado, ver arriba) y la contención de SFU como techo real en vez de
la ocupación, ¿sigue habiendo margen partiendo `hehe` en 2 warps más
(por PARIDAD de `J1`, mismo patrón que separar dispersión/inducción)?
`V_and_Vp_hehe` también usa `myexp`/`mysin`/`mycos` -- no es un bucle
libre de SFU, así que no hay motivo a priori para esperar mejor
resultado que el Intento 8.

**Implementación**: `He_dihydrogen_hehe_mitad(N, X, ENERGY1, PARIDAD)`
en copia aislada `v2-cuda-integracion/split-4warp-tmp/` (clonada de
`split-3warp-tmp/`) -- mismo bucle de `hehe`, filtrado por
`MOD(J1,2).eq.PARIDAD`, sin reordenar la acumulación dentro de cada
mitad. `k_vpot_4warp_t`: bloque de 128 hilos (4 warps: `hehe` par,
`hehe` impar, dispersión, inducción), combinados por memoria
compartida + `syncthreads()`.

**Verificación bit a bit**: diferencia máxima `1,14E-13` frente al
control, en las 5 escalas probadas.

### Registros y ocupación: se mantienen favorables

94 registros/hilo (igual que el Intento 8 -- "pico, no suma" se
mantiene). Ocupación teórica sube ligeramente a 41,67% (antes 37,5%),
lograda 37,62% -- muy cerca del techo.

### Tiempo: gana claramente en N pequeño, pero decae y se anula en N grande

| N walkers | Intento 9 vs Intento 8 |
|---|---|
| 500 | +20,1% |
| 1000 | +9,9% |
| 1500 | +7,9% |
| 2000 | -8 a -15% (anomalía de cuantización de oleadas, ver abajo) |
| 3000 | +6,9% |
| 4000 | +4,8% |
| 5000 | +3,8% |
| **6000** | **-0,4%** (empatado, dentro de ruido) |
| **8000** | **+0,06%** (empatado, dentro de ruido) |

**N=2000, anomalía explicada**: con 128 hilos/bloque, `Block Limit
Registers` baja de 6 (Intento 8) a 5 -- techo de bloques/SM de 144 a
120. A N=2000 (126 bloques) caben 120 en la primera oleada y sobran
solo 6 para una segunda oleada casi vacía (6 de 24 SM ocupados) --
efecto clásico de cuantización de oleadas. A N=1500 (95 bloques) cabe
todo en una oleada; a N=3000 (188 bloques) la segunda oleada ya está
bien poblada (68/120) -- por eso solo N=2000 sale perjudicado.

### Conclusión Intento 9: POSITIVO en N pequeño, NO recomendado para producción

La ganancia decae de forma consistente con N y se anula por completo a
partir de N≈6000 -- justo la escala de walkers de las corridas reales.
No compensa la complejidad añadida (4 warps, más registros agregados)
para un beneficio que desaparece en el rango de uso real. **No
migrado a producción.**

## Intento 10: partir `derananum_he4` en 2 warps (territorio nuevo)

Motivación: `wavef_derwavefhe4` (la función real de `k_derananum_he4_t`)
tiene la misma estructura que `hehe` -- bucle de pares
`iatom=1,nhe4-1; jatom=iatom+1,nhe4`, con `mypow_log`/
`mypow_desde_log`/`myexp` (mismo perfil SFU) -- pero con una diferencia
real: además del escalar `ujas` (→ `wfhe4=myexp(ujas)`), acumula
`d1wf(iatom)`/`d2wf(iatom)` (arrays por átomo, la derivada, salida
real usada después -- no código muerto como en `hehe`).

**Implementación**: `wavef_derwavefhe4_mitad` en copia aislada
`v2-cuda-integracion/split-he4-2warp-tmp/` -- mismo bucle filtrado por
paridad de `iatom`, sin aplicar el `myexp` final ni la corrección de
`d2wf` (dependen del total combinado). Combinación **sin memoria
compartida 2D** (un array compartido (átomo,warp,lane) se dispararía a
~48 KB y arruinaría la ocupación) -- en su lugar: warp 0 escribe su
parcial directamente en el array GLOBAL persistente (que de todos
modos se sobreescribe entero cada paso), `syncthreads()`, warp 1 lee +
suma su propio parcial + aplica la corrección `dot_product` y el
`myexp` final. `ujas` (escalar) se combina aparte, por memoria
compartida (32 doubles, barato). `k_derananum_he4_2warp_t`: bloque de
64 hilos (2 warps).

**Verificación bit a bit**: diferencias `1,6E-35` (wfhe4), `5,3E-15`
(d1wf), `1,1E-13` (d2wf) -- dentro de tolerancia.

### Registros y ocupación

88 registros/hilo, igual en control y 2warp ("pico, no suma"). Memoria
compartida estática solo 256 bytes (`ujas_s`). Ocupación teórica igual
en ambos (41,67%, límite de registros) pero **lograda** muy distinta:
15,9% en el original (32 hilos/bloque) vs 31,2% en el de 2 warps (64
hilos/bloque) -- a N=3000 el grid original ni siquiera llena una
oleada completa (0,39 waves/SM); con bloques más grandes, la misma
rejilla llena el 78% de una oleada. Parte de la ganancia en N medio
viene de mejor empaquetado, no solo de solapar latencia.

### Tiempo: gana fuerte en N pequeño, cruza a NEGATIVO antes que el Intento 9

| N walkers | Intento 10 vs original |
|---|---|
| 500 | +42,6% |
| 1000 | +29,8% (ruido de CPU compartida, ver nota) |
| 1500 | +14,8% (ídem) |
| 2000 | +2,7% |
| 3000 | +3,1% |
| **4000** | **-13,5%** |
| **6000** | **-2,9%** |

(N=1000/1500 con mucha variación entre repeticiones -- misma
contaminación de CPU compartida del portátil ya vista antes; se usa la
mediana en vez de la media para esos dos.)

Mismo patrón que el Intento 9 (fuerte en N pequeño, decae con N) pero
cruza a negativo antes (ya en N=4000) y se queda ligeramente negativo
en vez de estabilizarse en empate -- la combinación aquí no es sumar
un escalar en memoria compartida (`hehe`), sino leer-sumar-escribir
arrays de 20 átomos en memoria global tras un `syncthreads()`: un
coste fijo real por bloque que no se diluye, y que a partir de cierto
N pesa más que el margen de ocupación libre.

### Conclusión Intento 10: mismo veredicto que el Intento 9, más contundente

Por debajo de ~N=2000 gana claramente, pero en el rango de walkers de
las corridas reales el resultado es plano o negativo. **No migrado a
producción.**

## Conclusión general de la línea "más warps"

El patrón se repite en 2 kernels con estructura y coste de combinación
distintos (`hehe`: escalar vía memoria compartida; `he4`: arrays vía
memoria global) -- no es un accidente de un caso concreto. La ganancia
por solapar warps dentro de un kernel es real y medible en N pequeño,
pero se diluye (Intento 9) o se invierte (Intento 10) según crece el
número de oleadas necesarias para cubrir la rejilla, precisamente en
el rango de walkers de uso real. Combinado con el hallazgo de
contención de SFU (confirmado con *stall reasons*, no solo inferido):
la vía de "seguir añadiendo warps" para `vpot`/`derananum` se da por
agotada para producción. El Intento 8 (3 warps en `vpot`, ~11-14% real
en el pipeline completo) sigue siendo la mejora vigente.

## Intento 11: ILP dentro de un hilo en vez de más warps

Idea del usuario, ataca la causa confirmada (`short_scoreboard`, ver
más arriba) por una vía distinta a todo lo anterior: en vez de tapar
la espera de un resultado SFU con OTRO warp (la vía ya agotada), dar
al PROPIO hilo trabajo independiente que emitir mientras espera --
software pipelining/desenrollado manual. Los `N` átomos del `DO
J1=1,N` de `He_dihydrogen_dispersion` son independientes entre sí
(cada uno escribe `e2terms(2*J1-1)`/`e2terms(2*J1)`, índices propios,
sin dependencia cruzada) -- desenrollar 2 a la vez, emitiendo las
llamadas SFU de los dos átomos antes de consumir cualquiera de los dos
resultados, no debería alterar el resultado (`treesum`/`kahansum`
posterior no depende del orden en que se calculan los átomos, solo del
contenido final del array).

**Implementación**: `He_dihydrogen_dispersion_ilp2` en copia aislada
`v2-cuda-integracion/split-ilp2-tmp/` (clonada de `split-3warp-tmp/`)
-- mismo cálculo que `He_dihydrogen_dispersion`, desenrollado en pares
(`_a`/`_b`) con las llamadas `mypow_log`/`mypow_desde_log`/`mycos`/
`mysin`/`myexp` de ambos átomos emitidas antes de consumir sus
resultados; remanente del último átomo si `N` es impar. Comparación
PURA (mismo envoltorio de 32 hilos/bloque en las dos versiones, sin
ningún truco de warps) para aislar solo el efecto de ILP.

**Verificación bit a bit**: diferencia máxima **0,0 exacta**.

### Tiempo: sin ninguna ganancia medible

| | Registros/hilo | Ocupación lograda (N=3000) | Tiempo |
|---|---|---|---|
| Original (secuencial) | 94 | 14,77% | 1,0869 ms |
| ILP (2 átomos entrelazados) | **151** (+61%) | 14,79% | 1,0875 ms |

Diferencia de tiempo: 0,06% -- ruido puro. Duplicar las variables
locales para poder emitir las 2 llamadas SFU antes de consumir
cualquiera dispara los registros un 61% (el compilador mantiene vivo
el doble de valores intermedios a la vez), sin ningún beneficio de
tiempo a cambio.

### Por qué: confirmado con SASS, no supuesto -- ninguna de las 5 funciones está inlineada

`nvdisasm` sobre `He_dihydrogen_dispersion_ilp2` (con
`-gpu=lineinfo`, mismo binario ya compilado): **70 instrucciones
`CALL.ABS.NOINC`**, ninguna de `mycos`/`mysin`/`myexp`/`mypow_log`/
`mypow_desde_log` inlineada -- los recuentos cuadran exactamente con
el código fuente (3 `mycos`=2 del bucle principal+1 del resto impar;
9 `mypow_log`=3/átomo×3; 21 `mypow_desde_log`=7/átomo×3; 6
`myexp`=2/átomo, uno directo y otro dentro de `FN1`). El orden real de
las llamadas en el SASS confirma que el desenrollado SÍ se generó tal
cual se escribió (p.ej. las 6 llamadas a `mypow_desde_log` salen
seguidas en el orden A,B,A,B,A,B pretendido) -- pero no importa:
`CALL.ABS.NOINC` es una llamada síncrona y bloqueante, el hilo no
puede emitir la segunda llamada independiente hasta que la primera
retorna, sin importar el orden en el código fuente. El ILP a nivel de
código fuente es estructuralmente incompatible con subrutinas
`device` reales no inlineadas -- solo funcionaría si estuvieran
inlineadas de verdad.

**Se probó forzar el inline** (`-Minline=name:mycos,name:mysin,
name:myexp,name:mypow_log,name:mypow_desde_log`, con `-Minfo=inline`
para diagnóstico): **sin ningún efecto** -- SASS idéntico, mismas 70
llamadas, mismos objetivos. `-Minline` no aplica a código
`attributes(device)` de CUDA Fortran (verificado también que `-gpu=`
no tiene ninguna suboption de inline, revisado `-gpu=help` completo).

**Coste de un inline manual, evaluado y descartado**: `mycos` sola
despacha a otras 6 funciones (`high32_of`, `do_cos`, `do_sin`,
`reduce_sincos`, `mybranred`, `do_sincos`), cada una con lógica real
de reducción de rango y tablas de consulta (misma implementación fiel
a `glibc` de `optimizacion-mypow.md`/`docs-kernels/glibc_math.md`).
Aplanar de verdad las 5 funciones (`mycos`, `mysin`, `myexp`,
`mypow_log`, `mypow_desde_log`) a mano significaría replicar
transitivamente ~200-400+ líneas de lógica anidada por función dentro
de la subrutina llamadora, con riesgo real de romper la exactitud bit
a bit -- y aun haciéndolo bien, el resultado seguiría siendo incierto:
ya duplicar solo las variables locales (sin ningún inline) disparó los
registros un 61%; aplanar árboles de funciones completos
probablemente dispararía los registros mucho más, pudiendo anular
cualquier beneficio de ILP por la misma vía que ya limitó los
Intentos 9-10. Desproporcionado frente al beneficio esperado -- no se
persigue.

### Conclusión Intento 11: NEGATIVO, con las dos ramas de la hipótesis confirmadas

(1) No hay inline automático de las funciones matemáticas -- 70
llamadas reales, confirmado con SASS. (2) No existe una vía barata de
forzarlo para código `device` -- `-Minline`/`-gpu=` no lo soportan, y
el inline manual es desproporcionado (200-400+ líneas por función,
riesgo de bit-exactitud, beneficio incierto por la misma vía de
presión de registros que ya cerró los Intentos 9-10). El ILP a nivel
de código fuente no es una vía viable en esta base de código mientras
`myexp`/`mypow`/etc. sigan siendo subrutinas `device` reales.

## Ficheros

- Copia aislada (Intentos 1-4): `v2-cuda-integracion/split-he-dihidrogen-tmp/`
  (no versionada, ya recortada al archivar).
- Copia aislada (Intento 5): `v2-cuda-integracion/split-loop-tmp/` (no
  versionada, ya recortada al archivar en `gpu-split-loops/`).
- **Intento 1** (extracción simple, mismo fichero): `termino_dispersion`
  como subrutina hermana en `He_dihydrogen.f` (módulo `mHe_dihydrogen`),
  llamada sustituye a las líneas 413-437 originales; declaraciones locales
  de `cos2,cos4,cos6,sin2,sin4,sin6` eliminadas de `He_dihydrogen`.
- **Intento 2** (RDC): `mFN1_mod.cuf` (`FN1` movida, no duplicada),
  `mterminodispersion_mod.cuf` (`termino_dispersion` movida a fichero
  propio), compilado/enlazado con `-gpu=lineinfo,rdc`.
- **Intento 3** (`BLOCK`): variante de `He_dihydrogen.f` sin ningún cambio
  de `termino_dispersion`/RDC, solo `BLOCK`/`END BLOCK` envolviendo las
  líneas 413-437 originales.
- **Intento 4** (memoria compartida): `termino_dispersion_shared` +
  `k_test_dispersion`/`k_test_dispersion_shared` en
  `mterminodispersion_mod.cuf` (micro-benchmark aislado);
  `He_dihydrogen_shared.f`, `mpotenbh_shared_mod.cuf`,
  `vpot_shared_mod.cuf`, `test_vpot_shared_launch.cuf` (cadena paralela
  completa, contexto real) + una línea añadida en `qmccluster.f90`
  (`call lanza_test_vpot_shared()` tras `case(7)`, no afecta a la corrida
  real -- escribe a un array descartable nunca leído).
- **Intento 5** (split en 2 kernels): `He_dihydrogen_hehe`/
  `He_dihydrogen_impureza` añadidas como subrutinas hermanas en
  `He_dihydrogen.f` (módulo `mHe_dihydrogen`); `test_split_loops_mod.cuf`
  (`vpot_test_hehe`/`vpot_test_impureza`/`vpot_test_combined` + kernels
  `k_test_hehe_t`/`k_test_impureza_t`/`k_test_combined_t`/
  `k_test_ccuerpo_only_t`, reutilizan `dhcm`/`opot` de los módulos reales
  vía `use`); `test_split_loops_launch.cuf` (lanza cada kernel 20 veces
  sobre `atom_p`/`sprop_p` reales) + una línea en `qmccluster.f90`
  (`call lanza_test_split_loops()` tras `case(7)`).
- **Intento 6** (`e2terms` en memoria compartida): copia aislada nueva
  `v2-cuda-integracion/split-e2terms-tmp/` (no versionada, ya archivada
  aquí) -- `He_dihydrogen_shared.f` reconstruida desde cero del
  `He_dihydrogen.f` real (sin ningún resto de los Intentos 1-4), solo
  `e2terms` cambiada a `SHARED`; `vpot_shared_mod.cuf` ampliado con
  `vpot_control`/`k_vpot_control_t` (llama al `vpot`/`He_dihydrogen`
  originales, para comparar en el mismo binario); `test_vpot_shared_launch.cuf`
  (propio de esta copia, no el del Intento 4) lanza ambos 20 veces cada
  uno, dos veces con el orden invertido.
- **Intento 7** (2 warps del mismo kernel, He4-He4 vs He-impureza):
  copia aislada `v2-cuda-integracion/split-2warp-tmp/` (no versionada) --
  `k_vpot_2warp_t`/`k_vpot_control_t` en `test_2warp_mod.cuf` (reutiliza
  `He_dihydrogen_hehe`/`He_dihydrogen_impureza` del Intento 5 sin
  cambiarlas), `test_2warp_launch.cuf` (correción + 20 repeticiones,
  orden invertido) y `test_2warp_diag_launch.cuf`/`k_vpot_2warp_diag_t`
  (medición de balance de carga entre warps con `clock64()`, ver
  sección de balance más arriba). Migrado a producción en
  `dmc2_pipeline.cuf` (`v2-cuda-integracion/hibrido_instrumentado/`),
  staging verificado en `v2-cuda-integracion/split-prod-migracion/`.
- **Intento 8** (3er warp, separa dispersión de inducción): copia
  aislada `v2-cuda-integracion/split-3warp-tmp/` (no versionada, clonada
  de `split-2warp-tmp/`) -- `He_dihydrogen_dispersion`/
  `He_dihydrogen_induccion` añadidas en `He_dihydrogen.f` (derivadas
  directamente de la `He_dihydrogen` real sin fusionar);
  `k_vpot_3warp_t`/`k_vpot_control3_t` en `test_3warp_mod.cuf`;
  `test_3warp_launch.cuf` (correción contra control + 2warp, 20
  repeticiones de los 3). Migrado a producción en
  `v2-cuda-integracion/hibrido_instrumentado/` (`dmc2_pipeline.cuf`,
  `He_dihydrogen.f`) -- ~11-14% más rápido en el pipeline completo,
  verificado bit a bit con orden alternado.
- Copia aislada (experimento de contención SFU): `v2-cuda-integracion/
  split-sfu-stagger-tmp/` (no versionada, clonada de
  `hibrido_instrumentado/` con el Intento 8 ya migrado) -- 3 variantes
  de coreografía de streams (concurrente/serial/escalonado) sobre el
  mismo `k_vpot_3warp_t`, eventos `cudaEventRecord`/
  `cudaStreamWaitEvent` nuevos (`ev_he4_1`/`ev_he4_2`), sin tocar
  ningún kernel.
- **Intento 9** (4º warp, parte `hehe` por paridad dentro de `vpot`):
  copia aislada `v2-cuda-integracion/split-4warp-tmp/` (no versionada,
  clonada de `split-3warp-tmp/`) -- `He_dihydrogen_hehe_mitad` añadida
  en `He_dihydrogen.f`; `k_vpot_4warp_t`/`k_vpot_control4_t` en
  `test_4warp_mod.cuf`; `test_4warp_launch.cuf`. No migrado a
  producción -- ganancia se anula a partir de N≈6000 walkers.
- **Intento 10** (2 warps en `derananum_he4`, territorio nuevo): copia
  aislada `v2-cuda-integracion/split-he4-2warp-tmp/` (no versionada,
  clonada de `hibrido_instrumentado/`) -- `wavef_derwavefhe4_mitad`
  añadida en `der_wavefhe4_mod.cuf`; `k_derananum_he4_2warp_t`/
  `k_derananum_he4_control_t` en `test_he4_2warp_mod.cuf`;
  `test_he4_2warp_launch.cuf`. No migrado a producción -- ganancia
  cruza a negativo a partir de N≈4000 walkers.
- **Intento 11** (ILP dentro de un hilo): copia aislada
  `v2-cuda-integracion/split-ilp2-tmp/` (no versionada, clonada de
  `split-3warp-tmp/`) -- `He_dihydrogen_dispersion_ilp2` añadida en
  `He_dihydrogen.f` (desenrollado manual en pares); `k_dispersion_
  orig_t`/`k_dispersion_ilp2_t` en `test_ilp2_mod.cuf`;
  `test_ilp2_launch.cuf`; `compilar_pipeline_inline.sh` (variante con
  `-Minline=name:...`, para el experimento de inline forzado). Sin
  ganancia medible, sin migrar -- ver conclusión del Intento 11 para
  el porqué (confirmado con SASS, no supuesto).
