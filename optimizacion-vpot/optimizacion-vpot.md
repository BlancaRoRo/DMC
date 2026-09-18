# Optimización de `vpot`: por qué será el próximo cuello de botella

## Objetivo

`derananum-split-concurrente.md` dejó abierta una pregunta: la aceleración de
su split de `derananum` se mantiene estable (~2,6x) hasta 2000w pero cae a
~2,1x en 3000w, sin causa confirmada. Hipótesis de partida de esta
investigación: `vpot` (que esa investigación no tocó) podría estar
empezando a pesar lo suficiente como para explicar esa caída, y en cuanto el
split de `derananum` se migre a producción, `vpot` pasará a ser el kernel
dominante del pipeline.

## Medición 1: reparto real de tiempo por kernel, producción actual (sin split)

`nsys profile --cuda-graph-trace=node` sobre `qmccluster_pipeline`
(producción actual, `derananum` todavía monolítico), opcion=7, semilla 11,
1 bloque equilibrio + 59 bloques cálculo × 20 pasos = 1200 pasos, en
`v2-cuda-integracion/hibrido_instrumentado/` (worktree
`investigacion-vpot-registros`).

| Kernel | 2000w -- Time (%) | 2000w -- Tiempo medio/llamada | 3000w -- Time (%) | 3000w -- Tiempo medio/llamada |
|---|---|---|---|---|
| `k_derananum_t` | **72,0%** | 21,21 ms | **71,0%** | 28,93 ms |
| `k_vpot_t` | **26,0%** | 7,67 ms | **27,0%** | 11,21 ms |
| resto (fases a/c/d/f/g/h + split_seeds) | ~2,0% | -- | ~2,0% | -- |

(2.368 instancias de cada kernel en ambas escalas -- 2 llamadas/paso × 1184
pasos reales tras el equilibrio.)

**En producción actual, `vpot` NO es el cuello de botella** -- `derananum`
sigue dominando con claridad en ambas escalas. Hay una tendencia real pero
pequeña: el peso de `vpot` sube ligeramente con la escala (26,0% → 27,0%),
coherente con la caída de aceleración observada en el split a 3000w, pero
no explica por sí sola una caída de 2,6x a 2,1x -- un cambio de 1 punto
porcentual es demasiado pequeño.

Comparación con la medición de referencia anterior (`fase0-perfilado.md`,
1500w, antes de que `myexp-optimizacion` estuviera en producción):
`derananum` 73,8% / `vpot` 25,5%. El reparto apenas se ha movido desde
entonces pese a las optimizaciones de `derananum` ya migradas -- indicio de
que esas optimizaciones (registros de `myexp`/`GTEST`/`nhe3` fijo) no
cambiaron sustancialmente el tiempo relativo de `derananum` frente a
`vpot`, a diferencia de lo que haría el split (ver más abajo).

## Medición 2: reparto real de tiempo por kernel, CON el split de `derananum`

La Medición 1 mide producción sin el split -- para saber qué pasaría si el
split se migra, hace falta perfilar el propio código del split, no
estimarlo combinando documentos distintos. Se reconstruyó `gpu-split/`
(recortada a solo sus ficheros editados) copiando
`derananum_split_mod.cuf`, `der_wavefx_mod.cuf`, `dmc2_pipeline.cuf`,
`wavef_mod.cuf` sobre una copia fresca de `hibrido_instrumentado/`,
recompilado con el mismo `FILES` de `compilar_split.sh`. Mismo protocolo
que la Medición 1 (`nsys profile --cuda-graph-trace=node`, opcion=7,
semilla 11, 1+59 bloques × 20 pasos, conf fresco de
`v1-cuda-desarrollo/ccuerpo/`).

