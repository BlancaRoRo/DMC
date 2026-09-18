# Recíprocos de constante y bucles `nhe3` en `k_fase_h`

## 1. Objetivo

`mapa-sfu-produccion.md` §4.1 identificó `k_fase_h` (histogramas, `denssumapaso` en GPU) como el mayor consumidor de SFU de todo el binario (33 `RCP64H`, 26 `RSQ64H` estáticas) — más que todo `He_dihydrogen` junto. Este documento aplica a `k_fase_h` la misma idea de `reciprocos-ex0-duhe4x.md` (factor común de recíprocos), más una segunda técnica ya usada en el proyecto (`derananum-split-concurrente.md`): reescribir límites de bucle en términos de `nhe3` para que el compilador demuestre que están vacíos.

## 2. El código y los 3 tipos de división encontrados

`k_fase_h` tiene 5 bucles sobre pares de átomos (3 simples: He4-He4, He3-He3, He4-He3; 2 más grandes: He4-impureza, He3-impureza, con más divisiones cada uno por el cálculo angular). Se encontraron tres categorías de división:

**a) Por una constante de toda la simulación** (`dhr_h`, `dhc_h`, `dhs_h` — ya son `parameter`, calculados de otros `parameter`: `dhr_h=rmax_h/nhr_h`, etc.). Confirmado en SASS que el compilador **recalcula el recíproco en tiempo de ejecución en cada llamada**, no lo pliega en compilación:
```
MUFU.RCP64H R5, 0.0099999979138374328613   ! literal dhr_h, en CADA copia desenrollada del bucle
```
13 sitios en total (5×`dhr_h`, 4×`dhc_h`, 4×`dhs_h`).

**b) Por un valor invariante dentro de la subrutina pero no `parameter`** (`dnor`, calculado una vez en la línea 757 y reusado sin cambiar en los 2 bucles grandes). 2 sitios (`cval/dnor`).

**c) Por un valor que ya se cachea solo** (`w/sth`, confirmado en SASS: solo hay `MUFU.RCP64H` en el primer uso de las 4 apariciones — el compilador ya hace CSE, igual que `ulxp/rij` en `duhe4x`). **No se toca.**

Además, dos de los 5 bucles (He3-He3 y He3-impureza) usan `do iatom=nhe4+1,ngatom` — `ngatom` es una variable `device` opaca (sincronizada desde el host como `nhe4+nhe3` ya sumado), así que el compilador no puede relacionarla con `nhe3=0` aunque `nhe3` sea `parameter` en el lado GPU.

## 3. El cambio

```fortran
! nuevas constantes de compilacion (junto a dhr_h/dhc_h/dhs_h)
real(kind=r8), private, parameter :: inv_dhr_h=1.0_r8/dhr_h
real(kind=r8), private, parameter :: inv_dhc_h=1.0_r8/dhc_h
real(kind=r8), private, parameter :: inv_dhs_h=1.0_r8/dhs_h
```

En los 5 bucles: `int(rij/dhr_h)+1` → `int(rij*inv_dhr_h)+1` (5 sitios); `cval/dhc_h` → `cval*inv_dhc_h` (4 sitios); `sval/dhs_h` (y `-sval/dhs_h`) → `sval*inv_dhs_h` (4 sitios).

Justo donde se calcula `dnor`: `inv_dnor = 1.0_r8/dnor`, y sustituir las 2 apariciones de `cval/dnor` por `cval*inv_dnor`.

Límites de bucle, en los 3 sitios donde antes decía `nhe4+1,ngatom` (He3-He3 completo, y el límite de `jatom` en He4-He3, y el límite de `iatom` en He3-impureza):
```fortran
do iatom=nhe4+1,nhe4+nhe3   ! antes: nhe4+1,ngatom
```

## 4. Verificación: la métrica correcta importa

**Primer error evitado**: comparar solo "Energia total" no sirve para validar este cambio — `k_fase_h` únicamente escribe histogramas (`h44`, `hbhe4`, etc.), nunca alimenta la física ni el branching, así que la energía es ciega a cualquier cosa que le pase a este kernel. La verificación real es sobre los ficheros de histograma que el programa escribe a disco (`dhe4he4.20.00.HH`, `d2dhe4.20.00.HH`, etc.), comparados directamente entre producción y la variante nueva, en 4 semillas (11, 97, 42, 777), config real (2000 walkers), `conf.20.00.HH` fresco:

| Origen de la división | Ficheros | Resultado en las 4 semillas |
|---|---|---|
| `dhr_h`→`inv_dhr_h` (radiales) | `dhe4he4`, `dhe4he3`, `dihe4`, `dihe`, `dhe3he3`, `dihe3` | **Bit a bit idéntico, siempre** |
| `dhc_h`/`dhs_h`/`dnor` (angulares) | `d2dhe4`, `d2dhe`, `d2ydhe4`, `d2ydhe` | **Difiere en 3-6 bins de ~4000**, último dígito impreso (`...951` vs `...952`, relativo ~1e-11 a esa precisión de impresión) |
| Bucles `nhe3` | `dhe3he3`, `dihe3`, `d2dhe3`, `d2ydhe3` | Sin cambio (ya estaban vacíos) |

