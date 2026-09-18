# Optimización de `myexp`

## 1. Objetivo

Después de partir `mypow` en `mypow_log`/`mypow_desde_log` (ver `../optimización-mypow/`), el reperfilado con `ncu` mostró `myexp` como el segundo método más caro (11,195% del tiempo total, frente al 8,7% de `He_dihydrogen` donde vive el problema real). El objetivo aquí es el mismo principio que con `mypow`: **`myexp(x)` en sí no se toca** (sigue siendo el puerto bit a bit de `__exp` de glibc, en `glibc_exp_mod.cuf`) — lo que se ataca es la cantidad de veces que se llama con el **mismo argumento** dentro de `He_dihydrogen.f`, que es el único sitio donde `myexp` se ejecuta de verdad en esta simulación (ver `optimización-mypow/optimizacion-mypow.md` sección 8, tabla de qué métodos son caminos muertos con `nhe3=0`).

## 2. El hallazgo

`He_dihydrogen.f` no llama a `myexp` directamente en su mayoría — llama a una familia de funciones de amortiguamiento Tang-Toennies (`F00`, `F0`...`F6`, `DF0`...`DF6`, `FN1`, `DFN1`, `FN2`, `DFN2`), y es **dentro de esa familia** donde se repite la llamada:

```
F00(x) = myexp(-x)          ! la unica que llama a myexp de verdad
F0(x)  = 1 - F00(x)
F1(x)  = -F00(x)*x
F2(x)  = -F00(x)*x**2/2
F3(x)  = -F00(x)*x**3/6
F4(x)  = -F00(x)*x**4/24
F5(x)  = -F00(x)*x**5/120
F6(x)  = -F00(x)*x**6/720

FN1(x) = F0(x)+F1(x)+F2(x)+F3(x)+F4(x)+F5(x)+F6(x)   ! 7 llamadas a F00(x), mismo x
FN2(x) = F0(x)+F1(x)+F2(x)                            ! 3 llamadas a F00(x), mismo x
```

`DF0`...`DF6`/`DFN1`/`DFN2` repiten exactamente el mismo patrón (con `DF0(x)=F00(x)` también).

Además, en el bloque de inducción de `He_dihydrogen` (el que ya se fusionó en `optimización-mypow/`, sección 8.1), `Ex0`/`Ey0`/`Ez0` llaman cada uno, por separado, a `FN2(btheta*rh1)`, `FN2(btheta*rh2)` y `FN2(btheta*r0)` — los mismos 3 argumentos, repetidos 3 veces (una por cada componente `Ex0`/`Ey0`/`Ez0`).

### Sitios vivos vs. código muerto

Igual que con `mypow`, `GTEST=.false.` siempre en esta simulación (única llamada real a `He_dihydrogen`, en `mpotenbh_mod.cuf:51`) — así que `DFN1`/`DFN2` (usadas en `dvdR`/`dvdtheta`/`dExdx`...`dEzdz`, todas dentro de `IF(GTEST)`) **nunca se ejecutan**. Solo `FN1`/`FN2` (usadas en `eterm2` y en `Ex0`/`Ey0`/`Ez0`, ambas fuera de `IF(GTEST)`) están vivas.

### Cuenta de llamadas a `myexp` por átomo, en la parte viva

| Uso | Llamadas a `myexp` ahora | Llamadas mínimas necesarias |
|---|---|---|
| `eterm1=a0*myexp(atheta-rnorm*btheta)` | 1 | 1 |
| `eterm2=FN1(rnorm*btheta)*c6theta/norm6` | 7 | 1 |
| `Ex0`/`Ey0`/`Ez0` → 9 llamadas a `FN2` (3 argumentos × 3 repeticiones) | 27 | 3 |
| **Total por átomo** | **35** | **5** |

Una reducción de **7x** en llamadas a `myexp` dentro de la parte de `He_dihydrogen` que se ejecuta de verdad.

## 3. El arreglo

Dos cambios independientes, que se pueden combinar. El cambio (a) **no es un solo paso**: son 2 pasos encadenados, y el segundo solo es posible una vez hecho el primero -- por eso en la tabla de la sección 4 las filas de `FN1`/`FN2`/`DFN1`/`DFN2` dicen explícitamente "paso 1" y "paso 2".

**a) Compartir `F00(x)` dentro de `FN1`/`FN2`** (y `DFN1`/`DFN2`, por consistencia aunque sean código muerto):

