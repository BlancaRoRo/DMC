# ¿Es seguro compilar la orquestación CPU original con `nvfortran`?

Al ensamblar el programa híbrido (`v1-cuda-desarrollo/hibrido/`), todo el código de orquestación de la simulación (lectura de `in.mcv`, generación de la configuración inicial, el bucle de bloques/pasos DMC, estadísticas, densidades) tiene que compilarse con **`nvfortran`** (para poder enlazar en el mismo binario que los kernels CUDA Fortran) — pero ese código, hasta ahora, siempre se había validado usando **`gfortran`** como referencia. Antes de dar por bueno ese cambio de compilador para código que nunca se ha tocado, hacía falta comprobar si `nvfortran`-host reproduce lo mismo que `gfortran` para esta parte — no asumirlo.

## Por qué hacía falta esta prueba (y qué NO comprueba)

Este código de orquestación (`mentradatos`, `mconfiguraciones`, `msteps`, `mdensidades`, ...) **nunca ha tenido ni tendrá nada de GPU** — no hay ningún `attributes(device)` aquí, y no lo habrá. Por eso, el mecanismo de divergencia *garantizado* que ya conocemos de sobra en el resto del árbol (el device de `nvfortran`, vía `libdevice`, usa una implementación de `exp`/`sin`/`cos`/`acos`/`pow` completamente distinta e independiente de `glibc` — motivo por el que existen `myexp`/`mysin`/`mycos`/`myacos`/`mypow`) **no puede aparecer aquí**: no hay ningún device involucrado.

Pero eso no bastaba para dar la orquestación por buena sin comprobarlo, porque hay un **segundo mecanismo, distinto, que sí podía aplicar**: el **host** de `nvfortran` (`libnvcpumath`) es **también** una librería matemática propia, independiente de `glibc` — y ya la hemos visto divergir de `gfortran` en este mismo proyecto, sin que la GPU tuviera nada que ver:
- `dacos` con un ángulo "genérico" (`He_dihydrogen.md`): host-`nvfortran` dio `2.18627603546528393`, distinto de lo que dio `gfortran` para el mismo ángulo.
- `**N` con exponente entero bajo `-Kieee` (`wavef.md` §10): el host a veces resuelve la potencia llamando a una función de librería (`__pd_powi_1`) que puede divergir de cómo lo calcula `gfortran`.

Es decir: **host-`nvfortran` vs. `gfortran` no es una garantía en ningún sentido** — a veces coincide, a veces no, y solo se sabe probando con los valores reales. Como la orquestación usa `**` con exponente real en varios sitios (`phe4(1)=0.5*(bhe4**nuhe4)`, etc. — Prueba 3 más abajo) y un `log()` sin portar (`egrow`, Prueba 2), había una pregunta legítima y sin responder de antemano: ¿coinciden, para los valores físicos reales de este proyecto? Las pruebas de abajo responden que sí, con datos — no que "no podía fallar por no haber GPU" (eso ya se sabía y no era lo que había que comprobar).

Tres pruebas, de menos a más alcance. **Nota importante sobre el alcance de la Prueba 2** (añadida tras revisar el criterio de selección): comparar `egrow`/`etrial` en el bucle DMC es una prueba de extremo a extremo — si CUALQUIER cantidad derivada aguas arriba (masas convertidas a unidades del programa, parámetros `0.5*(b**nu)` de la función de onda, etc.) divergiera, muy probablemente se notaría en `egrow`/`etrial` porque dependen de la energía de cada walker en cada paso. Pero es una inferencia indirecta, no una comprobación directa de cada cantidad — por eso se añadió la Prueba 3, que imprime y compara explícitamente cada cantidad que nace de un cálculo (no de una lectura directa de `in.mcv`) antes de que `dmc2` la use, incluidas las que usan `**` con exponente real (el mismo tipo de operación que en el resto del proyecto ha demostrado poder divergir entre `nvfortran`-host y `gfortran`, motivo por el que existe `mypow`).

---

## Prueba 1: constantes derivadas en tiempo de compilación

**Qué se comparó**: `mparametros.f90` define varias constantes físicas como `parameter`, calculadas a partir de otras constantes literales — el compilador las resuelve en tiempo de compilación, no en tiempo de ejecución. Se aisló esa cadena de cálculo exacta:

```fortran
real(kind=r8), parameter :: pi=3.1415926535897930_r8
real(kind=r8), parameter :: kb=8.6173324d-5
real(kind=r8), parameter :: hbc=197.32697180_r8
real(kind=r8), parameter :: umac2=931.494061_r8
real(kind=r8), parameter :: hb2=hbc**2/(2.0_r8*umac2)*1.d-4/kb
real(kind=r8), parameter :: hb2cm=hbc**2/(2.0_r8*umac2)/(2.0_r8*pi*hbc)*1.d3
real(kind=r8), parameter :: cmtok=2.0_r8*pi*hbc*1.d-7/kb
real(kind=r8), parameter :: k2cm_bh=0.6950_r8
real(kind=r8), parameter :: cm2h_bh=4.556335380d-6
real(kind=r8), parameter :: h2mev_bh=27.20d3
real(kind=r8), parameter :: k2mev_bh=k2cm_bh*cm2h_bh*h2mev_bh
```

**Dónde**: programa mínimo aparte (`/tmp/.../param_check/test_params.f90`, no forma parte del árbol del proyecto — prueba desechable), con estas mismas líneas copiadas literalmente de `mparametros.f90`, imprimiendo `hb2`, `hb2cm`, `cmtok`, `k2mev_bh` con `es24.17`.

**Compilado con**: `gfortran -ffp-contract=off` y `nvfortran -Kieee -Mnofma` (host, sin `-cuda` — este código no tiene nada de CUDA).

**Resultado — idéntico bit a bit en las cuatro constantes**:
```
                gfortran                    nvfortran-host
hb2      =  2.42543684667789421E+01   2.42543684667789421E+01
hb2cm    =  1.68576292014195843E+01   1.68576292014195843E+01
cmtok    =  1.43877695831252894E+00   1.43877695831252894E+00
k2mev_bh =  8.61329640235199839E-02   8.61329640235199839E-02
```

## Prueba 2: el programa de orquestación completo, corrida real

**Qué se comparó**: el programa `qmccluster` **entero**, sin ningún cambio de fórmula (solo un `print` de depuración temporal, ver abajo) — `mparametros`, `mtipos`, `mentradatos` (lectura de `in.mcv`), `mconfiguraciones`/`iniwalkers` (configuración inicial), `msteps` (`pasodmc`/`dmc2`, el bucle DMC), `mdensidades`, `mdmcpromedia`, `mmcvpromedia`, `mserie`, `mmontecarlo`, `mminimiza`. Con especial atención a `egrow`/`etrial` (`msteps.f90:54`): `egrow=etrial-log(nwnew/nwold)/dtau`, señalado como el punto de mayor riesgo porque `etrial` se retroalimenta paso a paso (`etrial=0.50_r8*(etrial+segrow/ncetrial)`) y entra directamente en `dmc2` (`gb=exp(-(0.5*(eold+ene)-etrial)*dtau)`) — si `log()` divergiera aquí entre compiladores, el error no se quedaría aislado, se acumularía en toda la simulación.

**Conjunto de datos usado**: el `in.mcv` de producción real del proyecto (copiado de `ccuerpo/in.mcv`, sin tocar los datos físicos) — 20 átomos de He4, molécula de H2 como impureza, `opot=4` (He-H2⁺), los mismos `b`/`nu`/`alfa` de He4-He4 e impureza-He4 que se han usado en las baterías de prueba de todos los kernels. Solo se cambiaron los parámetros de **tamaño de la corrida** (para que sea rápida de repetir), dos veces:

| parámetro | original (producción) | prueba 1 | prueba 2 |
|---|---|---|---|
| `opcion` | 1 (mcv) | **4 (dmc)** | 4 (dmc) |
| bloques de cálculo | 10 | 2 | 3 |
| pasos por bloque | 1000000 | 5 | 20 |
| número de walkers | 2000 | 10 | **500** |

(`opcion` y "bloques de equilibrio"=1/"pasos para cambiar etrial"=2/10 igual en ambas). La semilla aleatoria (`0000000000000011`) y el resto de datos físicos, sin cambiar.

**Dónde se puso el print**: un único `write` temporal en `msteps.f90`, justo después de calcular `egrow` dentro de `pasodmc` (línea 55 en la copia de prueba, insertada entre `egrow=etrial-log(nwnew/nwold)/dtau` y `segrow=segrow+egrow`):
```fortran
write(*,'(a,es24.17,a,es24.17,a,es24.17)') ' HP nwnew=',nwnew,' egrow=',egrow,' etrial=',etrial
```
Este `write` se añadió **igual, en el mismo sitio**, en dos copias independientes del árbol completo de fuentes (`gf_build/`, `nv_build/` — carpetas de prueba desechables, no forman parte de `hibrido/`), una compilada con `gfortran -ffp-contract=off`, la otra con `nvfortran -Kieee -Mnofma` (host, sin `-cuda`).