| Kernel | 2000w -- Time (%) | 2000w -- Tiempo medio/llamada | 3000w -- Time (%) | 3000w -- Tiempo medio/llamada |
|---|---|---|---|---|
| **`k_vpot_t`** | **53,0%** | 6,14 ms | **54,0%** | 10,12 ms |
| `k_derananum_split_resto_t` | 23,0% | 2,67 ms | 22,0% | 4,09 ms |
| `k_derananum_split_he4_t` | 20,0% | 2,36 ms | 19,0% | 3,66 ms |
| `k_derananum_split_join_t` | ~1,0% | 0,06 ms | ~1,0% | 0,09 ms |
| resto (fases) | ~2,0% | -- | ~2,0% | -- |

Energía idéntica bit a bit a la Medición 1 en ambas escalas
(`-615.5737694991 meV`, ambas mediciones repetidas con la referencia
correcta de `conf.20.00.HH`), confirmando que esta reconstrucción de
`gpu-split` es físicamente equivalente a producción con el split
aplicado. Curiosamente, el mismo valor exacto sale en las 4 corridas
(sin split/con split × 2000w/3000w) -- no varía con la escala, algo
llamativo que no se investiga aquí por no ser relevante para `vpot`
(ver nota en `derananum-split-concurrente.md`).

**Confirmado con datos reales, no estimados: en cuanto se migre el split,
`vpot` pasa a ser el kernel dominante del pipeline al ~53-54%** -- coincide
con la cifra que se recordaba de esta misma investigación en una sesión
anterior. Esto confirma con solidez el motivo de esta investigación.

**Pero NO explica la caída de aceleración del split a 3000w**: igual que
en la Medición 1, el peso de `vpot` apenas sube (53,0% → 54,0%, 1 punto)
entre 2000w y 3000w -- insuficiente para explicar por sí solo que la
aceleración del split caiga de 2,6x a 2,1x en ese rango. Esa anomalía
sigue sin causa confirmada (ver nota en `derananum-split-concurrente.md`);
el candidato más plausible que queda sin comprobar es el límite de heap de
`device` de `derananum.md` Parte 9 (~3000-3500 walkers), no el peso de
`vpot`.

## Medición 3: registros y ocupación de `k_vpot_t`

`ncu --set full --kernel-name regex:k_vpot_t --launch-skip 1 --launch-count 1`,
mismo binario/config que la Medición 1 (2000w y 3000w, opcion=7, semilla 11).

| Métrica | 2000w | 3000w |
|---|---|---|
| Registros/hilo | 106 | 106 |
| Grid Size (bloques) | 125 | 188 |
| Waves per SM | 0,33 | 0,49 |
| Block Limit Registers | 16 | 16 |
| Theoretical Occupancy | 33,33% | 33,33% |
| **Achieved Occupancy** | **5,55%** | **7,89%** |
| Compute (SM) Throughput | 27,05% | 28,18% |
| Memory Throughput | 6,66% | 8,37% |
| Duration | 8,29 ms | 11,23 ms |

Mismo patrón ya visto en `derananum` antes del split y en
`fase0-perfilado.md`: ocupación real muy por debajo de la teórica (5,5-7,9%
frente a 33,3%), grid demasiado pequeño para llenar la GPU a estas escalas
(0,33-0,49 oleadas/SM). El límite de 16 bloques por registros (106
registros/hilo) es el mismo orden de magnitud que tenía `derananum` antes
de su split (126 registros, límite también 16) -- mismo mecanismo
candidato: **partir `vpot` en piezas más pequeñas podría liberar registros
y mejorar la ocupación, igual que funcionó con `derananum`**.

## Medición 4: perfilado por función dentro de `k_vpot_t`

`ncu --set full --page source --import-source yes`, exportado a CSV
(`--page source --csv`) y sumado por función (misma metodología que
`fase0-perfilado.md`/`optimización-mypow.md`), 2000w. Se suma la columna
"# Samples" (muestreo de warp-stall, proporcional al tiempo real) de
cada bloque de código fuente, agrupado por la función a la que pertenece.

