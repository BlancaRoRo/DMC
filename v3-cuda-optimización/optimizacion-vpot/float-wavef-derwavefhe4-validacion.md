# `wavef_derwavefhe4` en `float`: validación en corrida real, 4 semillas

## 1. Objetivo

`benchmark-float-vs-double.md` midió que `wavef_derwavefhe4` en `float` es 3,85x más rápida (benchmark aislado, sin tocar la simulación real). Este documento responde la pregunta que quedaba abierta: **¿sigue siendo físicamente válido el resultado dentro de una corrida DMC real?**

## 2. Diseño

`k_derananum_he4_float_t`: misma interfaz exacta que `k_derananum_he4_t` (mismos argumentos, mismos arrays de salida en `double`), pero el **cálculo interno** de `wavef_derwavefhe4` se hace en `real(kind=4)` -- el resultado se convierte a `double` solo al escribir la salida (`wfhe4_s(i) = real(wfhe4_l, r8)`). El resto del pipeline (`k_derananum_join_t`, `k_fase_c`, control de población, etc.) no cambia ni se entera -- sigue operando en `double` sobre el resultado ya convertido.

Sustituido en las 2 horquillas de `dmc2_pipeline.cuf` (llamada a `k_derananum_he4_t` → `k_derananum_he4_float_t`), sobre la configuración de producción real (2000w, 59 bloques, 20 pasos).

## 3. Resultado: diferencia indetectable frente a la referencia en `double`

4 semillas (11, 97, 42, 777), `conf.20.00.HH` fresco, comparado contra la producción real sin tocar:

| Semilla | `double` (referencia) | `float` (`he4` en simple precisión) | Diferencia | Energía final config. |
|---|---|---|---|---|
| 11 | −676,8178220759 ± 1,84465726 | −676,8178040472 ± 1,84465668 | 0,0000180 | idéntica en ambas |
| 97 | −677,4045573550 ± 1,80329062 | −677,4045392938 ± 1,80329008 | 0,0000181 | idéntica en ambas |
| 42 | −678,4074405137 ± 1,92476309 | −678,4074224982 ± 1,92476254 | 0,0000180 | idéntica en ambas |
| 777 | −678,9230457352 ± 1,70632962 | −678,9230276072 ± 1,70632913 | 0,0000181 | idéntica en ambas |

**La diferencia es de ~0,000018 meV en las 4 semillas, consistente** -- unas **100.000 veces menor** que el error estadístico de la propia medida (±1,7-1,9 meV). "Energía final de las configuraciones" (el chequeo de integridad de la población que se usa en toda la sesión) idéntica en las 8 corridas -- sin colapso ni corrupción de la población de walkers, número de walkers finales correcto (2000/2000 en el caso base).

## 4. Interpretación

Con 4 semillas y una diferencia tan consistente y tan por debajo del ruido estadístico, el resultado apunta a que sustituir `wavef_derwavefhe4` por su versión en `float` **no introduce sesgo detectable** en esta simulación concreta, con esta escala de walkers/pasos. Dicho esto, hay que ser preciso sobre lo que esto demuestra y lo que no:

- **Sí demuestra**: en una corrida de la escala de producción real (2000w, 1180 pasos DMC), la diferencia es indetectable frente al ruido estadístico -- no es una prueba de "1 paso", es la corrida completa que se usa como referencia en todo `v3-cuda-optimización/`.
- **No demuestra** (fuera de alcance de esta prueba): que la diferencia se mantenga igual de pequeña en corridas mucho más largas (la escala del TFG real, 100.000 pasos) o que no haya un sesgo sistemático que solo se note acumulado sobre muchísimos más pasos -- el error estadístico baja con más estadística, así que una diferencia que hoy es "0,00001σ" podría dejar de ser invisible si el error baja lo suficiente en una corrida mucho más larga. No se ha probado a esa escala.

## 4b. Validación a escala larga (1.000.000 de pasos) + contador de overflow/underflow

Quedaba pendiente lo que la sección anterior marcaba como fuera de alcance: ¿se mantiene el sesgo igual de pequeño en una corrida mucho más larga? Y, aparte, el hallazgo de `stall-float-vs-double-derananum-he4.md` sobre el clip `umax`/`umin=±200` (pensado para el rango de `double`, muy por encima del límite real de overflow de `exp()` en `float`, ~88,7) quedaba sin comprobar en la práctica.

