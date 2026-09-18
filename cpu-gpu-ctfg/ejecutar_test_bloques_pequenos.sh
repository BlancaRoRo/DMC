#!/bin/bash
# test-bloques-pequenos: walkers=1000, pasos por bloque=100 fijos (misma
# escala que pruebas-sfu/test-bloques, que ya cubre 50-500 bloques);
# bloques de calculo = 1,2,5,10,15,20,25,30,40,50 -- barrido fino por
# debajo del rango ya probado (50 bloques, donde la GPU ya gana 11,0x)
# para ver si el eje de bloques tiene el mismo tipo de cruce que el de
# walkers, o si el coste fijo de la GPU se comporta distinto aqui
# (posible sincronizacion host por cada bloque, no solo por corrida).
# Se para solo al terminar.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
source "$HERE/_comun.sh"

log "===== test-bloques-pequenos: INICIO ====="
for b in 1 2 5 10 15 20 25 30 40 50; do
  d="$HERE/test-bloques-pequenos/test-${b}b"
  correr "$d" gpu 7 "$GPU_DIR/qmccluster_pipeline" qmccluster_pipeline 1000 "$b" 100
  correr "$d" cpu 4 "$CPU_DIR/qmccluster" qmccluster 1000 "$b" 100
done
log "===== test-bloques-pequenos: TERMINADO ====="
