#!/bin/bash
# Compara 3 vias en la MISMA escala (1000 walkers, seed=11, 1 bloque
# equilibrio + 59 bloques calculo x 20 pasos -- misma config usada en
# la verificacion de produccion de optimizacion-mypow.md):
#   1) CPU gfortran (opcion=4)               -- referencia de exactitud
#   2) GPU nvfortran, mypow_log (produccion) -- hibrido_instrumentado real
#   3) GPU nvfortran, ** nativo (cambio-**)   -- esta carpeta
# Corridas SECUENCIALES (2 y 3 comparten GPU). Nada se sobreescribe:
# cada salida con nombre propio.
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
}

NW=1000

echo "=== 1) CPU gfortran, opcion=4, ${NW}w ==="
cp "$CONF" "$CPU/conf.20.00.HH"
genera "$CPU" 4 "$NW" 1 59 20
t0=$(date +%s.%N)
(cd "$CPU" && timeout 1200 ./qmccluster < in.mcv > "$RESULT_DIR/cpu_gfortran_${NW}w.log" 2>&1)
t1=$(date +%s.%N)
echo "  wall=$(echo "$t1 - $t0" | bc)s" | tee -a "$RESULT_DIR/wall_times.log"

echo "=== 2) GPU nvfortran, mypow_log (produccion), opcion=7, ${NW}w ==="
cp "$CONF" "$GPU_LOG/conf.20.00.HH"
genera "$GPU_LOG" 7 "$NW" 1 59 20
t0=$(date +%s.%N)
(cd "$GPU_LOG" && timeout 1200 ./qmccluster_pipeline < in.mcv > "$RESULT_DIR/gpu_mypow_log_${NW}w.log" 2>&1)
t1=$(date +%s.%N)
echo "  wall=$(echo "$t1 - $t0" | bc)s" | tee -a "$RESULT_DIR/wall_times.log"
cp "$GPU_LOG/tiempos_opcion7.dat" "$RESULT_DIR/gpu_mypow_log_${NW}w_tiempos_opcion7.dat"

echo "=== 3) GPU nvfortran, ** nativo (cambio-**), opcion=7, ${NW}w ==="
cp "$CONF" "$GPU_POW/conf.20.00.HH"
genera "$GPU_POW" 7 "$NW" 1 59 20
t0=$(date +%s.%N)
(cd "$GPU_POW" && timeout 1200 ./qmccluster_pipeline < in.mcv > "$RESULT_DIR/gpu_pow_nativo_${NW}w.log" 2>&1)
t1=$(date +%s.%N)
echo "  wall=$(echo "$t1 - $t0" | bc)s" | tee -a "$RESULT_DIR/wall_times.log"
cp "$GPU_POW/tiempos_opcion7.dat" "$RESULT_DIR/gpu_pow_nativo_${NW}w_tiempos_opcion7.dat"

echo "=== TODO OK ==="
