#!/bin/bash
# test-walkers: pasos=100, bloques=100 fijos; walkers=500,1000,1500,2000,2500
# Se para solo al terminar -- no encadena con los demas tests.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
source "$HERE/_comun.sh"

log "===== test-walkers: INICIO ====="
for w in 500 1000 1500 2000 2500; do
  d="$HERE/test-walkers/test-${w}w"
  correr "$d" gpu 7 "$GPU_DIR/qmccluster_pipeline" qmccluster_pipeline "$w" 100 100
  correr "$d" cpu 4 "$CPU_DIR/qmccluster" qmccluster "$w" 100 100
done
log "===== test-walkers: TERMINADO ====="
