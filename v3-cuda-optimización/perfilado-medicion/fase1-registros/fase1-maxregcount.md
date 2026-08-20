# Fase 1, opción 2 del menú: limitar registros por flag del compilador (`-gpu=maxregcount:N`)

Resultado: **negativo**. No cambia ni la ocupación ni el tiempo de kernel, en ningún valor de `N` probado. Documentado con la razón exacta, siguiendo el mismo criterio que las Partes 6-10 de `tiempo-ncu-resultado.md`.

## Condiciones de la prueba

- Copia aislada de `hibrido_instrumentado/` (`hibrido_maxregcount/`, no se toca el binario validado de `v2-cuda-integracion/`).
- 4 binarios: `qmccluster_pipeline_baseline` (sin flag, control) y `_reg128`/`_reg96`/`_reg64` (`-gpu=lineinfo,maxregcount:N` añadido a la compilación existente, `-cuda -Kieee -Mnofma` sin cambios).
- Escala de medición: 1.500 walkers (misma que Fase 0).

## Verificación de corrección primero

`diff` de la tabla de bloques (1000w/1eq/2calc/20pasos) entre `baseline` y cada `_regN`: **vacío en los 3 casos** — bit a bit idéntico. El flag no cambia el resultado físico, solo la compilación. Energía total coincide con la ya vista en la Fase 0 para esta config (`-649,53 ± 13,07 meV`).

## Medición con `ncu`

| | `baseline` (sin cap) | `reg128` | `reg96` | `reg64` |
|---|---|---|---|---|
| **`k_derananum_t`** registros/hilo | 144 | 128 | 96 | 64 |
| `k_derananum_t` waves/SM | 0,33 | 0,24 | 0,20 | 0,16 |
| `k_derananum_t` warps activos (%) | 4,77 | 4,80 | 4,80 | 4,76 |
| `k_derananum_t` duración | 37,29 ms | 37,68 ms | 37,72 ms | 38,30 ms |
| **`k_vpot_t`** registros/hilo | 247 | 128 | 96 | 64 |
| `k_vpot_t` waves/SM | 0,49 | 0,24 | 0,20 | 0,16 |
| `k_vpot_t` warps activos (%) | 4,84 | 4,86 | 4,84 | 4,84 |
| `k_vpot_t` duración | 8,49 ms | 8,25 ms | 8,30 ms | 8,33 ms |

**Los registros bajan exactamente como se pide (144→64, 247→64) pero la ocupación real (`warps activos`) se queda clavada en ~4,8% en los 4 casos, y la duración no mejora — en `derananum` incluso empeora ligeramente al bajar más el límite.** Las "waves por SM" (cuántos bloques caben a la vez) bajan encima, en vez de subir — lo contrario de lo que se buscaba.

## Por qué no funcionó — la causa real

El límite de 25% de ocupación teórica "por registros" que marcaba `ncu` en la Fase 0 es un techo que **nunca se llegó a rozar en la práctica**. La cuenta real:

```
nmax = 2 x 1500 walkers = 3.000
bloques lanzados = nmax / 32 hilos/bloque = 94 bloques, EN TOTAL PARA TODA LA GPU
```

Con 94 bloques repartidos entre las SMs de la GPU (del orden de 20-24 en esta tarjeta), a cada SM le tocan de media **menos de 4 bloques** — muy por debajo de lo que incluso el límite de registros más restrictivo permitiría (con 64 registros/hilo cabrían muchos más bloques por SM de los que hay disponibles para repartir). **El cuello de botella nunca fue cuántos registros usa cada hilo — es que, a esta escala de walkers, sencillamente no hay bloques suficientes para llenar la GPU, siendo generosos o tacaños con los registros.** Por eso bajar registros no mueve la aguja: el recurso que falta no es "espacio de registro por SM", es "trabajo total lanzado".

## Conclusión y siguiente paso

Esto **descarta la opción 2 del menú** (y, por la misma razón, hace improbable que la opción 1 — separar `derananum` en 4 kernels — ayude por sí sola: seguiría lanzando pocos bloques en total). Redirige la prioridad hacia:

1. **Confirmar con datos si el tamaño de bloque (hoy 32 hilos fijo) importa** — no para "caber más bloques por registro" (ya descartado), sino para ver si consolidar el mismo trabajo en menos bloques pero con más warps cada uno cambia cómo se reparte entre SMs y cuánto se solapa la latencia de memoria dentro de un mismo bloque. Sigue siendo una incógnita real, no descartada por esta prueba.
2. **El techo real puede ser, sencillamente, que a 1.500-3.000 walkers no hay suficiente paralelismo para esta GPU** — coherente con `test-walker.md` (la aceleración se aplana justo en ese rango). Si es así, la vía de mejora no está dentro de un kernel concreto, sino en **procesar más trabajo por lanzamiento** (Fase 3 del plan: kernels persistentes que hagan varios pasos DMC sin volver al host) o aceptar que este es el techo de esta arquitectura de pipeline a esta escala.

## Ficheros

- `hibrido_maxregcount/`: **eliminada** -- esta prueba no editaba ningún
  fichero fuente (solo añadía el flag `-gpu=maxregcount:N` en la
  compilación), así que no había nada que conservar de la copia
  completa. `compilar_maxregcount.sh` documenta el flag exacto usado.
- `compilar_maxregcount.sh`: script de compilación parametrizado (`./compilar_maxregcount.sh <N>`), referencia del flag usado.
- `ncu_qmccluster_pipeline_{baseline,reg128,reg96,reg64}.csv`: perfiles completos de cada variante (evidencia cruda, respalda la tabla de arriba).
