"""Sondeo de la API: uso  ./venv/bin/python3 pruebas/sondeo_api.py
Bateria de pruebas de cada ruta de app.py con entradas validas, malas y extremas.
No lanza el simulador ni toca settings.json ni runs/ reales: se parchean las
funciones que tendrian efectos (lanzar, guardar ajustes, carpeta de runs)."""
import importlib.util, json, os, shutil, sys, tempfile
from pathlib import Path

GUI_DIR = Path(__file__).resolve().parent.parent
APP = str(GUI_DIR / "app.py")
spec = importlib.util.spec_from_file_location("gui", APP)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

tmp = Path(tempfile.mkdtemp())
runs = tmp / "runs"; runs.mkdir()
lanzados = []
m.get_runs_dir = lambda: runs
m.lanzar_run_en_segundo_plano = lambda d: lanzados.append(d.name)
guardados = []
m.save_settings = lambda d: guardados.append(d)
os.chdir(tmp)                         # rutas relativas caen aqui, no en el repo
c = m.app.test_client()
m.app.config["PROPAGATE_EXCEPTIONS"] = False
m.app.static_folder = str(GUI_DIR / "static")

filas = []
inm_local = {}
inm_txt = {}
def call(nombre, method, url, **kw):
    antes = set(p.name for p in runs.iterdir())
    try:
        r = c.open(url, method=method, **kw)
        if url == "/api/run":
            for d in runs.iterdir():
                if d.name not in antes:
                    inm_local[nombre] = len((d / "in.mcv").read_text().splitlines())
                    txt = (d / "in.mcv").read_text()
                    inm_txt[nombre] = txt
                    shutil.rmtree(d)
        try:
            j = r.get_json(silent=True)
        except Exception:
            j = None
        msg = ""
        if isinstance(j, dict):
            msg = j.get("error") or ""
        filas.append((nombre, method, url, r.status_code, msg[:70]))
        return r
    except Exception as e:
        filas.append((nombre, method, url, "EXC", type(e).__name__ + ": " + str(e)[:60]))

J = dict(content_type="application/json")
def jd(d): return json.dumps(d)

# --- paginas y esquema
call("pagina config", "GET", "/")
call("pagina resultados", "GET", "/resultados")
call("esquema formulario", "GET", "/api/config-schema")
call("estado binario", "GET", "/api/binary-status")

# --- parse-inmcv
call("importar: vacio", "POST", "/api/parse-inmcv", data=jd({"content": ""}), **J)
call("importar: lineas de menos", "POST", "/api/parse-inmcv", data=jd({"content": "a\nb\n"}), **J)
call("importar: content no es texto", "POST", "/api/parse-inmcv", data=jd({"content": 5}), **J)
call("importar: cuerpo no es JSON", "POST", "/api/parse-inmcv", data="esto no es json", content_type="text/plain")
call("importar: cuerpo es lista", "POST", "/api/parse-inmcv", data=jd([1, 2]), **J)

# --- ajustes
call("ajustes: leer", "GET", "/api/settings")
call("ajustes: ruta vacia", "POST", "/api/settings", data=jd({"runs_dir": ""}), **J)
call("ajustes: fuentes inexistente", "POST", "/api/settings", data=jd({"source_dir": "/no/existe/xx"}), **J)
call("ajustes: binario inexistente", "POST", "/api/settings", data=jd({"binary_dir": "/no/existe/xx"}), **J)
call("ajustes: runs relativa", "POST", "/api/settings", data=jd({"runs_dir": "carpeta_relativa"}), **J)
call("ajustes: valor no texto", "POST", "/api/settings", data=jd({"runs_dir": 5}), **J)
call("ajustes: cuerpo lista", "POST", "/api/settings", data=jd([1]), **J)
call("ajustes: campo de fuentes = fichero", "POST", "/api/settings", data=jd({"source_dir": "/etc/hostname"}), **J)
rel_creada = (tmp / "carpeta_relativa").exists()
call("elegir carpeta: campo desconocido", "POST", "/api/settings/pick-folder", data=jd({"campo": "zzz"}), **J)

# --- compilar (sin ejecutar nada): fuentes sin script
m.get_source_dir = lambda: Path("/no/existe/fuentes")
call("compilar: sin script", "POST", "/api/compile")

