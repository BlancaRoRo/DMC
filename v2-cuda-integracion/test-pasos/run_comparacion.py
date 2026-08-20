#!/usr/bin/env python3
"""Prueba de comparacion final (ver comparacion-final.md): misma
configuracion inicial (conf.20.00.HH, semilla fija en in.mcv), mismo
tamano de problema (nwalkers/bloques/pasos), ejecutada en 4 binarios
distintos:

  1. hibrido/qmccluster_hibrido        opcion=5  (referencia original,
     SIN ninguna de las optimizaciones de esta sesion)
  2. hibrido_instrumentado/qmccluster_tiempos   opcion=5  (con las
     optimizaciones de tiempo-ncu-resultado.md Partes 1-13 aplicadas)
  3. hibrido_instrumentado/qmccluster_pipeline  opcion=7  (Opcion 1,
     arquitectura-streams-kin-pot.md Parte 14)
  4. hibrido_instrumentado/qmccluster_tiempos   opcion=4  (CPU
     secuencial, codigo original SIN portar -- referencia de fondo,
     RNG distinto, solo comparable en estadistica, no bit a bit)

Cada corrida usa una copia FRESCA de conf.20.00.HH (finconfiguraciones
la reescribe) y el mismo in.mcv.orig como plantilla (misma semilla
aleatoria, "0000000000000011").
"""
import sys, os, re, shutil, subprocess, time

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
HIBRIDO = os.path.join(V2, "hibrido")
INSTR = os.path.join(V2, "test-tiempos", "hibrido_instrumentado")
RES = os.path.join(HERE, "resultados")
CONF_FRESCO = "/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"

os.makedirs(RES, exist_ok=True)


def genera_inmcv(directorio, plantilla, opcion, nwalkers, bloq_eq, bloq_calc, pasos):
    with open(os.path.join(directorio, plantilla)) as f:
        txt = f.read()

    def sub_linea(patron, valor, etiqueta):
        nonlocal txt
        nuevo = f"{valor}   !{etiqueta}"
        txt2, n = re.subn(patron, nuevo, txt, count=1, flags=re.MULTILINE)
        if n != 1:
            raise RuntimeError(f"no se pudo sustituir: {etiqueta} en {directorio}/{plantilla}")
        return txt2

    txt = sub_linea(r"^\s*\d+\s+!opcion.*$", opcion,
                     "opcion  0=test der, 1=mcv, 2 optimiza, 3 optimiza correlated, 4=dmc, 5=dmc-gpu, 6=dmc-cpu-secuencial-con-semillas-gpu")
    txt = sub_linea(r"^\s*\d+\s+!bloques de equilibrio\s*$", bloq_eq, "bloques de equilibrio")
    txt = sub_linea(r"^\s*\d+\s+!bloques de calculo\s*$", bloq_calc, "bloques de calculo")
    txt = sub_linea(r"^\s*\d+\s+!pasos por bloque\s*$", pasos, "pasos por bloque")
    txt = sub_linea(r"^\s*\d+\s+!numero de walkers\s*$", nwalkers, "numero de walkers")

    with open(os.path.join(directorio, "in.mcv"), "w") as f:
        f.write(txt)


def corre(directorio, binario, tag, timeout=None):
    shutil.copy(CONF_FRESCO, os.path.join(directorio, "conf.20.00.HH"))
    t0 = time.time()
    with open(os.path.join(directorio, "in.mcv")) as fin, \
         open(os.path.join(RES, tag + ".log"), "w") as fout:
        subprocess.run([f"./{binario}"], cwd=directorio, stdin=fin, stdout=fout,
                        stderr=subprocess.STDOUT, check=True, timeout=timeout)
    dt = time.time() - t0
    print(f"[{tag}] wall={dt:.1f}s")
    return dt


if __name__ == "__main__":
    nwalkers, bloq_eq, bloq_calc, pasos = sys.argv[1:5]

    plantilla_hibrido = "in.mcv"
    plantilla_instr = "in.mcv.orig"

    corridas = [
        (HIBRIDO, plantilla_hibrido, "qmccluster_hibrido", "5", "hibrido_op5"),
        (INSTR,   plantilla_instr,   "qmccluster_tiempos",  "5", "instrumentado_op5"),
        (INSTR,   plantilla_instr,   "qmccluster_pipeline", "7", "instrumentado_op7"),
        (INSTR,   plantilla_instr,   "qmccluster_tiempos",  "4", "instrumentado_op4_cpu"),
    ]

    for directorio, plantilla, binario, opcion, tag in corridas:
        genera_inmcv(directorio, plantilla, opcion, nwalkers, bloq_eq, bloq_calc, pasos)
        corre(directorio, binario, tag)
