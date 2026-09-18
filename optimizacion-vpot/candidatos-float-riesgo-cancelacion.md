# Candidatos a `float` tras `wavef_derwavefhe4`: riesgo de cancelación medido

## 1. Objetivo

Con la Opción 3 de `wavef_derwavefhe4_float` cerrada (`float-wavef-derwavefhe4-validacion.md` §4c), tocaba buscar el siguiente método a convertir. La tabla de coste real por función está en `funciones-matematicas/optimización-mypow/optimizacion-mypow.md` §1/§6 (perfilado `ncu --page source`, 1.500 walkers) -- de ahí salen los 3 candidatos grandes todavía en `double`: `vp_hehe`/`v_hehe` (~14%), `duhe4x`/`uhe4x` (~11%) y `he_dihydrogen` (~8,7%). La hipótesis inicial de esta línea (`wavefx`, por tener la misma forma algebraica que `wavef_derwavefhe4`) quedó descartada por la propia tabla: `wavefx`+`derwavefx` es solo ~1,3% del tiempo total.

`wavef_derwavefhe4` era una **suma pura** (`ujas` solo acumula términos negativos) -- el único riesgo era el rango/overflow de `float32`, resuelto acumulando en `double` (Opción 3). Los 3 candidatos nuevos no tienen por qué compartir esa forma: dos de ellos (potenciales físicos tipo Lennard-Jones/Tang-Toennies) tienen **resta entre un término repulsivo y uno atractivo**, la forma clásica que puede sufrir cancelación catastrófica en `float32` (~7 cifras decimales) si ambos términos son comparables en magnitud. Este documento mide, empíricamente, cuánta cancelación real hay en cada uno antes de elegir por dónde seguir -- mismo criterio de "medir antes de decidir" que el resto del árbol.

## 2. Metodología

Copia aislada (`/tmp/duhe4x-float-test/`, no persistida, reconstruida desde `hibrido_instrumentado/`), instrumentando cada candidato con contadores `device` (mismo patrón que `ujas` en `float-wavef-derwavefhe4-validacion.md` §4b/4c): rango de las magnitudes involucradas, y un **ratio de cancelación** por evaluación:

```
cancel_r = |resultado final| / suma(|términos individuales|)
```

`cancel_r` cerca de 1 = sin cancelación (los términos se refuerzan). `cancel_r` pequeño = cancelación: el resultado es mucho menor que los términos que lo componen, así que las cifras significativas de cada término se cancelan entre sí. Un `cancel_r < 1e-4` significa que se pierden más de 4 de las ~7 cifras que tiene `float32` -- calcular esos términos en `float` daría un resultado con pocas o ninguna cifra correcta.

Corrida real: 1000 walkers, 1 bloque de equilibrio, 100 bloques × 100 pasos (10.000 pasos DMC), mismo `conf.20.00.HH`/`etrial=-631,8` de siempre. Energía final verificada bit a bit idéntica a la referencia (`-615.5737694990`) en las 3 corridas -- la instrumentación no altera el resultado.

## 3. Resultado: `duhe4x`/`uhe4x` sin cancelación, los otros dos con riesgo real

### 3.1. `uhe4x` (`d_uhex4_mod.cuf`, valor del potencial) -- SIN cancelación

Expansión en polinomios de Legendre, `il=0..lxhe4` (4 términos): cada término interno tiene forma `ul = -A - B - C` (los 3 sumandos restan en la misma dirección, no hay resta entre cantidades opuestas) y la suma final `uhe4x = Σ ul(il)·pl(il)`. Usada en `wavefx` (`der_wavefx_mod.cuf:156`, acumulador `ujas`).

```
rij MINIMO/MAXIMO visto:            1,215 / 6,934
cancel_uhe4x MINIMO/MAXIMO:         1,00000000 / 1,00000000
n_total_evals:                      681.660 (medición 1) / 719.347 (medición previa)
cancel_uhe4x < 1e-4 / 1e-6 / 1e-7:  0 / 0 / 0
```

**Ratio de cancelación exactamente 1,0 en cientos de miles de evaluaciones, sin una sola excepción.** Confirma el análisis algebraico: la forma "todo resta en la misma dirección" nunca cancela -- tan seguro como `wavef_derwavefhe4`.

### 3.1b. `duhe4x` (`d_uhex4_mod.cuf`, gradiente/laplaciano) -- CANCELACIÓN SEVERA (corrección tras revisión)

**Aviso de proceso**: la medición inicial de esta línea solo cubrió `uhe4x` -- se etiquetó el candidato como "`duhe4x`/`uhe4x`" sin haber medido `duhe4x` (la subrutina que calcula el gradiente y el laplaciano, usada en `derwavefx`, `der_wavefx_mod.cuf:207` -- necesaria para el término de deriva y la energía cinética del DMC). Una pregunta directa del usuario detectó el hueco. `duhe4x` NO tiene la misma forma que `uhe4x`: sus términos internos `ulxp` y `ulxs` sí mezclan signos --

```fortran
ulxp = ( pxhe4(1,il)*pxhe4(2,il)*inv_rijp2   ! +A
 &      -pxhe4(3,il)*pxhe4(4,il)*rijp4       ! -B
 &      -pxhe4(5,il) ) * inv_rij             ! -C
ulxs = (-pxhe4(1,il)*pxhe4(2,il)*(...)*inv_rijp2  ! -A
 &      -pxhe4(3,il)*pxhe4(4,il)*(...)*rijp4      ! -B
 &      +pxhe4(5,il) ) * inv_rij2                 ! +C
```

Instrumentado igual que los demás: cancelación de `ulxp`/`ulxs` (antes de multiplicar por `inv_rij`/`inv_rij2`) y del acumulador final `d2ux` (suma de 3 contribuciones por cada `il`).

```
cancel_ulxp MINIMO/MAXIMO:  0,00000000 / 1,44
cancel_ulxs MINIMO/MAXIMO:  0,00000000 / 1,40
cancel_d2ux MINIMO/MAXIMO:  0,76 / 1,00
n_total_evals (llamadas a duhe4x):  724.436  (≈2.897.744 iteraciones il, lxhe4=3 → 4 por llamada)
cancel_ulxp < 1e-4: 1.539.438 (53,13%)   < 1e-7: 1.541.304 (53,19%)
cancel_ulxs < 1e-4: 1.455.113 (50,22%)   < 1e-7: 1.457.188 (50,29%)
cancel_d2ux < 1e-4: 0                     < 1e-7: 0
```

