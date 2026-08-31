#!/bin/bash
# test-bloques: walkers=1000, pasos=100 fijos; bloques=50,100,200,300,500
# Se para solo al terminar -- no encadena con los demas tests.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
source "$HERE/_comun.sh"

log "===== test-bloques: INICIO ====="
for b in 50 100 200 300 500; do
  d="$HERE/test-bloques/test-${b}b"
  correr "$d" gpu 7 "$GPU_DIR/qmccluster_pipeline" qmccluster_pipeline 1000 "$b" 100
  correr "$d" cpu 4 "$CPU_DIR/qmccluster" qmccluster 1000 "$b" 100
done
log "===== test-bloques: TERMINADO ====="
