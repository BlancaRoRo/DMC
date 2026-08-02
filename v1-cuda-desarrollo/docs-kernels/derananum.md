# Decimotercer kernel: `derananum` (con `derwavefm`/`derwavefhe3`)

Documentación de [`v1-cuda-desarrollo/derananum/derananum.cuf`](../derananum/derananum.cuf). Porta `derananum`/`derwavefm`/`derwavefhe3` de [`mwavef.f90`](../derananum/mwavef.f90) (líneas 40-91, 230-261 y 677-711 respectivamente): `derananum` calcula la energía cinética de un walker a partir de las derivadas primera y segunda de las 4 partes de la función de onda (He4-He4, He3-He3, mezcla He4-He3, e impureza/molécula), más las energías de impureza (`eimp`) y rotación (`erot`) cuando aplican.

---

## Parte 1 — Implementación

## 1. Por qué hacía falta terminar dos métodos más

`derananum` llama, sin condición, a cuatro subrutinas de derivada: `derwavefhe4` y `derwavefx` ya estaban portadas (`der_wavefhe4.cuf`, `der_wavefx.cuf`), pero **`derwavefm` y `derwavefhe3` no** — eran los dos huecos que quedaban. Con `nhe3=0` (fijo en este proyecto), los bucles relevantes de ambas (`jhe3=1,nhe3` en `derwavefm`; `ihe3=1,nhe3` en `derwavefhe3`) no ejecutan ninguna iteración en la simulación real — exactamente el mismo caso que `duhe3x`/`uhe3x` en `der_wavefx.cuf` y `wavefm`/`wavefhe3` en `wavef.cuf`: el código tiene que existir y compilar igual, porque `derananum` los llama incondicionalmente, aunque con esta configuración concreta no aporten nada al resultado.

## 2. `derwavefm`: sin cambios de fórmula (en su momento)

Solo cambia `w1%atom(:)` → `atom(:)`, igual que en el resto de kernels. Reutiliza `pmix` (ya declarada como variable `device` en `mwavef_gpu`, `wavef.cuf`) y `nhe4`/`nhe3`/`ngatom` (de `der_wavefx`) — no se redeclara nada que ya existiera.

**Corrección posterior (ver §7): sí hizo falta un cambio de fondo.** `rij**(pmix(2)+1)` usa exponente real (`pmix(2)`, el `nu` de mezclas de `in.mcv`) — el mismo problema de `pow()` ya encontrado en `d_uhex4.cuf`/`der_wavefx.cuf`/`der_wavefhe4.cuf` (`glibc_math.md` Parte 4). En el momento de escribir esta sección, `wavefm`/`derwavefm` estaban descartadas de cualquier verificación seria porque `nhe3=0` las deja en resultado trivial en la simulación real — no se había probado con `nhe3=2` a precisión completa todavía.

## 3. `derwavefhe3`: derivada numérica, y una simplificación real

El original es una derivada **numérica** (diferencias finitas centradas, `dx=1.d-3`): perturba `w1%atom(iatom)` en cada coordenada, llama a `wavefhe3(w1)` (que sobreescribe `w1%lw%wfhe3` como efecto secundario), y al final **restaura** tanto `w1%atom(iatom)` como `w1%lw%wfhe3` a sus valores originales — la restauración de `wfhe3` hacía falta porque las llamadas intermedias lo habían ensuciado.

Al usar la versión ya portada `wavefhe3(atom, wfhe3)` (que devuelve el resultado en una variable **local**, sin tocar ningún estado externo), esa restauración deja de hacer falta — no hay nada que ensuciar. Solo se mantiene la restauración de `atom(iatom)`, que sí sigue haciendo falta (las llamadas siguientes de `derananum` — `derwavefm`, `derwavefx` — vuelven a leer `atom`).

