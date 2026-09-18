# Fusionar fases secuenciales del grafo: `k_fase_c`+`k_fase_d` y `k_fase_f`+`k_fase_g`+`k_fase_h`

Diagrama interactivo del pipeline completo ya con esta fusión aplicada, con el
recorrido de cada variable entre CPU y GPU: [`pipeline-cpu-gpu.html`](pipeline-cpu-gpu.html)
(ábrelo en el navegador).

## 1. Objetivo

Pregunta del usuario: `k_fase_c`→`k_fase_d` y `k_fase_f`→`k_fase_g`→`k_fase_h` son ya secuenciales (sin ninguna horquilla entre medias) — ¿no sería más rápido fusionarlas en un único kernel/nodo del grafo, en vez de mantenerlas separadas?

No hay ningún motivo de corrección que lo impida: cada fase trabaja un hilo = un walker, sin ninguna dependencia entre walkers (salvo los `atomicAdd` de `k_fase_h`, que siguen siendo seguros fusionados o no). El motivo real para probarlo: cada vez que una fase escribe un valor pequeño (`activo(i)`, `nsons(i)`) y la fase siguiente lo vuelve a leer, ese valor hace un viaje de ida y vuelta por memoria global de la GPU sin necesidad -- fusionando, se queda en un registro del propio hilo.

## 2. Diseño

Dos kernels nuevos, cuerpo idéntico a los originales, mismo orden aritmético exacto -- sin cambiar ninguna fórmula:

### `k_fase_cd` (sustituye a `k_fase_c` + `k_fase_d`)

```fortran
! ANTES: 2 kernels, "activo" viaja por memoria global entre ambos
call k_fase_c<<<...>>>(nmax, wf_p, wfold_p, kin_p, pot_p, ene_p, activo_p)
call k_fase_d<<<...>>>(nmax, atom_p, sprop_p, hb2m_p, b_p, dwf_p, dphi_p, activo_p)

! DESPUES: 1 kernel, "activo" se queda en un registro (activo_l) para la
! parte D -- pero SI se sigue escribiendo activo(i) al final, porque
! k_fase_f (en otro nodo del grafo, tras la 2a horquilla) todavia lo
! necesita como entrada.
call k_fase_cd<<<...>>>(nmax, wf_p, wfold_p, kin_p, pot_p, ene_p, &
               atom_p, sprop_p, hb2m_p, b_p, dwf_p, dphi_p, activo_p)
```

### `k_fase_fgh` (sustituye a `k_fase_f` + `k_fase_g` + `k_fase_h`)

```fortran
! ANTES: 3 kernels, "activo" viaja f->g, "nsons" viaja g->h
call k_fase_f<<<...>>>(nmax, wf_p, wfold_p, kin_p, pot_p, ene_p, activo_p)
call k_fase_g<<<...>>>(nmax, eold_p, ene_p, irn_p, activo_p, nsons_p)
call k_fase_h<<<...>>>(nmax, atom_p, sprop_p, nsons_p, h44_p, ...)

! DESPUES: 1 kernel. "activo" ya NO necesita tocar memoria global en
! absoluto -- nada despues de esta fase lo vuelve a leer (confirmado:
! ni k_fase_a del paso siguiente lo recibe como argumento). "nsons" SI
! se sigue escribiendo (la CPU lo lee de vuelta para el reparto), pero
! la lectura que antes hacia k_fase_h por separado ahora es un registro.
call k_fase_fgh<<<...>>>(nmax, wf_p, wfold_p, kin_p, pot_p, ene_p, activo_p, &
               eold_p, irn_p, nsons_p, atom_p, sprop_p, h44_p, ...)
```

`k_fase_c`/`k_fase_d`/`k_fase_f`/`k_fase_g`/`k_fase_h` se dejan intactas en el fichero, sin usar -- mismo criterio de referencia que el resto del árbol (`k_vpot_t` junto a `k_vpot_3warp_t`, `derananum_mod.cuf` junto a `derananum_split_mod.cuf`).

## 3. Verificación

