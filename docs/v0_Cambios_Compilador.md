# Primer intento de compilación con el toolchain de GPU (`nvfortran`)

## 0. Alcance de este hito

Este documento recoge **todos** los cambios hechos en `Compilacion-GPU/` para conseguir que el código compile y se ejecute con **`nvfortran`** (NVIDIA HPC SDK), el compilador documentado en [`docs/hardware_specs.md`](../docs/hardware_specs.md) para este TFG.

Importante para no llevar a confusión: en este hito **no se ha añadido ningún offload real a GPU** (ni directivas OpenACC ni CUDA Fortran). El objetivo, decidido explícitamente antes de tocar nada, era más modesto y más seguro como primer paso: comprobar que el código fuente —tal cual, en su variante en serie (equivalente a `Makefile.serie`, ver [`docs-Makefiles/Makefiles.md`](../docs-Makefiles/Makefiles.md))— compila limpiamente con el compilador que sí sabe generar código para GPU, aunque de momento el binario resultante siga ejecutándose íntegramente en la CPU. Añadir offload real a la GPU (OpenACC o CUDA Fortran) queda como el siguiente hito, ya con el código compilando de base.

## 1. Entorno usado

| | |
|---|---|
| Compilador | `nvfortran 24.1-0` (NVIDIA HPC SDK), ya instalado en `/opt/nvidia/hpc_sdk/...` |
| Máquina | PC personal (ver "Entorno 1" en [`hardware_specs.md`](../docs/hardware_specs.md)) |
| Librerías de álgebra lineal | `liblapack`/`libblas` del sistema (`/lib/x86_64-linux-gnu/`) |
| Base de partida | Copia de `Original/` en `Compilacion-GPU/` (ver conversación previa), usando como referencia `Makefile.serie` |

Se descartó `gfortran` para este intento porque, aunque dice soportar offload a `nvptx-none` en su configuración, en la práctica **falta el componente `mkoffload` para nvptx** (paquete `gcc-offload-nvptx`, no instalado) — un `!$acc parallel loop` de prueba falla al enlazar. `nvfortran` no tiene ese problema: es el compilador ya documentado como toolchain de este proyecto y soporta OpenACC/CUDA Fortran de fábrica.

## 2. Resumen de los cambios

| Archivo | Tipo de cambio | Líneas |
|---|---|---|
| [`Makefile.gpu`](Makefile.gpu) | **Nuevo** fichero | Todo el fichero (basado en `Makefile.serie`) |
| [`mtipos.f90`](mtipos.f90) | Modificación de 1 línea | Línea 7 |
| [`mwavef.f90`](mwavef.f90) | Modificación de 1 línea | Línea 714 |
| [`mrandom.f90`](mrandom.f90) | Corrección de un **bug de compilación crítico** en `fijasemilla` | Líneas 47-53 |
| [`mrandom2.f90`](mrandom2.f90) | Corrección del mismo bug en `rand1` y `rand1p` | Líneas 9-28 y 30-48 |

Los dos primeros cambios (`mtipos.f90`, `mwavef.f90`) son ajustes menores de precisión, explicados en la sección 4.1-4.3. El cambio en `mrandom.f90`/`mrandom2.f90`, explicado en la sección 4.4, es de otra magnitud: sin él, **`nvfortran` generaba una secuencia de números aleatorios distinta a la de `ifx`/`gfortran` con la misma semilla**, invalidando cualquier comparación numérica entre binarios. Es, con diferencia, el hallazgo más importante de este hito.

## 3. `Makefile.gpu`

Es una copia de [`Makefile.serie`](Makefile.serie) (la variante sin MPI/PVM, recomendada para pruebas — ver `docs-Makefiles/Makefiles.md`, sección 8) con dos cambios:

| | `Makefile.serie` | `Makefile.gpu` | Por qué |
|---|---|---|---|
| `FC` | `ifx` | `nvfortran` | Es el compilador que sabe generar código para la GPU NVIDIA; `ifx` (Intel) no puede. |
| `F77FLAGS` (solo para `bh_heh2m.f`) | `-extend-source 132 -O2` | `-Mextend -O2` | `-extend-source 132` es una opción específica de `ifx`. `nvfortran` no la reconoce; su equivalente para permitir líneas de hasta 132 columnas en Fortran de formato fijo es `-Mextend`. Sin esto, `bh_heh2m.f` (fuente F77 con líneas largas) no compilaría. |

