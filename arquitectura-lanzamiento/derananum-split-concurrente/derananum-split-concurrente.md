# Split de derananum en kernels concurrentes + arreglo de bucles ngatom→nhe3

## Objetivo

`derananum` es el kernel más caro del pipeline (73,9% del tiempo total de
kernels, ver `v4-cuda-pruebas/prueba2-threads-por-bloque/`). Dos preguntas
concretas de esta investigación:

1. ¿Se puede partir `derananum` en varios kernels que corran en streams
   concurrentes (como ya se hace con `derananum_t`∥`vpot_t`), para que las
   partes independientes que hoy se calculan una detrás de otra dentro de
   una sola llamada se solapen?
2. ¿Cuánto de la presión de registros de `derananum` viene de código que en
   esta configuración (`nhe3=0`, gota pura de He4) nunca se ejecuta pero que
   el compilador no puede demostrar muerto?

## Parte 1: split en 3 kernels (He4 / resto / cierre)

### Diseño

`derananum` combina 4 contribuciones independientes (mismo `atom`/`sprop`
de entrada, sin dependencia entre ellas, solo se combinan al final en
`wf`/`kin`):

- **He4-He4** (`wavef_derwavefhe4`): el bucle de parejas, ~190 pares con
  `nhe4=20` -- la parte pesada.
- **"resto"**: `wavefhe3`+`wavefm`+`wavefx`+`derwavefm`+`derwavefx`+
  `derwavefhe3` -- con `nhe3=0`, la mayoría son casi gratis, pero
  `wavefx`/`derwavefx` (interacción impureza-He4) es trabajo real.

Se partió en 3 kernels nuevos (`derananum_split_mod.cuf`):

```fortran
call k_derananum_he4_t<<<blocks,threads,0,stream_a>>>(...)   ! He4, stream_a
call k_derananum_resto_t<<<blocks,threads,0,stream_c>>>(...)  ! resto, stream_c (nuevo)
call k_vpot_t<<<blocks,threads,0,stream_b>>>(...)             ! ya existia, stream_b
! ... eventos de espera ...
call k_derananum_join_t<<<blocks,threads,0,stream_a>>>(...)   ! combina wf/kin, stream_a
```

`k_derananum_join_t` reproduce exactamente la lógica de combinación de
`derananum()` (líneas 168-218 de `derananum_mod.cuf`), leyendo los
resultados intermedios desde arrays `device` persistentes nuevos
(`wfhe4_s`, `d1wfhe4_s`, etc.) en vez de mantenerlos en variables locales
de una sola llamada.

### Dos errores metodológicos por el camino (documentados para no repetirlos)

1. **Comparación horquilla 1 vs horquilla 2**: la primera verificación
   insertó la referencia (`k_derananum_t` original) solo en la horquilla 1
   del grafo, pero leía el resultado del split después de que se ejecutara
   TAMBIÉN la horquilla 2 (con las posiciones ya movidas por `k_fase_d`
   entre medias) -- comparaba dos pasos físicos distintos. Al insertar la
   misma referencia en ambas horquillas, coincidencia bit a bit inmediata.

2. **"Condición de carrera" fantasma**: al repetir la corrida completa
   varias veces para comprobar reproducibilidad, la energía cambiaba cada
   vez (`-676,30` → `-647,03` → `-637,05`...). Parecía una carrera real, y
   se descartaron (con pruebas directas, no solo razonamiento) dos causas
   plausibles -- forzar todo a un único stream (sin concurrencia) y
   eliminar una variable `nw_actual_split` duplicada -- sin que el
   problema desapareciera. La causa real: `finconfiguraciones`
   (`mconfiguraciones.f90:179`) **reescribe `conf.20.00.HH`** con la
   posición final de los walkers al terminar cada corrida (para poder
   continuar el cálculo sin reequilibrar). El bucle de pruebas no
   restauraba el conf de referencia entre iteración e iteración -- cada
   corrida arrancaba de donde había terminado la anterior, lo cual explica
   la variación sin necesidad de ninguna carrera. Restaurando el conf
   antes de cada corrida: bit a bit idéntico las 3 veces.
   **Lección para pruebas futuras de repetibilidad**: SIEMPRE restaurar
   `conf.20.00.HH` desde la referencia antes de cada corrida repetida,
   incluso dentro de un mismo bucle de comprobación.

### Resultado: positivo, ~2,6x más rápido

Verificado bit a bit contra producción (`-676.2974256246 meV`, 2000w,
semilla 11) en las 4 corridas de la comparación, con conf restaurado antes
de cada una:

| Ronda | Producción | Split |
|---|---|---|
| 1 | 60,87 s | 24,48 s |
| 2 | 59,45 s | 22,35 s |
| **Media** | **60,16 s** | **23,42 s** |

**~2,6x más rápido (61% menos tiempo)** -- muy por encima de lo esperado
(se preveía una ganancia modesta, tipo "esconder gratis" `vpot_t` detrás de
`derananum_t`).

### Mecanismo: presión de registros, no (solo) concurrencia

