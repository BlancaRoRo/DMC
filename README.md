# v1-cuda-desarrollo

Primera fase del portado a CUDA Fortran: verificación aislada método a método, siguiendo la
estrategia descrita en la memoria (`Memoria-TFG`/`TFG_Blanca_Overleaf`, capítulo "Desarrollo del
modelo DMC en HPC", sección "Estrategia Seleccionada" — empezar por los nodos hoja del árbol de
llamadas de `pasodmc` e ir subiendo hasta la raíz, verificando cada método por separado antes de
integrarlo).

Cada subrutina se portaba y se comprobaba dentro de su propia carpeta, copiando ahí el
código base completo (Makefiles, todos los módulos, `conf.20.00.HH`, `in.mcv`...) para poder
compilar y ejecutar esa prueba de forma aislada. Esto dejaba **decenas de copias idénticas del
mismo código base repartidas por 13 carpetas** — más de 650 ficheros duplicados sin ningún
contenido propio de la prueba en cuestión. Las carpetas se han recortado a solo lo que cada una
aporta de verdad; el resto (recuperable en el historial de git si hiciera falta) se referencia
desde aquí.

## Estructura actual

- **`Original/`** (en la raíz del repositorio): el código CPU de partida, sin tocar. Es la base
  sobre la que se reconstruye cualquiera de las pruebas de abajo.
- **`glibc_math/`**: las aproximaciones por software de `exp`/`log`/`pow`/`sincos`/`acos` (y sus
  tablas) que usan casi todos los kernels de este directorio, en un único sitio.
- **`comun-pruebas-aisladas/`**: `mwavef.f90`, una instantánea de este fichero común a varias de
  las 13 carpetas recortadas (usada al compilarlas, ver más abajo), de un punto del desarrollo
  anterior a las optimizaciones finales — la versión que sí llegó a producción vive en
  `v2-cuda-integracion/hibrido_instrumentado/mwavef.f90` y ya no coincide con esta.
- **`dmc2/`** y **`hpsi/`**: las dos carpetas de integración (varios kernels ya juntos, no una
  prueba de un único método) — no se han tocado, siguen siendo copias completas, y ahora además
  son la referencia canónica de varios módulos `_mod.cuf` que se explican abajo.
- **`docs-kernels/`**: un `.md` por kernel con la explicación completa del portado y, en la
  sección "Cómo ejecutarlo"/"Resultado real", los comandos exactos de compilación usados
  (`nvfortran -cuda ...`/`gfortran ...`, fichero a fichero, sin `Makefile` de por medio). Es la
  referencia real para reconstruir cualquiera de las 13 pruebas — la tabla de abajo solo dice qué
  ficheros hacen falta reunir antes de esos comandos. Incluye además
  [`dmc2-call-graph.html`](docs-kernels/dmc2-call-graph.html), el árbol de llamadas completo de
  `dmc2` (diagrama interactivo + leyenda de qué está listo para GPU, bloqueado por el generador
  aleatorio o fuera de alcance, y el orden de ataque seguido) — ábrelo directamente en el
  navegador.

## Ficheros comunes a varias pruebas de la tabla

Antes de seguir los comandos de compilación de `docs-kernels/<carpeta>.md`, hace falta reunir en
el mismo sitio los ficheros propios de esa carpeta (ver tabla) más, según el caso, una copia
fresca de `Original/`, `v2-cuda-integracion/hibrido_instrumentado/{mtipos.f90,mrandom.f90,mrandom2.f90}`
(idénticos a los de producción, no se duplican aquí), `comun-pruebas-aisladas/mwavef.f90`, los
ficheros de `glibc_math/` que le hagan falta, o algún `_mod.cuf` de `dmc2/`.

## Las 13 pruebas

