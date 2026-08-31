#!/bin/bash
# Compara produccion actual (threads=32) contra gpu-threads128
# (threads=128), 4 escalas de walkers, semilla 11.
set -e
V2="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v2-cuda-integracion"
REF="$V2/hibrido_instrumentado"
T128="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v4-cuda-pruebas/prueba2-threads-por-bloque/gpu-threads128"
CONF="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"
RESULT_DIR="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v4-cuda-pruebas/prueba2-threads-por-bloque/resultados"
mkdir -p "$RESULT_DIR"

WALKERS="500 1000 2000 3000"

for nw in $WALKERS; do
  echo "=== REFERENCIA (threads=32), ${nw}w ==="
  cp "$CONF" "$REF/conf.20.00.HH"
  python3 -c "
import sys
sys.path.insert(0, '$V2/test-pasos')
from run_comparacion import genera_inmcv
genera_inmcv('$REF', 'in.mcv.orig', '7', '$nw', '1', '59', '20')
"
  t0=$(date +%s.%N)
  (cd "$REF" && timeout 600 ./qmccluster_pipeline < in.mcv > "$RESULT_DIR/referencia_${nw}w.log" 2>&1)
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"

  echo "=== THREADS=128, ${nw}w ==="
  cp "$CONF" "$T128/conf.20.00.HH"
  python3 -c "
import sys
sys.path.insert(0, '$V2/test-pasos')
from run_comparacion import genera_inmcv
genera_inmcv('$T128', 'in.mcv.orig', '7', '$nw', '1', '59', '20')
"
  t0=$(date +%s.%N)
  (cd "$T128" && timeout 600 ./qmccluster_pipeline < in.mcv > "$RESULT_DIR/threads128_${nw}w.log" 2>&1)
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"
done

echo "=== TODO OK ==="