Se probó forzar `k_derananum_resto_t` al mismo stream que todo lo demás
(sin concurrencia real) durante la investigación del bug de reproducibilidad
-- el problema de reproducibilidad no cambió, pero de paso confirma que la
ganancia de rendimiento no depende únicamente del solape entre streams.
Registros reales (`ncu --metrics launch__registers_per_thread`, medido en
la corrida real, no en el `.o` sin enlazar):

| Kernel | Registros | Tiempo medio/llamada |
|---|---|---|
| `derananum()` original (monolítico, vía `k_derananum_t`) | 126 | 20,5 ms |
| `k_derananum_he4_t` (solo He4) | **88** | 2,33 ms |
| `k_derananum_resto_t` (resto) | 126 | 2,63 ms |
| `k_derananum_join_t` (cierre) | 40 | 0,06 ms |

`derananum()` mantiene vivas a la vez las variables locales de las 4 partes
durante toda la función (8 arrays: `d1wfhe4`, `d2wfhe4`, `d1wfhe3`,
`d2wfhe3`, `d1wfm`, `d2wfm`, `d1wfx`, `d2wfx`), forzando 126 registros
aunque cada bucle solo use un subconjunto en cada momento. Al aislar la
parte He4 en su propio kernel, solo necesita las variables de su propia
parte vivas a la vez → 88 registros → mejor ocupación → corre más rápido
pese a hacer más trabajo real (el bucle de 190 pares).

**Nota sobre cómo se cuentan los registros**: no es una suma de todo lo
que usa el kernel a lo largo de su ejecución -- es el **pico simultáneo**
en el momento de mayor exigencia. Un registro se reutiliza en cuanto la
variable que contenía ya no hace falta, así que llamadas a subrutinas que
se ejecutan en momentos distintos (no a la vez) no se suman entre sí; el
kernel solo necesita tantos registros como el momento más exigente de
toda su ejecución. Esto explica por qué `k_derananum_resto_t` (que llama
a 6 subrutinas distintas, una detrás de otra) se queda exactamente en 126:
lo marca una sola de ellas en su momento más exigente (ver Parte 2), no la
suma de las 6.

## Parte 2: bucles `nhe4+1,ngatom` → `nhe3` (código muerto demostrable)

### El problema

Con `nhe3=0` (parameter, decisión de alcance ya fijada en
`myexp-optimizacion.md`), varios bucles en `wavefhe3`, `wavefm`, `getcm` y
`wavefx` recorren el rango de átomos de He3 en el array `atom`:

```fortran
do iatom = nhe4+1, ngatom     ! rango de He3: vacio EN LA PRACTICA (ngatom=nhe4+nhe3=nhe4)
  ...
enddo
```

El número de vueltas es siempre `ngatom - nhe4`, que por construcción
(`ngatom = nhe4 + nhe3`, `mentradatos.f90:352`) es exactamente `nhe3` --
pero el compilador, mirando solo esta función, no ve esa relación (vive en
otro fichero) y no puede demostrar que el bucle está vacío. `nhe4` no es
él mismo el problema -- es una variable real (tamaño de la gota, cambia
entre simulaciones) que aparece aquí solo como desplazamiento para
localizar dónde empezarían los átomos de He3 en el array, no como sujeto
de cómputo del bucle.

### El arreglo

Reescribir el bucle en términos de `nhe3` directamente (mismo número de
vueltas, expresado con la variable correcta):

```fortran
do jhe3 = 1, nhe3        ! nhe3 SI es parameter=0 -- demostrable en compilacion
  iatom = nhe4 + jhe3
  ...
enddo
```

`nhe4` sigue siendo libre de variar (se usa solo como desplazamiento
dentro del bucle, no como límite), pero ahora el compilador puede evaluar
`1, 0` en tiempo de compilación y eliminar el bucle entero.

Aplicado en: `wavefm` (bucle interno), `getcm` (suma de masas He3),
`wavefhe3` (2 bucles: relleno de `rb` y parejas He3-He3), `wavefx`
(interacción impureza-He3 vía `uhe3x`).

### Resultado: registros reales, verificado bit a bit

| Función | Antes | Después |
|---|---|---|
| `wavefhe3` | 91 registros | **24** |
| `wavefm` | 80 registros | **24** |
| `wavefx` | 82 registros | **58** |

Energía final tras el arreglo: `-676.2974256246 meV` -- idéntica a antes,
confirmando que el cambio no afecta al resultado (código que nunca se
ejecutaba, solo se demuestra que no se ejecuta).

### Por qué NO bajó el total de `k_derananum_resto_t`

Se comprobó con 2 pruebas directas que el techo de 126 registros de
`k_derananum_resto_t` no viene de código de He3:

1. Se quitó físicamente la llamada a `duhe3x` (126 registros, la única
   pieza de He3 que quedaba con ese coste, detrás de un bucle ya
   correctamente acotado por `nhe3` desde el código original) -- **el
   número no cambió**.
