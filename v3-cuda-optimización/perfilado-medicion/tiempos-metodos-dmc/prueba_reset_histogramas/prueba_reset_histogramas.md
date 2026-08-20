# Investigación: `resetea_histogramas_gpu` (36 ms/llamada, 4,58% del total GPU)

Punto de partida (`tiempos-metodos-dmc.md`): `resetea_histogramas_gpu` — una función que solo pone a cero 12 arrays de device (~620 KB en total) una vez por bloque — costaba 2,18 s (4,58% del total) en la medición method-by-method, proporcionalmente más que `denssumapaso` en la CPU original (2,42%) antes de arreglarla. Candidato sospechoso: 12 asignaciones de array separadas, cada una quizás un lanzamiento de kernel independiente con su propio gasto fijo.

## 1. Prueba aislada: la hipótesis de los "12 lanzamientos caros" no se sostiene

`test_reset.cuf`: mismo tamaño total (620 KB en 12 arrays), comparando 12 asignaciones separadas (versión A, igual que el código real) contra 1 solo kernel combinado (versión B), 60 repeticiones (igual que el nº de bloques real):

```
version A (12 asignaciones separadas): 0.0223 ms/rep
version B (1 kernel combinado):        0.0041 ms/rep
factor de mejora: 5.47x
```

Real, pero **~1.600 veces más pequeño** que los 36,3 ms/llamada medidos en producción — no explica ni de lejos la magnitud del problema.

## 2. `nsys`: el trabajo real de GPU es de microsegundos, no milisegundos

Perfilado de una corrida corta (1.000 walkers, 5 bloques) con `nsys profile --trace=cuda,osrt`:

- Los kernels `__pgi_dev_cumemset_16n`/`__pgi_dev_cumemset_8n` (el reset real, 84 instancias en 6 bloques): **~1 µs cada uno, ~90 µs en total**.
- Los 104 `cudaStreamSynchronize` (34,5 ms de media cada uno, 3,58 s en total, 94,8% de toda la API CUDA) coinciden en número **exacto** con los 104 `cudaGraphLaunch` — son de `lanza_pipeline` (el kernel de física real), no de `resetea_histogramas_gpu`.

**Conclusión: la medición original de 36 ms/llamada era un artefacto de la instrumentación `system_clock`, no coste real de GPU.** `resetea_histogramas_gpu` no es ni ha sido nunca un problema de rendimiento — se corrige la nota en `tiempos-metodos-dmc.md`.

## 3. `compute-sanitizer`: mientras se investigaba lo anterior, apareció algo real y distinto

Al correr la misma configuración corta bajo `compute-sanitizer --tool memcheck`, el programa **falla** (`cudaErrorLaunchFailure`, "unspecified launch failure") — algo que nunca pasa en ejecución normal (toda la sesión, hasta 3.000 walkers, sin un solo fallo).

### Aislamiento paso a paso

1. **¿Es `k_fase_h` (lo añadido hoy)?** No — copia idéntica con `k_fase_h` desactivada (comentada en la captura del grafo) falla exactamente igual.
2. **¿Es el heap de `device` (512 MB)?** Parcialmente sí, pero no solo tamaño — con el heap a 2 GB (4x) **sigue fallando**, con el mismo aviso repetido 100 veces.
3. **¿Dónde exactamente?** Con `--show-backtrace=device` (necesita `-gpu=lineinfo`, ya activo en la compilación):
   ```
   Malloc/Free Warning encountered : Empty malloc
     at mderananum_derananum_+0x990 in derananum_mod.cuf:136
     Device Frame: mdmc2_pipeline_k_derananum_t_+0xce0 in dmc2_pipeline.cuf:381
   ```

### Diagnóstico final

Es el **mismo problema ya documentado en `derananum.md` Parte 9** (heap de `device` agotado): `derananum` declara arrays locales de tamaño variable (`d1wfhe4(nhe4)`, `d1wfx(natom)`, etc. — `derananum_mod.cuf:148-149`), que al no conocerse en tiempo de compilación se reservan dinámicamente del heap compartido de 512 MB, uno por cada hilo que llama a `derananum`. Con miles de hilos a la vez, se agota.

En ejecución normal esto solo pasa por encima de ~3.500 walkers (`test-walker.md`). `compute-sanitizer` añade tanta memoria de instrumentación por hilo que el mismo límite se agota a 1.000 walkers — ni con el heap a 2 GB fue suficiente margen para el sanitizer.