El resto del Makefile —lista de objetos, dependencias entre módulos, `LDFLAGS=-llapack -lblas`, uso de `mserie.f90` como módulo de paralelismo— es idéntico a `Makefile.serie`, porque nada de eso depende del compilador.

No ha hecho falta ningún flag de GPU (`-acc`, `-gpu=ccXX`, `-cuda`) porque, como se ha decidido, este hito no compila ningún offload — es una compilación de CPU normal, solo que con el compilador de NVIDIA.

## 4. Cambios en el código fuente

Ambos cambios resuelven **el mismo problema de fondo**, en dos sitios distintos del código.

### 4.1 El problema: `nvfortran` no soporta precisión cuádruple (`REAL(16)`) en x86-64

Al compilar [`mtipos.f90`](mtipos.f90) tal cual estaba en `Original/`, `nvfortran` paraba con:

```
NVFORTRAN-S-0081-Illegal selector - KIND value must be non-negative  (mtipos.f90: 14)
NVFORTRAN-S-0081-Illegal selector - KIND value must be non-negative  (mtipos.f90: 15)
```

La causa es esta línea (línea 7 original):

```fortran
integer, private, parameter :: r16=selected_real_kind(2*precision(1.0_r8))
```

`r8` es doble precisión (`selected_real_kind(15,9)`, 15 dígitos decimales). `precision(1.0_r8)` vale 15, así que se le pide a `selected_real_kind` un tipo real con **30 dígitos decimales** de precisión — es decir, precisión cuádruple (128 bits). `ifx` y `gfortran` sí ofrecen esa precisión (`REAL(16)`, emulada por software). **`nvfortran` no la ofrece en absoluto en x86-64**: lo comprobé directamente,

```fortran
real(kind=16) :: x   ! nvfortran: "KIND parameter has unknown value for data type"
```

Cuando la precisión pedida no existe, `selected_real_kind` devuelve `-1` (así lo especifica el estándar Fortran). El código usaba ese `-1` directamente como el KIND de una variable (`real(kind=r16)`), y un KIND negativo no es válido — de ahí el error "Illegal selector - KIND value must be non-negative". Con `ifx`/`gfortran` nunca se ve este problema porque para ellos la función sí encuentra un tipo válido (kind=16) y nunca devuelve `-1`.

Este `r16` se usa en dos sitios del código:
- [`mtipos.f90`](mtipos.f90), en el tipo `vloc`, para los campos `wf`, `wfhe4`, `wfhe3`, `wfm`, `wfx` (líneas 13-15 antes del cambio) — es decir, para los valores de la función de onda de cada walker.
- [`mwavef.f90`](mwavef.f90), dentro de la subrutina `dernumeri` (línea 714), para unas variables locales `wfmas,wfmen,dend1,dend2,der2,wf0`.

### 4.2 Cambio 1 — `mtipos.f90`, línea 7

```diff
- integer, private, parameter :: r16=selected_real_kind(2*precision(1.0_r8))
+ integer, private, parameter :: r16=max(selected_real_kind(2*precision(1.0_r8)),r8)
```

**Qué hace:** si `selected_real_kind` no encuentra ningún tipo con precisión cuádruple (devuelve `-1`, como pasa en `nvfortran`), `max(-1, r8)` da `r8` (doble precisión, kind=8) — un valor válido y siempre disponible. Si el compilador **sí** tiene precisión cuádruple (`ifx`, `gfortran`), `max(16, 8)` sigue dando `16`: el comportamiento en esos compiladores no cambia en absoluto.

Lo comprobé de forma aislada antes de tocar el fichero real:

```fortran
integer, parameter :: r16raw=selected_real_kind(2*precision(1.0_r8))   ! = -1 con nvfortran
integer, parameter :: r16=max(selected_real_kind(2*precision(1.0_r8)),r8)  ! = 8 con nvfortran
```

