# Tiempos por método: CPU original vs. GPU con todas las mejoras

## Objetivo

Repetir, con el pipeline actual (todas las mejoras de esta sesión ya aplicadas: seed decorrelation, `sincroniza_constantes_gpu`/`etrial`, `k_fase_h`, reducción AoS↔SoA), el mismo tipo de análisis que en su momento justificó portar `pasodmc` a CUDA (memoria del TFG, `04b_AnalisisImplementacionCUDA.tex`: *"pasodmc concentra más del 95% del tiempo total de ejecución"*, medido sobre el código CPU original).

Dos preguntas concretas:
1. **¿Cuánto ha bajado el peso de `pasodmc`** (ahora `pasodmc_gpu_pipeline`) frente al 95%+ original?
2. **¿Hay algún otro método (de los ~20 que llama `mmontecarlo.f90`) que se haya vuelto relevante** ahora que `pasodmc` pesa menos — algo que antes era ruido y ahora no?

## Metodología

- **Dos copias aisladas**, dentro de esta misma carpeta, para no tocar ni el código de referencia validado ni el pipeline en uso en el resto de la sesión:
  - `cpu-original-instrumentado/`: copia de `../../v2-cuda-integracion/cpu-original-gfortran/` (CPU, `gfortran`, código original sin portar).
  - `gpu-mejorado-instrumentado/`: copia de `../../v2-cuda-integracion/hibrido_instrumentado/` (GPU, pipeline con todas las mejoras).
- **Misma configuración exacta en ambas**: 1.000 walkers, 1 bloque de equilibrio, 59 bloques de cálculo, 20 pasos/bloque (1.180 pasos totales), semilla 11, `conf.20.00.HH` fresco antes de cada corrida — mismo patrón que `test-walker`/`test-pasos`.
- **Dónde se ponen los prints (cronometraje)**: `system_clock` puro, envolviendo **cada llamada individual** dentro de `dmc` (CPU, `cpu-original-instrumentado/mmontecarlo.f90`) y `dmc_gpu_pipeline` (GPU, `gpu-mejorado-instrumentado/mmontecarlo.f90`) — literalmente antes y después de cada `call`, acumulando en una variable `t_<metodo>` propia. Al final de la subrutina se escribe un fichero `tiempos_metodos_dmc.dat` con cada método, su tiempo total y su porcentaje sobre la suma de todos los métodos cronometrados. Instrumentación añadida solo a estas dos copias — no toca `mtiempos.f90` ni ningún fichero compartido con el resto del proyecto.
- **Métodos cronometrados** (los mismos ~20 en ambas copias, para que la tabla sea comparable línea a línea): `iniimagina`, `dmcnumprop`, `densgethis`, `difusgethis`, `dmcescrini`, `dmcceroini`, `densceroini`, `difusceroini`, `dmcceroblo`, `densceroblo`, `difusceroblo`, `difusfijaorigen`, `pasodmc`/`pasodmc_gpu_pipeline`, `dmcsumapaso`, `denssumapaso` (o su equivalente GPU), `difussumapaso`, `dmcsumablo`, `denssumablo`, `difussumablo`, `dmcescrblopar`, `dmcsumaproc`, `denssumaproc`, `difussumaproc`, `dmcsumafin`, `dmcescrfin`, `denssumafin`, `densescrfin`, `difusfin`.
- **Nota sobre `denssumapaso` en la vía GPU**: ya no existe como llamada por paso — su trabajo se fusionó dentro de `pasodmc_gpu_pipeline` (`k_fase_h`, GPU, ver `aos-to-soa.md`). Lo que queda como línea separada es `resetea_histogramas_gpu` (una vez por bloque, antes del bucle de pasos) y `vuelca_histogramas_gpu` (una vez por bloque, después) — no son comparables 1:1 con la `denssumapaso` de la CPU (que se llama una vez por PASO), así que en la tabla de resultados se marcan aparte en vez de sumarlas a `pasodmc`.

## Resultado

1.000 walkers, 59 bloques de cálculo × 20 pasos (1.180 pasos), semilla 11. Sin errores, sin NaN, 1.000 walkers finales en ambas. Energías estadísticamente compatibles (CPU: -678,11 ± 1,91 meV; GPU: -679,34 ± 2,02 meV — dentro de 1σ, como en todo el resto de la sesión).

| Método | CPU (`gfortran`, original) | GPU (pipeline, todas las mejoras) |
|---|---|---|
| **`pasodmc` / `pasodmc_gpu_pipeline`** | **81,1486 s (97,394%)** | **45,0833 s (94,866%)** |
| `denssumapaso` (CPU, por paso) | 2,0182 s (2,422%) | *(ver nota abajo)* |
| `difusceroblo` | 0,0403 s (0,048%) | 0,0855 s (0,180%) |
| `difussumapaso` | 0,0282 s (0,034%) | 0,0913 s (0,192%) |
| `densescrfin` | 0,0498 s (0,060%) | 0,0244 s (0,051%) |
| `resetea_histogramas_gpu` — arranque CUDA (1 sola vez, la primera llamada) | — | 0,4075 s (0,857%) |
| `resetea_histogramas_gpu` — coste real (59 llamadas restantes) | — | 0,0060 s (0,013%) |
| `vuelca_histogramas_gpu` (nuevo, GPU, por bloque) | — | 0,0182 s (0,038%) |
| Resto (`iniimagina`, `dmcnumprop`, `densgethis`, `difusgethis`, `dmcescrini`, `dmcceroini`, `densceroini`, `difusceroini`, `dmcceroblo`, `densceroblo`, `difusfijaorigen`, `dmcsumapaso`, `dmcsumablo`, `denssumablo`, `difussumablo`, `dmcescrblopar`, `dmcsumaproc`, `denssumaproc`, `difussumaproc`, `dmcsumafin`, `dmcescrfin`, `denssumafin`, `difusfin`) | < 0,03 s combinado | < 0,03 s combinado |
| **Total instrumentado** | **83,3199 s** | **47,5232 s** (con `resetea_histogramas_gpu` re-medido con NVTX; el 2,1780 s de la primera pasada quedó sustituido por estas 2 filas, ver nota) |

