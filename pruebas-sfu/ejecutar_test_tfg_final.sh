#!/bin/bash
# test-tfg-final: 2000w, 128 bloques, 100000 pasos -- SOLO GPU.
# La configuracion real que necesita el TFG. ~40h estimadas.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
source "$HERE/_comun.sh"

log "===== test-tfg-final: INICIO ====="
d="$HERE/test-tfg-final"
correr "$d" gpu 7 "$GPU_DIR/qmccluster_pipeline" qmccluster_pipeline 2000 128 100000
log "===== test-tfg-final: TERMINADO ====="
