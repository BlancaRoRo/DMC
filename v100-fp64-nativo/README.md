# V100 (fluid3): ¿hardware nativo de `exp`/`log` en doble precisión?

Pregunta que motiva esta prueba: en la RTX 4060 Laptop (`sm_89`) confirmamos por SASS que **no existe hardware nativo (`MUFU.EX2`/`MUFU.LG2`) para `exp`/`log` en doble precisión** — solo en `float` — y que por eso `wavef_derwavefhe4` en `float` es 3,83-3,85x más rápido (ver `v3-cuda-optimización/optimizacion-vpot/benchmark-float-vs-double.md`). La Tesla V100 (Volta, `sm_70`, en `fluid3`) tiene un ratio FP64:FP32 mucho mejor (1:2 frente al ~1:32 de la RTX 4060) — ¿tiene también hardware nativo de `exp`/`log` en doble, o solo aritmética básica (suma/multiplicación) más rápida?

## Entorno (`docs/hardware_specs.md`)

- GPU: Tesla V100-PCIE-16GB, `compute capability 7.0`
- VM compartida (`fluid3`) — comprobar VRAM libre antes de nada (`nvidia-smi`), suele estar muy ajustada por otros procesos.
- Compilador: `nvfortran` (confirmado instalado en la máquina, aunque no en el `PATH` por defecto — localizar antes de compilar).

## Paso 0 — localizar `nvfortran`

```bash
find / -maxdepth 6 -iname "nvfortran" -type f 2>/dev/null
# o, si hay modules:
module avail 2>/dev/null | grep -i nvhpc
# ruta habitual (misma estructura que en la portátil):
ls /opt/nvidia/hpc_sdk/Linux_x86_64/*/compilers/bin/nvfortran 2>/dev/null
```

Una vez localizado:
```bash
export PATH=<ruta_encontrada>:$PATH
nvfortran --version
```

## Paso 1 — esta prueba (no ejecuta nada en GPU, solo compila + vuelca SASS)

```bash
nvfortran -cuda -gpu=cc70 -c test_native_exp_log.cuf
cuobjdump --dump-sass test_native_exp_log.o > sass_v100.txt
grep -n "k_test_double\|k_test_float" sass_v100.txt
```

Localiza el bloque de `k_test_double_` en `sass_v100.txt` (entre esa línea y la siguiente función) y busca `MUFU`:

```bash
awk '/k_test_double_/{f=1} /k_test_float_/{f=0} f' sass_v100.txt | grep -n "MUFU"
```

**Qué mirar**: si esa búsqueda no devuelve nada dentro del bloque `double`, confirma que Volta tampoco tiene hardware nativo de `exp`/`log` en doble (misma conclusión que la RTX 4060). Si aparece algún `MUFU.EX2`/`MUFU.LG2` ahí, es un hallazgo nuevo y relevante — avisar antes de asumir nada.

## Resultado del Paso 1 (confirmado con SASS real, `fluid3`)

**La V100 tampoco tiene hardware nativo de `exp`/`log` en doble precisión — misma limitación que la RTX 4060.**

```
grep -n "MUFU\|Function :" sass_v100.txt
33:   Function : test_native_exp_log_k_test_float_
93:   MUFU.EX2 R4, R11 ;                    <- exp() nativo, dentro de k_test_float
150:  Function : test_native_exp_log_k_test_double_
326:  MUFU.RCP64H R9, R17 ;                 <- unico MUFU dentro de k_test_double
```

El único `MUFU` que aparece dentro de `k_test_double` (líneas 150-404, la función ocupa hasta el final del fichero) es `MUFU.RCP64H` — la semilla de **división**, no de exponencial/logaritmo. No es un atajo para `exp`/`log`: es una pieza interna que el propio algoritmo de software (el que calcula `log()` en doble por reducción de rango + polinomio) usa como sub-operación, igual que `mypow_log`/`myexp` en la RTX 4060 usan `MUFU.RCP64H`/`RSQ64H` como semillas de sus propios cálculos internos. La firma también se nota en el tamaño: `k_test_double` ocupa ~254 líneas de SASS frente a las ~116 de `k_test_float` — el doble de instrucciones, típico de una emulación por software.

**Conclusión**: esta limitación no es de "GPU de gama baja" — es una restricción del propio hardware MUFU de NVIDIA, presente también en una GPU de centro de datos real como Volta. Lo que sí debería cambiar en la V100 es el throughput de la aritmética básica en doble (suma/multiplicación/FMA) que rellena esas ~254 instrucciones de software — con el ratio FP64:FP32 real de Volta (1:2, frente al ~1:32 de la RTX 4060), **la V100 podría acabar siendo más rápida en `double` que la RTX 4060 en términos absolutos**, aunque `float` probablemente siga ganando en relativo dentro de la propia V100 (menos instrucciones en total, sea cual sea la velocidad de cada una). Pendiente de confirmar con el benchmark real (Paso 2).

**Nota de toolchain** (relevante si se repite en otra máquina): CUDA 13.x ha dejado de soportar `sm_70` en `nvdisasm`/`cuobjdump` ("CUDA architecture SM70 is deprecated") — hizo falta usar el `cuobjdump` del toolkit 12.9 bundled dentro del mismo HPC SDK 26.5 (`.../cuda/12.9/bin/cuobjdump`, no el 13.2 que aparece primero en el `PATH`).

## Paso 2 — benchmark real `float` vs `double` en la V100

Repetir el benchmark aislado (mismo patrón que en la portátil, buffers desechables pequeños — cabe de sobra en la VRAM libre actual, ~767 MB) para medir el ratio real, no solo razonarlo. Pendiente de preparar y subir.

## Próximos pasos de la línea `float` (no solo de esta prueba de la V100)

1. **Protección de underflow de `ujas`**: el clip actual (`umax=200, umin=-200`) está pensado para `double`, no para `float`. Con datos reales medidos (`ujas` entre −99,74 y −41,63 en 10.000 pasos, nunca positivo) y los límites exactos de `float32` (`exp` desborda a partir de `+88,72`; underflow real por debajo de `-103,28`), el clip debería pasar a algo como `ujas = max(ujas, -85.0_4)` — margen de seguridad real, no heredado de `double`. Ver `v3-cuda-optimización/optimizacion-vpot/float-wavef-derwavefhe4-validacion.md`.
2. **Repetir la validación** con el clip corregido — no hace falta a la escala de 1.000.000 de pasos otra vez, una corrida más pequeña (10.000-100.000 pasos) ya deja ver si el clip nuevo cambia algo respecto al `±200` actual.
3. **Buscar un segundo método candidato** de precio comparable a `wavef_derwavefhe4` para probar el mismo cambio a `float` — mismo criterio de riesgo bajo ya establecido (suma de muchos pares, sin cancelación catastrófica, mismo tipo de exponente fraccionario suave). `wavefx` es el candidato natural por tener la misma forma algebraica exacta.
