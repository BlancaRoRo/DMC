#!/bin/bash
# Fase 2 (README.md del proyecto): repite SOLO la mitad "op7" de
# test-walker/ (250/500/1000/2000/3000 walkers, nblockeq=1, nblock=59,
# npasosblo=20, semilla 11 -- misma configuracion exacta) con el
# pipeline YA MEJORADO (seed decorrelation + sincroniza_constantes_gpu/
# etrial + k_fase_h). NO relanza op4 (CPU gfortran): esos numeros ya
# existen y siguen siendo validos (../cpu-original-gfortran/
# rehacer_op4_gfortran_wall.log, test-walker/test-walker.md) --
# comparamos contra ellos directamente.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
V2="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v2-cuda-integracion"
GPU_DIR="$V2/hibrido_instrumentado"
CONF_FRESCO="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"

WALKERS="250 500 1000 2000 3000"

: > "$HERE/wall_times_op7_aos_soa.log"

for nw in $WALKERS; do
  cp "$CONF_FRESCO" "$GPU_DIR/conf.20.00.HH"
  python3 -c "
import sys
sys.path.insert(0, '$V2/test-pasos')
from run_comparacion import genera_inmcv
genera_inmcv('$GPU_DIR', 'in.mcv.orig', '7', '$nw', '1', '59', '20')
"
  echo "=== op7_${nw}walkers (mejorado) ===" | tee -a "$HERE/wall_times_op7_aos_soa.log"
  cd "$GPU_DIR"
  t0=$(date +%s.%N)
  timeout 600 ./qmccluster_pipeline < in.mcv > "$HERE/op7_aos_soa_${nw}walkers.log" 2>&1
  t1=$(date +%s.%N)
  dt=$(echo "$t1 - $t0" | bc)
  echo "  wall=${dt}s" | tee -a "$HERE/wall_times_op7_aos_soa.log"
  cd "$HERE"
done

echo "=== TODO OK ==="
