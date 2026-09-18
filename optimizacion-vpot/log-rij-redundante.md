# `log(rij)` redundante en `duhe4x`/`uhe4x`/`duhe3x`/`uhe3x`

## 1. Objetivo

El usuario, revisando `uhe4x` para ver si el patrón de `duhe4x` se podía "minimizar a una sola llamada", señaló:

```fortran
ul=-pxhe4(1,il)/mypow_desde_log(rij_hi,rij_lo,pxhe4(2,il))-pxhe4(3,il)*mypow_desde_log(rij_hi,rij_lo,pxhe4(4,il))  &
 &      -pxhe4(5,il)*log(rij)
```

## 2. El hallazgo: no es una división, es una llamada nativa repetida

La división de esta línea (`pxhe4(1,il)/mypow_desde_log(...)`) no tiene redundancia que cachear -- es una sola división, usada una vez, como en `wavefx` (`reciprocos-derwavefx.md` §3). Pero mirando el resto de la línea: `mypow_log(rij, rij_hi, rij_lo)` ya se llamó unas líneas antes, y su cuerpo real es:

```fortran
! glibc_pow.cuf
subroutine mypow_log(x, hi, lo)
    hi = log(x)
    lo = 0.0_r8
end subroutine
```

Es decir, **`rij_hi` ya es exactamente `log(rij)`** -- misma llamada nativa, mismo argumento, sin ninguna operación intermedia que pueda redondear distinto. `-pxhe4(5,il)*log(rij)` está recalculando desde cero un valor que ya está en el ámbito con otro nombre.

Este patrón se repite en las 4 funciones de la familia (todas llaman a `mypow_log(rij,...)` antes de su propio `log(rij)`):

| Función | Fichero | Línea | Estado |
|---|---|---|---|
| `duhe4x` | `d_uhex4_mod.cuf` | 97 | Viva |
| `uhe4x` | `d_uhex4_mod.cuf` | 134 | Viva |
| `duhe3x` | `der_wavefx_mod.cuf` | 91 | Muerta (`nhe3=0`) |
| `uhe3x` | `der_wavefx_mod.cuf` | 129 | Muerta (`nhe3=0`) |

Se arreglan las 4 por consistencia (mismo criterio ya aplicado en el resto del árbol con código muerto: "se deja igual de correcto que la parte viva").

## 3. El cambio

```fortran
! antes
-pxhe4(5,il)*log(rij)
! despues
-pxhe4(5,il)*rij_hi
```

(y análogo con `pxhe3` en `duhe3x`/`uhe3x`). **Esto no es una reformulación algebraica** como los recíprocos cacheados -- es sustituir una expresión por otra que ya vale exactamente lo mismo (CSE real, no aproximado). Garantizado bit a bit por construcción, no por prueba.

## 4. Verificación

Aun así, mismo protocolo de siempre por rigor: pipeline completo, 4 semillas (11, 97, 42, 777), `conf.20.00.HH` fresco. **Bit a bit idéntico en las 4 semillas** — `diff` completo sin ninguna línea de física distinta, binarios genuinamente distintos.

## 5. Medición: mayor de lo esperado, y en un sitio inesperado

El conteo **estático** (SASS) dio un resultado mixto y confuso: `duhe4x_` bajó de 31 a 15 `DFMA`, pero `uhe4x_`/`k_uhe4x_` subieron de 23 a 35 `DFMA` y de 5 a 17 `CALL` -- efecto secundario de cómo el compilador decide inlinear tras el cambio, no representativo del rendimiento real. La medida **dinámica** (`ncu`, lo que de verdad importa) en el kernel donde ambas se ejecutan (`k_derananum_resto_t`) fue clara y positiva:

| Métrica | Antes | Después | Cambio |
|---|---|---|---|
| Ciclos | 1.811.063 | 1.449.544 | **−20,0%** |
| Instrucciones FMA | 620.673 | 477.033 | **−23,1%** |
| Instrucciones XU (SFU) | 43.281 | 30.681 | **−29,1%** |

Sorpresa: hasta la SFU baja, pese a no haber tocado ninguna división -- indica que `log()` nativo usa internamente al menos una división en su algoritmo (probablemente en la reducción de rango), así que cada llamada eliminada se lleva también su propio coste de SFU. Es la mayor reducción de ciclos de toda esta línea de trabajo hasta ahora, viniendo de un cambio que no es ni un recíproco ni una constante de compilación -- es puro "no repitas un cálculo que ya tienes".

## 6. Decisión

**Se lleva a producción** (bit a bit idéntico por construcción, y por prueba en 4 semillas). Aplicado a `hibrido_instrumentado/d_uhex4_mod.cuf` y `der_wavefx_mod.cuf`, recompilado y verificado desde config fresca.

## Ficheros

- Verificación hecha directamente sobre copias de `hibrido_instrumentado/` — no persistida (quedó en `/tmp`, no en el repo).
