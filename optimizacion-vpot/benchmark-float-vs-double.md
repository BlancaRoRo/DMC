# Benchmark aislado: `float` vs `double` en `wavef_derwavefhe4`

## 1. Objetivo

Con `mapa-sfu-produccion.md` §3 confirmando que esta GPU (RTX 4060 Laptop, compute 8.9) no tiene unidad de hardware para `exp`/`log`/`sin`/`cos` en doble precisión (solo en `float`), medir **cuánto más rápida sería la misma fórmula en simple precisión**, sin tocar la simulación real ni intentar validar si el resultado sigue siendo físicamente correcto (eso es una pregunta de validación numérica aparte, fuera de alcance de este benchmark).

## 2. Diseño

Réplica de `wavef_derwavefhe4` (la función con más peso de todo `derananum`, ver tabla de stall de la sesión) en `real(kind=4)`, con valores físicos **reales** (no inventados): se lanza una sola vez, tras terminar la corrida real completa (`opcion=7`), leyendo `atom_p` ya evolucionado por la simulación de verdad -- mismo patrón que `split-he-dihidrogen.md` (Intentos 5/7/8) para no contaminar ni depender de datos sintéticos.

```fortran
attributes(host, device) subroutine wavef_derwavefhe4_float(atom, wfhe4, d1wf, d2wf)
  ...
  real(kind=4) :: ujas,ujasp,ujass,rij,inv_rij
  ...
  rij=sqrt(real(dot_product(rtemp%comp,rtemp%comp),4))
  rij_hi=log(rij)
  rijp2=exp(p2*rij_hi)
  ...
  wfhe4=exp(ujas)
```

Misma estructura algebraica que la versión doble (`pow(x,y)=exp(y·log(x))`), mismo orden de operaciones -- el único cambio es el tipo de dato y que `log`/`exp`/`sqrt` ahora son los intrínsecos nativos en `float`.

**Medición**: 50 lanzamientos de cada kernel (`k_test_hehe_double_t`/`k_test_hehe_float_t`) con `cudaEvent`, sobre la población real de walkers ya evolucionada, con 1 lanzamiento de calentamiento previo (JIT/caché) descartado.

## 3. Resultado: 3,85x más rápido

| | Tiempo (50 lanzamientos) |
|---|---|
| `double` (referencia, sin tocar) | 66,65 ms |
| `float` | 17,32 ms |
| **Aceleración** | **3,85x** |

La corrida real (`opcion=7`) que arrastra este benchmark sigue dando el valor de referencia exacto (`-615.5737694991`) -- el benchmark usa arrays descartables propios, no toca ningún resultado real.

## 4. Por qué: confirmado en el SASS, no solo intuido

```
k_test_hehe_double_t: 3 MUFU.RCP64H, 1 MUFU.RSQ64H         (solo semillas de division/raiz -- exp/log siguen siendo software)
k_test_hehe_float_t:  3 MUFU.EX2, 3 MUFU.RCP, 1 MUFU.RSQ    (EX2 = exponencial de HARDWARE real, sin equivalente en doble)
```

**`MUFU.EX2` no tiene ningún equivalente en doble precisión en esta GPU** -- es la prueba directa de que la ganancia no es solo "las mismas operaciones más rápido por ser más pequeñas", es que `log`/`exp` dejan de ser un polinomio largo de software (decenas de instrucciones, el mecanismo ya documentado en `mapa-sfu-produccion.md` §3) y pasan a resolverse con una única instrucción de hardware.

## 5. Alcance y siguiente paso

Esto responde **solo** la pregunta mecánica ("cuánto más rápido"), con un resultado real y grande (3,85x en la función más pesada del árbol de `derananum`). **No responde** si el resultado sigue siendo físicamente válido para el DMC real -- `float` tiene ~7 dígitos de precisión frente a los ~15-16 de `double`, y un DMC acumula estadística sobre millones de pasos con control de población; validarlo exigiría una corrida larga comparando la física resultante (energía, convergencia) contra la referencia en doble, no solo un benchmark de velocidad.

**Pendiente, si se decide seguir por esta vía**: sustituir `wavef_derwavefhe4` por la versión `float` dentro de una corrida real completa (no aislada) y comparar la física resultante contra la referencia en doble -- decisión y alcance de esa prueba pendientes de acordar.

## Ficheros

- Copia aislada: `/tmp/float-vs-double-test/` (no persistida, no se llevó a producción -- este documento es solo el hallazgo del benchmark).
