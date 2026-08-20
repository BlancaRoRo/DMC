# Perfilado de `k_dmc2` con NVIDIA Nsight Compute

## Objetivo

`test-tiempos.md` dejó una pregunta abierta: el kernel `k_dmc2` domina el tiempo de `opcion=5` (87.9-98.6% del total según el caso) y cuesta ~1.9-3.2 s por lanzamiento **incluso con solo 50-200 hilos activos** — un coste que no se explicaba ni por el lanzamiento del kernel en sí ni por la reserva de los arrays `device` automáticos (ambas hipótesis descartadas con una prueba aislada, ver `test-tiempos.md`, seccion "Hallazgo"). Quedaba como trabajo futuro identificar **qué parte de la ejecución real del kernel** consume ese tiempo.

Este documento recoge cómo se configuró **NVIDIA Nsight Compute** (`ncu` / `ncu-ui`, incluido con el HPC SDK en `/opt/nvidia/hpc_sdk/.../profilers/Nsight_Compute/`) para perfilar `k_dmc2` de verdad, los problemas de configuración que fueron saliendo (todos con causa y solución concretas, no descartados a ciegas), y el resultado: la causa real, con números.

## Problemas de configuración (en el orden en que aparecieron)

### 1. Permisos: `ERR_NVGPUCTRPERM`

Primer intento (línea de comandos, sobre un binario de prueba aislado sin nada de física, ver `diagnostico_kernel/`):

```
==ERROR== ERR_NVGPUCTRPERM - The user does not have permission to access NVIDIA GPU Performance Counters on the target device 0.
```

El driver de NVIDIA bloquea por defecto el acceso a los contadores de rendimiento de la GPU a usuarios normales (no-root). Se necesita `NVreg_RestrictProfilingToAdminUsers=0`.

### 2. El arreglo permanente no se aplicaba tras reiniciar

Se creó `/etc/modprobe.d/nvidia-profiling.conf`:
```
options nvidia NVreg_RestrictProfilingToAdminUsers=0
```
y se reinició — pero `ERR_NVGPUCTRPERM` seguía apareciendo. Comprobado paso a paso:
- El parámetro existe de verdad en el módulo (`modinfo nvidia | grep RestrictProfiling` lo confirma).
- No había ningún otro fichero en `/etc/modprobe.d/` pisando el valor.
- La causa real: **`/boot/initrd.img-<kernel>` era más antiguo que el fichero de configuración nuevo**. Este equipo carga el módulo `nvidia` desde la imagen `initramfs` en el arranque temprano (coherente con `nvidia_drm modeset=1` en `nvidia-graphics-drivers-kms.conf`, típico de portátiles con pantalla gestionada por la GPU NVIDIA) — esa imagen es una foto fija de `/etc/modprobe.d/` en el momento en que se generó, y no incluía el fichero nuevo.

Solución: regenerar la imagen y reiniciar otra vez:
```bash
sudo update-initramfs -u -k $(uname -r)
sudo reboot
```
Verificado después, sin `sudo`, directamente con el binario de prueba (`diagnostico_kernel/diag.cuf`): capturó el kernel y generó un informe real (`Duration 2.98 usecond`, secciones completas). Permisos resueltos.

### 3. `qmccluster` lee `in.mcv` por stdin, no por argumento

`ncu-ui` no tiene un campo de redirección de entrada estándar (`stdin`) en el diálogo de lanzamiento. Solución: un script wrapper, apuntando "Application Executable" a él en vez de al binario:

```bash
#!/bin/bash
cd /home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v2-cuda-integracion/hibrido_instrumentado || exit 1
exec ./qmccluster_tiempos < in.mcv
```
(`v2-cuda-integracion/lanza_ncu.sh`). El `exec` es la clave: sustituye el proceso del script por el del binario real conservando el mismo PID, así que `ncu` perfila el proceso correcto. El `cd` absoluto se añadió para no depender de que el campo "Working Directory" del diálogo de `ncu-ui` se aplicase de forma fiable (en la práctica, con el `cd` puesto no hizo falta seguir investigando si ese campo funcionaba o no).

### 4. El filtro `--kernel-name k_dmc2` no encontraba nada, incluso con permisos ya arreglados

Con permisos corregidos y el script funcionando, una corrida **completa y correcta** de 40 pasos DMC reales (energías evolucionando bloque a bloque, terminó sola con `FORTRAN STOP`, ~77 s de CPU) seguía devolviendo `No kernels were profiled` con `--kernel-name k_dmc2 --launch-skip 1 --launch-count 1`. Es decir: `k_dmc2` se lanzó 40 veces de verdad, y aun así el filtro por nombre no encontraba ninguna.

Comprobado el nombre real del símbolo compilado (no adivinado):
```
$ nm qmccluster_tiempos | grep -i dmc2
000000000043f340 T mdmc2_k_dmc2_
$ cuobjdump -symbols qmccluster_tiempos | grep -i dmc2
STT_FUNC  STB_GLOBAL STO_ENTRY  mdmc2_k_dmc2_
```
El símbolo contiene la subcadena `k_dmc2` sin ambigüedad — el filtro debería haber hecho match por subcadena, pero no lo hacía (razón exacta no determinada: posiblemente el modo de comparación de nombre configurado en `ncu-ui`, `"kernelnamebase": "Function"`, compara contra una representación distinta de la que se ve con `nm`/`cuobjdump`).

Solución práctica: **abandonar el filtro por nombre** y apuntar por posición, apoyándose en un hecho conocido del código (`msteps.f90 : pasodmc_gpu`): `k_split_seeds` se lanza **una única vez**, en la primerísima llamada (dentro de `if (.not.iniciado)`), y a partir de ahí todos los lanzamientos son `k_dmc2`. Con `--kernel-name` vacío, `--launch-skip 1 --launch-count 1` captura sin ambigüedad el lanzamiento nº2 de toda la corrida — el primer `k_dmc2` real. Con esto sí funcionó: `Profiling "mdmc2_k_dmc2_" - 0 (1/1)`.

## Configuración final que funcionó

```
ncu --config-file off --export <ruta>/test-tiempos-ncu --force-overwrite \
    --launch-skip 1 --launch-count 1 --set full \
    v2-cuda-integracion/lanza_ncu.sh
```
(equivalente a los campos en `ncu-ui`: Application Executable = `lanza_ncu.sh`, Working Directory = `hibrido_instrumentado/`, Kernel Name = *vacío*, Launch Skip = `1`, Launch Capture Count = `1`, Set = `full`), sobre el `in.mcv` de 50 walkers / 1+1 bloques / 20 pasos por bloque usado en los barridos de `test-tiempos.md`.

Informe generado: `/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/Test-tiempo-ncu/test-tiempos-ncu.ncu-rep`. Se puede volver a consultar sin relanzar nada con:
```bash
ncu --import test-tiempos-ncu.ncu-rep --page details
```

**Nota sobre el aviso de "tarda más de lo esperado"**: con `--set full`, ncu re-ejecuta el kernel varias veces (Kernel Replay, una pasada por grupo de contadores que no caben a la vez en el hardware) — para un kernel que ya de por sí tarda segundos en ejecutarse una vez, la captura completa puede tardar varios minutos. Es esperado, no un fallo.

## Resultado: por qué `k_dmc2` es lento (con números, no hipótesis)

| métrica | valor | lectura |
|---|---|---|
| Duration (esta captura, con instrumentación de `ncu` activa) | 5.36 s | mayor que el ~2 s nativo medido con `system_clock` — la propia instrumentación de `ncu` añade overhead; lo que importa aquí son las proporciones, no el absoluto |
| Grid Size / Block Size | 2 bloques x 32 hilos = 64 hilos | coherente con 50 walkers (`ceil(50/32)=2` bloques) |
| **Registers Per Thread** | **247** | enorme para un kernel GPU (habitual: 32-64) |
| Theoretical Active Warps per SM / Occupancy | 8 warps / **16.67 %** | directamente limitado por los 247 registros/hilo (banco de registros del SM se agota) |
| Achieved Occupancy | **2.08 %** | muy por debajo incluso del ya bajo techo teórico — con solo 2 bloques de 24 multiprocesadores, casi toda la GPU está parada |
| Compute (SM) Throughput | 0.12 % | la GPU casi no calcula |
| Memory Throughput | 0.19 % | ni tampoco mueve datos, en términos de ancho de banda |
| **No Eligible (Scheduler Statistics)** | **92.76 %** | en 9 de cada 10 ciclos, ningún warp tenía instrucción lista para emitir — la GPU está esperando, no trabajando |
| **Stall dominante (Warp State Statistics)** | **60.5 % del tiempo de stall**, esperando "scoreboard dependency on a L1TEX (local, global, surface, texture) operation" | el cuello de botella es memoria, no cómputo |
| **Accesos a memoria no coalescidos (Source Counters)** | **91 % de los sectores leídos son sectores desperdiciados** (14.620.923 de 15.982.662) | de cada 4 "trozos" de 32 bytes que trae la GPU por petición, solo se aprovecha ~1 — patrón de acceso muy disperso entre hilos del mismo warp |
| L1/TEX Hit Rate / L2 Hit Rate | 51.3 % / 99.4 % | los datos probablemente caben en L2 (tablas de consulta), pero el patrón de acceso L1 es malo |
| Instrucciones FP64 | 724.956.940 ejecutadas (177.706 fusionadas, 710.999 no fusionadas) | confirma que es una carga de coma flotante en doble precision real, no un cuello de botella de otro tipo |

**Conclusión**: no es un problema de lanzamiento de kernel, ni de gestión de memoria alrededor de `pasodmc_gpu` (ambas cosas ya descartadas en `test-tiempos.md`). Es un problema **estructural del propio kernel `k_dmc2`**, con dos causas confirmadas y encadenadas:

1. **247 registros por hilo** — casi seguro porque toda la cadena de física (`dmc2` -> `hpsi` -> `derananum`/`vpot` -> `wavef`+derivadas+`potenbh`+`ccuerpo` -> `rota` -> `mrandom`) se compila e inlinea en un único kernel enorme, con muchísimas variables locales vivas a la vez. Esto limita a 8 warps activos por SM como máximo, muy por debajo del máximo de la tarjeta.
2. **91 % de los accesos a memoria global son no coalescidos** — con tan pocos warps activos para "tapar" esa espera con trabajo de otro warp, cada acceso lento a memoria se convierte directamente en tiempo de reloj real. Esto explica el 92.76 % de ciclos sin ningún warp listo para ejecutar, y por extensión, el coste real medido con `system_clock`.

No se ha llegado a identificar la línea de código exacta responsable del patrón de acceso no coalescido (haría falta recompilar con `-gpu=lineinfo` y usar la vista "Source" de `ncu` para correlacionar instrucciones SASS con líneas Fortran) — queda como siguiente paso si se decide abordar la optimización. Los candidatos más probables, por cómo está escrita la física, son las funciones con tablas de consulta (`myexp`/`mysin`/`mycos`/`mypow`/`myacos`, en `glibc_*_mod.cuf`), ya que acceden a memoria con un índice que depende del valor de cada hilo, y por tanto probablemente distinto entre los hilos de un mismo warp.

