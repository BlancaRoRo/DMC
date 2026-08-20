#!/bin/bash
# Compara produccion actual (mypow_log en todos los metodos +
# He_dihydrogen fusionado, myexp SIN compartir) contra
# gpu-myexp-optimizado (mismo + FN1/DFN1/FN2/DFN2 compartiendo F00 +
# fn2_rh1/fn2_rh2/fn2_r0 cacheados), 4 escalas de walkers, semilla 11.
set -e
V2="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v2-cuda-integracion"
REF="$V2/hibrido_instrumentado"
OPT="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v3-cuda-optimización/myexp-optimizacion/gpu-myexp-optimizado"
CONF="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"
RESULT_DIR="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v3-cuda-optimización/myexp-optimizacion/resultados_myexp"
mkdir -p "$RESULT_DIR"

WALKERS="500 1000 2000 3000"

for nw in $WALKERS; do
  echo "=== REFERENCIA (produccion actual), ${nw}w ==="
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
  cp "$REF/tiempos_opcion7.dat" "$RESULT_DIR/referencia_${nw}w_tiempos_opcion7.dat"

  echo "=== OPTIMIZADO (myexp compartido), ${nw}w ==="
  cp "$CONF" "$OPT/conf.20.00.HH"
  python3 -c "
import sys
sys.path.insert(0, '$V2/test-pasos')
from run_comparacion import genera_inmcv
genera_inmcv('$OPT', 'in.mcv.orig', '7', '$nw', '1', '59', '20')
"
  t0=$(date +%s.%N)
  (cd "$OPT" && timeout 600 ./qmccluster_pipeline < in.mcv > "$RESULT_DIR/optimizado_${nw}w.log" 2>&1)
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"
  cp "$OPT/tiempos_opcion7.dat" "$RESULT_DIR/optimizado_${nw}w_tiempos_opcion7.dat"
done

echo "=== TODO OK ==="
