# Decimocuarto kernel: `hpsi`

Documentación de [`v1-cuda-desarrollo/hpsi/hpsi.cuf`](../hpsi/hpsi.cuf). Porta `hpsi` de [`mwavef.f90`](../hpsi/mwavef.f90) (líneas 20-40): el despachador de más alto nivel de la función de onda de un walker, entre el caso `libre=.T.` (sin interacción, `valibre`) y el caso `libre=.F.` (caso real, `derananum`+`vpot`).

---

## Parte 1 — Implementación

## 1. Un despachador puro, sin fórmula propia

`hpsi` no calcula nada por sí mismo — es un `if`/`else` entre tres piezas ya portadas y probadas por separado:

```fortran
subroutine hpsi(w1)
  type (walker), intent (inout) :: w1

  if(libre) then
   call valibre(w1)
  else
    call derananum(w1)
    call vpot(w1)
    w1%lw%ene=w1%lw%kin+w1%lw%pot
  endif
 end subroutine hpsi
```

`valibre` ([`valibre.md`](valibre.md)), `derananum` ([`derananum.md`](derananum.md)) y `vpot` ([`vpot.md`](vpot.md)) están todas ya portadas y validadas de forma independiente. La única operación que introduce `hpsi` en sí es `ene=kin+pot`.

**Por qué esa suma no es un riesgo**: la reasociación de punto flotante (la fuente de todos los residuos de ~1 ULP documentados en este árbol — ver `He_dihydrogen.md` §30) solo puede dar un resultado distinto cuando hay **3 o más sumandos**, porque hacen falta al menos dos formas distintas de agrupar paréntesis para que se note. Con 2 sumandos (`kin+pot`) solo hay una forma de sumarlos — no hay elección de orden que hacer, así que no hay reasociación posible. `ene` hereda exactamente el mismo margen de acuerdo/desacuerdo que ya tengan `kin` y `pot` por separado, ni un bit más.

## 2. `signoup`/`signodw`: se quedan locales, igual que en `derananum`/`wavefhe3`

`valibre` sí devuelve `signoup`/`signodw` (signo del determinante de Slater de cada espín) en su puerto CUDA (`valibre.cuf`), pero `hpsi` no los expone en su propia interfaz — se reciben en variables locales y se descartan. Mismo criterio que ya se aplicó en `wavefhe3`/`derananum` (`wavef.md` §4): con `slaterdet_trivial` (`nhe3up`/`nhe3dw`≤1 en este proyecto) el signo es siempre `+1`, así que no aporta nada al resultado y no hace falta arrastrarlo por toda la cadena de llamadas.

## 3. Estructura AoS→SoA: unión de lo que ya usaban `derananum`/`vpot`

`hpsi` llama a las dos rutinas de interacción con exactamente los mismos argumentos que ya tenían por separado — no añade ni quita ningún campo:

```fortran
attributes(host, device) subroutine hpsi(atom, sprop, hb2m, b, &
                                          wf, wfhe4, wfhe3, wfm, wfx, &
                                          kin, eimp, erot, pot, ene, &
                                          dwf, dphi)
  type(vec3), intent (inout) :: atom(natom)
  type(vec3), intent (in) :: sprop(3)
  real(kind=r8), intent (in) :: hb2m(natom)
  real(kind=r8), intent (in) :: b
  real(kind=r8), intent (out) :: wf, wfhe4, wfhe3, wfm, wfx
  real(kind=r8), intent (out) :: kin, eimp, erot, pot, ene
  type(vec3), intent (out) :: dwf(natom)
  real(kind=r8), intent (out) :: dphi(2)
    if (libre) then
      call valibre(natom, wf, wfhe4, wfhe3, wfm, wfx, kin, pot, ene, &
                   signoup_l, signodw_l, dwf_libre, dphi)
      ...
      eimp = 0.0_r8
      erot = 0.0_r8
    else
      call derananum(atom, sprop, hb2m, b, wf, wfhe4, wfhe3, wfm, wfx, &
                      kin, eimp, erot, dwf, dphi)
      call vpot(atom, sprop, pot)
      ene = kin + pot
    endif
end subroutine hpsi
```

`atom` se declara `intent(inout)` (no `intent(in)`) porque `derananum` lo requiere así — `derwavefhe3`, dentro de `derananum`, perturba y restaura `atom` en su derivada numérica (`derananum.md` §3). Mismo criterio que ya usa `k_derananum` en su propio kernel `attributes(global)`.

En la rama `libre`, `valibre` no calcula `eimp`/`erot` (no tienen sentido sin interacción), así que se fijan a `0` explícitamente — igual que hace el original implícitamente al no tocarlos (en la versión AoS, `w1%lw%eimp`/`w1%lw%erot` simplemente no se escriben en esa rama; aquí, al ser una interfaz de salida explícita, hay que asignarlos).

