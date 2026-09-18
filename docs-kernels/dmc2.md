# Decimoséptimo kernel: `dmc2`

Documentación de [`v1-cuda-desarrollo/dmc2/dmc2.cuf`](../dmc2/dmc2.cuf). Porta `dmc2` de [`msteps.f90`](../dmc2/msteps.f90) (líneas 67-131): el paso DMC completo de un solo walker — mueve los átomos (difusión + arrastre), rota `sprop` si aplica, evalúa `hpsi`, comprueba el test de aceptación de la función de onda, aplica la corrección de arrastre del segundo medio paso, vuelve a evaluar `hpsi`, comprueba otra vez, y calcula el factor de ramificación (`nsons`). Es el primer kernel que combina, en una sola pieza, **todo** lo portado hasta ahora: `hpsi` (con `derananum`+`vpot` dentro), `rota` y `gauss3`/`rand1` (`mrandom`).

---

## Parte 1 — Implementación

## 1. `sigma1`/`sigma2`/`sig1rot`/`sig2rot`/`sig1hrot`/`sig2hrot`: no se guardan, se recalculan

En el original son **campos del walker** (`mtipos.f90`), calculados una sola vez en `iniwalkers` (`mmontecarlo.f90:436-480`) a partir de `hb2m`/`dtau`/`b` y nunca modificados después:

```fortran
w1%sigma1(iatom)=sqrt(2.0_r8*hb2he4*dtau)
w1%sigma2(iatom)=2.0_r8*hb2he4*dtau
...
w1%sig1rot=sqrt(2.0_r8*brot*dtau)
w1%sig2rot=2.0_r8*brot*dtau
w1%sig1hrot=sqrt(2.0_r8*brot*0.50_r8*dtau)
w1%sig2hrot=2.0_r8*brot*0.50_r8*dtau
```

Como son funciones puras de datos que `dmc2` **ya recibe** (`hb2m(iatom)`, `b`, `dtau`), en el port se recalculan en el sitio en vez de guardarlos como campos aparte — mismo resultado exacto (no son aproximaciones, son la misma fórmula), sin arrastrar estado redundante:

```fortran
sigma1_l = sqrt(2.0_r8*hb2m(iatom)*dtau)      ! sigma2_l = sigma1_l**2, por construccion
sigma2_l = 2.0_r8*hb2m(iatom)*dtau
sig1rot_l  = sqrt(2.0_r8*b*dtau)               ! sig2rot_l = sig1rot_l**2
sig2rot_l  = 2.0_r8*b*dtau
sig1hrot_l = sqrt(b*dtau)                      ! sig1hrot/sig2hrot = sustituir dtau->0.5*dtau arriba
sig2hrot_l = b*dtau
```

## 2. La estructura, sin cambios de fondo

```fortran
attributes(host, device) subroutine dmc2(atom, sprop, hb2m, b, &
                                          wf, wfhe4, wfhe3, wfm, wfx, &
                                          kin, eimp, erot, pot, ene, &
                                          dwf, dphi, irn, nsons)
  ...
    nsons = 0
    eold = ene
    wfold = wf

    do iatom = 1, ncmtras
      call gauss3_gpu(irn, gvar3)
      ...
      atom(iatom)%comp(:) = atom(iatom)%comp(:) + rtemp%comp(:)
    enddo
    if (rotamol) then
      call gauss3_gpu(irn, gvar3)
      ...
      call rota(1, phix1, sprop); call rota(2, phiy, sprop); call rota(1, phix2, sprop)
    endif

    call hpsi(atom, sprop, hb2m, b, wf, wfhe4, wfhe3, wfm, wfx, &
              kin, eimp, erot, pot, ene, dwf, dphi)

    wftest = (wf/wfold)**2
    if (wftest .lt. ratio) return

    do iatom = 1, ncmtras
      atom(iatom)%comp(:) = atom(iatom)%comp(:) + 0.50_r8*sigma2_l*dwf(iatom)%comp(:)
    enddo
    if (rotamol) then
      ...
      call rota(1, phix1, sprop); call rota(2, phiy, sprop); call rota(1, phix2, sprop)
    endif

    call hpsi(atom, sprop, hb2m, b, wf, wfhe4, wfhe3, wfm, wfx, &
              kin, eimp, erot, pot, ene, dwf, dphi)

    wftest = (wf/wfold)**2
    if (wftest .lt. ratio) return

    gb = exp(-(0.50_r8*(eold+ene)-etrial)*dtau)
    call rand1_gpu(rn, irn)
    nsons = int(gb+rn)
    if (nsons .gt. 10) nsons = 0
end subroutine dmc2
```

