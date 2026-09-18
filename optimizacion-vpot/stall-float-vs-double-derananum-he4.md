# Stall de warps: `k_derananum_he4_t` (double) vs `k_derananum_he4_float_t` (float)

## 1. Objetivo

`float-wavef-derwavefhe4-validacion.md` confirmó que sustituir `wavef_derwavefhe4` por `float` no introduce sesgo detectable a escala de producción. Quedaba pendiente la pregunta directa: **¿cuánto baja realmente el stall de warps al pasar a `float`?** -- medido con `ncu`, no estimado.

## 2. Metodología

Reconstrucción de la integración en `float` (`/tmp/float-vs-double-test/`, no persistida -- mismo código que `float-wavef-derwavefhe4-validacion.md`: `wavef_derwavefhe4_float` + `k_derananum_he4_float_t`, sustituido en las 2 horquillas de `dmc2_pipeline.cuf`) y una copia de referencia sin tocar (`/tmp/double_ref_stall/`) del pipeline de producción real, para comparar en igualdad de condiciones.

Mismo `in.mcv` en ambas (plantilla verificada `etrial=-631.8`, `conf.20.00.HH` fresco): `opcion=7`, `2000 walkers`, `1 bloque de cálculo`, `5 pasos` -- suficiente para que `ncu` capture 10 lanzamientos de cada kernel (2 horquillas x 5 pasos), sin necesitar una corrida larga (esto mide mecánica de ejecución, no física).

`ncu --kernel-name "regex:derananum_he4..." --section WarpStateStats --section SpeedOfLight`, exportado a CSV (`--page raw`) y promediado sobre los 10 lanzamientos de cada kernel.

## 3. Resultado

### Duración y ocupación del kernel

| | `k_derananum_he4_t` (double) | `k_derananum_he4_float_t` (float) | Razón |
|---|---|---|---|
| Duración media | 1159,3 µs | 307,2 µs | **3,77x más rápido** |
| Throughput SM medio | 65,4% | 57,4% | -- |

Consistente con el benchmark aislado de `benchmark-float-vs-double.md` (3,85x) -- confirmado ahora de forma independiente, dentro del pipeline real, con otra herramienta de medición.

### Reparto del stall (ciclos de espera del warp scheduler por instrucción emitida)

| Motivo del stall | Double | Float | Cambio absoluto |
|---|---|---|---|
| `short_scoreboard` (MIO -- semilla `MUFU`+Newton-Raphson) | 17,90 (75,1%) | 6,15 (53,2%) | **-65,6%** |
| `wait` (dependencia de latencia fija, ALU/FMA) | 2,69 (11,3%) | 2,13 (18,4%) | -20,8% |
| `long_scoreboard` (latencia de memoria global) | 1,45 (6,1%) | 1,81 (15,6%) | +25,3% |
| `selected` (emitiendo, sin stall) | 1,00 (4,2%) | 1,00 (8,6%) | -- |
| `branch_resolving` | 0,57 (2,4%) | 0,29 (2,5%) | -49,6% |
| **Total ciclos de stall/instrucción** | **≈23,81** | **≈11,56** | **-51,5%** |

## 4. Interpretación

**El stall total baja a poco más de la mitad** (23,81 → 11,56 ciclos de espera por instrucción emitida) -- coherente con que el kernel tarda ~3,8x menos en total: menos ciclos de stall Y menos instrucciones en total (al perder la cadena de refinamiento de Newton-Raphson que `mypow_log`/`mypow_desde_log` necesitan en doble).

Lo interesante no es solo que baje, sino **cómo cambia la composición**:

- `short_scoreboard` (la espera por la semilla `MUFU.RCP64H`/`MUFU.RSQ64H` + su refinamiento, la "MIO" de toda la sesión) es la que se desploma en términos absolutos (-65,6%) -- exactamente lo esperado: en `float`, `exp`/`log` usan `MUFU.EX2`/`MUFU.LG2` nativos de hardware, sin necesitar ningún refinamiento posterior. Sigue siendo el motivo de stall dominante en ambos casos, pero deja de ser tan aplastante (pasa de 3 de cada 4 ciclos de espera a poco más de 1 de cada 2).
- `long_scoreboard` (espera de memoria global) **sube en términos absolutos** (+25,3%), no solo en proporción. La lectura de `atom_p`/escritura de `wfhe4_s`/`d1wfhe4_s`/`d2wfhe4_s` es la misma en ambas versiones -- lo que cambia es que, al desaparecer tanto cómputo de por medio, esa latencia de memoria deja de quedar "escondida" detrás del cálculo y se hace más visible. Es la firma clásica de un kernel que pasa de estar limitado por cómputo (compute-bound) a estar más cerca de estar limitado por memoria (memory-bound).
- `wait` también sube en proporción pero baja en absoluto (2,69→2,13) -- el mismo efecto que `long_scoreboard`: no es que empeore, es que pesa más sobre un total mucho más pequeño.

## 5. Decisión

No cambia la decisión de `float-wavef-derwavefhe4-validacion.md` (**no se lleva a producción todavía**, pendiente de validar a la escala larga del TFG) -- este documento añade el dato de stall que faltaba: la ganancia de velocidad no viene solo de "menos instrucciones", viene de verdad de aliviar el cuello de botella de stall que domina toda esta línea de investigación (`short_scoreboard`/MIO), a la vez que expone que el siguiente límite, si se seguyera por este camino con más métodos en `float`, empezaría a ser la latencia de memoria en vez del cómputo de las funciones matemáticas.

## Ficheros

- Copia aislada con la integración en `float`: `/tmp/float-vs-double-test/` (no persistida, reconstruida para esta medición).
- Copia de referencia en `double` (producción sin tocar): `/tmp/double_ref_stall/` (no persistida).
- Reportes `ncu`: `rep_float2.ncu-rep` / `rep_double.ncu-rep` en sus respectivos `run_stall/` (no persistidos).
