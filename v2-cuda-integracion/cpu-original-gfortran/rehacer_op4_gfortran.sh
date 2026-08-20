#!/bin/bash
# Rehace TODAS las corridas op4 (CPU) de las 3 baterias (test-pasos,
# test-walker, test-bloques) con el binario gfortran de este
# directorio, en vez del binario nvfortran usado por error. No toca
# los logs op7 (GPU) ya existentes -- esos se mantienen. conf.20.00.HH
# fresco antes de CADA corrida individual, igual que siempre.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
V2="$(dirname "$HERE")"
CONF_FRESCO="/home/blanca/Documentos/Universidad/TFG-CUDA/Repostorio/DMC/v1-cuda-desarrollo/ccuerpo/conf.20.00.HH"

cd "$HERE"

genera() {
  # genera(opcion, nwalkers, bloq_eq, bloq_calc, pasos)
  python3 -c "
import sys
sys.path.insert(0, '$V2/test-pasos')
from run_comparacion import genera_inmcv
genera_inmcv('.', 'in.mcv.orig', '$1', '$2', '$3', '$4', '$5')
"
}

correr() {
  # correr(destino_log)
  cp "$CONF_FRESCO" conf.20.00.HH
  echo "=== $1 ==="
  t0=$(date +%s.%N)
  ./qmccluster < in.mcv > "$1" 2>&1
  t1=$(date +%s.%N)
  echo "  wall=$(echo "$t1 - $t0" | bc)s"
}

echo "########## test-pasos: nwalkers=1000 fijo, pasos=20 fijo, bloq_calc variable ##########"
declare -A PASOS_BLOQ=( [300]=14 [600]=29 [1200]=59 [2500]=124 [5000]=249 )
for total in 300 600 1200 2500 5000; do
  bloq="${PASOS_BLOQ[$total]}"
  genera 4 1000 1 "$bloq" 20
  correr "$V2/test-pasos/resultados/op4_limpio_${total}pasos.log"
done

echo "########## test-walker: bloq_calc=59 fijo, pasos=20 fijo, nwalkers variable ##########"
for nw in 250 500 1000 2000 3000; do
  genera 4 "$nw" 1 59 20
  correr "$V2/test-walker/op4_${nw}walkers.log"
done

echo "########## test-bloques: bloq_calc=59 fijo, nwalkers=1000 fijo, pasos por bloque variable ##########"
for pb in 5 10 20 40 80; do
  genera 4 1000 1 59 "$pb"
  correr "$V2/test-bloques/op4_${pb}pasosbloque.log"
done

echo "=== TODO OK ==="
