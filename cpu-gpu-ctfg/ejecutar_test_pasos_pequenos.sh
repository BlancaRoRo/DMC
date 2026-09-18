#!/bin/bash
# test-pasos-pequenos: walkers=1000, bloques de calculo=100 fijos (misma
# escala que pruebas-sfu/test-pasos, que ya cubre 100-50000 pasos);
# pasos por bloque = 1,2,5,10,15,20,25,30,40,50,75,100 -- barrido fino por
# debajo/hasta el rango ya probado (100 pasos, donde la GPU ya gana 11,7x)
# para ver si el eje de pasos tiene el mismo tipo de cruce que el de
# walkers, o si el coste fijo de la GPU se comporta distinto aqui (los
# pasos, a diferencia de los bloques, se quedan dentro del mismo grafo
# CUDA capturado, sin sincronizar con el host en cada uno).
# Se para solo al terminar.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
source "$HERE/_comun.sh"

log "===== test-pasos-pequenos: INICIO ====="
for p in 1 2 5 10 15 20 25 30 40 50 75 100; do
  d="$HERE/test-pasos-pequenos/test-${p}p"
  correr "$d" gpu 7 "$GPU_DIR/qmccluster_pipeline" qmccluster_pipeline 1000 100 "$p"
  correr "$d" cpu 4 "$CPU_DIR/qmccluster" qmccluster 1000 100 "$p"
done
log "===== test-pasos-pequenos: TERMINADO ====="
