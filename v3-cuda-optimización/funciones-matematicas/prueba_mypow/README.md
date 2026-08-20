# prueba_mypow (borrador temprano, sin documentar en su momento)

Primer tanteo (17 agosto, antes que `optimización-mypow/`) de sustituir
`mypow` por la intrínseca nativa de CUDA. No se documentó como investigación
formal en su momento -- lo que salió de aquí se investigó de verdad y quedó
documentado como es debido en [`../optimización-mypow/`](../optimización-mypow/).

Se conserva recortado (solo los ficheros editados) como rastro histórico,
no como investigación activa.

## Ficheros

- `gpu-pow-rapido/glibc_pow.cuf`: el cambio probado (pow nativa en vez de `mypow`).
- `verificacion_valores/`: comparación aislada GPU vs. `gfortran` de valores de `pow`.
