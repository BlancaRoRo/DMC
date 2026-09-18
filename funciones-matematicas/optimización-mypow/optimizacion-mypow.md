# Optimización de `mypow` (y, más adelante, `myexp`)

## 1. Detección: dónde se va el tiempo de verdad

Perfilado con `ncu --page source` (correlación por línea de código fuente, exportado a CSV y sumado por función — ver `v3-cuda-optimización/perfilado-medicion/fase0-perfilado/`) sobre `k_derananum_t`/`k_vpot_t`, 1.500 walkers. `derananum`/`vpot` **casi no gastan tiempo en su propia lógica** (0,7% combinado) — todo el coste está en las funciones matemáticas que llaman:

| Función | % del total (`k_derananum_t`+`k_vpot_t`) |
|---|---|
| **`mypow`** | **28,7%** |
| `myexp` + 3 auxiliares internas | 19,1% (combinado) |
| `vp_hehe`/`v_hehe` (potencial He-He) | 12,4% |
| `duhe4x`/`uhe4x` (potencial impureza) | 9,7% |
| `he_dihydrogen` (potencial He-H₂) | 7,6% |
| `derwavefhe4`/`wavefhe4` (función de onda He4) | 9,1% |
| `mycos`+`mysin` | 7,2% |
| `myacos` | 1,6% |

`mypow` es, con diferencia, la función individual más cara de todo el pipeline GPU — casi 1 de cada 3 ciclos de `derananum`/`vpot` se va ahí.

## 2. Por qué NO sustituimos `mypow` por la `x**y` nativa de la GPU

Primera idea explorada: cambiar `mypow` (puerto bit-exacto de `glibc`) por la intrínseca nativa de CUDA (`x**y`), mucho más barata. Verificado contra `gfortran` (la referencia real del proyecto, no otra pieza de GPU — ver `MEMORY.md`, "verificar contra el original"):

| | Diferencias con `gfortran` (60 pares `rij,nu` reales) |
|---|---|
| `mypow` (host y device) | **0** |
| `x**y` nativa — **host** (CPU, nvfortran) | **0** |
| `x**y` nativa — **device** (GPU) | **16 de 60 (26,7%)** |

La GPU nativa diverge de `gfortran` en más de 1 de cada 4 pares probados (siempre por el último bit). Confirmado con dos corridas completas de DMC (1.000 walkers, 59 bloques, dos semillas distintas): con la semilla 11 la energía coincidía por pura casualidad (esa trayectoria concreta no tocó ningún par divergente); con la semilla 23, la versión rápida y la bit-exacta se separan de `gfortran` cifras parecidas (0,48σ vs 0,74σ) — dentro de lo estadísticamente esperable en ambos casos, pero sin ninguna garantía real, y con un riesgo ya cuantificado y no despreciable. **Se descarta esta vía**: no es "acelerar el código portado", es sustituirlo por otro con menos garantías.

## 3. La vía elegida: acelerar `mypow` sin tocar su precisión

`x^y = exp(y · log(x))`. Dentro de `mypow` hay dos partes ya diferenciadas en el propio código (`glibc_pow.cuf`):

- **Parte 1** (`log_inline`): calcula `log(x)` — solo depende de `x`.
- **Parte 2** (`pow_exp_inline` + la combinación con `y`): depende de `x` **y** de `y`.

En varios sitios del código portado, `mypow` se llama **más de una vez con el mismo `x`** y solo cambia `y`:

- `duhe4x`/`uhe4x` (`d_uhex4_mod.cuf`): `mypow(rij,pxhe4(2,il))` y `mypow(rij,pxhe4(4,il))`, mismo `rij`, dentro del mismo bucle — sin que haga falta fusionar nada, ya están en la misma subrutina.
- `wavefhe4`+`derwavefhe4` (`der_wavefhe4_mod.cuf`): dos subrutinas **separadas** que recorren los mismos pares de átomos y recalculan el mismo `rij` cada una — aquí hace falta fusionarlas en una sola para que compartan el `rij` (y de ahí, el `log(rij)`).

Cada vez que esto pasa, la Parte 1 (`log_inline`, la cara) se repite para un `x` que no ha cambiado. La solución: partir `mypow` en sus dos mitades naturales, para poder calcular la Parte 1 una vez y reutilizarla.

## 4. Implementación y verificación (`prueba_split_mypow/`)

