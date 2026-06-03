V34 :0x24 msteps
10 msteps.f90 S624 0
04/28/2026  14:15:52
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
enduse
D 58 23 6 1 10 74 0 0 0 0 0
 10 73 11 10 73 74
D 61 23 6 1 11 74 0 0 0 0 0
 0 74 11 11 74 74
D 64 23 6 1 10 74 0 0 0 0 0
 10 73 11 10 73 74
D 67 23 6 1 11 74 0 0 0 0 0
 0 74 11 11 74 74
D 431 26 1059 1192 1058 7
D 479 22 7
D 481 22 7
D 483 22 7
D 485 22 7
D 487 22 7
D 489 22 7
D 1177 23 431 1 11 924 0 0 1 0 0
 0 923 11 11 924 924
S 624 24 0 0 0 6 1 0 5012 10005 0 A 0 0 0 0 B 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 msteps
S 631 3 0 0 0 6 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 4 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6
S 632 3 0 0 0 6 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 8 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6
S 633 3 0 0 0 6 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 2 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6
S 648 3 0 0 0 7 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 8 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 7
S 649 3 0 0 0 7 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 9 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 7
S 650 3 0 0 0 6 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 3 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6
R 679 7 18 mparametros nnup$ac
R 681 7 20 mparametros nndw$ac
R 722 6 61 mparametros nwalkers
S 782 3 0 0 0 7 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 7
R 1058 25 267 mtipos walker
R 1059 5 268 mtipos lw walker
R 1060 5 269 mtipos atom walker
R 1062 5 271 mtipos atom$sd walker
R 1063 5 272 mtipos atom$p walker
R 1064 5 273 mtipos atom$o walker
R 1066 5 275 mtipos dwf walker
R 1068 5 277 mtipos dwf$sd walker
R 1069 5 278 mtipos dwf$p walker
R 1070 5 279 mtipos dwf$o walker
R 1072 5 281 mtipos delta walker
R 1074 5 283 mtipos delta$sd walker
R 1075 5 284 mtipos delta$p walker
R 1076 5 285 mtipos delta$o walker
R 1078 5 287 mtipos hb2m walker
R 1080 5 289 mtipos hb2m$sd walker
R 1081 5 290 mtipos hb2m$p walker
R 1082 5 291 mtipos hb2m$o walker
R 1084 5 293 mtipos sigma1 walker
R 1086 5 295 mtipos sigma1$sd walker
R 1087 5 296 mtipos sigma1$p walker
R 1088 5 297 mtipos sigma1$o walker
R 1090 5 299 mtipos sigma2 walker
R 1092 5 301 mtipos sigma2$sd walker
R 1093 5 302 mtipos sigma2$p walker
R 1094 5 303 mtipos sigma2$o walker
R 1096 5 305 mtipos sprop walker
R 1097 5 306 mtipos dangle walker
R 1098 5 307 mtipos b walker
R 1099 5 308 mtipos sig1rot walker
R 1100 5 309 mtipos sig2rot walker
R 1101 5 310 mtipos sig1hrot walker
R 1102 5 311 mtipos sig2hrot walker
R 1103 5 312 mtipos dphi walker
R 1104 5 313 mtipos eje0 walker
R 1105 5 314 mtipos pos0 walker
R 1106 5 315 mtipos nsons walker
R 1109 26 318 mtipos =
R 1114 26 323 mtipos +
R 1116 26 325 mtipos -
R 1118 26 327 mtipos *
S 1820 16 0 0 0 6 1 624 5078 14 400000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 4 13 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 i4
S 1822 16 0 0 0 6 1 624 5081 14 400000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 8 15 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 i8
S 1824 16 0 0 0 6 1 624 5084 14 400000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 8 15 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 r8
S 1825 23 5 0 0 0 1829 624 12758 0 0 A 0 0 0 0 B 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 pasodmc
S 1826 1 3 3 0 6 1 1825 11890 4 3000 A 0 0 0 0 B 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 nwpaso
S 1827 1 3 2 0 10 1 1825 12766 4 3000 A 0 0 0 0 B 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 egrow
S 1828 7 3 3 0 1177 1 1825 9612 800204 3000 A 0 0 0 0 B 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 wsim
S 1829 14 5 0 0 0 1 1825 12758 200 400000 A 0 0 0 0 B 0 17 0 0 0 0 0 331 3 0 0 0 0 0 0 0 0 0 0 0 0 17 0 624 0 0 0 0 pasodmc pasodmc 
F 1829 3 1826 1827 1828
S 1830 6 1 0 0 7 1 1825 12772 40800006 3000 A 0 0 0 0 B 0 20 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 z_e_923
S 1831 23 5 0 0 0 1834 624 12780 0 0 A 0 0 0 0 B 0 67 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 dmc2
S 1832 1 3 3 0 431 1 1831 9509 4 3000 A 0 0 0 0 B 0 67 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 w1
S 1833 1 3 2 0 6 1 1831 9305 4 3000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 nsons
S 1834 14 5 0 0 0 1 1831 12780 0 400000 A 0 0 0 0 B 0 67 0 0 0 0 0 335 2 0 0 0 0 0 0 0 0 0 0 0 0 67 0 624 0 0 0 0 dmc2 dmc2 
F 1834 2 1832 1833
S 1835 23 5 0 0 0 1837 624 12785 0 0 A 0 0 0 0 B 0 132 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 pasomet
S 1836 1 3 3 0 431 1 1835 9509 4 3000 A 0 0 0 0 B 0 132 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 w1
S 1837 14 5 0 0 0 1 1835 12785 0 400000 A 0 0 0 0 B 0 132 0 0 0 0 0 338 1 0 0 0 0 0 0 0 0 0 0 0 0 132 0 624 0 0 0 0 pasomet pasomet 
F 1837 1 1836
A 13 2 0 0 0 6 631 0 0 0 13 0 0 0 0 0 0 0 0 0 0 0
A 15 2 0 0 0 6 632 0 0 0 15 0 0 0 0 0 0 0 0 0 0 0
A 43 2 0 0 0 6 633 0 0 0 43 0 0 0 0 0 0 0 0 0 0 0
A 44 2 0 0 0 6 650 0 0 0 44 0 0 0 0 0 0 0 0 0 0 0
A 73 2 0 0 0 7 648 0 0 0 73 0 0 0 0 0 0 0 0 0 0 0
A 74 2 0 0 0 7 649 0 0 0 74 0 0 0 0 0 0 0 0 0 0 0
A 94 1 0 1 0 58 679 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 105 1 0 1 0 64 681 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 119 2 0 0 0 7 782 0 0 0 119 0 0 0 0 0 0 0 0 0 0 0
A 921 1 0 0 0 6 722 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 922 4 0 0 0 6 921 0 43 0 0 0 0 3 0 0 0 0 0 0 0 0
A 923 7 0 0 0 7 922 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 924 1 0 0 0 7 1830 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
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
T 1058 431 0 0 0 0
A 1063 7 479 0 1 2 1
A 1062 7 0 119 1 10 1
A 1069 7 481 0 1 2 1
A 1068 7 0 119 1 10 1
A 1075 7 483 0 1 2 1
A 1074 7 0 119 1 10 1
A 1081 7 485 0 1 2 1
A 1080 7 0 119 1 10 1
A 1087 7 487 0 1 2 1
A 1086 7 0 119 1 10 1
A 1093 7 489 0 1 2 1
A 1092 7 0 119 1 10 0
Z