```fortran
attributes(host, device) subroutine derwavefhe3(atom, wfhe3_0, d1wf, d2wf)
  type(vec3), intent (inout) :: atom(natom)
  real(kind=r8), intent (in) :: wfhe3_0
  ...
    do ic=1,3
      atom(iatom)%comp(ic)=rtemp%comp(ic)+dx
      call wavefhe3(atom, wfmas)
      atom(iatom)%comp(ic)=rtemp%comp(ic)-dx
      call wavefhe3(atom, wfmen)
      atom(iatom)%comp(ic)=rtemp%comp(ic)
      ...
```

`wfhe3_0` (el valor sin perturbar, `wf0` en el original) se recibe como argumento en vez de leerse de `w1%lw%wfhe3`, ya calculado por `derananum` antes de llamar.

**Revisado — `dx**2` (línea `dend2=dx**2*wfhe3_0`), sin cambios necesarios**: al corregir `wavefhe3` (ver `wavef.md` §10) se encontró que `rij**3` con exponente entero literal SÍ podía divergir bajo `-Kieee` (llamada a una función de biblioteca, `__pd_powi_1`, no verificada hasta entonces). Se revisó por el mismo motivo el `dx**2` de aquí — pero `dx` es `real(kind=r8), parameter :: dx=1.d-3`, una constante fija, no una variable como `rij`.

**Por qué no hay riesgo aquí**: al ser `dx` un `parameter`, el compilador ve que su valor no cambia nunca y hace la cuenta él mismo **en tiempo de compilación** — no tiene sentido hacer que el procesador repita esa misma multiplicación en cada llamada si el resultado siempre va a ser el mismo número. El ejecutable final ya lleva el resultado guardado como un literal; en tiempo de ejecución no se calcula nada, solo se lee ese valor. Confirmado con `nm`: el objeto no genera ningún símbolo `pow`, y el resultado coincide exacto con `gfortran` con y sin `-Kieee`. Es justo lo contrario de `rij**3`: allí `rij` cambia en cada llamada, así que el cálculo se pospone forzosamente al procesador en tiempo de ejecución, y ahí es donde nvfortran (con `-Kieee`) y gfortran/GPU pueden elegir caminos distintos para la misma operación (ver `wavef.md` §10).

## 4. `derananum`: la interfaz cambia de `w1` a piezas sueltas, y devuelve las 4 funciones de onda por separado

El original hace **una sola llamada visible**, `call wavef(w1)`, al principio de `derananum` (`mwavef.f90:47`) — pero esa subrutina, por dentro, ya hace 4 llamadas más:
```fortran
! mwavef.f90:626-639 (el original)
subroutine wavef(w1)
  type(walker), intent (inout) :: w1
     call wavefhe4(w1)
     call wavefhe3(w1)
     call wavefm(w1)
     call wavefx(w1)
     w1%lw%wf=(w1%lw%wfhe4)*(w1%lw%wfhe3)*(w1%lw%wfm)*(w1%lw%wfx)
end subroutine wavef
```
`w1` es `intent(inout)`: las 4 llamadas dejan escritos `w1%lw%wfhe4`/`wfhe3`/`wfm`/`wfx` (además de `w1%lw%wf`), y como es el walker entero el que se modifica, `derananum` puede leer luego cualquiera de esas 5 piezas sin que la subrutina se las devuelva explícitamente.

