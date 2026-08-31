# Prueba 1: 2000 walkers, 20 bloques, 500 pasos/bloque

## Objetivo

Primer paso de la escalada gradual hacia la configuración real de producción (2000 walkers, 1 bloque equilibrio + 100 bloques cálculo, 10.000-100.000 pasos/bloque -- extrapolación estimada entre ~14 horas y ~6 días con el pipeline optimizado de hoy). En vez de saltar directamente ahí, esta prueba usa **el mismo número de walkers** que el objetivo real, y **el extremo bajo del rango de pasos/bloque (10.000)**, pero repartido en muchos menos bloques (20 en vez de 101) -- para tener una corrida de duración manejable (minutos, no horas) que ya se parezca en estructura a la real (muchos pasos seguidos dentro del mismo bloque, no los 20 pasos/bloque de las pruebas rápidas de `v3-cuda-optimización/`).

## Configuración

| Parámetro | Valor |
|---|---|
| Walkers | 2000 |
| Bloques equilibrio | 1 |
| Bloques cálculo | 19 |
| Pasos por bloque | 500 |
| **Pasos totales** | **10.000** (20 bloques × 500 pasos) |
| Semilla | 11 |
| Binario | `v2-cuda-integracion/hibrido_instrumentado/qmccluster_pipeline` (producción, ya con `GTEST` fijo + (a) + `nhe3` fijo) |

## Qué se espera

Con el ritmo medido en las pruebas cortas de hoy (0,05115 s/paso a 2000 walkers, medido con 1.200 pasos totales), la estimación lineal es:

10.000 pasos × 0,05115 s/paso ≈ **511,5 s ≈ 8,5 minutos**

Si el tiempo real se aleja mucho de esta estimación (por ejemplo, si escala peor de lo lineal, o si hay algún coste fijo por bloque que aquí pesa más al tener 20 bloques en vez de 60), sería una señal de que la extrapolación a la configuración real de producción (horas/días) no es tan fiable como parece con datos de corridas cortas.

## Resultado

**Tiempo real: 460,11 s (7,67 min)** -- un 10% más rápido que la estimación lineal (511,5 s). Sin errores ni `NaN` (solo el aviso estándar `ieee_inexact` que aparece en todas las corridas de esta sesión). Población final = 2.000 walkers = población inicial (sin colapso).

```
meV Energia total = -638.5565112476 +/- 3.69856783
numero de walkers que tengo finales = 2000
```

(La energía no es comparable bit a bit contra las pruebas cortas de hoy -- es una corrida genuinamente distinta, con 20 bloques de 500 pasos en vez de 60 bloques de 20, mucha más equilibración y estadística real, así que un valor de energía distinto es lo esperado, no un error.)

### Ritmo real medido vs. el usado para la estimación

| Configuración | Pasos/bloque | Ritmo (s/paso) |
|---|---|---|
| Pruebas rápidas de hoy (referencia usada para la estimación) | 20 | 0,05115 |
| Esta prueba | 500 | **0,04596** |

**Un 10,2% más rápido por paso con bloques más largos.** Confirma la sospecha que se apuntó al hacer la estimación: parte del coste fijo (empaquetado/estadísticas/E-S) se reparte por bloque, no por paso, así que se diluye más cuanto más largos son los bloques. Con `tiempos_opcion7.dat`: `lanza_pipeline` sigue siendo el ~86% dominante (86,249%, coherente con las escalas pequeñas), `CONVERSION AoS<->SoA` un 10,341% del total (similar proporción a antes).

### Consecuencia para la estimación de la configuración real

La estimación de 14,4-143,5 horas hecha con el ritmo de 20 pasos/bloque era, si acaso, **ligeramente pesimista** -- con bloques de 10.000-100.000 pasos (mucho más largos que los 500 de esta prueba), el ritmo real debería seguir mejorando un poco más, no empeorar. No se recalcula todavía con precisión (haría falta una prueba con pasos/bloque más cercanos al objetivo real para confirmarlo), pero la dirección del error va a favor: la corrida real probablemente tarde algo menos que la estimación original, no más.