**Este siguiente paso se hizo — ver Parte 2 más abajo.**

---

# Parte 2 — Localizando la causa exacta con `-gpu=lineinfo`, y un arreglo real verificado

## Recompilar con información de línea

`nvfortran` soporta `-gpu=lineinfo` (confirmado con `nvfortran -gpu=help`): incrusta la correspondencia SASS↔línea Fortran sin bajar la optimización ni cambiar el comportamiento del binario. Añadido a `compilar.sh` (`nvfortran -cuda -Kieee -Mnofma -gpu=lineinfo ...`), recompilado, y verificado que `in.mcv`/`conf.20.00.HH` seguían siendo exactamente los mismos que en la Parte 1 (mismos 50 walkers, 1+1 bloques, 20 pasos, mismo `md5sum` de `conf.20.00.HH`) para que la comparación fuera directa.

## La página "Source" de `ncu`

Con `lineinfo`, la página "Source" (`ncu --page source`, o la pestaña "Source" en `ncu-ui`) desglosa el kernel por cada función de device que lo compone (en este caso, ~30: todas las funciones inlineadas dentro de `k_dmc2` — `myexp`, `mysin`, `derananum`, `hpsi`, `vpot`, `potenbh`, `ccuerpo`, etc.), con el código Fortran real línea a línea junto a métricas por línea. Exportado desde `ncu-ui` a CSV (`Test-tiempo-ncu/prueba2-ncu.csv`) y analizado con un script Python que suma/ordena por la columna `L2 Theoretical Sectors Global Excessive` (la métrica exacta que señalaba el 91% de la Parte 1) a través de las ~30 funciones.

**Resultado, sin ambigüedad**: las 5 líneas que más sectores excedentes acumulan de todo el kernel están **todas dentro de `myexp`** (`glibc_exp_mod.cuf`):

```fortran
! glibc_exp_mod.cuf, funciones bits_of/real_of (líneas 60-74 en la version original)
attributes(host, device) function bits_of(x) result(ii)
  ...
  integer(kind=i8) :: tmp(1)
    tmp = transfer( (/x/), tmp)     ! L64: 6.797.629 sectores excedentes
    ii = tmp(1)
end function bits_of

attributes(host, device) function real_of(ii) result(x)
  ...
  real(kind=r8) :: tmp(1)
    tmp = transfer( (/ii/), tmp)    ! L72: 6.998.143 sectores excedentes -- la peor linea de TODO el kernel
    x = tmp(1)
end function real_of
```

más la consulta a la tabla dentro de `myexp` (`tail = real_of(exp_tab(idx))`, L134: 1.090.681). **`dmc2.cuf` (mi sospecha original del array `atom(natom,n)`) solo aparece una vez en toda la lista, con 6.993** — real, pero ~1000x menor que la peor línea de `myexp`. La hipótesis del array de `k_dmc2` quedaba así relegada a un actor muy secundario frente a este hallazgo.

## Por qué: el comentario del propio código ya lo explicaba

El comentario original de `bits_of`/`real_of` (en `glibc_exp_mod.cuf`, escrito durante el port original) documentaba el porqué del `TRANSFER` envuelto en un array de tamaño 1: un `TRANSFER` escalar directo **no enlaza** en esta versión de `nvfortran` dentro de una función `attributes(host,device)` compilada con `-cuda` (falta el símbolo de runtime `__pgi_transfer_dbl2long`/`long2dbl`, comprobado que no existe en ningún `.a`/`.so` del SDK). El array de tamaño 1 es un workaround ya probado que compila y da el resultado correcto — pero, según `ncu`, aparentemente a costa de que el compilador reserve esos "arrays" en memoria "local" de la GPU (que aunque privada por hilo, pasa por la misma jerarquía L1/L2 que la memoria global) en vez de en un registro.

## El arreglo: `EQUIVALENCE` en vez de `TRANSFER`

```fortran
attributes(host, device) function bits_of(x) result(ii)
  real(kind=r8), intent (in) :: x
  integer(kind=i8) :: ii
  real(kind=r8) :: xx
  integer(kind=i8) :: iii
  equivalence (xx, iii)
    xx = x
    ii = iii
end function bits_of

attributes(host, device) function real_of(ii) result(x)
  integer(kind=i8), intent (in) :: ii
  real(kind=r8) :: x
  real(kind=r8) :: xx
  integer(kind=i8) :: iii
  equivalence (xx, iii)
    iii = ii
    x = xx
end function real_of
```

`EQUIVALENCE` (dos variables comparten la misma posición de memoria) evita el `TRANSFER` por completo — mismo algoritmo, mismos bits, sin la llamada que forzaba el workaround original.

### Verificación 1 — aislada, antes de tocar nada real

`test-tiempos/prueba_equivalence_exp/test_equivalence_exp.cuf`: copia de `myexp`/`bits_of`/`real_of`/`exp_specialcase` con **las dos versiones a la vez** (`_orig` con `TRANSFER`, `_eq` con `EQUIVALENCE`), comparadas en el mismo programa, con los mismos 14 casos ya validados en `docs-kernels/glibc_math.md` (cero, ±1, ±0.5, `e`, `1e-30`, ±20, ±700 -- activa la rama `specialcase`, `π/2`), tanto en CPU como en GPU.

```
nvfortran -cuda -Kieee -Mnofma test_equivalence_exp.cuf -o test_equivalence_exp && ./test_equivalence_exp
```

**Resultado**: compila y enlaza sin problemas (confirma que `EQUIVALENCE` esquiva el símbolo de runtime que faltaba), y los 14 casos dan **exactamente los mismos bits**, CPU y GPU, `_orig` vs `_eq`:
```
PASA: EQUIVALENCE da EXACTAMENTE los mismos bits que TRANSFER, en CPU y GPU
```

### Verificación 2 — end-to-end, en la orquestación real

Aplicado el cambio a `hibrido_instrumentado/glibc_exp_mod.cuf` (solo la copia de pruebas de `test-tiempos/`, no `hibrido/`), recompilado, y comparados los `.log` completos de `opcion=4` y `opcion=5` (50 walkers, 1+1 bloques, 5 pasos, mismo `conf.20.00.HH`) contra los `base_opcion4.log`/`base_opcion5.log` de antes del cambio:

```bash
diff resultados/base_opcion4.log resultados/verif_equivalence_op4b.log
diff resultados/base_opcion5.log resultados/verif_equivalence_op5.log
```

**Únicas diferencias: la marca de hora y el tiempo de CPU.** Todas las energías, tabla de bloques, población — bit a bit idénticas en ambos casos (CPU y GPU). El cambio no altera ningún resultado físico.

### Descubrimiento adicional: el arreglo alcanza a `mypow`, `myacos`, `mysin`/`mycos` gratis

`glibc_pow.cuf`, `glibc_acos.cuf` y `glibc_sincos.cuf` no duplican `bits_of`/`real_of` — los tres hacen `use glibc_exp_mod, only: bits_of, real_of, ...` y reutilizan exactamente las dos funciones ya corregidas (confirmado leyendo sus `use`, no asumido). Un único cambio, en un único sitio, corrige el mecanismo de reinterpretación de bits para las **cinco** funciones transcendentales portadas a la vez.

## El resultado, con números

Comparación directa (misma configuración: 50 walkers, 1+1 bloques, 5 pasos, mismo `conf.20.00.HH`), del propio reparto de tiempos de `pasodmc_gpu`:

| bucket | antes | después | factor |
|---|---|---|---|
| **kernel `k_dmc2` (device)** | **19.1139 s** | **0.1284 s** | **~149x** |
| tiempo total del run | 21.7384 s | 2.7609 s | ~7.9x |
| % del total que es el kernel | 87.93 % | 4.65 % | (el kernel deja de ser el cuello de botella) |
| % del total que es "otros" (E/S por bloque) | 11.99 % | 94.70 % | (mismo coste fijo de siempre, ahora domina porque el kernel casi ha desaparecido) |

Y en el propio `ncu`, comparando el mismo lanzamiento perfilado (`--set full`, mismo `in.mcv`):

| métrica (`ncu`) | antes | después |
|---|---|---|
| Duration (con instrumentación de `ncu` activa) | 5.36 s | **25.27 ms** (~212x) |
| Registers Per Thread | 247 | 247 (sin cambios — no se ha tocado esto) |
| Compute (SM) Throughput | 0.12 % | 1.65 % |
| Memory Throughput | 0.19 % | 0.44 % |
| Avg. Active Threads Per Warp | 11.69 | 21.61 |
| Sectores excedentes (no coalescidos) | 14.620.923 (**91 %** de 15.982.662) | 621.432 (**57 %** de 1.084.786) |
| Achieved Occupancy | 2.08 % (igual que el techo teórico 16.67%, sin cambios) | 2.08 % (sin cambios — coherente, no se ha tocado grid/registros) |

El total de sectores de memoria pedidos por el kernel bajó de ~16 millones a ~1.08 millones (mucho menos tráfico de memoria en general), y de ese total mucho menor, la fracción desperdiciada bajó del 91% al 57% — sigue siendo alta, pero ya no es el problema dominante que era.

## Comentarios automáticos de `ncu` sobre el informe nuevo (post-arreglo) — qué sigue abierto y qué no aplica aquí

`ncu` genera automáticamente notas de optimización ("rules") por sección. Las relevantes del informe nuevo, tal cual las da la herramienta:

- **Small Grid (Launch Statistics), Est. Speedup 91.67%**: *"The grid for this launch is configured to execute only 2 blocks, which is less than the GPU's 24 multiprocessors."* — **sigue sin resolver**, es el problema de tamaño de rejilla que ya se discutió (atado al número de walkers con el diseño actual de 1 hilo = 1 walker; no lo toca este arreglo).
- **Achieved Occupancy, Est. Speedup 87.5%**: sin cambios (2.08% conseguido frente a 16.67% teórico) — sigue limitado por los mismos 247 registros/hilo y el grid pequeño, ninguno de los dos tocado en este arreglo.
- **Short Scoreboard Stalls (Warp State Statistics), Est. Speedup 42.84%** (bajó desde 60.52% antes, pero sigue siendo el motivo de stall dominante): *"...consult the Memory Workload Analysis section... consider increasing the usage of low-latency registers... consider moving frequently used data to shared memory."* — mismo diagnóstico de fondo que motivó el cambio de `EQUIVALENCE`; con `myexp` ya arreglado, lo que queda de este stall es candidato a venir del segundo grupo (`der_wavefhe4_mod.cuf` y compañía, ver más abajo).
- **Uncoalesced Global Accesses (Source Counters), Est. Speedup 1.95%**: *"This kernel has uncoalesced global accesses resulting in a total of 621.432 excessive sectors (57% of the total 1.084.786 sectors)."* — mejorado (era 91%), pero **sigue sin resolver del todo**.
- **FP64 Non-Fused Instructions, Est. Speedup 8.40%**: *"This kernel executes 175634 fused and 616373 non-fused FP64 instructions. By converting pairs of non-fused instructions to their fused... higher-throughput equivalent, the achieved FP64 performance could be increased by up to 39%."* — **NO aplica a este proyecto sin más matización**: fusionar instrucciones FP64 (usar FMA) es exactamente lo que `-Mnofma` desactiva **a propósito**, en toda la base de código, porque cambia el redondeo y rompería la coincidencia bit a bit ya validada contra `gfortran`/CPU que sostiene todo el árbol de pruebas del proyecto. Aceptar esta sugerencia de `ncu` sin más contradiría la convención establecida desde el principio (`gpu_vs_gfortran_arbol.md`) — se descarta explícitamente, no por descuido.
- **Compute Workload Analysis**: cambia de *"all compute pipelines are under-utilized"* (antes) a *"Balanced FP64 is the highest-utilized pipeline (21.6%)... well-utilized, but shouldn't be a bottleneck"* (después) — el cómputo real ya pesa más, proporcionalmente, ahora que se ha quitado de en medio el ruido de memoria de `myexp`.

