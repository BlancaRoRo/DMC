# Decimoquinto kernel: `rota`

Documentación de [`v1-cuda-desarrollo/rota/rota.cuf`](../rota/rota.cuf). Porta `rota` de [`mrotaciones.f90`](../rota/mrotaciones.f90) (líneas 11-33): rota los ejes `sprop` de un walker un ángulo `phi` alrededor del eje `i1`, usado por `hpsi` (`mwavef.f90:762-774`) para la derivada numérica de la parte rotacional de la función de onda (`erot`/`dphi`) — `phi` vale siempre `+da`/`-da`, con `da=1.d-4`.

---

## Parte 1 — Implementación

## 1. Transcripción directa, con `mycos`/`mysin` en vez de `cos`/`sin`

```fortran
attributes(host, device) subroutine rota(i1, phi, ejes)
  integer(kind=i4), intent (in) :: i1
  real(kind=r8), intent (in) :: phi
  type(vec3), intent (inout) :: ejes(3)
  real(kind=r8) :: c, s, t
  integer(kind=i4) :: j1, k1, ic

    j1 = i1+1
    if (j1.gt.3) j1 = 1
    k1 = j1+1
    if (k1.gt.3) k1 = 1

    c = mycos(phi)
    s = mysin(phi)

    do ic = 1, 3
      t                =  c*ejes(j1)%comp(ic)+s*ejes(k1)%comp(ic)
      ejes(k1)%comp(ic) = -s*ejes(j1)%comp(ic)+c*ejes(k1)%comp(ic)
      ejes(j1)%comp(ic) = t
    enddo
end subroutine rota
```

Sin cambios de fondo salvo `cos(phi)`→`mycos(phi)` y `sin(phi)`→`mysin(phi)` — mismo motivo que en todo el árbol: los intrínsecos de dispositivo de CUDA no coinciden bit a bit con glibc, que es lo que usa `gfortran` en la CPU de referencia. Cualquier llamada a una función trascendental con un argumento real en tiempo de ejecución necesita la versión propia para garantizar bit-exactitud entre GPU, CPU-`nvfortran` y `gfortran` — ya establecido para `exp`/`cos`/`sin`/`acos`/`pow` en kernels anteriores (`glibc_math.md`).

## 2. A diferencia de `mypow`: `mycos`/`mysin` ya soportan dominio negativo

`phi` toma ambos signos en la práctica (`phi=+da` y `phi=-da`, `mwavef.f90:762,768`). Esto NO reproduce el bug de dominio que sí tuvo `mypow` con `mycos(theta)`/`mysin(theta)` negativos (`He_dihydrogen.md` §27, que necesitó un parche `abs()`+`SIGN()`): `mysin`/`mycos` (`glibc_sincos.cuf`) extraen la magnitud internamente con `iand(high32_of(x), 0x7fffffff)` y aplican la paridad/imparidad correcta con `sign()` dentro de la propia función — no hace falta ningún tratamiento especial aquí, se llama igual que al intrínseco `cos`/`sin` original.

## 3. Dependencias: solo `mtipos` y `glibc_sincos_mod`

`rota` no necesita `mparametros`, `mccuerpo` ni ningún otro módulo de estado global del proyecto — solo el tipo `vec3` (`mtipos.f90`) y `mycos`/`mysin` (`glibc_sincos_mod`, que a su vez depende de `glibc_exp_mod` para `bits_of`/`real_of`/`top12_of`, igual que en el resto del árbol). Es el kernel con menos dependencias portado hasta ahora.

---

## Parte 2 — Pruebas

## 4. 8 casos: los 3 valores de `i1`, ambos signos de `da`, y 2 extremos de `phi`

**Casos 1-6 (caso real)**: `i1=1,2,3` × `phi=+da,-da` (`da=1.d-4`, el valor exacto que usa `hpsi`) — cubre los 3 valores de `i1` y, con ellos, las dos formas en que `j1`/`k1` dan la vuelta módulo 3 (`i1=2` da la vuelta a `k1`; `i1=3` da la vuelta a `j1`).

**Casos 7-8 (extremos de `phi`)**: `phi=1.0d10` (con `ejes` de magnitud `~1E8` también, para combinar ambos extremos) y `phi=1.0d-300` — para ejercitar ramas de reducción de rango distintas dentro de `mysin`/`mycos` con un argumento real de este kernel (la corrección exhaustiva de la propia librería `mysin`/`mycos` ya está hecha por separado en `glibc_math.md`; aquí solo se confirma que el punto de entrada de `rota` llega a esas ramas igual en las tres vías).

### Cómo ejecutarlo

Desde `v1-cuda-desarrollo/rota/`:
```bash
# 1) GPU + CPU(nvfortran) en el mismo binario
rm -f *.mod *.o
nvfortran -cuda -Kieee -Mnofma -c mtipos.f90 glibc_exp_mod.cuf glibc_sincos.cuf mrotaciones.f90 rota.cuf test_rota.cuf
nvfortran -cuda -Kieee -Mnofma mtipos.o glibc_exp_mod.o glibc_sincos.o mrotaciones.o rota.o test_rota.o \
  -o test_rota
./test_rota

# 2) Solo CPU, con gfortran
rm -f *.mod *.o
gfortran -ffp-contract=off -c mtipos.f90 mrotaciones.f90
gfortran -ffp-contract=off mtipos.o mrotaciones.o test_rota_gfortran.f90 -o test_rota_gfortran
./test_rota_gfortran
```

## 5. Resultado: 8/8 exacto en las tres vías

| caso | `i1` | `phi` | `|err| max` (GPU vs. CPU-`nvfortran`) |
|---|---|---|---|
| 1 | 1 | `+1.00E-04` | 0.00E+00 |
| 2 | 1 | `-1.00E-04` | 0.00E+00 |
| 3 | 2 | `+1.00E-04` | 0.00E+00 |
| 4 | 2 | `-1.00E-04` | 0.00E+00 |
| 5 | 3 | `+1.00E-04` | 0.00E+00 |
| 6 | 3 | `-1.00E-04` | 0.00E+00 |
| 7 | 1 | `1.00E+10` (extremo, `ejes~1E8`) | 0.00E+00 |
| 8 | 1 | `1.00E-300` (extremo) | 0.00E+00 |

`PASA` en los 8 casos. Se comprobó además, comparando manualmente la salida `es24.17` de `test_rota_gfortran` frente a la de GPU/CPU-`nvfortran`, que las tres vías coinciden dígito a dígito en los 24 valores (3 componentes × 3 ejes × ... realmente 2 ejes rotados + 1 sin tocar por caso) de los 8 casos — **GPU = CPU(`nvfortran`) = `gfortran`, exacto**, sin ningún residuo de ~1 ULP como el ya documentado para `He_dihydrogen`/`vpot`. Es el primer kernel con funciones trascendentales de este árbol que cierra completamente exacto en las tres vías, sin ninguna reserva — consistente con que aquí no hay ninguna suma de 3+ términos de signo variable que pueda reasociar (la única operación además de `mycos`/`mysin` es la combinación lineal `c*a+s*b`, de 2 términos, igual que `ene=kin+pot` en `hpsi.md` §1).
