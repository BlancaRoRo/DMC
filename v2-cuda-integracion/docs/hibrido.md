# Programa híbrido CPU+CUDA: hoja de ruta y evolución

Documentación de [`v1-cuda-desarrollo/hibrido/`](../hibrido/) — la carpeta donde se ensamblan, en un único sitio, todos los kernels ya portados a CUDA Fortran (`calpleg` hasta `dmc2`) junto con la orquestación original de la simulación (lectura de `in.mcv`, bucle de bloques/pasos DMC, estadísticas, salida). Es el sexto y último gran paso del proyecto (ver el esquema completo en el artefacto de la hoja de ruta) — corresponde a la sexta etapa: **"Integración híbrida"**.

Hasta este punto, cada kernel se había portado y probado **en su propia carpeta aislada**, cada una con sus propias copias de los ficheros compartidos — necesario para poder compilar y verificar cada pieza por separado, sin depender de las demás. Ensamblar el programa real exige lo contrario: que cada fichero compartido exista **una sola vez** en todo el árbol, que las variables de estado global no estén duplicadas entre módulos, y que la orquestación de la CPU original se integre sin haber tenido que tocarla.

El trabajo se divide en 5 pasos, verificando cada uno antes de pasar al siguiente.

---

## Paso 1 — Consolidar la base matemática

**Qué se hizo**: comprobado primero con `md5sum` que **todas** las copias de cada fichero compartido eran idénticas byte a byte en todo el árbol (`mtipos.f90`, `mparametros.f90`, `glibc_exp_mod.cuf`, `glibc_sincos.cuf`, `glibc_pow.cuf`, `glibc_acos.cuf` — de donde salen `myexp`/`mysin`/`mycos`/`myacos`/`mypow`) — no había ninguna divergencia real que reconciliar, solo duplicación. Se copió una sola vez cada uno a `hibrido/`.

**Verificación**: recompilada y re-ejecutada la batería completa de `rota` (8 casos: los 3 valores de `i1`, ambos signos de `phi`, 2 extremos) usando los ficheros consolidados en vez de la copia local de `rota/`.

**Resultado**: exacto, `0.00E+00` en los 8 casos, GPU = CPU-`nvfortran` = `gfortran` — mismo resultado que `rota.md`.

## Paso 2 — Consolidar la física

**Qué se hizo**: copiados a `hibrido/`, una sola vez cada uno, los 11 módulos de física ya portados y sus dependencias (`d_uhex4_mod.cuf`, `der_wavefx_mod.cuf`, `der_wavefhe4_mod.cuf`, `angle_scalar_vec_mod.cuf`, `mVheheVphehe_mod.cuf`, `He_dihydrogen.f`, `wavef_mod.cuf`, `derananum_mod.cuf`, `mccuerpo_mod.cuf`, `mpotenbh_mod.cuf`, `vpot_mod.cuf`, `valibre_mod.cuf`, `hpsi_mod.cuf`, `rota_mod.cuf`, `rand_gpu.cuf`, `dmc2.cuf`). Sin cambiar ni una línea — estos módulos **ya estaban encadenados entre sí** (`dmc2.cuf` ya hace `use mhpsi`/`use mrota`/`use mrandgpu`; `hpsi_mod.cuf` ya hace `use mderananum`/`use mvpot`/`use mvalibre`; etc.), fruto de cómo se fueron portando: cada kernel nuevo reutilizaba los ya construidos.

**Verificación**: recompilada y re-ejecutada la batería completa de `dmc2` (la más profunda — ejercita `hpsi`+`rota`+`gauss3`/`rand1` a la vez) desde `hibrido/`, en las tres vías.

**Resultado**: idéntico a `dmc2.md` en los 5 walkers, incluidos los dos casos de `gb` patológico ya documentados (walkers 3/4, `exp()` desborda por la geometría extrema — comportamiento no definido esperado, no un error).

## Paso 3 — Consolidar las variables globales duplicadas

**El problema**: al portar cada kernel por separado, se habían declarado las mismas variables `device` en más de un módulo — no por error, sino porque cada kernel se probaba aislado y no tenía sentido arrastrar dependencias extra:
- `natom`/`ngatom`: declaradas independientemente en `der_wavefx` **y** en `mccuerpo` — cada test las fijaba a mano a los mismos valores en los dos sitios.
- `nhe4`: declarada independientemente en `der_wavefx` **y** en `der_wavefhe4`.

