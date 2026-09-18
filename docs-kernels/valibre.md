# Duodécimo kernel: `valibre`

Documentación de [`v1-cuda-desarrollo/valibre/valibre.cuf`](../valibre/valibre.cuf). Porta `valibre` de [`mwavef.f90:875-896`](../valibre/mwavef.f90): inicializa un walker "vacío" — pone las funciones de onda a `1`, las energías a `0`, los signos a `1`, y pone a cero los vectores de derivada (`dwf`, `dphi`). Es la subrutina que se llama antes de acumular cualquier contribución de energía/función de onda sobre un walker recién creado.

---

## Parte 1 — Implementación

## 1. El original

```fortran
subroutine valibre(w1)
  type(walker), intent (inout) :: w1
  integer(kind=i4) :: iatom

   w1%lw%wf=1.0_r8
   w1%lw%wfhe4=1.0_r8
   w1%lw%wfhe3=1.0_r8
   w1%lw%wfm=1.0_r8
   w1%lw%wfx=1.0_r8
   w1%lw%kin=0.0_r8
   w1%lw%pot=0.0_r8
   w1%lw%ene=0.0_r8
   w1%lw%signoup=1
   w1%lw%signodw=1

   do iatom=1,natom
     w1%dwf(iatom)=0.0_r8
   enddo
   w1%dphi(:)=0.0_r8

end subroutine valibre
```

Es la subrutina más simple de todas las portadas hasta ahora: **ninguna operación aritmética**, solo asignación de constantes literales (`0.0`/`1.0`, exactas en cualquier precisión) — no hay ninguna vía por la que pueda aparecer una discrepancia de ULP entre GPU, CPU-`nvfortran` y `gfortran`.

## 2. El único punto delicado: `wf`/`wfhe4`/`wfhe3`/`wfm`/`wfx` son `real(kind=r16)`

En `mtipos.f90`, `type vloc` declara esos cinco campos como `real(kind=r16)` — **precisión cuádruple**, no doble. Esto ya se decidió en `wavef.cuf` (ver `docs-kernels/wavef.md`): la versión GPU trabaja en `real(kind=r8)` para estos campos, porque las GPU de NVIDIA no tienen soporte nativo de precisión cuádruple. Aquí se sigue exactamente la misma convención, sin necesidad de volver a justificarla — y como las únicas asignaciones son `1.0_r8`/`0.0_r8` (valores exactos en cualquier precisión), truncar de `r16` a `r8` no pierde ni cambia nada: el resultado es idéntico independientemente de la precisión de trabajo.

## 3. AoS → SoA: `w1%dwf` y `natom`

`w1%dwf` es `type(vec3), allocatable :: dwf(:)` — un array de vectores 3D, uno por átomo. Se convierte en `dwf(3,natoms)` (SoA), mismo patrón que en `ccuerpo.cuf`/`wavef.cuf`. `natom` no es un `PARAMETER` (es variable pública de `mparametros.f90`, fijada en tiempo de ejecución al leer `in.mcv`), así que se pasa como argumento (`natoms`), igual que en `potenbh.cuf`/`vpot.cuf` — no se puede leer directamente dentro de una subrutina `device`.

`w1%dphi(2)` es un array de tamaño fijo (2), se mantiene igual, con dimensión de walker añadida en el kernel (`dphi(2,n)`).

## 4. Estructura: subrutina `attributes(host,device)` + kernel de un hilo por walker

```fortran
attributes(host, device) subroutine valibre(natoms, wf, wfhe4, wfhe3, wfm, wfx, &
                                             kin, pot, ene, signoup, signodw, &
                                             dwf, dphi)
```
Los diez escalares del original (`wf`...`signodw`) pasan a ser diez argumentos `intent(out)` en vez de campos de un `type(walker)` — el mismo cambio de "recibe el walker entero" a "recibe solo lo que usa" que ya se hizo en `wavef.cuf`/`vpot.cuf`. El kernel `k_valibre` añade la dimensión de walker a cada uno (SoA, un array por campo, último índice = walker) y llama a `valibre` una vez por hilo.

Envuelto en `module mvalibre` por el motivo habitual: evitar que el símbolo enlazado choque con el `valibre` original de `mwavef.f90` al enlazar los dos `.o` juntos para comparar.

---

## Parte 2 — Pruebas

## 5. El programa de prueba

3 walkers, 5 átomos. La referencia de CPU es `valibre` de `mwavef.f90` **sin tocar**, llamada sobre un `type(walker)` real (`allocatewalker`), importada con `use mwavef, only: valibre` (vive dentro de un módulo real, igual que `vpot`, así que no hace falta `external`). Se comparan los diez escalares, los `3×5` componentes de `dwf`, y los 2 de `dphi` — 27 valores por walker.

### Cómo ejecutarlo

Desde `v1-cuda-desarrollo/valibre/`:
```bash
# 1) GPU + CPU(nvfortran) en el mismo binario
rm -f *.mod *.o
nvfortran -cuda -Kieee -Mnofma -c mparametros.f90 mtipos.f90 mlegendre.f90 mhh_heocs.f90 \
  mkp_heco.f90 mangwavef.f90 mvmolecula.f90 mvaziz.f90 mrotaciones.f90 mlineal.f90 \
  msistref.f90 mwavef.f90 modlegendre.f kpcoef.f pw_heocs.f bh_heh2m.f valibre.cuf
nvfortran -cuda -Kieee -Mnofma mparametros.o mtipos.o mlegendre.o mhh_heocs.o mkp_heco.o \
  mangwavef.o mvmolecula.o mvaziz.o mrotaciones.o mlineal.o msistref.o mwavef.o \
  modlegendre.o kpcoef.o pw_heocs.o bh_heh2m.o valibre.o -o test_valibre -llapack -lblas
./test_valibre

# 2) Solo CPU, con gfortran
rm -f *.mod *.o
gfortran -ffp-contract=off -c mparametros.f90 mtipos.f90 mlegendre.f90 mhh_heocs.f90 \
  mkp_heco.f90 mangwavef.f90 mvmolecula.f90 mvaziz.f90 mrotaciones.f90 mlineal.f90 \
  msistref.f90 mwavef.f90 modlegendre.f kpcoef.f pw_heocs.f
gfortran -ffixed-form -ffp-contract=off -c bh_heh2m.f -o bh_heh2m_gf.o
gfortran -ffp-contract=off mparametros.o mtipos.o mlegendre.o mhh_heocs.o mkp_heco.o \
  mangwavef.o mvmolecula.o mvaziz.o mrotaciones.o mlineal.o msistref.o mwavef.o \
  modlegendre.o kpcoef.o pw_heocs.o bh_heh2m_gf.o test_valibre_gfortran.f90 \
  -o test_valibre_gfortran -llapack -lblas
./test_valibre_gfortran
```

**Resultado real — 1) GPU + CPU(`nvfortran`)**:
```
--- walker 1
  wf     CPU=      1.0000000000   GPU=      1.0000000000
  ...
  kin    CPU=      0.0000000000   GPU=      0.0000000000
  ...
  |err| max=  0.00E+00
```
Los 3 walkers dan `|err| max = 0.00E+00` — coincidencia **exacta**, como se esperaba al no haber ninguna operación aritmética.

**Resultado real — 2) solo CPU, con `gfortran`**: mismos valores exactos (`1.00000000000000000E+00`/`0.00000000000000000E+00` en todos los campos, para los tres walkers) — las tres vías coinciden trivialmente: **GPU = CPU(`nvfortran`) = CPU(`gfortran`)**, sin ningún residuo, ni siquiera del orden de ULP.
