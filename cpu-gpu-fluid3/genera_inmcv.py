#!/usr/bin/env python3
"""Genera un in.mcv a partir de _plantillas/in.mcv.base (la Configuracion
Inicial del TFG), sustituyendo opcion/bloques/pasos/walkers -- mismo
patron robusto que v2-cuda-integracion/test-pasos/run_comparacion.py.
Verifica explicitamente que etrial se mantiene en -631.8 tras la
sustitucion (no se asume, se comprueba).

Uso: genera_inmcv.py <plantilla_base> <salida> <opcion> <walkers> <bloq_eq> <bloq_calc> <pasos>
"""
import sys, re

def sub_linea(txt, patron, valor, etiqueta):
    nuevo = f"{valor}   !{etiqueta}"
    txt2, n = re.subn(patron, nuevo, txt, count=1, flags=re.MULTILINE)
    if n != 1:
        raise RuntimeError(f"no se pudo sustituir: {etiqueta} (n={n})")
    return txt2

def main():
    plantilla, salida, opcion, nwalkers, bloq_eq, bloq_calc, pasos = sys.argv[1:8]
    with open(plantilla) as f:
        txt = f.read()

    txt = sub_linea(txt, r"^\s*\d+\s+!opcion.*$", opcion,
                     "opcion  0=test der, 1=mcv, 2 optimiza, 3 optimiza correlated, 4=dmc, 5=dmc-gpu, 6=dmc-cpu-secuencial-con-semillas-gpu")
    txt = sub_linea(txt, r"^\s*\d+\s+!bloques de equilibrio\s*$", bloq_eq, "bloques de equilibrio")
    txt = sub_linea(txt, r"^\s*\d+\s+!bloques de calculo\s*$", bloq_calc, "bloques de calculo")
    txt = sub_linea(txt, r"^\s*\d+\s+!pasos por bloque\s*$", pasos, "pasos por bloque")
    txt = sub_linea(txt, r"^\s*\d+\s+!numero de walkers\s*$", nwalkers, "numero de walkers")

    # Verificacion explicita: etrial debe seguir siendo -631.8
    m = re.search(r"^\s*(-?\d+\.?\d*)\s+!etrial\s*$", txt, flags=re.MULTILINE)
    if not m or abs(float(m.group(1)) - (-631.8)) > 1e-9:
        raise RuntimeError(f"ETRIAL INCORRECTO tras la sustitucion: {m.group(1) if m else 'NO ENCONTRADO'} (se esperaba -631.8)")

    with open(salida, "w") as f:
        f.write(txt)
    print(f"OK: {salida} (etrial verificado = -631.8)")

if __name__ == "__main__":
    main()
