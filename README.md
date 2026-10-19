# DMC · Interfaz gráfica

Interfaz web para configurar, compilar, ejecutar y seguir el simulador
**Diffusion Monte Carlo (DMC)** acelerado con GPU (CUDA Fortran), y para
visualizar sus resultados.

## 1. Descripción

El simulador DMC calcula el estado fundamental de un sistema de átomos de
helio con una impureza molecular. Cada simulación se define con un fichero
de configuración (`in.mcv`) de más de cien líneas que, sin esta interfaz,
hay que editar a mano.

La interfaz permite, desde el navegador:

- **Configurar** la simulación con un formulario construido a partir de un
  `in.mcv` de plantilla, con validación de cada campo (números, opciones
  de los desplegables, símbolos químicos).
- **Compilar** el simulador y ver la salida de la compilación en directo.
- **Ejecutar** la simulación en segundo plano y seguir su progreso: bloque
  actual, tiempo transcurrido, estimación del tiempo restante y registro
  en vivo. La ejecución no depende de que la página siga abierta y se
  puede detener en cualquier momento.
- **Ver los resultados** de cada ejecución:
  - nube de puntos 3D con la configuración final de los *walkers*;
  - histogramas radiales y angulares;
  - estadísticas por bloque (gráficas y tabla) en la pestaña *Numéricos*.
- **Reabrir ejecuciones anteriores**, cada una con sus propios resultados.

Cada ejecución se lanza en una carpeta propia
(`runs/run_<fecha>_<hora>/`), con una copia del binario, del `in.mcv`
editado y de la configuración inicial, de modo que las ejecuciones no se
mezclan entre sí ni con el código fuente.

## 2. Lenguajes y librerías

| Parte | Tecnología |
|---|---|
| Servidor | **Python 3** con **Flask** (≥ 3.1) |
| Interfaz | **HTML**, **CSS** y **JavaScript** sin *frameworks* |
| Gráficas | **Plotly** 2.35.2, cargado desde CDN |
| Simulador (externo a este repositorio) | **Fortran** y **CUDA Fortran**, compilado con `nvfortran` |

El navegador y el servidor se comunican mediante una API HTTP que
intercambia JSON. La salida de la compilación llega en directo mediante
*Server-Sent Events*, y el progreso de una ejecución se consulta
periódicamente (`/api/runs/<run_id>/seguimiento`).

### Estructura de este repositorio

```
gui-visualizacion/
├── app.py                      # servidor Flask: API, validación y gestión de ejecuciones
├── requirements.txt            # dependencias de Python
├── settings.json               # rutas configurables (se editan desde "Ajustes")
├── static/
│   ├── config.html             # página de configuración, compilación y ejecución
│   ├── results.html            # página de resultados
│   ├── app-config.js           # lógica del formulario y del seguimiento
│   ├── app-results.js          # gráficas, tabla y selector de ejecuciones
│   ├── app-settings.js         # ventana de ajustes (común a ambas páginas)
│   └── style.css               # estilos de las dos páginas
├── pruebas/
│   ├── test_api.py             # pruebas automáticas de la API
│   └── sondeo_api.py           # sondeo exploratorio de la API
├── plantilla/
│   └── in.mcv                  # plantilla del in.mcv que edita el formulario
├── INVENTARIO_INTERACCIONES.md # interacciones de la interfaz y huecos detectados
└── runs/                       # carpeta de las ejecuciones (se rellena al usarla)
```

## 3. Cómo usarlo

### Requisitos

- **Para ver la interfaz:** Python 3 y un navegador con conexión a
  internet (Plotly y las fuentes se cargan desde CDN).
- **Para compilar y ejecutar el simulador:** Linux, una GPU NVIDIA con
  sus controladores, el NVIDIA HPC SDK (`nvfortran`) y LAPACK/BLAS.

### Archivos necesarios

La interfaz no incluye el simulador. Para usarla se necesitan estos
archivos del simulador:

| Archivo | Para qué se usa | Si falta |
|---|---|---|
| `compilar_pipeline.sh` y el código fuente del simulador | Botón *Compilar* | No se puede compilar |
| `qmccluster_pipeline` (binario que genera la compilación) y los potenciales `*.pot` | Botón *Ejecutar* | No se puede ejecutar |
| `conf.20.00.HH` | Configuración inicial de los *walkers*, que se copia a cada ejecución | No se puede ejecutar |

Dónde están se indica en la interfaz, en la ventana **Ajustes** (icono
⚙), que guarda las rutas en `settings.json`:

- **Carpeta con los ficheros a compilar:** la que contiene
  `compilar_pipeline.sh` y el código fuente.
- **Carpeta donde está el binario compilado:** la que contiene
  `qmccluster_pipeline`, los `*.pot` y `conf.20.00.HH`. Normalmente es la
  misma que la anterior, porque el script deja ahí el binario. Si
  `conf.20.00.HH` no está en esta carpeta, se busca en la de compilación.
- **Carpeta donde se guardan las ejecuciones:** por defecto, `runs/`
  dentro de este repositorio. Se crea si no existe.

### El `in.mcv`

No hace falta aportarlo: la interfaz incluye una plantilla en
`plantilla/in.mcv`. El formulario se construye a partir de ella y, al
ejecutar, se genera el `in.mcv` de la ejecución sustituyendo en la
plantilla solo los valores editados; el resto de líneas (separadores,
comentarios y campos fijos) se copia tal cual, porque el simulador lee el
fichero por posición de línea.

Para partir de otra configuración, la página de configuración tiene el
panel **Importar in.mcv**: se elige un `in.mcv` del equipo, el formulario
se rellena con sus valores y ese fichero pasa a ser la base de la
ejecución. Solo se aceptan ficheros con la misma estructura que la
plantilla (mismo número de líneas y mismos `lmax` de la función de
onda), para que cada campo se lea de la línea correcta.

### Instalación

```bash
cd gui-visualizacion
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
```

### Arrancar

```bash
./venv/bin/python3 app.py
```

Abre <http://127.0.0.1:5057> en el navegador. Para desarrollar con recarga
automática y depurador: `DMC_GUI_DEBUG=1 ./venv/bin/python3 app.py`.

### Uso

1. **Configuración:** revisa o cambia los parámetros del formulario. Los
   valores se validan antes de lanzar nada.
2. **Compilar:** compila el simulador. La salida del compilador aparece en
   directo.
3. **Ejecutar:** lanza la simulación. Se muestran el registro, el bloque
   actual y el tiempo restante estimado. El botón *Parar* la detiene.
4. **Resultados:** al terminar, la página de resultados se abre sola.
   Desde su selector se pueden abrir también las ejecuciones anteriores.

**Limitación conocida:** se copia siempre `conf.20.00.HH`, preparado para
20 átomos de He4, 0 de He3 y la impureza H₂. Cambiar el número de átomos
de helio o la molécula en el formulario cambia el nombre del fichero de
configuración que espera el simulador, y la ejecución fallará.

### Pruebas

```bash
./venv/bin/python3 -m unittest discover -s pruebas -v
```

Usan el cliente de pruebas de Flask con carpetas temporales: no lanzan el
simulador ni modifican `settings.json` ni `runs/`.

### Seguridad

La interfaz está pensada para usarse **solo en local**: puede lanzar
procesos y escribir en disco, y no tiene autenticación. Por eso el
servidor escucha únicamente en `127.0.0.1`, rechaza las peticiones que no
vienen de la propia interfaz (comprobando las cabeceras `Origin` y
`Host`), exige cuerpos JSON y valida todos los valores antes de escribir
el `in.mcv`. No debe exponerse en una red.
