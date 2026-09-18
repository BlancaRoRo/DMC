# Fase 4: Pruebas

Última fase del proyecto: con el pipeline GPU ya integrado (`fase2-integración`) y
optimizado (`fase3-optimización`), aquí se mide su comportamiento real a escalas cada
vez mayores -- desde encontrar el punto de cruce CPU/GPU hasta la corrida de
producción completa del TFG -- y se explora un par de líneas de hardware aparte
(V100 nativa, configuración inicial de referencia).

## Contenido

- **`conf-ini-GPU/`**: configuración inicial propuesta para el desarrollo de esta
  simulación (`conf.20.00.HH`, `in.mcv`, `heh2m.pot`) -- el punto de partida común que
  usan varias de las pruebas de esta carpeta.
- **`cpu-gpu-ctfg/`**: investigación de en qué punto (número de walkers, de bloques,
  de pasos) compensa usar la GPU frente a la CPU y en cuál es al revés -- el cruce
  real de eficiencia entre las dos versiones, no solo "la GPU siempre gana".
- **`prueba1-2000w-500pasos-bloque/`**: primera prueba de duración intermedia,
  2000 walkers / 20 bloques / 500 pasos por bloque. Hallazgo clave: el cuello de
  botella real es el tamaño del grid (0,33 oleadas/SM), no los registros.
- **`prueba2-threads-por-bloque/`**: prueba de subir los hilos por bloque de 32 a 128.
  Resultado negativo (empeora el tiempo real pese a mejorar la ocupación) -- no se
  lleva a producción.
- **`prueba3-2000w-1000pasos-50bloques/`**: sigue escalando por bloques/pasos en vez
  de hilos. El ritmo por paso empeora un 5,8% respecto a la prueba 1 -- posible
  deriva térmica en corridas largas, sin confirmar.
- **`pruebas-sfu/`**: la batería grande de tiempos GPU vs. CPU (`test-walkers/`,
  `test-bloques/`, `test-pasos/`), con la línea de reducción de instrucciones SFU ya
  cerrada, más `test-tfg-final/`: la corrida de producción real del TFG (2000
  walkers, 128 bloques, 100.000 pasos/bloque).
- **`v100-fp64-nativo/`**: sondeo en la Tesla V100 de `fluid3` de si existe hardware
  nativo para `exp`/`log` en doble precisión (a diferencia de la RTX 4060, que solo
  lo tiene en `float`) -- para saber si el ratio float/double de rendimiento
  encontrado en la RTX 4060 se mantiene en una GPU con mejor FP64 nativo.

## Objetivo original de prueba1-3

Antes de saltar directamente a la configuración de producción real (2000 walkers,
1 bloque equilibrio + 100 bloques cálculo, 10.000-100.000 pasos/bloque), estas tres
primeras pruebas escalan gradualmente la duración/escala respecto a la anterior, para
detectar pronto cualquier problema que solo aparezca en corridas largas (deriva
térmica sostenida, fugas de memoria, degradación progresiva) antes de comprometerse a
una corrida de días. Cada subcarpeta de prueba tiene su propio `.md` explicando qué
configuración se usó y por qué, qué se esperaba ver, y qué se vio de verdad.
