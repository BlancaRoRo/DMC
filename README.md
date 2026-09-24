# Simulaciones

## Qué es DMC

DMC (*Diffusion Monte Carlo*) es un método de simulación cuántica: se hace evolucionar
una población de miles de copias ("*walkers*") de un sistema de partículas de helio con
una impureza molecular en su interior, hasta que la población converge a la
configuración de **mínima energía** del sistema — el estado fundamental. Cada *walker*
representa una posible disposición espacial de los átomos, y en cada paso se calculan
su energía cinética y potencial, se decide aleatoriamente si "sobrevive" o se ramifica
según esa energía, y se repite miles de veces hasta que el conjunto de la población
converge. Es un cálculo con mucho paralelismo natural entre *walkers* — de ahí el
interés de acelerarlo con GPU.

Este repositorio recoge el trabajo de portar ese simulador (originalmente solo CPU) a
CUDA Fortran para acelerarlo con GPUs NVIDIA. El histórico completo del desarrollo,
fase a fase, está en las ramas `fase0-compilación` a `fase4-pruebas`; esta rama
(`main`) contiene solo las dos versiones finales, listas para compilar y ejecutar.

## Diagramas interactivos

Cada uno vive en su rama correspondiente (GitHub no renderiza `.html` directamente,
por eso el enlace pasa por [htmlpreview.github.io](https://htmlpreview.github.io)):

- **Árbol de llamadas de `dmc2`** (`fase1-transcripción`, portado método a método):
  [ver diagrama](https://htmlpreview.github.io/?https://raw.githubusercontent.com/BlancaRoRo/DMC/fase1-transcripci%C3%B3n/docs-kernels/dmc2-call-graph.html)
- **Pipeline CPU↔GPU de un paso DMC** (`fase3-optimización`, con la fusión de fases
  `k_fase_cd`/`k_fase_fgh` ya aplicada):
  [ver diagrama](https://htmlpreview.github.io/?https://raw.githubusercontent.com/BlancaRoRo/DMC/fase3-optimizaci%C3%B3n/arquitectura-lanzamiento/fusion-fases-cd-fgh/pipeline-cpu-gpu.html)

## Las dos versiones

- **`dmc-cpu/`**: el código **tal como se proporcionó inicialmente** (la versión
  `Original`, sin portar a CUDA), compilado con `gfortran`.
- **`dmc-hibrido/`**: la versión **final, tras la aceleración** con CUDA Fortran —
  incluye todas las optimizaciones de GPU del proyecto.

Ambas son solo código fuente + lo necesario para compilar y ejecutar (sin
`.o`/`.mod`/binarios ni resultados de corridas anteriores).

## Requisitos

- **`gfortran`** para `dmc-cpu/` (viene con cualquier distribución de GCC).
- **`nvfortran`**, del **NVIDIA HPC SDK**, para `dmc-hibrido/` (no viene con GCC, hay
  que instalar el SDK de NVIDIA aparte), además de un driver de NVIDIA compatible.
- **`liblapack` y `libblas`** en las dos versiones: el ajuste por mínimos cuadrados del
  potencial (`kpcoef.f`, llamado desde `mkp_heco.f90`) usa `dgemv`/`dgemm` de BLAS
  directamente, y los `Makefile` de ambas enlazan con `-llapack -lblas`. En
  Debian/Ubuntu:
  ```bash
  sudo apt install liblapack-dev libblas-dev
  ```

## `dmc-cpu/`

El código proporcionado inicialmente, compilado con `gfortran`, **con el fix de `Vap`
ya aplicado** en `bh_heh2m.f`: en el potencial He-He (`Vp_hehe`), la variable `Vap` no
se inicializaba fuera de la ventana `[xx1_HeHe, xx2_HeHe]`, quedando con lo que hubiera
en memoria en ese momento (ver `V_hehe_Vp_hehe.md` en `fase3-optimización`, Sec. 5). El
fix recupera la intención original que ya sugería el propio código con un `!Vap=0.d0`
comentado, sin tocar ninguna otra fórmula.

Es el binario de referencia contra el que se ha verificado, en todo el proyecto, que
la versión GPU da la misma física.

**Para compilarlo hace falta `gfortran`** (viene con cualquier distribución de GCC,
no requiere nada adicional de NVIDIA). El Makefile que usa es
[`Makefile.serie`](dmc-cpu/Makefile.serie) (invocado por el propio script, no hace
falta llamarlo a mano):

```bash
./compilar_gfortran.sh
./qmccluster < in.mcv
```

Nótese el `<`: el programa lee la configuración por entrada estándar, no como
argumento de línea de comandos (`./qmccluster in.mcv`, sin el `<`, no funciona).

## `dmc-hibrido/`

El código híbrido final, con todas las optimizaciones GPU del proyecto ya integradas,
recortado a solo las vías que de verdad hacen falta.

Verificado bit a bit tras la limpieza: con `opcion=5`, la energía final coincide
exactamente con la que daba el binario original (`hibrido_instrumentado`) con
`opcion=7` antes de tocar nada (`-622.9201974824`).

**Para compilarlo hace falta el compilador `nvfortran`**, distribuido dentro del
**NVIDIA HPC SDK** (no viene con GCC, hay que instalar el SDK de NVIDIA aparte). Igual
que `dmc-cpu`, se compila con `make` -- el [`Makefile`](dmc-hibrido/Makefile) refleja
la dependencia real entre módulos (cada `.o` depende de los módulos que su fichero
`use`), así que soporta compilación en paralelo (`make -j`):

```bash
make
./qmccluster_pipeline < in.mcv
```

(Mismo `<` que en `dmc-cpu`: la configuración se lee por entrada estándar.)
