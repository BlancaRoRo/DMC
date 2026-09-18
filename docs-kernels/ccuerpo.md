# Octavo kernel: `ccuerpo`

Documentación de [`v1-cuda-desarrollo/ccuerpo/ccuerpo.cuf`](../ccuerpo/ccuerpo.cuf). Porta `ccuerpo` de [`msistref.f90`](../ccuerpo/msistref.f90): transforma las posiciones de los átomos de He (en el sistema de referencia del laboratorio) al sistema de referencia del cuerpo (el marco rotado que define `sprop`). Es la subrutina cuyo resultado ya se usaba, sin comentarlo entonces, como dato de entrada sintético en los tests de `He_dihydrogen` ("posiciones... como las deja `ccuerpo`").

Igual que en los kernels anteriores, el `.cuf` incluye el módulo con la implementación (`mccuerpo`) y, a continuación, el `program test_ccuerpo` que compara CPU y GPU — mismo criterio de un solo fichero por kernel que en `V_hehe_Vp_hehe.cuf`, `angle_scalar_vec.cuf`, `der_wavefhe4.cuf` y `der_wavefx.cuf` (`He_dihydrogen` fue la única excepción, y solo porque el choque de símbolos del enlazador con el original obligaba a separar la subrutina en su propio fichero — aquí no hay ese problema, así que se mantiene junto).

---

## Parte 1 — Implementación

## 1. El original

```fortran
subroutine ccuerpo(w1,rhesal)
 type(walker), intent (in) :: w1
 real(kind=r8), intent (out) :: rhesal(3*ngatom)
 type(vec3) :: rtemp
 integer(kind=i4) :: iatom,jatom,ic,jc

   iatom=0
     do jatom=1,ngatom
         rtemp=w1%atom(jatom)-w1%atom(ngatom+1)
        do ic=1,3
          rhesal(iatom+ic)=0.0_r8
          do jc=1,3
            rhesal(iatom+ic)=rhesal(iatom+ic)+w1%sprop(ic)%comp(jc)*rtemp%comp(jc)
          enddo
        enddo
        iatom=iatom+3
     enddo
end subroutine ccuerpo
```
Por cada átomo de He (`jatom=1..ngatom`), calcula el vector desde el átomo de referencia (`w1%atom(ngatom+1)`, la impureza/molécula) hasta ese átomo, y lo proyecta sobre los tres vectores de `w1%sprop` (la base del sistema de referencia del cuerpo). `ngatom`/`natom` (`=ngatom+1`) son variables reales de `mparametros.f90` (`public`, sin `parameter`), rellenadas por `mentradatos.f90` — mismo tratamiento que en kernels anteriores (`nhe4`, `phe4`...).

## 2. Cambios frente al original

**a) `w1` se descompone en `atom`/`sprop` sueltos (AoS→SoA).** El original recibe el `type(walker)` completo y accede a `w1%atom(:)`/`w1%sprop(:)`; la versión `device` no puede recibir un `walker` (componentes `allocatable`, ver `der_wavefhe4.md` §1), así que la interfaz recibe directamente los dos arrays que el cuerpo necesita:
```fortran
attributes(host, device) subroutine ccuerpo(atom, sprop, rhesal)
  type(vec3), intent (in)  :: atom(natom), sprop(3)
  real(kind=r8), intent (out) :: rhesal(3*ngatom)
```
Mismo criterio que en `wavefhe4`/`derwavefhe4` (`der_wavefhe4.md` §1-2). El módulo se llama `mccuerpo` (no `ccuerpo`), porque un módulo no puede compartir nombre con un procedimiento que contiene — mismo criterio que `mVheheVphehe`, `mHe_dihydrogen`.

**b) El operador `-` sobrecargado de `vec3` no es `device`.** El original hace `rtemp=w1%atom(jatom)-w1%atom(ngatom+1)`, usando el operador `-` que `mtipos.f90` define vía `interface operator (-)` → `restavec3`. A diferencia de `wavefhe4`/`duhe4x` (que solo leían componentes `%comp`, nunca operaban sobre un `vec3` entero — ver `der_wavefhe4.md` §3), `ccuerpo` sí lo hacía, y `restavec3` en `mtipos.f90` **no** tiene `attributes(host,device)` — es una función solo de host, no se puede llamar desde código `device`. Se sustituyó por la resta componente a componente, sin tocar `mtipos.f90`:
```fortran
rtemp%comp = atom(jatom)%comp - atom(natom)%comp
```
(`natom` en vez de `ngatom+1`: son el mismo valor, pero al recibir `natom` como argumento explícito ya no hace falta recalcularlo).