**Qué se hizo**: creado [`mcuda_globals.cuf`](../hibrido/mcuda_globals.cuf), un módulo nuevo con `natom`, `ngatom`, `nhe4`, `nhe3`, `impureza` — las únicas variables `device` que estaban duplicadas. `der_wavefx_mod.cuf`, `mccuerpo_mod.cuf` y `der_wavefhe4_mod.cuf` se modificaron para hacer `use mcuda_globals, only: ...` en vez de declarar su propia copia — sin tocar ninguna fórmula ni ninguna otra variable.

**Verificación**: como este cambio sí toca ficheros ya validados (a diferencia de los Pasos 1-2, que solo movían ficheros de sitio), se re-verificaron **las cuatro baterías que dependen de estos módulos**, en orden de menos a más dependencias:

| kernel | resultado tras la migración | igual que antes (documentado en) |
|---|---|---|
| `vpot` | 3/3 walkers, `0.00E+00`/`1.42E-14`/`1.14E-13` | `vpot.md` |
| `derananum` | 16/16 exacto (`3.55E-15`, `6.94E-18`, resto `0.00E+00`) | `derananum.md` |
| `hpsi` | 6/6, mismo patrón (`3.55E-15` … `3.31E-24`, `0.00E+00`) | `hpsi.md` |
| `dmc2` | 5/5, idéntico a antes de la migración | `dmc2.md` |

**Resultado**: exacto, mismos valores que antes de consolidar — la migración no cambió ningún resultado, solo eliminó la duplicación.

---

## Paso 4 — Copiar la orquestación CPU original (completado)

**Qué se hizo**: traídos `mconfiguraciones.f90`, `mentradatos.f90`, `mimagina.f90`, `mdmcpromedia.f90`, `mserie.f90`, `mminimiza.f90`, `mmontecarlo.f90`, `qmccluster.f90` (desde `ccuerpo/`, sin tocar nada) a `hibrido/` — `msteps.f90`/`mdensidades.f90`/`mmcvpromedia.f90` ya estaban ahí desde el Paso 2 (los necesitaba la CPU de referencia de `dmc2`). Compilado y enlazado **todo junto** — orquestación original + los 11+ módulos de física CUDA ya consolidados — en un único binario `qmccluster`, con `nvfortran -cuda -Kieee -Mnofma`.

**Resultado de la compilación/enlace**: limpio, sin errores ni colisiones de nombres — confirma que `mcuda_globals` (con `natom`/`ngatom`/`nhe4`/`nhe3`/`impureza`) y `mparametros` (con las variables reales del mismo nombre) conviven sin problema al estar en módulos Fortran distintos.

**Un susto por el camino, ya resuelto (ver `hallazgo-cuda-host.md`)**: al comparar una corrida real (`opcion=4`) del binario ensamblado en `hibrido/` (con los módulos CUDA presentes) contra la misma orquestación sin ningún módulo CUDA, aparecía una diferencia real en el resultado. Tras descartar varias hipótesis (el flag `-cuda`, un cambio de librería matemática del host para `log`/`exp`/`sin`/`cos`/`acos`/`pow`, la inicialización del runtime de CUDA) se encontró la causa real: `finwalkers` reescribe `conf.20.00.HH` al final de **cualquier** ejecución de `qmccluster` (pensado para continuar una simulación larga), y las distintas carpetas de prueba habían ido mutando sus propias copias de ese fichero sin que yo me diera cuenta — no era ni CUDA ni el compilador. Con el mismo `conf.20.00.HH` intacto en las dos variantes, el resultado es idéntico hasta el último dígito.

**Verificación final**: `qmccluster` compilado en `hibrido/` (orquestación + CUDA reales) da exactamente el mismo resultado, con `opcion=4` y un `conf.20.00.HH` limpio, que la misma orquestación compilada sola (sin ningún módulo CUDA) y que `gfortran` — confirmando lo que ya sugería `test-metodos-antes.md`, esta vez con los módulos CUDA físicamente presentes en el mismo binario.

