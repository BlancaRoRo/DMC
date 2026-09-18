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

## 4c. Protección de `ujas` contra el desbordamiento (Opción 3: acumular en `double`)

El apartado 4b dejaba un margen real, no solo teórico: `|ujas|` cruzó el umbral de aviso 50.289 veces en 1.000.000 de pasos, y el rango medido (`ujas` entre −99,74 y −41,63) queda peligrosamente cerca del límite de underflow absoluto de `float32` (`-103,28`, ver `derananum.md`). Antes de tocar el clip había que decidir cómo protegerlo. Se plantearon 3 opciones:

1. Recortar el clip (`umax`/`umin`) al rango real de `float` (`±85` en vez de `±200`) -- barato, pero sigue perdiendo precisión de forma silenciosa cerca del límite, solo evita el desbordamiento duro.
2. Suma compensada (Kahan) del acumulador en `float` -- recupera precisión sin cambiar de tipo, pero añade coste por cada par sumado (el bucle más caliente del kernel).
3. **Acumular `ujas` en `real(kind=r8)` (double), dejando el `log()`/`exp()` de cada par en `real(kind=4)` (hardware nativo `MUFU`)** -- elegida por el usuario. Solo la suma final y el `exp()` de cierre pasan a doble; el trabajo caro (~190 pares × `log`+`exp` por walker) sigue en hardware nativo de `float`, así que el coste añadido es mínimo (una variable más ancha que vive en registro, y un único `exp()` en doble por walker en vez de doscientos).

**Diseño**: en `wavef_derwavefhe4_float` (`der_wavefhe4_mod.cuf`), el acumulador pasa de `real(kind=4) :: ujas` a `real(kind=r8) :: ujas_d`. Por cada par, `rij_hi=log(rij)` y los `exp()` intermedios (`rijp2`, `rijp2p1`) se mantienen en `real(kind=4)` -- siguen usando `MUFU.LG2`/`MUFU.EX2` nativos --, y se acumulan en `ujas_d` mediante conversión explícita (`ujas_d = ujas_d - real(p1/rijp2, r8) - real(p3*rij, r8)`). Al cerrar el bucle, el clip (`umax=200.0_r8`, `umin=-200.0_r8`, los mismos parámetros que ya usa la versión original en `double` -- ya no hacen falta ajustados a `float`, porque `ujas_d` nunca estuvo en `float`) y el `exp()` final se hacen con `myexp()` (la versión bit-exacta en doble que ya usa el resto del proyecto). La salida `wfhe4` cambia de `real(kind=4)` a `real(kind=r8)` -- `k_derananum_he4_float_t` (`derananum_split_mod.cuf`) ya no necesita convertir el resultado, lo escribe directo.

Diagnóstico actualizado a la vez: `ujas_d_min_visto`/`ujas_d_max_visto` (rango real de `ujas_d`, en doble, sin el falso techo de `float`), `rijp2_min_visto`/`rijp2_max_visto` (rango del `exp()` intermedio en `float`, para vigilar que no se acerque a su límite de ~88,7/~1e30), y `n_wfhe4_no_finito` (cuenta si `wfhe4` sale `NaN` o mayor que `huge(1.0_r8)*0.99`). Todo con `atomicmax`/`atomicmin` sobre variables `device` -- confirmado que funcionan igual de bien sobre `real(kind=r8)` que sobre `real(kind=4)`.

**Verificación**: misma escala que el punto 2 de "Próximos pasos" de la sección anterior (10.000 pasos en vez de 1.000.000, ya no hace falta repetir la corrida larga porque el cambio no toca el rango de `ujas_d`, solo el tipo en el que vive): 1000 walkers, 1 bloque de equilibrio, 100 bloques × 100 pasos, mismo `conf.20.00.HH`/`etrial=-631,8` de siempre.

```
DIAGNOSTICO DE RANGO -- wavef_derwavefhe4_float (Opcion 3: ujas en double)
ujas_d MINIMO visto (antes del clip, double):  -9.97377294E+01
ujas_d MAXIMO visto (antes del clip, double):  -4.16299924E+01
rijp2  MINIMO visto (float, por par):           1.08276262E+01
rijp2  MAXIMO visto (float, por par):           1.10359852E+05
veces que wfhe4 salio NaN/Inf: 0

energia final de las configuraciones        -615.5737694990
numero de walkers que tengo finales         1000
```

- **Energía bit a bit idéntica** a la referencia en `double` y a la corrida de 4b -- `-615.5737694990`, mismo dígito, mismo 1000/1000 walkers finales.
- **`ujas_d` en el mismo rango físico de siempre** (−99,74 a −41,63) -- el cambio no altera el valor calculado, solo el tipo en el que se acumula y se recorta, así que no había motivo para esperar (ni se ve) diferencia frente al rango ya medido en 4b.
- **`n_wfhe4_no_finito = 0`** -- sin desbordamientos, y ahora por construcción: `ujas_d` nunca pasa por `float`, así que no puede tocar ni el límite de overflow (`+88,7`) ni el de underflow (`-103,28`) de `float32` -- esos límites ya no aplican a esta variable.
- `rijp2` (el `exp()` intermedio que sí sigue en `float`) llegó a `1,10×10⁵` en esta corrida -- lejos del límite de `float` (~3,4×10³⁸), sin señal de riesgo en esa parte.