**c) `rhesal` lleva una dimensión extra por walker en el kernel** (`rhesal(3*ngatom,n)` en vez de `rhesal(3*ngatom)`), porque cada walker necesita su propia salida — el resto de la interfaz de `k_ccuerpo` sigue el mismo patrón de un hilo por walker que todos los kernels anteriores:
```fortran
attributes(global) subroutine k_ccuerpo(n, atom, sprop, rhesal)
  integer(kind=i4), value :: n
  type(vec3), device, intent (in)  :: atom(natom,n), sprop(3,n)
  real(kind=r8), device, intent (out) :: rhesal(3*ngatom,n)
  integer(kind=i4) :: i

  i = (blockIdx%x - 1) * blockDim%x + threadIdx%x
  if (i <= n) then
    call ccuerpo(atom(:,i), sprop(:,i), rhesal(:,i))
  endif
end subroutine k_ccuerpo
```
Un hilo por walker, igual que en todos los kernels anteriores: `atom(:,i)`/`sprop(:,i)` son las posiciones y la base de ese walker; `rhesal(:,i)` es su salida.

## 3. Sin `IF` que reestructurar

`ccuerpo` no tiene ninguna rama condicional — es un doble bucle puro (`jatom`/`ic`/`jc`) sin ningún `IF`. No hay nada que discutir aquí sobre divergencia de warp: todos los hilos de un warp ejecutan exactamente el mismo camino, solo con datos distintos.

## 4. Variables externas: mismo criterio que siempre

- **`ngatom`, `natom`**: variables reales de `mparametros.f90`, no `parameter` — mismo tratamiento que `nhe4`/`ngatom`/`natom` en `der_wavefx.md`/`der_wavefhe4.md`: `device` a nivel del módulo `mccuerpo`, con una asignación explícita desde el host antes de lanzar el kernel. Usarlas como cota de un argumento mudo (`atom(natom)`, `atom(natom,n)`) es válido en código `device` — el array no se reserva ahí, solo se recibe; la restricción de "no arrays automáticos con tamaño en tiempo de ejecución" solo aplica a arrays *locales*, no a argumentos.
- **`vec3`**: se reutiliza `mtipos.f90` (`use mtipos, only: vec3`), sin retipear — igual que en todos los kernels anteriores que manejan posiciones.

---

## Parte 2 — Pruebas

## 5. Datos de prueba y resultado

Mismos 3 walkers y 4 átomos de He que en `der_wavefx`/`der_wavefhe4` (para poder reutilizar los mismos números si hace falta cruzarlos con esos kernels más adelante), más un `sprop` sintético (base no ortonormal a propósito, para que la proyección ejercite los tres términos del sumatorio interno).

La referencia de CPU es `ccuerpo` de `msistref.f90` **sin tocar** — recibe el `type(walker)` completo, así que hace falta construirlo con `allocatewalker` de `mtipos.f90`, igual que en `der_wavefhe4`/`der_wavefx`.

Un detalle propio de este test: `ngatom`/`natom` existen en **dos módulos distintos** con el mismo nombre — la copia `device` de `mccuerpo` (la que ve el kernel) y la copia real de `mparametros` (la que ve `ccuerpo` del `msistref.f90` original, para dimensionar `rhesal(3*ngatom)`). Para poder fijar las dos por separado sin que sus nombres choquen al hacer `use` de los dos módulos a la vez, la de `mparametros` se importa renombrada (mismo truco que en `test_derwavefx.cuf`):
```fortran
use mccuerpo, only: k_ccuerpo, ngatom, natom
use mparametros, only: ngatom_real => ngatom, natom_real => natom
...
ngatom = n_gatom        ! copia device, para el kernel
natom  = n_atom
ngatom_real = n_gatom   ! copia real, para el ccuerpo original (CPU)
natom_real  = n_atom
```

