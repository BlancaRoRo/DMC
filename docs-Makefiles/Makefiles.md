# Los Makefiles del código DMC original

En `Original/` conviven **cuatro** Makefiles distintos: [`Makefile`](../Original/Makefile), [`Makefile.mpi`](../Original/Makefile.mpi), [`Makefile.pvm`](../Original/Makefile.pvm) y [`Makefile.serie`](../Original/Makefile.serie). No son cuatro proyectos distintos: compilan **exactamente el mismo código científico** (el mismo conjunto de módulos Fortran que implementan la función de onda, el potencial, el muestreo Monte Carlo, etc.), pero cada uno lo enlaza contra un **backend de paralelismo distinto** — o contra ninguno.

La razón de que existan varias versiones es histórica: el código ha ido evolucionando de una ejecución en serie, a un reparto de trabajo mediante **PVM** (Parallel Virtual Machine, una librería de paso de mensajes anterior y hoy obsoleta), y finalmente a **MPI** (Message Passing Interface, el estándar actual). En vez de mantener un único Makefile con opciones condicionales, cada backend se dejó en su propio fichero.

Este documento explica qué hace cada uno, con qué compilador y flags, de qué depende externamente (librerías del sistema) y cuándo se usaría cada uno. Es relevante para el TFG porque, antes de portar el código a CUDA, hay que decidir **sobre cuál de estas variantes se construye** el nuevo port (spoiler: la lógica de paralelismo relevante para GPU no es ninguna de las tres — MPI/PVM reparten *walkers* entre procesos de CPU, mientras que CUDA paraleliza dentro de un único proceso).

---

## 1. Qué tienen en común los cuatro

Todos comparten:

- **La misma lista de fuentes "de física"** (`SRC`/`OBJECTS`): `qmccluster.f90`, `mmontecarlo.f90`, `mminimiza.f90`, `mentradatos.f90`, `mconfiguraciones.f90`, `mparametros.f90`, `mrandom.f90`/`mrandom2.f90`, `mtipos.f90`, `mdensidades.f90`, `msteps.f90`, `mwavef.f90`, `mangwavef.f90`, `mimagina.f90`, `mrotaciones.f90`, `msistref.f90`, `mvaziz.f90`, `mvmolecula.f90`, `mmcvpromedia.f90`, `mdmcpromedia.f90`, `bh_heh2m.f`, `pw_heocs.f`, `mhh_heocs.f90`, `mkp_heco.f90`, `kpcoef.f`, `mlineal.f90`, `mlegendre.f90`, `modlegendre.f`.
- **Las mismas reglas de sufijo** `.f90.o` y `.f.o` (compilación genérica de Fortran libre y fijo).
- **El mismo binario final**: `qmccluster`.
- **Un único módulo variable**: el que implementa la comunicación entre procesos, siempre bajo el nombre lógico `mparalelo` pero con tres implementaciones intercambiables:

| Fichero fuente | Backend | Usado por |
|---|---|---|
| [`mmpi.f90`](../Original/mmpi.f90) | MPI (`use mpi`) | `Makefile`, `Makefile.mpi` |
| [`mpvm.f90`](../Original/mpvm.f90) | PVM (`include 'fpvm3.h'`) | `Makefile.pvm` |
| [`mserie.f90`](../Original/mserie.f90) | Ninguno (stub que simula 1 proceso) | `Makefile.serie` |

Los tres exponen la misma interfaz (`iniciaparalelo`, `iniprocesos`, `quiensoy`, `cuantosparalelos`, `reparteentrada`, `repartepotencial`, `compruebatodos`, `distribuyesemillas`, `repartewalker`, etc.), de modo que `mmontecarlo.f90`, `mminimiza.f90` y `qmccluster.f90` se compilan sin cambios frente a cualquiera de los tres: solo cambia **contra cuál** de los tres módulos se enlazan.

---

## 2. Comparativa rápida entre los cuatro Makefiles

