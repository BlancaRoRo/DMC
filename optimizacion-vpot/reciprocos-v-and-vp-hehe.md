# Recíproco de `x` cacheado en `V_and_Vp_hehe`

## 1. Objetivo

Siguiendo `mapa-sfu-produccion.md` §4.1, se revisó `V_and_Vp_hehe` (9 `RCP64H` estáticas, marcada como "no visto"). El usuario planteó que probablemente solo la parte `D_HeHe/x-1.d0` fuera aprovechable; al revisar la función completa, la oportunidad resultó ser mucho mayor: **8 de las 9 divisiones son por una potencia de la misma `x`**.

## 2. El código y las 9 divisiones

```fortran
x  = r/req_HeHe                                          ! division 1: req_HeHe es PARAMETER
...
F  = myexp(-(D_HeHe/x-1.d0)**2)                          ! division 2: D_HeHe/x
Fp = 2.d0*(D_HeHe/x-1.d0)*(D_HeHe/x2)*F                  ! D_HeHe/x (CSE gratis, ya visto en duhe4x) + division 3: D_HeHe/x2
sum1 = c6_HeHe/x6 + c8_HeHe/x8 + c10_HeHe/x10            ! divisiones 4,5,6
sum2 = 6.d0*c6_HeHe/x7 + 8.d0*c8_HeHe/x9 + 10.d0*c10_HeHe/x11  ! divisiones 7,8,9
```

`req_HeHe` y `D_HeHe` son `PARAMETER` (`param_atoms_bh_freeform.h:39`) — confirmado antes de tocar nada. Las divisiones 2-9 dividen todas por `x`, `x2`, `x6`, `x7`, `x8`, `x9`, `x10` o `x11` — todas potencias de la misma `x` (la distancia He-He reducida).

## 3. El cambio

```fortran
double precision, parameter :: inv_req_HeHe = 1.d0/req_HeHe   ! constante de compilacion, coste cero
...
x = r*inv_req_HeHe                                             ! antes: r/req_HeHe

inv_x  = 1.d0/x
inv_x2 = inv_x*inv_x
inv_x6 = inv_x2*inv_x2*inv_x2
inv_x7 = inv_x6*inv_x
inv_x8 = inv_x6*inv_x2
inv_x9 = inv_x8*inv_x
inv_x10= inv_x8*inv_x2
inv_x11= inv_x10*inv_x

F  = myexp(-(D_HeHe*inv_x-1.d0)**2)                       ! antes: D_HeHe/x
Fp = 2.d0*(D_HeHe*inv_x-1.d0)*(D_HeHe*inv_x2)*F           ! antes: D_HeHe/x2
sum1 = c6_HeHe*inv_x6 + c8_HeHe*inv_x8 + c10_HeHe*inv_x10 ! antes: /x6, /x8, /x10
sum2 = 6.d0*c6_HeHe*inv_x7 + 8.d0*c8_HeHe*inv_x9 + 10.d0*c10_HeHe*inv_x11  ! antes: /x7, /x9, /x11
```

Las potencias directas (`x3`,`x6`,`x7`,`x8`,`x9`,`x10`,`x11`) se dejan calculadas tal cual en el código (quedan sin usar tras el cambio, salvo `x2` que sigue haciendo falta para `expbase`) — el compilador las elimina por su cuenta al ser código muerto, no hacía falta tocarlas para no arriesgar nada más de lo necesario.

## 4. Verificación

Mismo protocolo: pipeline completo, 4 semillas (11, 97, 42, 777), `conf.20.00.HH` fresco, comparado contra la producción con todos los cambios anteriores ya aplicados. **Bit a bit idéntico en las 4 semillas** — `diff` completo de los 79 bloques sin ninguna línea de física distinta, binarios genuinamente distintos (`md5sum`). Notable porque es el cambio con más divisiones sustituidas de golpe (8) de toda esta línea de trabajo, y aun así salió limpio en las 4 semillas.

## 5. SFU y ciclos: la mayor reducción dinámica de esta línea de trabajo

| | `RCP64H` | `RSQ64H` |
|---|---|---|
| `V_and_Vp_hehe` antes | 9 | 0 |
| `V_and_Vp_hehe` después | **1** | 0 |

(`k_V_hehe`/`k_Vp_hehe`, los kernels de prueba de `V_hehe`/`Vp_hehe` por separado, sin tocar y sin cambio — no se llaman desde producción, solo `V_and_Vp_hehe` los llama ambos fusionados.)

| Métrica (`k_vpot_3warp_t`) | Antes | Después | Cambio |
|---|---|---|---|
| Instrucciones XU dinámicas | 143.176 | 57.894 | **−59,6%** |
| Ciclos | 3.325.275 | 2.688.906 | **−19,1%** |

## 6. Decisión

**Se lleva a producción** (bit a bit idéntico en 4 semillas). Aplicado a `hibrido_instrumentado/mVheheVphehe_mod.cuf`, recompilado y verificado desde config fresca.

## Ficheros

- Verificación hecha directamente sobre copias de `hibrido_instrumentado/` — no persistida (quedó en `/tmp`, no en el repo).