| Función | % del tiempo de `vpot` | Instrucciones ejecutadas |
|---|---|---|
| **`Vp_hehe`** | **26,0%** | 2.750.810 |
| `myexp` | 20,6% | 2.721.978 |
| **`V_hehe`** | **15,9%** | 1.853.814 |
| `He_dihydrogen` (lógica propia) | 13,4% | 1.685.565 |
| `mypow_desde_log` | 7,8% | 1.614.060 |
| `mypow_log` | 3,4% | 548.100 |
| `mycos` | 2,3% | 385.830 |
| `mysin` | 2,2% | 384.012 |
| `real_of`/`bits_of`/`top12_of` (helpers de `myexp`) | 4,1% | 966.300 |
| `angle`/`myacos`/`vec_norm`/`scalar_product` | 3,3% | 439.740 |
| `ccuerpo` | 0,6% | 47.943 |
| `k_vpot_t` (kernel en sí) | 0,2% | 20.901 |
| `vpot`/`potenbh` (envoltorios) | 0,0% | 10.710 |

**`V_hehe`+`Vp_hehe` (el potencial de pareja He-He) es el 41,9% combinado
-- con diferencia el mayor bloque.** Mismo patrón que ya se vio en
`derananum` antes de `optimización-mypow`: el kernel casi no gasta nada en
su propia lógica (0,2%), todo el peso está en las funciones matemáticas
que llama. `myexp` por sí solo es un 20,6% -- no tiene el tratamiento de
"log/desde_log" que ya recibió `mypow` (que aquí solo cuesta 7,8%+3,4%=11,2%
combinado, bastante menos que `myexp` a pesar de aparecer también en
`V_hehe`/`Vp_hehe`).

**Candidatos concretos para seguir, por orden de impacto:**
1. `V_hehe`/`Vp_hehe` en conjunto (41,9%) -- el potencial de pareja He-He,
   candidato natural a examinar primero por ser el mayor bloque.
2. `myexp` (20,6%) -- ver si admite el mismo tipo de optimización que ya
   recibió `mypow` (separar en `log`+`desde_log` para reutilizar cálculo
   entre llamadas cercanas), o alguna variante más barata como se hizo en
   `myexp-optimizacion.md` para `derananum`.
3. No investigado todavía: cuánto de `myexp`/`mypow` dentro de `vpot`
   viene de `V_hehe`/`Vp_hehe` en concreto frente a otras rutas de
   `He_dihydrogen` -- haría falta perfilado por línea (no solo por
   función) para saber si conviene atacar la función matemática en sí o
   el patrón de llamada desde `V_hehe`/`Vp_hehe`.

## Medición 5: fusión de `V_hehe`+`Vp_hehe` -- resultado positivo

`V_hehe(r)`/`Vp_hehe(r)` se llaman siempre con el mismo `r`, dos líneas
seguidas, en el bucle de parejas He4-He4 de `He_dihydrogen.f:311-324`
(~190 pares). Ambas recalculan por separado `x=r/req_HeHe` y sus
potencias, y sobre todo **2 llamadas a `myexp` idénticas** (`F` y el
término principal) -- mismo patrón de redundancia que `fusion-angle-hehe`,
pero eliminando algo mucho más caro (2 `myexp`, no raíces+bucles cortos).

**Cambio**: nueva `V_and_Vp_hehe(r, v, vp)` en `mVheheVphehe_mod.cuf`
(calcula `x`/potencias/los 2 `myexp` una sola vez, ramas `mysin`/`mycos`
al final sin tocar), sustituye las 2 llamadas por 1 en `He_dihydrogen.f`.

**Verificación**: bit a bit correcto (`-615.5737694991 meV`, 2000w,
semilla 11, idéntico a producción con el split ya migrado).

**Registros de `k_vpot_t`**: **106 → 106, sin cambio** -- a diferencia de
`fusion-angle-hehe` (106→136), aquí no hay penalización de registros.

**Tiempo real** (2000w, 2 rondas alternas, conf restaurado antes de cada
corrida):

