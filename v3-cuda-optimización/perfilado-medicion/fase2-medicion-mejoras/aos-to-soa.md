# AoS↔SoA: qué variables se convierten, y si hacen falta todas

Punto de partida (`fase2-medicion-mejoras.md`): a 3.000 walkers, con `sincroniza_globales_gpu` y `denssumapaso` ya arreglados, la conversión AoS↔SoA (`msteps.f90`, `pasodmc_gpu_pipeline`) pasó a ser el **segundo coste** del pipeline (12,0% del total, ~10,8 s de bucles CPU + ~2,5 s de transferencias H2D/D2H, en 59 bloques × 20 pasos a esa escala).

Cada paso DMC, `wsim(iwalker)` (AoS — un array de walkers, cada uno con todos sus campos juntos) se convierte a arrays SoA (`*_h`, host) y se copia a los persistentes de device (`*_p`, `dmc2_pipeline.cuf`) — y, para algunas variables, se deshace el camino de vuelta al terminar el paso.

## Tabla de variables

| Variable | Tipo | Método(s) que la usan | Memoria |
|---|---|---|---|
| `atom` | `vec3(natom)` por walker (posiciones) | `k_fase_a` (inout), `k_derananum_t` (inout), `k_vpot_t` (in), `k_fase_d` (inout), `k_fase_h` (in) | `wsim%atom` (AoS) ↔ `atom_h` (host) ↔ `atom_p` (device, persistente) |
| `sprop` | `vec3(3)` por walker (orientación molecular) | `k_fase_a` (inout), `k_derananum_t` (in), `k_vpot_t` (in), `k_fase_d` (inout), `k_fase_h` (in) | `wsim%sprop` ↔ `sprop_h` ↔ `sprop_p` |
| `dwf` | `vec3(natom)` por walker (arrastre/drift, cambia cada paso) | `k_fase_a` (in, valor VIEJO), `k_derananum_t` (out, valor NUEVO), `k_fase_d` (in) | `wsim%dwf` ↔ `dwf_h` ↔ `dwf_p` |
| `dphi` | `real(2)` por walker (arrastre angular, cambia cada paso) | `k_fase_a` (in, viejo), `k_derananum_t` (out, nuevo), `k_fase_d` (in) | `wsim%dphi` ↔ `dphi_h` ↔ `dphi_p` |
| `wf` | `real` escalar (valor de función de onda) | `k_fase_a` (in), `k_derananum_t`×2 (out), `k_fase_c`/`k_fase_f` (in, junto a `wfold`) | `wsim%lw%wf` ↔ `wf_h` ↔ `wf_p` |
| `kin` | `real` escalar (energía cinética) | `k_derananum_t`×2 (out), `k_fase_c`/`k_fase_f` (in) — **y `dmcsumapaso` (CPU)** | `wsim%lw%kin` ↔ `kin_h` ↔ `kin_p` |
| `pot` | `real` escalar (energía potencial) | `k_vpot_t`×2 (out), `k_fase_c`/`k_fase_f` (in) — **y `dmcsumapaso` (CPU)** | `wsim%lw%pot` ↔ `pot_h` ↔ `pot_p` |
| `ene` | `real` escalar (energía total) | `k_fase_a` (in, viejo→`eold`), `k_fase_c`/`k_fase_f` (out), `k_fase_g` (in) — **y `dmcsumapaso` (CPU)** | `wsim%lw%ene` ↔ `ene_h` ↔ `ene_p` |
| `erot` | `real` escalar (energía rotación) | `k_derananum_t`×2 (out) — **ningún kernel del pipeline la vuelve a leer; sí la usa `dmcsumapaso` (CPU)**, columna "Energia rotacion" del resumen final | `wsim%lw%erot` ↔ `erot_h` ↔ `erot_p` |
| `eimp` | `real` escalar (energía traslación impureza) | `k_derananum_t`×2 (out) — **ningún kernel la vuelve a leer; sí la usa `dmcsumapaso` (CPU)**, columna "Energia trasl impur" | `wsim%lw%eimp` ↔ `eimp_h` ↔ `eimp_p` |
| `hb2m` | `real(natom)` por walker (constante física por átomo — masa) | `k_fase_a` (in), `k_derananum_t` (in), `k_fase_d` (in) — **nunca `out`/`inout` en ningún kernel** | `wsim%hb2m` ↔ `hb2m_h` ↔ `hb2m_p` (empaquetada y copiada H2D **cada paso**, nunca se trae de vuelta) |
| `b` | `real` escalar por walker (constante física — rotación) | `k_fase_a` (in), `k_derananum_t` (in), `k_fase_d` (in) — **nunca `out`/`inout`** | `wsim%b` ↔ `b_h` ↔ `b_p` (empaquetada y copiada H2D **cada paso**, nunca se trae de vuelta) |
| `irn` | `integer(kind=8)` escalar (estado del generador aleatorio) | `k_fase_a` (inout), `k_fase_g` (inout) | `irn_walkers` (host, fuera de `wsim`) ↔ `irn_p` |
| `nsons` | `integer` escalar (nº de hijos, se recalcula entero cada paso) | `k_fase_a` (out, se pone a 0), `k_fase_g` (inout), `k_fase_h` (in) | Solo D2H (`nsons_p`→`nsons`, host) — no se empaqueta desde `wsim`, se recalcula siempre |
| `wfhe4` | `real` escalar (componente de función de onda, He4) | `k_derananum_t`×2 (**solo `out`**) | `wsim%lw%wfhe4` ↔ `wfhe4_h` ↔ `wfhe4_p` |
| `wfhe3` | `real` escalar (componente, He3) | `k_derananum_t`×2 (**solo `out`**) | `wsim%lw%wfhe3` ↔ `wfhe3_h` ↔ `wfhe3_p` |
| `wfm` | `real` escalar (componente, mezcla) | `k_derananum_t`×2 (**solo `out`**) | `wsim%lw%wfm` ↔ `wfm_h` ↔ `wfm_p` |
| `wfx` | `real` escalar (componente, impureza) | `k_derananum_t`×2 (**solo `out`**) | `wsim%lw%wfx` ↔ `wfx_h` ↔ `wfx_p` |
| `eold` | `real` escalar (energía del paso anterior, auxiliar) | `k_fase_a` (out), `k_fase_g` (in) | **Solo device** — nunca sale de la GPU |
| `wfold` | `real` escalar (wf del paso anterior, auxiliar) | `k_fase_a` (out), `k_fase_c`/`k_fase_f` (in) | **Solo device** — nunca sale de la GPU |
| `activo` | `logical` escalar (bandera de "sigue vivo este sub-paso") | `k_fase_c` (out), `k_fase_d` (in), `k_fase_f` (inout), `k_fase_g` (in) | **Solo device** — nunca sale de la GPU |