**Aceleración de `pasodmc` en sí: 1,80x** (81,15 s → 45,08 s). **Aceleración total: 1,75x** — consistente con las mediciones de `test-walker` a esta escala (1,72x en `fase2-medicion-mejoras.md`, dentro del margen de variación entre corridas).

**Nota sobre `resetea_histogramas_gpu` (medición con marcadores NVTX, mismo `in.mcv` exacto — ver `prueba_reset_histogramas/prueba_reset_histogramas.md` §4)**: de las 60 llamadas, **una sola** (la primera, la del bloque de equilibración) tarda 407,5 ms; las otras 59 tardan de media **101 microsegundos** cada una (mínimo 62 µs, máximo 150 µs) — coherente con la prueba aislada (0,02 ms) y con `nsys` a nivel de kernel (~90 µs/bloque). El "36,3 ms/llamada" original (`system_clock`, primera medición) era la media de 1 coste de arranque de CUDA (una sola vez) repartido entre 60 llamadas — el mismo tipo de espejismo que ya se documentó para `sincroniza_globales_gpu` en la Fase 3, aquí aplicado a un tipo de operación distinta (asignación de array a cero, no `cudaMemcpyToSymbol`). `resetea_histogramas_gpu` no tiene ningún coste real que arreglar.

## Respuesta a las 2 preguntas

**1. ¿Cuánto ha bajado el peso de `pasodmc`?** De >95% (memoria del TFG, código original antes de portar nada) a **97,4% en la CPU actual / 94,9% en la GPU actual**. Nótese que el peso relativo en la CPU **no ha cambiado** respecto al análisis original (sigue siendo ~97%, coherente con el 95%+ de entonces) — lo que ha cambiado es que ahora existe una segunda columna (GPU) donde ese mismo trabajo cuesta 1,80x menos en segundos absolutos. El peso relativo de `pasodmc` baja solo 2,5 puntos porcentuales (97,4%→94,9%) porque casi todo el "resto" también se ha ido reduciendo o migrando dentro del propio `pasodmc_gpu_pipeline` (ver `k_fase_h`).

**2. ¿Hay algún método que se haya vuelto relevante?** Se investigó a fondo `resetea_histogramas_gpu` (2,18 s, 4,58% del total GPU — más, en términos relativos, de lo que costaba `denssumapaso` en la CPU original antes de arreglarla). **Resultado: era un artefacto de medición, no un coste real** — ver `prueba_reset_histogramas/prueba_reset_histogramas.md` para la investigación completa. `nsys` confirma que el trabajo real de GPU de esa función es de ~90 microsegundos en total (6 bloques), no milisegundos: los 34,5 ms/llamada de `cudaStreamSynchronize` que dominan el tiempo de CUDA en esa zona pertenecen a `lanza_pipeline` (el kernel de física real), no a `resetea_histogramas_gpu`. Durante esa investigación, `compute-sanitizer` sí encontró algo real y distinto (no relacionado con esta pregunta): el problema de heap de `device` ya conocido de `derananum.md` Parte 9, reactivado por la sobrecarga de memoria del propio sanitizer — documentado en el mismo fichero, dejado pendiente por decisión explícita, no afecta a ningún resultado de esta sesión.

## Ficheros

- `cpu-original-instrumentado/`, `gpu-mejorado-instrumentado/`: **recortadas** a `mmontecarlo.f90` (el fichero con la instrumentación real, `system_clock` envolviendo cada `call`), `in.mcv` (config exacta usada) y los resultados (`.dat`/`.log`) -- ya no son copias completas compilables por sí solas (originalmente copiaban `../../v2-cuda-integracion/cpu-original-gfortran/` y `hibrido_instrumentado/` enteros). Para recompilar de cero, copiar `mmontecarlo.f90` sobre una copia fresca de la referencia correspondiente.
- `gpu-sin-kfaseh-instrumentado/`: copia de diagnóstico de `prueba_reset_histogramas/` (Fase H desactivada, heap subido a 2GB para probar) -- recortada igual, a `mmontecarlo.f90`+`dmc2_pipeline.cuf`+`in.mcv`+resultados.
- `compilar_gpu_mejorado.sh`, `compilar_gpu_sin_kfaseh.sh`: compilan las copias GPU (apuntan a las carpetas de arriba -- ya no funcionan tal cual tras el recorte, sirven de referencia de qué `FILES` se usaban). La CPU usa su propio `compilar_gfortran.sh`.
- `tiempos_metodos_dmc.dat`, `run_*.log`, `tiempos_opcion*.dat`: resultados crudos de cada copia.
