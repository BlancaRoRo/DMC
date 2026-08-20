#!/bin/bash
# Compara referencia (sin optimizar) vs duhe4x/uhe4x optimizado, en 3
# escalas de walkers distintas -- misma semilla (11), mismos bloques
# (1 eq + 59 calculo x 20 pasos). Corridas SECUENCIALES (no en
# paralelo -- comparten la misma GPU, medir a la vez falsearia los
# tiempos). Cada salida se guarda con nombre propio, nada se sobreescribe.
set -e
V2="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v2-cuda-integracion"
REF="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v3-cuda-optimización/tiempos-metodos-dmc/gpu-mejorado-instrumentado"
OPT="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v3-cuda-optimización/optimización-mypow/gpu-duhe4x-optimizado"
CONF="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"
RESULT_DIR="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v3-cuda-optimización/optimización-mypow/resultados_varios_walkers"
mkdir -p "$RESULT_DIR"

WALKERS="500 2000 3000"

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
  cp "$REF/tiempos_opcion7.dat" "$RESULT_DIR/referencia_${nw}w_tiempos_opcion7.dat"

  echo "=== OPTIMIZADO (duhe4x/uhe4x), ${nw}w ==="
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
