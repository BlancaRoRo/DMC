#!/bin/bash
# Compila el codigo CPU ORIGINAL (nunca portado a CUDA, copiado tal
# cual de v1-cuda-desarrollo/ccuerpo/) con gfortran -- para que la
# referencia "op4" de test-pasos/test-walker/test-bloques sea de
# verdad "CPU, gfortran", no "CPU, nvfortran" (que es lo que se habia
# usado por error al reutilizar qmccluster_tiempos). Genera el binario
# "qmccluster" en este mismo directorio.
#
# Verificado bit a bit contra la version nvfortran (misma fisica
# original, sin ninguna diferencia): a escala pequena (1000w/1/2/20),
# diff vacio en la tabla de bloques y en la energia total.
set -e
cd "$(dirname "$0")"
make -f Makefile.serie clean >/dev/null 2>&1 || true
make -f Makefile.serie FC=gfortran FFLAGS="-O2" F77FLAGS="-ffixed-line-length-132 -O2"
echo "OK: qmccluster (gfortran, CPU original)"
