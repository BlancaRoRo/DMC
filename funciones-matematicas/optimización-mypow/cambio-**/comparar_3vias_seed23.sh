#!/bin/bash
# Misma comparacion de comparar_3vias.sh pero con semilla=23 en vez de
# 11 -- en esta sesion, seed=11 ya demostro no activar la divergencia
# de 1 ULP de ** nativo en la trayectoria real (mismo patron visto
# antes con x**y puro), asi que no es prueba de nada por si sola.
# seed=23 SI mostro divergencia medible anteriormente en esta sesion.
set -e
V2="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v2-cuda-integracion"
CPU="$V2/cpu-original-gfortran"
GPU_LOG="$V2/hibrido_instrumentado"
GPU_POW="$(cd "$(dirname "$0")" && pwd)/hibrido_instrumentado"
CONF="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"
RESULT_DIR="$(cd "$(dirname "$0")" && pwd)/resultados_3vias"
mkdir -p "$RESULT_DIR"

genera() {
  # genera(directorio, opcion, nwalkers, bloq_eq, bloq_calc, pasos)
  python3 -c "
import sys
sys.path.insert(0, '$V2/test-pasos')
from run_comparacion import genera_inmcv
genera_inmcv('$1', 'in.mcv.orig', '$2', '$3', '$4', '$5', '$6')
"
  sed -i -E 's/^0+11( *!semilla aleatoria.*)$/0000000000000023\1/' "$1/in.mcv"
}

NW=1000

echo "=== 1) CPU gfortran, seed=23, opcion=4, ${NW}w ==="
cp "$CONF" "$CPU/conf.20.00.HH"
genera "$CPU" 4 "$NW" 1 59 20
grep -m1 semilla "$CPU/in.mcv"
t0=$(date +%s.%N)
(cd "$CPU" && timeout 1200 ./qmccluster < in.mcv > "$RESULT_DIR/cpu_gfortran_seed23_${NW}w.log" 2>&1)
t1=$(date +%s.%N)
echo "  wall=$(echo "$t1 - $t0" | bc)s" | tee -a "$RESULT_DIR/wall_times_seed23.log"

echo "=== 2) GPU nvfortran, mypow_log (produccion), seed=23, opcion=7, ${NW}w ==="
cp "$CONF" "$GPU_LOG/conf.20.00.HH"
genera "$GPU_LOG" 7 "$NW" 1 59 20
grep -m1 semilla "$GPU_LOG/in.mcv"
t0=$(date +%s.%N)
(cd "$GPU_LOG" && timeout 1200 ./qmccluster_pipeline < in.mcv > "$RESULT_DIR/gpu_mypow_log_seed23_${NW}w.log" 2>&1)
t1=$(date +%s.%N)
echo "  wall=$(echo "$t1 - $t0" | bc)s" | tee -a "$RESULT_DIR/wall_times_seed23.log"

echo "=== 3) GPU nvfortran, ** nativo (cambio-**), seed=23, opcion=7, ${NW}w ==="
cp "$CONF" "$GPU_POW/conf.20.00.HH"
genera "$GPU_POW" 7 "$NW" 1 59 20
grep -m1 semilla "$GPU_POW/in.mcv"
t0=$(date +%s.%N)
(cd "$GPU_POW" && timeout 1200 ./qmccluster_pipeline < in.mcv > "$RESULT_DIR/gpu_pow_nativo_seed23_${NW}w.log" 2>&1)
t1=$(date +%s.%N)
echo "  wall=$(echo "$t1 - $t0" | bc)s" | tee -a "$RESULT_DIR/wall_times_seed23.log"

echo "=== TODO OK ==="