- **Paso 1 -- "deshacer" las llamadas (desplegar `F0`...`F6` en su fórmula, dentro del cuerpo de `FN1`)**: ahora mismo `FN1(x)` no ve las fórmulas de `F0`...`F6` -- solo ve 7 llamadas a función opacas. El primer paso es sustituir cada llamada (`F0(x)`, `F1(x)`, ..., `F6(x)`) por la expresión algebraica que esa función calcula por dentro, copiada tal cual dentro de `FN1`:

  ```fortran
  ! FN1(x) = F0(x)+F1(x)+F2(x)+F3(x)+F4(x)+F5(x)+F6(x), con cada Fi(x) desplegada:
  r =       (1.d0    - F00(x))            ! F0(x)
  r = r + ( -F00(x)*x            )        ! F1(x)
  r = r + ( -F00(x)*x**2/2.d0    )        ! F2(x)
  r = r + ( -F00(x)*x**3/6.d0    )        ! F3(x)
  r = r + ( -F00(x)*x**4/24.d0   )        ! F4(x)
  r = r + ( -F00(x)*x**5/120.d0  )        ! F5(x)
  r = r + ( -F00(x)*x**6/720.d0  )        ! F6(x)
  ```
  Este paso, por sí solo, todavía no ahorra nada -- `F00(x)` sigue apareciendo 7 veces. Pero ahora, al tener las 7 fórmulas desplegadas y a la vista en el mismo sitio, se puede ver que **todas comparten el mismo factor `F00(x)`**, algo que no se veía mientras `F0`...`F6` eran cajas negras.

- **Paso 2 -- sacar factor común (`F00(x)` se calcula 1 vez, en una variable nueva)**: con las 7 fórmulas ya desplegadas, se reemplaza cada aparición de `F00(x)` por una variable local (`f00`) calculada una sola vez al principio:

  ```fortran
  f00 = myexp(-x)                    ! UNA sola llamada -- esto es lo que F00(x) hacia por dentro

  r =       (1.d0 - f00)             ! F0(x), con F00(x) ya sustituido por f00
  r = r + (-f00*x)                   ! F1(x)
  r = r + (-f00*x**2/2.d0)           ! F2(x)
  r = r + (-f00*x**3/6.d0)           ! F3(x)
  r = r + (-f00*x**4/24.d0)          ! F4(x)
  r = r + (-f00*x**5/120.d0)         ! F5(x)
  r = r + (-f00*x**6/720.d0)         ! F6(x)
  ```

Bit a bit idéntico al original: cada término es exactamente la misma operación (`f00` multiplicado por el mismo `x^i/i!`), en el mismo orden de suma — solo que `f00` se calcula una vez en vez de siete (o tres, para `FN2`). `FN2` recibe el mismo tratamiento en 2 pasos, pero con solo 3 términos (`F0`+`F1`+`F2`) en vez de 7; `DFN1`/`DFN2` igual, con las fórmulas de `DF0`...`DF6` (código muerto, pero se aplica igual por consistencia).

**b) Cachear las evaluaciones repetidas de `FN2` en `Ex0`/`Ey0`/`Ez0`**: este cambio SÍ es un solo paso -- ni siquiera hace falta tocar `FN2` por dentro, solo evitar llamarla 3 veces con el mismo argumento:

```fortran
fn2_rh1 = FN2(btheta*rh1)
fn2_rh2 = FN2(btheta*rh2)
fn2_r0  = FN2(btheta*r0)

Ex0 = q*fn2_rh1*(...)/rh1**3 + q*fn2_rh2*(...)/rh2**3 - q0*fn2_r0*(...)/r0**3
Ey0 = q*fn2_rh1*(...)/rh1**3 + q*fn2_rh2*(...)/rh2**3 - q0*fn2_r0*(...)/r0**3
Ez0 = q*fn2_rh1*(...)/rh1**3 + q*fn2_rh2*(...)/rh2**3 - q0*fn2_r0*(...)/r0**3
```

`FN2(btheta*rh1)` da siempre el mismo resultado para el mismo argumento (determinista) — guardarlo y reutilizarlo no cambia ni un bit del resultado, es evitar repetir un cálculo idéntico.

## 4. Dónde se va a cambiar el código, y por qué

Todo dentro de `He_dihydrogen.f` (`v2-cuda-integracion/hibrido_instrumentado/`, primero en una copia aislada):

