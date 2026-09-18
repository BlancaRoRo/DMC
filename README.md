# Fase 2: Integración

Con los kernels ya portados y verificados por separado en `fase1-transcripción`, aquí
se consolidan en un único binario híbrido y se miden sus tiempos frente al código
original, en escalas cada vez mayores.

## Contenido

- **`cpu-original-gfortran/`**: el código CPU original, sin portar a CUDA, compilado
  con `gfortran` -- la referencia contra la que se compara todo el resto.
- **`hibrido_instrumentado/`**: el pipeline GPU de producción real (`opcion=7`), con
  instrumentación de tiempos añadida para las baterías de esta carpeta.
- **`docs/`**: 4 documentos de la fase de ensamblado híbrido -- `hibrido.md` (la hoja
  de ruta completa de "juntar todo en un único binario", 5 pasos), `hallazgo-cuda-host.md`
  (una diferencia de resultados que parecía venir de CUDA y resultó ser un fichero de
  configuración mutado entre pruebas), `test-metodos-antes.md` (verificación de que
  compilar la orquestación original con `nvfortran` da lo mismo que con `gfortran`).
- **`test-walker/`**: batería de escalado variando solo el número de *walkers*
  (bloques y pasos fijos), comparando la versión original frente a la optimizada.
- **`test-pasos/`**: la misma idea variando el número total de pasos DMC. Es además
  la prueba de cierre de la investigación de rendimiento de `test-tiempos/`, a mayor
  escala (1000 walkers).
- **`test-bloques/`**: la misma idea variando la granularidad del bloque (pasos por
  bloque), con el número de bloques fijo.
- **`test-tiempos/`**: la investigación de rendimiento propiamente dicha, en 3
  documentos -- primera comparación de tiempos CPU/GPU
  (`test-tiempos-proceso.md`), perfilado de `k_dmc2` con Nsight Compute
  (`tiempo-ncu-resultado.md`), y una propuesta de arquitectura con streams separados
  para cinética y potencial (`arquitectura-streams-kin-pot.md`).
