# cpu-gpu-fluid3: el eje de walkers en la Tesla V100 de la UAL

Repite en `fluid3` la batería de walkers de [`../cpu-gpu-ctfg/`](../cpu-gpu-ctfg/)
(`ejecutar_test_walkers_pequenos.sh`, ejecutada en el PC personal), para comparar en qué
punto compensa la versión híbrida (`dmc-hibrido`) frente a la secuencial original
(`dmc-cpu`) en las dos máquinas.

- Bloques de cálculo = 100 y pasos por bloque = 100, fijos.
- Walkers = 1, 5, 10, 15, 20, 25, 30, 40, 50, 75, 100, 150, 250, 500.
- `etrial = -631.8` (verificado por `genera_inmcv.py`), semilla fija `0000000000000011` y
  `conf.20.00.HH` nuevo antes de cada corrida (plantillas en `_plantillas/`).
- Se mide el tiempo *wall-clock* de cada corrida, primero GPU (`opcion=5`) y después
  CPU (`opcion=4`).

## Resultados

| Carpeta | Máquina | GPU | CPU |
|---|---|---|---|
| [`../cpu-gpu-ctfg/test-walkers-pequenos/`](../cpu-gpu-ctfg/test-walkers-pequenos/) | Ordenador personal | NVIDIA GeForce RTX 4060 Laptop | AMD Ryzen 7 8845HS |
| `test-walkers-fluid3/` | Máquina virtual de la UAL (`fluid3`) | NVIDIA Tesla V100 PCIe 16 GB | 2 × AMD EPYC 7301 |

`test-walkers-fluid3/` contiene `resultados.csv` (tiempos, aceleración CPU/GPU y versión
más rápida), `tabla.tex` (filas para la memoria) y, por cada configuración, los logs de las
dos ejecuciones (terminan con `wall=<segundos>s rc=<código>`) y los `in.mcv` usados. En
`test-walkers-fluid3/entorno.txt` se guardan `lscpu`, `nvidia-smi` y las versiones de los
compiladores. Los binarios copiados y los histogramas no se suben (ver `.gitignore`).

Las corridas del PC se hicieron con la versión de desarrollo `hibrido_instrumentado`
(`opcion=7`), equivalente bit a bit a la `opcion=5` de `dmc-hibrido`.

La corrida con 1 *walker* termina con colapso de población (no queda ningún *walker*
vivo) y no se tiene en cuenta en el cálculo del cruce.

## Cómo repetirla

El código de las dos versiones está en la rama `main`, así que el script recibe la ruta
a una copia de esa rama:

```bash
git clone https://github.com/BlancaRoRo/DMC.git ~/DMC          # rama main
./ejecutar_test_walkers.sh ~/DMC <etiqueta_maquina>             # p. ej. fluid3
```

El script compila las dos versiones si aún no hay binarios (`nvfortran` y `gfortran`),
registra el entorno y, al terminar, genera el resumen. Se puede regenerar con
`python3 resumen.py test-walkers-<etiqueta>`. Variables opcionales: `REPETICIONES=3`
(el resumen usa la media), `WALKERS="5 40"` y `FORZAR_COMPILAR=1`.