## El nuevo cuello de botella #1: `der_wavefhe4_mod.cuf`

Repitiendo el mismo análisis por línea (`Test-tiempo-ncu/prueba3-ncu-transfer.csv`, informe posterior al arreglo) y excluyendo ya `glibc_exp_mod.cuf`: el total de sectores excedentes de todo el kernel bajó de ~14.6 millones a **655.300** (~22x menos). El nuevo primer puesto es **`der_wavefhe4_mod.cuf`, líneas 82-91** (bucle de pares de átomos de He4, patrón `atom(iatom)%comp - atom(jatom)%comp` y las derivadas que dependen de ahí), con `glibc_pow.cuf` (el residuo de la misma familia `bits_of`/`real_of`, ya reducido pero no cero) y `derananum_mod.cuf`/`der_wavefx_mod.cuf`/`mccuerpo_mod.cuf`/`dmc2.cuf` (mismo patrón `atom(iatom)%comp-atom(jatom)%comp`, mi sospecha original sobre el orden de índices `atom(natom,n)`) repartiéndose el resto, cada uno un orden de magnitud por debajo de lo que era `myexp`.

**No investigado más allá de esto** — queda como trabajo futuro si se decide seguir esta línea de optimización. El "Small Grid"/"Achieved Occupancy" (atados al número de walkers, no a este código) y el patrón de acceso de `der_wavefhe4_mod.cuf` y su familia son los dos frentes que quedan abiertos.

## Ficheros de esta parte

- `test-tiempos/prueba_equivalence_exp/test_equivalence_exp.cuf` — prueba aislada `_orig` vs `_eq`.
- `hibrido_instrumentado/glibc_exp_mod.cuf` — arreglo aplicado (solo en la copia de pruebas; pendiente decidir si se lleva a `hibrido/`, la versión validada).
- `test-tiempos/resultados/verif_equivalence_op4b.log`, `verif_equivalence_op5.log` — corridas de verificación end-to-end.
- `Test-tiempo-ncu/prueba2-ncu.csv` (antes del arreglo) y `Test-tiempo-ncu/prueba3-ncu-transfer.csv` (después) — exportaciones CSV de la página "Source" de `ncu-ui`, con el código Fortran línea a línea.
- `Test-tiempo-ncu/comentarios-ncu.pdf` — captura completa de la página "Details" del informe posterior al arreglo (todas las secciones y notas automáticas citadas arriba).

---

# Parte 3 — El segundo cuello de botella: `atom(natom,n)` vs. layout transpuesto

## Localizando la causa exacta (no solo la sospecha)

Con `myexp` arreglado, el nuevo problema #1 (ver Parte 2, "nuevo cuello de botella") es `der_wavefhe4_mod.cuf` líneas 46-91 (bucle de pares de átomos He4, acumulando en `d1wf`/`d2wf`). Antes de proponer un arreglo, se comprobó **por qué** con la columna `Address Space` de la página Source de `ncu` (exportada a CSV, `prueba3-ncu-transfer.csv`) — el criterio exacto para distinguir "el compilador lo manda a memoria local" (el problema de `myexp`) de "es de verdad memoria global mal distribuida":

```
L46  Live Regs=34   AddrSpace=Global(15)  Op=Load(15)          Size=64(15)  | rtemp%comp=atom(iatom)%comp-atom(jatom)%comp
L82  Live Regs=44   AddrSpace=Global(6)   Op=Load(3),Store(3)  Size=64(6)   | d1wf(iatom)%comp(:)=d1wf(iatom)%comp(:)+ujasp*rtemp%comp(:)
```

**`Address Space = Global`, no `Local`.** Esto descarta que sea el mismo mecanismo que `myexp` y confirma la hipótesis original sobre `atom(natom,n)`. A continuación, la explicación de qué significa exactamente ese problema y en qué consiste el arreglo, con un ejemplo pequeño.

## Qué había antes: `atom(natom, n)`, explicado con un ejemplo pequeño

En vez de 22 átomos y 50 walkers (el caso real), imagina solo **3 átomos** y **4 walkers**, para que quepa en la cabeza. `atom(3, 4)` es una tabla de 3 filas (átomos) y 4 columnas (walkers):

```
           walker1  walker2  walker3  walker4
átomo 1:     A11      A12      A13      A14
átomo 2:     A21      A22      A23      A24
átomo 3:     A31      A32      A33      A34
```

Fortran no guarda esto como una tabla de verdad — lo guarda en una fila única, larguísima, de memoria. Y la regla de Fortran es: **el primer índice (aquí, el átomo) es el que va "seguido"**. Así que en memoria, el orden real es:

```
posición:  1    2    3    4    5    6    7    8    9   10   11   12
valor:    A11  A21  A31  A12  A22  A32  A13  A23  A33  A14  A24  A34
          └─ walker1 ─┘ └─ walker2 ─┘ └─ walker3 ─┘ └─ walker4 ─┘
```

Cada walker tiene sus 3 átomos juntitos, seguidos. Eso es **bueno si un único hilo va a leer los 3 átomos de SU walker uno detrás de otro** (rápido, todo cerca). Pero es **malo para la GPU**, porque la GPU no manda un hilo detrás de otro — manda 32 hilos **a la vez**, cada uno con un walker distinto, y **los 32 ejecutan la misma instrucción al mismo tiempo**. Si en ese instante todos están leyendo "mi átomo 1" (`iatom=1` fijo, walker distinto cada hilo), están pidiendo `A11`, `A12`, `A13`, `A14` — que en la fila de memoria de arriba están en las posiciones 1, 4, 7, 10: **saltando de 3 en 3**, no seguidas. La GPU trae la memoria en bloques (como cajas de varias casillas); si lo que necesitas está salteado, tiene que abrir muchas cajas para sacar solo 1 casilla útil de cada una — eso es el "91% desperdiciado" que vimos en la Parte 1.

## Qué hace la solución: transponer + una "libreta" local por hilo

Primero, **invertir la tabla** — ahora walkers primero, átomos después: `atom_t(4, 3)` (4 walkers, 3 átomos):

```
             átomo1  átomo2  átomo3
walker 1:     A11     A21     A31
walker 2:     A12     A22     A32
walker 3:     A13     A23     A33
walker 4:     A14     A24     A34
```

En memoria, ahora es:
```
posición:  1    2    3    4    5    6    7    8    9   10   11   12
valor:    A11  A12  A13  A14  A21  A22  A23  A24  A31  A32  A33  A34
          └── todos, átomo 1 ──┘ └── todos, átomo 2 ──┘ └── todos, átomo 3 ──┘
```

Ahora, si los 32 hilos leen "mi átomo 1" a la vez, piden `A11,A12,A13,A14` — posiciones 1,2,3,4: **seguidas de verdad**. Eso es lo que se quiere.

**El problema que esto crea, y por qué hace falta el paso extra**: con la tabla invertida, un único hilo ya NO tiene sus propios 3 átomos juntos (su walker 1 son las posiciones 1, 5, 9 — salteadas). Así que **cada hilo, nada más empezar, se copia sus propios 3 átomos a una "libreta" pequeña, propia, solo suya** (un array local de 3 elementos, que vive en el hilo, no en la tabla grande). Esa copia SÍ es coalescida (los 32 hilos leen "átomo 1" de todos a la vez, seguido, como arriba). Y una vez copiados a su libreta, el hilo hace todo el cálculo con su libreta — exactamente igual que antes, sin cambiar nada de la física (`hpsi`/`derananum`/etc. no cambiarían nada) — y al final copia el resultado de vuelta a la tabla grande, otra vez de forma seguida entre los 32 hilos.

Así que el cambio real son dos cosas: (1) la tabla grande cambia de orden (átomos-primero → walkers-primero), y (2) se añade un pequeño paso de "copiar a mi libreta antes de calcular, copiar de vuelta al terminar" en vez de trabajar directamente sobre la tabla grande.

## Prueba aislada: `test-tiempos/prueba_transpuesta_atom/test_transpuesta_atom.cuf`

Réplica del patrón de cómputo real de `der_wavefhe4_mod.cuf` (bucle de pares `iatom`/`jatom`, acumulando en `d1wf`/`d2wf` — misma estructura, física de juguete en vez de la real, ya que aquí lo que importa es el patrón de acceso a memoria, no el resultado físico) con **dos kernels en el mismo programa**:

- `k_orig`: `atom(natom,n)`, exactamente como ahora.
- `k_transpuesta`: `atom_t(n,natom)`, con la copia local descrita arriba.

Mismos datos de entrada (22 átomos x 50 walkers, valores deterministas), mismo cálculo (`paso_fisico`, compartido literalmente por las dos versiones — ninguna diferencia de algoritmo posible).

```bash
nvfortran -cuda -Kieee -Mnofma -gpu=lineinfo test_transpuesta_atom.cuf -o test_transpuesta_atom && ./test_transpuesta_atom
```

**Resultado 1 — corrección**: `d1wf`/`d2wf` idénticos bit a bit entre las dos versiones, para los 50 walkers x 22 átomos:
```
PASA: layout transpuesto (con copia local) da EXACTAMENTE los mismos resultados
```

**Resultado 2 — con `ncu` (`--set full` sobre los dos kernels a la vez, mismo informe)**:

| métrica | `k_orig` | `k_transpuesta` | factor |
|---|---|---|---|
| Duration | 584.32 µs | 392.74 µs | ~1.49x más rápido |
| Sectores excedentes (no coalescidos) | 167.980 | 3.289 | **~51x menos** |
| Sectores totales pedidos | 227.000 | 5.291 | ~43x menos trafico de memoria en total |
| % de sectores desperdiciados | 74 % | 62 % | mejora, no desaparece del todo |

La técnica funciona: mismo resultado exacto, y reduce de verdad el desperdicio de memoria (el volumen absoluto de sectores desperdiciados cae ~51x, aunque el porcentaje relativo siga siendo alto porque el total de trafico tambien bajo mucho).