**Cancelación severa y extremadamente frecuente** -- no un caso raro: **más de la mitad de todas las iteraciones** pierden más de 4 cifras al calcular `ulxp`/`ulxs`, y el mínimo llega a cancelación total (`0,0` exacto -- los términos coinciden hasta el último bit de `double`). El acumulador final `d2ux` sí se mantiene seguro en su propia combinación (`cancel_d2ux` nunca baja de 0,76), **pero esto no protege el resultado**: si `ulxp`/`ulxs` ya se calculan con precisión residual nula en `float32` (la mitad de las veces), esa corrupción se arrastra a `d2ux` igual, aunque el paso de combinación final no añada cancelación adicional por su cuenta -- mismo problema de fondo que `V_and_Vp_hehe`/`he_dihydrogen` (la pérdida ocurre dentro de los términos, no se puede recuperar después), pero aquí mucho más frecuente (>50% de las veces, frente a ~0,3-1% en los otros dos).

### 3.2. `He_dihydrogen_dispersion` (`He_dihydrogen.f`, la que de verdad ejecuta `k_vpot_3warp_t`) -- CON cancelación

**Aviso de proceso**: la primera instrumentación se hizo sobre `He_dihydrogen` (la subrutina fusionada al principio del fichero, línea 261) -- dio `n_total_evals=0`, es decir, nunca se ejecuta con `opcion=7` (confirma `mapa-sfu-produccion.md` §4.2: esa ruta pasa por `potenbh`/`vpot`/`k_vpot_t`, que no se lanzan). La real, llamada desde `k_vpot_3warp_t` (`dmc2_pipeline.cuf` línea 533), es `He_dihydrogen_dispersion` -- la reinstrumentación se hizo ahí.

Cada átomo aporta `eterm1` (repulsivo, `a0*myexp(...)`, siempre positivo) y `-eterm2` (dispersión, siempre negativo) a un array `e2terms`, sumado al final con `treesum` (suma en árbol binario de orden fijo, para reproducibilidad CPU/GPU -- no es una suma compensada, no protege de la cancelación en sí).

```
eterm1 MINIMO/MAXIMO visto:  6,307E-11 / 2939,0
eterm2 MINIMO/MAXIMO visto:  0,0368 / 638,3
cancel_e2 MINIMO/MAXIMO:     2,945E-10 / 0,582
n_total_evals:                390.222
cancel_e2 < 1e-4:             1268  (0,325%)
cancel_e2 < 1e-6:                11  (0,0028%)
cancel_e2 < 1e-7:                 1  (0,00026%)
```

**Cancelación real y no despreciable**: 0,325% de las evaluaciones pierden más de 4 cifras, y una evaluación entera perdió prácticamente toda la precisión de `float32` (`cancel_e2=2,9×10⁻¹⁰`).

### 3.2b. De dónde viene exactamente la cancelación de `He_dihydrogen_dispersion`: `atheta`

Pregunta del usuario, razonada mirando el código antes de medir (el método correcto: primero hipótesis desde la fórmula, después comprobación con datos): `eterm1=a0*myexp(atheta-rnorm*btheta)` usa 3 cantidades construidas a partir de los coeficientes del modelo (`param_atoms_bh.h`) --

```
atheta = a1*cos2 + a2*cos4 + a3*cos6     (a1=-0,42497, a2=+3,95634, a3=+0,07852)
btheta = b0 + b1*cos2 + b2*cos4 + b3*cos6 (b0=+3,49361, b1=+0,13908, b2=+1,89258, b3=-0,01065)
c6theta= c60 + c61*sin2 + c62*sin4 + c63*sin6 (c60=+4091,46, resto pequeños frente a c60)
```

`btheta` y `c6theta` tienen un término "suelo" (`b0`, `c60`) positivo y mucho más grande que cualquier posible resta interna -- nunca pueden acercarse a cero, no hace falta medirlos, el álgebra ya lo garantiza. `atheta` es distinto: `a1` es negativo y bastante más pequeño en valor absoluto que `a2`, así que sí existe un valor real de `cos²θ` donde `atheta` pasa por cero exactamente -- resolviendo `a3·x²+a2·x+a1=0` (con `x=cos²θ`) da `x≈0,10719`.

**Medición** (misma corrida de referencia, 10.000 pasos):

```
cos2 (=cos²θ) rango visto: 8,6E-17 a 0,99999998   -- barre todo [0,1], sí pasa cerca de 0,107
cancel_atheta (|atheta|/suma|términos|) MINIMO: 1,97E-9   -- cancelación casi total en algún caso
n_evals: 1.092.459
cancel_atheta < 1e-4: 19.063 (1,75%)   -- MÁS frecuente que la cancelación de v/Vbp en V_and_Vp_hehe
cancel_atheta < 1e-7: 18
frac_atheta en (atheta-rnorm·btheta) MAXIMO: 53,6%
veces que atheta pesa >10% en esa resta: 752.302 de 1.092.459 (68,9%)
```

**Confirmado**: `atheta` cancela de verdad, con más frecuencia que cualquier otro caso medido en este documento (1,75% de las evaluaciones pierden >4 cifras, frente a 0,325% de `He_dihydrogen_dispersion` a nivel de `e2terms`/`treesum`, o 0,36-1,07% de `V_and_Vp_hehe`). Y no queda tapado por `rnorm*btheta` en el argumento de `myexp`: pesa más del 10% en un 68,9% de las evaluaciones, hasta un máximo del 53,6% del total. Esto añade una capa de riesgo más a `He_dihydrogen_dispersion`, previa a la que ya se había medido en el propio `e2terms`/`treesum` (§3.2) -- dos mecanismos de cancelación distintos y acumulativos en el mismo método.

### 3.2c. `He_dihydrogen_hehe`: la propia suma `ENERGY1=Σv_tmp` también cancela

Otra pregunta del usuario sobre una parte de `He_dihydrogen.f` no mirada todavía: `He_dihydrogen_hehe` sí es la que llama a `V_and_Vp_hehe` (§3.3/§8) para cada uno de los `N·(N-1)/2` pares de átomos de He4 (`N=20` fijo en este proyecto → 190 pares), y acumula `ENERGY1=ENERGY1+v_tmp`. Pregunta: ¿esa suma en sí misma tiene un problema -- por ejemplo, si `ENERGY1` acabase siendo mucho más grande que cada `v_tmp`, perdiendo los términos pequeños en el redondeo?

**Medición**:

```
ENERGY1 (antes de escalar) rango visto: -2,07E-3 a 8,75E-3   -- MUY pequeño, no grande
cancel_E1 (|ENERGY1|/suma|v_tmp|) MINIMO: 3,94E-8             -- cancelación casi total
n_evals (llamadas a He_dihydrogen_hehe): 473.047
cancel_E1 < 1e-4: 5.898 (1,25%)
cancel_E1 < 1e-7: 2
```

