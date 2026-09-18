# Sustitución de `myexp`/`mypow`/`mysin`/`mycos`/`myacos` por las funciones nativas de CUDA

## 1. Objetivo

`split-he-dihidrogen.md` (Intento 8, migración a producción) encontró un techo de mejora explicado por **contención de SFU compartida** (`short_scoreboard`, 53-60% en los 3 kernels de `vpot`) que ninguna coreografía de streams conseguía esquivar. La pregunta que motiva esta investigación: las funciones matemáticas portadas a mano (`myexp`, `mypow`, `mysin`, `mycos`, `myacos`, en `glibc_exp_mod.cuf`/`glibc_pow.cuf`/`glibc_sincos.cuf`/`glibc_acos.cuf`) son reimplementaciones bit a bit de glibc construidas con tablas y polinomios — **¿merece la pena sustituirlas por las funciones nativas de nvfortran** (que si acaso usan la SFU directamente, en vez de emularla por software) para ver si eso alivia esa contención, y qué le pasa a la precisión al hacerlo?

## 2. El cambio

Se sustituyó el cuerpo de las 5 funciones públicas por la llamada nativa correspondiente, sin tocar su firma (mismos argumentos, mismo tipo de retorno) para no tener que tocar ningún sitio de llamada en el resto del árbol:

```fortran
! glibc_exp_mod.cuf
attributes(host, device) function myexp(x) result(y)
  real(kind=r8), intent (in) :: x
  real(kind=r8) :: y
    y = exp(x)
end function myexp

! glibc_pow.cuf
attributes(host, device) function mypow(x, y) result(r)
  real(kind=r8), intent (in) :: x, y
  real(kind=r8) :: r
    r = x**y
end function mypow

attributes(host, device) subroutine mypow_log(x, hi, lo)
  real(kind=r8), intent (in) :: x
  real(kind=r8), intent (out) :: hi, lo
    hi = log(x)
    lo = 0.0_r8
end subroutine mypow_log

attributes(host, device) function mypow_desde_log(hi, lo, y) result(r)
  real(kind=r8), intent (in) :: hi, lo, y
  real(kind=r8) :: r
    r = exp(y*hi)
end function mypow_desde_log

! glibc_sincos.cuf
attributes(host, device) function mysin(x) result(retval)
  real(kind=r8), intent (in) :: x
  real(kind=r8) :: retval
    retval = sin(x)
end function mysin

attributes(host, device) function mycos(x) result(retval)
  real(kind=r8), intent (in) :: x
  real(kind=r8) :: retval
    retval = cos(x)
end function mycos

! glibc_acos.cuf
attributes(host, device) function myacos(x) result(res)
  real(kind=r8), intent (in) :: x
  real(kind=r8) :: res
    res = acos(x)
end function myacos
```

`mypow_log`/`mypow_desde_log` (el split de `optimización-mypow/`, que reutiliza `log(x)` entre llamadas con la misma base) se conserva como estructura de llamada — solo cambia de dónde sale `log`/`exp`: ya no hay descomposición en precisión extendida (`hi`+`lo` tipo Dekker), `hi` es directamente `log(x)` nativo y `lo=0`. Las funciones auxiliares internas (`bits_of`, `top12_of`, `log_inline`, `do_sin`, `high32_of`...) y los kernels de prueba (`k_myexp`, `k_mypow`...) se dejan intactos — quedan como código muerto, sin llamador, igual criterio que otras piezas "sin usar, sin tocar" del árbol.

Copia de trabajo aislada: `/tmp/prueba_math_nativo/` (no persistida — solo los 4 ficheros editados y los logs se guardan aquí, en `nativa/` y `resultados_nativa/`).

## 3. Verificación bit a bit contra la versión portada

Dos semillas, mismo `in.mcv` (2000 walkers, 59 bloques de cálculo, 20 pasos/bloque, `opot=4`), mismo `conf.20.00.HH` fresco (`v1-cuda-desarrollo/ccuerpo/conf.20.00.HH`) en los dos casos:

| Semilla | Energía total (cm⁻¹) — portada | Energía total (cm⁻¹) — nativa | `diff` de los 79 bloques |
|---|---|---|---|
| 11 | −5461.4620412102 ± 14.88513638 | −5461.4620412102 ± 14.88513638 | **0 líneas distintas** |
| 97 | −5466.1965980595 ± 14.55133561 | −5466.1965980595 ± 14.55133561 | **0 líneas distintas** |

El `diff` completo entre los `stdout` de ambas variantes (bloque a bloque: `E_bloque`, `E_calculo`, `E_growth`, `Poblacion`, en los 79 bloques) solo difiere en las marcas de tiempo/reloj — ni un solo dígito de física cambia, en ninguna de las dos semillas. Esto es más fuerte que solo comparar el resumen final: significa que cada decisión individual del algoritmo (aceptación de movimiento, branching por walker, en cada uno de los ~1180 pasos) coincide exactamente entre las dos variantes.

Comparación adicional contra la referencia real (CPU, `gfortran`, `opcion=4`, misma semilla 11, mismo `conf.20.00.HH` fresco): `Energia total = −5464.1040928787 ± 15.63934442`. Diferencia frente a la GPU (portada o nativa, da igual): 2,64, frente a un error combinado de ~21 — compatible dentro de 1σ, como es de esperar entre RNG de arquitecturas distintas (criterio ya establecido en `docs/hibrido.md` §5.2).

**Aviso importante — no generalizar sin más pruebas**: esto contradice en apariencia `optimización-mypow/` (sustituir `mypow` por `x**y` nativo divergía en 16 de 60 pares sintéticos, 26,7%). La explicación más razonable es que esa prueba cubría un rango de valores genérico y amplio, mientras que aquí los argumentos que de verdad le llegan a `mypow`/`myexp` en esta física están acotados a un rango mucho más estrecho (distancias/energías físicas de un cúmulo de He) — dentro de ese rango, coincide exacto en las 2 semillas probadas. Es una observación real pero con muestra pequeña (1 configuración, 2 semillas); antes de confiar en ello a otras escalas u otras configuraciones (`opot` distinto, impureza distinta) habría que repetir esta misma verificación ahí.

## 4. Tiempo de ejecución

Mismo `in.mcv`/semilla, tiempo interno reportado por el propio programa (`tiempo de CPU en s`, más preciso que el `time` de shell):

| Semilla | Portada | Nativa | Diferencia |
|---|---|---|---|
| 11 | 20,74657 s | 15,86013 s | **−23,6%** |
| 97 | 20,49927 s | 17,02288 s | **−17,0%** |

Como referencia de escala: la CPU original (`gfortran`, `opcion=4`, semilla 11) tarda 159,106 s en la misma configuración.

## 5. ¿Esto alivia la contención de SFU? — medido con `ncu`

Perfilado de `k_vpot_3warp_t` (el kernel de producción del split de `vpot`, 3 lanzamientos comparables, `--launch-skip 2 --launch-count 3`):

| Pipe / métrica | Portada | Nativa | Cambio |
|---|---|---|---|
| `sm__inst_executed_pipe_xu.sum` (SFU) | 144.202 | 150.714 | **+4,5%** |
| `sm__inst_executed_pipe_fma.sum` | 1.864.971 | 866.903 | −53,5% |
| `sm__inst_executed_pipe_lsu.sum` | 4.058.677 | 1.798.409 | −55,7% |
| `smsp__...stalled_short_scoreboard...ratio` | 26,80 | 36,51 | +36,2% |