## Estado: técnica verificada, aplicación al código real pendiente

Esta prueba confirma que la técnica es correcta y efectiva **de forma aislada**. Aplicarla al código real (`dmc2.cuf`/`k_dmc2`, y el empaquetado en `pasodmc_gpu` de `msteps.f90`) es un cambio bastante mayor que el de `EQUIVALENCE`: toca la firma completa de `k_dmc2` (~18 arrays, no solo `atom`) y los bucles de empaquetado/desempaquetado en el host — **no hecho todavía**, queda pendiente de decisión.

## Ficheros de esta parte

- `test-tiempos/prueba_transpuesta_atom/test_transpuesta_atom.cuf` — prueba aislada `k_orig` vs `k_transpuesta`.
- `test-tiempos/prueba_transpuesta_atom/resultado_transpuesta.ncu-rep` — informe de `ncu` con los dos kernels perfilados en la misma corrida.

---

# Parte 4 — El nuevo cuello de botella (`der_wavefhe4`) no es un problema de llamadas de función

## Punto de partida: los números no se movían

Tras la transposición de `atom` (Parte 3), el problema #1 pasó a ser `der_wavefhe4_mod.cuf`, líneas 82-91 (`d1wf(iatom)%comp(:)=d1wf(iatom)%comp(:)+ujasp*rtemp%comp(:)` y similares) — 84.360+84.360 sectores excedentes, con `Address Space=Global`. Comprobado con el código real (`derananum_mod.cuf:148,160`): esas líneas no trabajan sobre el array `atom`/`dwf` que se transpuso — `d1wf`/`d2wf` (nombre del argumento dentro de `der_wavefhe4`) es, en esta llamada concreta, `d1wfhe4`/`d2wfhe4`: un cajón de trabajo **local**, propio de un único walker, que `derananum` crea de cero en cada llamada (línea 148) y le pasa a `derwavefhe4` (línea 160) — nunca toca la tabla de varios walkers.

## Hipótesis descartada con una prueba directa sobre el código real: no es la llamada de función

Hipótesis: como `d1wfhe4` se pasa como argumento a través de una llamada de función real (`derananum`→`derwavefhe4`, funciones separadas, confirmado por la enorme tanda de `STL` de guardado de registros al entrar en `der_wavefhe4` vista en el ensamblador), el compilador pierde la certeza de que es memoria privada del hilo al cruzar esa frontera, y usa un tipo de acceso que `ncu` clasifica como `Global`.

**Primera comprobación (aislada, de juguete)**: `test-tiempos/prueba_fusion_derananum/test_fusion.cuf` — el mismo patrón de cómputo (bucle de pares, acumulando en un array local) en dos versiones: `k_separado` (llamada de función real) y `k_fusionado` (mismo código pegado a mano, sin llamada). Resultado: **exactamente los mismos 3.278 sectores excedentes en las dos** — pero, al mirar el `Address Space` real, **las dos salían `Local`**, no `Global`. La prueba nunca reprodujo el problema que se quería estudiar (con solo ~47 registros/hilo, muy por debajo de los 247 del kernel real) — así que esta comparación no servía para concluir nada.

**Segunda comprobación (sobre el código real, con presión de registros real)**: se aplicó el mismo "pegado a mano" **directamente en `derananum_mod.cuf`** (sustituyendo `call derwavefhe4(atom(1:nhe4), d1wfhe4, d2wfhe4)` por el cuerpo entero de `derwavefhe4` copiado ahí dentro, variables renombradas con sufijo `_fus` para no chocar) — dentro del kernel real completo, con sus 247 registros/hilo de presión, no los 47 del juguete. Verificado primero que sigue dando el mismo resultado exacto (`diff` sin cambios salvo hora/tiempo de CPU), y perfilado con `ncu`:

```
d1wfhe4(iatom)%comp(:) = d1wfhe4(iatom)%comp(:) + ujasp_fus*rtemp_fus%comp(:)
   LD.E.64 R6, [R58.64]
   ST.E.64 [R58.64], R6
   Address Space = Global(6)
   L2 Theoretical Sectors Global Excessive = 84.360
```

**Exactamente el mismo número que antes de fusionar (84.360), sin diferencia alguna.** Con presión de registros real, fusionar tampoco cambia nada. Esto **descarta con certeza la hipótesis de la llamada de función** — no es el motivo, ni con poca presión de registros (donde ni siquiera aparecía el síntoma) ni con la presión real (donde el síntoma aparece igual, fusionado o no).

Revertido el cambio experimental en `derananum_mod.cuf` tras esta comprobación (no aportaba nada) — verificado de nuevo bit a bit contra el resultado conocido correcto antes de continuar.

## Nueva hipótesis, esta vez apoyada en la instrucción real usada

La instrucción real es `LD.E.64`/`ST.E.64` — la forma **genérica** de acceso (no `LDG` global "de verdad" ni `LDL` local "de verdad"). Esto es necesario porque `d1wfhe4(iatom)` se indexa con `iatom`, una variable que cambia en cada vuelta del bucle — un array indexado así no puede vivir en un registro (los registros no son direccionables en tiempo de ejecución), tiene que estar en algún tipo de memoria direccionable.

La hipótesis ahora (todavía no comprobada) es que, con solo ~47 registros/hilo (la prueba de juguete), el compilador tiene margen de sobra para usar la pila rápida de cada hilo (`LDL`/`STL`, clasificado `Local`) — pero con 247 registros/hilo (el kernel real), ese margen se agota, y el compilador recurre a un mecanismo de reserva que, por dentro, usa memoria global (`LD.E`/`ST.E`, clasificado `Global`). Si esto es así, la vía de arreglo no sería tocar cómo se organiza el código (llamadas de función, fusión) sino **reducir la presión de registros global del kernel** — el punto que ya estaba en el plan (`-gpu=maxregcount`, o reestructurar para que el kernel entero necesite menos registros a la vez). No comprobado todavía.

## Ficheros de esta parte

- `test-tiempos/prueba_fusion_derananum/test_fusion.cuf` — prueba aislada de juguete (`k_separado` vs `k_fusionado`), no concluyente por baja presión de registros.
- `test-tiempos/prueba_fusion_derananum/resultado_fusion.ncu-rep` — informe de esa prueba.
- Prueba sobre `derananum_mod.cuf` real: aplicada, verificada (bit a bit correcta), perfilada, y **revertida** tras confirmar que no aportaba mejora — no queda rastro en el código, solo en este documento y en `Test-tiempo-ncu/resultado-fusion-real.ncu-rep`.

---

# Parte 5 — Descartada también la presión de registros

## La prueba: `-gpu=maxregcount:128`

Flag de compilador que fuerza un tope de registros por hilo (sin tocar el código): `nvfortran -cuda -Kieee -Mnofma -gpu=lineinfo,maxregcount:128 ...` (`test-tiempos/compilar_maxreg.sh`, copia de `compilar.sh` con el flag añadido). El compilador usaba 247 registros/hilo por su cuenta; con esto se le obliga a bajar a 128.

Verificado primero que el resultado sigue siendo exacto (`diff` sin cambios salvo hora/tiempo de CPU). Perfilado con `ncu`:

| métrica | sin `maxregcount` (247 registros) | con `maxregcount:128` |
|---|---|---|
| Registers Per Thread | 247 | 128 |
| Theoretical Occupancy | 16.67 % | **33.33 %** (sube, como se esperaba) |
| Achieved Occupancy | 2.08 % | **2.08 %** (igual — el techo no era el problema aqui, la rejilla de 2 bloques si) |
| Sectores excedentes totales del kernel | 568.214 | 533.580 (~6 %, poco) |
| **Línea `d1wf(iatom)%comp(:)=d1wf(iatom)%comp(:)+ujasp*rtemp%comp(:)` (`der_wavefhe4_mod.cuf:82`)** | **Global(6), 84.360 sectores excedentes** | **Global(6), 84.360 sectores excedentes — EXACTAMENTE IGUAL** |

**Ni un sector de diferencia en la línea que nos interesa**, ni con 247 registros ni con 128. Tercera prueba directa (después de la fusión) que da resultado nulo.

## Por qué, en retrospectiva, esto no podía funcionar

`d1wf(iatom)` se indexa con `iatom`, que cambia en cada vuelta del bucle. Por diseño del hardware de la GPU, **un array indexado por una variable que cambia en tiempo de ejecución no puede vivir en un registro, tengas 64 registros libres o 247** — los registros no son direccionables dinámicamente. El número de registros disponibles afecta a otras variables (escalares, cosas que sí caben en un registro fijo), pero no decide dónde vive este array en concreto. La hipótesis nunca tenía por qué funcionar, y esta prueba lo confirma con datos en vez de dejarlo en el aire.

## Estado: dos hipótesis descartadas con pruebas directas, la causa real sigue abierta

Ni la llamada de función (Parte 4) ni la presión de registros (esta parte) explican por qué `d1wf`/`d2wf` dentro de `der_wavefhe4` salen `Global` en vez de `Local`. Ambas se comprobaron directamente sobre el código real, no solo en pruebas de juguete, y las dos dieron resultado nulo (mismo número exacto de sectores excedentes). La causa real queda sin identificar — candidato para retomar en otra sesión, posiblemente investigando si el problema viene de fusionar la cadena **entera** (`k_dmc2`→`dmc2`→`hpsi`→`derananum`→`der_wavefhe4`, los 4 niveles, no solo el último) en vez de un único eslabón.

Revertido `-gpu=maxregcount` tras esta prueba — `hibrido_instrumentado/` queda compilado con `compilar.sh` (sin `maxregcount`, sin fusión), el mismo estado que al cierre de la Parte 3.

## Ficheros de esta parte

- `test-tiempos/compilar_maxreg.sh` — script de compilación con `-gpu=maxregcount:128` (se queda en el repositorio para reproducir la prueba; el binario activo de `hibrido_instrumentado/` está compilado sin él).
- `Test-tiempo-ncu/resultado-maxreg.ncu-rep` — informe de `ncu` de esta prueba.

---

# Parte 6 — Auditoría de variables sobrantes: dos pruebas superficiales, ninguna baja los registros

## Motivación

Descartada la presión de registros como causa del `Global` (Parte 5), queda la pregunta de fondo que se hizo directamente: **¿hay margen real para bajar los 247 registros/hilo?** Antes de plantear nada invasivo, se hizo una auditoría completa, fichero a fichero, de toda la cadena de `k_dmc2` (`dmc2`, `hpsi`, `derananum`, `der_wavefhe4`, `der_wavefx`, `vpot`, `potenbh`, `ccuerpo`, `He_dihydrogen`, `rota`, `mrandom`/`rand_gpu`, `d_uhex4`, `mVheheVphehe`, `angle_scalar_vec`, `glibc_exp`/`glibc_pow`/`glibc_sincos`/`glibc_acos`), buscando dos cosas: variables declaradas y nunca usadas, y código condicionado por variables que en este proyecto son siempre el mismo valor.

**Resultado de la auditoría**: prácticamente todo el árbol está limpio (cada variable declarada se usa en algún sitio). Tres excepciones reales:

1. **`He_dihydrogen.f`**: 6 variables locales declaradas y nunca usadas en ningún otro sitio del fichero (confirmado con `grep`, no a ojo): `V_RGTH`, `E_total`, `rh3`, `dFdr`, `dFdtheta`, `b`.
2. **`hpsi_mod.cuf`**: la rama `if(libre) call valibre(...)` (con su array `dwf_libre(3,natom)`) nunca se ejecuta en este proyecto — `libre=.F.` siempre (interacción real, nunca el caso "partícula libre"), confirmado en `in.mcv`.
3. **`derananum_mod.cuf`/`der_wavefx_mod.cuf`**: con `nhe3=0` siempre en este proyecto (confirmado en `in.mcv` y ya reconocido en el propio comentario del código), los bucles `do ihe3=1,nhe3`/`do jhe3=1,nhe3` nunca ejecutan ninguna vuelta — y dentro de ese segundo bucle, **`duhe3x`/`uhe3x` completos** (~90 líneas de física real: polinomios de Legendre, varias llamadas a `mypow`) son código que nunca se alcanza.

En los tres casos, el motivo de que el compilador no pode esto por sí solo es el mismo: `libre` y `nhe3` son variables `device` de **tiempo de ejecución** (fijadas al leer `in.mcv`), así que el compilador no puede demostrar en tiempo de compilación que esas ramas son inalcanzables — aunque nosotros sepamos, por la configuración real de este proyecto, que nunca se disparan.

## Prueba 1: quitar las 6 variables realmente sin usar de `He_dihydrogen.f`

El caso más simple y seguro — variables genuinamente desconectadas de todo cálculo, sin ninguna condición de por medio. Quitadas de la declaración (`He_dihydrogen.f`), recompilado, verificado bit a bit correcto.

**Resultado con `ncu`**: `Registers Per Thread` sigue en **247, sin cambio**. El compilador ya las eliminaba solo — es la comprobación más básica que puede hacer un compilador ("esta variable se declara y no vuelve a aparecer en ningún sitio"), no hacía falta nuestra ayuda. Se deja aplicado igualmente (limpieza real, sin ninguna contrapartida).

## Prueba 2: convertir `nhe3` y `libre` en `parameter` (constantes de compilación)

Para que el compilador pueda demostrar por sí mismo que las ramas de `nhe3`/`libre` son inalcanzables, se cambiaron de variable `device` (tiempo de ejecución) a `parameter` (tiempo de compilación), con el valor que tienen siempre en este proyecto:

- `mcuda_globals.cuf`: `integer(kind=i4), device :: natom, ngatom, nhe4, nhe3` → `nhe3` separado como `integer(kind=i4), parameter :: nhe3 = 0`.
- `hpsi_mod.cuf`: `logical, device :: libre` → `logical, parameter :: libre = .false.`.
- `msync_gpu.cuf`: quitadas las líneas que asignaban a `nhe3`/`libre` (ya no es legal, son `parameter`) y sus importaciones correspondientes.

Recompilado, verificado bit a bit correcto. **Confirmación de que el compilador SÍ se enteró del cambio**: aparecieron avisos nuevos, `NVFORTRAN-W-0435-Array declared with zero size` en `derananum_mod.cuf` (los arrays `d1wfhe3(nhe3)`/`d2wfhe3(nhe3)`, ahora de tamaño 0 de verdad, no solo en tiempo de ejecución) — prueba de que el compilador ya tenía la información necesaria para razonar sobre ello.

**Resultado con `ncu`**: `Registers Per Thread` sigue en **247, sin cambio**, exactamente igual que antes de este cambio.

**Revertido tras la prueba** (no aportaba nada, y sí tiene una contrapartida real: perder la posibilidad de cambiar `nhe3`/`libre` solo editando `in.mcv`, sin recompilar) — verificado de nuevo bit a bit correcto tras el revertido.

## Conclusión: no es código sobrante

Dos pruebas distintas, ambas verificadas correctas, ambas con resultado limpio: **247 registros, sin ningún cambio**. Ni siquiera con el compilador demostrablemente enterado de que ciertas ramas son inalcanzables (los avisos de array de tamaño cero lo confirman) se libera ni un registro. Esto descarta con bastante seguridad que el problema sea código muerto o sobrante — el presupuesto de registros probablemente refleja cálculo real y necesario en algún punto de la cadena (las tablas de `myexp`/`mypow`/`mysin`/`mycos`/`myacos`, o sencillamente la anchura de toda la física que hace falta mantener a la vez), no algo recortable con cambios superficiales.

## Ficheros de esta parte

- Auditoría completa: sin fichero nuevo, hecha directamente sobre `hibrido_instrumentado/` fichero a fichero.
- `He_dihydrogen.f`: cambio aplicado y mantenido (6 variables sin usar quitadas).
- `mcuda_globals.cuf`, `hpsi_mod.cuf`, `msync_gpu.cuf`: cambio de `nhe3`/`libre` a `parameter` probado y **revertido** — no queda rastro en el código, solo en este documento y en `Test-tiempo-ncu/resultado-params.ncu-rep`.

---

# Parte 7 — Refactorización por fases en `derananum`: primera prueba de las 3 estrategias propuestas

## La idea

De las 3 estrategias planteadas (refactorización por fases, recompute-vs-store, granularidad de hilo), se empezó por la primera, aplicada a `derananum_mod.cuf` — el sitio donde vive el problema localizado en la Parte 3 (`der_wavefhe4_mod.cuf:82-83`, 84.360 sectores excedentes con `Address Space=Global`).

`derananum` calcula la energía cinética de un walker combinando 4 "trozos" de la derivada de la función de onda (He4-He4, He3-He3, molécula-He4, molécula-eje), cada uno guardado en su propio array local (`d1wfhe4`, `d1wfhe3`, `d1wfm`, `d1wfx`). Antes del cambio, el código llamaba a las 4 subrutinas que rellenan esos arrays **seguidas** (líneas 160-163 en la versión previa), y solo después los combinaba en dos bucles separados (uno para átomos de He4, otro para átomos de He3). Como consecuencia, `d1wfhe4`/`d2wfhe4` y `d1wfhe3`/`d2wfhe3` estaban vivos **a la vez** durante toda la función, aunque nunca se usan juntos: el bucle de He4 (líneas 166-173) solo lee `d1wfhe4`, y el de He3 (líneas 175-183) solo lee `d1wfhe3`.

## El cambio aplicado

Se retrasó la llamada a `derwavefhe3` (que rellena `d1wfhe3`/`d2wfhe3`) hasta justo antes del bucle que la usa, después de haber terminado ya el bucle de He4 (que es lo único que necesita a `d1wfhe4`):

```fortran
call derwavefhe4(atom(1:nhe4), d1wfhe4, d2wfhe4)
call derwavefm(atom(1:ngatom), d1wfm, d2wfm)
call derwavefx(atom, sprop, d1wfx, d2wfx, d1zwfx, d2zwfx)

kin=0.0_r8
do iatom=1,nhe4
  ... ! bucle He4, sin cambios, usa d1wfhe4/d1wfm/d1wfx
enddo

! d1wfhe4/d2wfhe4 ya no hacen falta -- d1wfhe3 se calcula ahora, no antes
call derwavefhe3(atom, wfhe3, d1wfhe3, d2wfhe3)

do ihe3=1,nhe3
  ... ! bucle He3, sin cambios, usa d1wfhe3/d1wfm/d1wfx
enddo
```

Ninguna operación aritmética cambia de orden dentro de cada bucle — solo cambia **cuándo** se calcula `d1wfhe3`, no **cómo**. Por eso se esperaba (y se confirmó) resultado bit a bit idéntico.

## Verificación de corrección

Recompilado, ejecutado (`python3 run_test.py 5 50 1 1 5 fase_derananum_op5`) y comparado con `resultados/unused_vars_op5.log` (última base correcta conocida): `diff` solo mostró diferencias de timestamp y tiempo de CPU — resultado físico bit a bit idéntico.

## Resultado con `ncu`

Recompilado, perfilado (`resultado-fase-derananum.ncu-rep`, mismo comando que siempre: `--launch-skip 1 --launch-count 1 --set full`) y comparado línea a línea contra el estado inmediatamente anterior (`resultado-sinvars.ncu-rep`):

| Métrica | Antes del reordenamiento | Después del reordenamiento |
|---|---|---|
| Registers Per Thread | 247 | **247 — sin cambio** |
| Theoretical Occupancy | 16,67% | **16,67% — sin cambio** |
| Achieved Occupancy | 2,08% | **2,08% — sin cambio** |
| Excessive sectors totales del kernel | 471.466 (53% de 883.493) | **471.466 (53% de 883.493) — sin cambio** |
| `der_wavefhe4_mod.cuf:82` (`d1wf(iatom)%comp(:)=...`) | Global(6), 84.360 sectores excedentes | **Global(6), 84.360 — sin cambio** |
| `der_wavefhe4_mod.cuf:83` (`d1wf(jatom)%comp(:)=...`) | Global(6), 84.360 sectores excedentes | **Global(6), 84.360 — sin cambio** |

**Ningún cambio, en ninguna métrica.** Cuarto/quinto resultado negativo consecutivo (junto con fusión, `maxregcount`, y las 2 pruebas de variables sobrantes de la Parte 6).

## Por qué no ha funcionado (hipótesis, no probada aún)

`d1wfhe4`/`d1wfhe3` son arrays locales de **tamaño variable en tiempo de ejecución** (`nhe4`, `nhe3` son variables `device`, no `parameter` — Parte 6 lo confirmó de nuevo). Un array así, indexado con una variable de bucle (`iatom`, no una constante de compilación), no se puede guardar en registros pase lo que pase: el compilador necesita reservarle espacio en memoria "local" (memoria del hilo, pero físicamente en la misma DRAM que la memoria global) desde el principio de la función, independientemente de cuándo empiece o termine de usarse en el código fuente. Es decir: **acortar el rango de vida en el código fuente no acorta el rango de vida real que ve el compilador**, porque el array nunca iba a vivir en un registro de todas formas — el compilador ya le reserva su hueco de memoria local para toda la función, se use antes o después. Esto encaja con el mismo hallazgo de la Parte 4 (fusionar tampoco cambió nada) y la Parte 5 (bajar los registros disponibles tampoco): el `Global` de estas líneas parece ser una propiedad estructural del array (tamaño no constante en compilación), no de cómo está organizado el código alrededor.

## Decisión: se mantiene el cambio

A diferencia de la prueba de `nhe3`/`libre` como `parameter` (Parte 6, revertida por tener una contrapartida real), este reordenamiento no tiene ningún coste: es la misma aritmética, mismo resultado bit exacto, verificado. Se deja aplicado como limpieza válida (evita calcular `d1wfhe3`/`d2wfhe3` antes de tiempo), aunque no aporte la mejora de memoria que se buscaba.

## Ficheros de esta parte

