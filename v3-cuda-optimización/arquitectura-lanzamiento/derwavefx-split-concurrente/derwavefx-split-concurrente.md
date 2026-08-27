# Sacar `derwavefx` de "resto" a su propio kernel concurrente: resultado NEGATIVO

## Objetivo

`k_derananum_resto_t` (del split de `derananum`, ver `derananum-split-concurrente.md`)
se queda en 126 registros — el mismo techo que tenía `derananum()` monolítico antes
del split. La Parte 2 de esa investigación ya localizó la causa exacta: `duhe4x`
(la derivada de la interacción impureza-He4, dentro de `derwavefx`) cuesta 126
registros como función independiente, y es la única llamada de "resto" que no se
reduce con `nhe3=0`.

Pregunta de esta investigación: si se saca **solo** `derwavefx` (la única llamada
que usa `duhe4x`) a un cuarto kernel concurrente, dejando "resto" con el resto de
llamadas (`wavefhe3`, `wavefm`, `wavefx`, `derwavefm`, `derwavefhe3` — todas
prácticamente gratis con `nhe3=0`), ¿mejora el tiempo real?

## El diseño

3 piezas independientes en vez de 2, todas leyendo el mismo `atom`/`sprop` de
entrada, combinadas al final por `k_derananum_join_t` (sin cambios en su lógica --
solo lee `d1wfx_s`/`d2wfx_s`/`d1zwfx_s`/`d2zwfx_s` de un kernel distinto ahora):

```fortran
call k_derananum_he4_t<<<blocks,threads,0,stream_a>>>(...)        ! sin cambios
call k_derananum_resto_t<<<blocks,threads,0,stream_c>>>(...)       ! SIN derwavefx
call k_derananum_derwavefx_t<<<blocks,threads,0,stream_d>>>(...)   ! NUEVO, solo derwavefx
call k_vpot_t<<<blocks,threads,0,stream_b>>>(...)
! ... eventos de espera a resto Y derwavefx ...
call k_derananum_join_t<<<blocks,threads,0,stream_a>>>(...)
```

Un `stream_d` nuevo, eventos `ev_dwfx1`/`ev_dwfx2` (mismo patrón que
`ev_resto1`/`ev_resto2`), y `k_derananum_join_t` espera a **ambos** eventos (resto
y derwavefx) antes de lanzarse -- sin tocar su lógica interna en absoluto.

## Verificación

Bit a bit correcto (`-615.5737694991 meV`, 2000w, semilla 11, idéntico a
producción con el split ya migrado).

## Registros: confirma la hipótesis exactamente

Medido con `ncu --metrics launch__registers_per_thread` sobre el binario real
(no `cuobjdump` sobre el `.o` intermedio -- con compilación separable, el `.o` no
refleja la asignación final de registros, solo el binario enlazado; comprobado que
`cuobjdump` daba un `REG:40` idéntico y sospechoso en los 4 kernels, descartado):

| Kernel | Registros antes | Registros después |
|---|---|---|
| `k_derananum_he4_t` | 88 | 88 (sin cambio) |
| `k_derananum_resto_t` | **126** | **67** |
| `k_derananum_derwavefx_t` (nuevo) | -- | **126** |
| `k_derananum_join_t` | 40 | 40 (sin cambio) |

Exactamente como predecía la Parte 2 de `derananum-split-concurrente.md`: quitar
`derwavefx` baja "resto" de 126 a 67 registros -- pero ese coste de 126 no
desaparece, se traslada íntegro al nuevo kernel (`duhe4x` sigue costando lo mismo,
es inherente al cálculo, no se ha tocado `lmax_dev`).

## Tiempo por kernel (`nsys`, 2000w)