**No.** La pipe XU (SFU) apenas cambia (+4,5%, dentro de ruido de medición) al pasar de emulación por software a funciones nativas — la contención de SFU que documentó `split-he-dihidrogen.md` sigue exactamente igual en términos absolutos. Lo que sí cambia radicalmente es todo lo demás: FMA y LSU caen a la mitad porque desaparecen las tablas de consulta (`exp_tab`, `pow_log_tab`, `sincostab`, `asincos_tab`) y los polinomios de aproximación. El ratio de stall `short_scoreboard` **sube** (26,8%→36,5%) a pesar de que el kernel es más rápido en tiempo real — porque es una métrica relativa (stalls por instrucción emitida): con muchas menos instrucciones totales, el mismo número de esperas de la SFU pesa proporcionalmente más.

### ¿De dónde sale entonces la SFU, si no es de `exp`/`sin`/`cos`/`pow`?

Conteo de divisiones reales (`/`, sin comentarios ni declaraciones) en el código:

| Fichero | Divisiones reales |
|---|---|
| `glibc_exp_mod.cuf` (`myexp`) | 0 |
| `glibc_pow.cuf` (`mypow`) | 1 |
| `glibc_sincos.cuf` (`mysin`/`mycos`) | 3 |
| `glibc_acos.cuf` (`myacos`) | 2 |
| `He_dihydrogen.f` (la fórmula de física) | **136** |
| `mVheheVphehe_mod.cuf` (`V_hehe`/`Vp_hehe`) | **27** |

Las funciones matemáticas portadas evitan la división casi por completo (están construidas con tablas y polinomios precisamente para no depender de ella). La fórmula física en sí (`He_dihydrogen`, términos de amortiguamiento tipo Tang-Toennies con potencias `1/r^n`) tiene 163 divisiones reales — y en esta GPU la división en doble precisión pasa por la SFU (aproximación del recíproco + refinamiento). Esa es, con mucha probabilidad, la fuente real de las 144K-150K instrucciones XU medidas — no la elección de biblioteca para `exp`/`sin`/`cos`/`pow`. Consistente con que sustituir esas 5 funciones enteras (no solo `mypow`) apenas mueva la aguja de la SFU: **el techo real está en las divisiones de la fórmula física, no en las funciones trascendentales**.

## 6. Decisión

**Se lleva a producción**: mejora real de tiempo (17-24%), física verificada bit a bit idéntica en las 2 semillas probadas, y confirma (no contradice) el diagnóstico de contención de SFU de `split-he-dihidrogen.md` — solo que el origen no era `myexp`/`mypow`/`mysin`/`mycos`/`myacos`.

**Efecto colateral**: las tablas `exp_tab_fortran.txt`, `pow_log_tab_fortran.txt`, `sincostab_fortran.txt`, `toverp_fortran.txt`, `asincos_tab_fortran.txt`, `inroot_fortran.txt`, `powtwo_fortran.txt` y las funciones auxiliares que las usaban (`log_inline`, `pow_exp_inline`, `do_sin`/`do_cos`/`do_sincos`/`mybranred`/`reduce_sincos`/`branred_half`, la tabla `exp_tab`/`exp_specialcase`...) quedan sin ningún llamador real — se dejan sin borrar por ahora (documentación de la fórmula original, mismo criterio que el resto del árbol), pendiente de una limpieza futura si se decide que ya no hace falta conservarlas.

**Pendiente para dar por cerrada esta línea con más confianza**: repetir la verificación bit a bit en, al menos, otra escala de walkers y con `nhe3>0`/otro `opot` si alguna vez se prueban, dado que la muestra actual es de una sola configuración con 2 semillas (ver aviso de la sección 3).

## Ficheros

- `nativa/glibc_exp_mod.cuf`, `nativa/glibc_pow.cuf`, `nativa/glibc_sincos.cuf`, `nativa/glibc_acos.cuf`: los 4 ficheros editados, tal como se llevaron a producción.
- `resultados_nativa/`: logs completos (`out_seed11.log`, `out_seed97.log`) de la variante nativa y de la variante portada de referencia, para las 2 semillas.
