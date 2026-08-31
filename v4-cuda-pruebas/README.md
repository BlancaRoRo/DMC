# v4-cuda-pruebas

Corridas de duración intermedia (minutos, no segundos) del pipeline GPU de producción (`v2-cuda-integracion/hibrido_instrumentado/`, ya con `GTEST` fijo + (a) + `nhe3` fijo migrados -- ver `v3-cuda-optimización/myexp-optimizacion/myexp-optimizacion.md`), para dos objetivos:

1. **Escalar gradualmente** hacia una configuración de producción real (2000 walkers, 1 bloque equilibrio + 100 bloques cálculo, 10.000-100.000 pasos/bloque -- ver estimación en el hilo de conversación, entre ~14 horas y ~6 días según el extremo) sin saltar directamente ahí. Cada prueba aquí sube un poco la duración/escala respecto a la anterior, para detectar pronto cualquier problema que solo aparezca en corridas largas (deriva térmica sostenida, fugas de memoria, degradación progresiva, errores que solo se manifiestan tras muchos pasos) antes de comprometerse a una corrida de días.
2. **Perfilado con Nsight Compute** (ocupación, registros, bloques residentes) sobre el pipeline de producción ya optimizado, en escalas realistas -- complementa el perfilado ya hecho en `v3-cuda-optimización/myexp-optimizacion/` (que se centró en registros/ocupación de kernels concretos, `k_derananum_t`/`k_vpot_t`, no en corridas completas de duración media).

## Estructura

Una subcarpeta por prueba, cada una con su propio `.md` explicando: qué configuración se usó y por qué (dónde encaja en la escalada gradual), qué se esperaba ver, qué se vio de verdad (tiempos, energía, cualquier perfilado de `ncu`/`nsys` asociado), y las salidas completas guardadas (nunca se sobreescriben entre pruebas).

## Pruebas

- `prueba1-2000w-500pasos-bloque/`: primera prueba, 2000 walkers / 20 bloques / 500 pasos por bloque (10.000 pasos totales, ~8-9 min estimados) -- coincide con el extremo bajo de pasos/bloque del objetivo final, en una sola corrida corta. **Hallazgo clave**: el cuello de botella real es el tamaño del grid (0,33 oleadas/SM), no los registros -- ocupación conseguida muy por debajo de la teórica (5,5% vs 33,3%).
- `prueba2-threads-por-bloque/`: sube los hilos/bloque de 32 (fijo desde siempre) a 128, siguiendo la pista de la Prueba 1. La ocupación conseguida mejora un 36% relativo, pero el tiempo real **empeora** en las 4 escalas probadas (500-3000w) -- resultado negativo, no se lleva a producción. Causa confirmada con `ncu`: con 128 hilos las SMs solo están ocupadas el 59,1% del tiempo total (frente al 79,4% con 32) -- efecto "cola larga" al repartir el mismo trabajo en menos bloques más grandes.
- `prueba3-2000w-1000pasos-50bloques/`: sigue escalando por el eje bloques/pasos (no hilos, que quedó descartado) -- 50 bloques × 1000 pasos = 50.000 pasos totales, ~40,5 min. El ritmo por paso **empeora** un 5,8% respecto a la Prueba 1 (rompe la tendencia de mejora vista hasta 500 pasos/bloque) -- posible deriva térmica sostenida en una corrida mucho más larga (no confirmado, no se monitorizó la GPU durante la corrida -- lección para las siguientes pruebas largas).
