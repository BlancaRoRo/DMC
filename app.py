"""
Interfaz web para compilar/ejecutar el pipeline DMC (v2-cuda-integracion/
hibrido_instrumentado) y visualizar histogramas + la configuracion final de
walkers. Fase 1: usa solo datos que el simulador ya produce (histogramas
finales, conf.*.HH final) -- no toca el codigo Fortran/CUDA.

Cada ejecucion corre en su propio directorio aislado bajo runs/, con su
propio conf.20.00.HH "fresco" copiado de la carpeta del binario (o, si no
esta ahi, de la de compilacion; ver buscar_conf_fresco) -- nunca se lanza
nada dentro de hibrido_instrumentado/, que solo se usa para compilar.
"""
import glob
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from urllib.parse import urlparse

from flask import Flask, Response, jsonify, request, send_from_directory
from werkzeug.exceptions import HTTPException

APP_DIR = Path(__file__).resolve().parent
REPO_ROOT = APP_DIR.parent
HIBRIDO_DIR = REPO_ROOT / "v2-cuda-integracion" / "hibrido_instrumentado"
CONF_NOMBRE = "conf.20.00.HH"
# plantilla del in.mcv: el formulario se construye a partir de ella y cada
# ejecucion parte de ella (o de un in.mcv importado con su misma
# estructura), sustituyendo solo las lineas editadas
DEFAULT_INMCV = APP_DIR / "plantilla" / "in.mcv"
DEFAULT_RUNS_DIR = APP_DIR / "runs"
SETTINGS_PATH = APP_DIR / "settings.json"
BINARY_NAME = "qmccluster_pipeline"
COMPILE_SCRIPT = "compilar_pipeline.sh"

# Ajustes editables desde la interfaz (ver /api/settings). 'create=True'
# es para carpetas de SALIDA -- se crean si no existen todavia (runs_dir).
# 'create=False' es para carpetas de ENTRADA que deben existir ya
# (source_dir/binary_dir): source_dir/compile_script es lo que compila
# "Compilar", binary_dir/BINARY_NAME es lo que ejecuta "Ejecutar" --
# separadas para poder apuntar "Ejecutar" a un binario ya compilado en
# otro sitio sin tener que recompilar. Por defecto las dos son
# HIBRIDO_DIR, que es donde compilar_pipeline.sh deja el binario.
SETTINGS_KEYS = {
    "runs_dir": {"default": DEFAULT_RUNS_DIR, "create": True},
    "source_dir": {"default": HIBRIDO_DIR, "create": False},
    "binary_dir": {"default": HIBRIDO_DIR, "create": False},
}

RADIAL_HISTS = [
    ("dhe4he4", "Radial He4-He4"),
    ("dhe3he3", "Radial He3-He3"),
    ("dhe4he3", "Radial He4-He3"),
    ("dihe4", "Radial impureza-He4"),
    ("dihe3", "Radial impureza-He3"),
    ("dihe", "Radial impureza-He"),
]
ANGULAR_HISTS = [
    ("d2dhe", "Angular impureza-He"),
    ("d2dhe4", "Angular impureza-He4"),
    ("d2dhe3", "Angular impureza-He3"),
    ("d2ydhe", "Angular-Y impureza-He"),
    ("d2ydhe4", "Angular-Y impureza-He4"),
    ("d2ydhe3", "Angular-Y impureza-He3"),
]

app = Flask(__name__, static_folder="static", static_url_path="")

DEFAULT_RUNS_DIR.mkdir(exist_ok=True)


# ---------------------------------------------------------------------
# Seguridad basica y entradas. Es una herramienta LOCAL, pero el
# navegador puede recibir peticiones desde OTRAS paginas web (CSRF) o
# mediante DNS rebinding, asi que:
#  - solo se atiende a localhost / 127.0.0.1 (cabecera Host);
#  - las peticiones que modifican algo (POST) solo se aceptan si vienen
#    de esta misma interfaz (cabecera Origin o Sec-Fetch-Site);
#  - los cuerpos deben ser JSON de verdad (sin force=True), lo que
#    ademas obliga a los navegadores a una comprobacion previa que otra
#    pagina no puede superar.
# ---------------------------------------------------------------------
HOSTS_LOCALES = {"localhost", "127.0.0.1", "::1"}


@app.before_request
def _proteger_peticion():
    if urlparse("//" + request.host).hostname not in HOSTS_LOCALES:
        return jsonify({"error": "host no permitido"}), 403
    if request.method not in ("GET", "HEAD", "OPTIONS"):
        origen = request.headers.get("Origin")
        if origen is not None:
            if origen == "null" or urlparse(origen).netloc != request.host:
                return jsonify({"error": "origen no permitido"}), 403
        elif request.headers.get("Sec-Fetch-Site") not in (None, "same-origin", "none"):
            return jsonify({"error": "origen no permitido"}), 403


def _cuerpo_objeto():
    """(cuerpo, None) si la peticion trae un objeto JSON; (None, respuesta_de_error) si no."""
    if not request.is_json:
        return None, (jsonify({"error": "la peticion debe enviarse como JSON (Content-Type: application/json)"}), 415)
    cuerpo = request.get_json(silent=True)
    if not isinstance(cuerpo, dict):
        return None, (jsonify({"error": "el cuerpo debe ser un objeto JSON"}), 400)
    return cuerpo, None


@app.errorhandler(Exception)
def _error_en_json(e):
    """Cualquier error no previsto sale como JSON (la interfaz siempre
    espera JSON), nunca como pagina HTML de error."""
    if isinstance(e, HTTPException):
        if request.path.startswith("/api/"):
            return jsonify({"error": e.description}), e.code
        return e
    app.logger.exception("error no controlado en %s", request.path)
    return jsonify({"error": f"error interno del servidor ({type(e).__name__})"}), 500


# Valores que el formulario puede enviar. Todo lo que se escribe en el
# in.mcv se valida ANTES: un salto de linea desplazaria el resto del
# fichero (el lector de Fortran es posicional) y la simulacion correria
# con datos equivocados sin ningun error.
_RE_NUMERO = re.compile(r"^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][+-]?\d+)?$")
_RE_TEXTO = re.compile(r"^[A-Za-z0-9._+-]{1,24}$")


