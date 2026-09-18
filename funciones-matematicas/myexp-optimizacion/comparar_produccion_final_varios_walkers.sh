#!/bin/bash
# Prueba de rendimiento de PRODUCCION (hibrido_instrumentado), ya con
# GTEST fijo + (a) + nhe3 fijo migrados. 4 escalas de walkers, semilla
# 11. No hay "referencia sin tocar" que correr (produccion YA es la
# version optimizada) -- se guardan los logs para comparar contra los
# de resultados_nhe3_fijo/referencia_*.log (produccion ANTES de hoy).
set -e
V2="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v2-cuda-integracion"
PROD="$V2/hibrido_instrumentado"
CONF="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"
RESULT_DIR="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v3-cuda-optimización/myexp-optimizacion/resultados_produccion_final"
mkdir -p "$RESULT_DIR"

WALKERS="500 1000 2000 3000"

for nw in $WALKERS; do
  echo "=== PRODUCCION (GTEST+a+nhe3 fijos), ${nw}w ==="
  cp "$CONF" "$PROD/conf.20.00.HH"
  python3 -c "
import sys
sys.path.insert(0, '$V2/test-pasos')
from run_comparacion import genera_inmcv
genera_inmcv('$PROD', 'in.mcv.orig', '7', '$nw', '1', '59', '20')
"
  t0=$(date +%s.%N)
  (cd "$PROD" && timeout 600 ./qmccluster_pipeline < in.mcv > "$RESULT_DIR/produccion_${nw}w.log" 2>&1)
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"
  grep "meV Energia total" "$RESULT_DIR/produccion_${nw}w.log"
done

echo "=== TODO OK ==="
