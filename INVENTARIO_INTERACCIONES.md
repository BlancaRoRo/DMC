# Inventario de interacciones de la interfaz

Lista de comprobación: para cada cosa que la persona usuaria puede hacer, qué entra,
qué comprueba el servidor, qué puede salir mal y **qué ve** en cada caso. Las celdas que
no tienen una respuesta clara son huecos.

- **Sección A (API)**: probada de verdad con `pruebas/sondeo_api.py`
  (`./venv/bin/python3 pruebas/sondeo_api.py`). No lanza el simulador ni toca `settings.json`
  ni `runs/`. La columna *Respuesta* es la observada, no la esperada.
- **Sección B (interfaz)**: obtenida leyendo `app-config.js`, `app-results.js` y
  `app-settings.js`. No está probada de forma automática.
- **Sección C**: huecos encontrados, con su prioridad y arreglo propuesto.

Estado: ✔ cubierto · ✖ hueco · ? no comprobado.

---

## A. Rutas de la API

| Ruta | Caso probado | Respuesta | Estado |
|---|---|---|---|
| Cualquier `POST` | `Origin` de otra página / `Sec-Fetch-Site: cross-site` | 403 | ✔ H11 |
| Cualquier petición | cabecera `Host` que no es local (DNS rebinding) | 403 | ✔ H11 |
| | ruta inexistente o error interno | JSON `{"error": …}`, nunca HTML | ✔ H5 |
| `GET /`, `/resultados` | normal | 200 | ✔ |
| `GET /api/config-schema` | normal | 200 | ✔ |
| `GET /api/binary-status` | normal | 200 | ✔ |
| `POST /api/parse-inmcv` | contenido vacío | 400 "fichero vacio" | ✔ |
| | nº de líneas incorrecto | 400 con las líneas esperadas | ✔ |
| | cuerpo que no es JSON | 400 | ✔ |
| | `content` que no es texto | 400 | ✔ H5 |
| | cuerpo que es una lista | 400 | ✔ H5 |
| `GET/POST /api/settings` | ruta vacía | 400 "ruta vacia" | ✔ |
| | carpeta de fuentes o binario inexistente | 400 "esa carpeta no existe" | ✔ |
| | ruta de fuentes que es un **fichero** | 400 "no es una carpeta" | ✔ H7 |
| | `runs_dir` **relativa** | 400, no crea nada | ✔ H6 |
| | valor que no es texto (`5`) | 400 | ✔ H6 |
| | cuerpo que es una lista | 400 | ✔ H6 |
| `POST /api/settings/pick-folder` | campo desconocido | 400 | ✔ |
| `POST /api/compile` | carpeta sin `compilar_pipeline.sh` | 400 "no existe compilar_pipeline.sh" | ✔ |
| `POST /api/run` | `valores` que no es objeto | 400 | ✔ |
| | número no válido (`abc`) | 400 con el nombre del campo | ✔ |
| | par con 3 valores | 400 | ✔ |
| | `in.mcv` importado con estructura distinta | 400 | ✔ |
| | cuerpo que no es JSON | 400 | ✔ |
| | nombre de 500 caracteres | 200 (se recorta a 80 sin avisar) | ✔ |
| | número `nan` / `inf` | 400 | ✔ H3 |
| | número con salto de línea **al final** (`"20\n"`) | 200: se eliminan los espacios y saltos de los extremos; el `in.mcv` sigue teniendo 110 líneas | ✔ H1 |
| | número con salto de línea **en medio** (`"2\n0"`) | 400 | ✔ H1 |
| | texto con salto de línea (`"H\n99"`) | 400 | ✔ H1 |
| | desplegable con un valor fuera de las opciones | 400 | ✔ H2 |
| | clave que no es un número (`"abc"`) | 400 | ✔ H5 |
| | cuerpo que es una lista | 400 | ✔ H5 |
| | otra simulación en curso | 409 (visto por código y en pruebas reales) | ✔ |
| | binario o `conf` inexistente | 400 "compila primero" | ✔ |
| | dos lanzamientos en el mismo segundo | choque de carpeta `run_AAAAMMDD_HHMMSS` → 500 | ✖ H8 |
| `GET /api/run-activa` | normal | 200 | ✔ |
| `GET /api/runs` | normal | 200 | ✔ |
| `GET /api/runs/<id>/seguimiento` | id mal formado / inexistente | 404 | ✔ |
| | `desde=abc`, `desde=-5`, `desde` enorme | 200 (se corrige) | ✔ |
| `POST /api/runs/<id>/stop` | ejecución inexistente o no en curso | 404 | ✔ |
| `POST /api/jobs/<id>/stop` | job inexistente | 404 | ✔ |
| `GET /api/runs/<id>/histograms` | inexistente | 404 | ✔ |
| | ejecución sin histogramas | 200 con datos vacíos **y el estado de la ejecución**; la interfaz explica por qué | ✔ H9 |
| `GET /api/runs/<id>/final-config` | inexistente | 404 | ✔ |
| | sin `conf.*` | 404 con mensaje | ✔ |
| | `conf` corrupto (0 *walkers* o no numérico) | 422 con mensaje | ✔ H5 |
| | ejecución detenida o en curso | 409: no hay configuración final | ✔ H4 |
| `GET /api/runs/<id>/stats` | sin `salida.log` | 404 con mensaje | ✔ |
| | log sin formato | 200 (datos vacíos) | ✔ |
| `GET /api/runs/<id>/inmcv`, `/log` | inexistente | 404 | ✔ |