`dhe3he3`/`dihe3`/`d2dhe3`/`d2ydhe3` (histogramas He3) salen idénticos porque ya eran cero en ambas versiones (`nhe3=0`) — el cambio de límites de bucle no altera ningún valor, solo si el compilador puede demostrarlo.

**Decisión del usuario**: se acepta la divergencia de último dígito en los histogramas angulares (`dhc_h`/`dhs_h`/`dnor`) — negligible frente al ruido estadístico propio de un histograma acumulado sobre miles de pasos, y consistente con el patrón ya visto en `reciprocos-ex0-duhe4x.md` (recíprocos cacheados no garantizan bit a bit, pero el error queda contenido y proporcional).

## 5. SFU y ciclos: la reducción más grande medida hasta ahora en esta línea de trabajo

Instrucciones `MUFU` estáticas en `k_fase_h` (`cuobjdump --dump-sass`):

| | `RCP64H` | `RSQ64H` | Total |
|---|---|---|---|
| Antes | 33 | 26 | 59 |
| Después | **3** | **10** | **13** (−78%) |

La caída es mayor que solo sustituir las 13 divisiones por recíprocos — los bucles de He3 ahora se demuestran vacíos de verdad y el compilador **elimina su cuerpo entero** (sus propios `sqrt`/`atomicadd`/divisiones), no solo evita recalcular una constante.

Instrucciones dinámicas ejecutadas y ciclos reales (`ncu --launch-skip 2 --launch-count 3`):

| Métrica | Antes | Después | Cambio |
|---|---|---|---|
| Instrucciones XU ejecutadas | 34.083 | 17.136 | **−49,7%** |
| Ciclos del kernel | 454.438 | 335.627 | **−26,1%** |

**Registros: sin cambio (94→94)**. A diferencia de cuando se fijó `nhe3` en `derananum` (que sí liberó registros al eliminar funciones enteras con variables propias), aquí el cuerpo del bucle He3 es estructuralmente igual al de He4 (mismas variables `rtemp`/`rij`/`ihr`) — el asignador de registros ya compartía esos registros entre bucles vecinos, así que demostrar que uno está vacío no libera nada nuevo. El beneficio de los bucles `nhe3` aquí es de instrucciones SFU/ciclos, no de registros.

## 6. Decisión

**Se lleva a producción, con la divergencia angular aceptada explícitamente.** Aplicado a `hibrido_instrumentado/dmc2_pipeline.cuf`, recompilado y verificado desde config fresca (`energia final de las configuraciones` y `Energia total` coinciden con la referencia conocida).

## 7. Control final acumulado contra CPU (todos los cambios de esta línea de trabajo)

Tras encadenar funciones nativas (`funciones-nativas-cuda.md`) + `He_dihydrogen_induccion`/`duhe4x` bucle (`reciprocos-ex0-duhe4x.md` §2-6) + `duhe4x` bloque `impurmol` (`reciprocos-ex0-duhe4x.md` §6.1) + `k_fase_h` (este documento), se repitió la comparación contra CPU (`gfortran`, `opcion=4`) en las 4 semillas usadas en toda esta línea de trabajo, `conf.20.00.HH` fresco:

| Semilla | CPU (`gfortran`, opcion=4) | GPU (producción con todos los cambios) | Diferencia | σ combinada |
|---|---|---|---|---|
| 11  | −677.1452 ± 1.94 meV | −676.8178 ± 1.84 meV | 0.33 | 0,12σ |
| 97  | −679.3221 ± 1.80 meV | −677.4046 ± 1.80 meV | 1.92 | 0,75σ |
| 42  | −681.3123 ± 1.82 meV | −678.4074 ± 1.92 meV | 2.90 | 1,10σ |
| 777 | −678.7018 ± 2.08 meV | −678.9230 ± 1.71 meV | 0.22 | 0,08σ |

Todas las semillas compatibles, ninguna por encima de 1,1σ (muy por debajo del umbral habitual de 2-3σ). El GPU de hoy da exactamente los mismos números en las 4 semillas que en cada verificación bit a bit intermedia de esta línea de trabajo, así que este control valida de una vez toda la cadena acumulada de cambios sobre la física real, no solo la autoconsistencia GPU-contra-GPU de cada paso individual.

## Ficheros

- Verificación hecha directamente sobre copias de `hibrido_instrumentado/`, comparando los ficheros `.HH` de histograma reales en 4 semillas — no persistida (quedó en `/tmp`, no en el repo).