## Paso 5 (completado) — `opcion=5`, sin tocar `dmc`/`pasodmc` originales

### 5.0 — El puente AoS→SoA: qué se transforma, por qué, y dónde exactamente

Antes de entrar en `pasodmc_gpu`/`pasodmc_cpu_gpurand` en sí, esto merece su propia sección — es la pieza que hace posible todo lo demás y no estaba documentada como tal en ningún sitio, solo mencionada de pasada.

**Por qué hace falta**: `wsim` (la población de walkers, en `mmontecarlo.f90`) es un array de `type(walker)` (`mtipos.f90`) — un tipo derivado con **componentes `allocatable`** (`atom(:)`, `dwf(:)`, `delta(:)`, `hb2m(:)`, `sigma1(:)`, `sigma2(:)`). Esto ya se estableció desde el primer kernel que recibía el walker completo (`der_wavefhe4.md` §1): *"un tipo derivado con componentes allocatable/pointer no se puede usar como dato device: la GPU no puede gestionar esa reserva dinámica anidada dentro de cada elemento de un array de walkers de la misma forma que la CPU"*. Por eso, desde el primer kernel portado hasta `k_dmc2`, ningún kernel recibe nunca un `type(walker)` — recibe los campos sueltos que necesita, como arrays "SoA" (*Structure of Arrays*: un array por campo, con el índice de walker al final) en vez del "AoS" (*Array of Structures*: un array de walkers, cada uno con todos sus campos dentro) que usa la CPU.

Dentro de cada kernel esto ya estaba resuelto (la interfaz de `dmc2`/`k_dmc2` ya recibe `atom(natom,n)`, `wf(n)`, etc., no un walker). Lo que faltaba documentar es el **paso previo**: convertir `wsim(1:nwpaso)` (el array de walkers real, con el que trabaja toda la orquestación) a esos arrays SoA antes de llamar al kernel, y convertir el resultado de vuelta a `wsim` después — el "puente" en sí. Eso ocurre en `msteps.f90`, dentro de `pasodmc_gpu` y `pasodmc_cpu_gpurand` (cada una con su propia copia del mismo empaquetado/desempaquetado, porque una alimenta un kernel `device` con arrays completos y la otra llama a la subrutina `host` un walker cada vez).

**Qué campos se transforman, exactamente** (tabla completa — cada fila es un campo real de `type(vloc)`/`type(walker)` en `mtipos.f90`):

| campo de `wsim(iwalker)` | tipo original | variable SoA (host) | notas |
|---|---|---|---|
| `%atom(iatom)` | `type(vec3), allocatable(:)` | `atom_h(iatom,iwalker)` | posición de cada átomo |
| `%dwf(iatom)` | `type(vec3), allocatable(:)` | `dwf_h(iatom,iwalker)` | derivada de la función de onda por átomo |
| `%sprop(:)` | `type(vec3)(3)` (fijo) | `sprop_h(:,iwalker)` | ejes de la molécula impureza |
| `%hb2m(:)` | `real, allocatable(:)` | `hb2m_h(:,iwalker)` | constante física por átomo (no cambia entre pasos, se re-empaqueta igual) |
| `%b` | `real` (escalar) | `b_h(iwalker)` | constante rotacional |
| `%lw%wf` | `real(kind=r16)` (¡cuádruple!) | `wf_h(iwalker)` (`real(kind=r8)`) | conversión `real(...,r8)` — mismo criterio que `wavef.md`/`valibre.md`: GPU sin soporte de cuádruple precisión |
| `%lw%wfhe4/wfhe3/wfm/wfx` | `real(kind=r16)` | `wfhe4_h`/`wfhe3_h`/`wfm_h`/`wfx_h` (`r8`) | misma conversión |
| `%lw%kin/eimp/erot/pot/ene` | `real(kind=r8)` | `kin_h`/`eimp_h`/`erot_h`/`pot_h`/`ene_h` | sin conversión, ya son `r8` |
| `%dphi(2)` | `real(2)` (fijo) | `dphi_h(:,iwalker)` | derivada de la parte rotacional |