## Perfilado con `ncu`: ocupación, registros, bloques

Corrida corta y aparte (1 bloque equilibrio + 1 bloque cálculo, 2 pasos, mismos 2000 walkers) solo para capturar el perfil -- `ncu --set full` ralentiza mucho la ejecución, no se usa sobre la corrida completa de 10.000 pasos.

| Métrica | `k_derananum_t` | `k_vpot_t` |
|---|---|---|
| Registros/hilo | 126 | 106 |
| Grid Size (bloques) | 125 | 125 |
| Hilos totales | 4.000 | 4.000 |
| Waves per SM | 0,33 | 0,33 |
| Block Limit SM | 24 | 24 |
| Block Limit Registers | 16 | 16 |
| Block Limit Warps | 48 | 48 |
| **Ocupación teórica** | 33,33% | 33,33% |
| **Ocupación conseguida (real)** | **5,56%** | **5,52%** |
| Warps activos por SM (conseguidos) | 2,67 | 2,65 |

(Los hilos totales, 4.000, no coinciden con los 2.000 walkers iniciales -- en DMC la población crece/decrece por el mecanismo de repoblación de cada paso, así que en el instante exacto donde `ncu` capturó estas 2 llamadas la población real ya era otra, no un error.)

### El hallazgo importante: el cuello de botella no son los registros, es el TAMAÑO DEL GRID

`ncu` mismo lo señala con una recomendación explícita:

> "The difference between calculated theoretical (33.3%) and measured achieved occupancy (5.6%) can be the result of warp scheduling overheads or workload imbalances during the kernel execution... Est. Speedup: 83.31%"

Con solo **0,33 "oleadas" por SM** (`Waves Per SM`), el grid (125 bloques) es tan pequeño que **ni siquiera llena una vez todas las SMs de la GPU** -- muchas SMs se quedan sin bloques que hacer mientras otras trabajan, un desequilibrio de carga real. Esto coincide y confirma lo que ya habíamos visto de pasada durante la investigación de `myexp` (la nota de `ncu` "grid demasiado pequeño para llenar los recursos del dispositivo"): **el techo real de rendimiento hoy no es la presión de registros que hemos estado optimizando toda la sesión -- es que el grid es demasiado pequeño**, incluso a 2000-4000 hilos.

Esto explica también, con datos, por qué nuestras optimizaciones de registros (`GTEST`/`nhe3` fijos) dieron ganancias reales pero moderadas (10-14%) en vez de algo mucho mayor: liberar registros solo ayuda si el grid es lo bastante grande como para necesitar esos registros liberados para caber más bloques a la vez -- y aquí, con 0,33 oleadas, casi nunca llegamos a ese límite.

### Pista para seguir (no implementada todavía)

El plan de fases anteriores de este proyecto (`v3-cuda-optimización/README.md`) ya había señalado esto como pendiente: las 10 llamadas a kernel del pipeline usan **32 hilos/bloque fijo (1 warp/bloque)** en todas, y nunca se ha barrido este parámetro (64/128/256 hilos/bloque). Con bloques más grandes, el mismo número de hilos totales se reparte en MENOS bloques -- podría cambiar la relación entre "oleadas por SM" y el desequilibrio de carga que `ncu` está señalando aquí. Candidato claro para la siguiente prueba de `v4-cuda-pruebas/`.

## Ficheros

- `salida.log`: salida completa de la corrida.
- `tiempos_opcion7.dat`: reparto de tiempos por fase, copiado tras la corrida.
- `ncu_ocupacion_2000w.ncu-rep`: perfil completo de `ncu --set full` (abrible con Nsight Compute UI).
- `ncu_ocupacion_detalle.txt`: volcado en texto de la vista "details" del perfil.
- `ncu_ocupacion_stdout.log`: salida de consola de la corrida usada para el perfilado.