def _valor_a_texto(v):
    if isinstance(v, bool) or not isinstance(v, (str, int, float)):
        return None
    return str(v).strip()


def _numero_valido(t):
    t = t.replace(",", ".")
    return bool(_RE_NUMERO.match(t)) and math.isfinite(float(t.replace("d", "e").replace("D", "e")))


def _limpiar_valores(valores):
    """Valida y normaliza los valores del formulario. Devuelve
    ({linea(int): texto | [texto, texto]}, None) o (None, mensaje_de_error).
    Las lineas desconocidas o no editables se ignoran (como siempre)."""
    campos = {c["linea"]: c for c in TODOS_LOS_CAMPOS}
    limpios = {}
    for clave, nuevo in valores.items():
        try:
            linea = int(clave)
        except (TypeError, ValueError):
            return None, f"clave de linea no valida: {clave!r}"
        campo = campos.get(linea)
        if campo is None or not campo["editable"]:
            continue
        et = campo["etiqueta"]
        if campo["par"]:
            if not (isinstance(nuevo, list) and len(nuevo) == 2):
                return None, f"'{et}': se esperaban 2 valores"
            par = []
            for v in nuevo:
                t = _valor_a_texto(v)
                if t is None or not _numero_valido(t):
                    return None, f"'{et}': valor invalido {v!r}"
                par.append(t.replace(",", "."))
            limpios[linea] = par
            continue
        t = _valor_a_texto(nuevo)
        if t is None:
            return None, f"'{et}': valor invalido {nuevo!r}"
        if campo["tipo"] == "number":
            if not _numero_valido(t):
                return None, f"'{et}': valor invalido {nuevo!r}"
            t = t.replace(",", ".")
        elif campo["tipo"] == "select":
            if t not in campo["opciones"]:
                return None, f"'{et}': debe ser uno de {', '.join(campo['opciones'])}"
        elif not _RE_TEXTO.match(t):
            return None, f"'{et}': texto no valido (solo letras, numeros y . _ + -)"
        limpios[linea] = t
    return limpios, None


def load_settings():
    if SETTINGS_PATH.exists():
        try:
            data = json.loads(SETTINGS_PATH.read_text())
        except (json.JSONDecodeError, OSError):
            data = {}
    else:
        data = {}
    for key, cfg in SETTINGS_KEYS.items():
        data.setdefault(key, str(cfg["default"]))
    return data


def save_settings(data):
    SETTINGS_PATH.write_text(json.dumps(data, indent=2))


def get_runs_dir():
    d = Path(load_settings()["runs_dir"])
    d.mkdir(parents=True, exist_ok=True)
    return d


def get_source_dir():
    return Path(load_settings()["source_dir"])


def get_binary_dir():
    return Path(load_settings()["binary_dir"])


def buscar_conf_fresco():
    """Configuracion inicial que se copia a cada ejecucion. Como los .pot,
    es un dato que se lee al EJECUTAR, asi que se busca primero junto al
    binario y, si no esta ahi, junto a los ficheros a compilar. Las dos
    carpetas se eligen en Ajustes, asi que no depende de donde este la
    interfaz. Devuelve None si no esta en ninguna."""
    for carpeta in (get_binary_dir(), get_source_dir()):
        candidato = carpeta / CONF_NOMBRE
        if candidato.is_file():
            return candidato
    return None


def _pick_folder_dialog(initial_dir):
    """Abre el selector de carpetas nativo del escritorio y devuelve la
    ruta elegida, o None si se cancela. Corre en un subproceso aparte
    (nunca en el propio hilo de Flask, que no es el hilo principal con
    threaded=True) para no interferir con el bucle de eventos del
    servidor. Usa zenity si esta disponible (dialogo GTK del propio
    escritorio, igual que 'abrir archivo' de cualquier aplicacion del
    sistema); si no, cae a tkinter, que viene con Python."""
    if shutil.which("zenity"):
        resultado = subprocess.run(
            [
                "zenity", "--file-selection", "--directory",
                "--title=Elegir carpeta para las ejecuciones",
                f"--filename={initial_dir}/",
            ],
            capture_output=True, text=True,
        )
        if resultado.returncode != 0:
            return None
        return resultado.stdout.strip() or None

    script = (
        "import tkinter, tkinter.filedialog as fd\n"
        "root = tkinter.Tk(); root.withdraw(); root.attributes('-topmost', True)\n"
        "print(fd.askdirectory(initialdir=%r, "
        "title='Elegir carpeta para las ejecuciones') or '')\n" % initial_dir
    )
    resultado = subprocess.run(
        [sys.executable, "-c", script], capture_output=True, text=True, timeout=300,
    )
    return resultado.stdout.strip() or None


def _parse_valor_comentario(linea):
    """Separa 'valor  !comentario' -- devuelve (valor_crudo, comentario)."""
    if "!" in linea:
        valor, comentario = linea.split("!", 1)
        return valor.strip(), comentario.strip()
    return linea.strip(), ""


# ---------------------------------------------------------------------
# Registro de TODOS los campos de in.mcv usados por esta interfaz.
# 'linea' es el numero de linea 1-based tal cual esta en el fichero.
# 'editable=False' son los campos que este TFG fija por como esta
# construido el pipeline GPU/CUDA (no por eleccion de esta corrida):
#   - opot debe ser 4 (unico potencial impureza-Helio implementado en
#     los kernels CUDA de He_dihydrogen).
#   - el fichero de potencial esta atado a ese opot=4.
#   - el numero de atomos de la impureza esta fijado a 2 en el codigo
#     CUDA (ndih=2, arrays r_dih(3,2) en todos los kernels de
#     He_dihydrogen construidos esta sesion) -- cambiarlo rompe los
#     limites de esos arrays.
#   - opcion debe ser 7: es la unica que ejecuta el pipeline GPU con
#     CUDA Graph que compila este binario.
#   - lmax (impureza-He4/He3) cambia cuantos bloques de parametros
#     tiene el fichero -- no es un simple cambio de valor.
#   - ncadapvm solo se usa con PVM, no con el pipeline GPU.
#   - TODO lo relacionado con He3 (masa, numero de He3, delta metropolis
#     He3, bloque He3/backflow He3 de la tabla He-He, tabla completa
#     impureza-He3) esta fijo porque en esta configuracion numero de
#     He3=0 -- no hay ningun atomo He3 en la simulacion, esos valores
#     no se usan/no tienen efecto en el fichero.
# Todo lo demas es un parametro fisico/numerico de verdad y se deja
# editable.
# ---------------------------------------------------------------------
def _campo(linea, etiqueta, tipo="number", editable=True, opciones=None, par=False):
    return {
        "linea": linea, "etiqueta": etiqueta, "tipo": tipo,
        "editable": editable, "opciones": opciones, "par": par,
    }