`glibc_pow.cuf`: se añadieron `mypow_log(x, hi, lo)` (Parte 1, expuesta) y `mypow_desde_log(hi, lo, y)` (Parte 2, expuesta) — **`mypow` original no se toca**, sigue ahí tal cual para quien no necesite reutilizar nada.

`test_split_mypow.cuf`: compara, con los exponentes reales de este proyecto (`p2=9.763290`, `p4=0.129298`, de `in.mcv`, l=0 nu/p4 he4) y `rij` en el rango físico real (0,3-6,3 Å, incluido el caso especial `x=1,0`):

- **"Antes"**: `mypow(rij,p2)` + `mypow(rij,p4)` — dos llamadas completas (el código actual).
- **"Después"**: `mypow_log(rij)` una vez + `mypow_desde_log(...,p2)` + `mypow_desde_log(...,p4)`.

### Resultado

```
PASA (host): mypow(x,y) == mypow_desde_log(mypow_log(x),y) en los 3000 casos (incluido x=1.0)
PASA (device): mismo resultado bit a bit en los 3000 casos

n walkers = 3000, repeticiones = 500
ANTES   (2x mypow completa):        0.01678 ms/rep
DESPUES (1x log + 2x remate):       0.01316 ms/rep
factor de mejora: 1.275x
```

**Bit a bit idéntico** en los 3.000 casos (host y device, incluido `x=1,0`) — confirma que partir `mypow` no cambia ni un bit del resultado, es la misma aritmética. Y **1,275x más rápido** en este patrón de dos llamadas con el mismo `rij`.

## 4b. Aplicado a `duhe4x`/`uhe4x` (el caso real, pipeline completo)

`d_uhex4_mod.cuf`: `duhe4x` y `uhe4x` calculan `log(rij)` **una vez** (con `mypow_log`, antes del bucle `do il=0,lxhe4`) y reutilizan ese resultado en las `2*(lxhe4+1)` llamadas a `mypow_desde_log` que antes eran `mypow` independientes — en la configuración real, `lxhe4=3` (4 términos angulares), así que cada llamada a `duhe4x`/`uhe4x` pasa de 8 `log_inline` a solo 1.

### Verificación (copia aislada `gpu-duhe4x-optimizado/`, pipeline completo)

Comparado contra la copia sin modificar, en 4 escalas de walkers (500, 1.000, 2.000, 3.000), misma semilla (11), mismos bloques (1 eq + 59 cálculo × 20 pasos), `conf.20.00.HH` fresco en cada corrida:

| Walkers | Energía — referencia | Energía — optimizado | `pasodmc_gpu_pipeline` ref. | `pasodmc_gpu_pipeline` opt. | Diferencia |
|---|---|---|---|---|---|
| 500 | -683,4776947558 | -683,4776947558 (idéntica) | 32,1363 s | 31,2879 s | −2,64% |
| 1.000 | -679,3359577544 | -679,3359577544 (idéntica) | 45,7460 s | 45,5247 s | −0,48% |
| 2.000 | -676,2974256246 | -676,2974256246 (idéntica) | 71,0152 s | 70,6015 s | −0,58% |
| 3.000 | -678,0618871962 | -678,0618871962 (idéntica) | 112,0123 s | 111,0354 s | −0,87% |

**Energía bit a bit idéntica en las 4 escalas** — confirma que el cambio no toca ni un bit del resultado también en el pipeline completo, no solo en la prueba aislada de `mypow`. **Más rápido en las 4 escalas, nunca más lento** (−0,48% a −2,64%) — la diferencia individual en cada escala es pequeña (del orden del ruido de corrida a corrida que se ha visto en otras partes de esta sesión), pero que sea sistemáticamente favorable en las 4 pruebas independientes, no aleatoriamente a favor o en contra, es una señal más fiable que cualquier medida suelta de que el ahorro es real, aunque modesto.

## 4c. Fusión `wavefhe4`+`derwavefhe4`, combinada con lo anterior

Igual que en `duhe4x`, `wavefhe4` (valor) y `derwavefhe4` (derivada) recorren los mismos pares `(iatom,jatom)` y calculan el mismo `rij` cada una por separado — pero aquí, a diferencia de `duhe4x`, están en **dos subrutinas distintas**, así que hace falta fusionarlas en una sola (`wavef_derwavefhe4`, `der_wavefhe4_mod.cuf`) para poder compartir `rij`/`log(rij)`. Cada acumulador (`ujas`, `d1wf`, `d2wf`) sigue sumando en el mismo orden exacto que antes — fusionar los bucles no reordena ninguna suma, solo evita recalcular `rij` y `log(rij)`. `wavefhe4`/`derwavefhe4` originales no se tocan, quedan sin usar como referencia.