- `hibrido_instrumentado/derananum_mod.cuf`: cambio aplicado y mantenido (líneas ~154-186, ver comentario `Refactorizacion por fases` en el propio fichero).
- `Test-tiempo-ncu/resultado-fase-derananum.ncu-rep`: informe de `ncu` de esta prueba.
- `resultados/fase_derananum_op5.log` / `fase_derananum_op5__tiempos_opcion5.dat`: verificación de corrección.

---

# Parte 8 — "Recompute vs. store" en `derwavefhe4`: la memoria mejora, el tiempo empeora

## La idea

Segunda de las 3 estrategias propuestas. `der_wavefhe4_mod.cuf:82-83` (dentro de `derwavefhe4`) seguía siendo, tras la Parte 7, el hotspot #1 de accesos no coalescidos (84.360+84.360 sectores excedentes, `Address Space=Global`) — porque `d1wf`/`d2wf` son arrays de tamaño `nhe4` (solo conocido en tiempo de ejecución), acumulados con lectura-modificación-escritura repetida durante el bucle de parejas `iatom<jatom` (O(n²/2) parejas). Un array así nunca puede vivir en un registro (Parte 7 lo estableció), así que cada suma va a memoria local.

La idea: en vez de recorrer cada pareja una vez y escribir el resultado parcial en el array dos veces (una por cada átomo de la pareja), recorrer **por cada átomo, todas las demás parejas** (el doble de evaluaciones, O(n²)) acumulando en una variable escalar que vive solo mientras se procesa ese átomo — el array de salida se escribe una única vez por átomo, al final, en vez de `nhe4²/2` veces repartidas por todo el bucle.

Comprobado a mano que el orden de sumas en punto flotante para un átomo fijo coincide exactamente con el original (mismo orden creciente del otro átomo, saltando el propio) — se esperaba resultado bit a bit idéntico.

## Prueba aislada primero

`prueba_recompute_derwavefhe4/test_recompute.cuf`: física de juguete (mismo patrón de bucle, con `**` en vez de `mypow` para no depender del resto del árbol), comparando la versión original (array acumulador) contra la reformulada (escalar). **Bit a bit idéntico, verificado en CPU y GPU** (14 muestras + comprobación completa de los 50 walkers × 22 átomos).

Perfilado con `ncu` (`resultado_recompute.ncu-rep`):

| Métrica | Original (array, O(n²/2)) | Recalculada (escalar, O(n²)) |
|---|---|---|
| Registros/hilo | 59 | 58 — prácticamente igual |
| Sectores excedentes | 172.050 | **105.820 — 38% menos** |
| Duración del kernel | 1,25 ms | **2,04 ms — 63% más lento** |

Primer aviso: la memoria mejora, pero el kernel se vuelve más lento — duplicar la potencia `rij**(phe4(2)+1)` cuesta más de lo que ahorra la memoria, incluso usando el operador `**` (barato). En el código real esa potencia es `mypow`, la función a tablas identificada en la Parte 2 como la más cara de toda la cadena — previsiblemente peor, no mejor.

## Aplicado al código real de todas formas, para confirmar con datos reales

Aplicado a `der_wavefhe4_mod.cuf` (sustituyendo el bucle de parejas por el bucle por átomo con acumulador escalar, usando `mypow` real). Recompilado, verificado bit a bit correcto (`python3 run_test.py 5 50 1 1 5 recompute_derwavefhe4_op5`, `diff` contra `unused_vars_op5.log` — solo timestamps/tiempo de CPU). Perfilado con `ncu` (`resultado-recompute-derwavefhe4.ncu-rep`):

| Métrica | Antes (Parte 7) | Después (recompute) |
|---|---|---|
| Registros/hilo | 247 | 247 — sin cambio |
| Sectores excedentes totales del kernel | 471.466 (53% de 883.493) | **250.553 (41% de 613.146) — bajan de verdad** |
| `der_wavefhe4_mod.cuf:82-83` (hotspot original) | 84.360+84.360 sectores | **ya no aparece en el top — el array desapareció** |
| Duración del kernel | 25,25 ms | **27,15 ms — ~7,5% más lento** |

Exactamente el mismo patrón que la prueba aislada, a escala real: el array que causaba el problema original **sí desaparece** (confirmado, ya no está entre las líneas con más sectores excedentes), pero el nuevo top pasa a ser `myexp`/`mypow` (`glibc_exp_mod.cuf:83,145`, `glibc_pow_mod.cuf:178,99-101` — sus propias tablas internas), porque ahora se les llama el doble de veces. El resultado neto: memoria mejor, tiempo peor. Energía final de la simulación idéntica en ambos casos (`-618.9794362447`), confirmando que la física no cambió.

## Decisión: revertido

El objetivo real es que la simulación completa vaya más rápido, no solo que baje un contador de sectores — y aquí el kernel tarda más, no menos. Revertido a la versión original (verificado de nuevo bit a bit correcto tras el revertido). Se mantiene documentado como el primer resultado real de la Estrategia 2: confirma la advertencia que la propia estrategia llevaba dentro ("la ALU suele ser más barata que la memoria... salvo que lo que recalcules sea caro") — aquí `mypow` es justo ese caso: recalcularlo no sale a cuenta.

## Ficheros de esta parte

- `prueba_recompute_derwavefhe4/test_recompute.cuf` y `resultado_recompute.ncu-rep`: prueba aislada (artefacto, se queda en el repositorio).
- `hibrido_instrumentado/der_wavefhe4_mod.cuf`: cambio probado y **revertido** — no queda rastro en el código.
- `Test-tiempo-ncu/resultado-recompute-derwavefhe4.ncu-rep`: informe de `ncu` de la prueba en código real.
- `resultados/recompute_derwavefhe4_op5.log`, `resultados/revert_recompute_op5.log`: verificación de corrección (aplicado y tras revertir).

---

# Parte 9 — Estrategia 1 en `He_dihydrogen.f`: descartada antes de tocar el fichero real

## Por qué se vuelve a mirar la Estrategia 1

`He_dihydrogen.f` es distinto a `derananum` (Parte 7): sus dimensiones (`nHH=1`, `ndih=2`, `natms=30`) son `PARAMETER` — constantes de compilación, confirmado en `param_atoms_bh.h:10,39` — no variables `device` como `nhe4`/`nhe3`. Sus arrays pequeños (`r_RGTH(3)`, `dVdx(3)`, `rvec(3)`, etc.) y sobre todo sus ~30 escalares (`atheta`, `btheta`, `Ex0`, `dExdx`...`dEzdz`, etc.) sí son candidatos genuinos para que el compilador los mantenga en registros. La subrutina tiene 3 fases claramente separadas (cálculo de `R2`/`G`, término `ENERGY2`, término `ENERGY3`) con casi todas las variables declaradas juntas al principio, usadas cada una solo dentro de UNA fase — el mismo patrón que motivó la Estrategia 1.

## Prueba aislada primero (antes de tocar 600 líneas de física real)

Dado el historial de esta sesión (Parte 4, 5, 7 y 8 con efecto cero o negativo), antes de reescribir un fichero grande y denso se comprobó la premisa básica en aislado: ¿reduce registros envolver cada fase en un `BLOCK` de Fortran con sus propias declaraciones, frente a declarar todo junto al principio de la subrutina?

`prueba_block_fases/test_block.cuf`: dos subrutinas con la misma aritmética en 2 fases independientes (~15 escalares cada una, sin ningún solapamiento de datos entre fases — el caso más favorable posible para esta técnica). `calculo_top`: todo declarado al principio (como `He_dihydrogen.f` hoy). `calculo_block`: cada fase en su propio `BLOCK...END BLOCK`, con declaraciones locales a cada bloque.

Verificado bit a bit idéntico. Perfilado con `ncu` (`resultado_block.ncu-rep`):

| Métrica | `calculo_top` (todo declarado arriba) | `calculo_block` (cada fase en su `BLOCK`) |
|---|---|---|
| Registros/hilo | 50 | **50 — exactamente igual** |

## Por qué: el compilador ya hace este trabajo solo

Ni siquiera en el caso más limpio posible (escalares puros, cero solapamiento de datos entre fases) el `BLOCK` cambia nada. La razón, distinta de la de la Parte 7 (que era sobre arrays de tamaño no constante): `nvfortran` ya calcula, analizando el flujo real de datos del programa, cuándo termina la vida de cada variable — el **ámbito de declaración en el código fuente no es lo mismo que el rango de vida real que ve el asignador de registros**. Envolver una fase en `BLOCK` es una pista redundante: el compilador ya sabía, sin que se lo dijéramos, que las variables de la fase A mueren antes de que empiecen a usarse las de la fase B.

Esto generaliza el hallazgo de la Parte 7 (que se limitaba a arrays de tamaño variable): la "Refactorización por Fases", tal como está descrita, no parece tener ningún margen con este compilador — ni para arrays de tamaño no constante (no pueden ir a registros pase lo que pase) ni para escalares puros (el compilador ya optimiza su rango de vida solo).

## Decisión: no se toca `He_dihydrogen.f`

Con este resultado, reescribir las 600 líneas de `He_dihydrogen.f` en fases con `BLOCK` sería mucho riesgo mecánico (código denso, con muchas variables reutilizadas con el mismo nombre entre fases — `rnorm`, `theta`, `btheta`, `fi`, etc. — fácil de introducir un error al separar) para un beneficio que esta prueba ya predice en cero. No se aplica. `He_dihydrogen.f` queda sin tocar (aparte de la limpieza de variables sin usar de la Parte 6, que sigue en pie).

## Ficheros de esta parte

- `prueba_block_fases/test_block.cuf` y `resultado_block.ncu-rep`: prueba aislada (artefacto, se queda en el repositorio).
- `hibrido_instrumentado/He_dihydrogen.f`: sin cambios en esta parte.

---

# Parte 10 — Estrategia 3 (granularidad de hilo, "equipo" con memoria compartida): prueba aislada, negativa

## La idea, tal como se propuso

En vez de que 1 hilo calcule las 3 piezas independientes de un walker (patrón de `derwavefhe4`/`derwavefm`/`derwavefx`, cada una un bucle de parejas que produce un array `d1/d2`) y luego las combine él solo, repartir un walker entre un **equipo de 3 hilos**: cada hilo calcula 1 pieza y la deja en **memoria compartida** (el "casillero" común al bloque); una **barrera** (`syncthreads()`) espera a que las 3 terminen; un hilo del equipo lee las 3 piezas y hace la combinación final.

## Prueba aislada

`prueba_equipo_hilos/test_equipo.cuf`: física de juguete con el mismo patrón de bucle de parejas que `derwavefhe4` (3 "piezas" parametrizadas por coeficientes distintos, sin depender de `mypow`/`myexp` reales — no hace falta para probar el reparto entre hilos). `k_solo`: 1 hilo = 1 walker, calcula las 3 piezas en arrays locales y combina (equivalente a hoy). `k_equipo`: 3 hilos por walker (30 hilos/bloque = 10 walkers/bloque), cada uno calcula 1 pieza en memoria compartida, `syncthreads()`, el hilo de rol 0 combina.