| Ronda | Producción | Fusión | Diferencia |
|---|---|---|---|
| 1 | 30,71 s | 27,10 s | -11,8% |
| 2 | 26,24 s | 24,96 s | -4,9% |
| **Media** | **28,48 s** | **26,03 s** | **-8,6%** |

La fusión gana en las 2 rondas (a diferencia de `fusion-angle-hehe`, donde
el orden se invertía entre rondas -- señal de que aquello era ruido). Aquí
la dirección es consistente aunque la magnitud varíe (11,8% vs 4,9%,
dispersión normal de deriva térmica) -- **resultado real, no ruido**.

**Nota**: el `ncu --set full` de una sola instancia del kernel (Duration
8,29→8,37 ms) no mostró esta mejora -- posiblemente porque el ahorro se
nota más en la media de muchas llamadas (1200 pasos) que en una instancia
aislada con el overhead del profiler encima. El tiempo real de la corrida
completa es la medida que manda aquí, siguiendo el mismo criterio que el
resto del árbol.

**No hizo falta investigar "por qué es más caro para el compilador"**
(la pregunta que se dejó abierta al proponer esta prueba) -- en este caso
no lo fue: los registros no subieron. La diferencia con `fusion-angle-hehe`
más probable: allí se eliminaba `angle()` como llamada indirecta aparte
(cambiando el patrón de llamada, lo que alteró el pico de registros según
ese documento); aquí `V_hehe`/`Vp_hehe` ya eran funciones `host,device`
normales fusionadas en otra del mismo tipo, sin indirección de por medio.

**Migrado a producción** (`hibrido_instrumentado/mVheheVphehe_mod.cuf` +
`He_dihydrogen.f`). Verificado bit a bit tras la migración
(`-615.5737694991 meV`, 2000w, semilla 11).

## Medición 6: reparto de tiempo por kernel, después de la fusión

Mismo protocolo que la Medición 2 (`nsys profile --cuda-graph-trace=node`,
2000w y 3000w, producción ya con split de `derananum` + fusión
`V_hehe`/`Vp_hehe`, ambas en producción).

| Kernel | 2000w -- antes → después | 3000w -- antes → después |
|---|---|---|
| **`k_vpot_t`** | 53,0% → **50,0%** | 54,0% → **51,0%** |
| `k_derananum_split_resto_t` | 23,0% → 24,0% | 22,0% → 23,0% |
| `k_derananum_split_he4_t` | 20,0% → 21,0% | 19,0% → 21,0% |

`vpot` baja ~3 puntos porcentuales en ambas escalas (coherente con el
~8,6% de mejora de tiempo real medido en la Medición 5) -- sigue siendo
el kernel dominante, pero un poco menos. Energía idéntica bit a bit
(`-615.5737694991 meV`) en las dos escalas, confirma que la migración no
cambió nada del resultado físico.

## Estado y siguiente paso

- Confirmado con datos frescos: `vpot` no era el cuello de botella con
  `derananum` monolítico (26-27% del tiempo), pero **ya lo es** ahora que
  el split de `derananum` está migrado a producción (53-54%, medido
  directamente).
- Descartado como explicación de la caída de aceleración del split a
  3000w: el peso de `vpot` apenas crece con la escala (53,0%→54,0%),
  tanto con split como sin él -- esa anomalía sigue abierta en
  `derananum-split-concurrente.md`.
- `vpot` comparte el mismo síntoma que tenía `derananum` antes del split
  (ocupación real muy por debajo de la teórica, grid pequeño, 106
  registros/hilo) -- candidato natural: examinar si `vpot`/`He_dihydrogen`
  tiene partes independientes que se puedan separar en kernels propios,
  siguiendo el mismo mecanismo que funcionó en `derananum-split-concurrente.md`
  (aislar la parte más pesada reduce el pico simultáneo de registros).
- Pendiente: identificar dentro de `He_dihydrogen.f`/`V_hehe`/`Vp_hehe` qué
  contribuciones son independientes entre sí (candidatas a separarse en
  kernels concurrentes) -- todavía no analizado.