`derananum_mod.cuf`: la llamada a `wavefhe4` se sustituye por `wavef_derwavefhe4` (que ya calcula `d1wfhe4`/`d2wfhe4` de paso), y se elimina la llamada posterior a `derwavefhe4`.

### Verificación (mismas 4 escalas, `duhe4x`/`uhe4x` + fusión `wavefhe4` combinadas)

| Walkers | Energía — referencia | Energía — optimizado | `pasodmc_gpu_pipeline` ref. | `pasodmc_gpu_pipeline` opt. | Diferencia |
|---|---|---|---|---|---|
| 500 | -683,4776947558 | -683,4776947558 (idéntica) | 32,3058 s | 30,6296 s | **−5,19%** |
| 1.000 | -679,3359577544 | -679,3359577544 (idéntica) | 46,5752 s | 43,4370 s | **−6,74%** |
| 2.000 | -676,2974256246 | -676,2974256246 (idéntica) | 73,2588 s | 70,3082 s | **−4,03%** |
| 3.000 | -678,0618871962 | -678,0618871962 (idéntica) | 110,7833 s | 106,5024 s | **−3,86%** |

**Energía bit a bit idéntica en las 4 escalas** (igual que con `duhe4x`/`uhe4x` solo). El ahorro combinado (3,86%-6,74%) es claramente mayor que con `duhe4x`/`uhe4x` solo (0,48%-2,64%) — y, sobre todo, **mayor que el ruido de corrida a corrida ya establecido en esta sesión** (0,5%-2,7%), así que aquí sí se puede afirmar con confianza que la mejora es real, no solo una señal débil dentro del ruido.

## 4d. Llevado a producción (`hibrido_instrumentado/`)

Los 4 ficheros modificados en `gpu-duhe4x-optimizado/` (`glibc_pow.cuf`, `d_uhex4_mod.cuf`, `der_wavefhe4_mod.cuf`, `derananum_mod.cuf` — confirmado con `diff` que son exactamente esos 4 y ningún otro) se copiaron a `v2-cuda-integracion/hibrido_instrumentado/`. Recompilado limpio, verificado de nuevo (semilla 11, 1.000 walkers, 59 bloques):

```
meV Energia total = -679.3359577544 +/- 2.01598823   (bit a bit igual a la referencia)
numero de walkers que tengo finales = 1000
sin errores, sin NaN
```

**`mypow` partida + `duhe4x`/`uhe4x` + fusión `wavefhe4`/`derwavefhe4` ya están en la copia de producción**, verificadas bit a bit tanto en las copias aisladas (4 escalas) como en producción (1 escala, misma semilla de referencia).

## 5. Siguiente paso (COMPLETADO)

Aplicar `mypow_log`/`mypow_desde_log` a los sitios reales:
1. ~~`duhe4x`/`uhe4x` (`d_uhex4_mod.cuf`)~~ — hecho, ver 4b.
2. ~~Fusionar `wavefhe4`+`derwavefhe4`~~ — hecho, ver 4c.
3. ~~Verificar bit a bit contra la energía real del pipeline completo~~ — hecho, ver 4d.
4. ~~Medir el impacto real en el pipeline completo~~ — hecho, ver 6 y 7.

## 6. Reperfilado post-optimización (`ncu`, 1.500 walkers, misma escala que Fase 0)

Con `mypow`/`duhe4x`/`uhe4x`/`wavef_derwavefhe4` ya en producción, se repitió el perfilado `ncu --set full` + `--page source` + suma por función (misma metodología de `fase0-perfilado.md`), para comparar contra la tabla original.