SECCION_1 = [
    _campo(4, "Cálculo libre", tipo="select", opciones=[".T.", ".F."]),
    _campo(5, "Masa He4"),
    _campo(6, "Masa He3", editable=False),
    _campo(7, "Número de He4"),
    _campo(8, "Número de He3", editable=False),
    _campo(9, "Número de átomos en la impureza molecular", editable=False),
    _campo(10, "Átomo 1 de la impureza molecular", tipo="text"),
    _campo(11, "Masa del átomo 1"),
    _campo(12, "Átomo 2 de la impureza molecular", tipo="text"),
    _campo(13, "Masa del átomo 2"),
    _campo(14, "Distancia del átomo 2 al átomo 1"),
    _campo(15, "Unidades de distancia (1=u.a., cualquier otro=Å)", tipo="select", opciones=["1", "0"]),
    _campo(23, "Potencial impureza-Helio (opot)", editable=False),
    _campo(24, "Fichero de datos del potencial", tipo="text", editable=False),
    _campo(25, "La impureza se traslada", tipo="select", opciones=[".T.", ".F."]),
    _campo(26, "La impureza rota", tipo="select", opciones=[".T.", ".F."]),
]

SECCION_2 = [
    _campo(30, "Semilla aleatoria", tipo="text"),
    _campo(31, "Opción de programa", editable=False),
    _campo(32, "Se minimiza la energía (si no, la varianza)", tipo="select", opciones=[".T.", ".F."]),
    _campo(33, "Delta pasos metropolis He4"),
    _campo(34, "Delta pasos metropolis He3", editable=False),
    _campo(35, "Delta pasos CM impureza"),
    _campo(36, "Delta angular rotaciones impureza (grados)"),
    _campo(37, "Etrial"),
    _campo(38, "Dtau"),
    _campo(39, "Bloques de equilibrio"),
    _campo(40, "Pasos de descorrelación"),
    _campo(41, "Bloques de cálculo"),
    _campo(42, "Pasos por bloque"),
    _campo(43, "Número de walkers"),
    _campo(44, "Pasos para cambiar etrial (bloques de equilibrio)"),
]

SECCION_4 = [
    _campo(110, "ncadapvm", editable=False),
]

# He3/backflow-He3 (lineas 54-57) fijas: no hay He3 en esta configuracion.
TABLA_HEHE = [_campo(n, et, par=True, editable=(n not in (54, 55, 56, 57))) for n, et in zip(
    range(51, 61),
    ["b He4", "nu He4-He4", "alfa He4", "b He3", "nu He3-He3", "alfa He3",
     "b backflow He3", "b mezclas", "nu mezclas", "alfa mezclas"],
)]

TABLA_IMP_HE4_LMAX = _campo(67, "lmax polinomios de Legendre impureza-He4", editable=False)
TABLA_IMP_HE4 = [
    [_campo(base + i, et, par=True) for i, et in enumerate(["b", "nu", "alfa", "p4", "p5"])]
    for base in [69, 75, 81, 87, 93]
]

# tabla impureza-He3 entera fija: no hay He3 en esta configuracion.
TABLA_IMP_HE3_LMAX = _campo(98, "lmax polinomios de Legendre impureza-He3", editable=False)
TABLA_IMP_HE3 = [
    [_campo(100 + i, et, par=True, editable=False) for i, et in enumerate(["b", "nu", "alfa", "p4", "p5"])]
]

TODOS_LOS_CAMPOS = (
    SECCION_1 + SECCION_2 + SECCION_4
    + TABLA_HEHE + [TABLA_IMP_HE4_LMAX] + [c for fila in TABLA_IMP_HE4 for c in fila]
    + [TABLA_IMP_HE3_LMAX] + [c for fila in TABLA_IMP_HE3 for c in fila]
)


def _leer_campo(lineas, campo):
    valor, comentario = _parse_valor_comentario(lineas[campo["linea"] - 1])
    out = dict(campo)
    if campo["par"]:
        partes = valor.split()
        out["v1"] = partes[0] if len(partes) > 0 else ""
        out["v2"] = partes[1] if len(partes) > 1 else ""
    else:
        out["valor"] = valor
    return out


def validar_estructura_inmcv(texto):
    """Comprueba que un in.mcv (por defecto o importado) tiene EXACTAMENTE
    la misma estructura de lineas que el de referencia -- mismo numero de
    lineas totales y mismos lmax (impureza-He4/He3), que es lo que fija
    en que linea cae cada campo posterior. Si no coincide, los campos
    fijos (opcion, opot, etc, que vienen despues de la seccion de
    funcion de onda) se leerian de la linea equivocada. Devuelve None si
    es valido, o un mensaje de error explicando el porque no."""
    referencia = DEFAULT_INMCV.read_text().splitlines()
    lineas = texto.splitlines()
    if len(lineas) != len(referencia):
        return (f"el fichero tiene {len(lineas)} lineas, se esperaban "
                f"{len(referencia)} -- probablemente tiene un lmax de "
                f"impureza-He4/He3 distinto, no compatible con esta interfaz")
    lmax_he4_ref, _ = _parse_valor_comentario(referencia[TABLA_IMP_HE4_LMAX["linea"] - 1])
    lmax_he4_new, _ = _parse_valor_comentario(lineas[TABLA_IMP_HE4_LMAX["linea"] - 1])
    if lmax_he4_ref.strip() != lmax_he4_new.strip():
        return f"lmax impureza-He4 = {lmax_he4_new} -- se esperaba {lmax_he4_ref}"
    lmax_he3_ref, _ = _parse_valor_comentario(referencia[TABLA_IMP_HE3_LMAX["linea"] - 1])
    lmax_he3_new, _ = _parse_valor_comentario(lineas[TABLA_IMP_HE3_LMAX["linea"] - 1])
    if lmax_he3_ref.strip() != lmax_he3_new.strip():
        return f"lmax impureza-He3 = {lmax_he3_new} -- se esperaba {lmax_he3_ref}"
    return None