Resultado, al revés de lo que se planteaba en la pregunta: `ENERGY1` no es grande, es diminuto -- lo cual solo puede pasar porque los 190 `v_tmp` de un mismo walker tienen signos mezclados (algunos pares en zona repulsiva, otros en zona atractiva del potencial) y se cancelan entre sí al sumarse. Es una **tercera capa** de cancelación en esta línea, distinta de la interna de `V_and_Vp_hehe` (§3.3/§8) y de la de `atheta`/`e2terms` (§3.2/§3.2b): aquí cancela la propia suma sobre los pares, no ningún término individual. Con `N=20` fijo (190 pares, no "muchos"), esta cancelación no se diluye por tener muchos términos -- cada caso de cancelación pesa proporcionalmente más que si hubiera miles de pares.

### 3.2d. La resta de coordenadas en `R2` (distancia He-He): segura en `double`, sería un riesgo distinto en `float`

Última pregunta de esta ronda: el cálculo de la distancia entre 2 átomos (`R2=(X1-X2)²+(Y1-Y2)²+(Z1-Z2)²`, dentro de `He_dihydrogen_hehe`) resta coordenadas -- ¿son coordenadas grandes? ¿se pierden cifras al restarlas?

```
|X(k)| MAXIMO visto: 6,92                          -- coordenadas modestas, no grandes
cancel_coord (|X1-X2|/max(|X1|,|X2|)) MINIMO: 2,90E-10
n_coord_evals: 21.144.105 (componentes x/y/z de cada par)
cancel_coord < 1e-4: 76.210 (0,36%)
```

A primera vista parece otro caso de cancelación -- pero **aquí no es peligroso, y es importante entender por qué no, para no generalizar mal la lección de los casos anteriores**: la cancelación catastrófica es un problema cuando se restan dos números que **ya llevaban error de redondeo acumulado** de un cálculo previo (como `expbase`/`F`/`sum1`, fruto de exponenciales y potencias). Las coordenadas `X(:)` son las posiciones de los walkers guardadas directamente en `double`, sin ningún cálculo intermedio que las haga imprecisas -- son exactas para efectos prácticos. Restar dos números exactos que resultan estar cerca da un resultado pequeño **igualmente exacto** (como `5,0 - 4,9999999 = 0,0000001`: el ratio de cancelación parece alarmante, pero el resultado es correcto porque los dos números de partida lo eran). No hay error previo que la resta pueda amplificar.

**Esto cambiaría si se convirtiera a `float`**: si `X(:)` se redondeara primero a `float32` (~7 cifras) y luego se restara, dos coordenadas casi alineadas en un eje sí perderían cifras de verdad, porque el redondeo a `float` sí introduce error antes de la resta. No es un riesgo hoy (en `double`), pero sería el primero a evaluar si alguna vez se planteara convertir esta parte concreta.

### 3.2e. `He_dihydrogen_induccion`: tabla de riesgo variable a variable (propuesta por el usuario) y medición

Antes de medir, se revisó a mano cada paso de `He_dihydrogen_induccion` para clasificar el riesgo por álgebra, igual que se hizo con `atheta`/`btheta`/`c6theta` en 3.2b:

| Variable | Riesgo por álgebra | Motivo |
|---|---|---|
| `cos2`/`cos4`/`cos6` | 🟢 Seguro | Potencias pares de `\|cos(θ)\|`, siempre ≥0 |
| `atheta` | 🟢 Seguro **aquí** (aunque cancele) | Se calcula (mismos coeficientes que en 3.2b, mismo cero real en `cos²θ≈0,107`) pero **nunca se usa** después en esta subrutina -- solo `btheta` alimenta `FN2`. Cálculo muerto, no afecta al resultado. |
| `btheta` | 🟢 Seguro | Igual que en 3.2b: `b0` es un término "suelo" positivo mucho mayor que cualquier resta interna posible |
| `rh1`, `rh2` (restas `X - r_dih`) | 🟡 A medir | Mismo patrón que la resta de coordenadas de 3.2d (`R2`) |
| `r0` | 🟢 Seguro | No es una resta -- es `\|X\|` directamente (distancia al origen), sin cancelación posible |
| `drh1dx` etc. (división) | 🟢 Seguro | Dividir no amplifica el error de una resta previa, solo lo transporta -- razonamiento correcto sin necesidad de medir |
| `inv_rh1_3` con `rh1→0` | 🟡 A medir | Riesgo distinto: sensibilidad física por proximidad (el campo diverge si el He se acerca mucho a un H), no cancelación de precisión en sí |
| `Ex0`, `Ey0`, `Ez0` | 🔴 Candidato fuerte | Suma de 3 términos con signos explícitos `+q`, `+q`, `-q0` (`q=0,7435`, `q0=0,487`, magnitudes parecidas) |
| `ENERGY3` (suma de cuadrados) | 🟢 Sin cancelación propia | Hereda el error de `Ex0`/`Ey0`/`Ez0`, pero su propia suma (de cuadrados, siempre ≥0) no cancela |

**Medición** (misma corrida de referencia, 10.000 pasos, energía verificada bit a bit idéntica a la referencia tras instrumentar):

```
rh1 MINIMO visto: 0,687      rh2 MINIMO visto: 0,705      r0 MINIMO visto: 1,215
  -- ninguno se acerca a 0 en esta corrida; no se observa el riesgo de inv_rh1_3
     disparandose, aunque esto no es una garantia para cualquier configuracion,
     solo lo que se vio en estos 10.000 pasos concretos

n_evals: 934.943

cancel_Ex0: MINIMO 0,444 / MAXIMO 0,748   -- NUNCA cancela, siempre entre 44-75%
cancel_Ey0: MINIMO 0,444 / MAXIMO 0,748   -- igual que Ex0, sin cancelacion real
cancel_Ez0: MINIMO 2,01E-8 / MAXIMO 0,628  -- SI cancela
cancel_Ez0 < 1e-4: 9.157 de 934.943 (0,98%)
cancel_Ez0 < 1e-7: 5
```