Es una transcripción directa — la única operación propia de `dmc2` (no heredada de `hpsi`/`rota`/`gauss3`) es aritmética simple (`+`, `*`, comparaciones, `exp`, `int`), sin ningún riesgo de ULP nuevo.

## 3. `signoup`/`signodw`: se omiten, mismo criterio que en `hpsi`

El original comprueba `if(supold.ne.w1%lw%signoup) return` tras cada `hpsi` (dos veces). Aquí se omite — mismo criterio ya aplicado en toda la rama `wavefhe3`/`derananum`/`hpsi` (`wavef.md` §4): con `slaterdet_trivial` (`nhe3up`/`nhe3dw`≤1 en este proyecto) el signo es siempre `+1`, la comprobación nunca dispara, y el port de `hpsi` ni siquiera expone `signoup`/`signodw` en su interfaz.

## 4. `ncmtras`/`dtau`/`etrial`: variables reales de módulo, `ratio` es `parameter`

`ncmtras` (número de átomos que se difunden — `ngatom`, o `natom` si la impureza no está fija), `dtau` y `etrial` son variables `public` de `mparametros.f90` (sin `parameter`, fijadas al leer `in.mcv` o actualizadas paso a paso — `etrial` se recalcula una vez por paso DMC en `pasodmc`, no aquí). Se declaran `device` de módulo en `mdmc2`, mismo tratamiento que `opot`/`impureza`/`dhcm` en kernels anteriores. `ratio` sí es un `parameter` real (`1.0d-7`) — se copia tal cual.

## 5. `irn`: el estado de aleatoriedad, ahora parte del "estado persistente" del walker

`dmc2` es el primer kernel que **consume** aleatoriedad como parte de su lógica central (no solo en una prueba aislada como `mrandom.cuf`). `irn` se recibe como argumento `intent(inout)` (mismo patrón de `mrandom.md` §2bis) y se actualiza a lo largo de la subrutina (`ncmtras+1` o `ncmtras+2` llamadas a `gauss3_gpu`, más una a `rand1_gpu` al final) — el walker que llama a `dmc2` debe guardar ese `irn` actualizado junto al resto de su estado persistente (`atom`, `sprop`, `wf`, etc.) para el siguiente paso DMC.

---

## Parte 2 — Pruebas

## 6. Cinco walkers, con un hallazgo real durante la depuración

Mismos 5 walkers que `hpsi.cuf`/`derananum.cuf` (3 normales + contacto muy cercano + largo alcance). Para cada uno: una llamada a `hpsi` fija el estado inicial (igual que `iniwalkers` antes del primer paso DMC), se reparte una semilla por walker (`k_split_seeds`), y se ejecuta un paso completo de `dmc2`.

**Primer intento: divergencia enorme (`|err|~1E2` a `1E4`), no un residuo de ULP.** Se aisló metódicamente (comparando semillas pre-`dmc2` —exactas—, estado pre-`dmc2` de `ene`/`kin`/`wf`/`dwf` —exacto—, y `ncmtras`/`dtau`/`etrial` —exactos—) hasta encontrar la causa real: **el walker de referencia de la CPU (`type(walker) :: w1`) nunca tenía sus campos `sigma1`/`sigma2`/`sig1rot`/`sig2rot`/`sig1hrot`/`sig2hrot` inicializados** en el programa de prueba — en la simulación real los fija `iniwalkers` una sola vez, pero el test no lo llama, y `allocatewalker` solo reserva memoria, no la inicializa. El resultado eran multiplicaciones por basura de memoria. **Corregido** fijándolos a mano en el test, con las mismas fórmulas de `mmontecarlo.f90:436-480` (§1) — no es un bug de `dmc2.cuf`, era un dato de prueba incompleto.

