#!/bin/bash
# Robustez de k_multiwalker: repite W=4,8,16,32 en varias escalas de
# walkers (no solo 1500) para comprobar que la ganancia de W=16 no es
# un efecto puntual de esa escala concreta. k_solo se mide siempre en
# la misma corrida (referencia interna, misma pasada de nsys).
set -e
cd "$(dirname "$0")"
mkdir -p robustez

for n in 500 1000 1500 2000 3000; do
  for wpb in 4 8 16 32; do
    tag="n${n}_wpb${wpb}"
    nsys profile --force-overwrite=true -o "robustez/nsys_${tag}" ./test_bloque_walker $n 10 1 $wpb > "robustez/stdout_${tag}.log" 2>&1
  done
done
echo "TODO OK"
