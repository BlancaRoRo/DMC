# Fase 2: medir la ganancia real de las mejoras de la Fase 3

Misma configuración exacta que `test-walker/` (nblockeq=1, nblock=59, npasosblo=20, semilla 11, `conf.20.00.HH` fresco antes de cada corrida) — solo se repite la mitad `op7` (GPU), con el pipeline ya mejorado (seed decorrelation + `sincroniza_constantes_gpu`/`sincroniza_etrial_gpu` + `k_fase_h`). `op4` (CPU, `gfortran` real) no se repite: esos tiempos ya existen y siguen siendo válidos (`../cpu-original-gfortran/rehacer_op4_gfortran_wall.log`).

## Resultado

| Walkers | `op4` (CPU gfortran) | `op7` antes | `op7` con mejoras | Aceleración (`op4`/`op7` nuevo) | Mejora sobre `op7` antes |
|---|---|---|---|---|---|
| 250 | 20,00 s | 26,91 s | 24,91 s | 0,803x (GPU aún más lenta) | +8,0% |
| 500 | 40,06 s | 39,04 s | 32,52 s | 1,232x | +20,0% |
| 1.000 | 79,63 s | 56,87 s | 46,41 s | 1,716x | +22,5% |
| 2.000 | 159,91 s | 89,83 s | 72,72 s | 2,199x | +23,5% |
| 3.000 | 237,44 s | 135,63 s | 111,06 s | 2,138x | +22,1% |

**El pipeline mejorado es un ~20-24% más rápido que antes en todo el rango de 500-3.000 walkers** — consistente con lo esperado: la mejora es un ahorro de tiempo fijo por bloque (menos copias redundantes + histogramas fusionados), así que su peso relativo es mayor cuanto más domina "el resto" sobre el trabajo GPU puro, y se estabiliza una vez el pipeline GPU es claramente el cuello de botella. El techo de aceleración frente a CPU sube de ~1,78x (antes) a **~2,2x** (ahora), en 2.000 walkers.

A 250 walkers la ganancia relativa es menor (+8%, no +20%): a esa escala el propio arranque/orquestación del grafo CUDA domina más que las piezas que se optimizaron, así que hay menos margen fijo que recortar — coherente con la Fase 0/3 (el coste fijo de lanzar el grafo, no las 24 copias ni `denssumapaso`, es lo que más pesa ahí).

## Estabilidad de los resultados

### Energía total: prácticamente idéntica antes/después de las mejoras

La cifra que importa es `Energia total` del resumen final de cada corrida — que es la misma que `<E_calculo>` del último bloque (bloque 59), con más decimales y su error estadístico (±), calculado sobre los 59 bloques de cálculo.

| Walkers | `op4` (CPU gfortran) | `op7` antes | `op7` con mejoras | Diferencia antes/después |
|---|---|---|---|---|
| 250 | -677,28 ± 3,41 | -677,66 ± 2,62 | -677,66 ± 2,62 | < 0,001 |
| 500 | -678,56 ± 1,89 | -683,48 ± 1,94 | -683,48 ± 1,94 | < 0,001 |
| 1.000 | -678,11 ± 1,91 | -679,34 ± 2,02 | -679,34 ± 2,02 | < 0,01 |
| 2.000 | -677,15 ± 1,94 | -676,30 ± 2,00 | -676,30 ± 2,00 | < 0,001 |
| 3.000 | -676,27 ± 1,86 | -678,06 ± 1,81 | -678,06 ± 1,81 | < 0,001 |

`op7` antes y después son indistinguibles hasta el redondeo mostrado — exactamente lo esperado, ya que ninguna de las mejoras (sincronización, `k_fase_h`) toca la física ni la secuencia de números aleatorios, solo el "alrededor". `op4` (CPU) y `op7` (GPU) difieren entre sí por ruido estadístico normal (dentro de 1-2σ en los 5 casos), como ya establecía `test-walker.md`.

### Cómo se llega a esa cifra: de bloque en bloque

Cada bloque (20 pasos DMC) da una energía muy ruidosa por sí solo (`<E_bloque>`, ejemplo real a 1.000 walkers: salta entre -654 y -704 según el bloque). `<E_calculo>` es la media **acumulada** desde el bloque 1 hasta el actual, por eso se va estabilizando: -636 en el bloque 1 → -690 hacia el bloque 20-30 → -679,34 en el bloque 59 (la cifra final). Es la forma estándar de DMC de convertir un paseo aleatorio ruidoso en una estimación con error decreciente.

### Población: sin colapsos en ninguna escala

Población final = walkers de entrada en las 10 corridas (5 antes + 5 después), sin NaN ni errores.

### Una cifra que NO hay que usar: "energia final de las configuraciones"

Esta línea (al final de cada log) es idéntica en las 10 corridas (-615,5737694990) sin importar walkers, CPU/GPU o semilla. Revisando el código (`mmontecarlo.f90:807`, subrutina `finwalkers`): suma `w1%lw%ene`, una variable de trabajo de una fase **anterior** al muestreo DMC (minimización de energía, antes de arrancar la simulación) — no la población final `wsim(iwalker)` que sí se usa en las líneas de al lado. Parece un residuo del código original (anterior a este proyecto), no un resultado físico de la simulación — no debe usarse para comparar corridas.

## Siguiente paso: dónde sigue el coste ahora

Con `sincroniza_globales_gpu` y `denssumapaso` ya arreglados, el desglose de tiempos a gran escala (3.000 walkers, `tiempos_opcion7.dat` de esta misma batería) cambia de forma reveladora:

| Componente | Antes (250w, fase 3) | Ahora (3.000w) |
|---|---|---|
| `lanza_pipeline` (grafo CUDA — física real) | 61,2% | **84,9%** |
| Conversión AoS↔SoA (pack+H2D+D2H+unpack) | 5,4% | **12,0%** |
| `sincroniza_globales_gpu`/`etrial` | 15,9% | 0,036% |
| `denssumapaso` | 13,8% | 0,024% |
| reparto/compactación | 0,8% | 1,3% |

Con las dos piezas grandes de "alrededor" ya resueltas, quedan solo dos candidatos reales:

1. **`lanza_pipeline` (84,9%, el kernel de física en sí)**: es donde vive `derananum`/`vpot`, ya investigado a fondo en la Fase 1 (registros, reparto de bloque, multi-walker) — con resultado mayormente negativo para la física real de parejas (el único hallazgo positivo, `k_multiwalker`, no aplica aquí). Las palancas "baratas" de este componente ya están agotadas; seguir aquí exigiría o bien tocar la fórmula física (cambia precisión, requiere permiso explícito) o hardware distinto (Fase 3 "condicional" del plan original).
2. **Conversión AoS↔SoA (12,0%, y creciendo en peso relativo)**: candidato nuevo, no explorado todavía. Son bucles CPU (`empaquetar`/`desempaquetar`, ~10,8 s de los 13,25 s a 3.000 walkers) que recorren `wsim` walker a walker, cada paso DMC, para convertir entre el formato AoS que usa el resto del código y el SoA que necesita la GPU. Encaja con la idea de "SoA nativo residente" que ya se había apuntado en esta sesión (mantener `wsim` en formato SoA de forma permanente, evitando repetir esta conversión en cada paso) — la siguiente investigación lógica, siguiendo el mismo patrón de siempre: medir/aislar antes de tocar nada.

## Ficheros

- `rehacer_op7_test_walker.sh`: script (solo relanza `op7`).
- `op7_mejorado_{250,500,1000,2000,3000}walkers.log`, `wall_times_op7_mejorado.log`.
