# Falsa alarma: no es un efecto de CUDA sobre el host — es `conf.<nombre>` mutando entre corridas

Durante el Paso 4 del ensamblado del híbrido (`v1-cuda-desarrollo/hibrido/`, ver `hibrido.md`), al comparar la orquestación original compilada junto con los módulos de física CUDA (aunque `opcion=0-4` nunca los llama) frente a la misma orquestación sin ningún módulo CUDA, aparecía una diferencia real en el resultado final (`-739.3555062496` frente a `-619.4111412937`/`gfortran`). Se investigó a fondo pensando que enlazar código de dispositivo real podía estar cambiando el comportamiento del host — **la investigación descartó esa hipótesis paso a paso, y terminó encontrando la causa real: un problema de metodología de prueba, no del compilador ni de CUDA.** Se deja constancia de las dos cosas: el proceso de descarte (con valor real, la técnica sigue siendo aplicable si algo así vuelve a aparecer) y la causa real encontrada.

---

## 1. La causa real

`mmontecarlo.f90:finwalkers` llama a `finconfiguraciones` (`mconfiguraciones.f90:179`), que **reescribe el fichero `conf.<nombre>`** (`conf.20.00.HH` en este caso) con la configuración final de walkers de la corrida — pensado para poder continuar una simulación larga en una ejecución posterior arrancando desde donde quedó la anterior. Esto ocurre **siempre**, para cualquier `opcion` (`0` a `4`), no solo para `dmc`.

Al ir montando varias carpetas de prueba (`hibrido/`, `nv_cuda_flag_only/`, `gf_check_step4/`, ...) copiando `conf.20.00.HH` en momentos distintos, cada una fue arrancando desde una versión **ya mutada** por una corrida de prueba anterior (la propia, o una de otra carpeta copiada después de ejecutarse) — sin que la orquestación, el compilador ni CUDA tuvieran nada que ver. Confirmado con `md5sum`: los `conf.20.00.HH` de las distintas carpetas de prueba eran **directamente distintos** entre sí, con contenido diferente desde la primera línea.

**Confirmación definitiva**: con el mismo `conf.20.00.HH` intacto (copiado de `ccuerpo/`, verificado con `md5sum` en ambas carpetas justo antes de correr) en las dos variantes — con y sin los 11+ módulos CUDA reales compilados y enlazados en el mismo binario — el resultado es **idéntico hasta el último dígito**: `xwalker(1:3)`, `ewalker(1:3)`, `gvar3` del primer walker, energía del walker 1, y la energía final de la simulación (`-615.5737694990` en ambas). No hay ningún efecto de enlazar código de dispositivo sobre el comportamiento del host.

**Lección para el resto del proyecto**: cualquier prueba futura que involucre `opcion=4`/`iniwalkers`/`finwalkers` con un fichero `conf.*` debe partir de una copia fresca y verificada (`md5sum`) de ese fichero, o usar `leefichero=.false.` (generar configuraciones aleatorias en vez de leer de fichero) si no importa el punto de partida exacto — no reutilizar entre corridas una carpeta donde ya se haya ejecutado `qmccluster` antes.

## 2. El proceso de descarte (conservado, tiene valor como método)

Antes de encontrar la causa real, se descartaron metódicamente varias hipótesis, con pruebas aisladas — la misma disciplina de siempre en este proyecto (aislar antes de concluir):

1. **¿Es el flag `-cuda` por sí solo?** No — con `-cuda` puesto pero sin ningún módulo CUDA real compilado, el resultado coincidía exacto con `gfortran`.
2. **¿Cambia la librería matemática del host (`log`/`dexp`/`dsin`/`dcos`/`dacos`/`**`) al enlazar módulos de dispositivo reales?** No — probado en aislado (`hibrido/aislado_libm/test_libm.f90`, `test_libm2.f90`) con valores reales del proyecto, enlazando contra los mismos objetos `.o` que sí mostraban la divergencia en el programa completo: las seis funciones coincidían exactas con `gfortran` en las tres variantes, salvo el residuo de `dsin` ya conocido y documentado desde antes (`mrandom.md` §7), sin relación con los módulos de dispositivo.
3. **¿Inicializar de verdad el runtime de CUDA (lanzar un kernel real y sincronizar) cambia el estado de la FPU del host?** Tampoco — mismo resultado exacto que sin inicializar nada.
4. **Bisección con `write` `es24.17` dentro de `iniwalkers`**: aquí se encontró que `xwalker(1:3)` (la posición del primer átomo del primer walker, **una simple lectura de fichero, sin ningún cálculo**) ya era distinta entre las dos variantes — la pista que llevó directamente a sospechar del fichero de entrada en sí, no de ningún cálculo, y de ahí a `conf.20.00.HH`.

El método (aislar función por función, luego bisecar con prints en el propio flujo del programa) fue el correcto y llevó a la causa real — el error fue de manejo de datos de prueba (ficheros de estado compartidos entre carpetas de prueba), no de razonamiento.