- **Fusión `V_hehe`+`Vp_hehe` (Medición 5)**: positivo, ~8,6% más rápido,
  sin coste de registros, verificado bit a bit -- **en producción**.
- Investigadas y descartadas (ya resueltas en `myexp-optimizacion.md`,
  sección 9.6): cachear `FN2(btheta*rh1/rh2/r0)` en `Ex0`/`Ey0`/`Ez0`
  (bajaba registros pero empeoraba el tiempo real un 22-66%, causa
  mecánica nunca identificada); `FN1` ya está en su forma óptima (`myexp`
  compartido internamente desde `myexp-optimizacion.md` (a), sin llamadas
  repetidas externas en la parte viva) -- nada que sacar ahí.

## Nota metodológica: `conf.20.00.HH`

Durante esta investigación se detectó (y corrigió) un error propio: restaurar
`conf.20.00.HH` con `git checkout` devuelve el fichero que quedó commiteado
en `hibrido_instrumentado/` (un resto de una corrida anterior, walkers ya
evolucionados), **no** el arranque limpio real. La referencia correcta,
usada en todo el proyecto (`run_comparacion.py`, `CONF_FRESCO`), es copiar
`v1-cuda-desarrollo/ccuerpo/conf.20.00.HH` (1.365 bytes, 1 configuración)
antes de cada corrida. Las medidas de este documento usan la referencia
correcta.

## Ficheros

- `nsys_pipeline_2000w.nsys-rep`/`.sqlite`, `nsys_kern_sum_2000w.txt`: perfil
  completo y resumen de kernels de la Medición 1 a 2000w (producción sin split).
- `nsys_pipeline_3000w.nsys-rep`/`.sqlite`, `nsys_kern_sum_3000w.txt`: ídem a 3000w.
- `split-2000w-3000w/`: perfiles de la Medición 2 (`gpu-split` reconstruido),
  `nsys_split_2000w.nsys-rep`/`.sqlite`+`nsys_kern_sum_split_2000w.txt` y su
  equivalente a 3000w -- no incluye el binario/fuentes reconstruidos, solo
  la evidencia del perfilado (el propio `gpu-split/` de
  `derananum-split-concurrente/` sigue siendo la referencia recortada para
  reconstruirlo si hace falta).
- `fusion-v-vp-hehe/`: ficheros editados de la Medición 5 (`mVheheVphehe_mod.cuf`
  con `V_and_Vp_hehe` nueva, `He_dihydrogen.f` con la llamada sustituida,
  `in.mcv`), perfil `ncu_fusion_vpot_2000w.ncu-rep` y logs de verificación
  y tiempo (`tiempo_fusion_r1/r2.log`). No es copia completa compilable
  por sí sola -- copiar sobre una copia fresca de `hibrido_instrumentado/`.
- `post-fusion-2000w-3000w/`: perfiles de la Medición 6 (`nsys_postfusion_2000w/3000w.nsys-rep`/`.sqlite`
  + `nsys_kern_sum_postfusion_2000w/3000w.txt`), sobre producción ya con la
  fusión migrada.
- `ncu_vpot_2000w.ncu-rep`, `ncu_vpot_3000w.ncu-rep`: perfiles `--set full`
  de `k_vpot_t` de la Medición 3, ambas escalas (sobre producción sin split).
- `ncu_vpot_source_2000w.ncu-rep`, `ncu_vpot_source_2000w.csv`: perfil
  `--page source --import-source yes` y su volcado CSV de la Medición 4
  (perfilado por función), 2000w, sobre producción con el split ya migrado.
- `run_2000w_stdout.log`, `run_3000w_stdout.log`, `ncu_vpot_2000w_stdout.log`,
  `ncu_vpot_3000w_stdout.log`, `ncu_vpot_source_2000w_stdout.log`: salidas
  completas de las corridas.
