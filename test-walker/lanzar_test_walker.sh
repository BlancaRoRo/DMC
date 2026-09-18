#!/bin/bash
# test-walker: unica variable que cambia es "numero de walkers"
# (250/500/1000/2000/3000 -- 4000 se probo y falla, ver test-walker.md
# "Limitacion encontrada"). Todo lo demas FIJO: bloques de
# equilibrio=1, bloques de calculo=59, pasos por bloque=20 (=1180
# pasos de calculo en las 5 corridas, siempre igual). op4=CPU original
# (qmccluster_tiempos, opcion=4), op7=GPU pipeline ya corregido
# (qmccluster_pipeline, opcion=7). conf.20.00.HH fresco antes de CADA
# corrida individual (nunca reutilizado), igual que test-pasos.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
V2="$(dirname "$HERE")"
INSTR="$V2/hibrido_instrumentado"
CONF_FRESCO="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"

cd "$INSTR"

WALKERS="250 500 1000 2000 3000"

for nw in $WALKERS; do
  # --- op4: CPU, codigo original ---
  cp "$CONF_FRESCO" conf.20.00.HH
  python3 -c "
import sys
sys.path.insert(0, '$V2/test-pasos')
from run_comparacion import genera_inmcv
genera_inmcv('.', 'in.mcv.orig', '4', '$nw', '1', '59', '20')
"
  echo "=== op4_${nw}walkers ==="
  t0=$(date +%s.%N)
  ./qmccluster_tiempos < in.mcv > "$HERE/op4_${nw}walkers.log" 2>&1
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"

  # --- op7: GPU, pipeline corregido ---
  cp "$CONF_FRESCO" conf.20.00.HH
  python3 -c "
import sys
sys.path.insert(0, '$V2/test-pasos')
from run_comparacion import genera_inmcv
genera_inmcv('.', 'in.mcv.orig', '7', '$nw', '1', '59', '20')
"
  echo "=== op7_${nw}walkers ==="
  t0=$(date +%s.%N)
  ./qmccluster_pipeline < in.mcv > "$HERE/op7_${nw}walkers.log" 2>&1
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"
done

echo "=== TODO OK ==="
