#!/usr/bin/env python3
"""Parsea resultados/*.dat de los barridos y genera las graficas de
crecimiento pedidas: tiempo de metodos (opcion=4, bucket 'hpsi') y
tiempo de conversion AoS<->SoA (opcion=5) frente a walkers, bloques de
calculo, bloques de equilibrio y pasos por bloque.
"""
import re, glob, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "resultados")

def lee_valor(fichero, etiqueta):
    with open(fichero) as f:
        for linea in f:
            if linea.strip().startswith(etiqueta):
                m = re.search(r"[\-0-9]+\.[0-9]+", linea)
                if m:
                    return float(m.group(0))
    return None

def punto_op4(tag):
    f = os.path.join(RES, tag + "__tiempos_opcion4.dat")
    return lee_valor(f, "hpsi"), lee_valor(f, "tiempo total")

def punto_op5(tag):
    f = os.path.join(RES, tag + "__tiempos_opcion5.dat")
    return lee_valor(f, "CONVERSION AoS<->SoA total"), lee_valor(f, "tiempo total")

sweeps = {
    "walkers (n. walkers)": {
        "x": [50, 100, 200],
        "op4": ["base_opcion4", "sweepA_w100_op4", "sweepA_w200_op4"],
        "op5": ["base_opcion5", "sweepA_w100_op5", "sweepA_w200_op5"],
    },
    "bloques de calculo": {
        "x": [1, 2, 4],
        "op4": ["base_opcion4", "sweepB_c2_op4", "sweepB_c4_op4"],
        "op5": ["base_opcion5", "sweepB_c2_op5", "sweepB_c4_op5"],
    },
    "bloques de equilibrio": {
        "x": [1, 2, 4],
        "op4": ["base_opcion4", "sweepC_e2_op4", "sweepC_e4_op4"],
        "op5": ["base_opcion5", "sweepC_e2_op5", "sweepC_e4_op5"],
    },
    "pasos por bloque": {
        "x": [5, 10, 20],
        "op4": ["base_opcion4", "sweepD_p10_op4", "sweepD_p20_op4"],
        "op5": ["base_opcion5", "sweepD_p10_op5", "sweepD_p20_op5"],
    },
}

fig, axes = plt.subplots(2, 2, figsize=(11, 8))
resumen_csv = ["sweep,x,metodos_op4_hpsi_s,total_op4_s,conversion_op5_s,total_op5_s"]

for ax, (nombre, datos) in zip(axes.flat, sweeps.items()):
    x = datos["x"]
    y_metodos, y_tot4 = zip(*[punto_op4(t) for t in datos["op4"]])
    y_conv, y_tot5 = zip(*[punto_op5(t) for t in datos["op5"]])

    for xi, ym, yt4, yc, yt5 in zip(x, y_metodos, y_tot4, y_conv, y_tot5):
        resumen_csv.append(f"{nombre},{xi},{ym},{yt4},{yc},{yt5}")

    ax.plot(x, y_metodos, "o-", label="metodos portados (opcion 4, bucket hpsi)", color="tab:blue")
    ax.set_yscale("log")
    ax.set_xlabel(nombre)
    ax.set_ylabel("tiempo metodos opcion 4 (s)", color="tab:blue")
    ax.tick_params(axis="y", labelcolor="tab:blue")

    ax2 = ax.twinx()
    ax2.plot(x, y_conv, "s--", label="conversion AoS<->SoA (opcion 5)", color="tab:red")
    ax2.set_yscale("log")
    ax2.set_ylabel("tiempo conversion opcion 5 (s)", color="tab:red")
    ax2.tick_params(axis="y", labelcolor="tab:red")

    ax.set_title(nombre)

fig.suptitle("Crecimiento del tiempo de metodos (opcion=4) y de conversion AoS<->SoA (opcion=5)")
fig.tight_layout()
out_png = os.path.join(HERE, "crecimiento_tiempos.png")
fig.savefig(out_png, dpi=140)
print("guardado:", out_png)

with open(os.path.join(HERE, "resumen_barridos.csv"), "w") as f:
    f.write("\n".join(resumen_csv) + "\n")
print("guardado: resumen_barridos.csv")