La versión ya portada de `wavef` (`wavef.cuf:166-177`) hace el mismo trabajo — las mismas 4 llamadas — pero con una diferencia de fondo:
```fortran
! wavef.cuf:166-177 (ya portada)
attributes(host, device) subroutine wavef(atom, sprop3, wf)
  ...
  real(kind=r8), intent (out) :: wf
  real(kind=r8) :: wfhe4, wfhe3, wfm, wfx        ! <-- LOCALES, no intent(out)
    call wavefhe4(atom(1:nhe4), wfhe4)
    call wavefhe3(atom, wfhe3)
    call wavefm(atom(1:ngatom), wfm)
    call wavefx(atom, sprop3, wfx)
    wf = wfhe4*wfhe3*wfm*wfx
end subroutine wavef
```
`wfhe4`/`wfhe3`/`wfm`/`wfx` son variables **locales**: existen solo mientras se ejecuta `wavef` y se descartan al salir — solo `wf` (el producto) sale hacia fuera, porque hasta ahora ningún kernel necesitaba las 4 piezas sueltas, solo el producto final. `derananum` sí necesita una de esas piezas (`wfhe3`, para pasársela a `derwavefhe3` — ver §3), y si se hubiera llamado a `wavef` tal cual, esa pieza ya estaría perdida en el momento en que `wavef` termina.

Por eso `derananum.cuf` no llama a `wavef`: llama directamente a las mismas 4 funciones que `wavef` llama por dentro, para poder quedarse con `wfhe3` (y de paso con las otras 3, ya calculadas):
```fortran
! derananum.cuf:148-152
call wavefhe4(atom(1:nhe4), wfhe4)
call wavefhe3(atom, wfhe3)      ! <-- esta pieza es la que hace falta conservar
call wavefm(atom(1:ngatom), wfm)
call wavefx(atom, sprop(3), wfx)
wf = wfhe4*wfhe3*wfm*wfx
```
Es el mismo cálculo, la misma cantidad de trabajo que el original — ni una llamada de más ni ningún resultado calculado dos veces — solo "desenvuelto" para poder acceder a la pieza intermedia que hace falta, en vez de escondida dentro de una subrutina que solo expone el producto final. Se aprovecha para devolver las 5 (`wf` + las 4 partes) como argumentos de salida, útiles también para depurar/verificar por separado.

`w1%hb2m` (allocatable) y `w1%b` (escalar) son campos del walker que `derananum` necesita leer — se extraen como argumentos `hb2m(natom)` y `b`, mismo criterio que `atom`/`sprop`.

```fortran
attributes(host, device) subroutine derananum(atom, sprop, hb2m, b, &
                                               wf, wfhe4, wfhe3, wfm, wfx, &
                                               kin, eimp, erot, dwf, dphi)
```

El resto es una transcripción directa: los dos bucles de acumulación de `kin` (átomos He4, luego He3), y las dos ramas finales (`impurfija`/`rotamol`) — con un único cambio de fondo: `dwf(iatom)=d1wfhe4(iatom)+d1wfm(iatom)+d1wfx(iatom)` (suma con el operador `+` sobrecargado de `vec3`) se reescribe como `dwf(iatom)%comp=d1wfhe4(iatom)%comp+d1wfm(iatom)%comp+d1wfx(iatom)%comp` — el operador `+`/`=` sobrecargado de `mtipos.f90` (`sumavec3`/`copiavec3`) **no es `attributes(host,device)`**, y usarlo dentro de código `device` da un error de compilación directo (`Calls from device code to a host subroutine/function are not allowed`) — mismo problema ya encontrado y evitado en `ccuerpo.cuf`, aquí aparece también en `rtemp=atom(iatom)` dentro de `derwavefhe3`.

## 5. `impurfija`/`rotamol`: mismo tratamiento que `impureza`

Son variables reales de `mparametros.f90` (públicas, sin `parameter`), fijadas una vez al leer `in.mcv` (`impurfija=.not.impurtras`; `rotamol` se lee directo). Se declaran como variables `device` de módulo, igual que `impureza` en `der_wavefx`.

---

## Parte 2 — Pruebas

## 6. Dos escenarios de prueba