Verificado bit a bit idéntico (300 walkers, comparación completa de `dwf` y `kin`). Perfilado con `ncu` (`resultado_equipo.ncu-rep`):

| Métrica | `_solo` | `_equipo` |
|---|---|---|
| Registros/hilo | 77 | **75 — casi igual** |
| Memoria compartida/bloque | 0 | 15,36 KB |
| Ocupación teórica | 50% | **12,5% — ahora limita la memoria compartida** |
| Ocupación real | 2,08% | 2,65% |
| Duración del kernel | 0,98 ms | **1,08 ms — ~10% más lento** |

## Por qué los registros casi no bajan (conecta con la Parte 9)

El hilo de rol 0 no solo calcula su propia pieza — tras la barrera, también lee las otras 2 y combina, así que su camino de ejecución completo sigue necesitando casi todo el espacio de antes. Como todos los hilos de un kernel CUDA ejecutan el mismo código compilado (no hay una versión distinta por rol), el compilador reserva registros para cubrir el camino más exigente de cualquier hilo, que sigue siendo el de quien combina.

Además, la Parte 9 ya había establecido que el compilador **reutiliza registros solo, dentro de un mismo hilo**, entre fases secuenciales sin solapamiento de datos (el `BLOCK` no aportó nada porque el compilador ya lo hacía). Eso significa que el hilo `_solo` **ya era casi tan eficiente en registros como el equipo repartido**, porque nunca mantenía las 3 piezas vivas a la vez — las calculaba una detrás de otra y el compilador reciclaba el sitio automáticamente. Repartir en varios hilos no tenía apenas margen real que ganar, por el mismo motivo de fondo identificado en la Parte 9.

## El coste (memoria compartida + barrera) sí aparece, como se anticipó

La ocupación teórica cae de 50% a 12,5% (la memoria compartida pasa a ser el nuevo límite, no los registros), y el kernel completo sale ~10% más lento — el ahorro de registros (2 de 77) es demasiado pequeño para compensar el coste de la barrera y de que 2 de cada 3 hilos se queden inactivos durante la combinación final.

## Decisión: no se lleva al código real

Con un resultado tan claramente negativo en la prueba aislada (que ya venía con la ventaja de una física de juguete, sin la complejidad añadida de `mypow`/`myexp` reales), y una explicación de fondo coherente con la Parte 9, no se justifica acometer el cambio arquitectónico real (el más invasivo de los tres, tocando la indexación de hilos, el lanzamiento del kernel y la estructura de `derananum`/`hpsi`) para un beneficio que la prueba ya predice nulo o negativo.

## Conclusión de las 3 estrategias

Ninguna de las 3 estrategias propuestas logró reducir de forma útil los 247 registros/hilo ni mejorar el tiempo real de `k_dmc2`:
- **Estrategia 1** (fases/`BLOCK`): sin efecto, ni en arrays de tamaño variable (Parte 7) ni en escalares puros (Parte 9) — el compilador ya hace ese trabajo de reutilización de registros solo.
- **Estrategia 2** (recompute vs. store): sí reduce memoria, pero empeora el tiempo total porque la única física de este proyecto (basada en factores de Jastrow) siempre pasa por `mypow`/`myexp`, caros de duplicar (Parte 8).
- **Estrategia 3** (granularidad de hilo): mismo problema de fondo que la Estrategia 1 (el compilador ya optimizaba el reciclaje de registros dentro de un hilo) más el coste añadido de sincronización y memoria compartida (Parte 10).

El techo de 247 registros/hilo parece, con la evidencia acumulada en esta sesión, una propiedad bastante inherente a la anchura real de la física portada, no una ineficiencia de código corregible con reorganizaciones locales.

## Ficheros de esta parte

- `prueba_equipo_hilos/test_equipo.cuf` y `resultado_equipo.ncu-rep`: prueba aislada (artefacto, se queda en el repositorio).

---

# Parte 11 — Equipo agrupado por warps completos: primer resultado positivo real

## Por qué la Parte 10 salía peor: divergencia de warp

Antes de seguir, se comprobó con métricas reales de `ncu` (no a ojo) por qué `_equipo` (Parte 10) salía más lento pese a "repartir el trabajo en 3 hilos". Una GPU no ejecuta hilos sueltos: los agrupa en **warps de 32**, y todo el warp ejecuta la misma instrucción a la vez (como un pelotón marcando el paso). En `_equipo`, los 3 roles estaban intercalados (hilo 0=rol A, hilo 1=rol B, hilo 2=rol C, hilo 3=rol A...), así que un mismo warp mezclaba los 3 roles — cuando el código pregunta "¿eres rol 0?", solo esos hilos trabajan mientras los demás esperan parados, y así con cada rol. Confirmado con la métrica real: **`_equipo` solo tenía 10,01 hilos activos de media por warp (de 32)** — dos tercios del warp parado en todo momento, frente a los 30,00 de `_solo`. Esto es "divergencia de warp", y explica el resultado negativo de la Parte 10 mejor que cualquier razonamiento sobre registros.

## La idea: agrupar por rol en vez de intercalar

En vez de mezclar los 3 roles dentro del mismo warp, se reorganiza el bloque en **3 tramos de warp completo**: los primeros 32 hilos son TODOS rol 0 (pieza A, de 32 walkers distintos), los siguientes 32 TODOS rol 1 (pieza B), los siguientes 32 TODOS rol 2 (pieza C). `blockDim=96` = exactamente 3 warps, cada uno ejecutando un único camino de código, sin ninguna rama que lo divida por dentro.

`prueba_equipo_hilos/test_equipo.cuf`, kernel nuevo `k_equipo_warp`, misma física de juguete y misma subrutina `combina` que en la Parte 10. Verificado bit a bit idéntico frente a `_solo` y `_equipo` (300 walkers). Perfilado con `ncu` (`resultado_equipo_warp.ncu-rep`):

| Métrica | `_solo` | `_equipo` (Parte 10) | `_equipo_warp` |
|---|---|---|---|
| Hilos activos/warp | 30,00 | 10,01 | **30,00 — divergencia eliminada** |
| Ramas divergentes/warp | 0 | 0,94 | **0,03** |
| Registros/hilo | 77 | 75 | 79 (no bajó, ni falta que hizo) |
| Ocupación real | 2,08% | 2,65% | **6,17% — casi el triple que `_solo`** |
| Duración del kernel | 981 µs | 1.070 µs | **447 µs — más del doble de rápido que `_solo`** |

## La confirmación importante: no es cuestión de registros

Los registros no bajaron (79, incluso un poco más que `_solo`) — la mejora **no viene de "menos registros por hilo"**, viene de que ahora los 3 warps del bloque avanzan de verdad en paralelo (más planificadores de warp de la SM ocupados a la vez, ocupación real casi triplicada), en vez de uno solo fingiendo repartir trabajo mientras en realidad lo serializaba por dentro.

## Antes de aplicarlo al código real: los tamaños no son todos iguales

En el código real, las piezas independientes de `derananum` NO tienen el mismo tamaño: `derwavefhe4` usa `nhe4` (=20 en `in.mcv` de este proyecto), `derwavefm` usa `ngatom` (=20), `derwavefx` usa `natom` (=21, confirmado en `mentradatos.f90:352-365`: `ngatom=nhe4+nhe3`, `natom=ngatom+1` con impureza). Además, con `nhe3=0` (siempre en este proyecto, Parte 6), `derwavefm` y `derwavefhe3` son estructuralmente triviales en la práctica — sus bucles internos con `nhe3` no ejecutan ninguna iteración real, así que casi no cuesta nada calcularlos, aunque el compilador no pueda demostrarlo. Solo `derwavefhe4` y `derwavefx` hacen trabajo O(n²) real y caro (con `mypow`).

## Ficheros de esta parte

- `prueba_equipo_hilos/test_equipo.cuf` (ampliado con `k_equipo_warp`) y `resultado_equipo_warp.ncu-rep`: artefactos, se quedan en el repositorio.

---

# Parte 12 — Equipo selectivo (2 hilos, no 3+) a tamaño real: resultado positivo confirmado

## La idea, refinada

En vez de dar a las 3 piezas (`derwavefhe4`, `derwavefm`, `derwavefx`) su propio rol (lo que dispararía la memoria compartida, como se advirtió al cerrar la Parte 11), usar un **equipo de solo 2 hilos**: uno calcula la pieza cara "A" (equivalente a `derwavefhe4`, tamaño `nhe4=20`) y la deja en memoria compartida — la única que hace falta compartir. El otro calcula, **en local, sin memoria compartida**, la pieza cara "B" (equivalente a `derwavefx`, tamaño `natom=21`) y además la pieza barata "M" (equivalente a `derwavefm`, casi gratis con `nhe3=0`, Parte 6/11) — y es también el que combina, leyendo "A" del casillero tras la barrera.

## Primer intento: un error propio, encontrado y corregido antes de sacar conclusiones

La primera versión de esta prueba dimensionó los arrays locales de los kernels (`d1A(natom_real)`, etc.) usando `natom_real`, declarado como `parameter` (constante de compilación) por comodidad. Eso le da al compilador información que el código real **nunca tiene** — `nhe4`/`ngatom`/`natom` son variables `device`, conocidas solo en tiempo de ejecución. Con ese error, la prueba daba una caída de registros enorme y engañosa (230→73) que no se podía atribuir al reparto en equipo, sino a que el compilador podía tratar arrays de tamaño "21" literal como candidatos a vivir en registros — algo que nunca podrá hacer con el código real.

**Corregido** pasando el tamaño como argumento `value` en cada lanzamiento (`natomv`, no `natom_real`) para los arrays locales de `k_solo_real`/`k_equipo_sel` — así, desde el punto de vista del propio kernel compilado, el tamaño es un desconocido en tiempo de compilación, igual que en el código real.

## Resultado, ya corregido

`prueba_equipo_hilos/test_equipo.cuf`, kernels `k_solo_real` (equivalente a hoy, 3 piezas secuenciales en 1 hilo) y `k_equipo_sel` (2 hilos, 1 casillero compartido), con tamaños reales del proyecto (`natom=21`, confirmado en `mentradatos.f90:352-365`). Verificado bit a bit idéntico (300 walkers). Perfilado con `ncu` (`resultado_equipo_sel_fix.ncu-rep`):

| Métrica | `_solo_real` | `_equipo_sel` (2 hilos) |
|---|---|---|
| Registros/hilo | 79 | 72 — apenas baja |
| Memoria compartida/bloque | 0 | 21,5 KB (lejos del límite de 48 KB) |
| Ocupación teórica | 50% | 16,67% |
| Ocupación real | 2,08% | **4,13% — el doble** |
| Ramas divergentes/warp | 0 | 0,02 — prácticamente cero |
| **Duración del kernel** | 2,04 ms | **1,20 ms — 1,7x más rápido** |

## Confirmación del mecanismo