**Resultado — 10 walkers** (prueba 1, 11 pasos DMC en total): `diff` entre las dos salidas de `HP nwnew=.../egrow=.../etrial=...` → **0 diferencias**. Coincide también la energía final impresa por el programa (`-615.5737694990`) y las tres tablas de resultados (cinética/potencial/total/rotación/traslación/growth, en meV/K/cm⁻¹).

**Resultado — 500 walkers** (prueba 2, 64 pasos DMC en total, para comprobar que no aparece nada al aumentar la población ni el número de pasos): `diff` entre las 64 líneas de `HP nwnew=.../egrow=.../etrial=...` de las dos vías → **0 diferencias**, otra vez. Primeras y últimas líneas, para que quede constancia:
```
 HP nwnew= 5.00000000000000000E+02 egrow=-6.31799999999999955E+02 etrial=-6.31799999999999955E+02
 HP nwnew= 4.99000000000000000E+02 egrow=-6.11779973293269109E+02 etrial=-6.31799999999999955E+02
 HP nwnew= 5.00000000000000000E+02 egrow=-6.46815020030046981E+02 etrial=-6.26794993323317271E+02
...
 HP nwnew= 5.09000000000000000E+02 egrow=-6.76399795320827479E+02 etrial=-6.76399795320827479E+02
 HP nwnew= 5.10000000000000000E+02 egrow=-6.96026886999314343E+02 etrial=-6.76399795320827479E+02
 HP nwnew= 5.13000000000000000E+02 egrow=-7.35050989844808100E+02 etrial=-6.76399795320827479E+02
```
Energía final de las configuraciones, ambas vías: `-602.5078412333` (idéntica hasta el último dígito impreso).

### Cómo repetirlo

Desde una copia de `ccuerpo/` (o `Original-VapFix/`, con el fix de `Vap`), con `in.mcv` modificado como en la tabla de arriba:
```bash
# gfortran
gfortran -ffp-contract=off -c mparametros.f90 mtipos.f90 mvaziz.f90 mhh_heocs.f90 mkp_heco.f90 \
  mrandom2.f90 mrandom.f90 mvmolecula.f90 mrotaciones.f90 mlineal.f90 msistref.f90 mlegendre.f90 \
  mangwavef.f90 mwavef.f90 modlegendre.f kpcoef.f pw_heocs.f bh_heh2m.f \
  mdensidades.f90 mmcvpromedia.f90 mdmcpromedia.f90 \
  mentradatos.f90 mconfiguraciones.f90 mimagina.f90 mserie.f90 msteps.f90 mmontecarlo.f90 mminimiza.f90 \
  qmccluster.f90
gfortran -ffp-contract=off *.o -o qmccluster_gf -llapack -lblas
./qmccluster_gf < in.mcv > out_gf.txt

# nvfortran (host puro, sin -cuda -- esta parte no tiene nada de CUDA todavia)
nvfortran -Kieee -Mnofma -c <mismos ficheros, mismo orden>
nvfortran -Kieee -Mnofma *.o -o qmccluster_nv -llapack -lblas
./qmccluster_nv < in.mcv > out_nv.txt

diff <(grep "HP nwnew" out_gf.txt) <(grep "HP nwnew" out_nv.txt)
```
(`promedia.f90` es un programa aparte, de post-proceso — no se enlaza con `qmccluster`.)

---

## Prueba 3: cada cantidad derivada de un cálculo, comprobada de forma explícita (no inferida)

La Prueba 2 compara `egrow`/`etrial` de extremo a extremo — si algo aguas arriba divergiera, es muy probable que se notase ahí, pero no es una comprobación directa de cada cantidad. Esta prueba imprime y compara **cada variable que `mentradatos.f90`/`escribedatos` calculan a partir de los datos de `in.mcv`** (no las que simplemente se leen tal cual), antes de que `dmc2` las use — con especial atención a las que usan `**` con exponente real, la operación que en el resto del proyecto (`mypow`, `glibc_pow.cuf`) ha demostrado poder divergir entre bibliotecas.

**Qué se comparó** (todo calculado dentro de `escribedatos`, `mentradatos.f90:377-487`, con los datos reales de `in.mcv`: masa He4=4.00260, masa He3=3.01604, molécula H-H, `opot=4`):