| Sitio | Líneas (aprox., estado actual) | Cambio | Motivo |
|---|---|---|---|
| `FN1(XDUMM)` | 135-145 | **2 pasos** -- paso 1: desplegar las 7 llamadas `F0(XDUMM)`...`F6(XDUMM)` en sus fórmulas, dentro del cuerpo de `FN1` (sección 3a). paso 2: sacar factor común -- sustituir las 7 apariciones de `F00(XDUMM)` por una variable local `f00=myexp(-XDUMM)` calculada una vez | Es la función que produce `eterm2` — 7→1 llamadas a `myexp` |
| `FN2(XDUMM)` | 159-165 | **2 pasos**, mismo procedimiento que `FN1` pero con solo 3 términos (`F0`+`F1`+`F2`) | Produce cada evaluación de `Ex0`/`Ey0`/`Ez0` — 3→1 llamadas a `myexp` por evaluación |
| `DFN1(XDUMM)` | 147-157 | **2 pasos**, mismo procedimiento con las fórmulas de `DF0`...`DF6` (`DF0(x)=F00(x)` también, así que comparte el mismo `f00`) | Código muerto (`GTEST` rama), sin impacto en velocidad real, pero se deja igual de correcto que `FN1` |
| `DFN2(XDUMM)` | 167-173 | **2 pasos**, igual que `DFN1` pero con `DF0`+`DF1`+`DF2` | Código muerto, igual motivo que `DFN1` |
| `He_dihydrogen`, bloque de inducción (`Ex0`/`Ey0`/`Ez0`) | ~495-505 | **1 paso** (no hace falta desplegar nada, `FN2` se llama desde fuera): calcular `fn2_rh1`/`fn2_rh2`/`fn2_r0` una vez cada uno, antes de `Ex0`/`Ey0`/`Ez0`, y sustituir las 9 llamadas a `FN2` por esas 3 variables | Elimina la repetición entre componentes Ex/Ey/Ez |
| `He_dihydrogen`, rama `IF(GTEST)` (`dExdx`...`dEzdz`) | ~516-631 | **1 paso**: reutilizar las mismas `fn2_rh1`/`fn2_rh2`/`fn2_r0` ya calculadas arriba, en vez de volver a llamar a `FN2` | Código muerto ahora mismo, pero si `GTEST` se activara algún día, ya estaría corregido igual que la parte viva |
| `F00`, `F0`...`F6`, `DF0`...`DF6` | 41-133 | **No se tocan** | Confirmado con `grep` que no las llama nadie más que `FN1`/`DFN1`/`FN2`/`DFN2` — se dejan intactas como referencia/documentación de la fórmula original, mismo criterio que `wavefhe4`/`derwavefhe4` (sin usar, sin tocar) tras la fusión de `mypow` |
| `myexp` (`glibc_exp_mod.cuf`) | — | **No se toca** | El objetivo nunca fue cambiar `myexp`, sino cuántas veces se llama |

## 5. Por qué es seguro bit a bit

Los dos cambios son casos de **cachear un valor ya determinista**, no de reordenar sumas ni cambiar ninguna fórmula:

- (a) `f00` se usa exactamente en las mismas operaciones (`f00*x^i/i!`) que antes hacía cada `Fi(x)` llamando a `F00(x)` por separado — mismos bits de entrada, misma operación, mismos bits de salida.
- (b) `FN2(btheta*rh1)` calculado una vez y usado en `Ex0`, `Ey0` y `Ez0` da el mismo resultado que llamarlo 3 veces (misma entrada, misma función, determinista) — no hay ninguna suma que reordenar, solo una llamada que se evita repetir.

## 6. Plan de verificación (mismo patrón que `mypow`)

1. Copia aislada de `hibrido_instrumentado` (`gpu-myexp-optimizado/` o similar).
2. Prueba unitaria aislada de `He_dihydrogen` (programa standalone, como se hizo en `optimización-mypow/`): comparar la versión vieja y la nueva con las mismas posiciones sintéticas, `GTEST=.false.` y `GTEST=.true.`, verificar `ENERGY1`/`ENERGY2`/`ENERGY3`/`V(:)` bit a bit idénticos.
3. Pipeline completo, varias escalas de walkers (500/1000/2000/3000), misma semilla — verificar energía bit a bit idéntica y medir el tiempo.
4. **Registros/ocupación por hilo, antes y después**: las variables auxiliares nuevas (`f00`, `fn2_rh1`, `fn2_rh2`, `fn2_r0`) tienen vida corta y probablemente no aumenten la presión de registros (sustituyen temporales que el compilador ya materializaba dentro de cada llamada repetida a `FN2`/`F00`), pero no se da por sentado -- se compara `registers_per_thread`/ocupación con `ncu` (o `nvfortran -Mcuda=ptxinfo`) antes y después del cambio, mismo criterio de "medir, no asumir" que ya evitó suposiciones incorrectas con los registros/warps en fases anteriores del proyecto (`tiempo-ncu-resultado.md`).
5. Si todo pasa: llevar a producción (`hibrido_instrumentado/`), recompilar, verificación final.

## 7. Verificación e implementación: (a) sola, (b) sola

Copia aislada `gpu-myexp-optimizado/` (luego separada en `gpu-myexp-solo-a-v2/` y `gpu-myexp-solo-b/` para aislar cada cambio). Prueba unitaria standalone de `He_dihydrogen` (20 átomos sintéticos, `GTEST=.false.` y `.true.`): **bit a bit idéntica** en ambos casos, en las dos variantes. Pipeline completo, 4 escalas de walkers, semilla 11: energía **bit a bit idéntica** a producción en todos los casos probados.

### 7.1. Primer intento (a)+(b) juntos: resultado mixto, con un aviso de presión de registros

Al medir el pipeline completo con (a)+(b) juntos se encontró algo inesperado: mejora clara a 500w (-9,2%) y 1000w (-1,9%), pero **empeoramiento** a 3000w (~+7-8% en varias corridas). `ncu` mostró que `k_vpot_t` había subido de 223 a 255 registros/hilo.

