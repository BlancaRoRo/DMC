# Mapa de instrucciones SFU en producción (`opcion=7`)

## 1. Objetivo

`split-he-dihidrogen.md` (Intento 8) atribuyó el techo de mejora del split de `vpot` a "contención de SFU compartida", apoyándose en el nombre del motivo de stall que da `ncu` (`short_scoreboard`). `funciones-nativas-cuda.md` puso a prueba esa idea sustituyendo `myexp`/`mypow`/`mysin`/`mycos`/`myacos` por las funciones nativas de nvfortran, y confirmó con métricas de pipe (`sm__inst_executed_pipe_xu`) que la SFU apenas se movía (+4,5%) — es decir, el diagnóstico de fondo seguía en pie, pero la causa no eran esas 5 funciones. Este documento va un paso más allá: en vez de inferir la causa a partir de contadores agregados, **lee directamente el ensamblador (SASS) del binario de producción**, localiza cada instrucción de SFU una por una, y confirma con la propia cadena de llamadas del programa cuáles de esos sitios se ejecutan de verdad con `opcion=7` (el único camino que se ha medido y optimizado en toda esta línea de trabajo).

## 2. Metodología: leer el SASS con línea de origen

`compilar_pipeline.sh` ya compila con `-gpu=lineinfo`, así que el binario lleva tabla de líneas de depuración. Con eso:

```bash
# 1. Extraer el/los cubin del binario
cuobjdump -xelf all qmccluster_pipeline

# 2. Desensamblar con anotacion de fichero:linea de origen
#    (nvdisasm vive en <hpc_sdk>/cuda/<version>/bin/, no en el PATH por defecto)
nvdisasm -gi pgcudafat*.sm_89.cubin > sass_con_lineas.txt

# 3. Buscar instrucciones de la Special Function Unit
grep -c "MUFU" sass_con_lineas.txt
grep -oE "MUFU\.[A-Z0-9]+" sass_con_lineas.txt | sort | uniq -c
```

`MUFU` es el mnemónico SASS real de la Special Function Unit (no una etiqueta de perfilado ni una suposición de arquitectura). Cada bloque de anotación tiene la forma:

```
//## File "/ruta/al/fichero.cuf", line 524
        /*3d90*/    MUFU.RCP64H R11, R23 ;
```

## 3. Primer hallazgo: en todo el binario solo hay 2 tipos de instrucción SFU

```
214  MUFU.RCP64H     (reciproco -- semilla de la division)
 99  MUFU.RSQ64H     (reciproco de raiz cuadrada -- semilla de DSQRT)
```

Ninguna instancia de `MUFU.SIN`/`MUFU.COS`/`MUFU.EX2`/`MUFU.LG2` (existen como opcode de esta GPU, pero solo se generan para `float` de precisión simple). **En doble precisión, esta arquitectura no tiene unidad hardware de seno/coseno/exponencial/logaritmo** — hasta `exp`/`sin`/`cos`/`log` "nativos" de nvfortran se implementan por software (polinomios, en `libdevice`), igual que la reimplementación de glibc que se sustituyó en `funciones-nativas-cuda.md`. Confirmado también mirando la rutina base del compilador:

```
__cuda_sm20_div_rn_f64_full:            ... MUFU.RCP64H R15, R5 ...
__cuda_sm20_dsqrt_rn_f64_mediumpath_v1: ... MUFU.RSQ64H ...
```

Es decir: **la SFU en doble precisión, en este binario, es única y exclusivamente división y raíz cuadrada.** Esto es lo que explica, con evidencia directa y no por inferencia, por qué sustituir las funciones trascendentales por sus versiones nativas apenas tocó la SFU en `funciones-nativas-cuda.md`.

## 4. Segundo hallazgo (y un error propio corregido): no todo lo que está en el binario se ejecuta con `opcion=7`

Un primer conteo por función (`cuobjdump --dump-sass`, agrupado por símbolo) incluyó `he_dihydrogen_` (la versión monolítica de `He_dihydrogen`, 24 instrucciones SFU) como si fuera parte de la carga real de producción. **Es un error** -- nunca se comprobó si esa función se ejecuta de verdad. Al trazar la cadena de llamadas real:

```
he_dihydrogen_ (monolitica) <- potenbh <- vpot <- k_vpot_t
```

y buscar todos los lanzamientos reales (`<<<...>>>`) de esa familia en el árbol:

```bash
grep -rn "k_vpot\w*<<<\|k_hpsi\w*<<<" *.cuf
# unico resultado: k_vpot_3warp_t<<<...>>>  (dmc2_pipeline.cuf, x2)
```

**`k_vpot_t` no se lanza nunca.** Esa cadena entera (`He_dihydrogen_` monolítica, `potenbh`, `vpot`, `k_vpot_t`, y por el mismo motivo `hpsi`/`k_hpsi` y `dmc2.cuf`/`k_dmc2`) es código real del binario -- se usa con `opcion=5`/`6` (los caminos de verificación de `docs/hibrido.md`) -- pero **nunca se ejecuta con `opcion=7`**, la única configuración que se ha medido y optimizado en esta sesión y en `split-he-dihidrogen.md`/`funciones-nativas-cuda.md`. Mismo error de fondo que motivó la lección de `derananum-split-concurrente.md`: no basta con que el código exista y compile, hay que comprobar que el camino de ejecución real lo alcanza.

Trazando la cadena completa de la misma manera para el resto de funciones con SFU (`grep` de cada nombre de función dentro del cuerpo de cada kernel realmente lanzado, siguiendo las llamadas nivel a nivel):

### 4.1. SÍ se ejecuta con `opcion=7`

| Estado | Método | Cadena real hasta el kernel | RCP64H | RSQ64H |
|---|---|---|---|---|
| Visto — **arreglado** (`reciprocos-k-fase-h.md`) | `k_fase_h` | lanzado directo (`dmc2_pipeline.cuf`) | 33 | 26 |
| Visto — **arreglado** (`reciprocos-ex0-duhe4x.md` §2-6.1; +`log-rij-redundante.md`) | `duhe4x` | `wavefx`/`derwavefx` ← `k_derananum_resto_t` | 16 | 1 |
| Visto — **arreglado** (`reciprocos-derwavefx.md`) | `derwavefx` | `k_derananum_resto_t` | 9 | 3 |
| Visto — **arreglado** (`reciprocos-ex0-duhe4x.md` §2) | `He_dihydrogen_induccion` | `k_vpot_3warp_t` | 9 | 3 |
| Visto — **arreglado** (`reciprocos-v-and-vp-hehe.md`) | `V_and_Vp_hehe` | `He_dihydrogen_hehe` ← `k_vpot_3warp_t` | 9 | 0 |
| Visto — **sin solución viable** (raíz sin redundancia que cachear, §6a) | `He_dihydrogen_hehe` | `k_vpot_3warp_t` | 0 | 7 |
| Visto — **sin solución viable** (divisor `dnor*rij` distinto cada iteración, ver `reciprocos-derwavefx.md` §3) | `wavefx` | `k_derananum_resto_t` | 3 | 4 |
| Visto — **sin solución viable** (divisor `il+1` distinto en cada iteración del bucle, sin repetición que explotar; alternativa de tabla de recíprocos en memoria constante no evaluada) | `calpleg`/`calderpleg` (via `uhe4x`) + `calplegd`/`calderplegd` (via `duhe4x`) (×4) | `duhe4x`/`uhe4x` | 20 (5 c/u) | 0 |
| Visto — **arreglado** (`reciprocos-he-dihydrogen-dispersion.md`) | `He_dihydrogen_dispersion` | `k_vpot_3warp_t` | 5 | 0 |
| Visto — **arreglado** (`reciprocos-wavef-derwavefhe4.md`) | `wavef_derwavefhe4` | `k_derananum_he4_t` | 4 | 1 |
| Visto — **sin solución viable** (sin división explícita en el código -- las 2 `RCP64H`/2 `RSQ64H` están dentro de las implementaciones nativas de `log()`/`sqrt()` en `xl=sqrt(-2·log(rn))`, confirmado en SASS; cada llamada usa un `rn` distinto e independiente, sin valor compartido que cachear) | `gauss3_gpu` | `k_fase_a` | 2 | 2 |
| Visto — **arreglado** (`log-rij-redundante.md`, `log(rij)`≡`rij_hi` ya calculado por `mypow_log`) | `uhe4x` | `wavefx`/`derwavefx` | 2 | 0 |
| Visto — **sin solución viable** (`wf(i)`/`wfold(i)` varía por walker, sin redundancia que cachear -- igual que `wavefx`) | `k_fase_c`/`k_fase_f` (propio, `wftest=(wf/wfold)**2`) | lanzados directo | 2 | 0 |
| Visto — **sin solución viable, no por precisión sino por impacto** (ver nota abajo) | `k_fase_a` (propio, `sigma1_l`/`sig1rot_l`/`sig1hrot_l`) | lanzado directo | 0 | 5 |
| Visto — **arreglado** (`funciones-nativas-cuda.md`) | `myexp` (nativo) | `wavef_derwavefhe4`, `FN2`/`F00` | 1 | 0 |
| Visto — **arreglado** (`funciones-nativas-cuda.md`) | `mypow_log` (nativo) | `wavef_derwavefhe4` | 1 | 0 |
| | **Total** | | **≈116** | **≈49** |

