# Simulaciones

Las dos versiones "definitivas" del simulador DMC, sin el histórico de pruebas ni las
copias de trabajo de `v2-cuda-integracion/` — pensadas para que el código final sea
fácil de encontrar y de compilar, sin tener que buscarlo entre carpetas de
investigación. Ambas son solo código fuente + lo necesario para compilar y ejecutar
(sin `.o`/`.mod`/binarios ni resultados de corridas anteriores).

## `dmc-cpu/`

El código tal como se entregó inicialmente (copia de
[`v1-cuda-desarrollo/ccuerpo`](../v1-cuda-desarrollo/ccuerpo/)/`Original/`, sin portar a
CUDA), compilado con `gfortran`, **con el fix de `Vap` ya aplicado** en `bh_heh2m.f`:
en el potencial He-He (`Vp_hehe`), la variable `Vap` no se inicializaba fuera de la
ventana `[xx1_HeHe, xx2_HeHe]`, quedando con lo que hubiera en memoria en ese momento
(ver `v3-cuda-optimización/optimizacion-vpot/V_hehe_Vp_hehe.md` Sec. 5). El fix
recupera la intención original que ya sugería el propio código con un
`!Vap=0.d0` comentado, sin tocar ninguna otra fórmula.

Es el binario de referencia contra el que se ha verificado, en todo el proyecto, que
la versión GPU da la misma física.

**Compilar y ejecutar**:
```bash
./compilar_gfortran.sh
./qmccluster < in.mcv
```

## `dmc-hibrido/`

El código híbrido final, con todas las optimizaciones GPU del proyecto ya integradas
(copia de [`v2-cuda-integracion/hibrido_instrumentado`](../v2-cuda-integracion/hibrido_instrumentado/)),
recortado a solo las vías que de verdad hacen falta:

- **El mismo fix de `Vap`** que `dmc-cpu`, aplicado aquí también (`hibrido_instrumentado`
  real no lo tenía todavía -- se ha portado en esta limpieza).
- **El código `dmc` original en CPU se mantiene integrado** en el mismo binario
  (`opcion=4`) como referencia/comparación, junto al pipeline GPU -- no es un binario
  aparte.
- **El fix de colapso de población**: si en un paso DMC mueren *todos* los walkers a
  la vez (`nwfin=0` -- se ha visto en la práctica arrancando con muy pocos walkers,
  p. ej. 1), `log(nwnew/nwold)` da `log(0)`, que sin este chequeo se propagaría en
  silencio como `NaN`/`Inf` en los pasos siguientes. El pipeline lo detecta, para la
  ejecución con un mensaje explícito y escribe un volcado forense
  (`snapshot_colapso.dat`) del estado justo antes del colapso, en vez de seguir
  calculando sobre datos inválidos. No es un "tope" de población -- es una comprobación
  defensiva ante el caso límite nwfin=0, que sí puede pasar de verdad (fluctuación
  estadística normal del método DMC, más probable cuanto menor es la población).
- **Las opciones antiguas 5 y 6** (`dmc_gpu`/`pasodmc_gpu` y
  `dmc_cpu_gpurand`/`pasodmc_cpu_gpurand`) se han eliminado -- eran vías de
  verificación intermedias, ya superadas por el pipeline y documentadas en
  `docs/hibrido.md`. **La opción 7 (el pipeline de producción) pasa a ser la opción 5.**
  Opciones finales: `0`=test der, `1`=mcv, `2`/`3`=optimiza, `4`=dmc (CPU), `5`=dmc-gpu-pipeline.
- Se conservan las 3 herramientas de diagnóstico forense (`driver_diagnostico.f90`,
  `driver_replay.f90`, `driver_verifica_prereparto.f90`) -- no dependen de las opciones
  eliminadas, sirven para depurar el propio pipeline.

Verificado bit a bit tras la limpieza: con `opcion=5`, la energía final coincide
exactamente con la que daba el binario original (`hibrido_instrumentado`) con
`opcion=7` antes de tocar nada (`-622.9201974824`).

**Compilar y ejecutar** (el pipeline GPU):
```bash
./compilar_pipeline.sh
./qmccluster_pipeline < in.mcv
```
