# Investigación float vs double — `wavef_derwavefhe4`

Ficheros editados de la reconstrucción aislada usada para `benchmark-float-vs-double.md`, `float-wavef-derwavefhe4-validacion.md` y `stall-float-vs-double-derananum-he4.md` (`v3-cuda-optimización/optimizacion-vpot/`). **No es una copia completa compilable por sí sola** — mismo criterio que `optimizacion-vpot/fusion-v-vp-hehe/`: copiar estos 4 ficheros sobre una copia fresca de `v2-cuda-integracion/hibrido_instrumentado/` para reconstruir el experimento.

## Qué contiene cada fichero

- **`der_wavefhe4_mod.cuf`**: añade `wavef_derwavefhe4_float` (Opción 3, ver `float-wavef-derwavefhe4-validacion.md` §4c: el `log()`/`exp()` de cada par se mantiene en `real(kind=4)` -- hardware nativo `MUFU` --, pero el acumulador `ujas_d` y la salida `wfhe4` son `real(kind=r8)`, eliminando por construcción el riesgo de desbordamiento de `float32`), más los contadores de diagnóstico de rango real (`ujas_d_min_visto`/`ujas_d_max_visto` en doble, `rijp2_min_visto`/`rijp2_max_visto` en `float`, `n_wfhe4_no_finito`) y las subrutinas `inicializa_diagnostico_float()`/`lee_diagnostico_float()` para leerlos desde el host. `wavef_derwavefhe4` original (`double`) se deja intacta, como referencia.
- **`derananum_split_mod.cuf`**: añade `k_derananum_he4_float_t` — mismo kernel que `k_derananum_he4_t`, pero llamando a la versión en `float`/`double` mixta de arriba; `wfhe4_l` ya es `real(kind=r8)`, se escribe directo sin conversión (`wfhe4_s(i) = wfhe4_l`).
- **`dmc2_pipeline.cuf`**: las 2 llamadas del grafo (una por horquilla) sustituidas de `k_derananum_he4_t` a `k_derananum_he4_float_t`.
- **`mmontecarlo.f90`**: llama a `inicializa_diagnostico_float()` antes del bucle de bloques y a `lee_diagnostico_float()` al final de `dmc_gpu_pipeline`, para que el diagnóstico se imprima junto al resto del resumen de la corrida.

## Cómo reconstruir el experimento

```bash
mkdir -p /tmp/float-vs-double-test
cp -r v2-cuda-integracion/hibrido_instrumentado/. /tmp/float-vs-double-test/
cp v3-cuda-optimización/optimizacion-vpot/investigacion-float-vs-double/*.cuf v3-cuda-optimización/optimizacion-vpot/investigacion-float-vs-double/*.f90 /tmp/float-vs-double-test/
cd /tmp/float-vs-double-test
./compilar_pipeline.sh
```

## Estado y próximos pasos

**Protección de `ujas` (Opción 3) implementada y verificada** — ver `float-wavef-derwavefhe4-validacion.md` §4c/§5. Resumen de lo pendiente:

1. ~~Ajustar el clip / proteger `ujas`~~ — resuelto: `ujas` se acumula en `double`, ya no puede tocar los límites de `float32`, verificado a 10.000 pasos con energía bit a bit idéntica y cero valores no finitos.
2. Buscar un segundo método candidato de coste comparable (`wavefx` es el natural, misma forma algebraica).
3. Decidir si esta línea (`wavef_derwavefhe4` en float/double mixto) se lleva a producción.
4. Benchmark real en la Tesla V100 (`v4-cuda-pruebas/v100-fp64-nativo/`, Paso 2) — confirmado que tampoco tiene hardware nativo de `exp`/`log` en doble, pendiente de medir si el ratio `float`/`double` cambia por su mejor throughput de FP64 básico.
