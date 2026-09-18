#!/bin/bash
# Repite la progresion de escalas (300/600/1200/2500/5000 pasos totales)
# para op4 (CPU, qmccluster_tiempos, opcion=4) y op7 (GPU, pipeline ya
# corregido, qmccluster_pipeline, opcion=7) -- version LIMPIA: copia
# conf.20.00.HH FRESCO antes de CADA corrida individual (10 en total),
# nunca reutilizado entre corridas, para que las 10 arranquen desde la
# MISMA configuracion inicial de walkers (verificable via "energia
# final de las configuraciones", que debe salir identica en las 10).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
INSTR="$HERE/../hibrido_instrumentado"
RES="$HERE/resultados"
CONF_FRESCO="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"

cd "$INSTR"

# pasos_totales:bloques_calculo (bloq_eq=1, pasos=20 fijos, igual que la
# progresion original)
ESCALAS="300:14 600:29 1200:59 2500:124 5000:249"

for par in $ESCALAS; do
  total="${par%%:*}"
  bloq="${par##*:}"

  # --- op4: CPU, codigo original, qmccluster_tiempos ---
  cp "$CONF_FRESCO" conf.20.00.HH
  python3 -c "
import sys
sys.path.insert(0, '$HERE')
from run_comparacion import genera_inmcv
genera_inmcv('.', 'in.mcv.orig', '4', '1000', '1', '$bloq', '20')
"
  echo "=== op4_limpio_${total}pasos ==="
  t0=$(date +%s.%N)
  ./qmccluster_tiempos < in.mcv > "$RES/op4_limpio_${total}pasos.log" 2>&1
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"

  # --- op7: GPU, pipeline corregido, qmccluster_pipeline ---
  cp "$CONF_FRESCO" conf.20.00.HH
  python3 -c "
import sys
sys.path.insert(0, '$HERE')
from run_comparacion import genera_inmcv
genera_inmcv('.', 'in.mcv.orig', '7', '1000', '1', '$bloq', '20')
"
  echo "=== op7_limpio_${total}pasos ==="
  t0=$(date +%s.%N)
  ./qmccluster_pipeline < in.mcv > "$RES/op7_limpio_${total}pasos.log" 2>&1
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"
done

echo "=== TODO OK ==="