Diagnóstico en dos partes:
- Se encontró que reutilizar `fn2_rh1`/`fn2_rh2`/`fn2_r0` (cambio b) **también dentro** de la rama `IF(GTEST)` (código muerto, pero el compilador no puede demostrarlo -- `GTEST` era entonces un argumento normal, no una constante) extendía el rango de vida de esas 3 variables a todo el bloque, incluida la parte muerta -- eso costaba 24 registros de los 32 de más. Solución: dejar que la rama `GTEST` siguiera llamando a `FN2` por su cuenta, sin reutilizar las variables cacheadas ahí (fila de la tabla de la sección 4, "1 paso" en la rama `GTEST`).
- Con eso corregido, `k_vpot_t` bajó a 231 registros -- pero **seguía habiendo una regresión real (~+4,7%) a 3000w**, aislada específicamente al cambio (a) (comprobado con `gpu-myexp-solo-a`/`gpu-myexp-solo-b` por separado, con la GPU ya fría y control de deriva térmica mediante corridas alternadas -- ver más abajo). Aviso aparte: la primera ronda de aislamiento tenía un fallo metodológico -- `gpu-myexp-solo-a` se había creado ANTES de que se aplicara la corrección `exp`→`myexp` del usuario en `wavefhe4`/`wavef_derwavefhe4`/`k_fase_g` (ver sección 8), así que no era una comparación limpia. Se rehizo (`gpu-myexp-solo-a-v2`) a partir de la producción ya corregida.

### 7.2. Resultado final limpio, aislado, con deriva térmica controlada

6 corridas a 3000w, semilla 11, orden alternado (`REF`/`solo-a`/`solo-b` × 2), GPU estabilizada (verificado con `nvidia-smi` antes de cada ronda):

| Variante | Media 3000w | vs REF |
|---|---|---|
| `REF` (sin cambios) | 97,92s | — |
| `solo-a-v2` (solo cambio a) | 102,53s | **+4,71%** (regresión real, fuera del ruido 0,5%-2,7%) |
| `solo-b` (solo cambio b) | 99,67s | +1,79% (dentro del ruido) |

Y con las 4 escalas completas por separado:

| Escala | REF | (b) sola |
|---|---|---|
| 500w | 31,93s | 29,55s (**-7,4%**) |
| 1000w | 42,58s | 42,42s (-0,4%) |
| 2000w | 67,10s | 66,42s (-1,0%) |
| 3000w | 94,26s / 102,62s / 93,22s (media 96,70s) | 100,79s / 99,91s / 99,43s (media 100,04s, **+3,45%**) |

**Conclusión de esta fase**: (b) es neutro-a-positivo en casi todas las escalas, con una posible penalización pequeña a 3000w (en el borde del ruido). (a) tiene un coste real y consistente, sin ningún beneficio medible -- explicación más probable: `nvfortran` ya hacía la misma eliminación de subexpresión común (`F00(x)` repetido) por su cuenta a nivel de compilador, así que la reescritura manual no ahorró trabajo real, solo cambió la forma del código de una manera que le costó peor al asignador de registros en un kernel ya muy exigente en registros (223 de partida, con *spilling* a memoria local ya confirmado con `ncu`: ~216 MB de carga/escritura local antes de tocar nada).

## 8. La corrección `exp`→`myexp` del usuario (contexto, no parte de esta rama de trabajo)

Durante esta investigación se descubrió (al buscar dónde faltaba `myexp` en `duhe4x`/`uhe4x`/`mycos`/`mysin`/`myacos` -- resultó que no hacía falta ahí, ver más abajo) que **`wavef_derwavefhe4`** (`der_wavefhe4_mod.cuf`, la función que SÍ corre en producción) calculaba `wfhe4=exp(ujas)` con el `exp()` nativo de `nvfortran`, no con `myexp(ujas)` -- y ese `wfhe4` alimenta `wf=wfhe4*wfhe3*wfm*wfx` en `derananum`, que a su vez decide la aceptación de cada movimiento de walker en `k_fase_c` (`wftest=(wf/wfold)**2; activo(i)=(wftest.ge.ratio)`). Lo mismo en `k_fase_g` (`dmc2_pipeline.cuf`): `gb=exp(...)` controla `nsons(i)`, la repoblación DMC. Dos decisiones centrales del algoritmo, calculadas con precisión distinta a `gfortran`.

El usuario corrigió esto directamente (`exp`→`myexp` en `der_wavefhe4_mod.cuf:57/152` y `dmc2_pipeline.cuf:524`), heredado de antes de que existiera `myexp` -- no introducido en esta sesión. Todas las mediciones de las secciones 7 en adelante se hicieron **con esta corrección ya aplicada de forma consistente** en la referencia y en todas las copias comparadas (verificado con `grep`/`md5sum` antes de cada comparación).

