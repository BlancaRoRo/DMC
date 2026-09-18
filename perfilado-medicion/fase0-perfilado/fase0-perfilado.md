# Fase 0 — Perfilado del pipeline actual

Objetivo: saber dónde se va el tiempo HOY en el pipeline de 7 fases + 2 fork-join (`dmc2_pipeline.cuf`), con datos reales — todo el perfilado anterior (`tiempo-ncu-resultado.md`, Partes 1-14) es de la versión de un solo kernel `k_dmc2`, previa al pipeline actual.

## Condiciones de la prueba

- Binario: `qmccluster_pipeline` (`v2-cuda-integracion/hibrido_instrumentado/`), `opcion=7`.
- Escala: 1.500 walkers — dentro del rango donde `test-walker.md` mostró que la aceleración GPU/CPU se aplana (~1,75x-1,78x entre 2.000-3.000).
- `conf.20.00.HH` fresco, misma semilla `0000000000000011` de siempre.

## 1. `nsys`: reparto de tiempo por kernel

`nsys profile --cuda-graph-trace=node` (imprescindible el flag — sin él los kernels del grafo no aparecen), 3 bloques de cálculo × 20 pasos = 64 pasos DMC en total (equilibrio + cálculo).

| Kernel | % tiempo GPU | Instancias | Tiempo medio/llamada |
|---|---|---|---|
| **`k_derananum_t`** | **73,8%** | 128 | 21,1 ms |
| **`k_vpot_t`** | **25,5%** | 128 | 7,3 ms |
| `k_fase_a` | 0,6% | 64 | 0,37 ms |
| `k_fase_d` | 0,03% | 64 | 16 µs |
| `k_fase_g`/`k_fase_f`/`k_fase_c` | <0,01% cada uno | 64 c/u | 2 µs c/u |
| `k_split_seeds` | ~0% (una sola vez) | 1 | 99 µs |

**`derananum` + `vpot` = 99,3% del tiempo de GPU.** El resto de fases (difusión, tests de aceptación, sorteo de ramificación) son irrelevantes en comparación — confirma con datos reales lo que el análisis de Amdahl anterior (basado en mediciones pre-pipeline) ya apuntaba, pero ahora con el pipeline real. **Cualquier optimización que no toque `derananum`/`vpot` tiene un techo de mejora total `<1%`.**

## 2. `ncu`: por qué son tan caros — no es la fórmula, es la ocupación

`ncu --set full` sobre `k_derananum_t`/`k_vpot_t` (1.500 walkers, `nmax=2×1500=3.000`):

| Métrica | `k_derananum_t` | `k_vpot_t` |
|---|---|---|
| Duración (1 llamada) | 37,9 ms | 9,1 ms |
| Registros/hilo | **144** | **247** |
| Configuración de lanzamiento | 94 bloques × 32 hilos | 94 bloques × 32 hilos |
| Waves por SM | **0,33** | **0,49** |
| Warps activos (% del pico) | **4,8%** | **4,8%** |
| Ocupación teórica | 25,0% (limitada por registros) | — |
| Ocupación conseguida | **4,8%** | — |
| Compute throughput | 5,8% | — |
| Memory throughput | 6,7% | — |

**Diagnóstico, no una suposición**: el `ncu` lo dice explícitamente —

- *"This kernel's theoretical occupancy (25.0%) is limited by the number of required registers"* — con 144-247 registros/hilo, cada bloque consume tanto registro por SM que apenas caben unos pocos bloques a la vez.
- *"This kernel grid is too small to fill the available resources on this device, resulting in only 0.3 full waves across all SMs"* — con solo 94 bloques de 32 hilos (3.008 hilos en total) y esta ocupación, la GPU está mayormente parada.
- *"each warp spends 12.3 cycles stalled waiting for a scoreboard dependency on L1TEX (local, global...) operation"* (61,2% del total de ciclos de espera) — coherente con **spill de registros a memoria local** (144-247 registros es mucho — probable que no quepan todos en el banco de registros y parte se derrame a memoria local, más lenta).

**Conclusión de la Fase 0**: el cuello de botella **no es que la fórmula de `derananum`/`vpot` sea intrínsecamente cara de calcular** (compute throughput solo 5,8%) — es que **la GPU apenas está ocupada** mientras las calcula, por exceso de registros por hilo. Esto también explica de raíz el hallazgo de `test-walker.md` (la GPU es más lenta que la CPU por debajo de ~500 walkers y se aplana en 2.000-3.000): con pocos walkers, el grid ya es demasiado pequeño para llenar la GPU sea cual sea el kernel — el problema de ocupación está ahí desde el principio, agravado por el registro.

## Prioridad para la Fase 1 (revisada con estos datos)

De los candidatos ya listados en el `README.md` de `v3-cuda-optimización/`, esta medición cambia el orden de prioridad:

1. **Reducir registros en `k_vpot_t`/`k_derananum_t`** (no explorado a fondo para `vpot` en sesiones anteriores — sí para `derananum`/`dmc2`, con resultados mixtos documentados en `tiempo-ncu-resultado.md` Partes 6-10). Impacto potencial alto: si sube la ocupación de 4,8% hacia el 25% teórico (o más, si además se reduce el propio límite de 25%), el kernel que domina el 99,3% del tiempo podría acelerarse sustancialmente.
2. **Barrido de tamaño de bloque** (32→64/128/256): dado que el límite real es "muy pocos bloques caben por registro", subir el tamaño de bloque sin bajar registros probablemente no ayude mucho por sí solo — pero es barato de probar y puede combinarse con lo anterior.
3. `derananum` de tamaño fijo (elimina heap de `device`, ver `derananum.md` Parte 9): no está entre las prioridades de rendimiento (el heap no aparece en este perfil como cuello de botella a 1.500 walkers), pero sigue siendo relevante para escalar por encima de ~3.000 walkers sin depender de subir el límite del heap.

## Ficheros

- `nsys_pipeline_1500w.nsys-rep`, `nsys_kern_sum.txt`: perfil completo y resumen por kernel.
- `ncu_derananum_vpot.ncu-rep`: perfil detallado (`--set full`) de `k_derananum_t`/`k_vpot_t`.
- `nsys_run_stdout.log`, `ncu_run_stdout.log`: salidas completas de las corridas instrumentadas.
