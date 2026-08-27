# v3-cuda-optimización: optimización del pipeline CUDA y evaluación de arquitecturas alternativas

Continuación de `v2-cuda-integracion/` (porteo funcional ya cerrado y validado). Cada investigación vive en su propia carpeta, con su propio `.md` explicando qué se hizo, sus pruebas/salidas, y sus conclusiones — mismo criterio que `test-pasos/`, `test-walker/`, `test-bloques/` en `v2-cuda-integracion/`.

## Contexto

El porteo a CUDA está funcionalmente cerrado y validado: física equivalente a la CPU (`op4`, `gfortran`) dentro del margen de error estadístico, sin colapsos de población (bug de semillas clonadas corregido), sin fallos de recursos a gran escala (heap de `device` corregido). Las 3 baterías de `v2-cuda-integracion/` (`test-pasos`, `test-walker`, `test-bloques`) midieron la aceleración real frente a la CPU correcta (`gfortran`) y el resultado fue más modesto de lo esperado (~1,3x-1,8x según el eje) — de ahí nace esta carpeta: perfilar el pipeline real (no el kernel único antiguo) y atacar el cuello de botella con datos, no intuición.

## Metodología (la misma en todas las investigaciones)

**Medir primero, hipótesis después, cambio aislado, verificar bit-exacto/dentro de error, medir de nuevo, mantener o revertir, documentar siempre** — incluidos los resultados negativos. Varias de las mejoras más valiosas de este árbol fueron descartar caminos que no funcionaban, con la razón exacta anotada. Nunca se mueve nada a producción sin verificación explícita.

## Índice de investigaciones

Agrupado por tipo de trabajo, no por orden cronológico (los nombres `fase0`/`fase1`/... de dentro de cada carpeta se conservan porque así se generaron, pero ya no marcan una secuencia global). "Estado" resume el resultado final, no si está terminada.

### Perfilado y medición

Dónde se va el tiempo, sin cambiar código todavía (o solo tocando flags de compilación).

| Carpeta | Qué investiga | Estado |
|---|---|---|
| [`perfilado-medicion/fase0-perfilado/`](perfilado-medicion/fase0-perfilado/) | Perfilado inicial del pipeline de 7 fases (primer `ncu`/`nsys` real, no el kernel único antiguo) | Base de todo lo posterior |
| [`perfilado-medicion/fase1-registros/`](perfilado-medicion/fase1-registros/) | Tiempos por método (cuál pesa más) + intento de bajar registros con `-gpu=maxregcount:N` | Medición + primer intento de reducir registros por flag |
| [`perfilado-medicion/fase2-medicion-mejoras/`](perfilado-medicion/fase2-medicion-mejoras/) | AoS↔SoA: qué variables sobraban como persistentes -- algunas se eliminaron | **Positivo, en producción** (`wfhe4_p`/`wfhe3_p`/`wfm_p`/`wfx_p` ya no viajan por H2D/D2H) |
| [`perfilado-medicion/tiempos-metodos-dmc/`](perfilado-medicion/tiempos-metodos-dmc/) | Tiempos por método, CPU original vs. GPU con todas las mejoras aplicadas | Medición de referencia |

### Arquitectura de lanzamiento

Cómo se reparte el trabajo entre bloques/hilos/kernels — no cambia fórmulas, cambia cómo se organiza el cómputo en la GPU.