Por completitud: se confirmó que `duhe4x`/`uhe4x` (`d_uhex4_mod.cuf`) y `mycos`/`mysin`/`myacos` **no necesitan** `myexp` -- las primeras trabajan en espacio logarítmico (nunca exponencian, eso pasa una vez en `wavefx`, fuera del bucle); las segundas son funciones trigonométricas, algoritmo completamente independiente de `exp()`.

## 9. `GTEST` fijo en compilación

### 9.1. La idea

`GTEST` es un argumento de `He_dihydrogen` en tiempo de ejecución, pero la única llamada real (`potenbh`, `mpotenbh_mod.cuf`) siempre pasa `.false.` -- confirmado con `grep` que `gtest=.true.` no aparece en ningún sitio del árbol vivo. El compilador **no puede demostrar** esto porque `GTEST` es un argumento normal, no una constante -- así que reserva registros para las 3 ramas `IF(GTEST)` (el cálculo de fuerzas: `dvdR`, `dvdtheta`, `dExdx`...`dEzdz`, `dbbbdx`, etc.) aunque nunca se ejecuten.

**Diferencia clave con `nhe3` (sección 10)**: `GTEST` nunca viene de `in.mcv` ni de ningún dato de usuario -- es una decisión de diseño interna, fija en un único sitio. Fijarla no le quita ninguna capacidad real a la simulación.

### 9.2. El cambio

En `He_dihydrogen.f`: `GTEST` deja de ser argumento de la subrutina y pasa a ser `LOGICAL, PARAMETER :: GTEST = .false.` interno. Con `GTEST` conocido en compilación, `nvfortran` demuestra que las 3 ramas `IF(GTEST)` son inalcanzables y las elimina enteras -- ya no hace falta reservar registros para nada de lo que solo alimenta esas ramas. En `mpotenbh_mod.cuf`: se quita la variable local `gtest` y el argumento en la llamada a `He_dihydrogen`.

Si algún día hiciera falta el cálculo de fuerzas, basta con cambiar el `PARAMETER` a `.true.` y recompilar -- no hace falta mantener una segunda copia de la rutina (a diferencia de lo que se planteó al principio).

### 9.3. Por qué esto hace que (a) (y en menor medida (b)) dejen de perjudicar

El coste de (a) a 3000w (sección 7) era, con toda probabilidad, un problema de presión de registros en un kernel (`k_vpot_t`) ya al límite (223 registros de partida). `GTEST` fijo ataca la causa de raíz -- libera muchos más registros que los que costaba (a), así que dentro de un kernel con margen de sobra, la reestructuración de (a) deja de desequilibrar nada.

### 9.4. Registros medidos (`ncu`, `k_vpot_t`, 1500 walkers)

| Variante | Registros/hilo | Bloques residentes (límite por registros) |
|---|---|---|
| Producción (sin ninguno de estos cambios) | 223 | 8 |
| `GTEST` fijo solo | **106** | **16** |
| `GTEST` fijo + (a) | 106 (igual) | 16 |
| `GTEST` fijo + (a) + (b) | **94** | **20** |

`k_derananum_t` no cambia en ningún caso (144 registros, 12 bloques) -- `GTEST` solo afecta a `He_dihydrogen`, que se ejecuta dentro de `vpot`/`k_vpot_t`.

Notar que `GTEST` fijo + (a) da **exactamente los mismos registros** que `GTEST` fijo solo (106) -- confirma la sospecha de la sección 7: (a) no cuesta nada por sí sola, el coste que se veía antes era enteramente por competir con la rama `GTEST` viva.

### 9.5. Tiempos medidos (bit a bit idéntico a producción en las 4 escalas, en todas las variantes)

| Escala | REF | `GTEST` fijo solo | `GTEST` fijo + (a) |
|---|---|---|---|
| 500w | 32,19s / 31,85s | 30,03s (**-6,7%**) | 29,23s (**-8,2%**) |
| 1000w | 42,84s / 42,39s | 42,43s (-1,0%) | 41,92s (-1,1%) |
| 2000w | 66,11s / 66,76s | 66,60s (+0,7%, ruido) | 66,65s (-0,2%) |
| 3000w | 93,53s / 93,85s | 92,65s (**-0,9%**) | 92,51s (**-1,4%**) |

**`GTEST` fijo es, de largo, la mejora más limpia de toda esta investigación**: ninguna escala empeora, y se libera más de la mitad de los registros de `k_vpot_t` con un cambio de 2 líneas (quitar un argumento, fijar una constante).

### 9.6. `GTEST` fijo + (a) + (b): anomalía confirmada, sin explicar -- NO se usa

Con (b) añadido encima de `GTEST` fijo + (a), los registros de `He_dihydrogen` bajan más todavía (`mhe_dihydrogen_he_dihydrogen_`: 106→82; `k_vpot_t`: 106→94, límite de ocupación 16→20 bloques) -- una reducción real, confirmada con `cuobjdump --dump-resource-usage` sobre cada función de la cadena de llamadas (`He_dihydrogen`→`potenbh`→`vpot`→`k_vpot_t`, todas registran menos registros).