| Kernel | Tiempo medio/llamada |
|---|---|
| `k_derananum_he4_t` | 2,673 ms (sin cambio, coherente con 88 registros sin tocar) |
| `k_derananum_resto_t` | 1,375 ms (baja de 2,684 ms -- menos trabajo real, no solo menos registros) |
| `k_derananum_derwavefx_t` | 2,302 ms |
| `k_derananum_join_t` | 0,061 ms |

## Resultado: NEGATIVO, tiempo real (rondas alternas, 2000w)

| Ronda | Producción (3 kernels) | Split derwavefx (4 kernels) | Diferencia |
|---|---|---|---|
| 1 | 24,07 s | 28,76 s | +19,5% |
| 2 | 25,61 s | 26,84 s | +4,8% |
| **Media** | **24,84 s** | **27,80 s** | **+11,9% más lento** |

Consistente en las dos rondas (siempre más lento, el orden no se invierte) -- no es
ruido térmico.

## Por qué no funciona, aun bajando registros de verdad

A diferencia del split original (`he4`+`resto` -> el techo de registros SÍ bajó, de
126 a un máximo de 88), aquí el "pico" que marca el camino crítico **no mejora**:
antes, el máximo entre las piezas concurrentes era `max(he4_t, resto_t)` = `max(88,
126)` en registros y `max(2,68 ms, 2,68 ms)` en tiempo (resto_t, con todo el trabajo
de antes, tardaba tanto como he4_t). Ahora es `max(he4_t, resto_t, derwavefx_t)` =
`max(88, 67, 126)` en registros y `max(2,67 ms, 1,38 ms, 2,30 ms)` en tiempo --
**`he4_t`, que no se ha tocado, sigue marcando un tiempo prácticamente idéntico al
que marcaba el `resto_t` viejo** (2,67 ms vs 2,68 ms). Bajar los registros de
`resto_t` no ayuda si la pieza que ya determinaba el camino crítico (`he4_t`) sigue
igual de lenta.

Y encima se añade un cuarto stream compitiendo por los mismos SMs, ya saturados de
peticiones concurrentes a una escala donde la ocupación real ya es muy baja (5-8%,
ver `optimizacion-vpot.md`) -- más kernels concurrentes pidiendo sitio en el mismo
recurso limitado, sin que el cuello de botella real (`he4_t`) se mueva, cuesta más
de lo que se gana.

**Lección para futuros intentos de subdividir más el split**: bajar los registros
de una pieza que **no** es la que marca el camino crítico no mejora el tiempo total
-- antes de aislar más trabajo, hay que confirmar primero cuál de las piezas
concurrentes es la que de verdad limita el paso, no asumir que cualquier reducción
de registros ayuda. Aquí `he4_t` (el bucle de parejas He4-He4 real, 190 pares) era
la pieza limitante desde el principio, y este cambio no la tocó en absoluto.

## Conclusión

Se descarta -- no se lleva a producción. `derananum-split-concurrente.md` (los 3
kernels: `he4`/`resto`/`join`) sigue siendo el estado en producción.

## Ficheros

- `gpu-derwavefx-split/derananum_split_mod.cuf`: `k_derananum_resto_t` recortada
  (sin `derwavefx`) + `k_derananum_derwavefx_t` nueva.
- `gpu-derwavefx-split/dmc2_pipeline.cuf`: `stream_d`, eventos `ev_dwfx1`/`ev_dwfx2`,
  las 2 horquillas actualizadas para lanzar y esperar la pieza nueva.
- `gpu-derwavefx-split/in.mcv`: configuración usada (2000w, 1+59 bloques×20 pasos,
  semilla 11).
- `gpu-derwavefx-split/nsys_kern_sum_2000w.txt`: resumen de kernels de `nsys`.
- `gpu-derwavefx-split/tiempo_r1.log/.time`, `tiempo_r2.log/.time`: las 2 rondas de
  tiempo real.
- No es copia completa compilable por sí sola -- copiar estos ficheros sobre una
  copia fresca de `../../../v2-cuda-integracion/hibrido_instrumentado/`.