**El 🔴 de la tabla era correcto solo para una de las tres componentes.** `Ex0`/`Ey0` nunca bajan del 44% -- no hay cancelación real en el plano `x`/`y`, pese a tener la misma forma algebraica (3 términos, signos `+q,+q,-q0`) que `Ez0`. `Ez0` sí cancela de verdad, con una frecuencia (0,98%) parecida a la de `e2terms`/`treesum` en `He_dihydrogen_dispersion` (3.2, 0,325%) o algo mayor. La explicación física más plausible: el eje `z` de esta geometría es el eje especial (define `r0`/la orientación de la molécula de H₂ frente al He), mientras que `x`/`y` son direcciones perpendiculares donde los tres términos no llegan a oponerse de forma comparable. `ENERGY3=Ex0²+Ey0²+Ez0²` hereda ese error solo a través del término `Ez0²`.

Esto confirma, con un ejemplo más, la lección general de este documento: **la forma algebraica (signos mixtos) es una condición necesaria pero no suficiente para la cancelación real** -- hace falta medir con datos físicos reales para saber si esos signos llegan a producir magnitudes comparables en la práctica, no basta con mirar la fórmula.

### 3.3. `V_and_Vp_hehe` (`mVheheVphehe_mod.cuf`) -- CON cancelación (ya medido, referencia)

Resultado ya documentado en detalle en la conversación de esta línea (potencial He-He, `v = A_HeHe*expbase - F*sum1`, resta directa repulsión-atracción):

```
n_total_evals: 7.276.159
cancel_v   < 1e-4 / 1e-6 / 1e-7:  0,362% / 0,00694% / 0,00071%
cancel_vbp < 1e-4 / 1e-6 / 1e-7:  1,072% / 0,01193% / 0,00135%
```

### 3.4. Comparación

| Candidato | Coste (`optimizacion-mypow.md` §6) | Forma | `cancel < 1e-4` | `cancel < 1e-7` (pérdida total) |
|---|---|---|---|---|
| `uhe4x` (valor, en `wavefx`) | ~2,5% | suma `-A-B-C`, mismo signo | **0%** | **0** |
| `duhe4x` (gradiente/laplaciano, en `derwavefx`) | ~8,7% (`derwavefx`+`ccuerpo` etc.) | `ulxp`/`ulxs` con signos mixtos (`+A-B-C`, `-A-B+C`) | **50-53%** | **50-53%** |
| `he_dihydrogen` (dispersión) | ~8,7% | `treesum(repulsión, -dispersión)` | 0,325% | 1 caso |
| `vp_hehe`/`v_hehe` | ~14% (8,705%+5,343%) | resta directa repulsión-atracción | 0,36%-1,07% | 52-98 casos |

## 4. Interpretación

**No todos los candidatos de la tabla de coste tienen el mismo riesgo -- ni siquiera dentro del mismo par de funciones.** La forma algebraica importa tanto como el coste, y hay que medirla función por función, no por el nombre con el que aparecen juntas en la tabla de perfilado: `uhe4x` (el valor del potencial) es la única pieza de las 4 medidas sin ningún rastro de cancelación -- pero es solo ~2,5% del coste total, no el ~11% que parecía al agrupar "`duhe4x`/`uhe4x`" como si fueran una sola cosa. `duhe4x` (el gradiente/laplaciano, la mitad que de verdad pesa en el coste y que además alimenta el término de deriva y la energía cinética del DMC) tiene la cancelación **más severa y frecuente de los 4 candidatos medidos** -- más de la mitad de las evaluaciones, no un caso raro como en `he_dihydrogen` (~0,3%) o `vp_hehe`/`v_hehe` (~1%).

En los 3 casos con cancelación (`duhe4x`, `he_dihydrogen`, `vp_hehe`/`v_hehe`) aplica el mismo argumento: a diferencia del problema de rango de `ujas` (resuelto acumulando en `double`, Opción 3), aquí la pérdida de precisión ya ocurre **dentro** de los términos individuales calculados en `float` (~7 cifras cada uno) antes de restarse -- hacer la combinación final en `double` no puede recuperar cifras que nunca se calcularon.

**Mapa de riesgo completo de `He_dihydrogen.f` (3.2-3.2e), cerrado**: además de la cancelación ya conocida en `e2terms`/`treesum` (0,325%), se localizaron dos capas más -- `atheta` (1,75%, la más frecuente de todo el documento, aunque resulta ser código muerto en `He_dihydrogen_induccion`) y `Ez0` en `He_dihydrogen_induccion` (0,98%, pero **solo** esa componente -- `Ex0`/`Ey0`, con la misma forma algebraica de 3 términos con signos mixtos, nunca cancelan, entre 44-75% siempre). Y la propia suma `ENERGY1` de `He_dihydrogen_hehe` sobre los 190 pares He-He cancela también (hasta 3,94E-8), independientemente de la cancelación interna de `V_and_Vp_hehe` que ya usa. La lección que deja este mapeo completo: **la forma algebraica (signos mixtos en una suma) es necesaria pero no suficiente para que haya cancelación real** -- `Ex0`/`Ey0`/`Ez0` comparten fórmula exacta y solo una de las tres cancela en la práctica; solo medir con datos físicos reales lo distingue.

## 4b. Reparto de coste real de `duhe4x`: ¿protección de la cancelación viable con un híbrido?

Antes de aparcar `duhe4x` del todo, se midió si merece la pena una protección tipo "solo la cadena que cancela se queda en `double`, el resto pasa a `float`" (Opción 2 del diseño). La cadena que tiene que quedarse en `double` es más larga que solo `mypow_log`: incluye `rij`/`inv_rij`/`inv_rij2`, la llamada a `mypow_log`, y todo el bucle `il` hasta la resta (`rijp2`, `rijp4`, `inv_rijp2`, `ulx`, `ulxp`, `ulxs`) -- convertir cualquier pieza de esa cadena a `float` antes de la resta tira las cifras que la resta necesita. El resto (Legendre `calderpleg`, geometría vectorial `grz`/`gpz`/`lpz`, y la acumulación final en `d1ux`/`d2ux`/`d1zux`/`d2zux`) no participa en la cancelación medida en 4.1b.

**Medición**: `nvdisasm -g` sobre `duhe4x` en solitario (no inlineada, conserva anotación de línea de origen -- a diferencia de dentro de `k_derananum_resto_t`, donde el inlineado agresivo pierde la correlación por línea; `ncu --page source --csv` tampoco llegó a adjuntar métricas por línea en las pruebas hechas). Clasificadas las 552 instrucciones SASS de la función por línea de origen:

| Región | Instrucciones SASS | % |
|---|---|---|
| Cadena obligada a `double` (líneas 59-62, 92-103: `mypow_log`, `rijp2`/`rijp4`, `inv_rijp2`, construcción y resta de `ulxp`/`ulxs`) | 163 | 29,5% |
| Resto (líneas 63-91, 104-114: Legendre, geometría vectorial, acumulación final) | 305 | 55,3% |
| Sin atribuir (prólogo/epílogo, control de bucle) | 84 | 15,2% |