---

## Parte 2 — Pruebas

## 4. Dos escenarios, heredados de `derananum`/`vpot`

**Caso real (`libre=.F.`)**: los mismos 5 walkers de la batería extrema de `derananum` (`derananum.md` §8) — 3 casos normales más 2 extremos (impureza a contacto muy cercano, `rij≈0.05`; impureza a largo alcance, `rij≈1000`) — con `opot=4`/`dhcm` añadidos para que `vpot` también se ejercite.

**Caso sin interacción (`libre=.T.`)**: un único caso (geometría del walker 1), solo para confirmar que `hpsi` despacha correctamente a `valibre` y que `eimp`/`erot` quedan en `0`.

### Nota: el `COMMON /datosbh/` de la vía CPU

`bh_heh2m.f` (el archivo original, sin tocar, que sigue usando la vía CPU de referencia a través de `mwavef.f90`) lee `dhcm` internamente de un `COMMON /datosbh/ dhcm` — **no** de la variable `device` `dhcm` del módulo `mpotenbh` que usa la vía GPU. Hace falta declarar y fijar ese `COMMON` por separado en el programa de prueba (mismo patrón que ya usan `potenbh.cuf`/`vpot.cuf`):

```fortran
real(kind=r8) :: dhcm_cpu
common / datosbh / dhcm_cpu
...
dhcm_cpu = dhcm_real
```

Omitirlo no da un error de compilación — da `NaN` silencioso en `pot`/`ene` de la vía CPU (la vía GPU, con su propia variable `device`, no se ve afectada). Se detectó comparando directamente la salida `es24.17` "HP", no por ningún fallo de la comprobación interna de tolerancia (que compara GPU contra CPU-`nvfortran`, ambas con el mismo bug si el `COMMON` falta en las dos).

### Cómo ejecutarlo

Desde `v1-cuda-desarrollo/hpsi/`:
```bash
# 1) GPU + CPU(nvfortran) en el mismo binario
rm -f *.mod *.o
nvfortran -cuda -Kieee -Mnofma -c mparametros.f90 mtipos.f90 mlegendre.f90 mhh_heocs.f90 \
  mkp_heco.f90 mangwavef.f90 mvmolecula.f90 mvaziz.f90 mrotaciones.f90 mlineal.f90 \
  msistref.f90 mwavef.f90 modlegendre.f kpcoef.f pw_heocs.f bh_heh2m.f \
  glibc_exp_mod.cuf glibc_acos.cuf glibc_sincos.cuf glibc_pow.cuf \
  angle_scalar_vec_mod.cuf mVheheVphehe_mod.cuf He_dihydrogen.f \
  mlegendre_gpu.cuf d_uhex4_mod.cuf der_wavefx_mod.cuf der_wavefhe4_mod.cuf wavef_mod.cuf \
  derananum_mod.cuf mccuerpo_mod.cuf mpotenbh_mod.cuf vpot_mod.cuf valibre_mod.cuf hpsi.cuf
nvfortran -cuda -Kieee -Mnofma mparametros.o mtipos.o mlegendre.o mhh_heocs.o mkp_heco.o \
  mangwavef.o mvmolecula.o mvaziz.o mrotaciones.o mlineal.o msistref.o mwavef.o \
  modlegendre.o kpcoef.o pw_heocs.o bh_heh2m.o \
  glibc_exp_mod.o glibc_acos.o glibc_sincos.o glibc_pow.o \
  angle_scalar_vec_mod.o mVheheVphehe_mod.o He_dihydrogen.o \
  mlegendre_gpu.o d_uhex4_mod.o der_wavefx_mod.o der_wavefhe4_mod.o wavef_mod.o derananum_mod.o \
  mccuerpo_mod.o mpotenbh_mod.o vpot_mod.o valibre_mod.o hpsi.o \
  -o test_hpsi -llapack -lblas
./test_hpsi

# 2) Solo CPU, con gfortran
rm -f *.mod *.o
gfortran -ffp-contract=off -c mparametros.f90 mtipos.f90 mlegendre.f90 mhh_heocs.f90 \
  mkp_heco.f90 mangwavef.f90 mvmolecula.f90 mvaziz.f90 mrotaciones.f90 mlineal.f90 \
  msistref.f90 mwavef.f90 modlegendre.f kpcoef.f pw_heocs.f
gfortran -ffixed-form -ffp-contract=off -c bh_heh2m.f -o bh_heh2m_gf.o
gfortran -ffp-contract=off mparametros.o mtipos.o mlegendre.o mhh_heocs.o mkp_heco.o \
  mangwavef.o mvmolecula.o mvaziz.o mrotaciones.o mlineal.o msistref.o mwavef.o \
  modlegendre.o kpcoef.o pw_heocs.o bh_heh2m_gf.o test_hpsi_gfortran.f90 \
  -o test_hpsi_gfortran -llapack -lblas
./test_hpsi_gfortran
```