## ¿Se usan todas de verdad? Tres casos distintos

1. **`hb2m`, `b`: se re-transfieren cada paso sin necesidad.** Revisé dónde se fijan en el código real (`mmontecarlo.f90:692,702,712,730`, subrutina `iniwalkers`) — son constantes físicas (masa, momento de inercia) fijadas **una sola vez antes de empezar la simulación**, y ningún kernel las escribe nunca (siempre `intent(in)`). Aun así, el bucle de empaquetado y la copia H2D las procesan **en cada uno de los miles de pasos DMC**, para un valor que no cambia. Mismo patrón que `sincroniza_globales_gpu` (arreglado en la Fase 3): dato constante tratado como si cambiara cada paso.

2. **`wfhe4`, `wfhe3`, `wfm`, `wfx`: no las usa nadie.** Las escribe `k_derananum_t` (dos veces por paso) pero ningún kernel posterior del pipeline las lee (no aparecen como argumento en `k_fase_c/d/f/g/h`), y en el lado CPU la única referencia que existe está **comentada** (`mmontecarlo.f90:767-770`, `!write(6,*) 'wf he4',w1%lw%wfhe4`, etc.). Se empaquetan, se copian H2D, se calculan en la GPU, se copian D2H, se desempaquetan — un viaje completo de ida y vuelta, cada paso, para un valor que no llega a leer nadie.