La cadena obligada a `double` concentra los únicos 2 `MUFU.RCP64H` de la función (confirma que ahí está el coste caro real). El "resto", pese a no tener SFU, tampoco es barato: 89 de sus 305 instrucciones son `LDL`/`STL`/`LDL.64`/`STL.64` (derrame a memoria local, probablemente de los arrays `pl`/`d1pl`/`d2pl` de Legendre) -- pasar esa parte a `float` ahorraría tanto por la aritmética como por reducir a la mitad ese derrame.

**Aviso**: esto es un recuento de instrucciones SASS, no de ciclos reales -- una `RCP64H` puede costar bastantes más ciclos que una `MOV`, así que el % de tiempo real no tiene por qué coincidir con el % de instrucciones. Con esa salvedad, la cadena obligada a `double` es minoría (~30%) del total, más favorable de lo esperado para la Opción 2.

## 5. Decisión

**Ningún candidato de los 4 medidos está listo para convertir a `float` entero sin más trabajo.** `he_dihydrogen` y `vp_hehe`/`v_hehe` siguen aparcados (requieren protección específica contra la cancelación, no explorada todavía). Para `duhe4x`/`uhe4x`, con el reparto de coste de 4b sobre la mesa, se decide seguir adelante con la **Opción 2 (híbrido)**: `uhe4x` se convierte entera a `float` (sin cancelación, sin necesitar protección); `duhe4x` mantiene en `double` toda la cadena que alimenta la resta (`mypow_log`, `rijp2`/`rijp4`, `inv_rijp2`, `ulx`/`ulxp`/`ulxs`) y pasa a `float` el resto (Legendre, geometría vectorial, acumulación final). Implementación y medición de tiempo real en §6.

## 6. Implementación de la Opción 2 (`uhe4x`/`duhe4x`) y medición de tiempo real

### 6.1. Diseño

**`uhe4x_float`** (`d_uhex4_mod.cuf`): conversión completa. Igual que `wavef_derwavefhe4_float`, no reutiliza `mypow_log`/`mypow_desde_log` (siguen tipadas en `double`, no engancharían el `MUFU` de `float`) -- llama a `log()`/`exp()` nativos directamente sobre `real(kind=4)`. `calpleg`/`calderpleg` tienen ahora una gemela `calplegd_float`/`calderplegd_float` (`mlegendre_gpu.cuf`, mismo cuerpo, `real(kind=4)`) -- la recurrencia de Legendre está acotada en `[-1,1]` y no participa en ninguna cancelación medida. La suma final se hace en `float` (verificado sin cancelación, 4.1) y se convierte a `double` solo al devolver el resultado, mismo criterio de protección de rango que la Opción 3.

**`duhe4x_float`** (`d_uhex4_mod.cuf`): híbrido real. La cadena `rij`/`inv_rij`/`inv_rij2`/`mypow_log`/`rijp2`/`rijp4`/`inv_rijp2`/`ulx`/`ulxp`/`ulxs` es **copia literal** de `duhe4x`, ni una línea tocada, sigue en `double`. La geometría (`cth`, `zpr`, `grz`, `gpz`, `lpz` y sus derivados) y `calderpleg` se recalculan en `float` (`grz_f`, `gpz_f`... arrays `real(kind=4)`, ya que `vec3%comp` es `double` fijo y no se puede reusar el tipo derivado para floats). Los valores "limpios" `ulx`/`ulxp`/`ulxs` (ya sin cancelación, verificado en 4.1b) se convierten a `float` **justo antes** de multiplicarse por las cantidades ya-float, y el producto se reconvierte a `double` solo al sumarse en los acumuladores de salida (`d1ux`/`d2ux`/`d1zux`/`d2zux`, que mantienen el tipo `double` de la interfaz original, sin tocar `derwavefx`/`der_wavefx_mod.cuf` fuera de las 2 nuevas subrutinas `wavefx_float`/`derwavefx_float` que llaman a las versiones `_float`).

Kernel nuevo `k_derananum_resto_float_t` (`derananum_split_mod.cuf`), idéntico a `k_derananum_resto_t` salvo llamar a `wavefx_float`/`derwavefx_float` en vez de las originales -- sustituido en las 2 horquillas de `dmc2_pipeline.cuf`.

### 6.2. Verificación

Corrida real (1000 walkers, 1 bloque equilibrio, 100 bloques × 100 pasos = 10.000 pasos DMC, `opcion=7`, mismo `conf.20.00.HH`/`etrial=-631,8` de siempre): **energía bit a bit idéntica a la referencia** (`-615.5737694990`), 1000/1000 walkers finales, sin `NaN`/pérdida de población.

Segunda verificación a escala mayor (2000 walkers, 1 eq + 50 bloques × 100 pasos = 5.000 pasos, 3 repeticiones con `conf.20.00.HH` fresco en cada una): **energía bit a bit idéntica también aquí** (`-615.5737694991`) en las 3 repeticiones, frente al mismo binario en `double` sin modificar.

### 6.3. Tiempo real (3 repeticiones, 2000 walkers, 5.000 pasos, `conf.20.00.HH` fresco en cada corrida, "tiempo de CPU en s" reportado por el propio programa)

| Repetición | `double` (original) | `float` (Opción 2) | Ahorro |
|---|---|---|---|
| 1 | 65,212 s | 60,230 s | 4,98 s (7,64%) |
| 2 | 64,444 s | 59,952 s | 4,49 s (6,97%) |
| 3 | 61,934 s | 59,772 s | 2,16 s (3,49%) |
| **Media** | **63,863 s** | **59,985 s** | **3,88 s (6,07%)** |

### 6.4. Interpretación

**Sí hay ahorro real, pero modesto** -- ~6% de media sobre el tiempo total del pipeline, con variación entre repeticiones (3,5%-7,6%, ruido del sistema, no de la propia corrida: la energía es bit a bit idéntica en las 3). Coherente con lo esperado: `duhe4x`+`uhe4x` combinados eran ~11% del coste medido en `optimizacion-mypow.md`, y de ese 11% solo una fracción (la parte "podría ir a `float`" de `duhe4x`, ~55% de sus instrucciones, más `uhe4x` entera) se convirtió -- el resto del pipeline (`vpot`, `k_fase_*`, la propia cadena obligada a `double` dentro de `duhe4x`) sigue exactamente igual. Ningún caso de pérdida de precisión detectable en las verificaciones hechas (bit a bit idéntico, no solo "dentro del error estadístico").