### 4.2. NO se ejecuta con `opcion=7` (código real, de otra vía)

| Método | Por qué |
|---|---|
| `He_dihydrogen_` (monolítica) | Solo la llama `potenbh`; `k_vpot_t` nunca se lanza |
| `vpot`, `potenbh`, `k_vpot_t` | Cadena completa sin lanzamiento real |
| `hpsi`, `k_hpsi` | Solo `dmc2.cuf` (`opcion=5`/`6`) los llama |
| `k_dmc2`/`dmc2` | Kernel de `opcion=5`/`6` |
| `wavefhe4`/`k_wavefhe4`, `derwavefhe4`/`k_derwavefhe4` (sin fusionar) | Superseded por `wavef_derwavefhe4` (`optimización-mypow/`); solo los llama el `wavef_mod.cuf`/`dmc2.cuf` viejo |
| `angle`/`k_angle`, `vec_norm`/`k_vec_norm` | Cero llamadas reales en todo el árbol, confirmado con `grep`, ni en la vía vieja |
| `myacos`/`k_myacos` | Su único llamador (`angle`) está muerto |
| `mypow` (versión simple, no el split) | Solo la llama `k_mypow`, kernel de prueba nunca lanzado |
| `duhe3x`/`k_duhe3x` | Su única llamada real es `derwavefx` línea 218, dentro de `do jhe3=1,nhe3` -- con `nhe3=0` (`parameter`), el compilador elimina la llamada; solo sobrevive compilada dentro de `k_duhe3x` (kernel de prueba nunca lanzado). El propio código lo documenta explícitamente (`der_wavefx_mod.cuf` línea 26): *"duhe3x/uhe3x nunca se llegan a ejecutar en tiempo de ejecución... pero el código tiene que existir y compilar igual"*. **Corrección**: una versión anterior de esta tabla la clasificaba como alcanzable -- error propio, mismo tipo de fallo que el de `He_dihydrogen_` monolítica (ver arriba): se vio "derwavefx llama a duhe3x" en el código fuente sin comprobar que esa llamada concreta vive dentro de un bucle de 0 iteraciones. Confirmado con `grep -o` sobre el SASS completo: `duhe3x` solo aparece como el nombre de su propia definición, ninguna referencia de llamada real. Pese a ser código muerto, se le aplicó también la corrección de `log-rij-redundante.md` (igual que a su análoga `uhe3x`) por consistencia con la parte viva. |

**Nota sobre `k_fase_a`**: sus 3 `sqrt` (`sigma1_l=sqrt(2·hb2m·dtau)`, `sig1rot_l=sqrt(2·b·dtau)`, `sig1hrot_l=sqrt(b·dtau)`) no dependen del walker -- `hb2m`/`b` son constantes físicas por átomo (`aos-to-soa.md` línea 49: "escalares globales... mismo valor para los 2·nwalkers walkers, siempre") y `dtau` se sincroniza una sola vez por corrida (`sincroniza_constantes_gpu`, `msync_gpu.cuf`), así que cada uno de los `nw_actual` hilos de `k_fase_a` recalcula, de forma redundante, el mismo valor -- distinto en naturaleza al patrón de recíproco cacheado de esta línea de trabajo: aquí no habría ni riesgo de precisión (mismo cálculo, mismo redondeo, bit a bit garantizado) porque no se cachearía "dentro de un hilo" sino "una vez para toda la simulación" (calculado en el host y pasado como parámetro de solo lectura, la misma idea que ya se aplicó al copiado H2D de `hb2m_p`/`b_p` en `aos-to-soa.md`). Se descarta igualmente **por impacto, no por precisión**: `k_fase_a` mide 0,6% del tiempo total del pipeline (0,37 ms, `fase0-perfilado.md`), así que aunque se eliminase el 100% de su SFU el techo de mejora total quedaría muy por debajo del ruido de medición térmica que este mismo árbol ya trata como no fiable (`README.md` §Verificación). Queda anotado por si en el futuro cambia la proporción de tiempo de `k_fase_a` (p.ej. tras optimizar el resto del pipeline lo suficiente como para que su peso relativo suba).

