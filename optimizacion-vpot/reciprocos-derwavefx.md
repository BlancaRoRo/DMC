# Recíproco cacheado en el bloque `dnor` de `derwavefx` (y por qué `wavefx` no aplica)

## 1. Objetivo

Siguiendo `mapa-sfu-produccion.md` §4.1, se revisó `derwavefx` (9 `RCP64H` estáticas, marcada como "no visto"). El usuario detectó por inspección visual del código que el bloque `if(impurmol)` divide 3 componentes de un vector por el mismo `dnor` — mismo patrón que `Ex0`/`Ey0`/`Ez0`. También se planteó si `wavefx` (función gemela, calcula el valor en vez de la derivada) tenía la misma oportunidad con `dnor*rij`.

## 2. `derwavefx`: sí hay redundancia real

```fortran
if(impurmol) then
  do ic=1,3
    dnor=sqrt(dot_product(sprop(ic)%comp,sprop(ic)%comp))
    smol(ic)%comp(:)=sprop(ic)%comp(:)/dnor    ! division de vector (3 componentes) por escalar
  enddo
endif
```

Confirmado en SASS **antes** de tocar nada: la línea del `/dnor` genera **3 `MUFU.RCP64H` con el mismo registro divisor**, una por componente (x/y/z) — el compilador no convierte "vector/escalar" en "vector*recíproco" por su cuenta (mismo motivo que en todo el árbol: `-Kieee` prohíbe esa reasociación). Esto se repite en las 3 vueltas de `do ic=1,3` (con un `dnor` distinto cada vez, pero siempre 3 divisiones por ese mismo valor dentro de cada vuelta) → 9 `RCP64H` en total, coincide con el conteo de la tabla.

**El cambio**:
```fortran
do ic=1,3
  dnor=sqrt(dot_product(sprop(ic)%comp,sprop(ic)%comp))
  inv_dnor=1.0_r8/dnor
  smol(ic)%comp(:)=sprop(ic)%comp(:)*inv_dnor
enddo
```

## 3. `wavefx`: NO hay redundancia, confirmado antes de tocar nada

```fortran
if(impurmol) dnor=sqrt(dot_product(sprop3%comp,sprop3%comp))   ! una vez, fuera del bucle
do jatom=1,nhe4
  rij=sqrt(dot_product(rtemp%comp,rtemp%comp))                 ! distinto cada iteracion
  if(impurmol) cth=dot_product(rtemp%comp,sprop3%comp)/(dnor*rij)
  ...
enddo
```

Aunque `dnor` es invariante en el bucle, se divide por el **producto** `dnor*rij` — y `rij` cambia en cada iteración, así que el divisor completo es distinto cada vez. Confirmado en SASS: la línea del `cth=.../(dnor*rij)` genera **una sola `MUFU.RCP64H` por iteración** (dividiendo directamente por el producto ya combinado). Sacar `1/dnor` fuera del bucle no reduciría el número de divisiones (seguiría haciendo falta dividir por `rij` en cada iteración, coste idéntico) — de hecho añadiría una división extra de más (el cálculo de `1/dnor`, hecho una sola vez pero sin ahorrar nada a cambio). **No se toca `wavefx`.**

## 4. Verificación

Mismo protocolo: pipeline completo, 4 semillas (11, 97, 42, 777), `conf.20.00.HH` fresco, comparado contra la producción con todos los cambios anteriores ya aplicados (`funciones-nativas-cuda.md` + `reciprocos-ex0-duhe4x.md` + `reciprocos-k-fase-h.md`):

**Bit a bit idéntico en las 4 semillas** — `diff` completo de los 79 bloques sin ninguna línea de física distinta, binarios genuinamente distintos (`md5sum`).

## 5. SFU y ciclos

| Métrica | Antes | Después | Cambio |
|---|---|---|---|
| `RCP64H` estáticas en `derwavefx` | 9 | **3** | −67% |
| Instrucciones XU dinámicas (`k_derananum_resto_t`) | 43.659 | 43.281 | −0,87% |
| Ciclos (`k_derananum_resto_t`) | 1.782.806 | 1.778.168 | −0,26% |

El impacto dinámico es mucho más modesto que en `duhe4x`/`k_fase_h` — el bloque `dnor` de `derwavefx` solo se ejecuta 3 veces por llamada (`do ic=1,3`), frente a los bucles de `duhe4x` (una vez por átomo de He4) o `k_fase_h` (una vez por par de átomos). Reducción estática grande, dinámica pequeña pero real y sin coste.

## 6. Decisión

**Se lleva a producción** (bit a bit idéntico, sin riesgo). Aplicado a `hibrido_instrumentado/der_wavefx_mod.cuf`, recompilado y verificado desde config fresca.

## Ficheros

- Verificación hecha directamente sobre copias de `hibrido_instrumentado/` — no persistida (quedó en `/tmp`, no en el repo).
