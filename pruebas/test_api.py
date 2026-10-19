"""Pruebas automaticas de la API de la interfaz (una por fila del inventario,
ver INVENTARIO_INTERACCIONES.md).

    ./venv/bin/python3 -m unittest discover -s pruebas -v

No lanzan el simulador ni tocan settings.json ni runs/: todo va a una carpeta
temporal y las funciones con efectos (lanzar el proceso, guardar ajustes) se
sustituyen por dobles.
"""
import importlib.util
import json
import shutil
import signal
import tempfile
import unittest
from pathlib import Path
from unittest import mock

GUI_DIR = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("gui_app", GUI_DIR / "app.py")
gui = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gui)
gui.app.static_folder = str(GUI_DIR / "static")

REF_LINEAS = len(gui.DEFAULT_INMCV.read_text().splitlines())
CONF_VALIDO = "2\n" + "".join(f"  {i}.0  {i}.5  {i}.9\n" for i in range(4))  # 2 walkers x 2 atomos


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.runs = self.tmp / "runs"
        self.runs.mkdir()
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        (self.bin / gui.BINARY_NAME).write_bytes(b"binario falso")
        (self.bin / "potencial.pot").write_text("datos")
        self.lanzados, self.guardados = [], []
        ajustes = {"runs_dir": str(self.runs), "source_dir": str(self.tmp), "binary_dir": str(self.bin)}
        for p in (
            mock.patch.object(gui, "get_runs_dir", lambda: self.runs),
            mock.patch.object(gui, "get_binary_dir", lambda: self.bin),
            mock.patch.object(gui, "load_settings", lambda: dict(ajustes)),
            mock.patch.object(gui, "save_settings", lambda d: self.guardados.append(d)),
            mock.patch.object(gui, "lanzar_run_en_segundo_plano", lambda d: self.lanzados.append(d.name)),
        ):
            p.start()
            self.addCleanup(p.stop)
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.c = gui.app.test_client()

    # -- utilidades
    def post(self, url, obj=None, **kw):
        return self.c.post(url, json=obj, **kw) if obj is not None else self.c.post(url, **kw)

    def crear_run(self, id_, conf=None, log=None, meta=None, returncode=None, inmcv=None):
        d = self.runs / id_
        d.mkdir()
        if conf is not None:
            (d / "conf.20.00.HH").write_text(conf)
        if log is not None:
            (d / "salida.log").write_text(log)
        if meta is not None:
            (d / "meta.json").write_text(json.dumps(meta))
        if returncode is not None:
            (d / "returncode").write_text(str(returncode))
        if inmcv is not None:
            (d / "in.mcv").write_text(inmcv)
        return d

    def assertError(self, r, codigo, fragmento=None):
        self.assertEqual(r.status_code, codigo, r.get_data(as_text=True)[:200])
        j = r.get_json()
        self.assertIsInstance(j, dict)
        self.assertIn("error", j)
        if fragmento:
            self.assertIn(fragmento, j["error"])


class TestPaginas(Base):
    def test_paginas_y_esquema(self):
        for url in ("/", "/resultados", "/api/config-schema", "/api/binary-status", "/api/runs", "/api/run-activa"):
            self.assertEqual(self.c.get(url).status_code, 200, url)


class TestImportarInmcv(Base):
    def test_vacio(self):
        self.assertError(self.post("/api/parse-inmcv", {"content": ""}), 400, "vacio")

    def test_estructura_incorrecta(self):
        self.assertError(self.post("/api/parse-inmcv", {"content": "a\nb\n"}), 400, "lineas")

    def test_content_no_es_texto(self):
        self.assertError(self.post("/api/parse-inmcv", {"content": 5}), 400)

    def test_cuerpo_no_es_json(self):
        self.assertError(self.post("/api/parse-inmcv", data="esto no es json", content_type="text/plain"), 415)

    def test_cuerpo_es_lista(self):
        self.assertError(self.post("/api/parse-inmcv", [1, 2]), 400)

    def test_valido(self):
        r = self.post("/api/parse-inmcv", {"content": gui.DEFAULT_INMCV.read_text()})
        self.assertEqual(r.status_code, 200)