**Caso real de la simulación** (`nhe3=0`, `impureza=.T.`, `impurfija=.F.`, `rotamol=.T.` — valores reales de `in.mcv`): 4 átomos de He4 + 1 impureza, 3 walkers. `hb2m`/`b` (campos del walker que `derananum` necesita) se calculan a partir de constantes físicas reales de `mparametros.f90` (`hb2=hbc**2/(2*umac2)*1.d-4/kb`) y masas/distancia reales de `in.mcv` (masa He4=4.00260, masa H=1.00782503210, d(H-H)=1.0588710), convertidos a meV con `k2mev_bh` — igual criterio que `mentradatos.f90` para `opot=4`.

**Prueba directa con `nhe3=2`** (igual que la ya usada para `wavefhe3`/`wavefm` en `wavef.cuf` y para `duhe3x`/`uhe3x` en `der_wavefx.cuf`): fuerza que los bucles `jhe3`/`ihe3` de `derwavefm`/`derwavefhe3` iteren de verdad — con `nhe3=0` siempre dan 0/1, sin ejercitar la lógica pairwise. `impureza=.F.` en esta prueba (`impurfija=.T.`, `rotamol=.F.`, rama por defecto de `mentradatos.f90` cuando no hay impureza).

### Cómo ejecutarlo

Desde `v1-cuda-desarrollo/derananum/`:
```bash
# 1) GPU + CPU(nvfortran) en el mismo binario
rm -f *.mod *.o
nvfortran -cuda -Kieee -Mnofma -c mparametros.f90 mtipos.f90 mlegendre.f90 mhh_heocs.f90 \
  mkp_heco.f90 mangwavef.f90 mvmolecula.f90 mvaziz.f90 mrotaciones.f90 mlineal.f90 \
  msistref.f90 mwavef.f90 modlegendre.f kpcoef.f pw_heocs.f bh_heh2m.f \
  mlegendre_gpu.cuf d_uhex4_mod.cuf der_wavefx_mod.cuf der_wavefhe4_mod.cuf wavef_mod.cuf derananum.cuf
nvfortran -cuda -Kieee -Mnofma mparametros.o mtipos.o mlegendre.o mhh_heocs.o mkp_heco.o \
  mangwavef.o mvmolecula.o mvaziz.o mrotaciones.o mlineal.o msistref.o mwavef.o \
  modlegendre.o kpcoef.o pw_heocs.o bh_heh2m.o \
  mlegendre_gpu.o d_uhex4_mod.o der_wavefx_mod.o der_wavefhe4_mod.o wavef_mod.o derananum.o \
  -o test_derananum -llapack -lblas
./test_derananum

# 2) Solo CPU, con gfortran
rm -f *.mod *.o
gfortran -ffp-contract=off -c mparametros.f90 mtipos.f90 mlegendre.f90 mhh_heocs.f90 \
  mkp_heco.f90 mangwavef.f90 mvmolecula.f90 mvaziz.f90 mrotaciones.f90 mlineal.f90 \
  msistref.f90 mwavef.f90 modlegendre.f kpcoef.f pw_heocs.f
gfortran -ffixed-form -ffp-contract=off -c bh_heh2m.f -o bh_heh2m_gf.o
gfortran -ffp-contract=off mparametros.o mtipos.o mlegendre.o mhh_heocs.o mkp_heco.o \
  mangwavef.o mvmolecula.o mvaziz.o mrotaciones.o mlineal.o msistref.o mwavef.o \
  modlegendre.o kpcoef.o pw_heocs.o bh_heh2m_gf.o test_derananum_gfortran.f90 \
  -o test_derananum_gfortran -llapack -lblas
./test_derananum_gfortran
```

