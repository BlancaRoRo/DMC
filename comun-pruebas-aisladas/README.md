# comun-pruebas-aisladas

`mwavef.f90`: instantánea de este fichero común a las 13 carpetas de prueba aislada de
`v1-cuda-desarrollo/` (ver `../README.md`) y usada por varias de ellas al compilar (ver los
comandos exactos en `../docs-kernels/`), de un punto del desarrollo anterior a las optimizaciones
finales. **No es la versión que llegó a producción** — esa es
`v2-cuda-integracion/hibrido_instrumentado/mwavef.f90`, y ya no coincide con esta. Se conserva
aquí (y no junto a `mtipos.f90`/`mrandom.f90`/`mrandom2.f90`, que sí son idénticos a los de
producción y por eso no se duplican en ningún sitio) porque hace falta para poder recompilar
estas pruebas históricas tal como eran en su momento.