2. Se redujeron los arrays locales de `k_derananum_resto_t` de tamaño 64 a
   32 -- **tampoco cambió**.

La causa real: `duhe4x` (derivada de la interacción impureza-He4,
expansión de Legendre hasta l=4) cuesta **126 registros como función
independiente**, y es una llamada real que sí se ejecuta (`nhe4=20`
iteraciones genuinas, nada que ver con `nhe3`). Coincidencia exacta de
número con el techo anterior de `derananum()` completo -- no es la misma
causa, es una función distinta que da la casualidad de necesitar el mismo
orden de magnitud de registros.

**Conclusión de esta parte**: no hace falta borrar código de He3 para
seguir bajando `k_derananum_resto_t` -- ya se extrajo lo que había ahí (91→24,
80→24, 82→58 en las funciones afectadas). El margen que queda está en
`duhe4x` en sí (física real de la impureza), una investigación distinta.

## Barrido de escalas (500-3000w)

Verificado bit a bit contra producción en las 4 escalas (misma semilla,
conf restaurado antes de cada corrida):

| Walkers | Producción | Split | Aceleración |
|---|---|---|---|
| 500 | 26,84 s | 10,26 s | 2,62x |
| 1000 | 37,91 s | 14,21 s | 2,67x |
| 2000 | 57,82 s | 22,01 s | 2,63x |
| 3000 (barrido inicial) | 82,48 s | 42,70 s | 1,93x |
| 3000 (ronda A, orden alterno) | 81,08 s | 38,05 s | 2,13x |
| 3000 (ronda B, orden alterno) | 86,01 s | 40,37 s | 2,13x |

Energía idéntica bit a bit en todas las corridas de cada escala
(`-683.4776947558` / `-679.3359577544` / `-676.2974256246` /
`-678.0618871962` meV para 500/1000/1500/2000/3000w respectivamente).

**Hallazgo abierto**: la aceleración se mantiene estable (~2,6x) en
500-2000w, pero cae a ~2,1x en 3000w -- confirmado con 2 rondas alternas
adicionales (no es deriva térmica, la caída es consistente y reproducible
en las 3 mediciones). Causa no investigada todavía -- posible relación con
el límite de ~3000-3500 walkers para el heap de `device` documentado en
`derananum.md` Parte 9, pero es una hipótesis sin confirmar.

## Estado y siguiente paso

- Split de `derananum`: verificado correcto y ~2,6x más rápido en
  500-2000w (cae a ~2,1x en 3000w, sin explicar todavía, aunque sigue
  siendo una mejora neta en todas las escalas probadas) -- **migrado a
  producción** (`hibrido_instrumentado/derananum_split_mod.cuf` +
  `dmc2_pipeline.cuf`/`wavef_mod.cuf`/`der_wavefx_mod.cuf` actualizados,
  `compilar_pipeline.sh` con `derananum_split_mod.cuf` añadido a `FILES`).
  Verificado bit a bit tras la migración (`-615.5737694991 meV`, 2000w,
  semilla 11, coincide con `v3-cuda-optimización/optimizacion-vpot/`).
- Arreglo `nhe3` en los bucles: verificado correcto, mejora real a nivel
  de función, sin impacto medible en el cuello de botella actual de
  `resto_t` -- se mantiene en el código aislado por ser una mejora limpia
  y sin coste, pero no es la vía para seguir apretando registros.
- `duhe4x` por dentro: se localizaron 2 piezas de sus 126 registros --
  (1) arrays locales `pl`/`d1pl`/`d2pl` dimensionados con `lmax_dev=20`
  (margen genérico, `mlegendre_gpu.cuf:24`) cuando el valor real usado es
  `lxhe4=4`; (2) `calderplegd` (78 registros aparte), que SÍ está bien
  dimensionada (usa el `l` real recibido, no `lmax_dev`) -- su coste es
  inherente al cálculo, no desperdicio. A diferencia de `nhe3`, `lxhe4`
  **no es fijo** (varía según la simulación, puede ser 0 en otros casos,
  `mentradatos.f90`) -- no es el mismo tipo de arreglo sin riesgo.
  **Decisión**: no tocar `lmax_dev`/`duhe4x` -- no hay confianza suficiente
  sobre las implicaciones de cambiar ese margen en el resto del árbol
  (`calpleg` para He3, etc.) para el beneficio incierto que daría. Se
  queda como está.

## Ficheros

- `gpu-split/`: **recortada** a los ficheros realmente editados
  (`dmc2_pipeline.cuf`, `derananum_split_mod.cuf` nuevo,
  `wavef_mod.cuf`/`der_wavefx_mod.cuf` con el arreglo `nhe3`, `in.mcv`,
  `tiempos_opcion7.dat`) -- ya no es una copia completa compilable por
  sí sola. Para recompilar, copiar estos ficheros sobre una copia
  fresca de `../../v2-cuda-integracion/hibrido_instrumentado/`.
- `compilar_split.sh`: referencia de qué `FILES` se usaban (ya no
  ejecutable tal cual tras el recorte).