Nota de confianza: la columna "SÍ se ejecuta" está verificada función por función siguiendo `call`/asignación real desde los 10 kernels que `dmc2_pipeline.cuf` lanza de verdad; no se rehizo el mismo nivel de rigor para cada eslabón más pequeño (p.ej. si `calpleg` tiene algún otro llamador muerto que no se comprobó), así que los números de esta sección son sólidos en las piezas grandes pero no una garantía absoluta al 100% en cada detalle.

## 5. Desglose completo de `He_dihydrogen.f` (48 instrucciones, ninguna sin explicar)

Clasificando cada línea del fichero según esté dentro o fuera del bloque `IF (GTEST)` (código muerto desde que `GTEST` es `PARAMETER=.false.`, `myexp-optimizacion.md` §9):

| Origen | Instrucciones SFU | Estado |
|---|---|---|
| `drh1dx`/`drh1dy`/`drh1dz`/`drh2dx`/`drh2dy`/`drh2dz`/`dr0dx`/`dr0dy`/`dr0dz` (líneas 512-522, 877-887) | 18 divisiones que **habrían existido** | **Eliminadas por el compilador** -- solo las lee `dExdx`...`dEzdz`, dentro de `IF(GTEST)` |
| `DSQRT(rh1)`/`DSQRT(rh2)`/`DSQRT(r0)` (líneas 502,506,510 y 867,871,875) | 6 (`RSQ64H`) | Vivas |
| `Ex0`/`Ey0`/`Ez0`, `/rh1**3` etc. (líneas 524-534 y 889-899) | 18 (`RCP64H`) | Vivas |
| `DSQRT` de la distancia He-He (líneas 318, 713) | 14 (`RSQ64H`, x7 por desenrollado) | Vivas |
| `eterm2=.../norm6` (líneas 437, 792) | 10 (`RCP64H`, x5 por desenrollado) | Vivas |
| **Total en el binario** | **48** | 24 vivas + 24 que existirían si no se hubiera eliminado el bloque muerto |

## 6. Por dónde empezar: división antes que raíz cuadrada

De los dos tipos de instrucción SFU encontrados, **la división es el candidato correcto para intentar algo, la raíz cuadrada no**, por dos razones independientes:

**a) No hay redundancia real que explotar en la raíz sin sacrificar precisión de verdad.** `DSQRT(rh1)`/`DSQRT(rh2)`/`DSQRT(r0)` se calculan una sola vez cada una -- no hay ninguna repetición que cachear, a diferencia de `/rh1**3` (se repite igual en `Ex0`, `Ey0`, `Ez0` con el mismo `rh1`). La única forma de tocar la SFU de la raíz sería sustituir `DSQRT` por una aproximación más barata y menos exacta -- eso sí sería sacrificar precisión física real, no reorganizar un cálculo ya determinista.

**b) Un error en la raíz se propaga peor que un error en la división.** `rh1`/`rh2`/`r0` son la distancia física entre átomos, y esa distancia alimenta lo que viene después para ese par: entra dentro de `FN2(btheta*rh1)`, que llama a `myexp(-x)`. Un error relativo pequeño en `rh1` se amplifica dentro de una exponencial (el error relativo en `exp(-α·r)` es del orden de `α` veces el error en `r`, no 1:1). El resultado de `/rh1**3` en `Ex0=q*FN2(...)*Δx/rh1**3`, en cambio, entra como un factor multiplicativo **lineal** dentro de una suma de energía -- un error ahí se queda proporcional y aislado a ese término, sin amplificarse.

**Conclusión**: la línea de trabajo que sigue (`funciones-nativas-cuda.md` §7 en adelante, o un documento nuevo) ataca las **18 divisiones vivas de `Ex0`/`Ey0`/`Ez0`** (sección 5), cacheando `1.0d0/rh1` una vez y reutilizándolo por multiplicación en vez de dividir 3 veces por `rh1`, `rh2` y `r0` respectivamente -- con una prueba unitaria aislada para medir si el resultado sigue siendo bit a bit idéntico o cuánto diverge, antes de decidir si compensa.

## Ficheros

- Este documento no tiene copias de trabajo propias -- todo el análisis se hizo directamente sobre `hibrido_instrumentado/qmccluster_pipeline` (el binario de producción ya actualizado en `funciones-nativas-cuda.md`) y su código fuente, sin modificarlos.