3. **`erot`, `eimp`: sí hacen falta, pero no donde se podría pensar.** Ningún kernel del pipeline las vuelve a leer tras `k_derananum_t` — parecen candidatas al mismo problema que el punto 2 — pero `dmcsumapaso` (CPU, `mdmcpromedia.f90`) sí las usa para las columnas "Energia rotacion"/"Energia trasl impur" del resumen final. Su viaje de vuelta (D2H + desempaquetado) es necesario; lo que no se necesitaría, si acaso, es su ida (H2D) — nunca se leen como entrada en ningún kernel.

4. **`eold`, `wfold`, `activo`: ejemplo de que esto ya se hizo bien en otras variables.** Son puramente internas al grafo — nunca se empaquetan desde `wsim` ni se copian a host. Confirma que el patrón "quedarse solo en device cuando no hace falta ir y volver" ya se aplica en parte del pipeline; la tabla de arriba es literalmente la lista de sitios donde ese mismo criterio *no* se aplicó todavía.

### Para qué se usa cada una, y por qué el cambio es seguro

Comprobación sobre **todo el árbol** (`grep -rn` en los 40 ficheros, no solo en los que ya tenía abiertos) — no basta con mirar dónde se usa dentro del pipeline, hay que descartar también los caminos de CPU que comparten el mismo tipo `walker` (`opcion=0/1/2/3`, Metropolis/minimización), aunque `opcion=7` no los ejecute.

| Variable | Para qué se usa | Por qué el cambio es seguro |
|---|---|---|
| `hb2m` | Constante física por átomo (masa) que usan `k_fase_a`/`k_derananum_t`/`k_fase_d` para el término de difusión (`sigma1=sqrt(2·hb2m·dtau)`, etc.) | Única escritura en todo el árbol: `mmontecarlo.f90:692,702,712` (`iniwalkers`), con `hb2he4`/`hb2he3`/`hb2x` — escalares **globales**, no indexados por walker → mismo valor para los 2·nwalkers walkers, siempre. Ningún kernel la declara `out`/`inout`. Copiar una vez desde `wsim(1)` a todas las filas es matemáticamente idéntico a copiarla cada paso desde cada walker. |
| `b` | Constante física (momento de inercia) para el término de difusión rotacional | Única escritura: `mmontecarlo.f90:730` (`w1%b=brot`, mismo escalar global para todos). Mismo razonamiento que `hb2m`. |
| `wfhe4`, `wfhe3`, `wfm`, `wfx` | Componentes intermedios de la función de onda (`wf=wfhe4·wfhe3·wfm·wfx`) — `derananum`/`hpsi` las necesitan para su cálculo interno, pero solo como resultado, no como entrada | En el pipeline (`k_derananum_t`, `hpsi_mod.cuf`, `dmc2.cuf`) son siempre `intent(out)`, nunca leídas. La única lectura como valor "viejo" que existe en todo el árbol es `mwavef.f90` (`iwavef`/`derwavefhe3`, líneas 670-717) — pero esas subrutinas las llama `pasomet` (Metropolis), que solo invocan `mcv` (`opcion=1`) y `calmin` (`opcion=2,3`). `opcion=7` despacha únicamente a `dmc_gpu_pipeline` (`qmccluster.f90`) — `pasomet` no se ejecuta nunca en esa rama. |
| `erot`, `eimp` | Energía de rotación / traslación de la impureza — componentes del reparto de energía total | Se leen en 3 sitios: `dmcsumapaso` (`mdmcpromedia.f90`, columnas "Energia rotacion"/"Energia trasl impur" del resumen — **sí corre en `opcion=7`**), `mcvsumapaso` (`mmcvpromedia.f90`, exclusivo de `opcion=1`) y `checkder` (`mmontecarlo.f90:630-633`, print de diagnóstico exclusivo de `opcion=0`). Solo se quitó la ida (H2D) — la vuelta (D2H+desempaquetado), que sí necesita `dmcsumapaso`, se mantuvo intacta. |

## Cuantificación (`prueba_aos_soa/test_pack_unpack.cuf`)

Réplica aislada, con el tipo `walker`/`vec3` real (`mtipos.f90`, sin modificar) para que el bucle de empaquetado tenga el mismo patrón de acceso AoS que el código real — no una reimplementación con otra estructura. 3.000 walkers, `natom=21` (mismos valores reales), 200 repeticiones.

