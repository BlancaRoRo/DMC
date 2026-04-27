V34 :0x24 msteps
10 msteps.f90 S624 0
04/24/2026  21:39:46
use mrandom2 public 0 indirect
use mrandom public 0 direct
use mlegendre public 0 indirect
use mangwavef public 0 indirect
use mvaziz public 0 indirect
use mhh_heocs public 0 indirect
use mkp_heco public 0 indirect
use mvmolecula public 0 indirect
use mlineal public 0 indirect
use mwavef public 0 direct
use mrotaciones public 0 direct
use mtipos public 0 direct
use mparametros public 0 direct
use msistref public 0 indirect
use mdensidades public 0 indirect
use mmcvpromedia public 0 direct
use iso_c_binding public 0 indirect
use nvf_acc_common public 0 indirect
use cudafor_lib_la public 0 indirect
use cudafor_la public 0 direct
use dmc_gpu private
use dmc_gpu_params private
enduse
D 58 23 6 1 10 74 0 0 0 0 0
 10 73 11 10 73 74
D 61 23 6 1 11 74 0 0 0 0 0
 0 74 11 11 74 74
D 64 23 6 1 10 74 0 0 0 0 0
 10 73 11 10 73 74
D 67 23 6 1 11 74 0 0 0 0 0
 0 74 11 11 74 74
D 431 26 1067 1192 1066 7
D 479 22 7
D 481 22 7
D 483 22 7
D 485 22 7
D 487 22 7
D 489 22 7
D 1177 26 1844 8 1843 7
D 1186 26 1847 8 1846 7
D 1195 26 1844 8 1843 7
D 1216 26 1934 8 1933 7
D 4772 23 431 1 11 10111 0 0 1 0 0
 0 10110 11 11 10111 10111
