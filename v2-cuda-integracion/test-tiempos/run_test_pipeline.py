#!/usr/bin/env python3
"""Genera un in.mcv a partir de la plantilla, corre qmccluster_pipeline,
y copia el reporte de tiempos + un resumen de energia/poblacion a
resultados/<tag>.dat / <tag>.log. Usa siempre una copia fresca de
conf.20.00.HH (finconfiguraciones la reescribe en cada ejecucion).
"""
import sys, os, re, shutil, subprocess, time

HERE = os.path.dirname(os.path.abspath(__file__))
HIB = os.path.join(HERE, "hibrido_instrumentado")
RES = os.path.join(HERE, "resultados")
CONF_FRESCO = "/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"

def genera_inmcv(opcion, nwalkers, bloq_eq, bloq_calc, pasos):
    with open(os.path.join(HIB, "in.mcv.orig")) as f:
        txt = f.read()

    def sub_linea(patron, valor, etiqueta):
        nonlocal txt
        nuevo = f"{valor}   !{etiqueta}"
        txt2, n = re.subn(patron, nuevo, txt, count=1, flags=re.MULTILINE)
        if n != 1:
            raise RuntimeError(f"no se pudo sustituir: {etiqueta}")
        return txt2

    txt = sub_linea(r"^\s*\d+\s+!opcion.*$", opcion, "opcion  0=test der, 1=mcv, 2 optimiza, 3 optimiza correlated, 4=dmc, 5=dmc-gpu, 6=dmc-cpu-secuencial-con-semillas-gpu")
    txt = sub_linea(r"^\s*\d+\s+!bloques de equilibrio\s*$", bloq_eq, "bloques de equilibrio")
    txt = sub_linea(r"^\s*\d+\s+!bloques de calculo\s*$", bloq_calc, "bloques de calculo")
    txt = sub_linea(r"^\s*\d+\s+!pasos por bloque\s*$", pasos, "pasos por bloque")
    txt = sub_linea(r"^\s*\d+\s+!numero de walkers\s*$", nwalkers, "numero de walkers")

    with open(os.path.join(HIB, "in.mcv"), "w") as f:
        f.write(txt)

def corre(tag):
    shutil.copy(CONF_FRESCO, os.path.join(HIB, "conf.20.00.HH"))
    for f in ("tiempos_opcion4.dat", "tiempos_opcion5.dat"):
        p = os.path.join(HIB, f)
        if os.path.exists(p):
            os.remove(p)
    t0 = time.time()
    with open(os.path.join(HIB, "in.mcv")) as fin, \
         open(os.path.join(RES, tag + ".log"), "w") as fout:
        subprocess.run(["./qmccluster_pipeline"], cwd=HIB, stdin=fin, stdout=fout, stderr=subprocess.STDOUT, check=True)
    dt = time.time() - t0
    for f in ("tiempos_opcion4.dat", "tiempos_opcion5.dat"):
        p = os.path.join(HIB, f)
        if os.path.exists(p):
            shutil.copy(p, os.path.join(RES, tag + "__" + f))
    print(f"[{tag}] wall={dt:.1f}s")
    return dt

if __name__ == "__main__":
    opcion, nwalkers, bloq_eq, bloq_calc, pasos, tag = sys.argv[1:7]
    genera_inmcv(opcion, nwalkers, bloq_eq, bloq_calc, pasos)
    corre(tag)