Los registros apenas bajan (79→72) — consistente con la Parte 9/10: la compartición entre hilos no libera registros de forma relevante cuando los arrays ya eran de tamaño variable (no vivían en registros de todas formas). La mejora real viene, otra vez, de **eliminar la divergencia de warp**: con solo 2 roles agrupados en warps completos, cada warp ejecuta un único camino sin ramas que lo dividan, y el bloque consigue el doble de ocupación real pese a que el techo teórico sea más bajo que el de `_solo`.

## Primer resultado positivo, verificado dos veces (aislado con física de juguete en la Parte 11, y ahora a tamaño real) — candidato serio para llevar al código real, con memoria compartida bajo control (21,5 KB, no 36-49 KB como con 3 roles completos).

## Ficheros de esta parte

- `prueba_equipo_hilos/test_equipo.cuf` (ampliado con `pieza_barata`, `k_equipo_sel`, `k_solo_real`) y `resultado_equipo_sel_fix.ncu-rep`: artefactos, se quedan en el repositorio.
- `resultado_equipo_sel.ncu-rep` (la corrida CON el error de `parameter`): se conserva también, documentado explícitamente como la versión incorrecta, para dejar rastro del error y su corrección.

## Por qué la ocupación teórica baja de 50% a 16,67% (datos exactos de `ncu`)

La ocupación teórica es siempre el límite **más restrictivo** entre 4 posibles (hardware de la SM, registros, memoria compartida, warps totales). Con los límites reales que reporta `ncu` para estos dos kernels concretos:

| Límite (bloques que caben por SM) | `_solo_real` | `_equipo_sel` |
|---|---|---|
| Por hardware de la SM | 24 | 24 |
| Por registros | 24 | 14 |
| Por memoria compartida | 32 (sobra sitio, 0 KB usados) | **4 — aquí aprieta** |
| Por warps totales | 48 | 24 |
| **Real (el mínimo de los 4)** | **24** | **4** |

`_solo_real`: cada bloque es 1 warp (32 hilos) → 24 bloques × 1 warp = 24 de 48 warps posibles → **50%**.
`_equipo_sel`: cada bloque son 2 warps (64 hilos, un walker ahora ocupa 2 hilos), y pide 21,5 KB de memoria compartida → solo caben 4 bloques/SM (la memoria compartida es ahora el cuello de botella, no los registros) → 4 bloques × 2 warps = 8 de 48 warps posibles → **16,67%**.

Aun con ese techo más bajo, la ocupación *real* salió el doble (4,13% vs 2,08%) y el kernel fue más rápido — eliminar la divergencia pesó más que bajar el techo teórico.

---

# Parte 13 — Plan (sin implementar todavía): llevar el equipo selectivo al código real

## Objetivo

Aplicar el patrón validado en la Parte 12 (equipo de 2 hilos por walker, agrupados en warps completos, 1 solo casillero de memoria compartida) a la cadena real `dmc2` → `hpsi` → `derananum`, donde viven de verdad `derwavefhe4`/`derwavefm`/`derwavefx`.

## Diseño concreto

- **Rol 0**: calcula `derwavefhe4` (tamaño `nhe4=20`) y lo deja en memoria compartida.
- **Rol 1**: calcula `derwavefx` (tamaño `natom=21`) y `derwavefm` (tamaño `ngatom=20`, casi gratis con `nhe3=0`) en local — sin memoria compartida para estas dos. Tras la barrera, lee el resultado de rol 0 del casillero y hace la combinación de `derananum` (`dwf`, `kin`).
- Los 2 roles de un mismo walker deben caer en **warps completos separados** (no intercalados) — igual que la Parte 11/12, para no reintroducir la divergencia que hundió la Parte 10. Con bloques de, por ejemplo, 64 hilos (32 walkers × 2 roles, 2 warps por bloque), el rol 0 ocupa el primer tramo de 32 hilos y el rol 1 el segundo.

## El obstáculo real, no visto en la prueba aislada: `dmc2` hace mucho más que `derananum`

`dmc2.cuf` (209 líneas) llama a `hpsi` (que a su vez llama a `derananum`) **dos veces** por walker (líneas 82 y 103 del cuerpo de `dmc2` -- una para la configuración actual, otra para el paso propuesto de Metropolis), rodeadas de sorteos aleatorios (`gauss3_gpu`, `rand1_gpu`) y rotaciones (`rota`) que **no tienen nada que ver con `derananum`** y no se benefician de este reparto.

Si se lanza `k_dmc2` con 2 hilos por walker, el hilo de rol 0 termina su trabajo (la pieza `derwavefhe4`) muy pronto — y se queda **inactivo el resto de la ejecución de `dmc2`** (todos los sorteos aleatorios, las rotaciones, la segunda llamada a `hpsi`, la lógica de aceptación/pesos). Eso significa pagar el coste de duplicar hilos y memoria compartida **para todo el kernel**, a cambio de acelerar solo el trozo de `derananum` — si ese trozo es una fracción pequeña del tiempo total de `dmc2`, la cuenta puede salir negativa (mismo principio que la Parte 8: una mejora real en una pieza no garantiza una mejora neta del conjunto).

## Paso 0 (obligatorio antes de tocar nada): medir qué fracción del tiempo de `dmc2` es de verdad `derananum`

Con la misma metodología ya usada en la Parte 1-2 (`ncu --page source --print-source cuda,sass`, sumando por función a través de las ~30 funciones que se inlinean dentro de `k_dmc2`), medir qué porcentaje del tiempo/instrucciones totales de `k_dmc2` corresponde a `derwavefhe4`+`derwavefx` frente al resto (`gauss3_gpu`, `rand1_gpu`, `rota`, el resto de `hpsi`/`vpot`/`potenbh`/`He_dihydrogen`). Si esa fracción es pequeña, el reparto en equipo dejaría demasiados hilos inactivos demasiado tiempo para compensar — habría que replantear el alcance (¿todo `hpsi`, no solo `derananum`? ¿envolver las 2 llamadas a `hpsi` completas en el reparto, no solo la combinación final?).

## Pasos siguientes (una vez medido el paso 0, y si la fracción lo justifica)

1. Prototipo aislado con la fracción real medida (misma disciplina de toda la sesión: probar primero en `prueba_equipo_hilos/`, no directamente en `hibrido_instrumentado/`).
2. Adaptar `hpsi_mod.cuf`/`derananum_mod.cuf` para que `derananum` acepte ejecutarse en modo "equipo" (parámetro de rol + puntero a memoria compartida), sin romper la firma que usan otros kernels ya validados (`k_hpsi`, `k_derananum` sueltos, si se siguen usando en pruebas por separado).
3. Cambiar el lanzamiento de `k_dmc2` en `msteps.f90` (`pasodmc_gpu`) a 2 hilos/walker, con la agrupación en warps completos.
4. Envolver TODO lo que no sea rol 1 tras la barrera en `if (rol==1) then ... endif` — el hilo de rol 0 debe quedar inactivo de forma explícita el resto de `dmc2`, sin ejecutar por error la segunda llamada a `hpsi`, los sorteos aleatorios ni la lógica de aceptación (que deben quedar reservados al hilo que de verdad lleva el estado completo del walker).
5. Verificación bit a bit de la batería completa de `dmc2.md` (no solo un caso suelto) — es el cambio más invasivo hecho en esta sesión, toca la firma de lanzamiento del kernel de producción.
6. `ncu` real sobre `k_dmc2` completo, comparando registros/ocupación/divergencia/duración contra la línea base actual, con el mismo rigor que el resto del documento.

## Riesgos a tener presentes

- Generalidad: si en el futuro se usa `nhe3>0` (mezcla He4-He3 real, no solo H2), `derwavefm` deja de ser casi gratis y el reparto de roles habría que revisarlo (hoy se apoya en que `nhe3=0` es un hecho permanente de esta tesis, Parte 6).
- Es un cambio de arquitectura del kernel de producción, no una función aislada — el coste de verificación y el riesgo de introducir una regresión son mayores que en cualquier cambio anterior de esta sesión.

## Ficheros de esta parte

- Ninguno todavía — es un plan, no una implementación. Referencia: `dmc2.cuf:60-160` (cuerpo de `dmc2`, las 2 llamadas a `hpsi`), `mentradatos.f90:352-365` (tamaños reales), `msteps.f90` (`pasodmc_gpu`, donde se lanza `k_dmc2` hoy con 1 hilo/walker).

## Paso 0 ejecutado: medición real del peso de la pieza

Con la misma metodología de la Parte 1-2 (`ncu --page source --print-source cuda,sass` en formato CSV, sumando por función a través de las ~30 que se inlinean en `k_dmc2`, usando `resultado-fase-derananum.ncu-rep` — la corrida real más reciente sin cambios de hilos), la fracción de tiempo/muestras de `k_dmc2` que corresponde a la pieza que se planeaba repartir:

| Función | % del tiempo total de `k_dmc2` |
|---|---|
| `der_wavefhe4_derwavefhe4_` (Rol 0 propuesto) | 5,70% |
| `der_wavefx_derwavefx_` + `d_uhex4_duhe4x_` + `d_uhex4_uhe4x_` + Legendre (Rol 1 propuesto) | 9,98% |
| `mderananum_derananum_` (combinación propia) | 0,53% |
| **Total de la pieza a repartir** | **16,21%** |

El resto (`mypow` 26,82%, `myexp` 11,87%, `V_hehe`/`Vp_hehe` 12,55%, `He_dihydrogen` 7,67%, `sincos` 8,93%, sorteos aleatorios, rotaciones, la segunda llamada a `hpsi`...) queda fuera del reparto propuesto — pertenece a la rama `vpot` (energía potencial) o son funciones matemáticas compartidas por ambas ramas.

**Con la ley de Amdahl**, aplicando la mejora de 1,7x medida en la Parte 12 (isolado) solo a ese 16,21%:

```
speedup_total = 1 / ( (1-0,1621) + 0,1621/1,7 ) ≈ 1,072x
```

**Techo realista: ~7% más rápido en `k_dmc2` completo** — muy por debajo del 1,7-2,2x visto en la prueba aislada, porque esa prueba medía solo la pieza repartida, no el kernel completo. Y ese 7% es un techo *optimista*: no incluye el coste real de dejar el hilo de rol 0 inactivo durante el 84% restante del kernel (el resto de sorteos aleatorios, rotaciones, la segunda llamada a `hpsi`, toda la rama `vpot`), que podría recortarlo más.

## Decisión: no se implementa

Ante un techo de ~7% y el riesgo del cambio más invasivo de toda la sesión (reescribir la firma de lanzamiento del kernel de producción `k_dmc2`, verificación bit a bit de toda la batería `dmc2.md`, riesgo real de regresión), se decide **no implementarlo** — la Parte 13 queda como plan de referencia documentado, con el Paso 0 ya medido, por si en el futuro cambian las condiciones (por ejemplo, si se decide ampliar el reparto también a la rama `vpot`, que cubriría una fracción mucho mayor del tiempo total, pero requeriría diseñar y probar esa parte desde cero antes de tocar el código real).

Con esto se cierra, por ahora, la investigación de rendimiento de `k_dmc2` iniciada en la Parte 1.