def build_config_schema(lineas=None):
    """Estructura de TODO in.mcv para la pagina de configuracion, con
    el valor ACTUAL de cada campo ya cargado (editable o no). Si no se
    pasa 'lineas' (lista de str, una por linea), usa el in.mcv de
    referencia por defecto."""
    if lineas is None:
        lineas = DEFAULT_INMCV.read_text().splitlines()

    return {
        "settings": load_settings(),
        "secciones": [
            {"titulo": "1. Datos del sistema",
             "campos": [_leer_campo(lineas, c) for c in SECCION_1]},
            {"titulo": "2. Datos Monte Carlo",
             "campos": [_leer_campo(lineas, c) for c in SECCION_2]},
            {"titulo": "3. Función de onda", "tablas": [
                {
                    "titulo": "He-He: f(r) = exp(-0.5*(b/r)^nu - alfa*r)",
                    "columnas": ["parámetro", "valor 1", "valor 2"],
                    "filas": [_leer_campo(lineas, c) for c in TABLA_HEHE],
                },
                {
                    "titulo": "Impureza-He4",
                    "lmax": _leer_campo(lineas, TABLA_IMP_HE4_LMAX),
                    "columnas": ["l", "b", "nu", "alfa", "p4", "p5"],
                    "filas": [
                        {"etiqueta": f"l={l}", "campos": [_leer_campo(lineas, c) for c in fila]}
                        for l, fila in enumerate(TABLA_IMP_HE4)
                    ],
                },
                {
                    "titulo": "Impureza-He3",
                    "lmax": _leer_campo(lineas, TABLA_IMP_HE3_LMAX),
                    "columnas": ["l", "b", "nu", "alfa", "p4", "p5"],
                    "filas": [
                        {"etiqueta": f"l={l}", "campos": [_leer_campo(lineas, c) for c in fila]}
                        for l, fila in enumerate(TABLA_IMP_HE3)
                    ],
                },
            ]},
            {"titulo": "4. Cálculo paralelo (solo si se usa PVM)",
             "campos": [_leer_campo(lineas, c) for c in SECCION_4]},
        ],
    }


def build_inmcv(valores, base_text=None):
    """Parte del in.mcv base (el de referencia, o uno importado si se
    pasa 'base_text') y sustituye SOLO el valor de las lineas editables
    recibidas en 'valores' (dict linea(str) -> texto, o linea(str) ->
    [v1, v2] para las filas de 2 valores), preservando el resto del
    fichero byte a byte -- el lector Fortran es list-directed
    (READ(5,*)), no depende de columnas exactas."""
    lineas = (base_text if base_text is not None else DEFAULT_INMCV.read_text()).splitlines()
    campos_por_linea = {c["linea"]: c for c in TODOS_LOS_CAMPOS}

    for linea_str, nuevo in valores.items():
        linea = int(linea_str)
        campo = campos_por_linea.get(linea)
        if campo is None or not campo["editable"]:
            continue  # ignora silenciosamente cualquier campo no editable
        _, comentario = _parse_valor_comentario(lineas[linea - 1])
        if campo["par"]:
            v1, v2 = nuevo
            lineas[linea - 1] = f" {v1}  {v2}       !{comentario}"
        elif campo["tipo"] == "text":
            # SIN espacio inicial: el simbolo de atomo (p.ej. "H") se
            # lee con read(5,'(a)') sobre una variable character(len=3)
            # -- un espacio inicial desplaza la letra y el programa
            # deja de reconocerla (verificado: daba una energia final
            # totalmente distinta, sin ningun error de lectura).
            lineas[linea - 1] = f"{nuevo}                    !{comentario}"
        else:
            lineas[linea - 1] = f" {nuevo}             !{comentario}"

    return "\n".join(lineas) + "\n"


def sse(event, data):
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"


def nombre_por_defecto():
    return time.strftime("%d-%m-%y_%H:%M")


def nombre_de_run(run_dir):
    nombre_path = run_dir / "nombre.txt"
    if nombre_path.exists():
        nombre = nombre_path.read_text().strip()
        if nombre:
            return nombre
    return run_dir.name


# registro de procesos en curso (compilacion o ejecucion), indexados por
# job_id, para poder pararlos desde /api/jobs/<job_id>/stop -- una peticion
# HTTP separada de la que esta consumiendo el stream SSE del propio proceso.
RUNNING_PROCS = {}
RUNNING_PROCS_LOCK = threading.Lock()


