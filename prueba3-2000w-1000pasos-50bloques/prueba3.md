# Prueba 3: 2000 walkers, 50 bloques, 1000 pasos/bloque

## Objetivo

Continúa la escalada gradual de la Prueba 1 (`v4-cuda-pruebas/prueba1-2000w-500pasos-bloque/`, 20 bloques × 500 pasos = 10.000 pasos totales) hacia la configuración real de producción (2000 walkers, 1 + 100 bloques, 10.000-100.000 pasos/bloque). La Prueba 2 (barrido de hilos/bloque) fue un eje distinto y quedó descartada (empeoraba el tiempo real) -- esta prueba sigue con `threads=32`, la configuración ya confirmada y en producción.

Dos ejes subidos a la vez respecto a la Prueba 1:
- **Bloques**: 20 -> 50 (hacia los 101 del objetivo real) -- más eventos de repoblación/ramificación del DMC acumulados, el tipo de cosa que solo se manifiesta en corridas largas.
- **Pasos/bloque**: 500 -> 1000 -- sigue confirmando si la mejora de ritmo por paso vista en la Prueba 1 (+10,2% al subir de 20 a 500 pasos/bloque) se mantiene o se estanca.

## Configuración

| Parámetro | Valor |
|---|---|
| Walkers | 2000 |
| Bloques equilibrio | 1 |
| Bloques cálculo | 49 |
| Pasos por bloque | 1000 |
| **Pasos totales** | **50.000** (50 bloques × 1000 pasos) |
| Semilla | 11 |
| Binario | `v2-cuda-integracion/hibrido_instrumentado/qmccluster_pipeline` (producción, `GTEST` fijo + (a) + `nhe3` fijo, `threads=32`) |

## Qué se espera

Con el ritmo medido en la Prueba 1 (0,045956 s/paso), la estimación lineal es:

50.000 pasos × 0,045956 s/paso ≈ **2.298 s ≈ 38,3 minutos**

Si el ritmo real mejora más (como pasó de la escala rápida a la Prueba 1), debería tardar algo menos. Si empeora (por ejemplo, por deriva térmica sostenida en una corrida mucho más larga, o por algún coste que crezca con el número de bloques), sería una señal de alerta antes de comprometerse a la configuración real de días.

## Resultado

**Tiempo real: 2.432,16 s (40,5 min)** -- un 5,8% más lento que la estimación lineal (38,3 min), no menos como en la Prueba 1. Sin errores ni `NaN`. Población final = 2.000 = población inicial.

```
meV Energia total = -629.4970268735 +/- 1.09983052
numero de walkers que tengo finales = 2000
```

### Ritmo real: empeora, no mejora -- contrario a la tendencia vista hasta ahora

| Prueba | Pasos/bloque | Pasos totales | Ritmo (s/paso) |
|---|---|---|---|
| Rápidas (referencia original) | 20 | 1.200 | 0,05115 |
| Prueba 1 | 500 | 10.000 | 0,04596 (**-10,2%** vs rápidas) |
| **Prueba 3** | **1.000** | **50.000** | **0,04864 (+5,8% vs Prueba 1)** |

La tendencia "más pasos/bloque = mejor ritmo" que se cumplió al pasar de 20 a 500 pasos/bloque **se rompe** al pasar a 1.000. `tiempos_opcion7.dat` también lo refleja: `CONVERSION AoS<->SoA` sube del 10,341% (Prueba 1) al **13,306%** del total -- si el empaquetado escalase solo con el número de bloques (menos bloques en proporción a los pasos totales aquí, ya que 50 bloques con 1000 pasos cada uno vs 20 bloques con 500), debería haber bajado su peso relativo, no subido.

**Hipótesis más probable (no confirmada -- no se monitorizó la temperatura de la GPU durante la corrida)**: deriva térmica sostenida. Esta corrida duró 40,5 minutos seguidos de carga continua de GPU, frente a los 8,5 minutos de la Prueba 1 -- y ya hemos visto varias veces hoy (sección de `myexp-optimizacion`) que la GPU de este portátil se ralentiza de forma medible tras solo unos minutos de uso intensivo. Es plausible que la segunda mitad de esta corrida fuera más lenta que la primera, arrastrando la media hacia abajo -- pero no hay datos para confirmarlo con certeza.

**Lección para las próximas pruebas largas**: monitorizar `nvidia-smi` (temperatura/reloj) en paralelo durante toda la corrida, no solo antes de empezar, para poder confirmar o descartar la deriva térmica como causa en vez de asumirla.

## Ficheros

- `salida.log`: salida completa de la corrida.
- `tiempos_opcion7.dat`: reparto de tiempos por fase, copiado tras la corrida.