| Carpeta | Doc con los comandos exactos | Qué prueba | Propio de la carpeta | Depende también de |
|---|---|---|---|---|
| `angle_scalar_vec/` | [`docs-kernels/angle_scalar_vec.md`](docs-kernels/angle_scalar_vec.md) | Versión vectorial de `angle`/`scalar_product`/`vec_norm` (`He_dihydrogen`) | `angle_scalar_vec.cuf`, `test_angle_gfortran.f90` | `glibc_math/`: `asincos_tab_fortran.txt`, `exp_tab_fortran.txt`, `glibc_acos.cuf`, `glibc_exp_mod.cuf`, `inroot_fortran.txt`, `powtwo_fortran.txt` |
| `calpleg-calderpleg/` | [`docs-kernels/docs-calpleg-calderpleg.md`](docs-kernels/docs-calpleg-calderpleg.md) | Polinomios de Legendre y su derivada (`k_calpleg`, ejemplo detallado en la memoria) | `legendre_gpu.cuf`, `test_legendre_gfortran.f90` | — |
| `ccuerpo/` | [`docs-kernels/ccuerpo.md`](docs-kernels/ccuerpo.md) | Cuerpo principal (`ccuerpo`) | `ccuerpo.cuf`, `test_ccuerpo_gfortran.f90` | — |
| `derananum/` | [`docs-kernels/derananum.md`](docs-kernels/derananum.md) | Orquestador `derananum` (llama a `wavef`/`derwavef*`) | `derananum.cuf`, `derananum_mod.cuf`, `test_derananum_gfortran.f90`, `test_wavefm.cuf`, `test_wavefm_gfortran.f90` | `glibc_math/`: `exp_tab_fortran.txt`, `glibc_exp_mod.cuf`, `glibc_pow.cuf`, `pow_log_tab_fortran.txt` · `dmc2/`: `d_uhex4_mod.cuf`, `der_wavefhe4_mod.cuf`, `der_wavefx_mod.cuf`, `mlegendre_gpu.cuf` · `wavef/wavef_mod.cuf` |
| `der_wavefhe4/` | [`docs-kernels/der_wavefhe4.md`](docs-kernels/der_wavefhe4.md) | Derivada de `wavefhe4` | `der_wavefhe4.cuf`, `test_derwavefhe4_gfortran.f90` | `glibc_math/`: `exp_tab_fortran.txt`, `glibc_exp_mod.cuf`, `glibc_pow.cuf`, `pow_log_tab_fortran.txt` |
| `der_wavefx/` | [`docs-kernels/der_wavefx.md`](docs-kernels/der_wavefx.md) | Derivada de `wavefx` (impureza-He4) | `der_wavefx.cuf`, `test_derwavefx_gfortran.f90` | `glibc_math/`: `exp_tab_fortran.txt`, `glibc_exp_mod.cuf`, `glibc_pow.cuf`, `pow_log_tab_fortran.txt` · `dmc2/`: `d_uhex4_mod.cuf`, `mlegendre_gpu.cuf` |
| `d_uhex4.cuf/` | [`docs-kernels/d_uhex4.md`](docs-kernels/d_uhex4.md) | `duhe4x` (parte de `derwavefx`) | `d_uhex4.cuf`, `test_duhe4x_gfortran.f90` | `glibc_math/`: `exp_tab_fortran.txt`, `glibc_exp_mod.cuf`, `glibc_pow.cuf`, `pow_log_tab_fortran.txt` · `dmc2/mlegendre_gpu.cuf` |
| `He_dihydrogen/` | [`docs-kernels/He_dihydrogen.md`](docs-kernels/He_dihydrogen.md) | Potencial impureza-Helio completo (`He_dihydrogen`, `V_hehe`/`Vp_hehe`, `angle`) | `He_dihydrogen.f`, `bh_heh2m.f` (variante con anotaciones GPU), `k_He_dihydrogen.cuf`, `param_atoms_bh_freeform.h`, `test_He_dihydrogen.cuf`, `test_He_dihydrogen_gfortran.f90` | `glibc_math/` (los 11 ficheros) · `dmc2/`: `angle_scalar_vec_mod.cuf`, `mVheheVphehe_mod.cuf` |
| `potenbh/` | [`docs-kernels/potenbh.md`](docs-kernels/potenbh.md) | Envoltorio `potenbh` (llama a `He_dihydrogen`) | `potenbh.cuf`, `test_potenbh_gfortran.f90` | `glibc_math/` (los 11 ficheros) · `He_dihydrogen/`: `He_dihydrogen.f`, `param_atoms_bh_freeform.h` · `dmc2/`: `angle_scalar_vec_mod.cuf`, `mVheheVphehe_mod.cuf` |
| `valibre/` | [`docs-kernels/valibre.md`](docs-kernels/valibre.md) | `valibre` | `valibre.cuf`, `test_valibre_gfortran.f90` | — |
| `V_hehe-Vp_hehe/` | [`docs-kernels/V_hehe_Vp_hehe.md`](docs-kernels/V_hehe_Vp_hehe.md) | Potencial y derivada He-He (`V_hehe`, `Vp_hehe`) | `V_hehe-Vp_hehe.cuf`, `test_hehe_gfortran.f90` | `glibc_math/`: `exp_tab_fortran.txt`, `glibc_exp_mod.cuf`, `glibc_sincos.cuf`, `sincostab_fortran.txt`, `toverp_fortran.txt` · `He_dihydrogen/`: `bh_heh2m.f`, `param_atoms_bh_freeform.h` |
| `vpot/` | [`docs-kernels/vpot.md`](docs-kernels/vpot.md) | `vpot` completo (orquesta `ccuerpo`, `potenbh`, `He_dihydrogen`, `angle_scalar_vec`) | `vpot.cuf`, `test_vpot_gfortran.f90` | `glibc_math/` (los 11 ficheros) · `He_dihydrogen/`: `He_dihydrogen.f`, `param_atoms_bh_freeform.h` · `dmc2/`: `angle_scalar_vec_mod.cuf`, `mVheheVphehe_mod.cuf`, `mccuerpo_mod.cuf`, `mpotenbh_mod.cuf` |
| `wavef/` | [`docs-kernels/wavef.md`](docs-kernels/wavef.md) | `wavef` (función de onda completa) y `getcm` | `wavef.cuf`, `wavef_mod.cuf`, `test_wavef_gfortran.f90`, `test_getcm.cuf`, `test_getcm_gfortran.f90` | `glibc_math/`: `exp_tab_fortran.txt`, `glibc_exp_mod.cuf`, `glibc_pow.cuf`, `pow_log_tab_fortran.txt` · `dmc2/`: `d_uhex4_mod.cuf`, `der_wavefhe4_mod.cuf`, `der_wavefx_mod.cuf`, `mlegendre_gpu.cuf` |

Nota: el `README.md` de `V_hehe-Vp_hehe.md` menciona una referencia de CPU en
`Original-VapFix/` (un `bh_heh2m.f` con un bug de `Vap` corregido) que no existe en el
repositorio actual -- posible hueco de documentación anterior a esta limpieza, no introducido
por ella; queda pendiente de revisar aparte.

Los ficheros `*_mod.cuf`/`m*_mod.cuf` que aparecen como dependencias de varias filas son la
versión de módulo (envuelta para poder combinarse con otros kernels) del mismo método — su copia
de referencia se ha dejado en `dmc2/`, la carpeta donde de verdad conviven todos juntos, en vez
de repetida en cada prueba aislada que también los necesitaba para compilar.
