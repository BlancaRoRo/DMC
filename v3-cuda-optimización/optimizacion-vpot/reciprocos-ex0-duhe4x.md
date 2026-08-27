# Recíprocos cacheados en `Ex0`/`Ey0`/`Ez0` (`He_dihydrogen_induccion`) y `duhe4x`

## 1. Objetivo

`mapa-sfu-produccion.md` §6 concluyó que, de los dos tipos de instrucción SFU encontrados, la división (`MUFU.RCP64H`) es el candidato correcto para intentar algo — hay redundancia real que explotar (el mismo divisor usado varias veces) y el error se propaga de forma lineal, no exponencial. Este documento aplica esa idea a los dos sitios con más volumen de división repetida por el mismo divisor: `Ex0`/`Ey0`/`Ez0` en `He_dihydrogen_induccion` (divide 3 veces por `rh1`, 3 por `rh2`, 3 por `r0`) y el bucle `do il=0,lxhe4` de `duhe4x` (divide repetidamente por `rij`, `rij**2` y `rijp2`).

## 2. El cambio

**`He_dihydrogen_induccion`** (`He_dihydrogen.f`, bloque `Ex0`/`Ey0`/`Ez0`):

```fortran
inv_rh1=1.d0/rh1
inv_rh2=1.d0/rh2
inv_r0=1.d0/r0
inv_rh1_3=inv_rh1*inv_rh1*inv_rh1
inv_rh2_3=inv_rh2*inv_rh2*inv_rh2
inv_r0_3=inv_r0*inv_r0*inv_r0

Ex0=q*FN2(btheta*rh1)*(X(...)-r_dih(1,1))*inv_rh1_3      ! antes: /rh1**3
Ex0=Ex0+q*FN2(btheta*rh2)*(X(...)-r_dih(1,2))*inv_rh2_3  ! antes: /rh2**3
Ex0=Ex0-q0*FN2(btheta*r0)*(X(...))*inv_r0_3               ! antes: /r0**3
! igual para Ey0, Ez0
```

Solo se tocó el bloque **vivo** (líneas 897-916, dentro de `He_dihydrogen_induccion`) — el mismo patrón en la versión monolítica de `He_dihydrogen` (línea 524, código muerto per `mapa-sfu-produccion.md` §4.2) se deja intacto, no hace falta tocar código que nunca se ejecuta.

**`duhe4x`** (`d_uhex4_mod.cuf`, bucle `do il=0,lxhe4`):

```fortran
inv_rij  = 1.0_r8/rij          ! antes de entrar al bucle
inv_rij2 = inv_rij*inv_rij

do il=0,lxhe4
  rijp2=mypow_desde_log(rij_hi,rij_lo,pxhe4(2,il))
  inv_rijp2 = 1.0_r8/rijp2      ! una vez por iteracion, se usaba 3 veces
  ulx=  -pxhe4(1,il)*inv_rijp2 - ...            ! antes: /rijp2
  ulxp=(...)*inv_rij                             ! antes: /rij
  ulxs=(...)*inv_rij2                            ! antes: /rij**2
  ulxs=ulxs+2.0_r8*ulxp*inv_rij                  ! antes: /rij
  grul%comp=ulxp*inv_rij*rivec%comp              ! antes: /rij
enddo
```

## 3. Verificación bit a bit en pruebas aisladas: NO es exacto

Dos pruebas unitarias independientes (`prueba_reciprocos/test_reciprocos.cuf` para `Ex0`/`Ey0`/`Ez0`, `prueba_reciprocos_duhe4x/test_duhe4x.cuf` para `duhe4x`), cada una con 10-12 posiciones sintéticas cubriendo un rango físico amplio (cercanas, lejanas, casi-cero, signos mixtos):

| Prueba | Casos que difieren | Error relativo típico |
|---|---|---|
| `Ex0`/`Ey0`/`Ez0` | 7 de 12 | ~1e-17 a 1e-16 (1-2 ULP) |
| `duhe4x` (`d2ux`) | 8 de 10 | ~1e-18 a 1e-16 (1-2 ULP) |

Consistente con la teoría: multiplicar por un recíproco cacheado no redondea igual que dividir cada vez. **Ninguna de las dos pruebas aisladas es bit a bit exacta.**

## 4. Verificación en el pipeline completo: SÍ es bit a bit idéntico (4 semillas)