**Bit a bit** (`opción 7`, config real: 1000 walkers, 100 bloques, 100 pasos/bloque = 10.000 pasos DMC, `conf.20.00.HH` fresco, `etrial=-631.8` verificado):

| | Sin fusionar (producción actual) | Fusionado |
|---|---|---|
| Energía final de las configuraciones | −615,5737694990 | −615,5737694990 (idéntica) |
| Walkers finales | 1000/1000 | 1000/1000 |

**Reloj de pared** (3 repeticiones cada uno, mismo `in.mcv`, sin nada más corriendo en la GPU):

| Repetición | Sin fusionar | Fusionado |
|---|---|---|
| 1 | 54,96 s | 55,11 s |
| 2 | 56,50 s | 54,30 s |
| 3 | 54,41 s | 54,36 s |
| **media** | **55,29 s** | **54,59 s** |

La diferencia (~1,3%) queda dentro del ruido de sistema a esta escala (10.000 pasos, ~55 s de corrida) -- no es una medida concluyente por sí sola.

**`ncu`, duración real por kernel** (sin ruido de reloj de pared, 6 lanzamientos medidos de cada uno, misma escala):

| Kernel | Duración media | Registros/hilo |
|---|---|---|
| `k_fase_c` | 3,81 µs | 32 |
| `k_fase_d` | 26,35 µs | 46 |
| `k_fase_f` | 4,55 µs | 32 |
| `k_fase_g` | 6,18 µs | 30 |
| `k_fase_h` | 199,34 µs | 94 |
| **suma (c+d+f+g+h)** | **240,22 µs** | -- |
| `k_fase_cd` | 27,21 µs | 46 |
| `k_fase_fgh` | 203,62 µs | 94 |
| **suma (cd+fgh)** | **230,83 µs** | -- |

## 4. Interpretación

- **Correcto**: bit a bit idéntico, en la configuración real de producción.
- **Real, medido con `ncu`**: **−9,39 µs por paso** en la parte fusionada (240,22→230,83 µs, un −3,9% de esa porción concreta del pipeline) -- consistente con eliminar el viaje de `activo`/`nsons` por memoria global entre kernels que antes eran nodos separados del grafo.
- **Sin coste de registros**: `k_fase_cd` usa 46 registros/hilo -- exactamente los mismos que ya necesitaba `k_fase_d` sola (la parte C, más ligera, no sube el pico). `k_fase_fgh` usa 94 -- los mismos que ya necesitaba `k_fase_h` sola. La fusión no empeora la ocupación en ningún caso, porque el pico de registros del kernel fusionado lo marca siempre la fase más pesada, no la suma de las tres.
- **Por qué el reloj de pared no lo muestra claramente**: 9,39 µs/paso es una cantidad real pero pequeña frente al resto del paso (`k_fase_a` sola ya son 174 µs, y las horquillas de `derananum`/`vpot` son varios cientos de µs más) -- en una corrida de 10.000 pasos esto son ~94 ms de ahorro total, muy por debajo del ruido de sistema (~1-2 s) que se ve en el reloj de pared a esta escala. Hace falta la medición de `ncu` (determinista, sin ruido) para verla con claridad.

## 5. Decisión

**Aplicado a producción.** Es una mejora real, verificada bit a bit, sin ningún coste de registros ni de ocupación -- el mismo criterio que ya se aplicó a la línea de recíprocos (`reciprocos-k-fase-h-sth.md`, una mejora de magnitud parecida, −1,3% de ciclos, también aplicada pese a ser pequeña). No es la palanca más grande del pipeline (esa sigue siendo `derananum`/`vpot`), pero es gratis: no hay ningún escenario en el que fusionar estas fases concretas empeore algo.

## Ficheros

- `dmc2_pipeline.cuf`: `k_fase_cd` y `k_fase_fgh` añadidas; llamadas del grafo (`inicializa_pipeline`) actualizadas para usarlas; `k_fase_c`/`k_fase_d`/`k_fase_f`/`k_fase_g`/`k_fase_h` sin tocar, como referencia.
- Copia de prueba aislada: `/tmp/verif_fusion_fases/` (no persistida).
