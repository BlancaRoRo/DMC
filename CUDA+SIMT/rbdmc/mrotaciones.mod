V34 :0x24 mrotaciones
15 mrotaciones.f90 S624 0
04/24/2026  21:39:15
use mtipos public 0 direct
enduse
D 316 26 894 24 893 7
D 337 26 911 1192 910 7
D 385 22 7
D 387 22 7
D 389 22 7
D 391 22 7
D 393 22 7
D 395 22 7
D 580 23 316 1 11 328 0 0 0 0 0
 0 328 11 11 328 328
S 624 24 0 0 0 6 1 0 5012 10005 0 A 0 0 0 0 B 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 mrotaciones
S 626 3 0 0 0 6 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 4 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6
S 627 3 0 0 0 6 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 8 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6
S 631 3 0 0 0 7 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 7
S 642 3 0 0 0 7 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 3 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 7
R 893 25 250 mtipos vec3
R 894 5 251 mtipos comp vec3
R 910 25 267 mtipos walker
R 911 5 268 mtipos lw walker
R 912 5 269 mtipos atom walker
R 914 5 271 mtipos atom$sd walker
R 915 5 272 mtipos atom$p walker
R 916 5 273 mtipos atom$o walker
R 918 5 275 mtipos dwf walker
R 920 5 277 mtipos dwf$sd walker
R 921 5 278 mtipos dwf$p walker
R 922 5 279 mtipos dwf$o walker
R 924 5 281 mtipos delta walker
R 926 5 283 mtipos delta$sd walker
R 927 5 284 mtipos delta$p walker
R 928 5 285 mtipos delta$o walker
R 930 5 287 mtipos hb2m walker
R 932 5 289 mtipos hb2m$sd walker
R 933 5 290 mtipos hb2m$p walker
R 934 5 291 mtipos hb2m$o walker
R 936 5 293 mtipos sigma1 walker
R 938 5 295 mtipos sigma1$sd walker
R 939 5 296 mtipos sigma1$p walker
R 940 5 297 mtipos sigma1$o walker
R 942 5 299 mtipos sigma2 walker
R 944 5 301 mtipos sigma2$sd walker
R 945 5 302 mtipos sigma2$p walker
R 946 5 303 mtipos sigma2$o walker
R 948 5 305 mtipos sprop walker
R 949 5 306 mtipos dangle walker
R 950 5 307 mtipos b walker
R 951 5 308 mtipos sig1rot walker
R 952 5 309 mtipos sig2rot walker
R 953 5 310 mtipos sig1hrot walker
R 954 5 311 mtipos sig2hrot walker
R 955 5 312 mtipos dphi walker
R 956 5 313 mtipos eje0 walker
R 957 5 314 mtipos pos0 walker
R 958 5 315 mtipos nsons walker
R 961 26 318 mtipos =
R 966 26 323 mtipos +
R 968 26 325 mtipos -
R 970 26 327 mtipos *
S 1117 16 0 0 0 6 1 624 5031 14 400000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 4 13 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 i4
S 1119 16 0 0 0 6 1 624 5037 14 400000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 8 15 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 r8
S 1122 23 5 0 0 0 1126 624 9368 0 0 A 0 0 0 0 B 0 11 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 rota
S 1123 1 3 1 0 6 1 1122 9373 4 3000 A 0 0 0 0 B 0 11 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 i1
S 1124 1 3 1 0 10 1 1122 9376 4 3000 A 0 0 0 0 B 0 11 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 phi
S 1125 7 3 3 0 580 1 1122 9380 800004 3000 A 0 0 0 0 B 0 11 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 ejes
S 1126 14 5 0 0 0 1 1122 9368 0 400000 A 0 0 0 0 B 0 11 0 0 0 0 0 79 3 0 0 0 0 0 0 0 0 0 0 0 0 11 0 624 0 0 0 0 rota rota 
F 1126 3 1123 1124 1125
A 13 2 0 0 0 6 626 0 0 0 13 0 0 0 0 0 0 0 0 0 0 0
A 15 2 0 0 0 6 627 0 0 0 15 0 0 0 0 0 0 0 0 0 0 0
A 29 2 0 0 0 7 631 0 0 0 29 0 0 0 0 0 0 0 0 0 0 0
A 328 2 0 0 0 7 642 0 0 0 328 0 0 0 0 0 0 0 0 0 0 0
Z
T 910 337 0 0 0 0
A 915 7 385 0 1 2 1
A 914 7 0 29 1 10 1
A 921 7 387 0 1 2 1
A 920 7 0 29 1 10 1
A 927 7 389 0 1 2 1
A 926 7 0 29 1 10 1
A 933 7 391 0 1 2 1
A 932 7 0 29 1 10 1
A 939 7 393 0 1 2 1
A 938 7 0 29 1 10 1
A 945 7 395 0 1 2 1
A 944 7 0 29 1 10 0
Z