Aplicando los dos cambios juntos a una copia completa del pipeline de producción (`opcion=7`, config real de 2000 walkers/59 bloques/20 pasos, `conf.20.00.HH` fresco en cada corrida) y comparando contra producción sin tocar, en 4 semillas independientes:

| Semilla | GPU producción | GPU con recíprocos | `diff` completo del log |
|---|---|---|---|
| 11  | −676.8178220759 ± 1.84 meV | −676.8178220759 ± 1.84 meV | 0 líneas de física distintas |
| 97  | −677.4045573550 ± 1.80 meV | −677.4045573550 ± 1.80 meV | 0 líneas de física distintas |
| 42  | −678.4074405137 ± 1.92 meV | −678.4074405137 ± 1.92 meV | 0 líneas de física distintas |
| 777 | −678.9230457352 ± 1.71 meV | −678.9230457352 ± 1.71 meV | 0 líneas de física distintas |

**Bit a bit idéntico en las 4 semillas**, confirmado con `diff` de los 79 bloques de cada corrida (solo difieren marcas de tiempo) y con binarios genuinamente distintos (`md5sum` distinto). Esto **no era el resultado esperado** tras la sección 3 — la explicación más razonable es que las pruebas aisladas metían a propósito valores sintéticos extremos (distancias casi cero, muy lejanas) para estresar casos límite, mientras que en una simulación real las distancias `rh1`/`rh2`/`r0`/`rij` que aparecen de verdad están acotadas a un rango físico mucho más estrecho — dentro de ese rango, en los ~2,36 millones de evaluaciones walker-paso de cada corrida (2000 walkers × 1180 pasos), el redondeo ha coincidido en el 100% de los casos, en las 4 semillas.

**Aviso de alcance**: esto está confirmado para esta configuración concreta (`opot=4`, esta impureza, este rango de densidad). No es una garantía matemática general — si algún día se cambia de configuración a un régimen con distancias muy distintas, habría que repetir esta misma verificación.

Comparación adicional contra CPU (`opcion=4`, gfortran, mismo `conf.20.00.HH` fresco) — compatible dentro de margen en las 2 semillas comprobadas:

| Semilla | CPU | GPU | Diferencia | Compatible |
|---|---|---|---|---|
| 11 | −677.1452 ± 1.94 meV | −676.8178 ± 1.84 meV | 0.33 | Sí, <1σ |
| 97 | −679.3221 ± 1.80 meV | −677.4046 ± 1.80 meV | 1.92 | Sí, <1σ |

## 5. La SFU baja de verdad, medido en SASS y con `ncu`

Instrucciones `MUFU` estáticas en el binario (`cuobjdump --dump-sass`):

| Función | `RCP64H` antes | `RCP64H` después | `RSQ64H` (sin cambio) |
|---|---|---|---|
| `He_dihydrogen_induccion` | 9 | **3** | 3 |
| `duhe4x`/`k_duhe4x` | 16 | **11** | 1 |
| Total del binario | 214 | **202** | 99 (sin cambio) |

Instrucciones dinámicas ejecutadas y ciclos reales (`ncu`, `--launch-skip 2 --launch-count 3`):

| Kernel | Métrica | Antes | Después | Cambio |
|---|---|---|---|---|
| `k_vpot_3warp_t` | Instrucciones XU ejecutadas | 150.714 | 143.154 | −5,0% |
| `k_vpot_3warp_t` | Ciclos | 3.374.422 | 3.324.217 | −1,5% |
| `k_derananum_resto_t` | Instrucciones XU ejecutadas | 107.919 | 53.739 | **−50,2%** |
| `k_derananum_resto_t` | Ciclos | 2.339.563 | 1.856.543 | **−20,6%** |

`k_derananum_resto_t` baja mucho más que la reducción estática de `duhe4x` (16→11) porque `duhe4x` se llama una vez por átomo de He4 dentro de ese kernel — el ahorro por llamada se multiplica por el número de átomos.

**Nota sobre el ratio de stall `short_scoreboard`**: sube ligeramente en `k_derananum_resto_t` (15,97→17,46) pese a que el kernel es un 20,6% más rápido — mismo efecto ya documentado en `funciones-nativas-cuda.md` §5: es una métrica relativa (stalls por instrucción emitida); con muchas menos instrucciones totales, la misma espera de SFU pesa proporcionalmente más. Lo que importa (ciclos e instrucciones absolutas) baja con claridad en los dos kernels.