class TestAjustes(Base):
    def test_ruta_vacia(self):
        self.assertError(self.post("/api/settings", {"runs_dir": ""}), 400, "vacia")

    def test_carpetas_de_entrada_inexistentes(self):
        self.assertError(self.post("/api/settings", {"source_dir": "/no/existe/xx"}), 400, "no existe")
        self.assertError(self.post("/api/settings", {"binary_dir": "/no/existe/xx"}), 400, "no existe")

    def test_ruta_que_es_un_fichero(self):
        f = self.tmp / "fichero.txt"
        f.write_text("x")
        self.assertError(self.post("/api/settings", {"source_dir": str(f)}), 400, "no es una carpeta")

    def test_ruta_relativa_se_rechaza_y_no_crea_nada(self):
        self.assertError(self.post("/api/settings", {"runs_dir": "carpeta_relativa"}), 400, "absoluta")
        self.assertFalse(Path("carpeta_relativa").exists())

    def test_valor_que_no_es_texto(self):
        self.assertError(self.post("/api/settings", {"runs_dir": 5}), 400, "texto")

    def test_cuerpo_lista(self):
        self.assertError(self.post("/api/settings", [1]), 400)

    def test_guardar_ruta_valida(self):
        nueva = self.tmp / "nuevas_runs"
        r = self.post("/api/settings", {"runs_dir": str(nueva)})
        self.assertEqual(r.status_code, 200)
        self.assertTrue(nueva.is_dir())
        self.assertEqual(self.guardados[-1]["runs_dir"], str(nueva.resolve()))

    def test_elegir_carpeta_campo_desconocido(self):
        self.assertError(self.post("/api/settings/pick-folder", {"campo": "zzz"}), 400, "desconocido")


class TestEjecutar(Base):
    def inmcv_generado(self):
        (d,) = list(self.runs.iterdir())
        return d, (d / "in.mcv").read_text().splitlines()

    def test_valores_correctos(self):
        r = self.post("/api/run", {"valores": {"7": "20"}, "nombre": "mi prueba"})
        self.assertEqual(r.status_code, 200, r.get_data(as_text=True))
        d, lineas = self.inmcv_generado()
        self.assertEqual(len(lineas), REF_LINEAS)
        self.assertTrue(lineas[6].strip().startswith("20"))
        self.assertEqual((d / "nombre.txt").read_text(), "mi prueba")
        self.assertEqual(self.lanzados, [d.name])
        self.assertTrue((d / gui.BINARY_NAME).exists() and (d / "potencial.pot").exists())

    def test_coma_decimal_se_normaliza_a_punto(self):
        self.assertEqual(self.post("/api/run", {"valores": {"33": "0,96"}}).status_code, 200)
        _, lineas = self.inmcv_generado()
        self.assertIn("0.96", lineas[32])
        self.assertNotIn(",", lineas[32].split("!")[0])

    def test_espacios_y_salto_al_final_se_eliminan(self):
        # un salto al FINAL no puede desplazar nada: se recorta y queda "20"
        self.assertEqual(self.post("/api/run", {"valores": {"7": "  20\n"}}).status_code, 200)
        _, lineas = self.inmcv_generado()
        self.assertEqual(len(lineas), REF_LINEAS)
        self.assertEqual(lineas[6].split("!")[0].strip(), "20")

    def test_nombre_largo_se_recorta(self):
        self.assertEqual(self.post("/api/run", {"valores": {}, "nombre": "x" * 500}).status_code, 200)
        d, _ = self.inmcv_generado()
        self.assertEqual(len((d / "nombre.txt").read_text()), 80)

    def test_entradas_rechazadas_sin_crear_nada(self):
        malos = {
            "numero no numerico": {"7": "abc"},
            "numero nan": {"7": "nan"},
            "numero inf": {"7": "inf"},
            "numero con salto en medio": {"7": "2\n0"},
            "numero booleano": {"7": True},
            "texto con salto de linea": {"10": "H\n99"},
            "texto con caracteres raros": {"10": "H!"},
            "desplegable fuera de opciones": {"4": "cualquier cosa"},
            "clave no numerica": {"abc": "1"},
            "par con 3 valores": {"51": ["1", "2", "3"]},
            "par con un valor malo": {"51": ["1", "x"]},
        }
        for nombre, valores in malos.items():
            with self.subTest(nombre):
                self.assertError(self.post("/api/run", {"valores": valores}), 400)
        self.assertEqual(list(self.runs.iterdir()), [])
        self.assertEqual(self.lanzados, [])

    def test_cuerpos_invalidos(self):
        self.assertError(self.post("/api/run", [1]), 400)
        self.assertError(self.post("/api/run", data="xx", content_type="text/plain"), 415)
        self.assertError(self.post("/api/run", {"valores": [1]}), 400, "objeto")
        self.assertError(self.post("/api/run", {"valores": {}, "base_inmcv": 5}), 400)
        self.assertError(self.post("/api/run", {"valores": {}, "base_inmcv": "a\nb"}), 400, "invalido")

    def test_otra_simulacion_en_curso(self):
        self.crear_run("run_20260101_000001", meta={"pid": 4000000, "inicio": 0})
        with mock.patch.object(gui, "_pid_vivo", lambda pid: True):
            self.assertError(self.post("/api/run", {"valores": {}}), 409, "en marcha")

    def test_binario_inexistente(self):
        (self.bin / gui.BINARY_NAME).unlink()
        self.assertError(self.post("/api/run", {"valores": {}}), 400, "compila primero")

    def test_compilar_sin_script(self):
        with mock.patch.object(gui, "get_source_dir", lambda: Path("/no/existe/fuentes")):
            self.assertError(self.post("/api/compile"), 400, gui.COMPILE_SCRIPT)


