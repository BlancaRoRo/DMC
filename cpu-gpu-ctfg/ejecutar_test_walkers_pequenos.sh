#!/bin/bash
# test-walkers-pequenos: pasos=100, bloques=100 fijos (misma escala que
# pruebas-sfu/test-walkers); walkers = 1,5,10,15,20,25,30,40,50,75,100,150,250,500
# -- barrido fino por debajo del rango ya probado en pruebas-sfu (500-2500w,
# donde la GPU gana siempre 9,8x-12,6x) para buscar el punto de cruce real,
# si existe, en la zona donde el overhead fijo de la GPU pesa mas que el
# trabajo por hacer.
# Se para solo al terminar -- no encadena con nada mas.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
source "$HERE/_comun.sh"

log "===== test-walkers-pequenos: INICIO ====="
for w in 1 5 10 15 20 25 30 40 50 75 100 150 250 500; do
  d="$HERE/test-walkers-pequenos/test-${w}w"
  correr "$d" gpu 7 "$GPU_DIR/qmccluster_pipeline" qmccluster_pipeline "$w" 100 100
  correr "$d" cpu 4 "$CPU_DIR/qmccluster" qmccluster "$w" 100 100
done
log "===== test-walkers-pequenos: TERMINADO ====="