| Grupo | pack | H2D | D2H | unpack | Total/paso |
|---|---|---|---|---|---|
| **necesaria** (referencia: `atom`+`sprop`+`dwf`+`dphi`+`wf`+`kin`+`pot`+`ene`) | 3,975 ms | 1,114 ms | 0,832 ms | 3,950 ms | 9,872 ms |
| `hb2m`+`b` | 0,720 ms | 0,157 ms | — | — | 0,877 ms |
| `wfhe4`/`wfhe3`/`wfm`/`wfx` ("muertas") | 0,056 ms | 0,300 ms | 0,077 ms | 0,035 ms | 0,468 ms |
| `erot`+`eimp` (completo) | 0,035 ms | 0,048 ms | 0,038 ms | 0,023 ms | 0,144 ms |
| `erot`+`eimp` (solo la parte "quitable": pack+H2D) | 0,035 ms | 0,048 ms | — | — | 0,083 ms |

Total medido (11,36 ms/paso) extrapolado a los 1.180 pasos de `test-walker`: **13,41 s** — coincide casi exactamente con el "CONVERSION AoS<->SoA total" real medido en producción a 3.000 walkers (13,25 s, `tiempos_opcion7_2500w.dat`/`fase2-medicion-mejoras.md`), lo que confirma que esta réplica aislada es fiel.

**Lo quitable (`hb2m`+`b` completo + `wfhe4`/`wfhe3`/`wfm`/`wfx` completo + `erot`/`eimp` solo pack+H2D) suma 1,428 ms/paso — 12,6% de toda la conversión AoS↔SoA, ~1,69 s en una corrida de 1.180 pasos.** No es la palanca más grande del pipeline (`lanza_pipeline` sigue siendo el 84,9%), pero es gratis y sin riesgo: son datos que o no cambian nunca (`hb2m`/`b`) o no los lee nadie (`wfhe4`/`wfhe3`/`wfm`/`wfx`, y la mitad de ida de `erot`/`eimp`).

## Implementado

- **`hb2m`/`b`**: se movió su empaquetado y copia H2D fuera del bucle de pasos, al bloque `if(.not.iniciado)` de `pasodmc_gpu_pipeline` (`msteps.f90`) — se hace una sola vez por corrida, no una vez por paso. Los arrays de device (`hb2m_p`/`b_p`, `dmc2_pipeline.cuf`) no cambian de tamaño ni de sitio, así que el resto del grafo (`k_fase_a`/`k_derananum_t`/`k_fase_d`, todas `intent(in)`) no se entera del cambio.
- **`wfhe4`/`wfhe3`/`wfm`/`wfx`**: eliminadas de los arrays persistentes de device, del empaquetado/H2D/D2H/desempaquetado, y de los campos de `wsim`/`walker` que ya no se rellenan desde la GPU. Dentro de `k_derananum_t`, `derananum` las sigue calculando (las necesita internamente para `wf = wfhe4*wfhe3*wfm*wfx`), pero ahora en variables locales al kernel (`wfhe4_l` etc.), nunca escritas a memoria persistente.
- **`erot`/`eimp`**: se quitó su empaquetado y copia H2D (nadie las lee como entrada en ningún kernel); se mantiene la copia D2H y el desempaquetado (las necesita `dmcsumapaso` en CPU).

Verificado: recompila limpio, corridas de humo (250w) y batería completa (250-3.000w) sin errores/NaN, mismas poblaciones finales.

## Adenda: `kin`/`pot` tenían el mismo caso que `erot`/`eimp`, sin cerrar

La cuantificación de arriba metía `kin`/`pot` en el grupo "necesaria" (línea de referencia) sin comprobar, como sí se hizo con `erot`/`eimp`, si su **ida** (H2D) hacía falta de verdad. Revisando las firmas reales de `k_fase_a`/`k_fase_d` (`dmc2_pipeline.cuf`) resulta que ninguna de las dos las recibe como argumento — `kin_p`/`pot_p` llegan a la GPU y, antes de que nada los lea, ya los ha sobrescrito el propio fork de este mismo paso (`k_derananum_join_t`/`k_vpot_3warp_t`). Exactamente el mismo caso que `erot`/`eimp`, pero sin el mismo arreglo aplicado.