class TestProteccionDePeticiones(Base):
    def test_origen_ajeno_se_rechaza(self):
        for origen in ("http://evil.example", "null", "http://localhost:9999"):
            with self.subTest(origen):
                self.assertError(self.post("/api/run", {"valores": {}}, headers={"Origin": origen}), 403)
        self.assertEqual(list(self.runs.iterdir()), [])

    def test_peticion_cruzada_sin_origin(self):
        r = self.post("/api/compile", headers={"Sec-Fetch-Site": "cross-site"})
        self.assertError(r, 403)

    def test_mismo_origen_se_acepta(self):
        r = self.post("/api/settings/pick-folder", {"campo": "zzz"}, headers={"Origin": "http://localhost"})
        self.assertEqual(r.status_code, 400)  # llega a la ruta (no es 403)
        r = self.post("/api/settings/pick-folder", {"campo": "zzz"}, headers={"Sec-Fetch-Site": "same-origin"})
        self.assertEqual(r.status_code, 400)

    def test_host_ajeno_se_rechaza(self):
        self.assertError(self.c.get("/api/runs", base_url="http://evil.example"), 403, "host")
        self.assertError(self.c.get("/", base_url="http://192.168.1.5:5057"), 403, "host")

    def test_hosts_locales_se_aceptan(self):
        for base in ("http://localhost:5057", "http://127.0.0.1:5057"):
            self.assertEqual(self.c.get("/api/runs", base_url=base).status_code, 200, base)


class TestEstadoYSeguimiento(Base):
    ID = "run_20260101_000001"

    def seg(self, desde=0):
        r = self.c.get(f"/api/runs/{self.ID}/seguimiento?desde={desde}")
        self.assertEqual(r.status_code, 200)
        return r.get_json()

    def test_ids_mal_formados_o_inexistentes(self):
        for url in ("/api/runs/../seguimiento", "/api/runs/run_20200101_000000/seguimiento"):
            self.assertError(self.c.get(url), 404)

    def test_desconocido_terminada_y_detenida(self):
        self.crear_run(self.ID, log="hola\n")
        self.assertEqual(self.seg()["estado"], "desconocido")
        (self.runs / self.ID / "returncode").write_text("0\n")
        j = self.seg()
        self.assertEqual((j["estado"], j["returncode"]), ("terminada", 0))
        (self.runs / self.ID / "returncode").unlink()
        (self.runs / self.ID / "meta.json").write_text(json.dumps({"pid": 4000000, "inicio": 0}))
        self.assertEqual(self.seg()["estado"], "detenida")

    def test_corriendo_solo_devuelve_lineas_completas(self):
        self.crear_run(self.ID, log="a\nb\nparcial", meta={"pid": 4000000, "inicio": 0})
        with mock.patch.object(gui, "_pid_vivo", lambda pid: True):
            j = self.seg()
            self.assertEqual((j["estado"], j["texto"], j["siguiente"]), ("corriendo", "a\nb\n", 4))
            self.assertEqual(self.seg(desde=4)["texto"], "")

    def test_terminada_devuelve_todo_el_log(self):
        self.crear_run(self.ID, log="a\nb\nfinal", meta={"pid": 1, "inicio": 0}, returncode=0)
        self.assertEqual(self.seg()["texto"], "a\nb\nfinal")

    def test_desde_raro_se_corrige(self):
        self.crear_run(self.ID, log="a\n")
        for desde in ("abc", "-5", "99999999999"):
            self.assertEqual(self.c.get(f"/api/runs/{self.ID}/seguimiento?desde={desde}").status_code, 200, desde)


