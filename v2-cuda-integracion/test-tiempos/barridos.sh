#!/bin/bash
set -e
cd "$(dirname "$0")"

run() { python3 run_test.py "$@"; }

# --- Sweep A: walkers (base eq=1 calc=1 pasos=5) ---
run 4 100 1 1 5 sweepA_w100_op4
run 4 200 1 1 5 sweepA_w200_op4
run 5 100 1 1 5 sweepA_w100_op5
run 5 200 1 1 5 sweepA_w200_op5

# --- Sweep B: bloques de calculo (base walkers=50 eq=1 pasos=5) ---
run 4 50 1 2 5 sweepB_c2_op4
run 4 50 1 4 5 sweepB_c4_op4
run 5 50 1 2 5 sweepB_c2_op5
run 5 50 1 4 5 sweepB_c4_op5

# --- Sweep C: bloques de equilibrio (base walkers=50 calc=1 pasos=5) ---
run 4 50 2 1 5 sweepC_e2_op4
run 4 50 4 1 5 sweepC_e4_op4
run 5 50 2 1 5 sweepC_e2_op5
run 5 50 4 1 5 sweepC_e4_op5

# --- Sweep D: pasos por bloque (base walkers=50 eq=1 calc=1) ---
run 4 50 1 1 10 sweepD_p10_op4
run 4 50 1 1 20 sweepD_p20_op4
run 5 50 1 1 10 sweepD_p10_op5
run 5 50 1 1 20 sweepD_p20_op5

echo "TODOS LOS BARRIDOS COMPLETADOS"