# --- ejecutar
call("ejecutar: valores no es objeto", "POST", "/api/run", data=jd({"valores": [1]}), **J)
call("ejecutar: numero invalido", "POST", "/api/run", data=jd({"valores": {"7": "abc"}}), **J)
call("ejecutar: numero 'nan'", "POST", "/api/run", data=jd({"valores": {"7": "nan"}, "nombre": "t1"}), **J)
call("ejecutar: numero 'inf'", "POST", "/api/run", data=jd({"valores": {"7": "inf"}, "nombre": "t2"}), **J)
call("ejecutar: numero con salto de linea", "POST", "/api/run", data=jd({"valores": {"7": "20\n"}, "nombre": "t3"}), **J)
call("ejecutar: texto con salto de linea", "POST", "/api/run", data=jd({"valores": {"10": "H\n99"}, "nombre": "t4"}), **J)
call("ejecutar: select fuera de opciones", "POST", "/api/run", data=jd({"valores": {"4": "cualquier cosa"}, "nombre": "t5"}), **J)
call("ejecutar: clave no numerica", "POST", "/api/run", data=jd({"valores": {"abc": "1"}, "nombre": "t6"}), **J)
call("ejecutar: par con 3 valores", "POST", "/api/run", data=jd({"valores": {"51": ["1", "2", "3"]}}), **J)
call("ejecutar: cuerpo lista", "POST", "/api/run", data=jd([1]), **J)
call("ejecutar: cuerpo no JSON", "POST", "/api/run", data="xx", content_type="text/plain")
call("ejecutar: nombre 500 caracteres", "POST", "/api/run", data=jd({"valores": {}, "nombre": "x" * 500}), **J)
call("ejecutar: base_inmcv incompleto", "POST", "/api/run", data=jd({"valores": {}, "base_inmcv": "a\nb"}), **J)

ref_lineas = len(m.DEFAULT_INMCV.read_text().splitlines())
inm = inm_local

# --- seguimiento / parada / resultados con ids raros
call("seguimiento: id mal formado", "GET", "/api/runs/../seguimiento")
call("seguimiento: id valido inexistente", "GET", "/api/runs/run_20200101_000000/seguimiento")
call("parar ejecucion inexistente", "POST", "/api/runs/run_20200101_000000/stop")
call("parar job inexistente", "POST", "/api/jobs/xx/stop")
call("histogramas inexistente", "GET", "/api/runs/run_20200101_000000/histograms")
call("config final inexistente", "GET", "/api/runs/run_20200101_000000/final-config")
call("stats inexistente", "GET", "/api/runs/run_20200101_000000/stats")
call("in.mcv de ejecucion inexistente", "GET", "/api/runs/run_20200101_000000/inmcv")
call("lista de ejecuciones", "GET", "/api/runs")
call("ejecucion activa", "GET", "/api/run-activa")

# --- ejecuciones sinteticas: parada temprana / ficheros corruptos
def crea(id_, conf=None, log=None):
    d = runs / id_; d.mkdir()
    if conf is not None: (d / "conf.20.00.HH").write_text(conf)
    if log is not None: (d / "salida.log").write_text(log)
    return d
crea("run_20260101_000001")                                          # vacia (sin conf ni log)
crea("run_20260101_000002", conf="0\n")                              # conf corrupta: 0 walkers
conf_ref = m.HIBRIDO_DIR / "conf.20.00.HH"
crea("run_20260101_000003", conf=conf_ref.read_text() if conf_ref.is_file() else "0\n")  # parada temprana: conf INICIAL copiada
crea("run_20260101_000004", log="basura sin formato\n" * 50)         # log corrupto
crea("run_20260101_000005", conf="abc\n")                            # conf no numerica
for rid in ["run_20260101_000001", "run_20260101_000002", "run_20260101_000003", "run_20260101_000004", "run_20260101_000005"]:
    for ruta in ["final-config", "stats", "histograms", "seguimiento"]:
        call(f"{rid[-1]} {ruta}", "GET", f"/api/runs/{rid}/{ruta}")
seg = c.get("/api/runs/run_20260101_000003/seguimiento").get_json()
fc = c.get("/api/runs/run_20260101_000003/final-config").get_json()

# --- seguimiento con parametros raros
call("seguimiento: desde=abc", "GET", "/api/runs/run_20260101_000001/seguimiento?desde=abc")
call("seguimiento: desde=-5", "GET", "/api/runs/run_20260101_000001/seguimiento?desde=-5")
call("seguimiento: desde enorme", "GET", "/api/runs/run_20260101_000001/seguimiento?desde=99999999999")

w = max(len(f[0]) for f in filas)
for f in filas:
    print(f"{f[0]:<{w}}  {f[1]:<4} {str(f[3]):<4} {f[4]}")
print("\n--- comprobaciones adicionales")
print("ejecuciones que habrian llegado a lanzarse:", len(lanzados))
print("in.mcv generado por los casos ACEPTADOS (lineas; referencia =", ref_lineas, "):")
for k,v in inm.items(): print("   ", k, "->", v, "lineas", "  <-- DESPLAZADO" if v != ref_lineas else "")
t = inm_txt.get("ejecutar: texto con salto de linea")
if t: print("    linea 10-12 con 'H\\n99':", [l[:12] for l in t.splitlines()[9:12]])
t = inm_txt.get("ejecutar: numero 'nan'")
if t: print("    linea 7 con 'nan':", t.splitlines()[6][:30])
print("carpeta relativa creada en el cwd por el ajuste 'runs_dir':", rel_creada)
print("parada temprana: estado =", seg.get("estado"), "| walkers en 'configuracion final' =", fc.get("nwalkers"))
shutil.rmtree(tmp, ignore_errors=True)
