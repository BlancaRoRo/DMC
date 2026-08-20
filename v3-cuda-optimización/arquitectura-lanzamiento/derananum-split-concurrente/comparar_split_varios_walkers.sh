#!/bin/bash
# Compara produccion actual (REF) contra gpu-split (derananum partido en
# He4/resto/cierre, 2 kernels concurrentes + arreglo nhe3 en los bucles),
# 4 escalas de walkers, semilla 11. Restaura conf.20.00.HH antes de CADA
# corrida (leccion del bug de "carrera fantasma" documentado en
# derananum-split-concurrente.md).
set -e
BASE="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC"
REF="$BASE/v3-cuda-optimización/wavefhe4-fusion-test/gpu-fusion"
SPLIT="$BASE/v3-cuda-optimización/derananum-split-concurrente/gpu-split"
CONF="$BASE/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"
RESULT_DIR="$BASE/v3-cuda-optimización/derananum-split-concurrente/resultados_split"
mkdir -p "$RESULT_DIR"

WALKERS="500 1000 2000 3000"

restaura() {
  cp "$CONF" "$1/conf.20.00.HH"
  python3 -c "
import sys
sys.path.insert(0, '$BASE/v2-cuda-integracion/test-pasos')
from run_comparacion import genera_inmcv
genera_inmcv('$1', 'in.mcv.orig', '7', '$2', '1', '59', '20')
"
}

for nw in $WALKERS; do
  echo "=== REFERENCIA, ${nw}w ==="
  restaura "$REF" "$nw"
  t0=$(date +%s.%N)
  (cd "$REF" && timeout 600 ./qmccluster_pipeline < in.mcv > "$RESULT_DIR/referencia_${nw}w.log" 2>&1)
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"

  echo "=== SPLIT, ${nw}w ==="
  restaura "$SPLIT" "$nw"
  t0=$(date +%s.%N)
  (cd "$SPLIT" && timeout 600 ./qmccluster_pipeline < in.mcv > "$RESULT_DIR/split_${nw}w.log" 2>&1)
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"
done

echo "=== energias finales (deben coincidir por escala) ==="
for nw in $WALKERS; do
  echo "-- ${nw}w --"
  grep "meV Energia total" "$RESULT_DIR/referencia_${nw}w.log" "$RESULT_DIR/split_${nw}w.log"
done
