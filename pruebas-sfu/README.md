# pruebas-sfu: batería de tiempos GPU (nvfortran, opcion=7) vs CPU (gfortran, opcion=4)

## Objetivo

Con la línea de trabajo de reducción de instrucciones SFU (`v3-cuda-optimización/optimizacion-vpot/`) cerrada -- 9 fixes en producción, mapa completo de divisiones y raíces cuadradas sin candidatos pendientes -- esta batería mide el tiempo real, a corridas medio-largas, del pipeline GPU de producción (`v2-cuda-integracion/hibrido_instrumentado/qmccluster_pipeline`, `opcion=7`, compilado con `nvfortran`) frente al código CPU original sin portar (`v2-cuda-integracion/cpu-original-gfortran/qmccluster`, `opcion=4`, compilado con `gfortran`).

No es una prueba de correctitud (eso ya está establecido en toda la línea de `v3-cuda-optimización/`) -- es una prueba de **tiempos**, a una escala mucho mayor que la usada para verificar cada fix individual (que siempre usó 2000w/59 bloques/20 pasos, corridas de 13-160s). Complementa directamente `v4-cuda-pruebas/README.md` (pruebas 1-3), que ya escaló gradualmente hasta 50.000 pasos totales y encontró una posible deriva térmica en corridas largas sin confirmar -- aquí se sigue escalando, con las 9 mejoras de SFU ya aplicadas (las pruebas 1-3 son anteriores a esa línea de trabajo).

## Configuración base (verificada antes de cualquier corrida)

Todas las corridas parten de la misma "Configuración Inicial" del TFG (`/home/blanca/Documentos/Universidad/TFG/Configuración inicial /rbdmc/`), copiada a `_plantillas/`:

- `conf.20.00.HH.base`: **idéntico** (diff vacío) al usado en toda la sesión de `v3-cuda-optimización/` (`v1-cuda-desarrollo/ccuerpo/conf.20.00.HH`) -- mismo punto de partida de siempre, un walker semilla que el propio programa expande a la población real.
- `in.mcv.base`: mismos parámetros físicos que la producción real (`dtau=0.0001`, deltas de Metropolis, ángulo de rotación) -- verificado con `diff` contra `hibrido_instrumentado/in.mcv`, solo difieren `opcion`/bloques/pasos/walkers (los que varía esta batería).
- **`etrial = -631.8`** en todas las corridas -- verificado explícitamente antes de generar cada `in.mcv` de prueba, y confirmado con `grep` después de cada sustitución (nunca se asume, se comprueba).
- **Semilla fija** (`0000000000000011`) en todas las corridas -- el objetivo es medir tiempo, no verificar física entre semillas (eso ya está hecho en `v3-cuda-optimización/`), así que se mantiene fija para que la única variable entre corridas sea el parámetro que cada test cambia.
- `conf.20.00.HH` fresco (recopiado desde `_plantillas/`) antes de cada corrida individual, sin excepción -- mismo protocolo que toda la sesión.

## Los 3 tipos de test

Cada uno varía **un solo eje**, dejando los otros dos fijos:

1. **`test-walkers/`**: pasos por bloque=100, bloques de cálculo=100 fijos; walkers = 500, 1000, 1500, 2000, 2500.
2. **`test-bloques/`**: walkers=1000, pasos por bloque=100 fijos; bloques de cálculo = 50, 100, 200, 300, 500.
3. **`test-pasos/`**: walkers=1000, bloques de cálculo=100 fijos; pasos por bloque = 100, 1000, 10.000, 50.000.

En todos los casos, "bloques de equilibrio"=1 y "pasos de descorrelación"=10 (valores de la Configuración Inicial, sin tocar).

### CPU vs GPU: recorte por tiempo (acordado explícitamente)

Con el coste medido en esta misma sesión (CPU `gfortran`: ~6,75·10⁻⁵ s por paso·walker; GPU `nvfortran`: ~5,71·10⁻⁶ s por paso·walker, ambos con el binario ya optimizado), un barrido completo CPU+GPU hasta 100.000 pasos habría tomado semanas. Se acordó con el usuario:

- **`test-walkers` y `test-bloques`**: CPU **y** GPU en los 5 puntos de cada uno (el máximo, ~28 min de CPU en `test-walkers` a 2500w, y ~56 min de CPU en `test-bloques` a 500 bloques -- ambos muy por debajo del límite razonable).
- **`test-pasos`**: CPU **y** GPU en 100 y 1.000 pasos (máximo ~1,9h de CPU en 1.000 pasos) -- en 10.000 y 50.000 pasos, **solo GPU** (la versión CPU tomaría ~18,75h y ~3,9 días respectivamente, fuera de lo razonable).

## La corrida final del TFG

`test-tfg-final/`: la configuración real que necesita el TFG -- **2000 walkers, 128 bloques de cálculo, 100.000 pasos por bloque** (12,8M pasos DMC totales) -- **solo GPU** (la versión CPU tomaría semanas, no es una comparación viable a esta escala; el propósito aquí es el tiempo real de producción, no la comparación). Esta configuración no se recorta bajo ningún concepto -- es la que de verdad hace falta para el TFG, independientemente de lo que tarde.

## Estructura de salidas

Cada punto de cada test guarda su salida en su propia carpeta, sin sobreescribir nunca entre pruebas:

```
test-walkers/test-1000w/salida-test-1000w-gpu.log
test-walkers/test-1000w/salida-test-1000w-cpu.log
test-walkers/test-1000w/in.mcv-gpu   (por trazabilidad, la config exacta usada)
test-walkers/test-1000w/in.mcv-cpu
...
test-pasos/test-100000p/salida-test-100000p-gpu.log   (sin -cpu, solo GPU a partir de 10000p)
...
test-tfg-final/salida-tfg-final-gpu.log
```

## Metodología de ejecución

- **Nunca dos corridas a la vez** -- todo en serie, un binario detrás de otro, para que el tiempo medido sea real y no esté contaminado por competencia de recursos (lección aprendida por las malas en `v3-cuda-optimización/`, ver `stall-antes-despues-y-reintento-concurrencia.md`).
- **4 scripts independientes, uno por tipo de test** (`ejecutar_test_walkers.sh`, `ejecutar_test_bloques.sh`, `ejecutar_test_pasos.sh`, `ejecutar_test_tfg_final.sh`), cada uno se para solo al terminar -- **no se encadenan automáticamente**. Se lanzan de uno en uno, a petición explícita.
- Cada carpeta de test tiene su propio `.md` comparando tiempos y datos (energía/población) de esa batería, para verificar que todo salió correcto además de medir cuánto tardó.
- Este `README.md` se actualiza con los resultados agregados una vez completada toda la batería.

## Estado

**Infraestructura preparada, ejecución pendiente de confirmación del usuario** (duración total estimada ~2,3 días de cómputo secuencial, tras reducir `test-walkers` a 500-2500w y `test-pasos` a 100/1.000/10.000/50.000 -- dominada por la corrida final del TFG, ~40,6h). No se ha lanzado ninguna corrida todavía.