### 6.5. Validación de 4 semillas a escala de producción

Mismo protocolo que `float-wavef-derwavefhe4-validacion.md` §3: 4 semillas (11, 97, 42, 777), `conf.20.00.HH` fresco, 2000 walkers, 1 bloque equilibrio + 59 bloques cálculo × 20 pasos, comparado contra la producción real en `double` sin tocar.

| Semilla | `double` (meV) | `float` (Opción 2, meV) | Diferencia |
|---|---|---|---|
| 11 | −676,8178220759 ± 1,84465726 | −676,8178220933 ± 1,84465726 | 0,0000000174 |
| 97 | −677,4045573550 ± 1,80329062 | −677,4045573703 ± 1,80329062 | 0,0000000153 |
| 42 | −678,4074405137 ± 1,92476309 | −678,4074405254 ± 1,92476310 | 0,0000000117 |
| 777 | −678,9230457352 ± 1,70632962 | −678,9230457184 ± 1,70632962 | 0,0000000168 |

**Diferencia de ~1,2-1,7×10⁻⁸ meV en las 4 semillas -- unas 100 millones de veces menor que el error estadístico** (más ajustado incluso que el precedente de `wavef_derwavefhe4_float`, que fue ~100.000 veces menor). 2000/2000 walkers finales en las 4.

`diff` bloque a bloque completo (semilla 11, 59 bloques, `E_bloque`/`E_calculo`/`E_growth`/`Poblacion`): **la población coincide exactamente en los 59 bloques** -- ninguna decisión de aceptación/rechazo cambia. Las energías por bloque sí difieren, pero solo del 7º-8º dígito en adelante (p.ej. bloque 1: `-619.15805784` vs `-619.15805755`), consistente con ruido de redondeo `float`/`double` normal, no con una divergencia real de trayectoria.

### 6.6. Estado

**Verificado en las 2 escalas (10.000 pasos, 5.000 pasos ×3, y 4 semillas a escala de producción) sin ninguna señal de sesgo ni de divergencia de trayectoria -- llevado a producción** (`v2-cuda-integracion/hibrido_instrumentado/`), primera vez que esta línea de investigación (float vs double) llega a producción real -- `wavef_derwavefhe4_float`/Opción 3 se quedó solo en copias aisladas, nunca se aplicó a `hibrido_instrumentado/`.

## 7. `wavefx`/`derwavefx`: convertir también la "envoltura" (no solo `uhe4x`/`duhe4x`)

Quedaba sin mirar el código de `wavefx`/`derwavefx` en sí -- lo que calculan **antes** de llamar a `uhe4x`/`duhe4x` (`rij=sqrt(dot_product(...))`, `cth=dot_product(...)/(dnor·rij)`, la normalización de `smol`), que hasta ahora se seguía haciendo en `double` para convertirse a `float` un instante después, dentro de `uhe4x_float`/`duhe4x_float`.

**Restricción importante, descubierta al revisar el código**: en `derwavefx`, el `rtemp%comp` (vector diferencia) que se le pasa a `duhe4x_float` alimenta directamente el `rij` de la cadena protegida contra cancelación (`mypow_log`/`rijp2`/`rijp4`) -- **no se puede tocar** sin reintroducir el problema de 4.1b. Solo `wavefx` (que llama a `uhe4x_float`, sin ninguna restricción de precisión, ver 4.1) tenía margen real.

**Medición de riesgo**: instrumentado el `dot_product(rtemp,sprop3)` que calcula `cth` (el único paso de `wavefx` con una resta de signos potencialmente mixtos, los otros son sumas de cuadrados). Resultado: `impurmol=.false.` en la configuración real de este proyecto -- **la rama de `cth` nunca se ejecuta** (0 evaluaciones sobre toda una corrida de 10.000 pasos). El resto de `wavefx` (`rij=sqrt(dot_product(rtemp,rtemp))`) es una norma (suma de 3 cuadrados, siempre ≥0) -- sin cancelación posible por construcción, se mida o no.

**Implementación**: `uhe4x_float2(rij_f, cth_f)` (`d_uhex4_mod.cuf`), idéntica a `uhe4x_float` pero recibiendo `rij`/`cth` ya en `real(kind=4)` en vez de recalcularlos internamente desde `double`. `wavefx_float2` (`der_wavefx_mod.cuf`) calcula toda la envoltura (`rtemp`, `rij`, `cth`, `dnor`) en `float` desde el principio. Nuevo kernel `k_derananum_resto_float2_t`, que usa `wavefx_float2` + `derwavefx_float` (esta última sin cambios, por la restricción de arriba).

**Verificación**: bit a bit idéntica a la referencia en `double` (10.000 pasos, 1000w) y a los valores ya validados de `uhe4x_float`/`duhe4x_float` en las 4 semillas de producción (§6.5) -- ninguna diferencia detectable frente a la versión anterior.

**Tiempo real** (3 repeticiones, 2000w/5.000 pasos, frente a la producción ya con `uhe4x_float`/`duhe4x_float`):

| Repetición | Producción (`wavefx_float`) | `wavefx_float2` (envoltura completa) | Ahorro |
|---|---|---|---|
| 1 | 51,133 s | 48,562 s | 2,57 s |
| 2 | 51,291 s | 49,233 s | 2,06 s |
| 3 | 50,801 s | 49,782 s | 1,02 s |
| **Media** | **51,075 s** | **49,192 s** | **1,88 s (3,69%)** |

**Decisión**: ahorro real adicional (~3,7%) encima del ya conseguido con `uhe4x_float`/`duhe4x_float`, con energía bit a bit idéntica en las 3 repeticiones y en las 4 semillas de validación -- **llevado a producción** (`d_uhex4_mod.cuf`, `der_wavefx_mod.cuf`, `derananum_split_mod.cuf`, `dmc2_pipeline.cuf`).

## 8. `V_and_Vp_hehe` explicado en detalle: dónde vive el riesgo y por qué el truco de `duhe4x` no sirve aquí

Esta sección reúne, explicado paso a paso, todo lo averiguado sobre `V_and_Vp_hehe` (`mVheheVphehe_mod.cuf`) en esta investigación -- por qué tiene riesgo, dónde exactamente, y por qué no se le puede aplicar el mismo diseño híbrido que funcionó en `duhe4x` (§6).

### 8.1. Qué es la cancelación catastrófica (con un ejemplo pequeño)

`float32` guarda solo ~7 cifras decimales significativas. Si restas dos números que empiezan igual, las cifras que coinciden se cancelan y solo quedan las que ya eran dudosas. Ejemplo con solo 7 cifras de precisión:

```
A = 1,234567          (7 cifras correctas)
B = 1,234566          (7 cifras correctas)
A - B = 0,000001
```

El problema: si el valor real de `A` fuera en verdad `1,2345671` (redondeado a `1,234567`) y el de `B` fuera en verdad `1,2345655` (redondeado a `1,234566`), la resta exacta sería `0,0000016`, no `0,000001` -- un error del 60% en el resultado, aunque `A` y `B` por separado parecían perfectamente precisos. La resta **no crea** el error; lo que hace es **dejar de esconderlo**: dos números con error solo en su última cifra, al restarse, convierten ese pequeño error en el protagonista del resultado.

Esto es justo lo que hay que vigilar en `V_and_Vp_hehe`: no basta con que cada término (`expbase`, `F`, `sum1`...) sea razonablemente preciso por separado -- si dos de ellos son parecidos en magnitud y se restan, el resultado puede quedar dominado por el error de redondeo de cada uno.

### 8.2. La forma física de `V_and_Vp_hehe`

`V_hehe`/`Vp_hehe` es un potencial de interacción He-He de tipo Tang-Toennies: un término repulsivo (crece cuando los átomos se acercan) menos un término atractivo de dispersión (van der Waals), con una función de amortiguamiento `F` que "apaga" el término atractivo cuando los átomos están muy cerca (para que no diverja sin control). Por eso el propio potencial, en su definición física, ya es una resta:

```
v  = (repulsión)              - (atracción amortiguada)
   =  A_HeHe*expbase          - F*sum1

vp = (derivada de repulsión)  - (derivada de atracción amortiguada) + (correccion de F)
   =  termAlfa                - Fp*sum1                             + F*sum2
```

Esto no es un error de programación ni una fórmula mal escrita -- **es la física real del potencial**. Cerca del punto de equilibrio del potencial (donde la fuerza neta es pequeña porque repulsión y atracción casi se compensan), esta resta es, por construcción, la resta de dos cantidades parecidas. Es exactamente la misma razón por la que la fuerza entre dos átomos en equilibrio es pequeña: porque las dos fuerzas que actúan sobre ellos casi se cancelan.

### 8.3. Qué mide `x` y qué es `D_HeHe`

`x = r/req_HeHe` es la distancia entre los dos átomos de He, medida en unidades de la distancia de equilibrio (`req_HeHe`). `D_HeHe = 1,4088` es un parámetro del modelo: mientras `x >= D_HeHe` (átomos relativamente separados), la función de amortiguamiento `F` vale exactamente 1 y su derivada `Fp` vale exactamente 0 -- el amortiguamiento no hace nada. Solo cuando `x < D_HeHe` (átomos más cerca) `F` empieza a bajar de 1 y `Fp` deja de ser 0.

### 8.4. Lo que se midió, y qué significa cada resultado

Se instrumentó el código real (no una prueba sintética) para responder, con datos de una corrida de verdad (1000 walkers, 10.000 pasos DMC), las preguntas que iban surgiendo:

**a) ¿Se acerca `x` a `D_HeHe` de verdad, o es un caso raro?**

```
closeness (D_HeHe/x - 1) MINIMO: 4,36e-10   <- x llega a estar prácticamente ENCIMA de D_HeHe
rama x < D_HeHe activa: 4.592.028 de 8.151.084 evaluaciones = 56,3%
```

No es un caso raro -- **la mitad de las veces** los átomos están en la zona donde `F`/`Fp` importan, y en algún momento `x` se acerca a `D_HeHe` hasta la décima cifra decimal.

**b) Cuando `F`/`Fp` están activos, ¿pesan de verdad en el resultado, o quedan tapados por otros términos mucho más grandes?**

Se midió qué fracción del resultado representa cada término, con la fórmula `fracción = |término| / max(|todos los términos que se combinan|)` -- una fracción cercana a 1 significa "este término es tan grande como el más grande de todos"; cercana a 0 significa "este término es insignificante al lado de los demás".

```
F*sum1 en v:    fracción entre 0,053 y 1,000 -- domina v (>50%) en 8,2 millones de evaluaciones
Fp*sum1 en Vbp: fracción hasta 0,189 -- nunca domina sola, pero pesa >10% millones de veces
```

Respuesta: **no, no quedan tapados**. `F*sum1` (el término atractivo) llega a ser el 100% del resultado en algún punto, y domina en la inmensa mayoría de los casos. `Fp*sum1` nunca es el término más grande de `Vbp` por sí solo, pero contribuye de forma real y frecuente.

**c) ¿Y las otras dos operaciones de la función -- `v = v + addin` y `vp = (Vap+Vbp)*constante` -- tienen el mismo problema?**

Esta pregunta la planteó directamente el usuario, razonando sobre el código antes de medir -- exactamente el método correcto: primero plantear la hipótesis mirando la fórmula, después comprobarla con datos.

```
addin: fracción MAXIMA 1,26% de v -- nunca pesa lo suficiente como para tapar
       (ni para ser un problema) el resultado de v
Vap+Vbp: ratio de cancelación entre 0,969 y 1,013 -- básicamente SIN cancelación,
         en 5.178.838 evaluaciones, ni una sola por debajo de ese rango
```

Respuesta: **`addin` y `Vap+Vbp` están limpios**. La hipótesis de que `Vap` y `Vbp` pudieran tener signos opuestos y magnitudes parecidas era razonable de plantear, pero los datos reales dicen que no ocurre -- cuando `Vap` es pequeño (cerca de un cruce por cero del coseno), no hay nada que cancelar; y cuando `Vap` es grande, no coincide con que `Vbp` sea comparable y de signo contrario.

### 8.5. Por qué el diseño que funcionó en `duhe4x` no se puede copiar aquí

En `duhe4x` (§6), el diseño híbrido funcionó porque el cálculo se divide en dos partes **verdaderamente independientes**, que solo se juntan al final con una suma:

```
CADENA QUE CANCELA (debe quedarse en double)      CADENA SEGURA (puede ir en float)
  rij, mypow_log, rijp2, rijp4                       geometria (grz, gpz...)
  -> ulx, ulxp, ulxs (ya "limpios",                   Legendre (pl, d1pl, d2pl)
     sin cancelacion, verificado)
              \                                      /
               \____________ SE COMBINAN AQUI _______/
                  (ulx/ulxp/ulxs ya son valores
                   correctos; multiplicarlos por
                   algo en float no reintroduce
                   el problema, porque la cancelacion
                   YA PASÓ y ya se resolvió en double)
```