**Por qué es el cambio mínimo:** es una única expresión, no toca ninguna lógica de cálculo, no cambia ningún otro tipo, y es "retrocompatible": la condición `max(...)` hace que el mismo código fuente siga compilando igual (con cuádruple precisión de verdad) en `ifx`/`gfortran`, y solo se degrada a doble precisión cuando el compilador no ofrece nada mejor.

**Consecuencia real que debe quedar documentada para la memoria del TFG:** con `nvfortran`, los campos `wf`, `wfhe4`, `wfhe3`, `wfm`, `wfx` del walker pasan de tener ~33-34 dígitos decimales de precisión (cuádruple) a ~15-16 (doble). Estos campos guardan el valor de la función de onda de prueba, que en DMC puede tomar valores muy grandes o muy pequeños durante el muestreo; la precisión extra en el original probablemente se añadió para evitar problemas de overflow/underflow o pérdida de cifras significativas en esos productos. Con `nvfortran` esa protección extra desaparece. **No debería impedir que el código funcione** (los resultados de la ejecución de prueba, sección 5, tienen un aspecto físicamente razonable), pero es un cambio de comportamiento numérico real, no solo cosmético, y conviene vigilarlo si en algún momento aparecen `NaN`/`Inf` o energías inestables que no aparecían en la versión compilada con `ifx`.

### 4.3 Cambio 2 — `mwavef.f90`, línea 714

```diff
- integer, parameter :: r16=selected_real_kind(2*precision(1.0_r8))
+ integer, parameter :: r16=max(selected_real_kind(2*precision(1.0_r8)),r8)
```

Mismo patrón exacto, dentro de la subrutina `dernumeri`. Aquí el matiz importante es **cuándo se usa esta subrutina**: solo se llama desde `checkder` ([`mmontecarlo.f90:363`](mmontecarlo.f90)), que a su vez solo se ejecuta si `opcion=0` en `in.mcv` (comprobación de derivadas analíticas frente a derivadas numéricas por diferencias finitas — una rutina de depuración/verificación, no de producción; el `in.mcv` de este proyecto usa `opcion=1`, mcv). El efecto de perder precisión cuádruple aquí es, si acaso, más relevante que en el caso anterior: las diferencias finitas son especialmente sensibles a la precisión (restar dos números casi iguales y dividir por un paso pequeño amplifica el error de redondeo), así que si en el futuro se usa `opcion=0` con `nvfortran` para verificar derivadas, hay que tener en cuenta que el margen de error numérico esperable será mayor que con `ifx`/`gfortran`.

### 4.4 Cambio 3 (CRÍTICO) — bug de compilación de `ishft` en `mrandom.f90` y `mrandom2.f90`

#### Cómo se detectó

Tras conseguir que el binario compilara y corriera (secciones 4.1-4.3), se hizo la comparación pendiente de la sección 5.2: ejecutar el mismo `in.mcv` (misma semilla, `0000000000000011`) y el mismo `conf.20.00.HH`, una vez con `Original/` + `gfortran` y otra con `Compilacion-GPU/` + `nvfortran`, usando [`scripts/run_test.sh`](../scripts/run_test.sh) para garantizar que ambas ejecuciones parten exactamente de los mismos ficheros de entrada (se comprobó con `md5sum` que `in.mcv`, `conf.20.00.HH` y `heh2m.pot` son idénticos byte a byte en ambos directorios).

Resultado de la primera comparación (con los cambios 4.2/4.3 ya aplicados, pero antes de este cambio 3):

| | `Original` + `gfortran` | `Compilacion-GPU` + `nvfortran` |
|---|---|---|
| `energia media` (config. inicial, sin RNG) | `-615.5737694991` | `-615.5737694991` (igual) |
| `semilla para este proceso` | `98330646220102` | `648` |
| `Energia cinetica` (meV) | `186.96659474` | `-222.99473469` |
| `Energia total` (meV) | `-545.02383970` | `-307.89948754` |

