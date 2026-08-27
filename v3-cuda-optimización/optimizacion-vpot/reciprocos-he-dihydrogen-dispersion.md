# `He_dihydrogen_dispersion`: código muerto identificado y recíprocos literales en `FN1`

## 1. Objetivo

Siguiendo `mapa-sfu-produccion.md` §4.1, se revisó `He_dihydrogen_dispersion` (5 `RCP64H` estáticas, marcada como "no visto"). El usuario señaló `fi=ror/(rnorm*onorm)` (línea 756) como candidato. La revisión con SASS reveló algo distinto: esa línea es código muerto, y el margen real está dentro de `FN1`.

## 2. Primer hallazgo: `fi`/`drrdx`/`dfidx`/`dthetadx` son código muerto

```fortran
fi=ror/(rnorm*onorm)
drrdx(:)=rvec(:)/rnorm
dfidx(:)=(orHH(:,1)*rnorm*onorm-ror*onorm*drrdx(:))/(rnorm*onorm)**2
IF (fi.eq.1.d0) THEN
  dthetadx(:)=-dfidx(:)
ELSE IF (fi.eq.-1.d0) THEN
  dthetadx(:)=dfidx(:)
ELSE
  dthetadx(:)=-dfidx(:)/dsqrt(1.d0-fi**2)
END IF
```

Confirmado en SASS (`sass_con_lineas.txt`, líneas 747-796): **ninguna instrucción `MUFU` proviene de este bloque**. `fi`, `drrdx`, `dfidx`, `dthetadx` se calculan pero nunca se leen para nada que llegue a `ENERGY2` (la única salida real de la subrutina) — ni `eterm1` ni `eterm2` dependen de ellas, solo de `atheta`/`btheta`/`c6theta`/`rnorm`/`norm6`, que vienen de `theta` (calculado aparte, con `angle`). El compilador ya lo eliminó por su cuenta, sin necesitar ningún truco de `parameter`/`GTEST` — es DCE (eliminación de código muerto) básica: variable local calculada pero nunca usada. Casi seguro es un resto de cuando esta pieza se separó de la `He_dihydrogen` monolítica (que sí usa esas derivadas, dentro de su bloque `IF(GTEST)` de fuerzas).

## 3. Segundo hallazgo: las 5 `RCP64H` reales están todas en `FN1` (línea 792)

```
linea 792: MUFU.RCP64H R7, -6      ! FN1: /6.d0
linea 792: MUFU.RCP64H R7, -24     ! FN1: /24.d0
linea 792: MUFU.RCP64H R7, -120    ! FN1: /120.d0
linea 792: MUFU.RCP64H R7, -720    ! FN1: /720.d0
linea 792: MUFU.RCP64H R5, R71     ! /norm6 (real, varia por atomo -- sin redundancia)
```

`FN1` (única llamadora real: esta línea 792; su otro uso, línea 437, vive en la `He_dihydrogen_` monolítica muerta) tiene:

```fortran
FN1=FN1+(-F00X*XDUMM**2/2.d0)     ! /2.d0: NO genera RCP64H -- dividir entre 2 es exacto en binario, *0.5 gratis
FN1=FN1+(-F00X*XDUMM**3/6.d0)     ! /6.d0, /24.d0, /120.d0, /720.d0: NO son potencias de 2,
FN1=FN1+(-F00X*XDUMM**4/24.d0)    ! division real cada una, con el literal como operando directo
FN1=FN1+(-F00X*XDUMM**5/120.d0)
FN1=FN1+(-F00X*XDUMM**6/720.d0)
```

`6.d0`/`24.d0`/`120.d0`/`720.d0` son literales de compilación, misma categoría que `dhr_h`/`req_HeHe` — su recíproco se puede precalcular como `PARAMETER`.

## 4. El cambio

```fortran
DOUBLE PRECISION, PARAMETER :: inv6=1.d0/6.d0, inv24=1.d0/24.d0
DOUBLE PRECISION, PARAMETER :: inv120=1.d0/120.d0, inv720=1.d0/720.d0
...
FN1=FN1+(-F00X*XDUMM**3*inv6)      ! antes: /6.d0
FN1=FN1+(-F00X*XDUMM**4*inv24)     ! antes: /24.d0
FN1=FN1+(-F00X*XDUMM**5*inv120)    ! antes: /120.d0
FN1=FN1+(-F00X*XDUMM**6*inv720)    ! antes: /720.d0
```

`/2.d0` se deja igual (ya es gratis). `/norm6` se deja igual (varía por átomo, sin redundancia).

## 5. Verificación

Mismo protocolo: pipeline completo, 4 semillas (11, 97, 42, 777), `conf.20.00.HH` fresco, comparado contra la producción con todos los cambios anteriores ya aplicados. **Bit a bit idéntico en las 4 semillas** — `diff` completo sin ninguna línea de física distinta, binarios genuinamente distintos.

## 6. SFU y ciclos

| | `RCP64H` |
|---|---|
| `He_dihydrogen_dispersion` antes | 5 |
| `He_dihydrogen_dispersion` después | **1** |

| Métrica (`k_vpot_3warp_t`) | Antes | Después | Cambio |
|---|---|---|---|
| Instrucciones XU dinámicas | 57.894 | 52.854 | −8,7% |
| Ciclos | 2.688.897 | 2.655.935 | −1,2% |

Modesto en términos absolutos porque `FN1` solo se llama una vez por átomo (no en un bucle interno como `duhe4x`), pero real y sin ningún coste añadido.

## 7. Decisión

**Se lleva a producción** (bit a bit idéntico en 4 semillas). Aplicado a `hibrido_instrumentado/He_dihydrogen.f`, recompilado y verificado desde config fresca.

## Ficheros

- Verificación hecha directamente sobre copias de `hibrido_instrumentado/` — no persistida (quedó en `/tmp`, no en el repo).