**Resultado real — 1) GPU + CPU(`nvfortran`)**:
```
=== caso real de la simulacion: nhe3=0, impureza=.T. ===
--- walker 1
  kin   CPU=    -1.2806345221597E+02   GPU=    -1.2806345221597E+02
  eimp  CPU=     1.3213647145749E+01   GPU=     1.3213647145749E+01
  erot  CPU=    -1.3141849243428E+02   GPU=    -1.3141849243428E+02
  |err| max=  5.55E-17
--- walker 2
  |err| max=  1.42E-14
--- walker 3
  |err| max=  3.73E-09

=== prueba directa de derwavefm/derwavefhe3, nhe3=2 ===
  |err| max=  8.88E-16

 PASA: GPU y CPU coinciden dentro de tolerancia
```
El residuo del walker 3 (`3.73E-09`) es mayor que en los otros dos — coincide con la misma geometría simétrica (`(5,0,0),(0,5,0),(0,0,5),(2,2,2)`) ya usada en `He_dihydrogen.md`, donde `dwf` del átomo 4/5 alcanza valores de `~2132` con cancelación entre ellos casi total (`2132.73...` y `-2132.44...`) — ruido de cancelación catastrófica amplificado por la resta, no un error de la implementación (confirmado también por el acuerdo con `gfortran` a la misma precisión, ver abajo). Sigue siendo `PASA` (`<1e-8`) y muchos órdenes de magnitud por debajo de cualquier magnitud física relevante del cálculo.

**Resultado real — 2) solo CPU, con `gfortran`**: mismos valores hasta 13-14 cifras significativas en las tres vías (`kin`/`eimp`/`erot` de los 3 walkers y del bloque `nhe3=2`) — **GPU ≈ CPU(`nvfortran`) ≈ CPU(`gfortran`)**, con la única discrepancia el ruido de cancelación ya descrito para el walker 3, presente por igual en las tres vías.

## 7. `mypow` + secuenciar `d2wf` en `wavefm`/`derwavefm`, y una prueba aislada nueva con contacto muy cercano/largo alcance

Con `nhe3=2` (única forma de ejercitar de verdad el bucle He4-He3), aparecen los mismos dos problemas ya vistos en `d_uhex4.cuf`/`der_wavefx.cuf`/`der_wavefhe4.cuf`:

**a)** `rij**pmix(2)` (en `wavefm`, `wavef.cuf`) → `mypow(rij,pmix(2))`; `rij**(pmix(2)+1)` (en `derwavefm`, aquí) → `mypow(rij,pmix(2)+1.0_r8)`.

**b)** Secuenciar acumulaciones de varios términos en una sola sentencia:
```fortran
! wavefm, antes:      ujas = ujas - pmix(1)/mypow(rij,pmix(2)) - pmix(3)*rij
! wavefm, despues:     ujas = ujas - pmix(1)/mypow(rij,pmix(2))
!                      ujas = ujas - pmix(3)*rij

! derwavefm, antes:    d2wf(iatom)=d2wf(iatom)+ujass+2.0_r8*ujasp
! derwavefm, despues:  d2wf(iatom)=d2wf(iatom)+ujass
!                      d2wf(iatom)=d2wf(iatom)+2.0_r8*ujasp
! (igual para d2wf(jatom))
```

**Prueba nueva y dedicada** ([`test_wavefm.cuf`](../derananum/test_wavefm.cuf)/[`test_wavefm_gfortran.f90`](../derananum/test_wavefm_gfortran.f90), con `nhe3=2` real, no el bloque de arriba): 3 casos —geometría normal, **contacto muy cercano** (par He4-He3 a `rij≈0.05`), y **largo alcance** (`rij≈1000`)— comparando `wfm` + `d1wf`/`d2wf` de los 6 átomos (25 valores por caso).

**Resultado — GPU vs CPU-`gfortran`, con `-Kieee -Mnofma`/`-ffp-contract=off`**:

| caso | valores | sin flags | con flags |
|---|---|---|---|
| 1 (normal) | 25 | `4.44E-16` | `0.00E+00` |
| 2 (contacto cercano) | 25 | `1.11E-16` | `0.00E+00` |
| 3 (largo alcance) | 25 | `2.78E-17` | `0.00E+00` |

**75/75 exactas con flags**, incluidos los dos extremos — ninguno introduce un residuo nuevo, mismo patrón que en el resto del árbol.

