#!/bin/bash
# Compara produccion actual (REF) contra gpu-myexp-solo-b (solo el
# cambio (b): fn2_rh1/fn2_rh2/fn2_r0 cacheados en Ex0/Ey0/Ez0, sin
# tocar FN1/FN2/DFN1/DFN2), 4 escalas de walkers, semilla 11.
set -e
V2="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v2-cuda-integracion"
REF="$V2/hibrido_instrumentado"
SOLOB="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v3-cuda-optimización/myexp-optimizacion/gpu-myexp-solo-b"
CONF="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"
RESULT_DIR="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v3-cuda-optimización/myexp-optimizacion/resultados_solo_b"
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

  echo "=== SOLO-B, ${nw}w ==="
  cp "$CONF" "$SOLOB/conf.20.00.HH"
  python3 -c "
import sys
sys.path.insert(0, '$V2/test-pasos')
from run_comparacion import genera_inmcv
genera_inmcv('$SOLOB', 'in.mcv.orig', '7', '$nw', '1', '59', '20')
"
  t0=$(date +%s.%N)
  (cd "$SOLOB" && timeout 600 ./qmccluster_pipeline < in.mcv > "$RESULT_DIR/solob_${nw}w.log" 2>&1)
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"
done

echo "=== TODO OK ==="