| Función | % post-`mypow_log` | % original (Fase 0) |
|---|---|---|
| `mypow_desde_log` | 13,666% | — |
| `myexp` | 11,195% | 9,835% |
| `wavef_derwavefhe4` (fusión) | 8,935% | 6,882%+2,241%=9,123% |
| `vp_hehe` | 8,705% | 7,683% |
| `he_dihydrogen` | 8,686% | 7,568% |
| `duhe4x` | 8,685% | 7,579% |
| `mypow` (aún vivo) | 8,492% | — |
| `v_hehe` | 5,343% | 4,719% |
| `real_of` | 4,576% | 4,694% |
| `mypow_log` | 4,073% | — |
| `bits_of` | 3,569% | 3,718% |
| `mycos` | 3,207% | 4,926% |
| `uhe4x` | 2,482% | 2,117% |
| `mysin` | 1,286% | 2,232% |
| `derwavefx` | 0,982% | 0,844% |
| `top12_of` | 0,974% | 0,842% |
| `derananum` | 0,807% | 0,685% |
| `angle` | 0,803% | 0,696% |
| `calderplegd` | 0,699% | 0,601% |
| `myacos` | 0,679% | 1,577% |
| `vec_norm` | 0,579% | 0,502% |
| `calplegd` | 0,548% | 0,463% |
| `wavefx` | 0,365% | 0,315% |
| `ccuerpo` | 0,179% | 0,154% |
| `k_derananum_t` | 0,166% | 0,120% |
| `scalar_product` | 0,123% | 0,118% |
| `k_vpot_t` | 0,073% | 0,060% |
| `wavefhe3` | 0,072% | 0,058% |
| `wavefm` | 0,026% | 0,019% |
| `potenbh` | 0,013% | 0,013% |
| `vpot` | 0,009% | 0,009% |

Total: 459.708 muestras, 31 funciones, suma de porcentajes = 100,000%. `mypow` ya no es una única entrada: se reparte en `mypow_desde_log` (13,666%) + `mypow` (8,492%, sitios sin migrar: `wavef_mod.cuf`, `der_wavefx_mod.cuf`, `He_dihydrogen.f`, `wavefhe4`/`derwavefhe4` de referencia sin usar) + `mypow_log` (4,073%). **Suma familia `mypow`: 26,231%, frente al 28,730% original** — mejora real pero modesta: el split evita *recalcular* `log(x)`, no elimina el coste del propio `log`/`pow`, que sigue siendo la operación más cara del kernel con diferencia.

## 7. Experimento `cambio-**`: sustituir `mypow` por `**` nativo

Pregunta: si en vez de solo evitar el recálculo de `log(x)` (mypow_log/mypow_desde_log, bit a bit idéntico a glibc) se sustituye **todo** el cálculo de potencia por el operador `**` nativo de nvfortran/CUDA (igual que se descartó en la sección 2, pero ahora aplicado sobre el pipeline YA optimizado con el split), ¿cuánto más rápido es y cuánto se paga en precisión?

### Cómo se hizo

Copia completa de `hibrido_instrumentado` (ya con `mypow_log`/`mypow_desde_log`/fusión `wavef_derwavefhe4` de producción) en `cambio-**/hibrido_instrumentado/`. Cambio **mínimo y único**: en `glibc_pow.cuf`, las 3 rutinas (`mypow`, `mypow_log`, `mypow_desde_log`) se reescriben para usar `**` nativo, sin tocar ningún sitio de llamada:

```fortran
attributes(host, device) function mypow(x, y) result(r)
  real(kind=r8), intent (in) :: x, y
  real(kind=r8) :: r
    r = x**y
end function mypow

attributes(host, device) subroutine mypow_log(x, hi, lo)
  real(kind=r8), intent (in) :: x
  real(kind=r8), intent (out) :: hi, lo
    hi = x      ! passthrough: ya no es log(x), es x tal cual
    lo = 0.0_r8
end subroutine mypow_log

attributes(host, device) function mypow_desde_log(hi, lo, y) result(r)
  real(kind=r8), intent (in) :: hi, lo, y
  real(kind=r8) :: r
    r = hi**y   ! hi es x (por el passthrough de arriba)
end function mypow_desde_log
```

Así, tanto los sitios que llaman a `mypow` directamente (`He_dihydrogen.f`, `wavef_mod.cuf`, `der_wavefx_mod.cuf`, `derananum_mod.cuf`, `wavefhe4`/`derwavefhe4` sin usar) como los que usan el split (`duhe4x`/`uhe4x`, `wavef_derwavefhe4`) acaban calculando `x**y` nativo, sin tener que tocar ni un sitio de llamada. Compilado limpio (mismos warnings preexistentes, sin errores nuevos).

### Comparación de 3 vías (semilla 11 y semilla 23, 1.000 walkers, 1 bloque equilibrio + 59 cálculo × 20 pasos)