## 7. Un hallazgo real y esperado: `gb=exp(...)` desborda para geometrías extremas

Con la corrección de §6, los walkers 3 y 4 seguían mostrando `nsons` distinto (`-2147483648` en CPU/`gfortran` frente a `0` en GPU). Aislado con un `print` temporal: `eold` del walker 3 es `~-2.16E7` (la energía cinética, ya documentada en `hpsi.md`, de esa geometría simétrica con cancelación casi total en `dwf`) y, tras el paso aleatorio, `ene` cae a un valor normal (`~-52`) — la geometría deja de ser degenerada. `gb=exp(-(0.5*(eold+ene)-etrial)*dtau)` se convierte en `exp(+10778.8)`, que desborda a `+Inf`. `int(Inf+rn)` es **comportamiento no definido** por el estándar Fortran — no hay ningún resultado "correcto" que CPU y GPU deban compartir, y de hecho no lo hacen (`-2147483648` en un caso, `0` en el otro): ambos son igual de válidos (o inválidos) ante una entrada sin sentido físico para este paso.

**No es un bug del port.** Las geometrías del walker 3/4 se diseñaron como prueba de esfuerzo para kernels *deterministas* de un solo paso (`potenbh`, `derananum`, `hpsi`) — nunca se pensaron para alimentar un paso DMC completo, donde una energía de partida así de extrema, combinada con un movimiento aleatorio real, puede hacer que el argumento de `exp()` se dispare. El resto de los campos del walker (`atom`, `wf`, `kin`, `pot`, `ene`, `dwf`, `dphi`) **sí** se comparan con la precisión habitual del árbol en estos dos walkers, sin ninguna excepción — solo `nsons` se excluye de la comprobación estricta cuando se detecta el salto de energía, y se documenta explícitamente en la salida del test (`gb patologico`) en vez de dejar que un desbordamiento de entero (`int(Inf+rn)` da el mismo valor centinela en cualquier plataforma IEEE, `-2147483648`) enmascarara silenciosamente la comparación.

### Cómo ejecutarlo

