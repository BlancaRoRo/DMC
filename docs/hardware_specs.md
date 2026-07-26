# Especificaciones de hardware — TFG CUDA Fortran (DMC)

Este documento recoge las especificaciones de los entornos usados para desarrollo, pruebas y benchmarks del proyecto. Se actualiza cada vez que se añade o cambia una máquina.

---

## Entorno 1: PC personal

**Fecha de registro:** 2026-07-25
**Equipo:** HP Victus Gaming Laptop 15-fb3xxx

### CPU

| Campo | Valor |
|---|---|
| Modelo | AMD Ryzen 7 8845HS |
| Arquitectura | x86_64 |
| Núcleos físicos | 8 |
| Hilos (con SMT/HT) | 16 |
| Frecuencia máx. | 5102.71 MHz |
| Frecuencia mín. | 416.55 MHz |
| Caché L1d / L1i | 256 KiB / 256 KiB (8 instancias c/u) |
| Caché L2 | 8 MiB (8 instancias) |
| Caché L3 | 16 MiB (1 instancia) |
| Virtualización | AMD-V |

### GPU

> ⚠️ Este equipo tiene **dos GPUs**: una integrada (AMD) y una dedicada (NVIDIA). Solo la NVIDIA es relevante para este proyecto, ya que **CUDA únicamente se ejecuta sobre GPUs NVIDIA**. La integrada se deja documentada por completitud, pero no interviene en ningún kernel CUDA Fortran.

| Campo | GPU dedicada (usada para CUDA) | GPU integrada (no usada para cómputo) |
|---|---|---|
| Modelo | NVIDIA GeForce RTX 4060 Laptop GPU | AMD Radeon 780M (integrada en el Ryzen 8845HS) |
| Memoria dedicada | 8188 MiB (~8 GB) | Memoria compartida con RAM del sistema |
| Compute Capability (CUDA) | 8.9 | N/A (no soporta CUDA) |
| Driver | 580.159.03 | — |
| CUDA Version (soportada por driver) | 13.0 | — |
| Rol en el proyecto | Ejecuta todos los kernels CUDA Fortran | Solo renderizado de escritorio/pantalla |

### Sistema Operativo

| Campo | Valor |
|---|---|
| Distribución | Linux Mint 22.2 (codename: zara) |
| Basado en | Ubuntu (LTS) |
| Kernel | 7.0.0-28-generic |

### Software / Toolchain

| Campo | Valor |
|---|---|
| Compilador | nvfortran 24.1-0 (NVIDIA HPC SDK) |
| Target | 64-bit, x86-64 Linux, `-tp bulldozer` |
| Driver NVIDIA | 580.159.03 |
| CUDA Toolkit (vía driver) | 13.0 |
| Flags de compilación usados | *(pendiente de completar según versión del código)* |

### Notas
- Verificar en cada ejecución que el proceso usa la GPU NVIDIA y no interferencia de la integrada, con:
  ```bash
  nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
  ```
- Equipo tipo *laptop gaming*: posible throttling térmico en ejecuciones largas — a vigilar en benchmarks de más de unos pocos minutos.

---

## Entorno 2: Máquina Virtual

**Fecha de registro:** 2026-07-25
**Hostname:** fluid3

### CPU

| Campo | Valor |
|---|---|
| Modelo | AMD EPYC 7301 16-Core Processor |
| Sockets | 2 |
| Núcleos por socket | 16 |
| Núcleos físicos totales | 32 |
| Hilos por núcleo | 1 (SMT deshabilitado) |
| Hilos totales | 32 |
| Caché L1d / L1i | 1 MiB / 2 MiB (32 instancias c/u) |
| Caché L2 | 16 MiB (32 instancias) |
| Caché L3 | 128 MiB (16 instancias) |
| Topología NUMA | 8 nodos NUMA |

### GPU

| Campo | Valor |
|---|---|
| Modelo | NVIDIA Tesla V100-PCIE-16GB |
| Memoria VRAM total | 16384 MiB (16 GB) |
| Memoria libre en el momento del registro | ~1006 MiB (15378 MiB ya en uso por otro proceso) |
| Compute Capability (CUDA) | 7.0 |
| Driver | 580.167.08 |
| CUDA Version (soportada por driver) | 13.0 |
| ¿GPU passthrough o virtualizada? | *(pendiente de confirmar con el administrador de la VM)* |

### Sistema Operativo

| Campo | Valor |
|---|---|
| Distribución | Ubuntu 24.04.4 LTS (codename: noble) |
| Kernel | 6.8.0-124-generic |

### Software / Toolchain

| Campo | Valor |
|---|---|
| Compilador | ⚠️ **no instalado** (`nvfortran: command not found`) — pendiente instalar NVIDIA HPC SDK |
| Flags de compilación usados | *(pendiente, tras instalar el compilador)* |

### Notas
- ⚠️ **Máquina compartida con otros usuarios/procesos.** En el momento del registro, la GPU tenía un proceso ajeno (`llama-server`, de otro usuario) ocupando 15344 MiB de los 16384 MiB totales de VRAM — prácticamente toda la memoria disponible.
- Implicaciones a documentar en la memoria:
  - Los tiempos medidos en este entorno pueden tener **más variabilidad** que en el PC personal, por contención de recursos (GPU y posiblemente CPU/NUMA compartidos con otros procesos).
  - Riesgo de quedarse sin memoria VRAM si el tamaño de problema (nº de walkers) crece, dado el poco margen libre.
  - Recomendable comprobar con `nvidia-smi` el estado de la GPU **antes de cada tanda de benchmarks**, y anotar si hay otros procesos activos en ese momento, para poder descartar medidas contaminadas.
- Instalar NVIDIA HPC SDK antes de poder compilar/ejecutar el código CUDA Fortran aquí.
- Arquitectura CPU con 8 nodos NUMA: si en algún momento se paraleliza también la parte CPU (OpenMP/MPI), la afinidad de hilos a núcleos/nodos NUMA puede ser relevante para tiempos de referencia justos.

---

## Comandos de referencia para rellenar

```bash
lscpu                                                          # CPU
nvidia-smi                                                     # GPU: modelo, driver, CUDA version
nvidia-smi --query-gpu=name,memory.total,compute_cap --format=csv
lsb_release -a                                                 # SO: distribución
uname -r                                                       # SO: kernel
nvfortran --version                                            # Compilador
```