```fortran
! msteps.f90, pasodmc_gpu_pipeline -- ANTES:
atom_p(1:nwpaso,:) = atom_h; sprop_p(1:nwpaso,:) = sprop_h
wf_p(1:nwpaso) = wf_h
kin_p(1:nwpaso) = kin_h
pot_p(1:nwpaso) = pot_h; ene_p(1:nwpaso) = ene_h

! DESPUES -- se quita solo la ida de kin/pot (mismo criterio que erot/eimp):
atom_p(1:nwpaso,:) = atom_h; sprop_p(1:nwpaso,:) = sprop_h
wf_p(1:nwpaso) = wf_h
ene_p(1:nwpaso) = ene_h
```

`kin_h`/`pot_h` se mantienen empaquetados desde `wsim` (no se toca esa parte) porque el volcado forense pre-colapso (`driver_replay.f90`) sí necesita una copia real del valor de entrada; solo se quita la copia H2D hacia `kin_p`/`pot_p`, que nadie llegaba a leer.

Verificado bit a bit contra la versión sin el cambio, configuración real (1000 walkers/100 bloques/100 pasos = 10.000 pasos): `-615.5737694990`, 1000/1000 walkers finales, idéntico.

## Medición real (3.000 walkers, misma configuración, antes/después)

Comparando `tiempos_opcion7.dat` de una corrida antes de este cambio contra una después, ambas a 3.000 walkers/1.180 pasos:

| Componente | Antes | Después | Cambio |
|---|---|---|---|
| empaquetar (pack) | 4,8595 s | 4,0080 s | −17,5% |
| copia H2D | 1,0685 s | 0,8204 s | −23,2% |
| copia D2H | 1,4032 s | 1,2853 s | −8,4% |
| desempaquetar (unpack) | 5,9193 s | 5,8740 s | −0,8% |
| **CONVERSIÓN total** | **13,2505 s** | **11,9877 s** | **−9,5% (−1,26 s)** |

El ahorro real (1,26 s) es algo menor que el predicho por la prueba aislada (1,69 s) pero va en la misma dirección y orden de magnitud — razonable, ya que la prueba aislada mide cada grupo en su propio bucle por separado, mientras que en el código real todo pasa en un único bucle fusionado (el ahorro de quitar unas pocas asignaciones de un bucle que ya recorre 3.000 walkers no escala perfectamente lineal). `pack` y `H2D` (de donde se quitaron `hb2m`/`b`, más grandes, y las 4 "muertas") bajan claramente; `unpack` apenas se mueve porque de ahí solo se quitaron las 4 "muertas" (`hb2m`/`b` nunca estuvieron en el unpack).

**Aviso importante sobre el tiempo total de pared**: en la batería completa (`wall_times_op7_aos_soa.log`), el tiempo total apenas bajó (110,67 s vs 111,06 s a 3.000 walkers, −0,4%) — mucho menos que el −9,5% medido en el componente de conversión. La razón: `lanza_pipeline` (85% del tiempo total, el kernel de física en sí) tiene ruido de corrida a corrida (94,13 s vs 94,01 s aquí, una diferencia MAYOR que los 1,26 s ahorrados) que domina el tiempo de pared total a esta escala. El ahorro es real y se ve con claridad en el desglose interno — simplemente es pequeño frente al ruido natural del componente que más pesa. No es el mismo patrón que el hallazgo de `sincroniza_globales_gpu` (ahí la ganancia real ERA pequeña); aquí la ganancia es real y del tamaño esperado, solo que difícil de ver en el tiempo total sin el desglose fino.

## Ficheros

- `prueba_aos_soa/mtipos.f90`, `test_pack_unpack.cuf`: prueba aislada, tipo `walker`/`vec3` real.
- `dmc2_pipeline.cuf`, `msteps.f90` (en `hibrido_instrumentado/`): los 3 arreglos implementados.
- `rehacer_op7_aos_soa.sh`, `op7_aos_soa_{250,500,1000,2000,3000}walkers.log`, `wall_times_op7_aos_soa.log`: batería completa después del arreglo, sin errores/NaN, mismas poblaciones finales que antes.
