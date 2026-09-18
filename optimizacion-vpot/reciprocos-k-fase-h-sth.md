# `k_fase_h`: recíproco cacheado para `w/sth` (hallazgo del usuario)

## 1. Objetivo

Revisando la tabla de raíces cuadradas (`mapa-sfu-produccion.md` §7), el usuario señaló directamente `w/sth` en el bloque He4-impureza de `k_fase_h` -- una división que se nos había escapado en `reciprocos-k-fase-h.md` (ese fix se centró en `dhr_h`/`dhc_h`/`dhs_h`/`dnor`, no llegó a `sth`).

## 2. El hallazgo

```fortran
! dmc2_pipeline.cuf, bloque He4-impureza de k_fase_h (antes)
cth = cval/rij; sth = sqrt(1.0_r8-cth**2); sval = rij*sth
...
dummy = atomicadd(hbhe4(ihc,ihs), w/sth)
dummy = atomicadd(hbhe(ihc,ihs), w/sth)
...
dummy = atomicadd(hybhe4(ihc,ihs), w/sth)
dummy = atomicadd(hybhe(ihc,ihs), w/sth)
```

`sth` se calcula una vez y se usa en **4 divisiones** (`w/sth`), sin ninguna reasignación entre medias -- mismo patrón de siempre. El mismo bloque se repite en la parte He3-impureza (código muerto con `nhe3=0`, arreglado igual por consistencia con la parte viva, mismo criterio que `duhe3x`/`uhe3x`).

## 3. El cambio

```fortran
! despues
cth = cval/rij; sth = sqrt(1.0_r8-cth**2); sval = rij*sth
inv_sth = 1.0_r8/sth
...
dummy = atomicadd(hbhe4(ihc,ihs), w*inv_sth)
dummy = atomicadd(hbhe(ihc,ihs), w*inv_sth)
...
dummy = atomicadd(hybhe4(ihc,ihs), w*inv_sth)
dummy = atomicadd(hybhe(ihc,ihs), w*inv_sth)
```

## 4. Verificación

Pipeline completo, 4 semillas (11, 97, 42, 777), `conf.20.00.HH` fresco, comparado contra la producción acumulada. **Bit a bit idéntico en las 4 semillas**.

## 5. SFU y ciclos: un matiz nuevo -- las instrucciones XU no bajan, pero sí el resto

Medido con `ncu` sobre `k_fase_h` (media de 3 lanzamientos):

| Métrica | Antes | Después | Cambio |
|---|---|---|---|
| Ciclos | 336.382 | 331.951 | **−1,3%** |
| Instrucciones totales | 804.181 | 790.825 | **−1,7%** |
| Instrucciones FMA | 110.184 | 105.837 | **−3,9%** |
| Instrucciones XU (SFU) | 17.136 | 17.136 | **0%** |

**Por qué las XU no se mueven, a diferencia de todos los fixes anteriores**: en este caso concreto `w` y `sth` son *literalmente* la misma expresión repetida 4 veces (no solo el mismo divisor con numerador distinto, como en `dhr_h`) -- el compilador ya hacía CSE automático de la semilla `MUFU.RCP64H` de `w/sth` (mismo mecanismo confirmado en todo este árbol: CSE real para expresiones idénticas, nunca reciprocal-caching para expresiones distintas con divisor común). Lo que el compilador **no** compartía era el resto de la secuencia de refinamiento de precisión que sigue a la semilla (varias `FMA` por cada división completa) -- cachear `inv_sth` a mano fuerza a compartir también eso, de ahí que bajen ciclos/instrucciones/FMA sin que baje la propia cuenta de `MUFU`. Primer caso de esta línea de trabajo donde el ahorro no pasa por el canal SFU.

## 6. Decisión

**Se lleva a producción** (bit a bit idéntico en 4 semillas). Aplicado a `hibrido_instrumentado/dmc2_pipeline.cuf`, recompilado y verificado desde config fresca (`meV Energia total = -676.8178220759`, valor de referencia sin cambios).

## Ficheros

- Backup: `/tmp/backup_sin_reciprocos/dmc2_pipeline.cuf.antes_sth`.
- Verificación hecha directamente sobre copias de `hibrido_instrumentado/` -- no persistida (quedó en `/tmp`, no en el repo).
