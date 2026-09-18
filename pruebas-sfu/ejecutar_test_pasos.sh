#!/bin/bash
# test-pasos: walkers=1000, bloques=100 fijos; pasos=100,1000 (CPU+GPU),
# 10000,50000 (solo GPU). Se para solo al terminar.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
source "$HERE/_comun.sh"

log "===== test-pasos: INICIO ====="
for p in 100 1000; do
  d="$HERE/test-pasos/test-${p}p"
  correr "$d" gpu 7 "$GPU_DIR/qmccluster_pipeline" qmccluster_pipeline 1000 100 "$p"
  correr "$d" cpu 4 "$CPU_DIR/qmccluster" qmccluster 1000 100 "$p"
done
for p in 10000 50000; do
  d="$HERE/test-pasos/test-${p}p"
  correr "$d" gpu 7 "$GPU_DIR/qmccluster_pipeline" qmccluster_pipeline 1000 100 "$p"
done
log "===== test-pasos: TERMINADO ====="