### Cómo ejecutarlo

Desde `v1-cuda-desarrollo/ccuerpo/`:
```bash
# 1) GPU + CPU(nvfortran) en el mismo binario (modulo + program, en ccuerpo.cuf)
rm -f *.mod *.o
nvfortran -cuda -c mtipos.f90 mparametros.f90
nvfortran -cuda -c msistref.f90
nvfortran -cuda mtipos.o mparametros.o msistref.o ccuerpo.cuf \
  -o test_ccuerpo -llapack -lblas
./test_ccuerpo

# 2) Solo CPU, con gfortran
rm -f *.mod *.o
gfortran -c mtipos.f90 mparametros.f90 msistref.f90
gfortran mtipos.o mparametros.o msistref.o test_ccuerpo_gfortran.f90 -o test_ccuerpo_gfortran
./test_ccuerpo_gfortran
```

**Resultado real — 1) GPU + CPU(`nvfortran`)**:
```
--- walker 1
  rhesal(1:3) CPU=     -2.00000000     -1.50000000     -1.90000000
  rhesal(1:3) GPU=     -2.00000000     -1.50000000     -1.90000000
  rhesal(4:6) CPU=      5.00000000     -1.50000000     -0.85000000
  rhesal(4:6) GPU=      5.00000000     -1.50000000     -0.85000000
  |err| max=  0.00E+00

--- walker 2
  rhesal(1:3) CPU=      0.80000000      1.65000000      0.75000000
  rhesal(1:3) GPU=      0.80000000      1.65000000      0.75000000
  rhesal(4:6) CPU=     -1.00000000      2.50000000     -0.75000000
  rhesal(4:6) GPU=     -1.00000000      2.50000000     -0.75000000
  |err| max=  0.00E+00

--- walker 3
  rhesal(1:3) CPU=      1.40000000     -3.50000000     -3.00000000
  rhesal(1:3) GPU=      1.40000000     -3.50000000     -3.00000000
  rhesal(4:6) CPU=      1.40000000      3.50000000     -3.00000000
  rhesal(4:6) GPU=      1.40000000      3.50000000     -3.00000000
  |err| max=  0.00E+00

 PASA: GPU y CPU coinciden dentro de tolerancia
```
Cero exacto en los tres walkers, sin necesitar ninguna flag especial (`-Kieee`/`-Mnofma`) — coherente con que el cuerpo entero son solo sumas y productos, sin ninguna `dexp`/`dcos`/división delicada de por medio (a diferencia de `Vp_hehe`/`angle`, donde sí aparecían ULPs por FMA).

**Re-verificado a `es24.17`** (revisión final del árbol, junto con `wavef`/`potenbh`/`valibre`): se añadió salida de alta precisión a `rhesal` — la única línea de cálculo real, `rhesal(iatom+ic)=rhesal(iatom+ic)+sprop(ic)%comp(jc)*rtemp%comp(jc)` dentro de `do jc=1,3`, es un término por sentencia acumulado a través del bucle (mismo patrón "seguro" que `getcm`/`derwavefm`, no una suma de varios términos en una sola línea). **Confirmado exacto en las 3 vías (GPU / CPU-`nvfortran` / `gfortran`), con y sin flags, en los 3 walkers × 6 componentes** — cero diferencias en ningún caso, no solo dentro de la tolerancia baja del `f16.8` original.

**Resultado real — 2) solo CPU, con `gfortran`**:
```
--- walker 1
  rhesal(1:3) gfortran=     -2.00000000     -1.50000000     -1.90000000
  rhesal(4:6) gfortran=      5.00000000     -1.50000000     -0.85000000

--- walker 2
  rhesal(1:3) gfortran=      0.80000000      1.65000000      0.75000000
  rhesal(4:6) gfortran=     -1.00000000      2.50000000     -0.75000000

--- walker 3
  rhesal(1:3) gfortran=      1.40000000     -3.50000000     -3.00000000
  rhesal(4:6) gfortran=      1.40000000      3.50000000     -3.00000000
```
Idéntico dígito a dígito con la columna `CPU:`/`GPU:` de la prueba 1. Las tres vías coinciden: **GPU = CPU(`nvfortran`) = CPU(`gfortran`)**.
