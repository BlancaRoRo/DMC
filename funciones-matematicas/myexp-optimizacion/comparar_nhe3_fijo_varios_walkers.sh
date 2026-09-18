#!/bin/bash
# Compara produccion actual (REF, sin GTEST/nhe3 fijos) contra
# gpu-gtest-fijo-mas-a-mas-nhe3fijo (GTEST fijo + (a) + nhe3 fijo,
# SIN (b)), 4 escalas de walkers, semilla 11.
set -e
V2="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v2-cuda-integracion"
REF="$V2/hibrido_instrumentado"
NHE3FIJO="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v3-cuda-optimización/myexp-optimizacion/gpu-gtest-fijo-mas-a-mas-nhe3fijo"
CONF="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"
RESULT_DIR="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v3-cuda-optimización/myexp-optimizacion/resultados_nhe3_fijo"
mkdir -p "$RESULT_DIR"

WALKERS="500 1000 2000 3000"

for nw in $WALKERS; do
  echo "=== REFERENCIA, ${nw}w ==="
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

  echo "=== GTEST fijo + (a) + nhe3 fijo, ${nw}w ==="
  cp "$CONF" "$NHE3FIJO/conf.20.00.HH"
  python3 -c "
import sys
sys.path.insert(0, '$V2/test-pasos')
from run_comparacion import genera_inmcv
genera_inmcv('$NHE3FIJO', 'in.mcv.orig', '7', '$nw', '1', '59', '20')
"
  t0=$(date +%s.%N)
  (cd "$NHE3FIJO" && timeout 600 ./qmccluster_pipeline < in.mcv > "$RESULT_DIR/nhe3fijo_${nw}w.log" 2>&1)
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"
done

echo "=== TODO OK ==="
