#!/bin/bash
# Reanuda test-pasos justo donde se corto (test-50000p, solo GPU) para
# hacer hueco a la validacion de wavef_derwavefhe4 en float.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
source "$HERE/_comun.sh"

log "===== test-pasos (reanudado): test-50000p ====="
d="$HERE/test-pasos/test-50000p"
correr "$d" gpu 7 "$GPU_DIR/qmccluster_pipeline" qmccluster_pipeline 1000 100 50000
log "===== test-pasos: TERMINADO ====="