| | `Makefile` | `Makefile.mpi` | `Makefile.pvm` | `Makefile.serie` |
|---|---|---|---|---|
| **Compilador (`FC`)** | `mpiifx` | `mpiifx` | `gfortran` | `ifx` |
| **Paralelismo** | MPI | MPI | PVM | Ninguno (1 proceso) |
| **Módulo de comunicación** | `mmpi.f90` | `mmpi.f90` | `mpvm.f90` | `mserie.f90` |
| **Librerías externas de paralelismo** | `-lmpi` | `-lmpi` | `-lmnu -lfpvm3 -lpvm3` | — |
| **Álgebra lineal** | `-llapack -lblas` (sistema) | `-llapack -lblas` (sistema) | `-llapack -lrefblas` (ruta local `../lapack/lapack-3.6.0`) | `-llapack -lblas` (sistema) |
| **Flags de optimización** | `-O2` | `-O2` | `-O2` | `-O2` (+ `-extend-source 132` solo para `bh_heh2m.f`) |
| **Paso extra tras enlazar** | — | — | `copiahosts qmccluster` (distribuye el binario a las máquinas del clúster PVM) | — |
| **Uso típico** | Build "por defecto" (`make` sin argumentos) en un clúster con Intel MPI | Build MPI explícito, casi idéntico al anterior | Ejecución en clúster heterogéneo con PVM (esquema antiguo) | Ejecución en una sola máquina/un solo proceso, sin dependencias de clúster |

---

## 3. `Makefile` (build por defecto — MPI)