A pesar de eso, el tiempo medido es **mucho peor**, no mejor:

| Escala | REF | `GTEST` fijo + (a) + (b) |
|---|---|---|
| 500w | 32,70s | 40,03s (+22%) |
| 1000w | 42,39s | 70,31s (+66%) |
| 2000w | 67,37s | 105,30s (+56%) |
| 3000w | 94,29s | 135,49s (+44%) |

Repetido con control de deriva térmica (GPU verificada fría con `nvidia-smi` antes de empezar, 2 rondas alternadas REF/combo a 3000w): **REF media 99,31s, combo media 138,66s -- +39,6%, consistente, no es ruido ni deriva térmica**. Energía bit a bit idéntica en todas las corridas (`-678.0618871962`) -- no es un problema de corrección, solo de rendimiento.

**Investigación de la causa (sin resolver)**:
- Se comparó el ensamblador (`cuobjdump --dump-sass`) de `k_vpot_t` entre `GTEST fijo+(a)` y `GTEST fijo+(a)+(b)`: **idéntico, byte a byte** (mismo `md5sum`, 152 instrucciones) -- porque `He_dihydrogen` no está insertada dentro de `k_vpot_t`, es una función separada, llamada de verdad (`CALL`), así que el cambio (b) no toca el ensamblador de `k_vpot_t` en absoluto.
- Comparando `He_dihydrogen` directamente (`cuobjdump --dump-resource-usage`), los registros SÍ bajan de verdad (106→82) -- contradice la idea de que (b) genere más trabajo o más instrucciones.
- Con registros más bajos en toda la cadena, ocupación más alta, y el mismo número de bloques lanzados (el tamaño del grid solo depende del número de walkers, no de los registros) -- no hay una explicación mecánica clara, con las herramientas usadas, de por qué esto sale tan lento.
- Se descartó que fuera deriva térmica (control explícito con `nvidia-smi` + 2 rondas alternadas, mismo resultado).

**Conclusión**: `GTEST` fijo + (a) + (b) **no se lleva a producción** -- se documenta como un resultado negativo real y verificado (no ruido, no un bug de corrección), pero con la causa mecánica sin identificar. La combinación que sí se usa es `GTEST` fijo + (a), sin (b) (sección 9.5), que no muestra este problema en ninguna escala probada.

## 10. `nhe3` fijo en compilación (decisión de alcance, EN CURSO)

### 10.1. Qué se va a hacer

Igual que `GTEST`, pero con `nhe3`: fijarla como `PARAMETER=0` en vez de argumento/variable en tiempo de ejecución, para que el compilador pueda demostrar y eliminar los caminos que dependen de ella (`duhe3x`/`uhe3x` en `der_wavefx_mod.cuf`; `wavefm`/`wavefhe3` en `wavef_mod.cuf`; `derwavefm`/`derwavefhe3` en `derananum_mod.cuf` -- todos con bucles `do ...=1,nhe3`, 0 iteraciones hoy).

### 10.2. Por qué esto es DISTINTO de `GTEST` -- una decisión de alcance, no solo de rendimiento

`GTEST` nunca fue un dato de entrada -- era una decisión de diseño interna, invisible para quien usa el programa. `nhe3`, en cambio, **se lee directamente de `in.mcv`** (`mentradatos.f90:40`, `read(5,*) nhe3`) -- es un parámetro real de la simulación. Cualquiera que ponga `nhe3>0` en su `in.mcv` (para simular una gota mixta He3+He4) espera que el programa lo soporte -- y hoy lo soporta, aunque en esta configuración concreta valga 0.

**Este TFG está diseñado expresamente para esta simulación** (gota pura de He4) -- no para el caso general con He3. Fijar `nhe3=0` en compilación es coherente con ese alcance, pero tiene una consecuencia real: **este binario dejaría de poder simular nunca más sistemas con He3** sin volver a tocar el código.

Además, importante: **no todos los métodos de cálculo originales de la rama `pasodmc` están portados a GPU para el caso `nhe3>0`** -- partes como `derwavefhe3` (derivada numérica por diferencias finitas) y el determinante de Slater completo (`slaterdet`, recortado aquí a la rama trivial `npart<=1`, documentado en `wavef_mod.cuf`) nunca se completaron para el caso general, porque nunca hizo falta con `nhe3=0` fijo en todas las pruebas de esta sesión. Si algún día se necesitara `nhe3>0` de verdad, habría que:
1. Revertir `nhe3` a variable en tiempo de ejecución (deshacer este cambio -- ver 10.3).
2. Terminar de portar `slaterdet` (la rama general, con determinante NxN de verdad) y verificar `derwavefhe3` a fondo con `nhe3>0` real -- trabajo no hecho todavía, aparcado desde antes de esta sesión.

### 10.3. Cómo deshacer esto en el futuro (las 2 líneas exactas)

