#!/bin/bash
# NO EJECUTABLE: Original-Semilla/ se recorto a solo rand_gpu.cuf +
# in.mcv + resultados (era la copia previa a la correccion de
# v3-cuda-optimizacion/correccion-fisica/alineacion-semilla-walker1);
# los fuentes que este script listaba ya no estan en disco. Se conserva
# unicamente como referencia textual de que exactamente se compilo.
#
# Compila el binario de Original-Semilla/ (copia de hibrido_instrumentado/
# con opcion=8 anadida: fisica ORIGINAL + semillas de GPU -- ver
# comparacion-final.md). No toca hibrido_instrumentado/ ni sus binarios.
set -e
cd "$(dirname "$0")/Original-Semilla"

FILES="mtipos.f90 mrotaciones.f90 mparametros.f90 mlegendre.f90 mangwavef.f90 \
mrandom2.f90 mrandom.f90 msistref.f90 mkp_heco.f90 mhh_heocs.f90 mvmolecula.f90 \
mdensidades.f90 mmcvpromedia.f90 mvaziz.f90 mtiempos.f90 mlineal.f90 mwavef.f90 \
mdmcpromedia.f90 mimagina.f90 mconfiguraciones.f90 mentradatos.f90 \
glibc_exp_mod.cuf glibc_pow.cuf mcuda_globals.cuf mlegendre_gpu.cuf \
d_uhex4_mod.cuf der_wavefx_mod.cuf der_wavefhe4_mod.cuf wavef_mod.cuf \
derananum_mod.cuf glibc_sincos.cuf rota_mod.cuf valibre_mod.cuf mccuerpo_mod.cuf \
mVheheVphehe_mod.cuf glibc_acos.cuf angle_scalar_vec_mod.cuf He_dihydrogen.f \
mpotenbh_mod.cuf vpot_mod.cuf hpsi_mod.cuf rand_gpu.cuf dmc2.cuf dmc2_pipeline.cuf \
msync_gpu.cuf msteps.f90 mserie.f90 mmontecarlo.f90 mminimiza.f90 bh_heh2m.f \
modlegendre.f pw_heocs.f kpcoef.f qmccluster.f90"

nvfortran -cuda -Kieee -Mnofma -gpu=lineinfo -c $FILES
nvfortran -cuda -Kieee -Mnofma -gpu=lineinfo -o qmccluster_original_semilla $(echo $FILES | sed -E 's/\.(f90|f|cuf)\b/.o/g') -llapack -lblas
echo "OK: qmccluster_original_semilla"
