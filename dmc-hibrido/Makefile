FC=nvfortran
FFLAGS=-cuda -Kieee -Mnofma -gpu=lineinfo
LDFLAGS=-llapack -lblas

.SUFFIXES:
.SUFFIXES: .f90 .f .cuf .o

.f90.o:
	$(FC) $(FFLAGS) -c $<

.f.o:
	$(FC) $(FFLAGS) -c $<

.cuf.o:
	$(FC) $(FFLAGS) -c $<

OBJECTS=\
 mtipos.o\
 mrotaciones.o\
 mparametros.o\
 mlegendre.o\
 mangwavef.o\
 mrandom2.o\
 mrandom.o\
 msistref.o\
 mkp_heco.o\
 mhh_heocs.o\
 mvmolecula.o\
 mdensidades.o\
 mmcvpromedia.o\
 mvaziz.o\
 mtiempos.o\
 mlineal.o\
 mwavef.o\
 mdmcpromedia.o\
 mimagina.o\
 mconfiguraciones.o\
 mentradatos.o\
 glibc_exp_mod.o\
 glibc_pow.o\
 mcuda_globals.o\
 mlegendre_gpu.o\
 d_uhex4_mod.o\
 der_wavefx_mod.o\
 der_wavefhe4_mod.o\
 wavef_mod.o\
 derananum_mod.o\
 derananum_split_mod.o\
 glibc_sincos.o\
 rota_mod.o\
 valibre_mod.o\
 mccuerpo_mod.o\
 mVheheVphehe_mod.o\
 glibc_acos.o\
 angle_scalar_vec_mod.o\
 He_dihydrogen.o\
 mpotenbh_mod.o\
 vpot_mod.o\
 hpsi_mod.o\
 rand_gpu.o\
 dmc2.o\
 dmc2_pipeline.o\
 msync_gpu.o\
 msteps.o\
 mserie.o\
 mmontecarlo.o\
 mminimiza.o\
 bh_heh2m.o\
 modlegendre.o\
 pw_heocs.o\
 kpcoef.o\
 qmccluster.o\

qmccluster_pipeline: $(OBJECTS)
	$(FC) $(FFLAGS) -o $@ $(OBJECTS) $(LDFLAGS)

clean:
	rm -f *.o *.mod qmccluster_pipeline