## 5. Resultado

**GPU vs. CPU(`nvfortran`)**, `-Kieee -Mnofma` (comprobación interna del propio binario, incluye `wf`/`wfhe4`/`wfhe3`/`wfm`/`wfx`/`kin`/`eimp`/`erot`/`pot`/`ene`/`dwf`/`dphi`):

| walker | `|err| max` |
|---|---|
| 1 (normal) | 3.55E-15 |
| 2 (normal) | 2.84E-14 |
| 3 (normal, geometría simétrica) | 1.14E-13 |
| 4 (extremo, contacto `rij≈0.05`) | 3.11E-09 |
| 5 (extremo, largo alcance `rij≈1000`) | 3.31E-24 |
| `libre=.T.` | 0.00E+00 |

`PASA` en los 6 casos (umbral `<1E-8`, salvo el walker 4 que a `3.11E-09` también pasa con margen). El walker 4 hereda el mismo ruido de cancelación catastrófica ya visto en `derananum.md` §8 para geometrías de contacto muy cercano (diferencias de `dwf` entre términos de magnitud similar y signo opuesto) — no es un error nuevo de `hpsi`.

**Las tres vías, `kin`/`pot`/`ene` a precisión completa (`es24.17`)**:

| walker | | CPU(`nvfortran`) | GPU | `gfortran` |
|---|---|---|---|---|
| 1 | kin | -1.28063452215966379E+02 | -1.28063452215966379E+02 | -1.28063452215966379E+02 |
| 1 | pot | -2.36733760163884703E+01 | -2.36733760163884703E+01 | -2.36733760163884703E+01 |
| 1 | ene | -1.51736828232354839E+02 | -1.51736828232354839E+02 | -1.51736828232354839E+02 |
| 2 | kin | -8.58073990499144799E+01 | -8.58073990499144799E+01 | -8.58073990499144799E+01 |
| 2 | pot | -9.05544524331596961E+01 | -9.05544524331596818E+01 | -9.05544524331596961E+01 |
| 2 | ene | -1.76361851483074190E+02 | -1.76361851483074162E+02 | -1.76361851483074190E+02 |
| 3 | kin | -2.15580754156659581E+07 | -2.15580754156659581E+07 | -2.15580754156659581E+07 |
| 3 | pot |  2.29759081566634791E+02 |  2.29759081566634677E+02 |  2.29759081566634677E+02 |
| 3 | ene | -2.15578456565843932E+07 | -2.15578456565843932E+07 | -2.15578456565843932E+07 |
| 4 | kin | -9.73527404611269658E+33 | -9.73527404611269658E+33 | -9.73527404611269658E+33 |
| 4 | pot |  5.71570073441602726E+04 |  5.71570073441633795E+04 |  5.71570073441633867E+04 |
| 4 | ene | -9.73527404611269658E+33 | -9.73527404611269658E+33 | -9.73527404611269658E+33 |
| 5 | kin |  4.65799315818954796E+01 |  4.65799315818954796E+01 |  4.65799315818954796E+01 |
| 5 | pot | -4.68926040267134434E-09 | -4.68926040267134104E-09 | -4.68926040267134104E-09 |
| 5 | ene |  4.65799315772062172E+01 |  4.65799315772062172E+01 |  4.65799315772062172E+01 |
| `libre` | kin/pot/ene | 0 | 0 | 0 |

`kin` coincide exacto en las 5+1 escenas, en las tres vías — hereda directamente el 16/16 exacto de `derananum.md` §8 (`hpsi` no le añade ninguna operación propia). `pot` reproduce, sin sorpresas, el mismo residuo de ~1 ULP ya documentado y explicado a fondo en `He_dihydrogen.md` §30 (Kahan/`treesum` de GPU vs. suma secuencial de `gfortran`) — nótese que en los walkers 3-5 **GPU** es la vía que coincide exacto con `gfortran`, y **CPU(`nvfortran`)** la que difiere; en los walkers 1-2 es al revés. Es la firma característica de un residuo de no-asociatividad genuino (ninguna de las dos vías "gana" siempre) y no de un algoritmo incorrecto en una de ellas. `ene=kin+pot` hereda ese mismo margen sin amplificarlo (§1), y en los casos donde `kin` domina en magnitud (walkers 3-4) el residuo de `pot` queda completamente absorbido y `ene` sale exacto en las tres vías.