## 6. Tiempo de pared

Con las 4 semillas ya usadas para la verificación bit a bit: mejoras del orden de 5-15% según la semilla (17,46s→14,89s en semilla 11; diferencias menores en otras, dentro de lo esperable dado que estas dos funciones son solo una fracción de la SFU total de `opcion=7`, ver `mapa-sfu-produccion.md` §4.1).

## 6.1. Extensión: bloque `if(impurmol)` de `duhe4x` (6 divisiones más)

Encontrado por el usuario revisando el propio código: dentro de `duhe4x`, el bloque `if(impurmol)` (líneas 63-73) tiene 6 divisiones más por `rij` (`cth`, `zpr`, `grz%comp`, `lapz`, `gpz(1)`, `gpz(2)`), sin tocar en la sección 2. Antes de aplicar el cambio, se verificó que era seguro reutilizar `inv_rij`: ese bloque va **después** de `call mypow_log(rij, rij_hi, rij_lo)` (línea 62), y `mypow_log` declara `x` como `intent(in)` (`glibc_pow.cuf:214`) — no puede modificar `rij`, así que `inv_rij` (calculado en la línea 60, antes de la llamada) sigue siendo válido dentro del bloque.

```fortran
cth=dot_product(rivec%comp,smol(3)%comp)*inv_rij      ! antes: /rij
zpr=cth*inv_rij                                        ! antes: /rij
grz%comp=(smol(3)%comp-zpr*rivec%comp)*inv_rij         ! antes: /rij
lapz=-2.0_r8*zpr*inv_rij                               ! antes: /rij
gpz(1)=-dot_product(rivec%comp,smol(2)%comp)*inv_rij   ! antes: /rij
gpz(2)= dot_product(rivec%comp,smol(1)%comp)*inv_rij   ! antes: /rij
```

**Verificación** (mismo protocolo: pipeline completo, 4 semillas, `conf.20.00.HH` fresco, comparado contra la producción ya con el cambio de la sección 2 aplicado): **bit a bit idéntico en las 4 semillas** (11, 97, 42, 777), `diff` completo de los 79 bloques sin ninguna línea de física distinta, binarios genuinamente distintos.

SFU y ciclos (`duhe4x`, sobre la base de 11 `RCP64H` que ya tenía tras la sección 2):

| Métrica | Antes (solo cambio del bucle) | Después (+ bloque `impurmol`) | Cambio |
|---|---|---|---|
| `RCP64H` estáticas en `duhe4x` | 11 | **3** | −73% |
| Instrucciones XU dinámicas (`k_derananum_resto_t`) | 53.739 | 43.659 | **−18,8%** |
| Ciclos (`k_derananum_resto_t`) | 1.857.413 | 1.781.110 | **−4,1%** |

**Se lleva a producción**, con el mismo criterio ya aplicado (bit a bit idéntico en 4 semillas supera el listón fijado). `duhe4x` acumula ahora dos rondas de recíprocos: 16→11 (bucle `do il`, sección 2) →3 (bloque `impurmol`, esta sección) instrucciones `RCP64H` estáticas.

## 7. Decisión

**Se lleva a producción**: bit a bit idéntico en 4 semillas (supera el listón de "dentro del margen estadístico" que se había fijado de antemano), SFU/ciclos reducidos y medidos con `ncu`/SASS, mejora de tiempo real. Aplicado a `hibrido_instrumentado/He_dihydrogen.f` y `hibrido_instrumentado/d_uhex4_mod.cuf`, recompilado y verificado desde config fresca.

## Ficheros

- `prueba_reciprocos/test_reciprocos.cuf`: prueba unitaria aislada de `Ex0`/`Ey0`/`Ez0` (sección 3).
- `prueba_reciprocos_duhe4x/test_duhe4x.cuf`, `d_uhex4_original.cuf`, `d_uhex4_reciprocos.cuf`: prueba unitaria aislada de `duhe4x` (sección 3).
- Verificación de pipeline completo: hecha directamente sobre copias de `hibrido_instrumentado/`, sin persistir (los binarios/logs de las 4 semillas quedaron en `/tmp`, no en el repo).
