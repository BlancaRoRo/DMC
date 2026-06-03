V34 :0x24 mrotaciones
15 mrotaciones.f90 S624 0
06/03/2026  17:46:23
use mtipos public 0 direct
enduse
D 58 26 641 24 640 7
D 79 26 659 1192 658 7
D 127 22 7
D 129 22 7
D 131 22 7
D 133 22 7
D 135 22 7
D 137 22 7
D 142 23 58 1 11 18 0 0 0 0 0
 0 18 11 11 18 18
S 624 24 0 0 0 6 1 0 5012 10005 0 A 0 0 0 0 B 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 mrotaciones
S 626 3 0 0 0 6 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 4 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6
S 627 3 0 0 0 6 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 8 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6
S 628 3 0 0 0 7 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 3 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 7
S 629 3 0 0 0 7 1 1 0 0 0 A 0 0 0 0 B 0 0 0 0 0 0 0 0 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 7
R 640 25 5 mtipos vec3
R 641 5 6 mtipos comp vec3
R 658 25 23 mtipos walker
R 659 5 24 mtipos lw walker
R 660 5 25 mtipos atom walker
R 662 5 27 mtipos atom$sd walker
R 663 5 28 mtipos atom$p walker
R 664 5 29 mtipos atom$o walker
R 666 5 31 mtipos dwf walker
R 668 5 33 mtipos dwf$sd walker
R 669 5 34 mtipos dwf$p walker
R 670 5 35 mtipos dwf$o walker
R 672 5 37 mtipos delta walker
R 674 5 39 mtipos delta$sd walker
R 675 5 40 mtipos delta$p walker
R 676 5 41 mtipos delta$o walker
R 678 5 43 mtipos hb2m walker
R 680 5 45 mtipos hb2m$sd walker
R 681 5 46 mtipos hb2m$p walker
R 682 5 47 mtipos hb2m$o walker
R 684 5 49 mtipos sigma1 walker
R 686 5 51 mtipos sigma1$sd walker
R 687 5 52 mtipos sigma1$p walker
R 688 5 53 mtipos sigma1$o walker
R 690 5 55 mtipos sigma2 walker
R 692 5 57 mtipos sigma2$sd walker
R 693 5 58 mtipos sigma2$p walker
R 694 5 59 mtipos sigma2$o walker
R 696 5 61 mtipos sprop walker
R 697 5 62 mtipos dangle walker
R 698 5 63 mtipos b walker
R 699 5 64 mtipos sig1rot walker
R 700 5 65 mtipos sig2rot walker
R 701 5 66 mtipos sig1hrot walker
R 702 5 67 mtipos sig2hrot walker
R 703 5 68 mtipos dphi walker
R 704 5 69 mtipos eje0 walker
R 705 5 70 mtipos pos0 walker
R 708 26 73 mtipos =
R 713 26 78 mtipos +
R 715 26 80 mtipos -
R 717 26 82 mtipos *
S 772 16 0 0 0 6 1 624 5031 14 400000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 4 13 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 i4
S 774 16 0 0 0 6 1 624 5037 14 400000 A 0 0 0 0 B 0 0 0 0 0 0 0 0 8 15 0 0 0 0 0 0 0 0 0 0 0 0 0 624 0 0 0 0 r8
S 777 23 5 0 0 0 781 624 5731 0 0 A 0 0 0 0 B 0 11 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 rota
S 778 1 3 1 0 6 1 777 5736 4 3000 A 0 0 0 0 B 0 11 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 i1
S 779 1 3 1 0 10 1 777 5739 4 3000 A 0 0 0 0 B 0 11 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 phi
S 780 7 3 3 0 142 1 777 5743 800004 3000 A 0 0 0 0 B 0 11 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 ejes
S 781 14 5 0 0 0 1 777 5731 0 400000 A 0 0 0 0 B 0 11 0 0 0 0 0 34 3 0 0 0 0 0 0 0 0 0 0 0 0 11 0 624 0 0 0 0 rota rota 
F 781 3 778 779 780
A 13 2 0 0 0 6 626 0 0 0 13 0 0 0 0 0 0 0 0 0 0 0
A 15 2 0 0 0 6 627 0 0 0 15 0 0 0 0 0 0 0 0 0 0 0
A 18 2 0 0 0 7 628 0 0 0 18 0 0 0 0 0 0 0 0 0 0 0
A 19 2 0 0 0 7 629 0 0 0 19 0 0 0 0 0 0 0 0 0 0 0
Z
T 658 79 0 0 0 0
A 663 7 127 0 1 2 1
A 662 7 0 19 1 10 1
A 669 7 129 0 1 2 1
A 668 7 0 19 1 10 1
A 675 7 131 0 1 2 1
A 674 7 0 19 1 10 1
A 681 7 133 0 1 2 1
A 680 7 0 19 1 10 1
A 687 7 135 0 1 2 1
A 686 7 0 19 1 10 1
A 693 7 137 0 1 2 1
A 692 7 0 19 1 10 0
Z