def stream_subprocess(cmd, cwd, stdin_path=None, log_path=None, job_id=None):
    """Lanza un subproceso y va cediendo (yield) cada linea de stdout/stderr
    como eventos SSE 'log', y un evento final 'done' con el codigo de
    salida. Si se pasa 'log_path', ademas escribe la salida completa ahi
    -- el binario solo imprime la tabla de bloques/resultados finales
    por pantalla, nunca a fichero, asi que sin esto no habria forma de
    volver a leerla despues (para la pestana de resultados numericos).

    'stdin_path' (no 'stdin_text'/pipe): el binario relee su propia
    entrada dos veces por dentro (mentradatos.f90, escribein -- primero
    la copia linea a linea con formato de ancho fijo A90 a un fichero
    'in.copia', luego reabre ESE fichero para las lecturas reales). Con
    una tuberia (subprocess.PIPE) esto dio energias distintas a las de
    referencia sin ningun error visible -- probablemente una diferencia
    real de comportamiento de E/S formateada de nvfortran entre unit 5
    conectado a un pipe vs a un fichero regular. Usar SIEMPRE un
    fichero real como entrada (< fichero, igual que en todo el resto
    del proyecto) elimina esa diferencia de raiz, en vez de solo
    esconderla."""
    stdin_fh = open(stdin_path) if stdin_path else None
    proc = subprocess.Popen(
        cmd,
        cwd=cwd,
        stdin=stdin_fh,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    if stdin_fh:
        stdin_fh.close()
    if job_id:
        with RUNNING_PROCS_LOCK:
            RUNNING_PROCS[job_id] = proc
    log_file = open(log_path, "w") if log_path else None
    try:
        for line in proc.stdout:
            if log_file:
                log_file.write(line)
            yield sse("log", {"line": line.rstrip("\n")})
    finally:
        if log_file:
            log_file.close()
    proc.wait()
    if job_id:
        with RUNNING_PROCS_LOCK:
            RUNNING_PROCS.pop(job_id, None)
    yield sse("done", {"returncode": proc.returncode})


# ---------------------------------------------------------------------
# Ejecuciones en SEGUNDO PLANO. Una simulacion no depende de que la
# pagina siga abierta: se lanza en su propia sesion de procesos
# (start_new_session) a traves de un pequeno 'bash -c' que redirige la
# salida directamente a salida.log y, al terminar, deja el codigo de
# salida en 'returncode'. Asi sobrevive a recargar la pagina, cerrarla o
# reiniciar el servidor. El estado se deduce de los ficheros del propio
# directorio de la ejecucion:
#   meta.json    -> {"pid": <pid del bash>, "inicio": <epoch>}
#   returncode   -> existe (y no esta vacio) si termino por si sola
#   sin returncode y proceso vivo    -> corriendo
#   sin returncode y proceso muerto  -> detenida (parada o cortada)
#   sin meta.json                    -> desconocido (ejecuciones antiguas)
# ---------------------------------------------------------------------
def _pid_vivo(pid):
    """True si 'pid' es aun un 'bash -c ./qmccluster...' nuestro y no un
    zombi (evita dar por viva una ejecucion por reutilizacion del pid)."""
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return False
    if stat.rsplit(")", 1)[1].split()[0] == "Z":
        return False
    return BINARY_NAME.encode() in cmdline


def _meta_run(run_dir):
    try:
        return json.loads((run_dir / "meta.json").read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def estado_run(run_dir):
    """Devuelve {"estado": ..., "returncode": ...} de una ejecucion."""
    rc_file = run_dir / "returncode"
    if rc_file.exists():
        texto = rc_file.read_text().strip()
        if texto:
            try:
                return {"estado": "terminada", "returncode": int(texto)}
            except ValueError:
                return {"estado": "terminada", "returncode": None}
        return {"estado": "corriendo", "returncode": None}
    pid = _meta_run(run_dir).get("pid")
    if pid is None:
        return {"estado": "desconocido", "returncode": None}
    if _pid_vivo(pid):
        return {"estado": "corriendo", "returncode": None}
    return {"estado": "detenida", "returncode": None}


def run_activa():
    """(run_dir) de la ejecucion que esta corriendo ahora, o None. Solo se
    permite una a la vez: comparten GPU y la interfaz sigue una sola."""
    runs_dir = get_runs_dir()
    for d in sorted((p for p in runs_dir.iterdir() if p.is_dir()), reverse=True):
        if (d / "meta.json").exists() and not (d / "returncode").exists():
            if estado_run(d)["estado"] == "corriendo":
                return d
    return None


def lanzar_run_en_segundo_plano(run_dir):
    cmd = f"./{BINARY_NAME} < in.mcv > salida.log 2>&1; echo $? > returncode"
    proc = subprocess.Popen(
        ["bash", "-c", cmd], cwd=str(run_dir), start_new_session=True,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    (run_dir / "meta.json").write_text(json.dumps({"pid": proc.pid, "inicio": time.time()}))
    # recoge el proceso al terminar (si no, quedaria como zombi hasta que
    # reiniciase el servidor)
    threading.Thread(target=proc.wait, daemon=True).start()


@app.route("/")
def index():
    return send_from_directory(app.static_folder, "config.html")


@app.route("/resultados")
def resultados():
    return send_from_directory(app.static_folder, "results.html")


@app.route("/api/config-schema")
def config_schema():
    return jsonify(build_config_schema())


@app.route("/api/parse-inmcv", methods=["POST"])
def parse_inmcv():
    body, err = _cuerpo_objeto()
    if err:
        return err
    contenido = body.get("content", "")
    if not isinstance(contenido, str):
        return jsonify({"error": "'content' debe ser texto"}), 400
    if not contenido.strip():
        return jsonify({"error": "fichero vacio"}), 400

    error = validar_estructura_inmcv(contenido)
    if error:
        return jsonify({"error": error}), 400

    schema = build_config_schema(contenido.splitlines())
    schema["base_inmcv"] = contenido
    return jsonify(schema)


@app.route("/api/binary-status")
def binary_status():
    binpath = get_binary_dir() / BINARY_NAME
    exists = binpath.exists()
    mtime = binpath.stat().st_mtime if exists else None
    return jsonify({"exists": exists, "mtime": mtime, "path": str(binpath)})


@app.route("/api/compile", methods=["POST"])
def compile_pipeline():
    source_dir = get_source_dir()
    if not (source_dir / COMPILE_SCRIPT).exists():
        return jsonify({"error": f"no existe {COMPILE_SCRIPT} en {source_dir}"}), 400

    def generate():
        job_id = time.strftime("compile_%Y%m%d_%H%M%S")
        yield sse("started", {"job_id": job_id})
        yield sse("log", {"line": f"$ bash {COMPILE_SCRIPT}  (cwd={source_dir})"})
        yield from stream_subprocess(["bash", COMPILE_SCRIPT], cwd=str(source_dir), job_id=job_id)

    return Response(generate(), mimetype="text/event-stream")


@app.route("/api/settings", methods=["GET", "POST"])
def settings():
    if request.method == "GET":
        return jsonify(load_settings())

    body, err = _cuerpo_objeto()
    if err:
        return err
    data = load_settings()

    for key, cfg in SETTINGS_KEYS.items():
        if key not in body:
            continue
        raw = body[key]
        if not isinstance(raw, str):
            return jsonify({"error": f"la ruta ({key}) debe ser texto"}), 400
        raw = raw.strip()
        if not raw:
            return jsonify({"error": f"ruta vacia ({key})"}), 400
        ruta = Path(raw).expanduser()
        if not ruta.is_absolute():
            return jsonify({"error": f"la ruta debe ser absoluta (empieza por /): {raw}"}), 400
        try:
            ruta = ruta.resolve()
            if cfg["create"]:
                ruta.mkdir(parents=True, exist_ok=True)
            elif not ruta.exists():
                return jsonify({"error": f"esa carpeta no existe: {ruta}"}), 400
            elif not ruta.is_dir():
                return jsonify({"error": f"eso no es una carpeta: {ruta}"}), 400
        except OSError as e:
            return jsonify({"error": f"no se pudo usar esa ruta: {e}"}), 400
        data[key] = str(ruta)

    save_settings(data)
    return jsonify(data)


@app.route("/api/settings/pick-folder", methods=["POST"])
def pick_folder():
    body, err = _cuerpo_objeto()
    if err:
        return err
    campo = body.get("campo", "runs_dir")
    if campo not in SETTINGS_KEYS:
        return jsonify({"error": f"campo de ajuste desconocido: {campo}"}), 400

    inicio = load_settings()[campo]
    try:
        elegida = _pick_folder_dialog(inicio)
    except (OSError, subprocess.TimeoutExpired) as e:
        return jsonify({"error": f"no se pudo abrir el selector de carpetas: {e}"}), 500
    if not elegida:
        return jsonify({"cancelled": True})
    return jsonify({"path": elegida})


@app.route("/api/run", methods=["POST"])
def run_simulation():
    body, err = _cuerpo_objeto()
    if err:
        return err
    valores = body.get("valores", {})
    if not isinstance(valores, dict):
        return jsonify({"error": "'valores' debe ser un objeto {linea: valor}"}), 400

    limpios, error = _limpiar_valores(valores)
    if error:
        return jsonify({"error": error}), 400

    base_inmcv = body.get("base_inmcv")
    if base_inmcv is not None and not isinstance(base_inmcv, str):
        return jsonify({"error": "'base_inmcv' debe ser texto"}), 400
    if base_inmcv:
        error = validar_estructura_inmcv(base_inmcv)
        if error:
            return jsonify({"error": "in.mcv base importado invalido: " + error}), 400

    inmcv_content = build_inmcv(limpios, base_text=base_inmcv or None)
    # red de seguridad: el in.mcv generado debe tener EXACTAMENTE la
    # estructura del de referencia (mismo numero de lineas y lmax)
    error = validar_estructura_inmcv(inmcv_content)
    if error:
        return jsonify({"error": "el in.mcv generado no es valido: " + error}), 400

    en_curso = run_activa()
    if en_curso is not None:
        return jsonify({"error": f"ya hay una simulacion en marcha ({nombre_de_run(en_curso)}) -- "
                                 "espera a que termine o pararla antes de lanzar otra"}), 409

    binary_dir = get_binary_dir()
    binpath = binary_dir / BINARY_NAME
    if not binpath.exists():
        return jsonify({"error": "compila primero -- no existe " + BINARY_NAME + " en " + str(binary_dir)}), 400
    conf_fresco = buscar_conf_fresco()
    if conf_fresco is None:
        return jsonify({"error": f"no se encuentra {CONF_NOMBRE} ni en la carpeta del binario "
                                 f"({binary_dir}) ni en la de compilacion ({get_source_dir()})"}), 400

    nombre = str(body.get("nombre", "")).strip().replace("\n", " ").replace("\r", "")[:80]
    if not nombre:
        nombre = nombre_por_defecto()

    run_id = time.strftime("run_%Y%m%d_%H%M%S")
    run_dir = get_runs_dir() / run_id
    run_dir.mkdir(parents=True, exist_ok=False)

    shutil.copy(binpath, run_dir / BINARY_NAME)
    shutil.copy(conf_fresco, run_dir / CONF_NOMBRE)
    (run_dir / "in.mcv").write_text(inmcv_content)
    (run_dir / "nombre.txt").write_text(nombre)
    # ficheros de datos auxiliares (potenciales, etc.) que el binario lee
    # en tiempo de ejecucion por nombre -- no van compilados en el binario.
    # se cogen de binary_dir (no source_dir): si se apunta "Ejecutar" a un
    # binario ya compilado en otro sitio, sus .pot deben venir de ahi.
    for potfile in binary_dir.glob("*.pot"):
        shutil.copy(potfile, run_dir / potfile.name)

    lanzar_run_en_segundo_plano(run_dir)
    return jsonify({"run_id": run_id, "nombre": nombre})


@app.route("/api/run-activa")
def run_activa_endpoint():
    d = run_activa()
    if d is None:
        return jsonify({"run_id": None})
    return jsonify({"run_id": d.name, "nombre": nombre_de_run(d)})


@app.route("/api/jobs/<job_id>/stop", methods=["POST"])
def stop_job(job_id):
    with RUNNING_PROCS_LOCK:
        proc = RUNNING_PROCS.get(job_id)
    if proc is None or proc.poll() is not None:
        return jsonify({"error": "no hay ninguna ejecucion en curso con ese id"}), 404

    proc.terminate()

    def _forzar_si_no_termina():
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    threading.Thread(target=_forzar_si_no_termina, daemon=True).start()
    return jsonify({"stopping": True})


@app.route("/api/runs")
def list_runs():
    runs_dir = get_runs_dir()
    run_ids = sorted((p.name for p in runs_dir.iterdir() if p.is_dir()), reverse=True)
    runs = [{"run_id": run_id, "nombre": nombre_de_run(runs_dir / run_id)} for run_id in run_ids]
    return jsonify({"runs": runs})


def _run_dir_or_404(run_id):
    if not re.fullmatch(r"run_\d{8}_\d{6}", run_id):
        return None
    d = get_runs_dir() / run_id
    return d if d.is_dir() else None

@app.route("/api/runs/<run_id>/seguimiento")
def run_seguimiento(run_id):
    """Estado de la ejecucion + el trozo de salida.log posterior al byte
    'desde'. Mientras corre solo se devuelven lineas COMPLETAS (hasta el
    ultimo salto de linea), para que la interfaz no reciba medias lineas."""
    run_dir = _run_dir_or_404(run_id)
    if run_dir is None:
        return jsonify({"error": "run no encontrado"}), 404
    try:
        desde = max(0, int(request.args.get("desde", "0")))
    except ValueError:
        desde = 0

    estado = estado_run(run_dir)  # se lee ANTES que el log: si ya termino, el log esta completo
    datos = b""
    log = run_dir / "salida.log"
    if log.exists():
        with open(log, "rb") as f:
            f.seek(desde)
            datos = f.read(512 * 1024)
        if estado["estado"] == "corriendo":
            datos = datos[: datos.rfind(b"\n") + 1]

    meta = _meta_run(run_dir)
    inicio = meta.get("inicio")
    if inicio is None:
        elapsed = None
    elif estado["estado"] == "terminada":
        elapsed = (run_dir / "returncode").stat().st_mtime - inicio
    elif estado["estado"] == "corriendo":
        elapsed = time.time() - inicio
    else:
        elapsed = (log.stat().st_mtime - inicio) if log.exists() else 0.0

    bloques = {"eq": 0, "ca": 0}
    try:
        lineas = (run_dir / "in.mcv").read_text().splitlines()
        bloques["eq"] = int(_parse_valor_comentario(lineas[38])[0])
        bloques["ca"] = int(_parse_valor_comentario(lineas[40])[0])
    except (OSError, ValueError, IndexError):
        pass

    return jsonify({
        **estado, "texto": datos.decode("utf-8", errors="replace"),
        "siguiente": desde + len(datos), "elapsed_s": elapsed,
        "bloques_eq": bloques["eq"], "bloques_ca": bloques["ca"],
        "nombre": nombre_de_run(run_dir),
    })


@app.route("/api/runs/<run_id>/stop", methods=["POST"])
def stop_run(run_id):
    run_dir = _run_dir_or_404(run_id)
    if run_dir is None:
        return jsonify({"error": "run no encontrado"}), 404
    pid = _meta_run(run_dir).get("pid")
    if pid is None or estado_run(run_dir)["estado"] != "corriendo":
        return jsonify({"error": "esa ejecucion no esta en curso"}), 404

    try:
        os.killpg(pid, signal.SIGTERM)  # pgid == pid (start_new_session)
    except ProcessLookupError:
        pass

    def _forzar_si_no_termina():
        for _ in range(50):
            time.sleep(0.1)
            if not _pid_vivo(pid):
                return
        try:
            os.killpg(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    threading.Thread(target=_forzar_si_no_termina, daemon=True).start()
    return jsonify({"stopping": True})


def _read_radial(path):
    xs, ys = [], []
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        xs.append(float(parts[0]))
        ys.append(float(parts[1]))
    return {"x": xs, "y": ys}


def _read_angular(path):
    """Los ficheros angulares son una rejilla regular (x,y,z) -- se
    reordena a matriz z[iy][ix] + ejes x/y unicos y ordenados, formato
    que espera un heatmap de Plotly (mapa de calor, no dispersion de
    puntos con color)."""
    puntos = []
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        puntos.append((float(parts[0]), float(parts[1]), float(parts[2])))

    xs_unicos = sorted({p[0] for p in puntos})
    ys_unicos = sorted({p[1] for p in puntos})
    idx_x = {v: i for i, v in enumerate(xs_unicos)}
    idx_y = {v: i for i, v in enumerate(ys_unicos)}

    matriz = [[0.0] * len(xs_unicos) for _ in range(len(ys_unicos))]
    for x, y, z in puntos:
        matriz[idx_y[y]][idx_x[x]] = z

    return {"x": xs_unicos, "y": ys_unicos, "z": matriz}


@app.route("/api/runs/<run_id>/histograms")
def run_histograms(run_id):
    run_dir = _run_dir_or_404(run_id)
    if run_dir is None:
        return jsonify({"error": "run no encontrado"}), 404

    radial, angular, omitidos = {}, {}, []
    for tabla, destino, lector in ((RADIAL_HISTS, radial, _read_radial), (ANGULAR_HISTS, angular, _read_angular)):
        for prefix, label in tabla:
            matches = glob.glob(str(run_dir / f"{prefix}.*"))
            if not matches:
                continue
            try:
                destino[prefix] = {"label": label, **lector(Path(matches[0]))}
            except (OSError, ValueError, IndexError):
                omitidos.append(prefix)  # fichero danado: se omite ese, no se cae todo

    return jsonify({"radial": radial, "angular": angular, "omitidos": omitidos, **estado_run(run_dir)})


@app.route("/api/runs/<run_id>/final-config")
def run_final_config(run_id):
    run_dir = _run_dir_or_404(run_id)
    if run_dir is None:
        return jsonify({"error": "run no encontrado"}), 404

    # El directorio de la ejecucion trae desde el principio un conf.*.HH
    # INICIAL (copiado antes de arrancar): solo es la configuracion final
    # si la simulacion termino bien. Las ejecuciones anteriores a este
    # control (estado "desconocido") se siguen sirviendo como antes.
    estado = estado_run(run_dir)
    if estado["estado"] == "corriendo":
        return jsonify({"error": "la ejecucion sigue en curso: todavia no hay configuracion final"}), 409
    if estado["estado"] == "detenida":
        return jsonify({"error": "la ejecucion se detuvo antes de terminar: no hay configuracion final"}), 409
    if estado["estado"] == "terminada" and estado["returncode"] != 0:
        return jsonify({"error": f"la ejecucion termino con error (codigo {estado['returncode']}): no hay configuracion final"}), 409

    matches = [
        p
        for p in glob.glob(str(run_dir / "conf.*"))
        if not p.endswith(".xyz")
    ]
    if not matches:
        return jsonify({"error": "no se encontro conf.*.HH final en este run"}), 404

    try:
        lines = Path(matches[0]).read_text().splitlines()
        nwalkers = int(lines[0].split()[0])
        if nwalkers <= 0:
            raise ValueError("numero de walkers no positivo")
        natom = (len(lines) - 1) // nwalkers
        if natom <= 0 or (len(lines) - 1) % nwalkers:
            raise ValueError("el numero de lineas no cuadra con el numero de walkers")

        walkers = []
        idx = 1
        for _ in range(nwalkers):
            atoms = []
            for _ in range(natom):
                parts = lines[idx].split()
                atoms.append([float(parts[0]), float(parts[1]), float(parts[2])])
                idx += 1
            walkers.append(atoms)
    except (OSError, ValueError, IndexError):
        return jsonify({"error": "el fichero conf.* de esta ejecucion esta danado o incompleto"}), 422

    nhe4, nhe3, n_impureza = natom, 0, 0
    inmcv_run = run_dir / "in.mcv"
    if inmcv_run.exists():
        run_lines = inmcv_run.read_text().splitlines()
        try:
            # lineas 7/8/9 de in.mcv: numero de he4 / he3 / atomos impureza
            # (ver TODOS_LOS_CAMPOS) -- fijas en esta version del fichero.
            nhe4 = int(_parse_valor_comentario(run_lines[6])[0])
            nhe3 = int(_parse_valor_comentario(run_lines[7])[0])
            n_impureza = int(_parse_valor_comentario(run_lines[8])[0])
        except (IndexError, ValueError):
            pass

    return jsonify({
        "nwalkers": nwalkers,
        "natom": natom,
        "nhe4": nhe4,
        "nhe3": nhe3,
        "n_impureza": n_impureza,
        "walkers": walkers,
    })


_RE_BLOQUE = re.compile(
    r"^\s*(\d+)\s+(\d+)\s+(\d+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s*$"
)
_RE_RESUMEN_UNIDAD = re.compile(
    r"^(meV|K|cm-1)\s+(.+?)\s*=\s*[\d.]+\s+(-?[\d.EeE+-]+)\s*\+/-\s*([\d.Ee+-]+)\s*$"
)
_RE_POBLACION_FIN = re.compile(
    r"^(Poblacion media|Estadistica)\s*=\s*(-?[\d.Ee+-]+)\s*\+/-\s*([\d.Ee+-]+)\s*$"
)


def parse_salida_log(texto):
    """Extrae de la salida REAL del binario (nunca se escribe a fichero
    por si sola, ver mdmcpromedia.f90 -- solo WRITE(6,...), por eso
    stream_subprocess la guarda a salida.log) la tabla de bloques
    (Bloque/Blq-Proc/Proceso/E_bloque/E_calculo/E_growth/Poblacion,
    tanto de equilibrio como de calculo) y el resumen final de energias
    en meV/K/cm-1 -- exactamente lo que el usuario ve por pantalla,
    estructurado para graficarlo."""
    bloques = []
    fase = None
    resumen = {"meV": {}, "K": {}, "cm-1": {}}
    poblacion_media = None
    estadistica = None
    energia_final = None
    walkers_finales = None
    walkers_iniciales = None
    tiempo_cpu_s = None

    for linea in texto.splitlines():
        if "Bloques para EQUILIBRIO" in linea:
            fase = "equilibrio"
            continue
        if "Bloques de CALCULO" in linea:
            fase = "calculo"
            continue

        m = _RE_BLOQUE.match(linea)
        if m and fase:
            bloques.append({
                "fase": fase,
                "bloque": int(m.group(1)),
                "blq_proc": int(m.group(2)),
                "proceso": int(m.group(3)),
                "e_bloque": float(m.group(4)),
                "e_calculo": float(m.group(5)),
                "e_growth": float(m.group(6)),
                "poblacion": float(m.group(7)),
            })
            continue

        m = _RE_RESUMEN_UNIDAD.match(linea)
        if m:
            unidad, etiqueta, valor, error = m.groups()
            resumen[unidad][etiqueta.strip()] = {"valor": float(valor), "error": float(error)}
            continue

        m = _RE_POBLACION_FIN.match(linea)
        if m:
            etiqueta, valor, error = m.groups()
            if etiqueta == "Poblacion media":
                poblacion_media = {"valor": float(valor), "error": float(error)}
            else:
                estadistica = {"valor": float(valor), "error": float(error)}
            continue

        m = re.search(r"energia final de las configuraciones\s+(-?[\d.]+)", linea)
        if m:
            energia_final = float(m.group(1))
            continue
        m = re.search(r"numero de walkers que tengo finales\s+(\d+)", linea)
        if m:
            walkers_finales = int(m.group(1))
            continue
        m = re.search(r"numero de walkers de partida en la simulacion\s+(\d+)", linea)
        if m:
            walkers_iniciales = int(m.group(1))
            continue
        m = re.search(r"tiempo de CPU en s\s+([\d.]+)", linea)
        if m:
            tiempo_cpu_s = float(m.group(1))
            continue

    return {
        "bloques": bloques,
        "resumen": resumen,
        "poblacion_media": poblacion_media,
        "estadistica": estadistica,
        "energia_final": energia_final,
        "walkers_finales": walkers_finales,
        "walkers_iniciales": walkers_iniciales,
        "tiempo_cpu_s": tiempo_cpu_s,
    }


@app.route("/api/runs/<run_id>/inmcv")
def run_inmcv(run_id):
    run_dir = _run_dir_or_404(run_id)
    if run_dir is None:
        return jsonify({"error": "run no encontrado"}), 404
    inmcv_path = run_dir / "in.mcv"
    if not inmcv_path.exists():
        return jsonify({"error": "esta ejecución no tiene in.mcv guardado"}), 404
    return jsonify({"content": inmcv_path.read_text()})


@app.route("/api/runs/<run_id>/stats")
def run_stats(run_id):
    run_dir = _run_dir_or_404(run_id)
    if run_dir is None:
        return jsonify({"error": "run no encontrado"}), 404
    log_path = run_dir / "salida.log"
    if not log_path.exists():
        return jsonify({"error": "esta ejecución no tiene salida.log guardada (ejecuciones anteriores a esta funcion)"}), 404
    return jsonify(parse_salida_log(log_path.read_text()))


@app.route("/api/runs/<run_id>/log")
def run_log(run_id):
    run_dir = _run_dir_or_404(run_id)
    if run_dir is None:
        return jsonify({"error": "run no encontrado"}), 404
    return jsonify({"files": sorted(p.name for p in run_dir.iterdir())})


if __name__ == "__main__":
    # host explicito: solo esta maquina. threaded=True: hace falta para
    # atender /stop y /seguimiento mientras otra peticion (p. ej. el flujo
    # de /api/compile) sigue abierta.
    # El modo depuracion (recarga automatica al editar y depurador
    # interactivo, que permite ejecutar codigo) SOLO se activa si se pide:
    #     DMC_GUI_DEBUG=1 ./venv/bin/python3 app.py
    app.run(host="127.0.0.1", port=5057, threaded=True,
            debug=os.environ.get("DMC_GUI_DEBUG") == "1")
