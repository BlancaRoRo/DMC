# test-walkers: resultados

Pasos por bloque=100, bloques de cálculo=100 fijos; walkers = 500, 1000, 1500, 2000, 2500. `etrial=-631.8` y semilla `0000000000000011` verificadas en las 10 corridas (5 escalas × GPU/CPU), `conf.20.00.HH` fresco antes de cada una.

## Verificación de datos (correctitud, no solo tiempo)

| Walkers | Energía final de config. (GPU) | Energía final de config. (CPU) | Walkers finales (GPU/CPU) |
|---|---|---|---|
| 500 | −615.5737694990 | −615.5737694990 | 500 / 500 |
| 1000 | −615.5737694990 | −615.5737694990 | 1000 / 1000 |
| 1500 | −615.5737694990 | −615.5737694990 | 1500 / 1500 |
| 2000 | −615.5737694991 | −615.5737694991 | 2000 / 2000 |
| 2500 | −615.5737694991 | −615.5737694991 | 2500 / 2500 |

**"Energía final de las configuraciones" es idéntica entre GPU y CPU en las 5 escalas**, y coincide con el valor de referencia usado en toda la línea de trabajo de `v3-cuda-optimización/` (`-615.5737694991`) -- confirma que la configuración inicial y los parámetros físicos son correctos en las 5 escalas. Ningún walker se pierde (finales = iniciales en todos los casos).

| Walkers | meV Energía total (GPU) | meV Energía total (CPU) | Diferencia | σ combinada | Compatibilidad |
|---|---|---|---|---|---|
| 500 | −636,28 ± 1,78 | −639,58 ± 1,71 | 3,30 | 2,47 | 1,34σ |
| 1000 | −641,11 ± 1,70 | −640,94 ± 1,58 | 0,17 | 2,32 | 0,07σ |
| 1500 | −639,94 ± 1,63 | −639,91 ± 1,62 | 0,02 | 2,30 | 0,01σ |
| 2000 | −640,64 ± 1,53 | −640,89 ± 1,55 | 0,25 | 2,18 | 0,12σ |
| 2500 | −640,92 ± 1,65 | −640,51 ± 1,59 | 0,41 | 2,29 | 0,18σ |

Todas las escalas compatibles, muy por debajo del umbral habitual de 2-3σ (el valor más alto, 1,34σ en 500w, es esperable -- es la estadística más pequeña de la batería, 100 bloques × 100 pasos × 500 walkers).

## Tiempos

| Walkers | GPU (wall) | CPU (wall) | Aceleración CPU/GPU |
|---|---|---|---|
| 500 | 31,18 s | 306,30 s | 9,83x |
| 1000 | 51,53 s | 607,15 s | 11,78x |
| 1500 | 83,79 s | 909,35 s | 10,85x |
| 2000 | 96,63 s | 1.219,83 s | 12,62x |
| 2500 | 121,74 s | 1.525,50 s | 12,53x |

Aceleración en el mismo orden que la medida en `control-final-cpu-vs-gpu.md` (~11,8x) para esta config física, consistente en toda la escala de walkers probada -- no hay indicio de que la aceleración se degrade o mejore de forma notable entre 500 y 2500 walkers a esta escala de bloques/pasos (100/100).

## Conclusión

Datos correctos en las 10 corridas, aceleración GPU consistente (~10-12,6x) en todo el rango de walkers probado. Sin anomalías.
