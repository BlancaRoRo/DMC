# Cuarto kernel: `angle` / `scalar_product` / `vec_norm`

Documentación de [`v1-cuda-desarrollo/angle_scalar_vec/angle_scalar_vec.cuf`](../angle_scalar_vec/angle_scalar_vec.cuf). Son las tres rutinas de álgebra vectorial de apoyo que usa `He_dihydrogen` en [`bh_heh2m.f`](../angle_scalar_vec/bh_heh2m.f) (líneas 540-583 del original). A diferencia de `calpleg`/`V_hehe` (un escalar `r` por hilo), aquí cada hilo trabaja con **vectores de 3 componentes**, lo que obliga a un array de dos dimensiones en vez de uno.

---

## Parte 1 — Implementación

## 1. Por qué `(3,n)` y no un array de una dimensión

En `calpleg` y `V_hehe`/`Vp_hehe`, cada hilo tenía un único número de entrada (`r(n)`, un escalar por hilo) y un único número de salida. Aquí `angle`/`scalar_product` reciben **dos vectores de 3 componentes cada uno**, y `vec_norm` recibe uno. Un solo hilo no puede trabajar con "un valor" — necesita sus 3 componentes juntas. La solución es un array con una dimensión extra:
```fortran
double precision, device, intent(in) :: vec1(3,n), vec2(3,n)
```
`n` walkers/pares, cada uno con sus 3 componentes. Dentro del kernel, cada hilo recorta su propia columna con la notación de sección de array de Fortran:
```fortran
call angle(vec1(:,i), vec2(:,i), ang_out(i))
```
`vec1(:,i)` son las 3 componentes del hilo `i` — se le pasan a `angle` exactamente como si fueran el `vec1(3)` de toda la vida, sin que la subrutina `attributes(host,device)` necesite saber nada de que viene de un array más grande.

### El matiz de rendimiento: `(3,n)` es cómodo de escribir, pero no es el orden óptimo para la GPU

Con `mparametros.f90`/`mtipos.f90` ya vimos que Fortran es *column-major* (el primer índice es el que varía más rápido en memoria), y que para que hilos consecutivos de un warp lean memoria contigua (coalescencia), conviene que el índice de **walker/hilo** sea el que varía más rápido — es decir, lo ideal sería `vec1(n,3)` (hilo primero, componente después), no `vec1(3,n)`.

Aquí se ha usado `(3,n)` a propósito, por comodidad de escritura y de lectura (`vec1(:,i)` se lee de forma natural como "el vector del hilo `i`", y cada subrutina recibe exactamente un `vec1(3)` sin tener que reordenar nada) — pero con `n=5` walkers de prueba esto es irrelevante para el rendimiento. **Si esto se escala a miles de walkers reales, conviene revisar el orden de los índices**: con `(3,n)`, dos hilos consecutivos (`i`, `i+1`) leyendo su primera componente están a 3 posiciones de distancia en memoria (acceso con salto, no coalescido); con `(n,3)` estarían contiguos. Queda anotado como algo a revisar en la fase de rendimiento, no en esta fase de corrección.

## 2. Los errores que había en el primer borrador

1. **`ang = call angle()`** — `angle` es `subroutine`, no `function` (a diferencia de `V_hehe`). Una subrutina se invoca con `call` como instrucción propia, nunca dentro de una asignación; el resultado sale por el argumento `intent(out)`, no por el nombre de la subrutina.
2. **`vec1(3), vec2(3)` sin la dimensión de hilo** en los kernels — con eso, los 32 hilos de un bloque habrían leído todos el mismo vector y escrito todos en la misma posición de salida (carrera de datos). Corregido a `vec1(3,n)`, `vec2(3,n)`, con cada hilo indexando su propia columna (§1).
3. **Un parámetro `l`** en las tres firmas de kernel, que no pertenece aquí — resto de copiar la plantilla de `calpleg` (donde sí hacía falta el grado del polinomio). `angle`/`scalar_product`/`vec_norm` no tienen ningún parámetro de ese tipo; se quitó.

---

## Parte 2 — Pruebas

## 3. Los 5 pares de vectores de prueba

