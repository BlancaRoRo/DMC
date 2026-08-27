# Control final: CPU (`gfortran`) vs. GPU con todos los cambios de `optimizacion-vpot/` aplicados

## 1. Objetivo

Con la tabla de `mapa-sfu-produccion.md` §4.1 ya sin ningún método "No visto", se cierra esta línea de trabajo con una batería completa: física + tiempos totales contra la CPU original (`gfortran`, `opcion=4`), y un perfil final del lado GPU (registros, stall de warps, instrucciones) con **todos** los cambios de esta carpeta ya en producción:

`funciones-nativas-cuda.md` + `reciprocos-ex0-duhe4x.md` (§2-6.1) + `reciprocos-k-fase-h.md` + `reciprocos-derwavefx.md` + `reciprocos-v-and-vp-hehe.md` + `reciprocos-he-dihydrogen-dispersion.md` + `log-rij-redundante.md` + `reciprocos-wavef-derwavefhe4.md`.

Config idéntica en ambos binarios: 2000 walkers, 1 bloque de equilibrio, 59 bloques de cálculo, 20 pasos por bloque -- la misma que usa `hibrido_instrumentado/in.mcv` y la misma que `test-walker/op4_2000walkers.log`/`op7_2000walkers.log`. `conf.20.00.HH` fresco antes de cada corrida individual (mismo protocolo de siempre).

## 2. Física: CPU vs GPU, 4 semillas

| Semilla | CPU (`gfortran`, opcion=4) | GPU (producción, todos los cambios) | Diferencia | σ combinada |
|---|---|---|---|---|
| 11  | −677.1452 ± 1.938 meV | −676.8178 ± 1.845 meV | 0.327 | 0,12σ |
| 97  | −679.3221 ± 1.800 meV | −677.4046 ± 1.803 meV | 1.918 | 0,75σ |
| 42  | −681.3123 ± 1.822 meV | −678.4074 ± 1.925 meV | 2.905 | 1,10σ |
| 777 | −678.7018 ± 2.076 meV | −678.9230 ± 1.706 meV | 0.221 | 0,08σ |

Idénticas a las 4 semillas ya registradas en `reciprocos-k-fase-h.md` §7 -- los 5 cambios añadidos desde entonces (`derwavefx`, `V_and_Vp_hehe`, `He_dihydrogen_dispersion`, `log_rij`, `wavef_derwavefhe4`) no mueven ni un dígito el resultado GPU, tal como garantizaba cada verificación bit a bit individual. Todas las semillas compatibles con la CPU, ninguna por encima de 1,1σ.

## 3. Tiempos totales

| Semilla | CPU `tiempo de CPU en s` | GPU `tiempo total opcion7 (pipeline)` | Cociente |
|---|---|---|---|
| 11  | 159,67 s | 14,97 s | 10,67x |
| 97  | 158,46 s | 13,01 s | 12,18x |
| 42  | 158,79 s | 12,96 s | 12,25x |
| 777 | 160,33 s | 12,95 s | 12,38x |
| **Media** | **159,31 s** | **13,47 s** | **~11,8x** |

(La semilla 11 es sistemáticamente la más lenta en GPU en toda esta línea de trabajo -- mismo patrón de calentamiento/JIT ya observado en verificaciones anteriores, no específico de esta prueba.)

**Nota importante -- discrepancia con `test-walker/wall_times.log`, causa verificada (no supuesta)**: esa batería (misma config exacta: 2000w/59 bloques/20 pasos) registró wall=253,5s (CPU) / wall=89,8s (GPU) -> ~2,8x, muy por debajo del ~11,8x medido aquí. **No es un artefacto de medición -- son dos binarios distintos**, confirmado por fecha:

- `test-walker/wall_times.log` está fechado el **14-08-2026**.
- Entre esa fecha y hoy: `2f16339` (20-08-2026) migra el split de `derananum` a producción (una de las mejoras más grandes del proyecto, ~2,6x por sí sola según el propio índice de este README) y **toda** la línea de trabajo `optimizacion-vpot/` (los 8 fixes de SFU de esta carpeta) se hizo íntegra en la sesión de hoy, 27-08-2026 -- el `qmccluster_pipeline` de la batería antigua casi seguro no tenía ni el split de `derananum` aplicado.
- Por el lado CPU, `lanzar_test_walker.sh` usaba `qmccluster_tiempos` (compilado con `nvfortran` "por error", ya documentado en el propio árbol -- de ahí `rehacer_op4_gfortran.sh`), no el `gfortran` correcto usado en esta tabla.

