#!/bin/bash
# test-bloques: unica variable que cambia es "pasos por bloque"
# (5/10/20/40/80), manteniendo el numero de BLOQUES de calculo fijo
# (59) -- aisla el efecto de bloques mas largos/cortos, no el volumen
# total de trabajo (que SI variaba en test-pasos). Todo lo demas FIJO:
# bloques de equilibrio=1, nwalkers=1000. op4=CPU original
# (qmccluster_tiempos, opcion=4), op7=GPU pipeline ya corregido
# (qmccluster_pipeline, opcion=7). conf.20.00.HH fresco antes de CADA
# corrida individual (nunca reutilizado), igual que test-pasos.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
V2="$(dirname "$HERE")"
INSTR="$V2/hibrido_instrumentado"
CONF_FRESCO="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"

cd "$INSTR"

PASOS_POR_BLOQUE="5 10 20 40 80"

for pb in $PASOS_POR_BLOQUE; do
  # --- op4: CPU, codigo original ---
  cp "$CONF_FRESCO" conf.20.00.HH
  python3 -c "
import sys
sys.path.insert(0, '$V2/test-pasos')
from run_comparacion import genera_inmcv
genera_inmcv('.', 'in.mcv.orig', '4', '1000', '1', '59', '$pb')
"
  echo "=== op4_${pb}pasosbloque ==="
  t0=$(date +%s.%N)
  ./qmccluster_tiempos < in.mcv > "$HERE/op4_${pb}pasosbloque.log" 2>&1
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"

  # --- op7: GPU, pipeline corregido ---
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
