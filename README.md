# DMC · panel de control (Fase 1)

Interfaz web local para compilar/ejecutar el pipeline CUDA Fortran
(`v2-cuda-integracion/hibrido_instrumentado`) y visualizar sus resultados:
histogramas (radiales + angulares) y la configuraci&oacute;n final de walkers
en 3D.

**Fase 1**: usa &uacute;nicamente datos que el simulador ya produce hoy
(histogramas finales, `conf.*.HH` final) -- no toca el c&oacute;digo
Fortran/CUDA. La animaci&oacute;n paso a paso de la evoluci&oacute;n de los
walkers por bloque queda para una Fase 2, que requiere a&ntilde;adir
instrumentaci&oacute;n nueva al simulador (volcar posiciones por bloque, hoy
no existe).

## C&oacute;mo cada ejecuci&oacute;n queda aislada

Cada clic en "Ejecutar" copia el binario ya compilado + un `conf.20.00.HH`
fresco (de `v1-cuda-desarrollo/ccuerpo/conf.20.00.HH`, mismo criterio
`CONF_FRESCO` que el resto del proyecto) + el `in.mcv` editado a un
directorio nuevo bajo `runs/run_<timestamp>/`, y lo ejecuta ah&iacute; --
nunca se lanza nada dentro de `hibrido_instrumentado/`, que solo se usa
para compilar.

**Limitaci&oacute;n conocida**: el preset por defecto usa 20 &aacute;tomos
de He4 (mismo que `conf.20.00.HH`). Si cambias `nhe4`/`nhe3`/la
mol&eacute;cula impureza en el `in.mcv`, el nombre de fichero de
configuraci&oacute;n esperado cambia (`nombre = nhe4.nhe3.molecula`,
ver `mentradatos.f90:406`) y el `conf.20.00.HH` fresco copiado ya no
coincidir&aacute; -- de momento solo se soportan cambios que no alteren
`nhe4`/`nhe3`/la mol&eacute;cula.

## Arrancar

```bash
cd gui-visualizacion
./venv/bin/python app.py
```

Abre `http://localhost:5057`.

El servidor escucha **solo en `127.0.0.1`** y con el modo de depuraci&oacute;n
**desactivado**. Para desarrollar con recarga autom&aacute;tica:
`DMC_GUI_DEBUG=1 ./venv/bin/python app.py`.

## Seguridad (uso local)

La interfaz puede lanzar procesos y escribir en disco, as&iacute; que
`app.py` protege las rutas `POST`: rechaza (403) las peticiones cuyo
`Origin`/`Sec-Fetch-Site` no sea el propio servidor y las que llegan con
una cabecera `Host` no local (DNS rebinding); exige JSON real; valida los
valores del `in.mcv` (n&uacute;meros finitos, opciones de los
desplegables, texto `^[A-Za-z]{1,3}$`, sin saltos de l&iacute;nea que
desplacen las l&iacute;neas del fichero); y responde siempre con JSON de
error, nunca con HTML ni un 500 por entrada mal formada. No est&aacute;
pensada para exponerse en una red: no hay autenticaci&oacute;n.

Lista de comprobaci&oacute;n por interacci&oacute;n y huecos que siguen
abiertos: `INVENTARIO_INTERACCIONES.md`.

## Pruebas

```bash
cd gui-visualizacion
true
```

Usan el cliente de pruebas de Flask con carpetas temporales: no lanzan el
simulador ni tocan `settings.json` ni `runs/`.

## Flujo

1. **Compilar**: lanza `compilar_pipeline.sh` dentro de
   `hibrido_instrumentado/` (en vivo, por streaming).
2. **Ejecutar**: copia el binario + conf fresco + `in.mcv` a un run
   aislado y lo lanza (en vivo, por streaming).
3. Al terminar, se cargan autom&aacute;ticamente los gr&aacute;ficos:
   nube de puntos 3D de la configuraci&oacute;n final de walkers,
   histogramas radiales (l&iacute;nea) e histogramas angulares
   (dispersi&oacute;n coloreada por valor).
4. **Corridas anteriores**: lista de runs previos, cada uno reabre sus
   propios resultados.