Dos campos **no** existen en `type(walker)` y se llevan por fuera, en arrays propios:
- **`irn_walkers(iwalker)`** (`integer(kind=i8)`): el estado de aleatoriedad propio de cada walker (ver `mrandom.md`). Se decidió explícitamente **no** añadirlo como campo nuevo a `type(walker)` en `mtipos.f90` (que usa *todo* el código original, no solo la vía GPU) — se guarda aparte, con `save`, dentro de la propia subrutina, y se reordena en paralelo con `wsim` cuando la población se reparte/compacta según `nsons`.
- **`nsons(iwalker)`** (`integer(kind=i4)`): la salida de `dmc2`/`k_dmc2` que decide cuántas copias sobreviven de cada walker — no es un dato persistente del walker, se consume inmediatamente en la lógica de repartición.

**Qué campos de `type(walker)` NO se tocan** (se quedan en `wsim` tal cual, sin pasar por el puente): `%delta`, `%sigma1`, `%sigma2`, `%dangle`, `%sig1rot`, `%sig2rot`, `%sig1hrot`, `%sig2hrot`, `%eje0`, `%pos0`, `%lw%signoup`, `%lw%signodw`. Los seis primeros no hacen falta porque `dmc2`/`k_dmc2` los recalcula en el sitio a partir de `hb2m`/`b`/`dtau` en vez de guardarlos (ver `dmc2.md` §1); `signoup`/`signodw` nunca se exponen desde `hpsi` (siempre `+1` en este proyecto, `wavef.md` §4); `eje0`/`pos0` son estado de `iniwalkers`/`restacm`, ajenos a `dmc2`.

**Dónde pasa exactamente, línea a línea** (`msteps.f90`):

| | `pasodmc_gpu` (paralelo) | `pasodmc_cpu_gpurand` (secuencial) |
|---|---|---|
| Declaración de las variables SoA (host y device) | líneas 104–122 | líneas 281–285 (solo host, un walker: no hace falta SoA de dispositivo porque no hay kernel) |
| Empaquetar `wsim` → SoA | líneas 143–163 (bucle sobre los `nwpaso` walkers de golpe) | líneas 304–322 (dentro del bucle `do iwalker=1,nwpaso`, un walker cada vez) |
| Copia a memoria de dispositivo (H2D) | líneas 165–169 (`atom_d = atom_h`, ...) | *(no aplica — `pasodmc_cpu_gpurand` no usa memoria de dispositivo para los walkers, todo se queda en host)* |
| Llamada a la física | línea 174: `call k_dmc2<<<blocks,threads>>>(nwpaso, ...)` — un lanzamiento para todos | línea 324: `call dmc2_hd(...)` — dentro del bucle, un walker cada vez |
| Copia de vuelta (D2H) | líneas 179–184 | *(no aplica)* |
| Desempaquetar SoA → `wsim` | líneas 186–204 (bucle sobre los `nwpaso` walkers de golpe, después de la llamada) | líneas 329–344 (mismo walker, inmediatamente después de `dmc2_hd`, dentro del mismo bucle) |

La diferencia entre las dos columnas es exactamente la que ya se explicó en la comparación `pasodmc_gpu` vs. `pasodmc_cpu_gpurand`: la primera empaqueta **toda la población de golpe** y hace **una** ida y vuelta a memoria de dispositivo; la segunda empaqueta **un walker cada vez**, en variables locales pequeñas, sin tocar memoria de dispositivo para los datos del walker (el `k_split_seeds` inicial es la única parte que sí usa el device en `pasodmc_cpu_gpurand`).

En vez de modificar `pasodmc` en el sitio, se añadió una opción nueva en `qmccluster.f90` (`opcion=5`, junto a `0=test der, 1=mcv, 2 optimiza, 3 optimiza correlated, 4=dmc`) que hace lo mismo que `dmc` pero con los métodos de GPU:
- `mmontecarlo.f90`: subrutina nueva `dmc_gpu`, mismo esqueleto que `dmc`, llamando a `pasodmc_gpu` en vez de `pasodmc`.
- `msteps.f90`: subrutina nueva `pasodmc_gpu`, igual que `pasodmc` salvo el bucle interior — ahí va el puente AoS↔SoA (empaquetar `wsim(1:nwpaso)` en los arrays SoA de dispositivo, lanzar `k_dmc2` una vez para todos los walkers en paralelo, desempaquetar los resultados de vuelta en `wsim(:)`). La repartición/compactación de la población según `nsons` se repite igual — es barata, O(n), ya probada, sin física real.
- `mentradatos.f90`/`in.mcv`: se actualiza el comentario de `opcion` para incluir las opciones nuevas.