Es el fichero que se usa al ejecutar `make` sin argumentos. Es, en la práctica, una copia de `Makefile.mpi` con dos diferencias mínimas de mantenimiento (ver [sección 6](#6-una-inconsistencia-entre-makefile-y-makefilempi)).

| Aspecto | Detalle |
|---|---|
| Compilador | `FC=mpiifx` (wrapper de Intel Fortran para MPI). Alternativa comentada: `mpif90` |
| Flags de compilación | `FFLAGS=-O2` |
| Enlazado | `$(FC) $(FFLAGS) -o $@ $^ $(LDFLAGS) $(MPILIBS)` |
| Librerías | `MPILIBS=-lmpi`, `LDFLAGS=-llapack -lblas` |
| Fuente de paralelismo | `mmpi.f90` (compilada aparte con `$(MPILIBS)`) |
| Regla `clean` | Borra `qmccluster`, `*.o`, `*.d`, `work.pc`, `work.pcl`, `tags`, `*.mod` |
| ¿Para qué se usa? | Compilación estándar en un clúster/nodo con Intel MPI ya instalado (`mpiifx` disponible en el `PATH`). Es el build de producción para ejecutar el DMC repartiendo *walkers* entre varios procesos MPI. |

---

## 4. `Makefile.mpi` (build MPI explícito)

Funcionalmente equivalente al anterior — mismo compilador, mismas librerías, mismo módulo `mmpi.f90` — pensado para invocarse explícitamente con `make -f Makefile.mpi` cuando conviene dejar claro (o coexistir con otras variantes) que se está construyendo la versión MPI.

| Aspecto | Detalle |
|---|---|
| Compilador | `FC=mpiifx` (idéntico a `Makefile`) |
| Flags de compilación | `FFLAGS=-O2` |
| Enlazado | `$(FC) $(FFLAGS) -o $@ $^ $(LDFLAGS) $(MPILIBS)` |
| Librerías | `MPILIBS=-lmpi`, `LDFLAGS=-llapack -lblas` |
| Fuente de paralelismo | `mmpi.f90` |
| Regla `clean` | Borra `*.o`, `*.d`, `work.pc`, `work.pcl`, `tags`, `*.mod` (**no** borra el binario `qmccluster`) |
| ¿Para qué se usa? | Igual que `Makefile`: build MPI, invocado explícitamente con `make -f Makefile.mpi` cuando se quiere reconstruir solo los objetos y conservar el ejecutable anterior. |

---

## 5. `Makefile.pvm` (build con PVM — esquema de clúster heterogéneo antiguo)

Es la variante más distinta de las cuatro, porque PVM no es un simple *wrapper* de compilador: necesita su propia librería de arranque de procesos remotos (`pvm3`) y un paso adicional para desplegar el ejecutable en todas las máquinas del clúster.

| Aspecto | Detalle |
|---|---|
| Compilador | `FC=gfortran` (GNU Fortran; hay una alternativa comentada `f95`) |
| Enlazador | `LOADER=gfortran -O2 -L/usr/share/pvm3/lib/LINUXX86_64` (ruta de librerías PVM del sistema) |
| Flags de compilación | `FFLAGS=-O2` |
| Librerías de paralelismo | `LOADOPTS=-lmnu -lfpvm3 -lpvm3` |
| Librerías de álgebra lineal | `LDFLAGS=-L ../lapack/lapack-3.6.0 -llapack -lrefblas` (LAPACK compilado localmente en una ruta relativa, no el del sistema) |
| Cabecera C incluida | [`fpvm3.h`](../Original/fpvm3.h) (interfaz Fortran-PVM) |
| Fuente de paralelismo | `mpvm.f90` |
| Paso extra | Tras enlazar, ejecuta `copiahosts qmccluster` — un script que copia el binario a las máquinas listadas como "hosts" del clúster PVM, necesario porque PVM lanza procesos en máquinas remotas que deben tener el ejecutable disponible localmente |
| Regla `clean` | Borra `*.o`, `*.d`, `work.pc`, `work.pcl`, `tags`, `*.mod` |
| ¿Para qué se usa? | Ejecutar el DMC en un conjunto de máquinas heterogéneas usando PVM como capa de paso de mensajes. Es el esquema de paralelización más antiguo del código (véase también [`in.mcv`](../Original/in.mcv), que en su bloque `#4 DATOS CALCULO PARALELO` todavía trae el parámetro `ncadapvm`, y los scripts de ejemplo en [`in.mcv`](../Original/in.mcv)/[chuleta.txt](../Original/chuleta.txt) con comandos `pvm`, `conf`, `halt`, `startpvm`). Hoy es una vía prácticamente en desuso frente a MPI. |

---

## 6. `Makefile.serie` (build en serie — un solo proceso)

Es la variante sin paralelismo real: en vez de repartir *walkers* entre procesos, usa el módulo `mserie.f90`, que implementa la misma interfaz que `mmpi.f90`/`mpvm.f90` pero como funciones vacías o triviales (`ncpar=1`, "calculo en serie").

| Aspecto | Detalle |
|---|---|
| Compilador | `FC=ifx` (Intel Fortran, sin wrapper MPI). Alternativa comentada: `gfortran` |
| Flags de compilación | `FFLAGS=-O2`; además `F77FLAGS=-extend-source 132 -O2`, usado **solo** al compilar `bh_heh2m.f` (fuente Fortran 77 de formato fijo que necesita líneas más largas de 72 columnas) |
| Enlazado | `$(FC) $(FFLAGS) -o $@ $(OBJECTS) mserie.o $(LDFLAGS)` |
| Librerías | `LDFLAGS=-llapack -lblas` (del sistema; sin librería de paralelismo) |
| Fuente de paralelismo | `mserie.f90` (módulo *stub*, `ncpar=1`, sin comunicación real) |
| Regla `clean` | Borra `*.o`, `*.d`, `work.pc`, `work.pcl`, `tags`, `*.mod` |
| ¿Para qué se usa? | Ejecutar el DMC en un único proceso, en una sola máquina, sin necesitar MPI ni PVM instalados. Útil para pruebas locales, depuración, o cuando el número de walkers/recursos no justifica repartir el cálculo. **Es el punto de partida más natural para un port a CUDA**, ya que el paralelismo de la GPU sustituye por completo al reparto entre procesos de CPU que hacen MPI/PVM. |

---

## 7. Una inconsistencia entre `Makefile` y `Makefile.mpi`

Aunque en la práctica compilan lo mismo, un `diff` entre ambos revela dos diferencias que parecen residuos de mantenimiento (no afectan al binario resultante, porque ambos objetos igualmente se compilan y enlazan al formar parte de `OBJECTS`):

```diff
86c86
<   rm -f qmccluster *.o *.d work.pc work.pcl tags *.mod      (Makefile)
---
>   rm -f *.o *.d work.pc work.pcl tags *.mod                 (Makefile.mpi)

96c96
< mwavef.o: ... mvmolecula.o bh_heh2m.o mlineal.o             (Makefile)
---
> mwavef.o: ... mvmolecula.o mlineal.o                        (Makefile.mpi)

126c126
< mvmolecula.o: mvmolecula.f90 pw_heocs.o mhh_heocs.o mkp_heco.o                  (Makefile)
---
> mvmolecula.o: mvmolecula.f90 bh_heh2m.o pw_heocs.o mhh_heocs.o mkp_heco.o       (Makefile.mpi)
```

- `Makefile` borra también el ejecutable `qmccluster` en `make clean`; `Makefile.mpi` no.
- La dependencia declarada sobre `bh_heh2m.o` está colgada de un módulo distinto en cada fichero (`mwavef.o` en uno, `mvmolecula.o` en el otro). No cambia el resultado de la compilación —ambos ficheros acaban compilándose igualmente—, solo afecta a qué objetivo dispara la recompilación si `bh_heh2m.f` cambia.

Se documenta aquí porque, si en el port a CUDA se reescribe uno de los dos Makefiles como referencia, conviene saber que **no son bit a bit idénticos** aunque construyan el mismo programa.

---

## 8. ¿Cuál conviene usar para hacer pruebas?

Para pruebas de desarrollo (compilar rápido, ejecutar en local, comparar resultados frente al futuro port a CUDA, depurar con `gdb`/`print`, etc.) conviene usar **`Makefile.serie`**, y no las variantes MPI o PVM. Motivos:

| Motivo | `Makefile.serie` | `Makefile`/`Makefile.mpi` | `Makefile.pvm` |
|---|---|---|---|
| Dependencias externas necesarias | Solo `ifx`/`gfortran` + `lapack`/`blas` del sistema | Requiere una implementación de MPI instalada y funcionando (`mpiifx`, `-lmpi`) | Requiere el demonio PVM arrancado, ficheros de *hosts*, y `copiahosts` funcionando |
| Puesta en marcha | `make -f Makefile.serie && ./qmccluster` | Hace falta arrancar el entorno MPI (`mpirun`/`mpiexec`) y, si hay varias máquinas, tenerlas accesibles | Hace falta arrancar la consola PVM (`pvm`, `startpvm`, ver [`in.mcv`](../Original/in.mcv) líneas de ejemplo con `pvm`/`conf`/`quit`) antes de poder lanzar nada |
| Reproducibilidad para comparar resultados | Un solo proceso → una única secuencia de números aleatorios, fácil de comparar walker a walker con el port CUDA | El resultado depende del número de procesos y de cómo se reparten los *walkers*, complicando la comparación 1:1 | Igual que MPI, más la variabilidad de qué máquinas del clúster participan |
| Facilidad de depuración | Se puede meter directamente en `gdb`/añadir `write(*,*)` sin preocuparse de qué proceso escribe qué | Depurar multi-proceso es más costoso (hay que fijar el número de ranks, identificar cuál falla, etc.) | Aún más costoso: procesos en máquinas distintas |
| Tiempo de compilación/iteración | Mínimo, sin *overhead* de librerías de paralelismo | Similar, pero cada prueba implica levantar el entorno MPI | Mayor, por el paso extra `copiahosts` y la infraestructura PVM |

En resumen: **usa `Makefile.serie` mientras estés desarrollando, depurando o validando resultados numéricos** (por ejemplo, comparando la energía del sistema calculada por el código original frente a tu port CUDA con la misma semilla y la misma configuración inicial — ver la conversación previa sobre `in.mcv`/`conf.*.HH`). Reserva `Makefile`/`Makefile.mpi` para comprobar que el reparto de trabajo en paralelo sigue funcionando una vez que la parte numérica ya está validada en serie, y `Makefile.pvm` prácticamente solo tiene sentido si necesitas reproducir un resultado histórico obtenido con esa infraestructura concreta — no como parte del flujo de pruebas habitual.

---

## 9. Resumen para el port a CUDA

Ninguno de los tres backends de paralelismo (MPI, PVM, serie) resuelve el mismo problema que resolverá CUDA:

- **MPI/PVM** paralelizan **entre procesos** (normalmente uno por núcleo de CPU o por máquina), repartiendo el conjunto de *walkers* del DMC en subconjuntos disjuntos que se ejecutan de forma independiente y se sincronizan periódicamente (reparto de la semilla aleatoria, del potencial, recolección de energías, etc. — ver `mmpi.f90`/`mpvm.f90`).
- **CUDA** paralelizará **dentro de un único proceso**, típicamente asignando un walker (o un grupo de ellos) a cada hilo de la GPU.

Por eso, de las cuatro variantes, **`Makefile.serie`** es la base conceptualmente más cercana al punto de partida de un port a CUDA: al no tener ninguna capa de reparto entre procesos, aísla mejor la lógica de física/Monte Carlo que hay que trasladar a *kernels* de GPU, sin mezclarla con la lógica de comunicación MPI/PVM que no tiene equivalente directo en el modelo de programación CUDA.