class TestResultados(Base):
    ID = "run_20260101_000001"

    def get(self, ruta):
        return self.c.get(f"/api/runs/{self.ID}/{ruta}")

    def test_inexistente_da_404(self):
        for ruta in ("histograms", "final-config", "stats", "inmcv", "log"):
            self.assertError(self.c.get(f"/api/runs/run_20200101_000000/{ruta}"), 404)

    def test_config_final_de_ejecucion_terminada(self):
        self.crear_run(self.ID, conf=CONF_VALIDO, meta={"pid": 1, "inicio": 0}, returncode=0)
        j = self.get("final-config").get_json()
        self.assertEqual((j["nwalkers"], j["natom"]), (2, 2))

    def test_config_final_no_se_sirve_si_no_termino_bien(self):
        # el directorio trae desde el principio el conf INICIAL: no debe pasar por final
        casos = {
            "detenida": dict(meta={"pid": 4000000, "inicio": 0}),
            "terminada con error": dict(meta={"pid": 1, "inicio": 0}, returncode=3),
        }
        for nombre, kw in casos.items():
            with self.subTest(nombre):
                d = self.crear_run(self.ID, conf=CONF_VALIDO, **kw)
                self.assertError(self.get("final-config"), 409)
                shutil.rmtree(d)
        d = self.crear_run(self.ID, conf=CONF_VALIDO, meta={"pid": 4000000, "inicio": 0})
        with mock.patch.object(gui, "_pid_vivo", lambda pid: True):
            self.assertError(self.get("final-config"), 409, "en curso")

    def test_config_final_ejecucion_antigua_sin_meta_se_sigue_sirviendo(self):
        self.crear_run(self.ID, conf=CONF_VALIDO)
        self.assertEqual(self.get("final-config").status_code, 200)

    def test_config_final_danada_o_ausente(self):
        d = self.crear_run(self.ID, returncode=0, meta={"pid": 1, "inicio": 0})
        self.assertError(self.get("final-config"), 404)
        for contenido in ("0\n", "abc\n", "2\n1.0 2.0\n"):
            with self.subTest(contenido):
                (d / "conf.20.00.HH").write_text(contenido)
                self.assertError(self.get("final-config"), 422, "danado")

    def test_histogramas_incluyen_el_estado_y_omiten_los_danados(self):
        d = self.crear_run(self.ID, returncode=0, meta={"pid": 1, "inicio": 0})
        (d / "dhe4he4.20.00.HH").write_text("no es un histograma\n")
        j = self.get("histograms").get_json()
        self.assertEqual((j["estado"], j["returncode"]), ("terminada", 0))
        self.assertIn("dhe4he4", j["omitidos"])
        self.assertEqual(j["radial"], {})

    def test_estadisticas(self):
        self.crear_run(self.ID)
        self.assertError(self.get("stats"), 404)
        (self.runs / self.ID / "salida.log").write_text("basura sin formato\n" * 10)
        self.assertEqual(self.get("stats").status_code, 200)


class TestParar(Base):
    def test_no_existe_o_no_esta_en_curso(self):
        self.assertError(self.post("/api/runs/run_20200101_000000/stop"), 404)
        self.crear_run("run_20260101_000001", meta={"pid": 4000000, "inicio": 0})
        self.assertError(self.post("/api/runs/run_20260101_000001/stop"), 404, "no esta en curso")
        self.assertError(self.post("/api/jobs/xx/stop"), 404)

    def test_parar_envia_sigterm_al_grupo_del_proceso(self):
        self.crear_run("run_20260101_000001", meta={"pid": 4000000, "inicio": 0})
        with mock.patch.object(gui, "_pid_vivo", lambda pid: True), mock.patch.object(gui.os, "killpg") as killpg:
            r = self.post("/api/runs/run_20260101_000001/stop")
            self.assertEqual(r.status_code, 200)
            killpg.assert_any_call(4000000, signal.SIGTERM)


class TestErroresEnJson(Base):
    def test_ruta_inexistente_da_json(self):
        self.assertError(self.c.get("/api/no-existe"), 404)

    def test_error_interno_da_json(self):
        with mock.patch.object(gui, "build_config_schema", side_effect=RuntimeError("fallo")):
            r = self.c.get("/api/config-schema")
        self.assertError(r, 500, "RuntimeError")


if __name__ == "__main__":
    unittest.main()