**Por qué así y no modificando `pasodmc`**: `dmc`/`pasodmc` originales quedan intactos para siempre — se puede seguir corriendo la trayectoria 100% CPU con la misma semilla en cualquier momento, para comparar o depurar, y no hace falta volver a tocar código de orquestación ya validado (`test-metodos-antes.md`). El coste es repetir un poco de bookkeeping barato en `pasodmc_gpu`, asumible.

### 5.1 — Un bug real encontrado y corregido: faltaba sincronizar las variables `device`

Primera prueba con `opcion=5`: la simulación corría sin errores, pero la energía cinética salía **exactamente `0.0`** en cada paso, y la población de walkers se quedaba congelada (`50.00` sin cambiar nunca) — síntoma de que la física real no se estaba evaluando. Causa encontrada: **en cada kernel portado por separado, sus variables `device` de módulo (`pxhe4`, `phe4`, `dhcm`, `opot`, `libre`, `etrial`, `ncmtras`, ...) se fijaban a mano, una vez, al principio de cada programa de prueba aislado** — pero la orquestación real (`mentradatos.f90`/`escribedatos`) nunca copia esos valores a las variables `device`, solo a las variables *host* de `mparametros.f90`. Sin esa copia, todas las variables `device` se quedaban en su valor por defecto (cero), dando una física trivial.

**Corrección**: nuevo módulo [`msync_gpu.cuf`](../hibrido/msync_gpu.cuf), con una subrutina `sincroniza_globales_gpu` que copia explícitamente cada variable real (`mparametros`, más el `COMMON /datosbh/` que rellena `bh_leevheh2m` al leer `heh2m.pot`) a su variable `device` correspondiente (`mcuda_globals`, `d_uhex4`, `der_wavefx`, `der_wavefhe4`, `mwavef_gpu`, `mderananum`, `mpotenbh`, `mvpot`, `mhpsi`, `mdmc2`). Se llama **en cada paso** (no solo una vez), porque `etrial` cambia durante la simulación. Con esto corregido, la física ya se evalúa de verdad: energías y población fluctúan de forma realista.

### 5.2 — El criterio de verificación correcto (y por qué "deben coincidir" era la pregunta equivocada)

Al comparar `opcion=4` contra `opcion=5` con el mismo `conf.20.00.HH`/semilla, las trayectorias **divergen a partir del quinto paso** (`nwnew` distinto entre las dos vías). Esto **no es un bug** — es exactamente la consecuencia, ya establecida y documentada desde el diseño de `mrandom` (`mrandom.md` Parte 1), de que la CPU original usa **una única secuencia aleatoria compartida y secuencial entre walkers**, mientras que `pasodmc_gpu` da a cada walker **su propia semilla independiente**: son dos trayectorias Monte Carlo distintas pero igual de válidas, nunca iban a coincidir número a número. El criterio de verificación correcto para un proceso estocástico no es "misma trayectoria", es "mismas estadísticas dentro del margen de error".

**Verificación real, 200 walkers, 5 bloques × 50 pasos, `opcion=4` vs `opcion=5`** (mismo `in.mcv`/semilla):

| | `opcion=4` (CPU) | `opcion=5` (GPU) |
|---|---|---|
| Energía total (meV) | `-684.33 ± 7.39` | `-686.04 ± 5.56` |
| Población media | `204.29 ± 0.87` | `203.92 ± 0.41` |

Compatibles dentro del margen de error — la física converge al mismo resultado por dos caminos distintos, como se espera de dos trayectorias Monte Carlo válidas con datos iniciales iguales.

**Hallazgo de rendimiento** (no bloquea el Paso 5, apuntado como trabajo futuro): en este caso pequeño, `opcion=5` tardó **1402 s** frente a los **5.3 s** de `opcion=4` — la copia CPU↔GPU en cada paso (empaquetar/desempaquetar `wsim` entero, más `sincroniza_globales_gpu`) domina el tiempo para poblaciones de walkers pequeñas. Con más walkers (la simulación real usa 2000) la ventaja de la GPU debería notarse más, pero el diseño actual (ida y vuelta a host en cada paso) deja mucho margen de optimización pendiente para una fase de rendimiento, no de correctitud.