| Semilla | Vía | `meV Energia total` | `energia final configuraciones` | Wall time |
|---|---|---|---|---|
| 11 | CPU `gfortran` (op4) | -678,1071206844 | -615,5737694990 | 84,749 s |
| 11 | GPU `mypow_log` (producción) | -679,3359577544 | -615,5737694990 | 47,427 s |
| 11 | GPU `**` nativo (`cambio-**`) | -679,3359577544 | -615,5737694990 | 46,640 s |
| 23 | CPU `gfortran` (op4) | -677,9802816985 | -615,5737694990 | 83,100 s |
| 23 | GPU `mypow_log` (producción) | -675,8974261137 | -615,5737694990 | 47,396 s |
| 23 | GPU `**` nativo (`cambio-**`) | -675,8974261137 | -615,5737694990 | 46,185 s |

**Hallazgos:**

- **`energia final de las configuraciones` es idéntica en las 6 corridas** (-615,5737694990) — esta línea es determinista (depende solo de `conf.20.00.HH` de entrada, no del muestreo aleatorio), así que no es una comparación útil de precisión, solo confirma que las 6 corridas arrancan del mismo punto.
- **CPU vs GPU difiere** (esperado y ya conocido de sesiones anteriores: la GPU usa su propio flujo de semillas, no es la misma secuencia de números aleatorios que `gfortran` — la comparación válida es "dentro del margen de error estadístico", no bit a bit).
- **GPU `mypow_log` vs GPU `**` nativo son bit a bit IDÉNTICOS, en ambas semillas (11 y 23)**, a pesar de que la prueba aislada de la sección 2 (`prueba_mypow/verificacion_valores`) ya demostró que `**` nativo diverge de la versión bit-exacta en 16 de 60 pares `(rij,nu)` (26,7%) para exactamente esos mismos exponentes (`phe4(2)`, `pxhe4(2,il)`, `pxhe4(4,il)`). Es decir: la divergencia de 1 ULP existe (verificada por separado, con matemáticas, no en duda), pero en estas 2 trayectorias concretas de 1.000 walkers × 59 bloques × 20 pasos no llegó a cambiar ninguna decisión de aceptación/rechazo del DMC de forma que se notase en el resultado final. **Esto no es prueba de que sea seguro en general** — solo de que, para estas 2 semillas y esta escala, no se manifestó. Con más semillas, más pasos, u otra configuración física podría manifestarse.
- **La ganancia de velocidad de ir más allá de `mypow_log` hasta `**` nativo es pequeña**: 46,640s vs 47,427s (semilla 11, −1,66%) y 46,185s vs 47,396s (semilla 23, −2,56%). Comparado con la ganancia YA conseguida por el split bit-exacto (3,86%-6,74% frente al original sin optimizar, sección 4c), quedan solo 1,7-2,6 puntos adicionales sobre la mesa, y a cambio de una divergencia de precisión conocida y no acotada estadísticamente en este experimento.

### Conclusión

El coste de `mypow`/`log`/`pow` no está en el *recálculo redundante* (eso ya se corrigió con el split, sección 6) sino en la propia operación matemática — sustituirla por `**` nativo la abarata solo marginalmente (~2%) porque nvfortran probablemente ya usa una implementación de hardware/biblioteca razonablemente eficiente para `**`, y la parte cara real (la propia `pow_exp_inline`/`log_inline`, o su equivalente nativo) sigue estando ahí. Dado el margen tan pequeño frente al riesgo de precisión ya cuantificado (26,7% de divergencia de 1 ULP en el dominio real de uso), **`mypow_log`/`mypow_desde_log` (bit a bit idéntico a `gfortran`) sigue siendo la opción recomendada para producción**; `cambio-**` queda documentado como experimento descartado, no se lleva a `hibrido_instrumentado`.

### Ficheros

- `cambio-**/hibrido_instrumentado/`: copia completa con el cambio de `glibc_pow.cuf` descrito arriba.
- `cambio-**/compilar_cambio_pow.sh`: script de compilación (misma lista de ficheros que `compilar_pipeline.sh`).
- `cambio-**/comparar_3vias.sh`, `cambio-**/comparar_3vias_seed23.sh`: scripts de la comparación de 3 vías, semillas 11 y 23.
- `cambio-**/resultados_3vias/`: logs completos + `tiempos_opcion7.dat` de las 6 corridas + `wall_times.log`/`wall_times_seed23.log`.
- `ncu_post_optimizacion.ncu-rep`, `ncu_post_optimizacion_source.csv`, `ncu_post_optimizacion_stdout.log`: perfil `ncu` post-optimización de la sección 6.