[`angle_scalar_vec.cuf`](../angle_scalar_vec/angle_scalar_vec.cuf), `program test_angle_scalar_vec`:
```fortran
vec1_h(:,1) = (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,1) = (/  1.0d0, 0.0d0, 0.0d0 /)  ! paralelos      -> angulo=0
vec1_h(:,2) = (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,2) = (/ -1.0d0, 0.0d0, 0.0d0 /)  ! antiparalelos  -> angulo=pi
vec1_h(:,3) = (/ 1.0d0, 0.0d0, 0.0d0 /); vec2_h(:,3) = (/  0.0d0, 1.0d0, 0.0d0 /)  ! perpendiculares-> angulo=pi/2
vec1_h(:,4) = (/ 1.0d0, 2.0d0, 3.0d0 /); vec2_h(:,4) = (/  4.0d0, 5.0d0, 6.0d0 /)  ! generico 1
vec1_h(:,5) = (/ 2.5d0,-1.3d0, 0.7d0 /); vec2_h(:,5) = (/ -0.4d0, 3.2d0, 1.1d0 /)  ! generico 2
```
Los tres primeros tienen ángulo conocido de antemano (0, π, π/2) — comprobación analítica directa, igual que los extremos `x=±1` en `calpleg`. Los dos últimos son genéricos, sin ningún valor "bonito", para no probar solo casos especiales.

**Resultado real de la ejecución** (`nvfortran -cuda bh_heh2m.f angle_scalar_vec.cuf -o test_angle`, sin flags):
```
--- par 1  (paralelos)      angle CPU=GPU= 0.000000000000   |err| angle=0.00E+00  scalar=0.00E+00  norm=0.00E+00
--- par 2  (antiparalelos)  angle CPU=GPU= 3.141592653590   |err| angle=0.00E+00  scalar=0.00E+00  norm=0.00E+00
--- par 3  (perpendiculares)angle CPU=GPU= 1.570796326795   |err| angle=0.00E+00  scalar=0.00E+00  norm=0.00E+00
--- par 4  (generico)       angle CPU=GPU= 0.225726128553   |err| angle=2.78E-17  scalar=0.00E+00  norm=0.00E+00
--- par 5  (generico)       angle CPU=GPU= 2.030570982660   |err| angle=4.44E-16  scalar=0.00E+00  norm=0.00E+00

 PASA: GPU y CPU coinciden dentro de tolerancia
```
`scalar_product` y `vec_norm` dan cero exacto en los 5 casos (son solo sumas de productos y una raíz, sin más). `angle` da cero exacto en los tres casos con ángulo "bonito", y un resto de 1-2 ULP en los dos genéricos — mismo orden de magnitud que vimos en `Vp_hehe`, y por la misma familia de motivos (§4).

También se comprobó la tercera vía, [`test_angle_gfortran.f90`](../angle_scalar_vec/test_angle_gfortran.f90) (mismo patrón que en los kernels anteriores: mismos 5 pares, llamando a `angle`/`scalar_product`/`vec_norm` de `bh_heh2m.f` compilado con `gfortran`) — **valores idénticos** a la columna CPU de `test_angle`.

### Dos tablas completas: con y sin flags

*(Estas dos tablas son del estado ORIGINAL, con `dacos` intrínseca — antes del cambio a `myacos` de §5. Se dejan como registro de lo que se encontró; el estado actual del código, con `myacos`, se documenta en §5.)*

Repitiendo con salida de precisión completa (`es24.17`), comparando explícitamente GPU-vs-`gfortran` y CPU(`nvfortran`)-vs-GPU, con y sin `-Kieee -Mnofma`/`-ffp-contract=off`:

**Tabla 1 — GPU (`nvfortran`) vs CPU-`gfortran`**:

| par | `angle`/`scalar`/`norm` | sin flags | con flags |
|---|---|---|---|
| 1-5 | los tres, todos los pares | `0.00E+00` | `0.00E+00` |

**GPU coincide con `gfortran` exacto en los 5 pares, con y sin flags** — incluidos los dos ángulos genéricos donde sí hay residuo frente a CPU-`nvfortran` (Tabla 2). Es decir: la GPU (`libdevice`) calcula `acos` más parecido a `glibc` que el propio `nvfortran`-host sin `-Kieee` para estos dos valores concretos — pura coincidencia de qué implementación se acerca a cuál, no una relación fiable (ver más abajo).

**Tabla 2 — CPU(`nvfortran`) vs GPU**:

| par | | sin flags | con flags |
|---|---|---|---|
| 1-3 | `angle`/`scalar`/`norm` | `0.00E+00` | `0.00E+00` |
| 4 | `angle` | `2.78E-17` | `0.00E+00` |
| 5 | `angle` | `4.44E-16` | `0.00E+00` |
| 4-5 | `scalar`/`norm` | `0.00E+00` | `0.00E+00` |