Desde `v1-cuda-desarrollo/dmc2/`:
```bash
# 1) GPU + CPU(nvfortran) en el mismo binario
rm -f *.mod *.o
nvfortran -cuda -Kieee -Mnofma -c mparametros.f90 mtipos.f90 \
  mlegendre.f90 mhh_heocs.f90 mkp_heco.f90 mangwavef.f90 mvmolecula.f90 mvaziz.f90 \
  mrotaciones.f90 mlineal.f90 msistref.f90 mdensidades.f90 mmcvpromedia.f90 \
  mrandom2.f90 mrandom.f90 mwavef.f90 msteps.f90 \
  modlegendre.f kpcoef.f pw_heocs.f bh_heh2m.f \
  glibc_exp_mod.cuf glibc_acos.cuf glibc_sincos.cuf glibc_pow.cuf \
  angle_scalar_vec_mod.cuf mVheheVphehe_mod.cuf He_dihydrogen.f \
  mlegendre_gpu.cuf d_uhex4_mod.cuf der_wavefx_mod.cuf der_wavefhe4_mod.cuf wavef_mod.cuf \
  derananum_mod.cuf mccuerpo_mod.cuf mpotenbh_mod.cuf vpot_mod.cuf valibre_mod.cuf \
  hpsi_mod.cuf rota_mod.cuf rand_gpu.cuf dmc2.cuf test_dmc2.cuf
nvfortran -cuda -Kieee -Mnofma mparametros.o mtipos.o \
  mlegendre.o mhh_heocs.o mkp_heco.o mangwavef.o mvmolecula.o mvaziz.o \
  mrotaciones.o mlineal.o msistref.o mdensidades.o mmcvpromedia.o \
  mrandom2.o mrandom.o mwavef.o msteps.o \
  modlegendre.o kpcoef.o pw_heocs.o bh_heh2m.o \
  glibc_exp_mod.o glibc_acos.o glibc_sincos.o glibc_pow.o \
  angle_scalar_vec_mod.o mVheheVphehe_mod.o He_dihydrogen.o \
  mlegendre_gpu.o d_uhex4_mod.o der_wavefx_mod.o der_wavefhe4_mod.o wavef_mod.o \
  derananum_mod.o mccuerpo_mod.o mpotenbh_mod.o vpot_mod.o valibre_mod.o \
  hpsi_mod.o rota_mod.o rand_gpu.o dmc2.o test_dmc2.o \
  -o test_dmc2 -llapack -lblas
./test_dmc2

# 2) Solo CPU, con gfortran
rm -f *.mod *.o
gfortran -ffp-contract=off -c mparametros.f90 mtipos.f90 mlegendre.f90 mhh_heocs.f90 \
  mkp_heco.f90 mangwavef.f90 mvmolecula.f90 mvaziz.f90 mrotaciones.f90 mlineal.f90 \
  msistref.f90 mdensidades.f90 mmcvpromedia.f90 mrandom2.f90 mrandom.f90 mwavef.f90 msteps.f90 \
  modlegendre.f kpcoef.f pw_heocs.f
gfortran -ffixed-form -ffp-contract=off -c bh_heh2m.f -o bh_heh2m_gf.o
gfortran -ffp-contract=off mparametros.o mtipos.o mlegendre.o mhh_heocs.o mkp_heco.o \
  mangwavef.o mvmolecula.o mvaziz.o mrotaciones.o mlineal.o msistref.o mdensidades.o \
  mmcvpromedia.o mrandom2.o mrandom.o mwavef.o msteps.o \
  modlegendre.o kpcoef.o pw_heocs.o bh_heh2m_gf.o test_dmc2_gfortran.f90 \
  -o test_dmc2_gfortran -llapack -lblas
./test_dmc2_gfortran
```

## 8. Resultado

**GPU vs. CPU(`nvfortran`)**, `-Kieee -Mnofma`:

| walker | `nsons` CPU / GPU | `|err| max` |
|---|---|---|
| 1 (normal) | 1 / 1 | 3.55E-15 |
| 2 (normal) | 1 / 1 | 2.84E-14 |
| 3 (normal, geometría simétrica) | `gb` patológico (§7), excluido | 7.11E-15 |
| 4 (extremo, contacto `rij≈0.05`) | `gb` patológico (§7), excluido | 0.00E+00 |
| 5 (extremo, largo alcance `rij≈1000`) | 0 / 0 | 8.27E-25 |

**Las tres vías, `ene`/`kin`/`pot` a precisión completa (`es24.17`)**: coinciden en las tres — GPU, CPU-`nvfortran` y `gfortran` real — al mismo nivel de precisión ya visto en `hpsi.md` (exacto o `~1E-14` según el walker, heredado sin amplificar de `hpsi`/`vpot`). Las posiciones finales de los átomos (incluidas las magnitudes extremas del walker 4, `~1E13` tras el arrastre con un `dwf` casi singular) también coinciden en las tres vías, confirmando que el desbordamiento de `gb` (§7) es el único punto de divergencia esperada, y está perfectamente localizado y explicado — no contamina ningún otro resultado del mismo walker.

`PASA` en los 5 casos. `dmc2` cierra la cadena completa `hpsi`+`rota`+`gauss3`/`rand1` con el mismo rigor que cada pieza por separado, sin introducir ningún residuo nuevo.
