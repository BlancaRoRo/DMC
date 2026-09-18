# Fase 0: Compilación

Primera fase del proyecto, previa a portar ningún código a CUDA. Antes de tocar una
sola línea de física, había que resolver tres preguntas: en qué hardware se iba a
trabajar, cómo estaba organizada la compilación del código original, y si ese código
compilaba siquiera con el compilador de NVIDIA.

## [`hardware_specs.md`](hardware_specs.md) — el material de partida

Especificaciones de los equipos usados para desarrollo y pruebas a lo largo del TFG
(CPU, GPU, memoria) — incluye la GPU NVIDIA de cada entorno, el dato que de verdad
importa para saber qué es viable ejecutar y perfilar en cada máquina.

## [`Makefiles.md`](Makefiles.md) — los Makefiles con los que arrancaba el proyecto

El código original venía con **cuatro Makefiles distintos** (`Makefile`,
`Makefile.mpi`, `Makefile.pvm`, `Makefile.serie`), que compilan el mismo código
científico pero enlazado contra un backend de paralelismo distinto (serie, PVM o MPI
— todos reparten *walkers* entre procesos de CPU). Este documento explica qué hace
cada uno y por qué ninguno de esos backends es el relevante para CUDA: MPI/PVM
paralelizan entre procesos, mientras que la GPU paraleliza dentro de uno solo.

## [`v0_Cambios_Compilador.md`](v0_Cambios_Compilador.md) — primer intento con `nvfortran`

Antes de escribir ningún kernel, había que comprobar que el código original compilaba
con `nvfortran` (NVIDIA HPC SDK) — el compilador necesario para poder acabar
enlazando código CUDA Fortran en el mismo binario. Este documento recoge ese primer
intento: **sin añadir ningún offload real a GPU todavía**, solo conseguir que el
código en serie (`Makefile.serie`) compilase limpio con `nvfortran` en vez de
`gfortran`, y qué diferencias hubo que resolver para lograrlo.