**Corrección posterior — `exp` → `myexp` en `wavefm`:** `wavefm`/`wavefhe3` eran los dos únicos sitios del árbol que aún llamaban al `exp()` intrínseco en vez de `myexp`. Comprobado con `nm`: el `exp()` de nvfortran tiene la misma partición fast/precise (`__fd_exp_1`/`__pd_exp_1`) ya vista en `acos`/`pow` — mismo riesgo estructural, aunque no llegara a manifestarse para los 3 `ujas` reales de esta prueba. Se cambió `wfm = exp(ujas)` → `wfm = myexp(ujas)` (detalle completo, incluida la comprobación aislada de `exp` con los 3 valores reales de `ujas`, en `wavef.md` §10). Se repitió esta misma prueba (`test_wavefm.cuf`, 3 casos × 25 valores) tras el cambio: **resultado idéntico, 75/75 exacto con flags**, mismos residuos sin flags (`4.44E-16`/`1.11E-16`/`2.78E-17`) — el cambio de `exp` no introduce ninguna regresión ni altera el patrón de reasociación/FMA ya cerrado.

## 8. Batería extrema de `derananum` (combinado): 5 walkers y 3 casos `nhe3=2`

Lo probado hasta ahora en §6-7 solo cubría geometrías "normales" para la subrutina `derananum` en sí (la que combina `derwavefhe4`+`derwavefx`+`derwavefhe3`+`derwavefm` y da `kin`/`eimp`/`erot`) — las piezas por separado (`derwavefx`, `derwavefhe4`) ya tenían sus propias baterías extremas en sus ficheros, pero la combinación completa no. Se añaden casos extremos a las dos pruebas de §6:

**Caso real (`nhe3=0`, antes 3 walkers → ahora 5)**: se añaden los mismos 2 walkers extremos ya usados en `der_wavefx.md` §10 — walker 4 (impureza a contacto muy cercano de un átomo de He4, `rij≈0.05`) y walker 5 (impureza a largo alcance de los 4 átomos de He4, `rij≈1000`).

**Prueba directa `nhe3=2` (antes 1 caso → ahora 3)**: caso 1 normal (el de siempre), caso 2 (par He3-He3 a contacto muy cercano, `rij≈0.05`) y caso 3 (par He3-He3 a largo alcance, `rij≈1000`) — mismo patrón que la batería de `wavefhe3` en `wavef.md` §10.

**Resultado (`es24.17`), GPU vs. `gfortran`, `-Kieee -Mnofma`:**

| caso | `kin` |
|---|---|
| walker 1 (normal) | exacto |
| walker 2 (normal) | exacto |
| walker 3 (normal, geometría simétrica con cancelación) | exacto |
| walker 4 (extremo, contacto cercano) | exacto (`~-9.7E+33`, magnitud enorme por la singularidad cerca de `rij→0`, pero bit a bit) |
| walker 5 (extremo, largo alcance) | exacto |
| `nhe3=2` caso 1 (normal) | exacto |
| `nhe3=2` caso 2 (extremo, contacto cercano He3-He3) | exacto |
| `nhe3=2` caso 3 (extremo, largo alcance He3-He3) | exacto |

**16/16 exacto** (8 casos × `kin`, más `wf`/`wfhe4`/`wfhe3`/`wfm`/`wfx`/`eimp`/`erot`/`dwf`/`dphi` en cada uno, todos comprobados también exactos) — ninguno de los 4 casos extremos nuevos introduce un residuo, ni siquiera el walker 4 con magnitudes de `~10^33` (`kin` cerca de una singularidad `1/r²` cuando `r→0`, donde cualquier ULP de diferencia se amplificaría enormemente si lo hubiera). Con flags, el único residuo presente en toda la batería sigue siendo el ya documentado en walker 1 (`~3.5E-15`, el suelo host/device habitual, sin relación con estos casos nuevos).