**Importante -- corrección sobre lo dicho antes**: `mentradatos.f90` **nunca se tocó** y sigue leyendo `nhe3` de `in.mcv` con `read(5,*) nhe3` tal cual siempre (lo sigue necesitando `mparametros::nhe3` para el lado CPU). El cambio real está en 2 sitios, en `hibrido_instrumentado/`:

**1) `mcuda_globals.cuf`** -- ahora mismo:
```fortran
 integer(kind=i4), device :: natom, ngatom, nhe4
 ...
 integer(kind=i4), parameter :: nhe3 = 0
```
Revertir a:
```fortran
 integer(kind=i4), device :: natom, ngatom, nhe4, nhe3
```
(quitar la línea `integer(kind=i4), parameter :: nhe3 = 0` y devolver `nhe3` a la lista de variables `device` de la línea de arriba, tal como estaba).

**2) `msync_gpu.cuf`** -- añadir de nuevo la línea `nhe3     = nhe3_real` (justo después de `nhe4     = nhe4_real`) en las **2** subrutinas donde se quitó:
```fortran
   nhe4     = nhe4_real
   nhe3     = nhe3_real     ! <- volver a añadir esta linea
   impureza = impureza_real
```
-- una vez dentro de `sincroniza_globales_gpu` (usada por `opcion=5`/`6`) y otra vez dentro de `sincroniza_constantes_gpu` (usada por `opcion=7`, la que usa producción).

No hace falta tocar nada más -- ni `mentradatos.f90` ni el resto del código (`duhe3x`/`uhe3x`, `wavefm`/`wavefhe3`, `derwavefm`/`derwavefhe3`) cambiaron nunca, ya estaban preparados para `nhe3` variable y lo siguen estando.

### 10.4. Implementación

`mcuda_globals.cuf`: `nhe3` deja de ser `integer(kind=i4), device` y pasa a `integer(kind=i4), parameter :: nhe3 = 0`. `msync_gpu.cuf`: se quitan las 2 líneas `nhe3 = nhe3_real` (en `sincroniza_globales_gpu` y `sincroniza_constantes_gpu` -- ya no se puede asignar a una constante). `mentradatos.f90` **no se toca** -- sigue leyendo `nhe3` de `in.mcv` sin cambios, porque `mparametros::nhe3` lo sigue necesitando el lado CPU (opciones 1-4). Ningún otro fichero necesitó cambios.

Aviso del compilador tras el cambio (esperado, confirma que `nhe3=0` ya es visible en compilación): `NVFORTRAN-W-0435-Array declared with zero size` en `derananum_mod.cuf` (los arrays `d1wf(nhe3)`/`d2wf(nhe3)` de `derwavefhe3`, ahora de tamaño 0 de verdad).

### 10.5. Registros medidos (`ncu`, 1500 walkers)

A diferencia de `GTEST` (que solo afecta a la cadena `He_dihydrogen`→`potenbh`→`vpot`→`k_vpot_t`), `nhe3` afecta a la OTRA cadena (`derwavefhe3`/`wavefm`/`wavefhe3`/`duhe3x`/`uhe3x`, dentro de `derananum`→`k_derananum_t`):

| Función | Antes (`GTEST` fijo + (a) solo) | Con `nhe3` fijo también |
|---|---|---|
| `k_derananum_t` | 144 registros, límite 12 bloques | **126 registros, límite 16 bloques** |
| `k_vpot_t` | 106 registros, límite 16 bloques | 106 registros, límite 16 bloques (sin cambio -- `nhe3` no toca esta cadena) |

### 10.6. Tiempos medidos (bit a bit idéntico a producción en las 4 escalas)

| Escala | REF | `GTEST` fijo + (a) + `nhe3` fijo |
|---|---|---|
| 500w | 31,48s | 27,11s (**-13,9%**) |
| 1000w | 43,28s | 38,03s (**-12,1%**) |
| 2000w | 68,80s | 61,46s (**-10,7%**) |
| 3000w | 99,55s | 86,79s (**-12,8%**) |

Mejora clara y consistente en las 4 escalas -- mejor incluso que `GTEST` fijo + (a) solo (sección 9.5), sin ninguna de las anomalías vistas con (b). Combinación final recomendada: **`GTEST` fijo + (a) + `nhe3` fijo, sin (b)**.

### 10.7. Estado

**Hecho, verificado bit a bit, resultado positivo en las 4 escalas** (ver 10.4-10.6). Pendiente: llevar a producción (`hibrido_instrumentado/`).

## 11. Combinación final recomendada

**`GTEST` fijo + (a) + `nhe3` fijo** (`gpu-gtest-fijo-mas-a-mas-nhe3fijo/`), sin (b):

| Escala | REF | Combinación final | Diferencia |
|---|---|---|---|
| 500w | 31,48s | 27,11s | **-13,9%** |
| 1000w | 43,28s | 38,03s | **-12,1%** |
| 2000w | 68,80s | 61,46s | **-10,7%** |
| 3000w | 99,55s | 86,79s | **-12,8%** |