La `energia media` inicial —que se calcula sobre la configuración de partida sin usar ningún número aleatorio— coincidía exactamente. Pero la **semilla derivada** que arranca el muestreo Monte Carlo (`98330646220102` frente a `648`) era completamente distinta, y a partir de ahí toda la trayectoria del cálculo diverge por completo (hasta cambiar el signo de la energía cinética). Esto no es el "ruido esperable" de comparar dos compiladores (ver conversación previa sobre precisión cuádruple): una diferencia de esa magnitud, en un valor que debería ser aritmética de enteros pura y determinista, apunta a un error real, no a redondeo.

#### Causa raíz

La derivación de esa semilla usa `rand1p` ([`mrandom2.f90`](mrandom2.f90)), que a su vez depende de `ishft` (desplazamiento de bits) sobre enteros de 64 bits (`integer(kind=i8)`). El código original tenía expresiones como:

```fortran
integer(kind=i8), parameter :: mask24 = ishft(1_i8,24)-1
integer(kind=i8), parameter :: mask48 = ishft(1_i8,48)-1
...
is2=iand(ishft(irn,-24),mask24)
irn=iand(ishft(iand(is1*m12+is2*m11,mask24),24)+is1*m11+iadd1,mask48)
```

El primer argumento de `ishft` es de 64 bits (`1_i8`, `irn`, etc.), pero el **segundo argumento** (la cantidad de bits a desplazar: `24`, `48`, `-24`) se escribe como literal entero **sin sufijo de kind**, es decir, entero por defecto de 32 bits. El estándar Fortran permite que el segundo argumento de `ishft` tenga un kind distinto del primero, así que esto es código válido — pero, además, estas expresiones estaban declaradas como `parameter`, lo que obliga al compilador a evaluarlas en **tiempo de compilación** (constant folding).

La hipótesis (aportada directamente por Blanca, que identificó el patrón y propuso la reescritura) es que el evaluador de expresiones constantes de `nvfortran` calcula mal `ishft` de 64 bits cuando el segundo argumento no lleva explícitamente el kind de 64 bits, en el contexto de una expresión `parameter`. `gfortran` e `ifx` no tienen ese problema y evalúan la misma expresión correctamente. El resultado con `nvfortran` eran máscaras (`mask24`, `mask48`) y multiplicadores (`m11`, `m12`, `m21`, `m22`) mal calculados en tiempo de compilación, que corrompían silenciosamente el generador de números aleatorios — sin ningún error ni aviso de compilación, porque sintácticamente el código es válido.

#### El cambio aplicado