### 5.3 — Prueba de control (`opcion=6`): aislar si la paralelización en sí introduce alguna diferencia

Para comprobar de forma equitativa que la ÚNICA causa de la divergencia 4-vs-5 es el reparto de aleatoriedad (y no, por ejemplo, algún efecto de la paralelización en sí, o un bug sutil en `k_dmc2`/`pasodmc_gpu`), se añadió una tercera vía de control, **`opcion=6`** (`dmc_cpu_gpurand`/`pasodmc_cpu_gpurand`, no pensada como una vía de producción, solo como prueba): procesa los walkers **secuencialmente en el host** (mismo orden que `pasodmc` original) pero **con la misma semilla independiente por walker que usa `pasodmc_gpu`** (mismo `k_split_seeds`), llamando a `dmc2` de `mdmc2.cuf` (la subrutina `attributes(host,device)` que ejecuta `k_dmc2` en el device) invocada aquí en modo host, un walker cada vez.

**Resultado — 50 walkers, 2 bloques × 10 pasos, mismo `conf.20.00.HH`/semilla, `opcion=5` vs `opcion=6`**: `diff` sobre `egrow`/`etrial` en `es24.17`, todos los pasos → **0 diferencias**. Coinciden también, hasta el último dígito impreso, la tabla de bloques y la energía final (`-615.5737694990` en ambas).

**Conclusión**: la paralelización (pasar de un bucle secuencial que llama a `dmc2` walker a walker, a un único lanzamiento de `k_dmc2` para todos a la vez) **no introduce ninguna diferencia por sí sola** — con la misma arquitectura de aleatoriedad (semilla independiente por walker), da exactamente lo mismo en host secuencial que en device paralelo. La única diferencia real entre `opcion=4` (original) y `opcion=5` es, y solo es, el reparto de aleatoriedad — ya sabido, ya documentado, ahora demostrado de forma directa y controlada.

### 5.4 — Cerrando el triángulo: `opcion=4` vs `opcion=6`

Las dos pruebas de arriba (§5.2, §5.3) cambian **dos variables a la vez** en distintas combinaciones: `4` vs `5` cambia ejecución *y* semillas juntas; `5` vs `6` aísla solo la ejecución (semillas iguales). Falta la tercera combinación, la que aísla **solo** el reparto de semillas dejando fija la ejecución (las dos secuenciales en host): `opcion=4` (`pasodmc`, semilla compartida) vs. `opcion=6` (`pasodmc_cpu_gpurand`, semilla independiente). Por transitividad ya se sabía qué tenía que salir (si `5`≡`6` exacto y `4`≠`5`, entonces `4`≠`6` de la misma forma) — pero en este proyecto una conclusión "por lógica" siempre se ha comprobado con datos antes de darla por buena.

**Resultado — mismo caso que §5.3 (50 walkers, 2 bloques × 10 pasos, mismo `conf.20.00.HH`/semilla), `opcion=4` vs `opcion=6`**: divergen a partir del **mismo quinto paso** que ya se vio entre `opcion=4` y `opcion=5` — mismo punto exacto de divergencia, mismo patrón.

Con esto quedan las tres combinaciones comprobadas de forma directa, no solo dos de tres inferidas:

| comparación | qué cambia | qué se mantiene igual | resultado |
|---|---|---|---|
| `4` vs `5` (§5.2) | ejecución **y** semillas | nada | divergen (paso 5) — estadísticas compatibles |
| `5` vs `6` (§5.3) | ejecución (paralelo↔secuencial) | semillas (independientes) | **idénticos, bit a bit** |
| `4` vs `6` (§5.4) | semillas (compartida↔independiente) | ejecución (secuencial) | divergen (paso 5) |

Las tres, coherentes entre sí: la fila 2 aísla que la paralelización no pesa; la fila 3 aísla que el reparto de semillas sí pesa, con el mismo punto de divergencia que la fila 1 — confirmando que esa es la única causa real, ahora con las tres esquinas del triángulo comprobadas, no dos de tres.
