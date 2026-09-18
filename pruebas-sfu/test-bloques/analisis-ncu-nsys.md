# test-bloques: análisis `nsys`/`ncu` -- escalado y una anomalía real

## 1. Objetivo

Walkers=1000, pasos por bloque=100 fijos; bloques de cálculo = 50, 100, 200, 300, 500. Mismo perfilado que `test-walkers` (`nsys --cuda-graph-trace=node` + `ncu` con ciclos/instrucciones/stall/ocupación) para ver qué cambia al escalar por número de bloques en vez de por walkers.

## 2. Por kernel: idéntico en las 5 escalas (esperado, y confirma que el diseño es correcto)

`ncu` (media de 2-3 lanzamientos por escala):

| Kernel | Registros | Ocupación | Ciclos | Instr. totales | FMA | XU | Stall |
|---|---|---|---|---|---|---|---|
| `k_vpot_3warp_t` | 94 | 8,8% | ~1.602.000 | 3.298.435 | 326.574 | 26.496 | MIO 64,0% |
| `k_derananum_he4_t` | 90 | 2,8% | ~1.293.000 | 1.978.163 | 289.629 | 30.400 | MIO 73,5% |
| `k_derananum_resto_t` | 111 | 2,8% | ~1.205.000 | 1.955.444 | 242.301 | 15.584 | MIO 69,0% |
| `k_fase_h` | 94 | 2,9% | ~263.300 | 401.682 | 53.757 | 8.704 | MIO 72,4% |

**Estos números son, dentro del margen de medición, exactamente los mismos en las 5 escalas de `test-bloques`** -- y coinciden exactamente con la fila de 1000w de `test-walkers/analisis-ncu-nsys.md` (mismo walkers=1000, es la misma condición física). Tiene sentido: `bloques` controla **cuántas veces** se repite cada kernel (más pasos DMC totales), no **cuánto cuesta cada lanzamiento individual** -- el coste por lanzamiento depende solo de los walkers y la física, no de cuántos bloques queden por delante. Es una buena confirmación de que el diseño del pipeline (grafo CUDA fijo, relanzado igual en cada paso) se comporta como se espera: escalar por bloques es "más de lo mismo", sin ningún efecto de segundo orden a nivel de kernel.

## 3. Tiempo total: lineal en 4 de 5 puntos, un outlier real en 300 bloques

| Bloques | Pasos DMC totales | GPU (wall) | Coste/bloque | Desviación del ajuste lineal (50-200b) |
|---|---|---|---|---|
| 50 | 5.000 | 27,96 s | 0,559 s/bloque | -- |
| 100 | 10.000 | 52,28 s | 0,523 s/bloque | -- |
| 200 | 20.000 | 102,79 s | 0,514 s/bloque | -- |
| **300** | 30.000 | **331,72 s** | **1,106 s/bloque** | **+115% sobre lo esperado (~154 s)** |
| 500 | 50.000 | 259,25 s | 0,519 s/bloque | vuelve a la tendencia (~257 s esperados) |

Ajustando la tendencia lineal con los 3 primeros puntos (50-200b, muy consistente entre sí, ~0,51-0,56 s/bloque) y extrapolando: 300 bloques debería tardar ~154 s, y 500 bloques ~257 s. **300b tardó 331,72 s -- más del doble de lo esperado.** 500b, en cambio, tardó 259,25 s -- prácticamente exacto a la extrapolación lineal, como si el punto de 300b fuera el único fuera de tendencia, no un cambio de régimen sostenido.

**No es un artefacto de esta sesión de perfilado**: comprobado el orden temporal real de la batería (`progreso_bloques.log`), la corrida GPU de 300 bloques (14:09:52-14:15:23) se ejecutó **antes** de que se lanzara ningún perfilado `ncu`/`nsys` de esta sesión -- no hay solapamiento posible con otro proceso de GPU conocido.

**Mismo patrón que la anomalía de 2500w en `test-walkers`** (ver ese `analisis-ncu-nsys.md` §4): un punto aislado, sin relación aparente con el tamaño del problema (300b no es ni el más grande ni un cruce obvio de límite de recursos, a diferencia de la cuantización de oleadas sospechada en 2500w), que se sale claramente de una tendencia por lo demás muy limpia. Encaja con la deriva térmica sostenida que `v4-cuda-pruebas/README.md` (Prueba 3) ya dejó como sospecha sin confirmar. **Tampoco se confirma aquí** -- no se monitorizó temperatura/reloj de la GPU durante la corrida (para no añadir otro proceso compitiendo por recursos durante la medición).

## 4. Conclusión

- A nivel de kernel, escalar por bloques es puro "más de lo mismo" -- ninguna optimización de código nueva que atacar, coherente con que el coste por lanzamiento no cambia.
- El tiempo total escala linealmente con los bloques **excepto en un punto** (300b, +115% sobre lo esperado) que no se explica por el propio código ni por contención con este perfilado -- segunda vez en esta batería (tras 2500w en `test-walkers`) que aparece una desviación grande y puntual, ninguna de las dos con causa confirmada.
- **Recomendación para la corrida final del TFG** (~34-40h, mucho más larga que cualquiera de estas): dado que ya van dos anomalías de este tipo en corridas de minutos, vale la pena monitorizar temperatura/reloj de la GPU en paralelo durante esa corrida (con `nvidia-smi --query-gpu=temperature.gpu,clocks.sm,clocks.max.sm --format=csv -l 60` a un fichero, coste mínimo de recursos) para poder confirmar o descartar la hipótesis de deriva térmica de una vez, en vez de seguir acumulando anomalías sin diagnosticar.

## Ficheros

- `nsys_${b}b.nsys-rep` en cada subcarpeta `test-${b}b/`.
- Perfiles `ncu` no persistidos (quedaron en `/tmp`, reproducibles con los `in.mcv-gpu`/binarios ya guardados en cada subcarpeta).