Ver §4 para la causa raíz exacta de los pares 4/5 (no es reasociación del bucle, es `dacos` con implementación de host distinta según `-Kieee`).

## 4. Las flags, y por qué aquí es al revés que en `Vp_hehe`

Se repitió la misma comprobación de flags que en [`V_hehe_Vp_hehe.md`](V_hehe_Vp_hehe.md) §9, aislando `-Kieee` y `-Mnofma` por separado:

| Flags | `angle` — par 4 | `angle` — par 5 |
|---|---|---|
| Ninguna | `2.78E-17` | `4.44E-16` |
| `-Mnofma` (sola) | `2.78E-17` — sin cambio | `4.44E-16` — sin cambio |
| `-Kieee` (sola) | `0.00E+00` — arreglado | `0.00E+00` — arreglado |
| `-Kieee -Mnofma` | `0.00E+00` | `0.00E+00` |

**Aquí es `-Kieee` la que hace todo el trabajo, y `-Mnofma` no cambia nada** — justo al revés que en `Vp_hehe`, donde `-Mnofma` sola lo arreglaba y `-Kieee` sola no. Conclusión importante: **no hay una causa universal para este tipo de diferencias de 1 ULP entre CPU y GPU**; cada expresión puede depender de un mecanismo distinto del compilador, y hay que comprobarlo caso por caso en vez de asumir que la flag que funcionó la última vez es la que hace falta esta vez.

**Corrección posterior — la causa real no es la reasociación del bucle, es `dacos`.** Esta sección se escribió antes de investigar a fondo `dacos` (ver `He_dihydrogen.md` Parte 5, `glibc_math.md` Parte 3): en aquel momento se asumió que el bucle acumulador reordenaba la suma de forma distinta en CPU y GPU, sin comprobarlo. Instrumentando directamente `sprod`/`norm1`/`norm2` (los acumuladores del bucle) y `fi=sprod/(norm1*norm2)` (el argumento que recibe `dacos`) para el par 5, resultan **bit a bit idénticos entre host y device** — el bucle no reasocia nada distinto. La única diferencia aparece en `dacos(fi)` mismo:
```
fi                HOST=-4.43746175520633779E-01   GPU=-4.43746175520633779E-01   (igual)
dacos(fi)=ang     HOST= 2.03057098266013325E+00   GPU= 2.03057098266013369E+00   (distinto)
```
Confirmado con `nm` (mismo método que en `He_dihydrogen.md` Parte 5, §12): sin `-Kieee`, el host enlaza `__fd_acos_1` ("fast"); con `-Kieee`, enlaza `__pd_acos_1` ("precise") — dos implementaciones de `acos` distintas dentro de la propia `libnvcpumath.so`, y para este valor de `fi` concreto la versión "precisa" (la que usa `-Kieee`) coincide con la de la GPU, mientras que la "rápida" no. Es el mismo mecanismo, no una reasociación de sumas.

**Importante: esto no es una "solución" general de `-Kieee` para `dacos`.** En `He_dihydrogen.md` (Parte 5, walker 3/átomo 4) se encontró un valor de `fi` distinto donde ocurre justo lo contrario: con `-Kieee`, el host coincide con `gfortran` pero **no** con la GPU. Cuál de los dos `acos` de host (rápido o preciso) coincide con el de la GPU depende del valor concreto de entrada — no hay ninguna garantía de que `-Kieee` cierre el hueco para *todos* los ángulos, solo lo cierra por coincidencia para los pares 4/5 de esta prueba en concreto.

## 5. `dacos` → `myacos`: cierre garantizado, no solo "no se ha notado"

Que la Tabla 1 (§ arriba) diera `0.00E+00` para los 5 pares originales **no demuestra que `dacos` esté bien** — solo demuestra que, para esos 5 ángulos concretos, no tropezamos con un caso donde se note (confirmado preguntándole directamente a `dacos(-0.5773502691896258)` — el `fi` real de `He_dihydrogen`, walker 3/átomo 4 — en GPU: da `2.18627603546528437`, mientras que `gfortran` da `2.18627603546528393`; **no coinciden**). Cinco vectores de prueba no cubren el espacio de ángulos que puede aparecer en una simulación real de millones de pasos Monte Carlo.