Bit a bit idéntico a producción en las 4 escalas. Sin ninguna de las anomalías de (b) (sección 9.6). Registros: `k_derananum_t` 144→126, `k_vpot_t` 223→106 (heredado de `GTEST` fijo). Recuerda: `nhe3` fijo es una decisión de **alcance** (sección 10.2), no solo de rendimiento -- este binario deja de poder simular sistemas con He3.

## 12. Punto 2 aplicado a `myexp` (eliminar variables de un solo uso): resultado nulo

Revisión externa sugirió que reducir variables intermedias en `myexp` liberaría registros. Se repasaron las 13 variables locales de `myexp` una por una: la mayoría se reutilizan de verdad (`idx` dos veces; `ki`/`sbits`/`tmp` los necesita también `exp_specialcase`; `kd`/`r`/`r2` son el propio esquema de Horner de la sección 3a) -- solo **2 eran de un solo uso real**: `z` (usada una vez para `kd`) y `topbits` (usada una vez para `sbits`). Se eliminaron, calculando su valor directamente en el punto de uso (mismo orden de operaciones, bit a bit idéntico -- verificado).

**Resultado: nulo.** `cuobjdump --dump-resource-usage` da exactamente los mismos registros (`k_vpot_t` 106, `k_derananum_t` 126) y el mismo `STACK`, con o sin el cambio. `cuobjdump --dump-sass` confirma que el ensamblador de `k_vpot_t` es **idéntico byte a byte** en las dos versiones. `nvfortran` ya eliminaba `z`/`topbits` por su cuenta -- es el caso más simple posible de optimización automática (código lineal, sin ramas, sin alias), exactamente el tipo de cosa que cualquier compilador con un asignador de registros razonable resuelve solo. No se llegó a medir tiempo de pared (no tenía sentido con el binario compilado siendo el mismo).

Mismo patrón que el cambio (a) de la sección 7: cuando la redundancia es local y simple, el compilador de `nvfortran` normalmente ya la resuelve -- el margen real está en la redundancia que el compilador NO puede ver (entre funciones separadas, como `He_dihydrogen`; o en código muerto que no puede demostrar inalcanzable en tiempo de compilación, como `GTEST`/`nhe3`).

## Ficheros

- `gpu-myexp-optimizado/`, `gpu-myexp-solo-a/`, `gpu-myexp-solo-a-v2/`, `gpu-myexp-solo-b/`: copias aisladas de las distintas variantes de (a)/(b), en sus distintas iteraciones (`solo-a` sin `-v2` quedó obsoleta por el fallo metodológico de la sección 7.1, se conserva por trazabilidad).
- `gpu-gtest-fijo/`, `gpu-gtest-fijo-mas-a/`, `gpu-gtest-fijo-mas-a-mas-b/`, `gpu-gtest-fijo-mas-a-mas-nhe3fijo/`: copias aisladas de `GTEST` fijo, solo y combinado con (a), (a)+(b), y (a)+`nhe3` fijo (esta última, la combinación final recomendada).
- `gpu-gtest-fijo-mas-a-mas-nhe3fijo-mas-myexpvars/`: variante exploratoria adicional (combinación final + ajuste de las variables internas de `myexp`, en `glibc_exp_mod.cuf`), sin sección propia en este documento.
- `compilar_myexp_optimizado.sh`, `compilar_gtest_fijo.sh`, `compilar_nhe3_fijo.sh`: scripts de compilación.
- `comparar_myexp_varios_walkers.sh`, `comparar_solo_b_varios_walkers.sh`, `comparar_gtest_fijo_varios_walkers.sh`, `comparar_gtest_fijo_mas_a_varios_walkers.sh`, `comparar_combo_final_varios_walkers.sh`, `comparar_nhe3_fijo_varios_walkers.sh`: scripts de las comparaciones de 4 escalas.
- `resultados_myexp/`, `resultados_solo_b/`, `resultados_gtest_fijo/`, `resultados_gtest_fijo_mas_a/`, `resultados_combo_final/`, `resultados_nhe3_fijo/`: logs completos + `tiempos_opcion7.dat` de todas las corridas.

**Nota de limpieza**: las 9 copias `gpu-*/` se recortaron de copias completas (~38-41M
cada una, 359M en total) a solo sus ficheros genuinamente editados + `in.mcv` +
`tiempos_opcion7.dat` (1,8M en total). Todas mantienen `He_dihydrogen.f` (el
cambio central de (a)/(b)/GTEST); las variantes `nhe3fijo` y `nhe3fijo-mas-myexpvars`
además mantienen `mcuda_globals.cuf` y `msync_gpu.cuf` (el fijado de `nhe3`); la
variante `myexpvars` además mantiene `glibc_exp_mod.cuf` (verificado con `diff`
que es el único fichero que distingue esa copia de `nhe3fijo`: `He_dihydrogen.f`
es idéntico entre ambas). No recompilables tal cual, igual que el resto de
carpetas recortadas de este árbol.