**No es un fallo introducido en esta sesión** (confirmado: ocurre igual con y sin `k_fase_h`, y con y sin las reducciones AoS↔SoA no llegó a hacer falta comprobarlas por separado una vez descartado `k_fase_h` y el heap). Es un riesgo real y ya conocido, pero no afecta a ningún resultado de esta sesión (nunca se ha llegado a esa escala en las pruebas hechas).

## 4. Medición precisa: marcadores NVTX en la corrida original exacta

Las pruebas 1 y 2 ya demostraban que el trabajo real de GPU es de microsegundos, pero no explicaban por qué el `system_clock` original (`tiempos-metodos-dmc.md`) medía 36,3 ms/llamada de media. Para saberlo con precisión, sin adivinar: se añadieron marcadores `nvtxRangePush`/`nvtxRangePop` (módulo `nvtx` de `nvfortran`, enlazando `libnvhpcwrapnvtx`) alrededor de `resetea_histogramas_gpu` y `pasodmc_gpu_pipeline`, y se perfiló con `nsys --trace=cuda,osrt,nvtx` la **misma configuración exacta** donde se midieron los 36,3 ms/llamada (1.000 walkers, 59 bloques de cálculo).

```
Range                     Instances  Avg (ns)     Med (ns)   Min (ns)  Max (ns)
pasodmc_gpu_pipeline           1184  38.974.862   39.023.846 35.018.743 57.439.728
resetea_histogramas_gpu          60   6.891.399      103.224     62.316 407.517.553
```

La media (6,89 ms) y la mediana (103 µs) de `resetea_histogramas_gpu` son radicalmente distintas — señal inequívoca de que unos pocos valores extremos están arrastrando la media. Mirando las 60 llamadas una a una: **la primera** (bloque de equilibración, la primerísima de toda la corrida) tarda **407,5 ms**; las otras 59 tardan de media **101 µs** (mínimo 62 µs, máximo 150 µs).

```
407.517.553 ns / 6,0 ms (suma de las otras 59) / total 413,5 ms
```

**Diagnóstico definitivo**: es el mismo fenómeno de arranque perezoso de CUDA ya documentado en la Fase 3 (`fase3-arquitecturas-alternativas.md`, `prueba_arranque_cuda/test_arranque.cuf`: la primera vez que se usa un tipo de operación de CUDA, el driver/runtime hace trabajo de inicialización de una sola vez) — allí se vio con `cudaMemcpyToSymbol` (270-350 ms), aquí con la asignación de array a cero a device (`h44_p=0.0_r8` etc.), un tipo de operación distinta que aún no se había "tocado" antes de la primera llamada a `resetea_histogramas_gpu`. El "36,3 ms/llamada" de la medición original no era un coste real repartido en 60 llamadas — era 1 coste de arranque (~400 ms-2 s, con variación normal entre corridas) diluido en la media de 60. **`resetea_histogramas_gpu` no tiene ningún coste real que arreglar.**

## Pendiente (no implementado, decisión explícita de dejarlo aparcado)

El arreglo de fondo ya estaba identificado desde `derananum.md` Parte 9, "Opción 3" (nunca implementada): convertir los arrays locales de `derananum` (`d1wfhe4`, `d1wfhe3`, `d1wfm`, `d1wfx`, `d2wfhe4`, `d2wfhe3`, `d2wfm`, `d2wfx`) a tamaño **fijo** (mismo patrón que `atom_l(64)` en `k_derananum_t`/`k_fase_h`), eliminando la dependencia del heap de `device` en esta subrutina por completo — no solo agrandar el límite, sino no necesitarlo. Queda pendiente para una futura sesión si se decide abordarlo.

## Ficheros

- `test_reset.cuf`, `test_reset`: prueba aislada (12 asignaciones vs. 1 kernel combinado).
- `../gpu-mejorado-instrumentado/mmontecarlo.f90`: marcadores `nvtxRangePush`/`nvtxRangePop` alrededor de `resetea_histogramas_gpu` y `pasodmc_gpu_pipeline` (permanentes, no estorban en ejecución normal sin profiler).
- `../compilar_gpu_mejorado.sh`: enlaza `-lnvhpcwrapnvtx` para las marcas NVTX.
- Logs de `nsys` y `compute-sanitizer` generados durante la investigación (en `/tmp`, no copiados aquí por ser de un solo uso diagnóstico).