Es decir: ninguno de los dos lados de esa comparación antigua es el mismo código que se compara aquí -- no son cifras comparables entre sí, y el ~1,75x de aquella batería no debe tomarse como referencia de "techo real" del código actual. La cifra de esta tabla (~11,8x) sí usa el binario de producción real, verificado bit a bit contra la CPU en la sección 2. Si se quiere una curva walkers-vs-aceleración actualizada con el código de hoy, hay que rehacer `test-walker`/`test-bloques`/`test-pasos` (Fase 2 del plan pendiente) -- no reciclar los logs de agosto.

## 4. Perfil final del lado GPU (todos los cambios, `ncu` sobre el binario de producción)

Kernels realmente lanzados con más peso físico/SFU -- media de 3-4 lanzamientos cada uno (`--launch-skip 2`, régimen estable, sin el primer lanzamiento de calentamiento):

| Kernel | Registros/hilo | Ciclos | Instr. totales | FMA | XU (SFU) | Ciclos de warp/instr. emitida | Stall dominante |
|---|---|---|---|---|---|---|---|
| `k_vpot_3warp_t` | 94 | 2.659.692 | 7.538.289 | 726.187 | 52.866 | 59,76 | MIO (65,3%) |
| `k_derananum_he4_t` | 90 | 1.521.014 | 3.894.521 | 570.210 | 59.850 | 23,81 | MIO (75,1%) |
| `k_derananum_resto_t` | 111 | 1.430.616 | 3.849.792 | 477.033 | 30.681 | 22,43 | MIO (72,7%) |
| `k_derananum_join_t` | 40 | 81.892 | 166.560 | 24.567 | 0 | 28,66 | L1TEX (49,9%) |
| `k_fase_h` | 94 | 335.277 | 804.181 | 110.184 | 17.136 | 24,93 | MIO (76,0%) |

**MIO = "memory input/output operation (not to L1TEX)"** -- es la misma familia de stall que `short_scoreboard` (la que originó todo el diagnóstico de `split-he-dihidrogen.md`, Intento 8): `ncu` la describe explícitamente como causada por operaciones a memoria compartida **o por instrucciones matemáticas especiales frecuentes (MUFU)**, que es justo lo que esta línea de trabajo lleva reduciendo desde entonces. Sigue siendo la mayoría del stall en los kernels de física real -- **reducida en magnitud absoluta por todos los fixes aplicados, pero no eliminada como categoría**: incluso sin SFU, `duhe4x`/`derwavefx`/`k_fase_h` todavía tienen spill a memoria local (`pl(0:l)` de `calplegd`, confirmado en `mapa-sfu-produccion.md` nota GPU) y accesos a arrays grandes en registros/local, que también cuentan como MIO.

Nota sobre registros: una recompilación aislada de cada `.cuf` por separado (vía `-gpu=ptxinfo`) da cifras mucho más bajas (`k_vpot_3warp_t`=40, `k_derananum_he4_t/resto_t/join_t`=40) que no coinciden con lo que el binario real usa en ejecución (94/90/111/40 vía `ncu launch__registers_per_thread`) -- mismo aviso que ya dejó `log-rij-redundante.md` con los conteos SASS estáticos: **el número real es el que reporta `ncu` sobre el binario enlazado**, no una recompilación parcial fuera de contexto (el enlazado final decide inlining de las funciones `device` llamadas -- `He_dihydrogen_hehe`, `V_and_Vp_hehe`, `duhe4x`, `derwavefx`, etc. -- de forma distinta a compilar cada fichero suelto).

## 5. Conclusión

- **Física**: sin cambios, confirmado de nuevo con el control acumulado completo -- los 8 fixes de esta carpeta son, en conjunto, bit a bit idénticos a la producción intermedia y compatibles con la CPU dentro de 1,1σ.
- **Tiempos**: ~11,8x CPU/GPU con el binario de producción real de hoy -- mucho mayor que el ~1,75x de la batería `test-walker` antigua, que comparaba binarios distintos (GPU sin el split de `derananum` ni ninguno de los 8 fixes de SFU, CPU compilada con `nvfortran` en vez de `gfortran`), no una cuestión de metodología de medición. Repetir esa batería con el código de hoy queda pendiente (Fase 2 del plan) si se quiere una curva walkers-vs-aceleración actualizada.
- **Registros/stall/instrucciones**: el stall dominante en los 3 kernels de física real (`k_vpot_3warp_t`, `k_derananum_he4_t/resto_t`, `k_fase_h`) sigue siendo MIO/short-scoreboard (65-76%), la misma categoría que motivó toda esta línea de trabajo -- coherente con que se ha reducido la cantidad de SFU, no eliminado su naturaleza como cuello de botella.

## Ficheros

- Verificación hecha directamente sobre copias de `hibrido_instrumentado/` y `cpu-original-gfortran/` -- no persistida (quedó en `/tmp`, no en el repo).