**Diseño**: misma reconstrucción aislada (`/tmp/float-vs-double-test/`, no persistida) con dos contadores `device` añadidos a `wavef_derwavefhe4_float` (`der_wavefhe4_mod.cuf`): uno cuenta cuántas veces `|ujas|` (antes del clip) supera 80,0 (margen de aviso antes del límite real de `float`), otro cuenta cuántas veces `wfhe4` sale `NaN` o `>1e30`. Corrida real: 1000 walkers, 1 bloque de equilibrio, 100 bloques de cálculo, 10.000 pasos/bloque = **1.000.000 de pasos DMC totales**, mismo `conf.20.00.HH` y `etrial=-631,8` verificados de siempre — el mismo punto exacto de la batería `test-pasos` (`test-10000p`) ya medido en `double` para poder comparar directo.

**Resultado**:

| | `double` (`test-10000p`, ya medido) | `float` (esta prueba) |
|---|---|---|
| Energía final de las configuraciones | −615,5737694990 | **−615,5737694990** (idéntica) |
| Walkers finales | 1000/1000 | 1000/1000 |
| Tiempo de pared | 4918,33 s (~1,37 h) | 4863,76 s (~1,35 h) |

```
DIAGNOSTICO OVERFLOW/UNDERFLOW -- wavef_derwavefhe4_float
veces que |ujas| (antes del clip) supero 80.0: 50289
veces que wfhe4 salio NaN o > 1e30: 0
```

**Interpretación**:

- **La energía final sale bit a bit idéntica** a la referencia en `double`, incluso a 1.000.000 de pasos — muy por encima de los 1180 pasos de la validación de producción. Ninguna señal de que el sesgo (~0,000018 meV a escala corta) se acumule de forma visible a esta escala.
- **El margen de seguridad SÍ se toca de verdad**, no es solo un riesgo teórico: `|ujas|` superó el umbral de aviso (80) **50.289 veces** a lo largo de la corrida — sobre del orden de 10¹¹ evaluaciones (~1000 walkers × 1.000.000 pasos × ~190 pares), una tasa baja (~2,6×10⁻⁷) pero decididamente no nula.
- **Pese a eso, `wfhe4` no llegó a desbordar ni una sola vez** (`NaN`/`>1e30`: 0) — el clip de `±200` (heredado de `double`) sigue conteniendo el valor antes de que `exp()` en `float` llegue a su límite real (~88,7), al menos para esta física y esta escala.
- **Tiempo de pared prácticamente igual** (4863,76 s vs 4918,33 s, ~1,1% más rápido) — coherente con lo ya visto en el pipeline: `wavef_derwavefhe4` es solo una pieza del coste total por paso (fase_a, vpot, fase_c/d/f/g/h siguen en `double`), así que un 3,77x de mejora en esa pieza concreta no se traduce en una mejora visible del tiempo total de la corrida completa. La ganancia de esta línea de trabajo está en el *stall* y en la instrucción, no (todavía) en el reloj de pared del pipeline entero.

## 5. Decisión

**No se lleva a producción todavía.** La escala larga (1.000.000 de pasos, una sola semilla) despeja la duda principal -- energía bit a bit idéntica, sin sesgo acumulado visible -- pero abre una segunda, nueva: el margen de overflow se toca de verdad (50.289 veces por encima del umbral de aviso), aunque nunca llegó a desbordar. Antes de dar este candidato por cerrado haría falta, como mínimo, ajustar el clip `umax`/`umin` al rango real de `float` (algo como `±85`, no `±200` heredado de `double`) y repetir la validación en 4 semillas a esta misma escala larga -- no basta con que "no haya desbordado esta vez". Queda documentado como candidato fuerte, con esa condición añadida, para revisar junto con los resultados de `pruebas-sfu/`.

Ver `stall-float-vs-double-derananum-he4.md` para la medición de stall de warps (con `ncu`) que faltaba: el stall total cae a menos de la mitad, pero el cuello de botella empieza a desplazarse de cómputo (MIO/`short_scoreboard`) hacia memoria (`long_scoreboard`).

## Ficheros

- Copia aislada: `/tmp/float-vs-double-test/` (no persistida).
- Verificación de 4 semillas: `/tmp/verifica_float_seeds/` (no persistida).
