# Prueba: portar denssumapaso a GPU

## El problema

`denssumapaso` (15 histogramas de distancias/ángulos, ~310 incrementos/walker con los parámetros reales de este proyecto) resultó ser el 13,8%-20,0% del tiempo de `opcion=7` (ver `fase3-arquitecturas-alternativas.md`, punto 2) — crece con la escala, a diferencia de otros candidatos ya descartados.

A diferencia de `derananum`/`vpot` (cada walker escribe solo lo suyo) o de las pruebas de parejas de la Fase 1 (cada walker necesita un array privado que reducir), aquí **muchos walkers incrementan el MISMO histograma compartido** — un patrón nuevo, no probado hasta ahora.

## Prueba 1: réplica aislada (`test_histograma.cuf`)

Réplica del bucle más caro de `denssumapaso` (`drb44`, parejas He4-He4: `C(20,2)=190` incrementos/walker), con los parámetros reales (nhr=2000, rmax=20.0). GPU: 1 hilo = 1 walker (el patrón ya conocido que funciona), cada hilo hace sus 190 parejas y usa `atomicadd` directo sobre el histograma de device — sin array privado, sin reducción.

| Walkers | CPU/paso | GPU/paso | Aceleración |
|---|---|---|---|
| 250 | 1,06 ms | 0,145 ms | 7,3x |
| 500 | 2,14 ms | 0,145 ms | 14,8x |
| 1.000 | 4,30 ms | 0,157 ms | 27,4x |
| 2.000 | 8,67 ms | 0,192 ms | 45,1x |
| 3.000 | 13,14 ms | 0,235 ms | 55,9x |

Bit a bit idéntico en las 5 escalas (los incrementos son siempre `+1.0`, exacto en coma flotante). Y la ventaja **crece** con la escala: la CPU es lineal en walkers, la GPU casi no lo nota.

## El problema de fondo: el reparto de población

Para que el resultado sea correcto, `denssumapaso` tiene que ver la población **después** del reparto (quién murió, quién se clonó) — pero en el pipeline, ese reparto pasa en la CPU, **después** de traer las posiciones de vuelta del device (ver `msteps.f90:486-517`). Portar el kernel tal cual habría exigido: traer posiciones → repartir en CPU → subirlas OTRA VEZ a la GPU solo para el histograma. Un viaje de ida y vuelta extra, cada paso.

## La solución: pesar por `nsons` en vez de repartir

Cuando un walker se clona, sus copias son posiciones **idénticas** al padre en ese instante (el reparto solo duplica, no mueve nada más). Así que:

```
sumar 1 vez por cada una de las nsons(i) copias, DESPUÉS del reparto
   ==
sumar nsons(i) veces, sobre el walker ANTES del reparto
```

Y `k_fase_g` (la última fase del pipeline, dentro del mismo grafo CUDA) ya calcula `nsons_p` usando las posiciones finales (`atom_p`) — ambos, listos en el device, antes de cualquier copia a host. Un walker con `nsons=0` (muere) aporta 0 automáticamente, sin ningún caso especial. Esto permitiría una fase nueva (`k_fase_h`) al final del mismo grafo, sin reparto en GPU y sin ninguna copia H2D extra de posiciones.

## Verificación (antes de tocar el pipeline real)

Siguiendo el criterio de este proyecto (comparar contra la rutina real, no contra otra pieza de prueba — ver `MEMORY.md`, "verificar contra el original"): `driver_verifica_prereparto.f90` llama a la **`denssumapaso` real** (`mdensidades.f90`, sin tocar salvo 3 getters de solo lectura añadidos para poder leer sus acumuladores) sobre una población post-reparto construida con la misma lógica que `msteps.f90`, y lo compara contra la propuesta (pre-reparto, pesada por `nsons`) sobre 500 walkers sintéticos con `nsons` cíclico 0-4 (cubre muertes y clones).

**Resultado:**
- Los histogramas de conteo simple (`drb44`, `drb33`, `drb43`, `drbi4`, `drbi3`, `drbia` — 190 de los ~310 incrementos/walker, el grueso del coste): **bit a bit idénticos**.
- Los histogramas angulares (`d2bhe4`, `d2bhe`, `d2ybhe4`, `d2ybhe`, que pesan por `1/sin(θ)`, no por `+1.0`): difieren en ~1e-14 relativo (ejemplo real: `258.78499553350923` vs `258.78499553350929`). Confirmado con una prueba adicional (sumar secuencialmente en vez de multiplicar por el peso: reduce las diferencias de 921 a 448 bins de 7260, pero no las elimina) que el origen es el **orden** de acumulación entre walkers distintos, no la operación en sí — reproducirlo exigiría reconstruir el reparto en la GPU, anulando la ventaja de saltárselo.