| Carpeta | Qué investiga | Estado |
|---|---|---|
| [`arquitectura-lanzamiento/fase1-bloque-por-walker/`](arquitectura-lanzamiento/fase1-bloque-por-walker/) | ¿Más de 1 hilo por walker ayuda? (bloque=walker, multiwalker, atomics a memoria global) | **Negativo** en todos los casos reales — documentado para no repetir el intento |
| [`arquitectura-lanzamiento/fase3-arquitecturas-alternativas/`](arquitectura-lanzamiento/fase3-arquitecturas-alternativas/) | Overhead de CUDA Graph, persistir kernels entre pasos, dónde se va el tiempo "invisible" | Descartó varias vías (overhead de grafo despreciable) |
| [`arquitectura-lanzamiento/derananum-split-concurrente/`](arquitectura-lanzamiento/derananum-split-concurrente/) | Split de `derananum` en 3 kernels concurrentes (He4/resto/cierre) + arreglo de bucles `ngatom→nhe3` | **En producción** (~2,6x en 500-2000w, ~2,1x en 3000w) |
| [`arquitectura-lanzamiento/derwavefx-split-concurrente/`](arquitectura-lanzamiento/derwavefx-split-concurrente/) | Sacar `derwavefx` de "resto" a un 4º kernel concurrente (baja resto de 126→67 registros) | **Negativo** (~12% más lento) — `he4_t`, sin tocar, seguía marcando el camino crítico |
| [`optimizacion-vpot/`](optimizacion-vpot/) | Peso real de `vpot` antes/después del split de `derananum` (pasa a dominar el pipeline, 53-54%), y fusión `V_hehe`+`Vp_hehe` para evitar cómputo duplicado | **En producción** (fusión, ~8,6% más rápido) |
| [`optimizacion-vpot/mapa-sfu-produccion.md`](optimizacion-vpot/mapa-sfu-produccion.md) | Mapa completo de instrucciones SFU (`MUFU.RCP64H`/`RSQ64H`) leído del SASS real, filtrado a lo que de verdad ejecuta `opcion=7` — confirma que la SFU es solo división/raíz (nada de seno/coseno/exp en doble precisión) y que `He_dihydrogen` monolítica/`vpot`/`hpsi`/`dmc2` viejo no se ejecutan en producción | Diagnóstico — motiva atacar división antes que raíz (§6) |
| [`optimizacion-vpot/reciprocos-ex0-duhe4x.md`](optimizacion-vpot/reciprocos-ex0-duhe4x.md) | Recíproco cacheado en `Ex0`/`Ey0`/`Ez0` (`He_dihydrogen_induccion`) y en el bucle de `duhe4x` — no bit a bit en pruebas aisladas sintéticas, pero sí bit a bit idéntico en 4 semillas del pipeline completo; SFU/ciclos medidos con `ncu` (hasta −50% instrucciones XU, −20,6% ciclos en `k_derananum_resto_t`) | **En producción** |
| [`optimizacion-vpot/reciprocos-k-fase-h.md`](optimizacion-vpot/reciprocos-k-fase-h.md) | `k_fase_h` (histogramas): recíprocos de `dhr_h`/`dhc_h`/`dhs_h`/`dnor` + límites de bucle reescritos en términos de `nhe3` — histogramas radiales bit a bit idénticos, angulares con divergencia de último dígito aceptada; −78% instrucciones SFU estáticas, −49,7% instrucciones XU dinámicas, −26,1% ciclos; también incluye el control final acumulado contra CPU (4 semillas) | **En producción** |
| [`optimizacion-vpot/reciprocos-derwavefx.md`](optimizacion-vpot/reciprocos-derwavefx.md) | `derwavefx`: recíproco de `dnor` en el bloque `impurmol` (vector÷escalar repetido 3 veces) — bit a bit idéntico en 4 semillas; −67% `RCP64H` estáticas, impacto dinámico modesto (el bloque solo corre 3 veces por llamada). Descarta el mismo cambio para `wavefx` (divisor `dnor*rij` distinto cada iteración, sin redundancia) | **En producción** |
| [`optimizacion-vpot/reciprocos-v-and-vp-hehe.md`](optimizacion-vpot/reciprocos-v-and-vp-hehe.md) | `V_and_Vp_hehe`: 8 de 9 divisiones eran potencias de la misma `x` — un solo `1/x` cacheado sustituye todas por multiplicación; bit a bit idéntico en 4 semillas pese a ser el mayor número de divisiones sustituidas de golpe; −89% `RCP64H` estáticas, −59,6% instrucciones XU dinámicas y −19,1% ciclos en `k_vpot_3warp_t` (la mayor reducción dinámica de toda la línea de trabajo) | **En producción** |
| [`optimizacion-vpot/reciprocos-he-dihydrogen-dispersion.md`](optimizacion-vpot/reciprocos-he-dihydrogen-dispersion.md) | `He_dihydrogen_dispersion`: identifica `fi`/`drrdx`/`dfidx`/`dthetadx` como código muerto (DCE básica, sin `parameter` de por medio) y arregla los 4 recíprocos literales de `FN1` (`/6`,`/24`,`/120`,`/720`) — bit a bit idéntico en 4 semillas; −80% `RCP64H` estáticas (5→1), −8,7% instrucciones XU y −1,2% ciclos en `k_vpot_3warp_t` | **En producción** |
| [`optimizacion-vpot/log-rij-redundante.md`](optimizacion-vpot/log-rij-redundante.md) | `duhe4x`/`uhe4x`/`duhe3x`/`uhe3x`: `log(rij)` recalculado desde cero cuando `rij_hi` (de una llamada previa a `mypow_log`) ya vale exactamente eso — CSE puro, bit a bit garantizado por construcción, no una reformulación algebraica; confirmado bit a bit idéntico en 4 semillas; en `k_derananum_resto_t`: −20,0% ciclos, −23,1% FMA, −29,1% instrucciones XU (la mayor reducción de ciclos de toda la línea de trabajo) | **En producción** |
| [`optimizacion-vpot/reciprocos-wavef-derwavefhe4.md`](optimizacion-vpot/reciprocos-wavef-derwavefhe4.md) | `wavef_derwavefhe4` (versión fusionada real, no `wavefhe4`/`derwavefhe4` sueltas): recíproco cacheado para 2 divisiones repetidas por `rij` — bit a bit idéntico en 4 semillas; en `k_derananum_he4_t`: −6,7% ciclos, −4,0% FMA, −16,7% instrucciones XU | **En producción** |
| [`optimizacion-vpot/control-final-cpu-vs-gpu.md`](optimizacion-vpot/control-final-cpu-vs-gpu.md) | Cierre de la línea de trabajo: control físico completo CPU-vs-GPU (4 semillas, todos los fixes acumulados, compatibles dentro de 1,1σ), tiempos totales (~11,8x CPU/GPU con metodología limpia, con nota sobre la discrepancia frente a la batería `test-walker` antigua), y perfil final (registros/stall de warps/instrucciones) de los 5 kernels de física real — el stall dominante sigue siendo MIO/short-scoreboard (65-76%), reducido en magnitud pero no en naturaleza | Diagnóstico de cierre |