## B. Acciones de la interfaz (por lectura del código)

| Acción | Qué puede salir mal | Qué ve la persona usuaria | Estado |
|---|---|---|---|
| Importar `in.mcv` | fichero incompatible | mensaje rojo bajo el selector | ✔ |
| Escribir en el formulario | valor no numérico o texto no válido | no se avisa hasta pulsar Ejecutar; entonces el servidor lo rechaza con el nombre del campo y los botones se reactivan (verificado en Chrome) | ✔ (aviso tardío) |
| Cambiar de pestaña / "Siguiente" | (solo navegador) | nada que fallar | ✔ |
| Compilar | script inexistente, error del compilador | error o salida en el registro; botones se reactivan | ✔ |
| Ejecutar | error 400 / 409 | "error: …" en el registro; botones se reactivan | ✔ |
| | el servidor no responde | "error: …" en el registro | ✔ |
| Seguimiento | el servidor se cae o reinicia | "Sin conexión… reintentando" y se reengancha | ✔ |
| Recargar la página con la simulación corriendo | (probado en navegador) | se reengancha: registro, letrero y Parar | ✔ |
| Parar | ya no hay simulación | "no se pudo parar: …" | ✔ |
| Terminar con código ≠ 0 | fallo del simulador | "ejecución terminada (código X)", sin redirigir | ✔ |
| Guardar ajustes | ruta inválida | mensaje bajo el botón | ✔ |
| | el servidor no responde | "error: no se pudo contactar con el servidor" | ✔ H10 |
| Elegir carpeta | diálogo cancelado | mensaje vacío | ✔ |
| Resultados sin ejecución elegida | — | "Todavía no hay resultados" | ✔ |
| Resultados: elegir ejecución | histogramas ausentes | "No hay histogramas…" en Angulares/Radiales | ✔ H9 |
| | servidor no responde o ejecución inexistente | aviso "No se pudieron cargar los resultados: …" | ✔ H9 |
| | ejecución en curso o detenida | letrero con el estado; la pestaña Nube explica que no hay configuración final | ✔ H4 |
| Numéricos | `salida.log` ausente | mensaje en la tarjeta (las gráficas quedan vacías) | ✔ |
| Compilar en dos pestañas a la vez | dos compilaciones simultáneas | no comprobado | ? H12 |

## C. Huecos y arreglo propuesto

| Id | Prioridad | Hueco | Arreglo | Estado |
|---|---|---|---|---|
| H1 | **Alta** | Un salto de línea en un campo numérico o de texto desplaza todo el `in.mcv`: la simulación corre con datos equivocados sin ningún error. | Se recortan espacios y saltos de los extremos, se rechaza cualquier salto interior, y se comprueba que el `in.mcv` generado tiene las mismas líneas que el de referencia. | ✔ corregido |
| H2 | **Alta** | Los desplegables aceptan cualquier valor. | Validar contra la lista de opciones del campo; en los de texto, patrón (`^[A-Za-z]{1,3}$`). | ✔ corregido |
| H3 | Media | `nan` e `inf` pasan la validación numérica. | Exigir número finito (`math.isfinite`). | ✔ corregido |
| H4 | **Alta** | Una ejecución detenida (o en curso) muestra en la pestaña Nube la configuración inicial como si fuera la final, sin ningún aviso. | Servir `final-config` solo si `estado == terminada` y código 0, y mostrar el estado de la ejecución en Resultados. | ✔ corregido |
| H5 | Media | Varias entradas malformadas dan 500 (clave no numérica, cuerpo que no es objeto, `conf` corrupto). | Comprobar el tipo del cuerpo y capturar errores de lectura; devolver siempre un JSON de error. | ✔ corregido |
| H6 | Media | Ajustes acepta rutas relativas y valores que no son texto. | Exigir texto y ruta absoluta; 400 si el cuerpo no es un objeto. | ✔ corregido |
| H7 | Baja | Mensaje "no existe" cuando la ruta es un fichero. | Distinguir "no existe" de "no es una carpeta". | ✔ corregido |
| H8 | Baja | Dos ejecuciones en el mismo segundo colisionan. | Añadir un sufijo o contador al identificador. | ✖ abierto |
| H9 | Media | Resultados no avisa si faltan histogramas ni si el servidor no responde. | Mensaje en la pestaña y `try/catch` en `loadResults`. | ✔ corregido |
| H10 | Baja | Guardar ajustes queda en "guardando…" si el servidor no responde. | `try/catch` con mensaje de error. | ✔ corregido |
| H11 | **Alta** (seguridad) | `get_json(force=True)` acepta peticiones de otras páginas; `debug=True` siempre. | Exigir JSON real, comprobar `Origin`/`Host`, fijar `host="127.0.0.1"` y desactivar `debug` por defecto. | ✔ corregido |
| H12 | Baja | Compilaciones simultáneas sin comprobar. | Bloqueo, o comprobación como en Ejecutar. | ✖ abierto |
