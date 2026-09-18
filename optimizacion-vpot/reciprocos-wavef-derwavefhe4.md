# `wavef_derwavefhe4`: recíproco cacheado para las 2 divisiones por `rij`

## 1. Objetivo

Siguiendo `mapa-sfu-produccion.md` §4.1, quedaban por revisar `wavef_derwavefhe4` (`k_derananum_he4_t`). El usuario señaló `/rij` en `der_wavefhe4_mod.cuf`, preguntando si `derwavefhe4` se podía reducir a un solo `1/rij` y si `wavefhe4` tenía el mismo margen.

## 2. El hallazgo: `wavefhe4` no tiene nada que cachear, `derwavefhe4` sí -- pero ninguna de las dos corre en producción

`wavefhe4` (línea 37-59) tiene una única división en toda la función (`phe4(1)/mypow(rij,phe4(2))`) -- sin repetición, nada que cachear, correcto el instinto del usuario. `derwavefhe4` (línea 63-95) sí tiene 2 divisiones por el mismo `rij`:

```fortran
ujasp=phe4(1)*phe4(2)/mypow(rij,phe4(2)+1.0_r8)
ujass=-(phe4(2)+1)*ujasp/rij      ! division 1 por rij
ujasp=(ujasp-phe4(3))/rij         ! division 2 por rij -- mismo rij
```

Pero **ni `wavefhe4` ni `derwavefhe4` sueltas se ejecutan con `opcion=7`** -- `mapa-sfu-produccion.md` §4.2 ya las marca como "superseded" por `wavef_derwavefhe4` (la versión fusionada de `optimización-mypow/`, más abajo en el mismo fichero), la única que llama de verdad `k_derananum_he4_t`. Esa fusión tiene el mismo patrón exacto, con las mismas 2 divisiones repetidas por `rij` (líneas 139-140):

```fortran
ujass=-(phe4(2)+1)*ujasp/rij
ujasp=(ujasp-phe4(3))/rij
```

Ese es el sitio real donde aplica el recíproco cacheado.

(De paso se detectó un segundo patrón, mayor pero de distinta naturaleza -- `rijp2p1=rij^(phe4(2)+1)` se recalcula con una llamada completa a `mypow_desde_log` en vez de reusar `rijp2=rij^phe4(2)` ya calculado (`rijp2p1=rijp2*rij`). No es CSE puro como el de `log(rij)`≡`rij_hi`: `mypow_desde_log` calcula `exp(y·hi)` directamente, así que las dos rutas no están garantizadas bit a bit idénticas. Se deja fuera de este cambio, como candidato aparte a evaluar si hace falta más margen.)

## 3. El cambio

```fortran
! antes
ujass=-(phe4(2)+1)*ujasp/rij
ujasp=(ujasp-phe4(3))/rij
! despues
inv_rij=1.0_r8/rij
ujass=-(phe4(2)+1)*ujasp*inv_rij
ujasp=(ujasp-phe4(3))*inv_rij
```

## 4. Verificación

Pipeline completo, 4 semillas (11, 97, 42, 777), `conf.20.00.HH` fresco, comparado contra la producción con todos los cambios anteriores ya aplicados. **Bit a bit idéntico en las 4 semillas** -- `diff` completo sin ninguna línea de física distinta, binarios genuinamente distintos (`md5sum` diferente).

## 5. SFU y ciclos

| | `RCP64H` (estático, `wavef_derwavefhe4_`) |
|---|---|
| Antes | 4 |
| Después | **3** |

| Métrica (`k_derananum_he4_t`, media de 3 lanzamientos) | Antes | Después | Cambio |
|---|---|---|---|
| Ciclos | 1.632.839 | 1.523.580 | **−6,7%** |
| Instrucciones FMA | 594.150 | 570.210 | **−4,0%** |
| Instrucciones XU (SFU) | 71.820 | 59.850 | **−16,7%** |

## 6. Decisión

**Se lleva a producción** (bit a bit idéntico en 4 semillas). Aplicado a `hibrido_instrumentado/der_wavefhe4_mod.cuf`, recompilado y verificado desde config fresca (`meV Energia total = -676.8178220759`, valor de referencia sin cambios).

## Ficheros

- Backup: `/tmp/backup_sin_reciprocos/der_wavefhe4_mod.cuf.antes_invrij`.
- Verificación hecha directamente sobre copias de `hibrido_instrumentado/` -- no persistida (quedó en `/tmp`, no en el repo).