## 8. `mypow_log` en TODOS los sitios de llamada (no solo `duhe4x`/`wavef_derwavefhe4`)

Motivación del usuario: la sección 7 mostró un margen de mejora pequeño (~2%) al pasar de `mypow_log` a `**` nativo, y la pregunta directa fue: ¿es ese margen pequeño porque `mypow_log` de verdad no da para más, o porque solo estaba aplicado en 2 de los muchos sitios que llaman a `mypow`? Se hizo el mapeo completo de TODOS los sitios `mypow` restantes:

| Fichero | Método | ¿Se ejecuta en esta simulación? | Motivo |
|---|---|---|---|
| `d_uhex4_mod.cuf` | `duhe3x`/`uhe3x` | **No** | bucle `il=0,lxhe3`/análogo con `nhe3=0` — código gemelo de `duhe4x`/`uhe4x` pero para la especie He3, nunca invocado |
| `wavef_mod.cuf` | `wavefm`, `wavefhe3` | **No** | bucles `jatom=nhe4+1,ngatom` / `iatom=nhe4+1,ngatom-1`, 0 iteraciones con `nhe3=0` |
| `derananum_mod.cuf` | `derwavefm` | **No** | bucle `jhe3=1,nhe3`, 0 iteraciones |
| `He_dihydrogen.f` | `He_dihydrogen` | **Sí — 8,686% del perfil** | el único sitio vivo fuera de `duhe4x`/`uhe4x`/`wavef_derwavefhe4`, y con mucha redundancia sin explotar (ver 8.1) |

Confirmado con `grep` (`gtest\s*=\s*\.true\.` no aparece en ningún sitio del árbol): `He_dihydrogen` se llama **siempre con `GTEST=.false.`** (única llamada real, en `potenbh`, `mpotenbh_mod.cuf:51`) — la rama que calcula fuerzas (`dExdx...dEzdz`, acumulación en `V`) nunca se ejecuta en esta simulación. Esto no invalida la fusión (ver 8.1), pero acota su beneficio real a la parte SIN `GTEST`.

### 8.1. `He_dihydrogen.f`: fusión de los bloques de dispersión e inducción + `mypow_log`

`He_dihydrogen` tenía DOS bucles `DO ...=1,N` separados (dispersión/`ENERGY2` y inducción/`ENERGY3`) que recorrían el mismo rango de átomos y calculaban, cada uno por su cuenta, el mismo `rvec/rnorm/onorm/theta` (misma fórmula, mismo `X`, mismo `orHH`) y el mismo `btheta` (`b0+b1*mypow(...)+b2*mypow(...)+b3*mypow(...)`, exponentes 2/4/6). Además, dentro del propio bloque de dispersión, `atheta` y `btheta` usaban los mismos exponentes (2,4,6) sobre la misma base `abs(mycos(theta))`, con llamadas a `mypow` independientes cada vez.

**Cambio aplicado** (aislado en `gpu-he_dihydrogen-optimizado/`, copia completa de `hibrido_instrumentado`):
1. Los dos `DO` se fusionan en uno solo (`DO J1=1,N`): el cuerpo de dispersión se mantiene igual, y el de inducción, justo después dentro de la misma iteración, reutiliza `rvec/rnorm/onorm/theta/btheta/dbtheta` ya calculados en vez de recalcularlos.
2. `mypow_log`/`mypow_desde_log` para `abs(mycos(theta))`, `abs(mysin(theta))` y `rnorm`: el logaritmo se calcula una vez por átomo y se reutiliza entre `atheta`/`btheta` (mismos exponentes 2,4,6) y, en la rama `GTEST`, entre `datheta`/`dbtheta` (exponentes 3,5) y `eterm2`/`dvdR`/`dvdtheta` (exponente 6, usado hasta 4 veces).

**Por qué es seguro bit a bit**: `ENERGY2` se rellena por asignación en `e2terms(:)` (no por suma acumulada), así que el orden de cálculo no le afecta; `ENERGY3` y `V(:)` se acumulan en el mismo orden de átomos `1..N` que antes, y ningún otro átomo toca el mismo elemento de `V` entre medias — fusionar el bucle no reordena ninguna suma en coma flotante.