## 5. Decisión

**Opción 3 implementada y verificada -- pendiente de subir a producción tras una revisión final.** El apartado 4b había dejado un riesgo real (50.289 cruces del umbral de aviso en 1.000.000 de pasos, aunque sin desbordar nunca) y 3 opciones sobre la mesa; se eligió la Opción 3 (acumular `ujas` en `double`) por eliminar el riesgo *por construcción* en vez de solo recortar el margen, con coste añadido mínimo (el bucle caliente de `log`/`exp` por par sigue enteramente en hardware nativo de `float`). Verificado a 10.000 pasos: energía bit a bit idéntica a la referencia, cero valores no finitos, mismo rango físico de `ujas` que la corrida de 1.000.000 de pasos. Con esto se cierra la línea de protección de `ujas` abierta en 4b; queda pendiente decidir si se lleva a producción junto con el resto de conversiones a `float` de esta investigación, o de forma independiente.

### Contexto multi-GPU (`v4-cuda-pruebas/v100-fp64-nativo/`)

Confirmado con SASS real en una segunda GPU (Tesla V100, Volta, `sm_70`, `fluid3`): **la falta de hardware nativo de `exp`/`log` en doble no es una limitación de la RTX 4060 en concreto -- es una restricción del propio hardware MUFU de NVIDIA, presente también en una GPU de centro de datos real.** Lo que sí cambia en la V100 es el throughput de la aritmética básica en doble (ratio FP64:FP32 real de 1:2, frente al ~1:32 de la RTX 4060) -- la V100 podría acabar siendo más rápida que la RTX 4060 en `double` en términos absolutos, aunque `float` debería seguir ganando en relativo dentro de la propia V100 (menos instrucciones en total, sea cual sea la velocidad de cada una). Pendiente de confirmar con un benchmark real en la V100 (Paso 2 de esa prueba).

### Próximos pasos de esta línea

1. ~~**Protección de underflow de `ujas`**~~ -- resuelto en el apartado 4c: en vez de ajustar el clip, se elimina el riesgo por construcción acumulando `ujas` en `double` (Opción 3).
2. ~~**Repetir la validación**~~ -- hecho en 4c, 10.000 pasos, energía bit a bit idéntica.
3. **Buscar un segundo método candidato** de coste comparable a `wavef_derwavefhe4` para probar el mismo cambio a `float`. La tabla de coste real por función (perfilado `ncu --page source`, `k_derananum_t`+`k_vpot_t`, 1.500 walkers) está en `v3-cuda-optimización/funciones-matematicas/optimización-mypow/optimizacion-mypow.md` §1 (tabla original) y §6 (reperfilado post-optimización, la más actual) -- de ahí se sacan los candidatos, no de una intuición sobre la forma algebraica. Esa tabla revisó la hipótesis inicial (`wavefx`, por tener la misma forma que `wavef_derwavefhe4`): `wavefx`+`derwavefx` es solo ~1,3% del tiempo total, frente a `vp_hehe`+`v_hehe` (~14%), `duhe4x`+`uhe4x` (~11%) y `he_dihydrogen` (~8,7%), los tres todavía en `double`. ~~Elegido `vp_hehe`/`v_hehe`~~ -- medido el riesgo de cancelación de los 4 candidatos (los 3 de la tabla + `duhe4x` separado de `uhe4x`) en `candidatos-float-riesgo-cancelacion.md`: los 3 con coste real (`duhe4x`, `he_dihydrogen`, `vp_hehe`/`v_hehe`) tienen cancelación catastrófica real, un problema que la Opción 3 (acumular en `double`) no resuelve porque la pérdida ya ocurre dentro de los propios términos en `float`. **Corrección importante**: la primera medición solo cubrió `uhe4x` (limpio, 0 cancelación) y etiquetó el par entero "`duhe4x`/`uhe4x`" como seguro sin haber medido `duhe4x` -- una pregunta del usuario detectó el hueco. `duhe4x` (el gradiente/laplaciano, la mitad que de verdad importa para el DMC) resultó tener la cancelación **más severa de los 4 candidatos** (50-53% de las iteraciones, frente a ~0,3-1% en los otros dos). Ningún candidato con coste real queda listo para convertir sin diseñar antes una protección específica contra la cancelación.

Ver `stall-float-vs-double-derananum-he4.md` para la medición de stall de warps (con `ncu`) que faltaba: el stall total cae a menos de la mitad, pero el cuello de botella empieza a desplazarse de cómputo (MIO/`short_scoreboard`) hacia memoria (`long_scoreboard`).

## Ficheros

- Copia aislada: `/tmp/float-vs-double-test/` (no persistida).
- Verificación de 4 semillas: `/tmp/verifica_float_seeds/` (no persistida).
