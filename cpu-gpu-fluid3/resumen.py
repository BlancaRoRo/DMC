#!/usr/bin/env python3
"""Resume una carpeta test-walkers-<maquina>/ generada por
ejecutar_test_walkers.sh: lee el "wall=...s rc=..." del final de cada log,
marca las corridas con colapso de poblacion o energia NaN, y escribe:
  - resultados.csv    (una fila por walkers, media de las repeticiones)
  - tabla.tex         (filas en el mismo formato que la tabla del capitulo 4)
  - por pantalla: la tabla y el cruce CPU/GPU interpolado.

Uso: resumen.py <carpeta test-walkers-maquina>
"""
import sys, re, glob, os, statistics

def leer_log(ruta):
    txt = open(ruta, errors="replace").read()
    m = re.search(r"wall=([\d.]+)s rc=(-?\d+)", txt)
    if not m:
        return None
    wall, rc = float(m.group(1)), int(m.group(2))
    invalida = rc != 0 or "colapso" in txt.lower() or re.search(r"\bnan\b", txt, re.I)
    return wall, bool(invalida)

def coma(x, dec=2):
    return f"{x:.{dec}f}".replace(".", ",")

def main():
    carpeta = sys.argv[1]
    filas = []
    for d in glob.glob(os.path.join(carpeta, "test-*w")):
        w = int(re.search(r"test-(\d+)w$", d).group(1))
        datos = {}
        for tag in ("gpu", "cpu"):
            corr = [leer_log(f) for f in sorted(glob.glob(os.path.join(d, f"salida-*-{tag}.log")) + glob.glob(os.path.join(d, f"salida-*-{tag}-r*.log")))]
            corr = [c for c in corr if c]
            if corr:
                datos[tag] = (statistics.mean(c[0] for c in corr), any(c[1] for c in corr), len(corr))
        if "gpu" in datos and "cpu" in datos:
            filas.append((w, datos["gpu"], datos["cpu"]))
    filas.sort()

    with open(os.path.join(carpeta, "resultados.csv"), "w") as f:
        f.write("walkers,gpu_s,cpu_s,aceleracion,gana,repeticiones,invalida\n")
        for w, g, c in filas:
            inval = g[1] or c[1]
            acel = c[0] / g[0]
            f.write(f"{w},{g[0]:.3f},{c[0]:.3f},{acel:.4f},{'GPU' if acel > 1 else 'CPU'},{g[2]},{int(inval)}\n")

    # Cruce: interpolacion lineal entre el ultimo punto en que gana la CPU
    # y el primero en que gana la GPU (solo corridas validas)
    validas = [(w, c[0] / g[0]) for w, g, c in filas if not (g[1] or c[1])]
    cruce = None
    for (w0, a0), (w1, a1) in zip(validas, validas[1:]):
        if a0 < 1 <= a1:
            cruce = (w0, w1, w0 + (1 - a0) * (w1 - w0) / (a1 - a0))
            break

    lineas = []
    for w, g, c in filas:
        if g[1] or c[1]:
            lineas.append(f"{w} & \\multicolumn{{2}}{{c|}}{{ver nota debajo de la tabla}} & -- & -- \\\\\n\\hline")
            continue
        acel = c[0] / g[0]
        if cruce and w == cruce[1]:
            lineas.append(f"\\multicolumn{{5}}{{|c|}}{{\\textit{{cruce estimado (interpolado) en torno a {round(cruce[2])} walkers}}}} \\\\\n\\hline")
        lineas.append(f"{w} & {coma(g[0])} s & {coma(c[0])} s & {coma(acel)}$\\times$ & {'GPU' if acel > 1 else 'CPU'} \\\\\n\\hline")
    with open(os.path.join(carpeta, "tabla.tex"), "w") as f:
        f.write("\n".join(lineas) + "\n")

    print(f"\n{'walkers':>8} {'GPU (s)':>10} {'CPU (s)':>10} {'CPU/GPU':>9}  gana")
    for w, g, c in filas:
        nota = "  (no valida: colapso/NaN/error)" if g[1] or c[1] else ""
        acel = c[0] / g[0]
        print(f"{w:>8} {g[0]:>10.2f} {c[0]:>10.2f} {acel:>8.2f}x  {'GPU' if acel > 1 else 'CPU'}{nota}")
    if cruce:
        print(f"\nCruce estimado: ~{cruce[2]:.1f} walkers (entre {cruce[0]} y {cruce[1]})")
    else:
        print("\nNo se ha encontrado cruce CPU->GPU en las corridas validas")
    print(f"Escritos: {carpeta}/resultados.csv y {carpeta}/tabla.tex")

if __name__ == "__main__":
    main()