**Verificación**:
- Prueba unitaria aislada (programa standalone, `He_dihydrogen` compilado por separado con la versión vieja y la nueva, 20 átomos sintéticos, mismas posiciones en las dos corridas): `ENERGY1/ENERGY2/ENERGY3/V(:)` **idénticos byte a byte**, tanto con `GTEST=.false.` (el caso real) como con `GTEST=.true.` (defensivo, por si algún día se activa).
- Pipeline completo, semilla 11, 4 escalas de walkers — energía **bit a bit idéntica** a producción en las 4:

| Walkers | Energía (idéntica ref./opt.) | Referencia | Optimizado | Mejora |
|---|---|---|---|---|
| 500 | -683,4776947558 | 34,17 s | 30,54 s | **−10,6%** |
| 1.000 | -679,3359577544 | 47,43 s | 46,29 s | **−2,4%** |
| 2.000 | -676,2974256246 | 70,77 s | 70,56 s | −0,3% (dentro del ruido) |
| 3.000 | -678,0618871962 | 109,57 s | 100,28 s | **−8,5%** |

3 de las 4 escalas muestran mejora clara por encima del ruido de corrida a corrida (0,5%-2,7%, ya establecido en esta sesión); la de 2.000w queda dentro del ruido.

### 8.2. Caminos muertos (`duhe3x`/`uhe3x`, `wavefm`, `wavefhe3`, `derwavefm`)

Se aplicó `mypow_log`/`mypow_desde_log` igualmente, por consistencia y por si `nhe3` dejase de ser 0 en el futuro — pero al no ejecutarse ninguna iteración de sus bucles en esta simulación, el cambio no tiene impacto medible en el tiempo de corrida (verificado: la energía sigue bit a bit idéntica tras aplicarlo). `wavefhe4`/`derwavefhe4` (`der_wavefhe4_mod.cuf`) se dejan **intencionadamente** sin tocar: son la referencia sin optimizar usada para verificar `wavef_derwavefhe4` bit a bit, y solo se llaman desde los kernels de prueba `k_wavefhe4`/`k_derwavefhe4` (no desde el camino real).

### 8.3. Llevado a producción (`hibrido_instrumentado/`)

Los 4 ficheros modificados (`He_dihydrogen.f`, `der_wavefx_mod.cuf`, `wavef_mod.cuf`, `derananum_mod.cuf` — confirmado con `diff` que son exactamente esos 4 y ningún otro) se copiaron a `v2-cuda-integracion/hibrido_instrumentado/`. Recompilado limpio, verificado de nuevo (semilla 11, 1.000 walkers, 59 bloques):

```
meV Energia total = -679.3359577544 +/- 2.01598823   (bit a bit igual a la referencia)
numero de walkers que tengo finales = 1000
sin errores, sin NaN
```

**La fusión de `He_dihydrogen` (dispersión+inducción) y `mypow_log` en todos los sitios restantes ya están en la copia de producción**, verificadas bit a bit tanto en la copia aislada (unitaria + 4 escalas) como en producción.

### Ficheros

- `gpu-he_dihydrogen-optimizado/`: copia completa de `hibrido_instrumentado` con la fusión de `He_dihydrogen.f` + `mypow_log` en todos los sitios restantes.
- `compilar_he_dihydrogen_optimizado.sh`: script de compilación.
- `comparar_he_dihydrogen_varios_walkers.sh`: script de la comparación de 4 escalas.
- `resultados_he_dihydrogen/`: logs completos + `tiempos_opcion7.dat` de las 8 corridas (4 escalas × referencia/optimizado) + `verificacion_produccion_1000w.log` (verificación final en producción).

## Ficheros

- `prueba_split_mypow/glibc_pow.cuf`: `mypow` original + `mypow_log`/`mypow_desde_log` nuevas.
- `prueba_split_mypow/test_split_mypow.cuf`: verificación bit a bit + medición de tiempo.

## Nota de limpieza (recorte de copias completas)

`cambio-**/hibrido_instrumentado/`, `gpu-duhe4x-optimizado/` y
`gpu-he_dihydrogen-optimizado/` estaban como copias completas de
`hibrido_instrumentado` -- **recortadas** a los ficheros realmente
editados en cada una (confirmados arriba con `diff` en su momento) +
`in.mcv` + `tiempos_opcion7.dat`. Ya no son compilables por sí solas.
`ncu_post_optimizacion.ncu-rep`/`_source.csv` (26M, perfiles crudos
regenerables) eliminados.
