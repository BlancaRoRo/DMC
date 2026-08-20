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
| [`arquitectura-lanzamiento/derananum-split-concurrente/`](arquitectura-lanzamiento/derananum-split-concurrente/) | Split de `derananum` en 3 kernels concurrentes (He4/resto/cierre) + arreglo de bucles `ngatom→nhe3` | Positivo (~2,6x en 500-2000w), no migrado a producción todavía |

### Funciones matemáticas

Todo lo relacionado con funciones matemáticas bit-exactas (`mypow`/`myexp`/`angle`/`acos`).

| Carpeta | Qué investiga | Estado |
|---|---|---|
| [`funciones-matematicas/optimización-mypow/`](funciones-matematicas/optimización-mypow/) | Optimización real de `mypow`/`myexp` en el árbol (sustituye el tanteo temprano sin documentar de `prueba_mypow/`) | Base de mejoras ya en producción |
| [`funciones-matematicas/myexp-optimizacion/`](funciones-matematicas/myexp-optimizacion/) | `GTEST` fijo, `nhe3` fijo, cambios (a)/(b), combo final | **En producción** |
| [`funciones-matematicas/fusion-angle-hehe/`](funciones-matematicas/fusion-angle-hehe/) | Fusión de `angle` con `vec_norm`+`scalar_product` en `He_dihydrogen` | **Negativo** — el ahorro de cómputo no compensa el aumento de registros |
| [`funciones-matematicas/wavefhe4-fusion-test/`](funciones-matematicas/wavefhe4-fusion-test/) | ¿Es la fusión `wavefhe4`+`derwavefhe4` la causante de que `derananum` no mejore? | **Negativo** — la fusión no es el problema |
| [`funciones-matematicas/prueba_mypow/`](funciones-matematicas/prueba_mypow/) | Tanteo temprano sin documentar, precursor de `optimización-mypow/` | Rastro histórico, no investigación activa |

### Corrección física

Hallazgos de corrección (no de rendimiento) encontrados mientras se optimizaba.

| Carpeta | Qué investiga | Estado |
|---|---|---|
| [`correccion-fisica/alineacion-semilla-walker1/`](correccion-fisica/alineacion-semilla-walker1/) | La semilla del walker 1 no coincidía entre GPU y CPU ni con N=1 | **En producción** |

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