**Conclusión:** la fusión es matemáticamente correcta. El histograma que más pesa es exacto; los angulares tienen ruido de redondeo (~1e-14) muy por debajo del error estadístico propio de cualquier simulación DMC (~1e-3/1e-4) — no bit a bit, pero sí correcto para el propósito.

## Nota: `leedatos` fuera del lanzador real

Para escribir `driver_verifica_prereparto.f90` se intentó inicializar los parámetros reales (`natom`, `nhe4`, etc.) con `leedatos` (como hace `qmccluster.f90`) — pero `leedatos` depende de que `iniciaparalelo`/`quiensoy` (`mserie.f90`) se hayan llamado antes, y fuera del lanzador real deja `natom`/`ngatom` en 0 **en silencio** (sin error, sin mensaje) hasta que `denssumapaso` accede a un array con índice corrupto y crashea mucho más tarde. Como `denssumapaso` no depende de CÓMO se fijan esas variables, solo de sus valores, se fijaron a mano (`nhe4=20, nhe3=0, impurmol=true`, los valores reales confirmados en toda esta investigación) — evita la dependencia sin afectar a lo que se quería verificar.

## Ficheros

- `test_histograma.cuf`: réplica aislada, prueba de rendimiento (5 escalas, bit a bit exacto).
- `mdensidades.f90` (en `hibrido_instrumentado/`): 3 getters nuevos de solo lectura (`densgetblo_r`/`_c`/`_y`), `denssumapaso` sin tocar.
- `driver_verifica_prereparto.f90` (en `hibrido_instrumentado/`), `compilar_verifica_prereparto.sh` (en `test-tiempos/`): verificación de la propuesta pre-reparto contra `denssumapaso` real.

## Implementación real

`k_fase_h` (`dmc2_pipeline.cuf`): 8ª fase del mismo grafo CUDA, justo después de `k_fase_g` — usa `atom_p`/`sprop_p`/`nsons_p` ya finales, sin reparto ni copia H2D extra. Réplica línea a línea de la geometría de `denssumapaso` (mismas fórmulas, mismos índices), pesando cada incremento por `nsons(i)` (un walker con `nsons=0` no entra, sin caso especial). Histogramas de device **persistentes**, reseteados una vez por bloque (`resetea_histogramas_gpu`), no por paso — como `drb44` etc. en `mdensidades.f90`.

`vuelca_histogramas_gpu`: copia D2H **una vez por bloque** (no una vez por paso — ahí está la ganancia) e inyecta el resultado en los acumuladores reales de `mdensidades.f90` vía 3 setters nuevos (`densputblo_r/_c/_y`, mismo patrón que los getters de verificación). `denssumablo`/`denssumafin` siguen funcionando exactamente igual, sin saber de dónde vino el dato.

`mmontecarlo.f90` (`dmc_gpu_pipeline`, `opcion=7`): ya no llama a `denssumapaso` paso a paso — solo lleva la cuenta de `denb` (walkers procesados) en el host, trivial. `denssumapaso`, `mdensidades.f90`, y las vías `opcion=4/5/6` no se tocan.

### Medición en producción

`qmccluster_pipeline`, 250 walkers, mismo `in.mcv` (semilla 11, 5 bloques de cálculo):

| | Antes | Después |
|---|---|---|
| `denssumapaso` (bloque de tiempos) | 0,382 s (10,6% del total) | 0,004 s (0,08%) |

Sin errores, sin NaN, 250 walkers finales (sin colapso de población). Los histogramas de conteo dan sus totales exactos esperados por walker: `dhe4he4` suma 190,0 (=C(20,2), pares He4-He4), `dihe4`/`dihe` suman 20,0 (=nhe4, pares con la impureza) — confirmación adicional e independiente (aritmética exacta sobre datos físicos reales, no sintéticos) de que el pesado por `nsons` es correcto.

## Ficheros (actualizado)

- `test_histograma.cuf`: réplica aislada, prueba de rendimiento (5 escalas, bit a bit exacto).
- `mdensidades.f90` (en `hibrido_instrumentado/`): 3 getters + 3 setters de solo lectura/escritura (`densgetblo_r/_c/_y`, `densputblo_r/_c/_y`, `densputdenb`), `denssumapaso` sin tocar.
- `driver_verifica_prereparto.f90` (en `hibrido_instrumentado/`), `compilar_verifica_prereparto.sh` (en `test-tiempos/`): verificación de la propuesta pre-reparto contra `denssumapaso` real.
- `dmc2_pipeline.cuf` (en `hibrido_instrumentado/`): `k_fase_h`, histogramas de device persistentes, `resetea_histogramas_gpu`, `vuelca_histogramas_gpu`.
- `mmontecarlo.f90` (en `hibrido_instrumentado/`): `dmc_gpu_pipeline` ya no llama a `denssumapaso` paso a paso.
