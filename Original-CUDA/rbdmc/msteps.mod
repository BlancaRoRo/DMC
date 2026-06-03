V34 :0x24 msteps
10 msteps.f90 S624 0
06/03/2026  17:46:31
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
D 173 26 808 1192 807 7
D 221 22 7
D 223 22 7
D 225 22 7
D 227 22 7
D 229 22 7
D 231 22 7
D 739 23 173 1 11 316 0 0 1 0 0
 0 315 11 11 316 316
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
S 780 3 0 0 0 7 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 7
R 807 25 23 mtipos walker
R 808 5 24 mtipos lw walker
R 809 5 25 mtipos atom walker
R 811 5 27 mtipos atom$sd walker
R 812 5 28 mtipos atom$p walker
R 813 5 29 mtipos atom$o walker
R 815 5 31 mtipos dwf walker
R 817 5 33 mtipos dwf$sd walker
R 818 5 34 mtipos dwf$p walker
R 819 5 35 mtipos dwf$o walker
R 821 5 37 mtipos delta walker
R 823 5 39 mtipos delta$sd walker
R 824 5 40 mtipos delta$p walker
R 825 5 41 mtipos delta$o walker
R 827 5 43 mtipos hb2m walker
R 829 5 45 mtipos hb2m$sd walker
R 830 5 46 mtipos hb2m$p walker
R 831 5 47 mtipos hb2m$o walker
R 833 5 49 mtipos sigma1 walker
R 835 5 51 mtipos sigma1$sd walker
R 836 5 52 mtipos sigma1$p walker
R 837 5 53 mtipos sigma1$o walker
R 839 5 55 mtipos sigma2 walker
R 841 5 57 mtipos sigma2$sd walker
R 842 5 58 mtipos sigma2$p walker
R 843 5 59 mtipos sigma2$o walker
R 845 5 61 mtipos sprop walker
R 846 5 62 mtipos dangle walker
R 847 5 63 mtipos b walker
R 848 5 64 mtipos sig1rot walker
R 849 5 65 mtipos sig2rot walker
R 850 5 66 mtipos sig1hrot walker
R 851 5 67 mtipos sig2hrot walker
R 852 5 68 mtipos dphi walker
R 853 5 69 mtipos eje0 walker
R 854 5 70 mtipos pos0 walker
R 857 26 73 mtipos =
R 862 26 78 mtipos +
R 864 26 80 mtipos -
R 866 26 82 mtipos *
S 1476 16 0 0 0 6 1 624 5078 14 400000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 4 13 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 i4
S 1478 16 0 0 0 6 1 624 5081 14 400000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 8 15 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 i8
S 1480 16 0 0 0 6 1 624 5084 14 400000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 8 15 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 r8
S 1481 23 5 0 0 0 1485 624 9126 0 0 A 0 0 0 0 B 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 pasodmc
S 1482 1 3 3 0 6 1 1481 8253 4 3000 A 0 0 0 0 B 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 nwpaso
S 1483 1 3 2 0 10 1 1481 9134 4 3000 A 0 0 0 0 B 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 egrow
S 1484 7 3 3 0 739 1 1481 8260 800204 3000 A 0 0 0 0 B 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 wsim
S 1485 14 5 0 0 0 1 1481 9126 200 400000 A 0 0 0 0 B 0 17 0 0 0 0 0 286 3 0 0 0 0 0 0 0 0 0 0 0 0 17 0 624 0 0 0 0 pasodmc pasodmc 
F 1485 3 1482 1483 1484
S 1486 6 1 0 0 7 1 1481 9140 40800006 3000 A 0 0 0 0 B 0 20 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 z_e_315
S 1487 23 5 0 0 0 1490 624 9148 0 0 A 0 0 0 0 B 0 67 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 dmc2
S 1488 1 3 3 0 173 1 1487 6560 4 3000 A 0 0 0 0 B 0 67 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 w1
S 1489 1 3 2 0 6 1 1487 9153 4 3000 A 0 0 0 0 B 0 67 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 nsons
S 1490 14 5 0 0 0 1 1487 9148 0 400000 A 0 0 0 0 B 0 67 0 0 0 0 0 290 2 0 0 0 0 0 0 0 0 0 0 0 0 67 0 624 0 0 0 0 dmc2 dmc2 
F 1490 2 1488 1489
S 1491 23 5 0 0 0 1493 624 9159 0 0 A 0 0 0 0 B 0 133 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 pasomet
S 1492 1 3 3 0 173 1 1491 6560 4 3000 A 0 0 0 0 B 0 133 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 w1
S 1493 14 5 0 0 0 1 1491 9159 0 400000 A 0 0 0 0 B 0 133 0 0 0 0 0 293 1 0 0 0 0 0 0 0 0 0 0 0 0 133 0 624 0 0 0 0 pasomet pasomet 
F 1493 1 1492
A 13 2 0 0 0 6 631 0 0 0 13 0 0 0 0 0 0 0 0 0 0 0
A 15 2 0 0 0 6 632 0 0 0 15 0 0 0 0 0 0 0 0 0 0 0
A 43 2 0 0 0 6 633 0 0 0 43 0 0 0 0 0 0 0 0 0 0 0
A 44 2 0 0 0 6 650 0 0 0 44 0 0 0 0 0 0 0 0 0 0 0
A 73 2 0 0 0 7 648 0 0 0 73 0 0 0 0 0 0 0 0 0 0 0
A 74 2 0 0 0 7 649 0 0 0 74 0 0 0 0 0 0 0 0 0 0 0
A 94 1 0 1 0 58 679 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 105 1 0 1 0 64 681 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 110 2 0 0 0 7 780 0 0 0 110 0 0 0 0 0 0 0 0 0 0 0
A 313 1 0 0 0 6 722 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 314 4 0 0 0 6 313 0 43 0 0 0 0 3 0 0 0 0 0 0 0 0
A 315 7 0 0 5 7 314 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
A 316 1 0 0 0 7 1486 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
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
T 807 173 0 0 0 0
A 812 7 221 0 1 2 1
A 811 7 0 110 1 10 1
A 818 7 223 0 1 2 1
A 817 7 0 110 1 10 1
A 824 7 225 0 1 2 1
A 823 7 0 110 1 10 1
A 830 7 227 0 1 2 1
A 829 7 0 110 1 10 1
A 836 7 229 0 1 2 1
A 835 7 0 110 1 10 1
A 842 7 231 0 1 2 1
A 841 7 0 110 1 10 0
Z