S 624 24 0 0 0 6 1 0 5012 10005 0 A 0 0 0 0 B 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 msteps
S 634 23 0 0 0 9 15600 624 5112 4 0 A 0 0 0 0 B 400000 10 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 d_etrial
S 635 23 0 0 0 9 15868 624 5121 4 0 A 0 0 0 0 B 400000 10 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 gpu_soa_h2d
S 636 23 0 0 0 9 15872 624 5133 4 0 A 0 0 0 0 B 400000 10 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 gpu_soa_d2h
S 638 23 0 0 0 9 16084 624 5153 4 0 A 0 0 0 0 B 400000 11 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 dmc2_gpu_kernel
S 639 3 0 0 0 6 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 4 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6
S 640 3 0 0 0 6 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 8 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6
S 641 3 0 0 0 6 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 2 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6
S 656 3 0 0 0 7 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 8 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 7
S 657 3 0 0 0 7 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 9 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 7
S 658 3 0 0 0 6 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 3 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6
R 687 7 18 mparametros nnup$ac
R 689 7 20 mparametros nndw$ac
R 730 6 61 mparametros nwalkers
S 790 3 0 0 0 7 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 7
R 1066 25 267 mtipos walker
R 1067 5 268 mtipos lw walker
R 1068 5 269 mtipos atom walker
R 1070 5 271 mtipos atom$sd walker
R 1071 5 272 mtipos atom$p walker
R 1072 5 273 mtipos atom$o walker
R 1074 5 275 mtipos dwf walker
R 1076 5 277 mtipos dwf$sd walker
R 1077 5 278 mtipos dwf$p walker
R 1078 5 279 mtipos dwf$o walker
R 1080 5 281 mtipos delta walker
R 1082 5 283 mtipos delta$sd walker
R 1083 5 284 mtipos delta$p walker
R 1084 5 285 mtipos delta$o walker
R 1086 5 287 mtipos hb2m walker
R 1088 5 289 mtipos hb2m$sd walker
R 1089 5 290 mtipos hb2m$p walker
R 1090 5 291 mtipos hb2m$o walker
R 1092 5 293 mtipos sigma1 walker
R 1094 5 295 mtipos sigma1$sd walker
R 1095 5 296 mtipos sigma1$p walker
R 1096 5 297 mtipos sigma1$o walker
R 1098 5 299 mtipos sigma2 walker
R 1100 5 301 mtipos sigma2$sd walker
R 1101 5 302 mtipos sigma2$p walker
R 1102 5 303 mtipos sigma2$o walker
R 1104 5 305 mtipos sprop walker
R 1105 5 306 mtipos dangle walker
R 1106 5 307 mtipos b walker
R 1107 5 308 mtipos sig1rot walker
R 1108 5 309 mtipos sig2rot walker
R 1109 5 310 mtipos sig1hrot walker
R 1110 5 311 mtipos sig2hrot walker
R 1111 5 312 mtipos dphi walker
R 1112 5 313 mtipos eje0 walker
R 1113 5 314 mtipos pos0 walker
R 1114 5 315 mtipos nsons walker
R 1122 26 323 mtipos +
R 1124 26 325 mtipos -
R 1126 26 327 mtipos *
R 1163 14 364 mtipos inicivec3
R 1167 14 368 mtipos copiavec3
R 1171 14 372 mtipos copialoc
R 1175 14 376 mtipos copiawalker
R 1843 25 7 iso_c_binding c_ptr
R 1844 5 8 iso_c_binding val c_ptr
R 1846 25 10 iso_c_binding c_funptr
R 1847 5 11 iso_c_binding val c_funptr
R 1881 6 45 iso_c_binding c_null_ptr$ac
R 1883 6 47 iso_c_binding c_null_funptr$ac
R 1884 26 48 iso_c_binding ==
R 1886 26 50 iso_c_binding !=
R 1933 25 6 nvf_acc_common c_devptr
R 1934 5 7 nvf_acc_common cptr c_devptr
R 1940 6 13 nvf_acc_common c_null_devptr$ac
R 1988 14 61 nvf_acc_common __pgf90_assign_int_to_dim3
R 15600 6 25 dmc_gpu_params d_etrial
R 15868 14 293 dmc_gpu_params gpu_soa_h2d
R 15872 14 297 dmc_gpu_params gpu_soa_d2h
R 16084 14 202 dmc_gpu dmc2_gpu_kernel
S 16087 16 0 0 0 6 1 624 5169 14 400000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 4 13 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 i4
S 16088 16 0 0 0 6 1 624 5172 14 400000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 8 15 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 i8
S 16089 16 0 0 0 6 1 624 5175 14 400000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 8 15 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 r8
S 16090 26 0 0 0 0 1 624 9432 4 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 966 5 0 0 0 0 0 624 0 0 0 0 =
O 16090 5 1988 1175 1171 1167 1163
S 16091 23 5 0 0 0 16095 624 113801 0 0 A 0 0 0 0 B 0 30 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 pasodmc
S 16092 1 3 3 0 6 1 16091 11981 4 3000 A 0 0 0 0 B 0 30 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 nwpaso
S 16093 1 3 2 0 10 1 16091 113809 4 3000 A 0 0 0 0 B 0 30 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 egrow
S 16094 7 3 3 0 4772 1 16091 9703 800204 3000 A 0 0 0 0 B 0 30 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 wsim
S 16095 14 5 0 0 0 1 16091 113801 200 400000 A 0 0 0 0 B 0 30 0 0 0 0 0 5678 3 0 0 0 0 0 0 0 0 0 0 0 0 30 0 624 0 0 0 0 pasodmc pasodmc 
F 16095 3 16092 16093 16094
S 16096 6 1 0 0 7 1 16091 113815 40800006 3000 A 0 0 0 0 B 0 33 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 z_e_10110
S 16097 23 5 0 0 0 16100 624 113825 0 0 A 0 0 0 0 B 0 109 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 dmc2
S 16098 1 3 3 0 431 1 16097 9600 4 3000 A 0 0 0 0 B 0 109 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 w1
S 16099 1 3 2 0 6 1 16097 9396 4 3000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 nsons
S 16100 14 5 0 0 0 1 16097 113825 0 400000 A 0 0 0 0 B 0 109 0 0 0 0 0 5682 2 0 0 0 0 0 0 0 0 0 0 0 0 109 0 624 0 0 0 0 dmc2 dmc2 
F 16100 2 16098 16099
S 16101 23 5 0 0 0 16103 624 113830 0 0 A 0 0 0 0 B 0 173 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 pasomet
S 16102 1 3 3 0 431 1 16101 9600 4 3000 A 0 0 0 0 B 0 173 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 w1
S 16103 14 5 0 0 0 1 16101 113830 0 400000 A 0 0 0 0 B 0 173 0 0 0 0 0 5685 1 0 0 0 0 0 0 0 0 0 0 0 0 173 0 624 0 0 0 0 pasomet pasomet 
F 16103 1 16102
A 13 2 0 0 0 6 639 0 0 0 13 0 0 0 0 0 0 0 0 0 0 0
A 15 2 0 0 0 6 640 0 0 0 15 0 0 0 0 0 0 0 0 0 0 0
A 43 2 0 0 0 6 641 0 0 0 43 0 0 0 0 0 0 0 0 0 0 0
A 44 2 0 0 0 6 658 0 0 0 44 0 0 0 0 0 0 0 0 0 0 0
A 73 2 0 0 0 7 656 0 0 0 73 0 0 0 0 0 0 0 0 0 0 0
A 74 2 0 0 0 7 657 0 0 0 74 0 0 0 0 0 0 0 0 0 0 0
A 94 1 0 1 0 58 687 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 105 1 0 1 0 64 689 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 119 2 0 0 0 7 790 0 0 0 119 0 0 0 0 0 0 0 0 0 0 0
A 964 1 0 0 0 1177 1881 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 967 1 0 0 0 1186 1883 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 1030 1 0 0 0 1216 1940 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 10108 1 0 0 4308 6 730 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 10109 4 0 0 6412 6 10108 0 43 0 0 0 0 3 0 0 0 0 0 0 0 0
A 10110 7 0 0 8117 7 10109 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 10111 1 0 0 6571 7 16096 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
Z
J 24 1 1
V 94 58 7 0
R 0 61 0 0
A 0 6 0 0 1 2 1
A 0 6 0 0 1 3 1
A 0 6 0 0 1 3 1
A 0 6 0 0 1 43 1
A 0 6 0 0 1 44 1
A 0 6 0 0 1 13 1
A 0 6 0 0 1 13 1
A 0 6 0 0 1 13 1
A 0 6 0 0 1 13 0
J 25 1 1
V 105 64 7 0
R 0 67 0 0
A 0 6 0 0 1 2 1
A 0 6 0 0 1 2 1
A 0 6 0 0 1 3 1
A 0 6 0 0 1 3 1
A 0 6 0 0 1 3 1
A 0 6 0 0 1 3 1
A 0 6 0 0 1 43 1
A 0 6 0 0 1 44 1
A 0 6 0 0 1 13 0
J 133 1 1
V 964 1177 7 0
S 0 1177 0 0 0
A 0 6 0 0 1 2 0
J 134 1 1
V 967 1186 7 0
S 0 1186 0 0 0
A 0 6 0 0 1 2 0
J 36 1 1
V 1030 1216 7 0
S 0 1216 0 0 0
A 0 1195 0 0 1 964 0
T 1066 431 0 0 0 0
A 1071 7 479 0 1 2 1
A 1070 7 0 119 1 10 1
A 1077 7 481 0 1 2 1
A 1076 7 0 119 1 10 1
A 1083 7 483 0 1 2 1
A 1082 7 0 119 1 10 1
A 1089 7 485 0 1 2 1
A 1088 7 0 119 1 10 1
A 1095 7 487 0 1 2 1
A 1094 7 0 119 1 10 1
A 1101 7 489 0 1 2 1
A 1100 7 0 119 1 10 0
Z