Se reescribieron `fijasemilla` ([`mrandom.f90:47-53`](mrandom.f90#L47-L53)) y `rand1`/`rand1p` ([`mrandom2.f90:9-28,30-48`](mrandom2.f90#L9-L48)) con dos modificaciones, ambas necesarias:

1. **Se añade el sufijo `_i8` a todos los argumentos de `ishft`**, incluyendo la cantidad de desplazamiento (`ishft(1_i8, 24_i8)`, `ishft(irn, -24_i8)`, etc.), no solo al valor desplazado.
2. **Se dejan de declarar como `parameter`** las máscaras y multiplicadores derivados de `ishft` (`mask24`, `mask48`, `m11`, `m12`, `m21`, `m22`); pasan a ser variables locales normales, calculadas con una asignación al principio de la subrutina, en tiempo de ejecución.

```diff
- integer(kind=i8),  parameter :: mask24 = ishft(1_i8,24)-1
- integer(kind=i8),  parameter :: mask48 = ishft(1_i8,48_i8)-1_i8
+ integer(kind=i8) :: mask24, mask48
  ...
+  mask24 = ishft(1_i8, 24_i8) - 1_i8
+  mask48 = ishft(1_i8, 48_i8) - 1_i8
```

El resultado matemático de estas expresiones es idéntico al que "debería" dar el código original en un compilador que las evalúe bien — no se ha cambiado el algoritmo del generador aleatorio, solo la forma de expresarlo para que `nvfortran` lo calcule correctamente. `gfortran`/`ifx` siguen dando el mismo resultado que antes (ya lo calculaban bien).

#### Verificación

Repitiendo exactamente la misma comparación tras el cambio:

| | `Original` + `gfortran` | `Compilacion-GPU` + `nvfortran` (tras el fix) |
|---|---|---|
| `semilla para este proceso` | `98330646220102` | `98330646220102` (**igual**) |
| `Energia cinetica` (meV) | `186.96659474` | `186.96659474` (**igual**) |
| `Energia potencial` (meV) | `-731.99043444` | `-731.99043444` (**igual**) |
| `Energia total` (meV) | `-545.02383970` | `-545.02383970` (**igual**) |
| `Energia rotacion mol` (meV) | `49.56716009` | `49.56716009` (**igual**) |

Coinciden dígito a dígito en las 10 cifras mostradas del resumen final, para toda una tirada de Monte Carlo Variacional (10 bloques × 1000 pasos, `in.mcv` con `pasos por bloque` reducido para la prueba). Esto confirma que el bug era real y estaba exclusivamente en esas líneas — pero, como se explica justo debajo, esta coincidencia en el resumen no implica coincidencia bit a bit en todos los pasos intermedios.

#### Matiz importante: "idéntico" solo se cumplió a la precisión mostrada en el resumen

Al hacer un `diff` completo, línea a línea, de los dos `run.log` (no solo del bloque resumen "Resultados en meV"), aparecían diferencias de 1 bit en el último dígito significativo en varias filas de la tabla de bloques (p.ej. `-543.6719044759` frente a `-543.6719044760`). Esto **no es un bug**: es el límite normal de precisión de `double` (~15-17 cifras decimales) al comparar dos compiladores distintos, porque:

- Las funciones trascendentes (`exp`, `**`) no tienen redondeo exactamente igual garantizado entre librerías matemáticas de distintos fabricantes (glibc para `gfortran`, la de NVIDIA HPC SDK para `nvfortran`).
- La suma en coma flotante no es asociativa: si el compilador reordena una suma (vectorización automática) o fusiona `a*b+c` en una instrucción FMA (fused multiply-add) con un solo redondeo, el último bit puede cambiar.

Con el generador de números aleatorios ya corregido, la *secuencia* de decisiones de Metropolis es idéntica; el ruido de 1 bit en la evaluación de energías no llegó a cambiar ninguna decisión de aceptar/rechazar en esta tirada corta, así que no se propagó — pero no hay garantía de que eso se mantenga en una tirada mucho más larga.

**Se puede eliminar ese ruido con flags de coma flotante estricta.** Añadiendo `-Kieee -Mnofma` a `FFLAGS` en la compilación con `nvfortran` (fuerza aritmética IEEE-754 estricta y desactiva la fusión FMA, que son las dos fuentes de reordenación/optimización agresiva que introducían el ruido):

```bash
scripts/run_test.sh -c Compilacion-GPU -f Makefile.gpu -i Compilacion-GPU/in.mcv \
  -e "FFLAGS=-O2 -Kieee -Mnofma"
```

Repitiendo la comparación completa con este flag, **la tabla de bloques completa (energías, % de aceptación, todo) coincide bit a bit** con `Original`+`gfortran` — no solo el resumen final. Verificado con:

```bash
diff <(grep -E "^\s+[0-9]+\s+[0-9]+\s+[0-9]+" run_gfortran.log) \
     <(grep -E "^\s+[0-9]+\s+[0-9]+\s+[0-9]+" run_nvfortran_ieee.log)
# → sin diferencias
```

**Por qué no se ha añadido `-Kieee -Mnofma` por defecto a `Makefile.gpu`:** es la flag correcta para *validar* que el port no ha introducido ningún cambio de comportamiento (comparándolo contra `Original`), pero fuerza al compilador a renunciar a optimizaciones (reordenación, FMA) que normalmente mejoran el rendimiento — justo lo contrario de lo que se busca en un port a GPU pensado para medir *speedup*. La recomendación es: usar `-Kieee -Mnofma` (vía `-e` en `scripts/run_test.sh`) **solo** para las comparaciones de corrección frente a `Original`, y dejarlo desactivado en las compilaciones usadas para medir tiempos/rendimiento.

**Por qué es relevante más allá de este hito:** este bug no depende de `mserie.f90` ni de ningún otro módulo de paralelismo — afectaría igual a un futuro build `nvfortran` con MPI o con offload real a GPU, en cualquier sitio del código que use `ishft` de 64 bits con literales de desplazamiento sin sufijo de kind dentro de una expresión `parameter`. Se ha comprobado (`grep -rn "ishft" *.f90 *.f`) que en todo `Compilacion-GPU/` el intrínseco `ishft` **solo se usa en `mrandom.f90` y `mrandom2.f90`**, es decir, ya no quedan más sitios con este patrón — pero conviene repetir esta búsqueda si se añade código nuevo (p.ej. al escribir kernels CUDA Fortran) que también manipule bits a mano.

## 5. Verificación

### 5.1 Compilación

```bash
cd Compilacion-GPU
make -f Makefile.gpu clean
make -f Makefile.gpu
```

Resultado: compilación y enlazado completos sin errores. Han aparecido ~30 avisos del tipo `NVFORTRAN-W-0093-Type conversion of expression performed` en `mwavef.f90` — son solo warnings (0 "severes", 0 "fatal"), y **no están causados por los dos cambios anteriores**: revisando las líneas señaladas (p. ej. `mwavef.f90:108-109`, `ujas=min(ujas,umax)` / `ujas=max(ujas,umin)`) corresponden a mezclas de precisión ya presentes en el código original (constantes/variables de distinto kind pasadas a `min`/`max`) que `ifx`/`gfortran` simplemente no avisaban con la misma verbosidad. No se han tocado porque no impiden la compilación ni están relacionadas con el problema de `r16`; quedan anotadas aquí por si se quieren limpiar más adelante.

### 5.2 Ejecución

El binario espera `in.mcv` por **entrada estándar**, no como fichero ya copiado a mano — es el propio programa el que genera `in.copia` internamente a partir de lo leído por stdin ([`mentradatos.f90:21-31`](mentradatos.f90)):

```bash
./qmccluster < in.mcv
```

Con los parámetros de `in.mcv` tal cual (1.000.000 de pasos por bloque, ver conversación previa sobre `in.mcv`), la ejecución es larga por diseño, no por ningún problema del port. Para verificar que el binario corre un cálculo completo de principio a fin sin errores, se ha repetido la prueba con una copia de `in.mcv` con `pasos por bloque` reducido a 1000, obteniendo una salida completa y coherente (energías cinética/potencial/rotacional en meV, K y cm⁻¹, con sus barras de error, y el mensaje final de walkers/tiempo de CPU) — sin ningún error de tiempo de ejecución.

**Actualización:** la comparación numérica frente a `Original/` (con `gfortran`, ya que `ifx` no está instalado en esta máquina) sí se ha hecho — ver sección 4.4. Tras corregir el bug de `ishft`, ambos binarios dan resultados idénticos dígito a dígito para la misma semilla y los mismos datos de entrada, usando [`scripts/run_test.sh`](../scripts/run_test.sh) para garantizar que cada uno se ejecuta en una copia aislada sin contaminar los ficheros de datos originales.

## 6. Qué NO ha cambiado

- Ninguna lógica de física ni de potencial.
- El **algoritmo** del generador de números aleatorios (constantes `mult1`, `mult2`, `iadd1`, `iadd2`, las mismas operaciones de bits) es exactamente el mismo; el cambio de la sección 4.4 solo corrige cómo se le indica a `nvfortran` que evalúe esas operaciones, no qué operaciones son.
- Ningún otro tipo de dato ni precisión (`r8`, `i4`, `i8` siguen igual).
- El módulo de paralelismo sigue siendo `mserie.f90` (un solo proceso, sin MPI/PVM), igual que `Makefile.serie`.
- No hay ninguna directiva de GPU (`!$acc`, `!$cuf`, `attributes(global)`, etc.) en el código — este binario, aunque compilado con el compilador de NVIDIA, **se ejecuta entero en la CPU**.
