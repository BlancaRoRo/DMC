# Alineación de la semilla del walker 1 entre CPU y GPU

## Objetivo

Verificar que, con un solo walker (N=1), la GPU produce exactamente el
mismo resultado que la CPU original (mismo `conf.20.00.HH`, mismo
`in.mcv`) -- la comparación más limpia posible, sin efectos de
concurrencia entre streams, divergencia entre warps ni coalescencia de
memoria entre walkers distintos.

## Hallazgo: CPU y GPU no coincidían ni con N=1

Primera prueba (sin cambios): CPU (`opcion=4`) da `-639.0137471270 meV`,
GPU (`opcion=7`) da `-634.8052626235 meV` tras 5 pasos -- divergen desde
el primer paso, pese a partir del mismo `conf`/semilla de selección de
configuración inicial (esa parte sí coincidía: mismo walker elegido,
misma energía de partida).

### La causa: un avance de más en la GPU

Ambos árboles comparten el mismo código de arranque:

```fortran
! qmccluster.f90:31 -- IDENTICO en CPU y GPU
call compruebatodos          ! solo LEE y muestra la semilla, no la toca

! mmontecarlo.f90:657 -- IDENTICO en CPU y GPU
call distribuyesemillas      ! avanza la semilla UNA vez (rand1p) y la fija
```

Hasta aquí, CPU y GPU hacen lo mismo -- la semilla ya viene avanzada una
vez cuando arranca el walker 1. Pero la GPU tiene un paso extra que la
CPU no tiene:

```fortran
! msteps.f90:171-174 -- SOLO en GPU
call sacasemilla(irnmaster)                    ! lee la semilla YA avanzada
call k_split_seeds<<<...>>>(2*nwalkers, irnmaster, irn_walkers_d)
                                                 ! avanza OTRA VEZ, iw veces
```

`k_split_seeds` (`rand_gpu.cuf`) calculaba la semilla del walker `iw`
como "maestra avanzada `iw` veces vía `rand1p`" -- para `iw=1`, eso es
**un avance más** encima del que ya hizo `distribuyesemillas`. El walker
1 de la GPU usaba, en la práctica, la semilla que en el reparto
secuencial de la CPU le correspondería al walker 2.

### Por qué no se puede simplemente "usar el walker 2 de la CPU"

La CPU no deriva la semilla del walker N con ninguna fórmula fija --
`iniwalkers` (`mmontecarlo.f90:409-478`) simplemente sigue consumiendo la
MISMA racha de números aleatorios donde la dejó el walker anterior
(`call gauss3(gvar3)` dentro del bucle `do iwalker=1,nwalkers`, sin
ningún reinicio de semilla entre walkers). El walker 2 de la CPU arranca
en el punto exacto donde terminaron los sorteos del walker 1, que
depende de cuántos números consumió -- no es "maestra avanzada 2 veces".
GPU (`k_split_seeds`) SÍ usa una fórmula fija e independiente por diseño
(necesaria para poder calcular cada walker en paralelo sin saber cuánto
consumieron los demás). Son dos esquemas incompatibles más allá del
walker 1 -- el único punto donde SÍ hay una comparación limpia posible,
porque no hay ningún walker anterior cuyo consumo haya que igualar.

## El cambio

`rand_gpu.cuf`, `k_split_seeds`: `(iw)` avances de `rand1p_gpu` →
`(iw-1)` avances.

```fortran
! ANTES:
do i = 1, iw
  call rand1p_gpu(rn, irn)
enddo

! DESPUES:
do i = 1, iw-1
  call rand1p_gpu(rn, irn)
enddo
```

El walker 1 pasa a usar `irnin` tal cual (0 avances de más, igual que la
CPU). Cada walker posterior recibe la semilla que antes tenía el walker
anterior -- mismo conjunto de `2*nwalkers` semillas bien separadas entre
sí (ninguna se pierde ni se repite), solo desplazado una posición. No
cambia la calidad estadística del reparto, solo qué walker concreto usa
cada semilla del conjunto.

## Verificación

**N=1, GPU vs CPU** (mismo `conf.20.00.HH`, semilla 11, 5 pasos):

| | Antes del cambio | Después del cambio |
|---|---|---|
| CPU (`opcion=4`) | -639.0137471270 meV | -639.0137471270 meV |
| GPU (`opcion=7`) | -634.8052626235 meV (NO coincide) | **-639.0137471270 meV (coincide)** |

Bit a bit idéntico tras el cambio.

**2000w** (semilla 11, 1200 pasos) -- confirma que la simulación sigue
siendo válida a escala normal, sin esperar coincidencia bit a bit con CPU
(los esquemas son incompatibles más allá de N=1, ver arriba):

- Energía: `-676.8178220759 meV` (antes del cambio, producción daba
  `-676.2974256246 meV`) -- diferencia de 0,52 meV, muy por debajo del
  error estadístico (±1,84-2,00 meV) -- misma física, distinta muestra
  concreta de la misma distribución, como se espera al desplazar qué
  semilla usa cada walker.
- Población final: 2000 = población inicial. Sin errores.

## Conclusión

Cambio verificado, correcto, de bajo riesgo -- alinea el walker 1 de la
GPU con el walker 1 de la CPU (la única comparación bit a bit posible
entre los dos esquemas), sin alterar la validez estadística de la
simulación a escala normal.

**Migrado a producción** (`v2-cuda-integracion/hibrido_instrumentado/rand_gpu.cuf`).
Reverificado tras migrar: N=1 sigue coincidiendo bit a bit con CPU
(`-639.0137471270 meV`), 2000w sigue dando el mismo resultado que la
copia aislada (`-676.8178220759 meV`, población conservada, sin
errores).

**Nota para quien compare contra resultados anteriores de esta sesión**:
a partir de este cambio, la energía de referencia a 2000w/semilla 11
pasa de `-676.2974256246 meV` (valor usado en todas las pruebas
anteriores del árbol, con el reparto de semillas antiguo) a
`-676.8178220759 meV` (nuevo reparto, alineado con CPU). Ambos valores
son física válida (misma distribución, dentro de 1σ) -- el cambio no
invalida ninguna de las comparaciones anteriores de rendimiento (todas
comparaban el mismo binario contra sí mismo con distintas
optimizaciones), pero el valor absoluto de energía "de referencia" ya
no es el mismo si se compara contra pruebas de antes de este cambio.

## Ficheros

- `gpu-semilla-alineada/`: **recortada** a `rand_gpu.cuf` (el cambio,
  `k_split_seeds`), `in.mcv` y `tiempos_opcion7.dat` -- ya no es copia
  completa (el cambio ya está en producción, así que `rand_gpu.cuf` de
  esta copia hoy coincide con el de `hibrido_instrumentado`).
- `compilar_semilla_alineada.sh`: referencia de qué `FILES` se usaban.