mtipos.o: mtipos.f90
mrotaciones.o: mrotaciones.f90 mtipos.o
mparametros.o: mparametros.f90
mlegendre.o: mlegendre.f90
mangwavef.o: mangwavef.f90 mparametros.o mtipos.o mlegendre.o
mrandom2.o: mrandom2.f90
mrandom.o: mrandom.f90 mrandom2.o
msistref.o: msistref.f90 mparametros.o mtipos.o
mkp_heco.o: mkp_heco.f90
mhh_heocs.o: mhh_heocs.f90
mvmolecula.o: mvmolecula.f90 mhh_heocs.o mkp_heco.o
mdensidades.o: mdensidades.f90 msistref.o mparametros.o mtipos.o
mmcvpromedia.o: mmcvpromedia.f90 mtipos.o mdensidades.o
mvaziz.o: mvaziz.f90
mtiempos.o: mtiempos.f90
mlineal.o: mlineal.f90
mwavef.o: mwavef.f90 mparametros.o mtipos.o mangwavef.o mvaziz.o mvmolecula.o mrotaciones.o mlineal.o msistref.o mtiempos.o
mdmcpromedia.o: mdmcpromedia.f90 mtipos.o
mimagina.o: mimagina.f90 mtipos.o mlegendre.o
mconfiguraciones.o: mconfiguraciones.f90 mrandom.o
mentradatos.o: mentradatos.f90 mparametros.o mvaziz.o mhh_heocs.o mkp_heco.o mrandom.o
glibc_exp_mod.o: glibc_exp_mod.cuf
glibc_pow.o: glibc_pow.cuf glibc_exp_mod.o
mcuda_globals.o: mcuda_globals.cuf
mlegendre_gpu.o: mlegendre_gpu.cuf
d_uhex4_mod.o: d_uhex4_mod.cuf mtipos.o mlegendre_gpu.o glibc_pow.o
der_wavefx_mod.o: der_wavefx_mod.cuf mtipos.o mcuda_globals.o d_uhex4_mod.o mlegendre_gpu.o glibc_pow.o glibc_exp_mod.o
der_wavefhe4_mod.o: der_wavefhe4_mod.cuf mtipos.o glibc_pow.o glibc_exp_mod.o mcuda_globals.o
wavef_mod.o: wavef_mod.cuf mtipos.o mparametros.o der_wavefhe4_mod.o der_wavefx_mod.o glibc_pow.o glibc_exp_mod.o
derananum_mod.o: derananum_mod.cuf mtipos.o der_wavefhe4_mod.o der_wavefx_mod.o wavef_mod.o glibc_pow.o
derananum_split_mod.o: derananum_split_mod.cuf mtipos.o der_wavefhe4_mod.o der_wavefx_mod.o wavef_mod.o derananum_mod.o
glibc_sincos.o: glibc_sincos.cuf glibc_exp_mod.o
rota_mod.o: rota_mod.cuf mtipos.o glibc_sincos.o
valibre_mod.o: valibre_mod.cuf
mccuerpo_mod.o: mccuerpo_mod.cuf mtipos.o mcuda_globals.o
mVheheVphehe_mod.o: mVheheVphehe_mod.cuf glibc_exp_mod.o glibc_sincos.o
glibc_acos.o: glibc_acos.cuf glibc_exp_mod.o
angle_scalar_vec_mod.o: angle_scalar_vec_mod.cuf glibc_acos.o
He_dihydrogen.o: He_dihydrogen.f glibc_exp_mod.o mVheheVphehe_mod.o angle_scalar_vec_mod.o glibc_sincos.o glibc_pow.o
mpotenbh_mod.o: mpotenbh_mod.cuf He_dihydrogen.o
vpot_mod.o: vpot_mod.cuf mtipos.o mccuerpo_mod.o mpotenbh_mod.o
hpsi_mod.o: hpsi_mod.cuf mtipos.o valibre_mod.o derananum_mod.o vpot_mod.o der_wavefx_mod.o
rand_gpu.o: rand_gpu.cuf glibc_sincos.o
dmc2.o: dmc2.cuf mtipos.o hpsi_mod.o rota_mod.o rand_gpu.o der_wavefx_mod.o derananum_mod.o
dmc2_pipeline.o: dmc2_pipeline.cuf mtipos.o rota_mod.o rand_gpu.o der_wavefx_mod.o derananum_mod.o derananum_split_mod.o vpot_mod.o dmc2.o mcuda_globals.o d_uhex4_mod.o mccuerpo_mod.o He_dihydrogen.o mpotenbh_mod.o glibc_exp_mod.o mdensidades.o
msync_gpu.o: msync_gpu.cuf mparametros.o mcuda_globals.o d_uhex4_mod.o der_wavefx_mod.o der_wavefhe4_mod.o wavef_mod.o derananum_mod.o mpotenbh_mod.o vpot_mod.o hpsi_mod.o dmc2.o
msteps.o: msteps.f90 mparametros.o mtipos.o mrandom.o mwavef.o mrotaciones.o mmcvpromedia.o rand_gpu.o msync_gpu.o dmc2_pipeline.o mtiempos.o
mserie.o: mserie.f90 mtipos.o mrandom.o mrandom2.o mvaziz.o mvmolecula.o mparametros.o
mmontecarlo.o: mmontecarlo.f90 mparametros.o mconfiguraciones.o mtipos.o msteps.o dmc2_pipeline.o mwavef.o msistref.o mkp_heco.o mdensidades.o mimagina.o mmcvpromedia.o mdmcpromedia.o mrandom.o mserie.o mtiempos.o
mminimiza.o: mminimiza.f90 mparametros.o mmontecarlo.o mentradatos.o mserie.o
bh_heh2m.o: bh_heh2m.f
modlegendre.o: modlegendre.f
pw_heocs.o: pw_heocs.f
kpcoef.o: kpcoef.f
qmccluster.o: qmccluster.f90 mentradatos.o mmontecarlo.o mminimiza.o mparametros.o mserie.o