La clave es que `ulx`/`ulxp`/`ulxs` **ya están calculados y ya son correctos** en el momento en que se combinan con la parte en `float` -- la cancelación ya ocurrió y se resolvió, dentro de la parte que se dejó en `double`. Convertir la parte de Legendre/geometría a `float` no toca esos valores ya calculados.

En `V_and_Vp_hehe` **no hay dos cadenas independientes** -- hay una sola cadena, y la resta está al final de ella, no en medio:

```
x (double)
  |
  +--> expbase, F, sum1, sum2   <- estos SON los operandos de la resta,
  |                                 no un calculo aparte que se junta despues
  |
  v = A_HeHe*expbase - F*sum1   <- si expbase/F/sum1 se calculan en float,
                                    el error YA esta metido aqui, y la resta
                                    (se haga en double o en float) no puede
                                    recuperar cifras que nunca existieron
```

`sum2` es un buen ejemplo de esto: por sí solo, calcular `sum2` no tiene ningún problema (es una suma de 3 términos del mismo signo, como `uhe4x`). Pero `sum2` no vive aislado -- alimenta directamente `F*sum2`, uno de los 3 términos que se combinan en la resta de `Vbp`. Convertirlo a `float` significa que ese término entra en la resta con solo ~7 cifras fiables, exactamente el mismo problema que si convirtiéramos `Fp*sum1`.

**Las únicas piezas de `V_and_Vp_hehe` que sí son como la parte "segura" de `duhe4x`** -- cálculo aparte, se combinan al final sin volver a cancelar -- son `addin` y `Vap` (confirmado en 8.4c). Pero son piezas pequeñas (`addin` nunca pasa del 1,26% del resultado) y solo se calculan en una ventana estrecha de `x` -- convertirlas a `float` sería seguro, pero la ganancia de tiempo esperable es pequeña, mucho menor que la conseguida con `duhe4x`/`uhe4x` (§6-7).

### 8.6. Resumen de la línea `V_and_Vp_hehe`

| Pieza | ¿Alimenta una resta que cancela? | ¿Se puede convertir a `float` de forma aislada? |
|---|---|---|
| `x`, potencias de `x`, recíprocos | Sí (alimentan `sum1`/`sum2`/`expbase`) | No |
| `expbase`, `F`, `Fp` | Sí (son operandos directos de las restas) | No |
| `sum1` | Sí (operando de `v` y de `Vbp`) | No |
| `sum2` | Sí (operando de `Vbp`, aunque no domina) | No |
| `addin` | No (se suma después, ya no cancela) | Sí, pero ganancia pequeña |
| `Vap` | No (`Vap+Vbp` no cancela, medido) | Sí, pero ganancia pequeña |
| **La resta de `v`** | Es la propia resta | Necesita protección específica, no diseñada todavía |
| **La resta de `Vbp`** | Es la propia resta | Necesita protección específica, no diseñada todavía |

**Conclusión de esta línea**: `V_and_Vp_hehe` sigue aparcada. No es un candidato "a medias" que se pueda convertir por partes como `duhe4x` -- casi todo su coste real (`expbase`, `F`, `sum1`, `sum2`, las potencias de `x`) forma parte de las dos restas que cancelan, y las únicas piezas seguras (`addin`, `Vap`) son demasiado pequeñas para justificar el esfuerzo por sí solas. Una protección real para esta función necesitaría un diseño distinto -- por ejemplo, reformular las restas para calcular directamente la diferencia pequeña sin pasar por los dos términos grandes (una técnica real en análisis numérico, pero que exigiría rehacer la fórmula matemática, no solo cambiar tipos de dato) -- que no se ha explorado en esta sesión.

## Ficheros

- Copia aislada de esta medición: `/tmp/duhe4x-float-test/` (no persistida) -- instrumentación en `mVheheVphehe_mod.cuf`, `d_uhex4_mod.cuf` (solo `uhe4x`), `He_dihydrogen.f` + nuevo `he_dihydrogen_diag_mod.cuf`, `mmontecarlo.f90`.
- Copia aislada de la corrección de `duhe4x` (gradiente/laplaciano): `/tmp/duhe4x2-float-test/` (no persistida) -- instrumentación añadida en `d_uhex4_mod.cuf` (`ulxp`, `ulxs`, `d2ux`).
- Copia aislada del perfilado SASS de §4b: `/tmp/duhe4x-ncu-profile/` (no persistida) -- binario limpio (sin instrumentación) para `nvdisasm -g`.
- Copia aislada de la implementación de §6: `/tmp/uhe4x-duhe4x-float-impl/` (no persistida) -- `mlegendre_gpu.cuf` (+`calplegd_float`/`calderplegd_float`), `d_uhex4_mod.cuf` (+`uhe4x_float`/`duhe4x_float`), `der_wavefx_mod.cuf` (+`wavefx_float`/`derwavefx_float`), `derananum_split_mod.cuf` (+`k_derananum_resto_float_t`), `dmc2_pipeline.cuf` (horquillas apuntando al kernel `_float`).
- Copia aislada de la implementación de §7: `/tmp/wavefx-full-float/` (no persistida) -- `d_uhex4_mod.cuf` (+`uhe4x_float2`), `der_wavefx_mod.cuf` (+`wavefx_float2`), `derananum_split_mod.cuf` (+`k_derananum_resto_float2_t`), `dmc2_pipeline.cuf` (horquillas apuntando al kernel `_float2`).
- Comparación de tiempos de §6: `/tmp/timing_compare/`; de §7: `/tmp/timing_compare2/` (ninguna persistida).
- Comparación de tiempos: `/tmp/timing_compare/` (no persistida) -- binario `double` (copia limpia de producción) vs binario `float` de `/tmp/uhe4x-duhe4x-float-impl/`.
- Copia aislada de la medición detallada de §8: `/tmp/vhehe-rango-detalle/` (no persistida) -- instrumentación en `mVheheVphehe_mod.cuf` (`closeness`, `frac_Fpsum1`, `frac_Fsum1`, `frac_addin`, `cancel_VapVbp`) y `mmontecarlo.f90`.
- Copia aislada de la medición de §3.2b/3.2c/3.2d/3.2e: `/tmp/energy1-cancel-test/` (no persistida) -- `he_dihydrogen_hehe_diag_mod.cuf` (`ENERGY1`, coordenadas), `atheta_diag_mod.cuf` (`atheta`), `induccion_diag_mod.cuf` (`rh1`/`rh2`/`r0`, `Ex0`/`Ey0`/`Ez0`), instrumentación en `He_dihydrogen.f` y `mmontecarlo.f90`.