### Funciones matemáticas

Todo lo relacionado con funciones matemáticas bit-exactas (`mypow`/`myexp`/`angle`/`acos`).

| Carpeta | Qué investiga | Estado |
|---|---|---|
| [`funciones-matematicas/optimización-mypow/`](funciones-matematicas/optimización-mypow/) | Optimización real de `mypow`/`myexp` en el árbol (sustituye el tanteo temprano sin documentar de `prueba_mypow/`) | Base de mejoras ya en producción |
| [`funciones-matematicas/myexp-optimizacion/`](funciones-matematicas/myexp-optimizacion/) | `GTEST` fijo, `nhe3` fijo, cambios (a)/(b), combo final | **En producción** |
| [`funciones-matematicas/funciones-nativas-cuda/`](funciones-matematicas/funciones-nativas-cuda/) | Sustituir `myexp`/`mypow`/`mysin`/`mycos`/`myacos` portados por las funciones nativas de nvfortran; confirma que la SFU viene de las divisiones de `He_dihydrogen`, no de estas 5 funciones | **En producción** — 17-24% más rápido, bit a bit idéntico en 2 semillas |
| [`funciones-matematicas/fusion-angle-hehe/`](funciones-matematicas/fusion-angle-hehe/) | Fusión de `angle` con `vec_norm`+`scalar_product` en `He_dihydrogen` | **Negativo** — el ahorro de cómputo no compensa el aumento de registros |
| [`funciones-matematicas/wavefhe4-fusion-test/`](funciones-matematicas/wavefhe4-fusion-test/) | ¿Es la fusión `wavefhe4`+`derwavefhe4` la causante de que `derananum` no mejore? | **Negativo** — la fusión no es el problema |
| [`funciones-matematicas/prueba_mypow/`](funciones-matematicas/prueba_mypow/) | Tanteo temprano sin documentar, precursor de `optimización-mypow/` | Rastro histórico, no investigación activa |

### Corrección física

Hallazgos de corrección (no de rendimiento) encontrados mientras se optimizaba.

| Carpeta | Qué investiga | Estado |
|---|---|---|
| [`correccion-fisica/alineacion-semilla-walker1/`](correccion-fisica/alineacion-semilla-walker1/) | La semilla del walker 1 no coincidía entre GPU y CPU ni con N=1 | **En producción** |

## Ideas futuras

[`ideas-optimizacion-futuras.md`](ideas-optimizacion-futuras.md): backlog de vías identificadas pero no investigadas todavía (memoria compartida como scratchpad de spill en `vpot`, kernels persistentes, partir `vpot` en kernels concurrentes, la caída de aceleración del split a 3000w sin explicar).

## Ficheros / herramientas clave (reutilizar, no reinventar)

- `../v2-cuda-integracion/hibrido_instrumentado/dmc2_pipeline.cuf`: el pipeline de 7 fases, objetivo principal de optimización.
- `../v2-cuda-integracion/test-pasos/run_comparacion.py` (`genera_inmcv`): generación de configuraciones de prueba.
- `../v2-cuda-integracion/test-pasos/`, `test-walker/`, `test-bloques/`: metodología de prueba limpia ya validada (copiar el patrón para cualquier nueva batería).
- `../v1-cuda-desarrollo/docs-kernels/tiempo-ncu-resultado.md`, `arquitectura-streams-kin-pot.md`: perfilado y hallazgos previos (registro, warps, CUDA Graphs) — contexto histórico, pero su perfilado no es del pipeline actual (ver `perfilado-medicion/fase0-perfilado/`).
- `../v1-cuda-desarrollo/docs-kernels/derananum.md` Parte 9: el hallazgo del heap de `device`.

## Verificación (en cada investigación)

- Cambios de configuración de lanzamiento (bloques/threads): verificar resultado bit a bit idéntico (no cambia física).
- Cambios de fórmula/precisión: verificar contra la batería de pruebas del kernel afectado (mismo criterio GPU=CPU-`nvfortran`=`gfortran` ya usado en todo el árbol).
- Cada medida de rendimiento: con `ncu`/`nsys` reales, nunca inferida, con control de deriva térmica (rondas alternas) cuando la diferencia es pequeña.