Por eso se sustituye `dacos` por `myacos` (`glibc_acos.cuf`, puerto de glibc 2.39 ya verificado con 26 casos en `glibc_math.md`) en `angle`, y se añade un **sexto par** que reproduce exactamente ese ángulo problemático (`vec1=(2,2,2)`, `vec2=(0,0,-1.05887100)`, los mismos vectores reales de `He_dihydrogen`):

```bash
nvfortran -cuda -Kieee -Mnofma glibc_exp_mod.o glibc_acos.o bh_heh2m.o angle_scalar_vec.o -o test_angle_scalar_vec
./test_angle_scalar_vec
gfortran -ffixed-line-length-132 -ffp-contract=off bh_heh2m.f test_angle_gfortran.f90 -o test_angle_gfortran
./test_angle_gfortran
```

**Resultado — GPU (`myacos`) vs CPU-`gfortran`, los 6 pares, con y sin flags:**

| par | `angle`/`scalar`/`norm` | sin flags | con flags |
|---|---|---|---|
| 1-6 | los tres, todos los pares | `0.00E+00` | `0.00E+00` |

**Coincidencia exacta en los 6 pares, con y sin flags — incluido el par 6**, el ángulo que antes (con `dacos` intrínseca) daba `GPU≠gfortran`:
```
par 6: HP angle CPU= 2.18627603546528393E+00   GPU= 2.18627603546528393E+00   (myacos, idéntico)
```
frente al `2.18627603546528437E+00` que daba `dacos` de GPU antes del cambio. Esta vez el cierre no depende de qué flag se use ni de qué ángulo caiga por casualidad del lado bueno — `myacos` da el mismo resultado que `gfortran` para cualquier entrada, verificado ya en 27 casos distintos entre este documento y `glibc_math.md` (26 allí + este ángulo aquí).

**Misma recomendación práctica que en `Vp_hehe`:** usar `-Kieee -Mnofma`/`-ffp-contract=off` para validar corrección, no en compilaciones pensadas para medir rendimiento — pero ahora, para `angle`, ya no depende de las flags: `myacos` cierra el hueco de forma incondicional.

## 6. Batería extrema: 22 pares, las 8 zonas de `myacos` y magnitudes de 1e-150 a 1e150

6 pares no bastan para confiar en un puerto de una función transcendente — pueden no tocar ninguna de las zonas delicadas del algoritmo. Se añaden 16 pares más (`vec2` siempre de norma 1 por construcción, así `fi=vec2(1)` exacto salvo redondeo):

- **Zonas 0-7 de `glibc_acos.cuf`** (umbrales por `|fi|`: `2.78e-17`, `0.125`, `0.5`, `0.75`, `0.921875`, `0.953125`, `0.96875`, `1`): un par por zona, con signo positivo y negativo donde aplica.
- **Muy cerca de `±1`** (`fi=0.999999`, `fi=-0.999999`): el punto más delicado de `acos` — la derivada `1/√(1-x²)` diverge ahí, así que cualquier error de redondeo en `fi` se amplifica al máximo al pasar por `acos`.
- **Magnitudes extremas** (`1e150` y `1e-150`, misma dirección relativa que el par 11): para comprobar que `vec_norm`/`scalar_product` también aguantan bajo escalas muy distintas entre `vec1` y `vec2`, no solo `angle`.

**Resultado — GPU (`myacos`) vs CPU-`gfortran`, 22 pares × 3 cantidades (66 comparaciones):**

| | sin flags | con flags |
|---|---|---|
| Exactas (`0.00E+00`) | 65 / 66 | **66 / 66** |
| Con residuo | 1 (par 22, `angle`, `2.22E-16`) | 0 |

**El único caso con residuo (par 22, magnitud `1e-150`, sin flags) no es culpa de `myacos`.** Instrumentando `fi` directamente: `nvfortran`-host y `nvfortran`-device dan **el mismo** `fi` entre sí (`9.27295218001612298E-01`), pero **distinto** de `gfortran` (`9.27295218001612076E-01`) — la divergencia está en la cadena `sprod/(norm1*norm2)` bajo magnitudes tan extremas, antes incluso de llegar a `acos`, y es la misma familia de diferencia FMA/reasociación ya vista en todo el árbol (`calpleg`/`V_hehe`/`Vp_hehe`) — se cierra con `-Kieee -Mnofma`, igual que las demás.

**Con las flags activas, 66/66 exactas** — `myacos` sostiene el cierre total en las 8 zonas del algoritmo, en los dos extremos cercanos a `±1` (el caso más delicado matemáticamente), y bajo 300 órdenes de magnitud de diferencia entre `vec1` y `vec2`.