| variable | fórmula | por qué se eligió |
|---|---|---|
| `phe4(1)` | `0.50_r8*(bhe4**nuhe4)` | `**` exponente real (`nuhe4=4.725025`) |
| `phe3(1)` | `0.50_r8*(bhe3**nuhe3)` | `**` exponente real (caso `bhe3=0`, valor trivial pero se comprueba igual) |
| `pmix(1)` | `0.50_r8*(bmix**numix)` | `**` exponente real (caso `bmix=0`) |
| `pxhe4(1,il)`, `il=0..4` | `0.50_r8*(bxhe4(il)**nuxhe4(il))` | `**` exponente real, 5 valores de `nuxhe4` distintos (impureza-He4, polinomios de Legendre) |
| `pxhe3(1,0)` | `0.50_r8*(bxhe3(0)**nuxhe3(0))` | ídem, impureza-He3 |
| `hb2he4`, `hb2he3`, `hb2x` | `hb2/masa`, luego `*k2mev_bh` | división + producto de constantes (sin riesgo por IEEE-754, pero se comprueba igual) |
| `brot` | `hb2/momi`, luego `*k2mev_bh` | `momi` es una suma en tiempo de ejecución (`momi=momi+matmol(iamol)*(zatmol(iamol)-zcm)**2`) — el único caso con una acumulación real, no solo aritmética puntual |
| `momi`, `dtau`, `ratio`, `ncmtras` | leídas/derivadas | control, para descartar cualquier duda |

**Dónde se puso el print**: dos bloques de `write` temporales en `mentradatos.f90` (subrutina `escribedatos`), uno justo después de calcular `phe4`/`phe3`/`pmix`/`pxhe4`/`pxhe3` (tras el `endif` que cierra el bloque `if(namol.gt.0)`, línea ~403), otro justo después de la conversión final a meV (`hb2he4=hb2he4*k2mev_bh`, etc., tras el `write` de "B=hb2/(2*I) en MHz", línea ~488) — mismo criterio `es24.17` de siempre, mismas dos copias independientes (`gfortran -ffp-contract=off` / `nvfortran -Kieee -Mnofma` host, sin `-cuda`).

**Resultado — 500 walkers, mismo `in.mcv`**: `diff` entre las 17 líneas `HP DEBUG ...` de las dos vías → **0 diferencias**. Selección de valores (idénticos en ambas vías, hasta el último dígito):
```
 HP DEBUG phe4(1)= 1.11319629792548241E+02
 HP DEBUG pxhe4(1,0)= 7.93431929060951688E+01
 HP DEBUG pxhe4(1,2)= 1.66022613497800222E+01
 HP DEBUG pxhe4(1,4)= 1.60286061504886779E-02
 HP DEBUG pxhe3(1,0)= 5.00000000000000000E-01
 HP DEBUG hb2he4= 5.21935903303419879E-01
 HP DEBUG hb2he3= 6.92663441652719536E-01
 HP DEBUG hb2x= 1.03644014586997302E+00
 HP DEBUG brot= 3.69758451849447356E+00
 HP DEBUG momi= 5.64990640812417899E-01
 HP DEBUG dtau= 1.00000000000000005E-04
 HP DEBUG ratio= 9.99999999999999955E-08
 HP DEBUG ncmtras=21
```
(`hb2he4`, `hb2x`, `brot` coinciden exactamente con `hb2he4_real`/`hb2x_real`/`brot_real` usados en las baterías de prueba de `hpsi`/`derananum`/`dmc2` — confirma que son los mismos valores físicos reales de producción, no unos inventados para el test.)

## Conclusión

Para el caso de uso real de este proyecto (los parámetros físicos de `in.mcv`, con 10 y con 500 walkers), **no hay ninguna incompatibilidad entre compilar la orquestación con `gfortran` o con `nvfortran`** — ni en las constantes derivadas en tiempo de compilación (Prueba 1), ni en el `log()` sin portar de `egrow`/`etrial` a lo largo de todo el bucle DMC (Prueba 2), ni en ninguna de las cantidades que `mentradatos`/`escribedatos` calculan antes de que `dmc2` las use, incluidas las que usan `**` con exponente real (Prueba 3, comprobación directa, no inferida). Es la misma conclusión ya vista para `gauss3` (`mrandom.md` §7): el riesgo teórico de que `nvfortran`-host y `gfortran` usen bibliotecas matemáticas distintas es real en general, pero para los valores que realmente aparecen en este programa, con estas flags (`-Kieee -Mnofma` / `-ffp-contract=off`), no se ha manifestado — comprobado con datos, no asumido.

Esto no es una prueba exhaustiva para cualquier entrada posible (como el resto de la validación de este proyecto, se basa en los datos reales de uso, no en un barrido exhaustivo del dominio) — pero da la confianza necesaria para seguir con el Paso 4 del plan del híbrido (copiar esta orquestación a `v1-cuda-desarrollo/hibrido/` sin tocarla).
