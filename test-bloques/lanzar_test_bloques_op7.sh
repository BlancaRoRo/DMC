#!/bin/bash
# Solo la mitad GPU (op7) de test-bloques -- la mitad CPU (op4) se hace
# aparte con gfortran (ver cpu-original-gfortran/rehacer_op4_gfortran.sh).
# Se ejecuta en paralelo con esa porque usa un directorio distinto
# (hibrido_instrumentado/), sin conflicto de conf.20.00.HH/in.mcv.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
V2="$(dirname "$HERE")"
INSTR="$V2/hibrido_instrumentado"
CONF_FRESCO="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"

cd "$INSTR"

PASOS_POR_BLOQUE="5 10 20 40 80"

for pb in $PASOS_POR_BLOQUE; do
  cp "$CONF_FRESCO" conf.20.00.HH
  python3 -c "
import sys
sys.path.insert(0, '$V2/test-pasos')
from run_comparacion import genera_inmcv
genera_inmcv('.', 'in.mcv.orig', '7', '1000', '1', '59', '$pb')
"
  echo "=== op7_${pb}pasosbloque ==="
  t0=$(date +%s.%N)
  ./qmccluster_pipeline < in.mcv > "$HERE/op7_${pb}pasosbloque.log" 2>&1
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"
done

echo "=== TODO OK ==="
