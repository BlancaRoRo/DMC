C*************************************************************************
C
C  Subroutine He_dihydrogen calculates the cartesian
C  gradient derivative matrix analytically.
C
C  Version GPU: attributes(host,device) + reutiliza V_hehe/Vp_hehe
C  (modulo mVheheVphehe) y angle/scalar_product/vec_norm (modulo
C  angle_scalar_vec), ya portados y probados por separado. Fichero en
C  formato FIJO a proposito (igual que el original bh_heh2m.f): permite
C  copiar el cuerpo tal cual, sin reformatear ninguna linea de
C  continuacion, y el INCLUDE de param_atoms_bh.h puede seguir siendo
C  el ORIGINAL (fijo), sin necesitar una version _freeform como la que
C  hizo falta para V_hehe/Vp_hehe (aquellas se portaron a un .cuf de
C  formato libre; esta se queda en formato fijo, no hay choque).
C
C  Se envuelve en un MODULE (mHe_dihydrogen) por el mismo motivo que
C  V_hehe/Vp_hehe/angle/etc: si se deja como subrutina externa suelta,
C  su simbolo enlazado (he_dihydrogen_) es el MISMO que el de la
C  version original de bh_heh2m.f, y el enlazador falla con "multiple
C  definition" en cuanto se linkan los dos .o juntos (como hace falta
C  aqui, para comparar GPU contra la CPU de referencia). Metida en un
C  modulo, el simbolo queda cualificado por el modulo y no choca.
C  MODULE/CONTAINS/END MODULE son validas en formato fijo igual que en
C  libre, asi que esto no obliga a reformatear nada del cuerpo.
C
C*************************************************************************
C
      module mHe_dihydrogen
      contains

C  F00...DFN2 eran funciones-sentencia locales de He_dihydrogen (una
C  sola expresion cada una, sin sitio para acumular paso a paso). Se
C  convierten aqui en funciones de modulo de verdad: F00...DF6 no
C  cambian de formula (cada una es una sola operacion, sin varios
C  sumandos que reagrupar, asi que no aportaban ULPs); FN1/DFN1/FN2/
C  DFN2 (sumas de 7 y 3 terminos) SI se reescriben con acumulacion
C  secuencial explicita -- ver docs-kernels/He_dihydrogen.md Parte 3
C  para la diseccion completa que encontro esto como fuente real de
C  discrepancia GPU-vs-gfortran, independiente de dcos/dsin/dexp.

      attributes(host,device) FUNCTION F00(XDUMM)
      use glibc_exp_mod, only: myexp
      IMPLICIT NONE
      DOUBLE PRECISION F00, XDUMM
      F00=myexp(-XDUMM)
      END FUNCTION F00

      attributes(host,device) FUNCTION F0(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION F0, XDUMM
      F0=1.d0-F00(XDUMM)
      END FUNCTION F0

      attributes(host,device) FUNCTION DF0(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION DF0, XDUMM
      DF0=F00(XDUMM)
      END FUNCTION DF0

      attributes(host,device) FUNCTION F1(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION F1, XDUMM
      F1=-F00(XDUMM)*XDUMM
      END FUNCTION F1

      attributes(host,device) FUNCTION DF1(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION DF1, XDUMM
      DF1=DF0(XDUMM)*XDUMM-F00(XDUMM)
      END FUNCTION DF1

      attributes(host,device) FUNCTION F2(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION F2, XDUMM
      F2=-F00(XDUMM)*(XDUMM)**2/2.d0
      END FUNCTION F2

      attributes(host,device) FUNCTION DF2(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION DF2, XDUMM
      DF2=DF0(XDUMM)*(XDUMM)**2/2.d0-XDUMM*F00(XDUMM)
      END FUNCTION DF2

      attributes(host,device) FUNCTION F3(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION F3, XDUMM
      F3=-F00(XDUMM)*(XDUMM)**3/6.d0
      END FUNCTION F3

      attributes(host,device) FUNCTION DF3(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION DF3, XDUMM
      DF3=DF0(XDUMM)*(XDUMM)**3/6.d0-XDUMM*XDUMM*F00(XDUMM)/2.d0
      END FUNCTION DF3

      attributes(host,device) FUNCTION F4(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION F4, XDUMM
      F4=-F00(XDUMM)*(XDUMM)**4/24.d0
      END FUNCTION F4

      attributes(host,device) FUNCTION DF4(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION DF4, XDUMM
      DF4=DF0(XDUMM)*(XDUMM)**4/24.d0
     &    -XDUMM*XDUMM*XDUMM*F00(XDUMM)/6.d0
      END FUNCTION DF4

      attributes(host,device) FUNCTION F5(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION F5, XDUMM
      F5=-F00(XDUMM)*(XDUMM)**5/120.d0
      END FUNCTION F5

      attributes(host,device) FUNCTION DF5(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION DF5, XDUMM
      DF5=DF0(XDUMM)*(XDUMM)**5/120.d0
     &    -XDUMM*XDUMM*XDUMM*XDUMM*F00(XDUMM)/24.d0
      END FUNCTION DF5

      attributes(host,device) FUNCTION F6(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION F6, XDUMM
      F6=-F00(XDUMM)*(XDUMM)**6/720.d0
      END FUNCTION F6

      attributes(host,device) FUNCTION DF6(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION DF6, XDUMM
      DF6=DF0(XDUMM)*(XDUMM)**6/720.d0
     &    -XDUMM*XDUMM*XDUMM*XDUMM*XDUMM*F00(XDUMM)/120.d0
      END FUNCTION DF6

      attributes(host,device) FUNCTION FN1(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION FN1, XDUMM
      FN1=F0(XDUMM)
      FN1=FN1+F1(XDUMM)
      FN1=FN1+F2(XDUMM)
      FN1=FN1+F3(XDUMM)
      FN1=FN1+F4(XDUMM)
      FN1=FN1+F5(XDUMM)
      FN1=FN1+F6(XDUMM)
      END FUNCTION FN1

      attributes(host,device) FUNCTION DFN1(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION DFN1, XDUMM
      DFN1=DF0(XDUMM)
      DFN1=DFN1+DF1(XDUMM)
      DFN1=DFN1+DF2(XDUMM)
      DFN1=DFN1+DF3(XDUMM)
      DFN1=DFN1+DF4(XDUMM)
      DFN1=DFN1+DF5(XDUMM)
      DFN1=DFN1+DF6(XDUMM)
      END FUNCTION DFN1

      attributes(host,device) FUNCTION FN2(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION FN2, XDUMM
      FN2=F0(XDUMM)
      FN2=FN2+F1(XDUMM)
      FN2=FN2+F2(XDUMM)
      END FUNCTION FN2

      attributes(host,device) FUNCTION DFN2(XDUMM)
      IMPLICIT NONE
      DOUBLE PRECISION DFN2, XDUMM
      DFN2=DF0(XDUMM)
      DFN2=DFN2+DF1(XDUMM)
      DFN2=DFN2+DF2(XDUMM)
      END FUNCTION DFN2

C  treesum/kahansum: dos formas de sumar arr(1:n) con la MISMA interfaz
C  (array de entrada + n, devuelven la suma) -- para poder cambiar cual
C  se usa en ENERGY2 con una sola linea (ver USE_TREESUM mas abajo),
C  sin tocar el resto del codigo. Las dos evitan depender del orden
C  que elija el compilador para una acumulacion secuencial simple:
C
C  treesum: arbol binario por pares, orden de asociacion fijo (agrupa
C  de 2 en 2, luego los resultados de 2 en 2, etc.) -- CPU y GPU hacen
C  siempre los mismos pares en el mismo orden. work(natms) de tamano
C  fijo (misma cota que R2/G en He_dihydrogen), aunque solo entran
C  como mucho 2*N terminos con N=natoms de la simulacion real.
      attributes(host,device) FUNCTION treesum(arr, n)
      IMPLICIT NONE
      INCLUDE 'param_atoms_bh.h'
      INTEGER n, m, half, i
      DOUBLE PRECISION treesum, arr(n), work(2*natms)

       DO i=1,n
         work(i)=arr(i)
       ENDDO
       m=n
       DO WHILE (m.GT.1)
         half=m/2
         DO i=1,half
           work(i)=work(2*i-1)+work(2*i)
         ENDDO
         IF (MOD(m,2).EQ.1) THEN
           work(half+1)=work(m)
           half=half+1
         END IF
         m=half
       END DO
       treesum=work(1)
      END FUNCTION treesum

C  kahansum: suma compensada de Kahan de arr(1:n) -- la que ya se
C  probo y cerro 9/9 en docs-kernels/He_dihydrogen.md Parte 7.
      attributes(host,device) FUNCTION kahansum(arr, n)
      IMPLICIT NONE
      INTEGER n, i
      DOUBLE PRECISION kahansum, arr(n), c_k, y_k, t_k

       kahansum=0.d0
       c_k=0.d0
       DO i=1,n
         y_k=arr(i)-c_k
         t_k=kahansum+y_k
         c_k=(t_k-kahansum)-y_k
         kahansum=t_k
       ENDDO
      END FUNCTION kahansum

      attributes(host,device) SUBROUTINE He_dihydrogen (N, r_dih, rHH,
     &                          orHH, X, V, ENERGY1,
     &                          ENERGY2, ENERGY3, GTEST)
      use mVheheVphehe, only: V_hehe, Vp_hehe
      use angle_scalar_vec, only: angle, scalar_product, vec_norm
      use glibc_exp_mod, only: myexp
      use glibc_sincos_mod, only: mysin, mycos
      use glibc_pow_mod, only: mypow
      IMPLICIT NONE
      INCLUDE 'param_atoms_bh.h'
      INTEGER N, J, J1, J2, J3, J4
      LOGICAL GTEST
      DOUBLE PRECISION X(3*N), ENERGY1,ENERGY2,ENERGY3,
     1     V(3*N), R2(natms,natms), R,
     2     G(natms,natms), DUMMY,
     3     r_RGTH(3),V_RGTH,dVdx(3),
     4     rHH(3,nHH),orHH(3,nHH),
     7     cte,alpha,q,q0,r_dih(3,ndih),b,rvec(3),
     8     Ex0,Ey0,Ez0,E_total,rh1,rh2,rh3,r0,ror,
     9     dExdx,dEydx,dEzdx,dExdy,dEydy,dEzdy,
     &     dExdz,dEydz,dEzdz,dExtot,dEytot,dEztot,dFdr,dFdtheta,
     &     atheta,btheta,c6theta,rnorm,onorm,theta,dvdR,dvdtheta,
     &     datheta,dbtheta,dc6theta,drrdx(3),dthetadx(3),fi,dfidx(3),
     &     drh1dx,drh1dy,drh1dz,drh2dx,drh2dy,drh2dz,dr0dx,dr0dy,dr0dz,
     &     dbbbdx(3),eterm1,eterm2,e2terms(2*natms)
      LOGICAL USE_TREESUM
      PARAMETER (USE_TREESUM=.TRUE.)
C  USE_TREESUM=.TRUE.: ENERGY2 se suma con treesum (arbol binario,
C  orden de asociacion fijo). USE_TREESUM=.FALSE.: con kahansum (suma
C  compensada, la ya cerrada 9/9 en docs-kernels/He_dihydrogen.md
C  Parte 7). Cambiar aqui y recompilar para alternar entre las dos --
C  ver Parte 8 para la comparativa.
C      DOUBLE PRECISION a0,a1,a2,a3,b0,b1,b2,b3,c60,c61,c62,c63

C      common/refparam/a0,a1,a2,a3,b0,b1,b2,b3,c60,c61,c62,c63



********************************************************************************
C  F00...DFN2 ya no se definen aqui como funciones-sentencia locales:
C  son funciones de modulo (ver justo antes de He_dihydrogen), para
C  poder darle a FN1/DFN1/FN2/DFN2 acumulacion secuencial explicita.
********************************************************************************



      ENERGY1=0.d0
      DO J1=1,N-1
          G(J1,J1)=0.0D0
        DO J2=J1+1,N
          R2(J2,J1)=(X(3*(J1-1)+1)-X(3*(J2-1)+1))**2
     1             +(X(3*(J1-1)+2)-X(3*(J2-1)+2))**2
     2             +(X(3*(J1-1)+3)-X(3*(J2-1)+3))**2
          R2(J2,J1)=DSQRT(R2(J2,J1))
          R=R2(J2,J1)
          G(J2,J1)=Vp_hehe(R)/R
          G(J1,J2)=G(J2,J1)
          ENERGY1=ENERGY1+V_hehe(R)
         ENDDO
      ENDDO

      ENERGY1=ENERGY1*conve3   ! en meV

      IF (GTEST) THEN
      DO J1=1,3*N
       V(J1)=0.d0
      END DO
       DO J1=1,N
         DO J2=1,3
            J3=3*(J1-1)+J2
            DUMMY=0.0D0
            DO J4=1,N
               DUMMY=DUMMY+G(J4,J1)*(X(J3)-X(3*(J4-1)+J2))
            ENDDO
            V(J3)=DUMMY*conve3
         ENDDO
       ENDDO
      END IF


CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
CCCCCCCC    rep+disp TT    CCCCCCCCCCCC
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

      DO J1=1,N
       r_RGTH(1)=X(3*(J1-1)+1)
       r_RGTH(2)=X(3*(J1-1)+2)
       r_RGTH(3)=X(3*(J1-1)+3)
C       rvec(:)=r_RGTH(:)-rHH(:,1)
       rvec(:)=r_RGTH(:)
       call vec_norm(rvec,rnorm)
       call vec_norm(orHH(:,1),onorm)
       call angle (rvec,orHH(:,1),theta)
       call scalar_product(rvec,orHH(:,1),ror)
       fi=ror/(rnorm*onorm)
       drrdx(:)=rvec(:)/rnorm
       dfidx(:)=(orHH(:,1)*rnorm*onorm-ror*onorm*drrdx(:))
     &         /(rnorm*onorm)**2
       IF (fi.eq.1.d0) THEN
        dthetadx(:)=-dfidx(:)
       ELSE IF (fi.eq.-1.d0) THEN
        dthetadx(:)=dfidx(:)
       ELSE
        dthetadx(:)=-dfidx(:)/dsqrt(1.d0-fi**2)
       END IF


C  atheta/btheta/c6theta/rnorm**6: en el ORIGINAL (bh_heh2m.f) estos
C  **N usan exponente REAL (2.d0/3.d0/4.d0/5.d0/6.d0/7.d0), no entero
C  -- invocan pow() de verdad, no potencia entera. Se replican con
C  mypow (ya portado y validado bit a bit contra pow() real, ver
C  docs-kernels/glibc_math.md Parte 4), no con multiplicacion directa
C  (que replica potencia ENTERA, semantica distinta). mypow solo
C  soporta base>0 (nunca hizo falta la rama x<0 en usos anteriores,
C  donde la base siempre era rij, una distancia); mycos(theta)/
C  mysin(theta) SI pueden ser negativos, asi que se usa abs() (exacto
C  para exponente par: (-a)**2n=a**2n) y, en los exponentes impares
C  (3,5) de la rama GTEST, se reintroduce el signo con SIGN(1.d0,x).
C  Ver docs-kernels/He_dihydrogen.md Parte 8.
       atheta=a1*mypow(abs(mycos(theta)),2.0d0)
       atheta=atheta+a2*mypow(abs(mycos(theta)),4.0d0)
       atheta=atheta+a3*mypow(abs(mycos(theta)),6.0d0)
       btheta=b0
       btheta=btheta+b1*mypow(abs(mycos(theta)),2.0d0)
       btheta=btheta+b2*mypow(abs(mycos(theta)),4.0d0)
       btheta=btheta+b3*mypow(abs(mycos(theta)),6.0d0)
       c6theta=c60
       c6theta=c6theta+c61*mypow(abs(mysin(theta)),2.0d0)
       c6theta=c6theta+c62*mypow(abs(mysin(theta)),4.0d0)
       c6theta=c6theta+c63*mypow(abs(mysin(theta)),6.0d0)

       eterm1=a0*myexp(atheta-rnorm*btheta)
       eterm2=FN1(rnorm*btheta)*c6theta/mypow(rnorm,6.0d0)
C  eterm1/eterm2 de cada atomo se guardan en e2terms en vez de
C  acumularse aqui mismo -- la suma de verdad (treesum o kahansum,
C  ver USE_TREESUM arriba) se hace de una vez, despues del DO, sobre
C  los 2*N terminos completos. Ver docs-kernels/He_dihydrogen.md
C  Parte 7-8.
       e2terms(2*J1-1)=eterm1
       e2terms(2*J1)=-eterm2
       IF (GTEST) THEN
        datheta=-(2.d0*a1*(mycos(theta))+4.d0*a2*SIGN(1.d0,
     &            mycos(theta))*mypow(abs(mycos(theta)),3.0d0)
     &            +6.d0*a3*SIGN(1.d0,mycos(theta))
     &            *mypow(abs(mycos(theta)),5.0d0))*mysin(theta)
        dbtheta=-(2.d0*b1*(mycos(theta))+4.d0*b2*SIGN(1.d0,
     &            mycos(theta))*mypow(abs(mycos(theta)),3.0d0)
     &            +6.d0*b3*SIGN(1.d0,mycos(theta))
     &            *mypow(abs(mycos(theta)),5.0d0))*mysin(theta)
        dc6theta=(2.d0*c61*(mysin(theta))+4.d0*c62*SIGN(1.d0,
     &            mysin(theta))*mypow(abs(mysin(theta)),3.0d0)
     &            +6.d0*c63*SIGN(1.d0,mysin(theta))
     &            *mypow(abs(mysin(theta)),5.0d0))*mycos(theta)

        dvdR=a0*myexp(atheta-rnorm*btheta)*(-btheta)
     &      -DFN1(rnorm*btheta)*btheta*c6theta/mypow(rnorm,6.0d0)
     &      +6.d0*FN1(rnorm*btheta)*c6theta/mypow(rnorm,7.0d0)

        dvdtheta=a0*myexp(atheta-rnorm*btheta)*(datheta-rnorm*dbtheta)
     &          -DFN1(rnorm*btheta)*rnorm*dbtheta*c6theta
     &          /mypow(rnorm,6.0d0)
     &          -FN1(rnorm*btheta)*dc6theta/mypow(rnorm,6.0d0)

        dVdx(1)=dVdR*drrdx(1)+dvdtheta*dthetadx(1)
        dVdx(2)=dVdR*drrdx(2)+dvdtheta*dthetadx(2)
        dVdx(3)=dVdR*drrdx(3)+dvdtheta*dthetadx(3)


        V(3*(J1-1)+1)=V(3*(J1-1)+1)+dVdx(1)
        V(3*(J1-1)+2)=V(3*(J1-1)+2)+dVdx(2)
        V(3*(J1-1)+3)=V(3*(J1-1)+3)+dVdx(3)


C        WRITE (*,*) 'btheta,c6theta',btheta,c6theta
C        WRITE (*,*) 'dvdr,dvdtheta',dVdR,dvdtheta
C        WRITe (*,*) 'drdx,drdy,drdz',drrdx(1),drrdx(2),drrdx(3)
c        WRITE (*,*) 'dvdx1,dvdx2,dvdx3',dVdx(1),dVdx(2),dVdx(3)

       END IF

      END DO

      IF (USE_TREESUM) THEN
        ENERGY2=treesum(e2terms,2*N)
      ELSE
        ENERGY2=kahansum(e2terms,2*N)
      END IF

CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
CCCCCCCC     Induction term   CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

      ENERGY3=0.d0

      cte=14393.894d0 ! (meV)
      alpha=1.38d0*(0.5291772d0)**3
      q=0.7435d0
      q0=2.d0*q-1.d0



      DO j=1,N
       rh1=(x(3*(j-1)+1)-r_dih(1,1))**2+(x(3*(j-1)+2)-r_dih(2,1))**2+
     &     (x(3*(j-1)+3)-r_dih(3,1))**2
       rh1=DSQRT(rh1)

       rh2=(x(3*(j-1)+1)-r_dih(1,2))**2+(x(3*(j-1)+2)-r_dih(2,2))**2+
     &     (x(3*(j-1)+3)-r_dih(3,2))**2
       rh2=DSQRT(rh2)

       r0=(x(3*(j-1)+1))**2+(x(3*(j-1)+2))**2+
     &    (x(3*(j-1)+3))**2
       r0=DSQRT(r0)

       drh1dx=(x(3*(j-1)+1)-r_dih(1,1))/rh1
       drh1dy=(x(3*(j-1)+2)-r_dih(2,1))/rh1
       drh1dz=(x(3*(j-1)+3)-r_dih(3,1))/rh1

       drh2dx=(x(3*(j-1)+1)-r_dih(1,2))/rh2
       drh2dy=(x(3*(j-1)+2)-r_dih(2,2))/rh2
       drh2dz=(x(3*(j-1)+3)-r_dih(3,2))/rh2

       dr0dx=x(3*(j-1)+1)/r0
       dr0dy=x(3*(j-1)+2)/r0
       dr0dz=x(3*(j-1)+3)/r0


       r_RGTH(1)=x(3*(j-1)+1)
       r_RGTH(2)=x(3*(j-1)+2)
       r_RGTH(3)=x(3*(j-1)+3)
C       rvec(:)=r_RGTH(:)-rHH(:,1)
       rvec(:)=r_RGTH(:)
       call vec_norm(rvec,rnorm)
       call vec_norm(orHH(:,1),onorm)
       call angle (rvec,orHH(:,1),theta)
       call scalar_product(rvec,orHH(:,1),ror)
       fi=ror/(rnorm*onorm)
       drrdx(:)=rvec(:)/rnorm
       dfidx(:)=(orHH(:,1)*rnorm*onorm-ror*onorm*drrdx(:))
     &         /(rnorm*onorm)**2
       IF (fi.eq.1.d0) THEN
        dthetadx(:)=-dfidx(:)
       ELSE IF (fi.eq.-1.d0) THEN
        dthetadx(:)=dfidx(:)
       ELSE
        dthetadx(:)=-dfidx(:)/dsqrt(1.d0-fi**2)
       END IF

C  btheta: mismo motivo que en ENERGY2 -- exponente real en el
C  original, ver Parte 8. abs() por el mismo motivo (mycos puede
C  ser negativo, mypow solo soporta base>0).
       btheta=b0
       btheta=btheta+b1*mypow(abs(mycos(theta)),2.0d0)
       btheta=btheta+b2*mypow(abs(mycos(theta)),4.0d0)
       btheta=btheta+b3*mypow(abs(mycos(theta)),6.0d0)


       Ex0=q*FN2(btheta*rh1)*(x(3*(j-1)+1)-r_dih(1,1))/rh1**3
       Ex0=Ex0+q*FN2(btheta*rh2)*(x(3*(j-1)+1)-r_dih(1,2))/rh2**3
       Ex0=Ex0-q0*FN2(btheta*r0)*(x(3*(j-1)+1))/r0**3

       Ey0=q*FN2(btheta*rh1)*(x(3*(j-1)+2)-r_dih(2,1))/rh1**3
       Ey0=Ey0+q*FN2(btheta*rh2)*(x(3*(j-1)+2)-r_dih(2,2))/rh2**3
       Ey0=Ey0-q0*FN2(btheta*r0)*(x(3*(j-1)+2))/r0**3

       Ez0=q*FN2(btheta*rh1)*(x(3*(j-1)+3)-r_dih(3,1))/rh1**3
       Ez0=Ez0+q*FN2(btheta*rh2)*(x(3*(j-1)+3)-r_dih(3,2))/rh2**3
       Ez0=Ez0-q0*FN2(btheta*r0)*(x(3*(j-1)+3))/r0**3


       ENERGY3=ENERGY3+Ex0*Ex0
       ENERGY3=ENERGY3+Ey0*Ey0
       ENERGY3=ENERGY3+Ez0*Ez0

       IF (GTEST) THEN

       dbtheta=-(2.d0*b1*(mycos(theta))+4.d0*b2*SIGN(1.d0,
     &          mycos(theta))*mypow(abs(mycos(theta)),3.0d0)
     &          +6.d0*b3*SIGN(1.d0,mycos(theta))
     &          *mypow(abs(mycos(theta)),5.0d0))*mysin(theta)

       dbbbdx(:)=dbtheta*dthetadx(:)

       dExdx=q*DFN2(btheta*rh1)*(rh1*dbbbdx(1)+btheta*drh1dx)
     &            *(x(3*(j-1)+1)-r_dih(1,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(1.d0/rh1**3-3.d0
     &            *((x(3*(j-1)+1)-r_dih(1,1))**2)/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(1)+btheta*drh2dx)
     &            *(x(3*(j-1)+1)-r_dih(1,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(1.d0/rh2**3-3.d0
     &            *((x(3*(j-1)+1)-r_dih(1,2))**2)/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(1)+btheta*dr0dx)
     &            *(x(3*(j-1)+1))/r0**3-
     &        q0*FN2(btheta*r0)*(1.d0/r0**3-3.d0*((x(3*(j-1)+1))**2)
     &                          /r0**5)

        dExdy=q*DFN2(btheta*rh1)*(rh1*dbbbdx(2)+btheta*drh1dy)
     &             *(x(3*(j-1)+1)-r_dih(1,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(-3.d0*(x(3*(j-1)+1)-r_dih(1,1))
     &             *(x(3*(j-1)+2)-r_dih(2,1))/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(2)+btheta*drh2dy)
     &             *(x(3*(j-1)+1)-r_dih(1,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(-3.d0*(x(3*(j-1)+1)-r_dih(1,2))
     &             *(x(3*(j-1)+2)-r_dih(2,2))/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(2)+btheta*dr0dy)
     &             *(x(3*(j-1)+1))/r0**3-
     &        q0*FN2(btheta*r0)*(-3.d0*(x(3*(j-1)+1))*(x(3*(j-1)+2)))
     &             /r0**5

        dExdz=q*DFN2(btheta*rh1)*(rh1*dbbbdx(3)+btheta*drh1dz)
     &             *(x(3*(j-1)+1)-r_dih(1,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(-3.d0*(x(3*(j-1)+1)-r_dih(1,1))
     &             *(x(3*(j-1)+3)-r_dih(3,1))/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(3)+btheta*drh2dz)
     &             *(x(3*(j-1)+1)-r_dih(1,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(-3.d0*(x(3*(j-1)+1)-r_dih(1,2))
     &             *(x(3*(j-1)+3)-r_dih(3,2))/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(3)+btheta*dr0dz)
     &             *(x(3*(j-1)+1))/r0**3-
     &        q0*FN2(btheta*r0)*(-3.d0*(x(3*(j-1)+1))*(x(3*(j-1)+3)))
     &             /r0**5

        dEydx=q*DFN2(btheta*rh1)*(rh1*dbbbdx(1)+btheta*drh1dx)
     &                          *(x(3*(j-1)+2)-r_dih(2,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(-3.d0*(x(3*(j-1)+2)-r_dih(2,1))
     &                          *(x(3*(j-1)+1)-r_dih(1,1))/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(1)+btheta*drh2dx)
     &                          *(x(3*(j-1)+2)-r_dih(2,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(-3.d0*(x(3*(j-1)+2)-r_dih(2,2))
     &                          *(x(3*(j-1)+1)-r_dih(1,2))/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(1)+btheta*dr0dx)
     &                          *(x(3*(j-1)+2))/r0**3-
     &        q0*FN2(btheta*r0)*(-3.d0*(x(3*(j-1)+2))*(x(3*(j-1)+1)))
     &                          /r0**5

        dEydy=q*DFN2(btheta*rh1)*(rh1*dbbbdx(2)+btheta*drh1dy)
     &                          *(x(3*(j-1)+2)-r_dih(2,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(1.d0/rh1**3-3.d0
     &                         *((x(3*(j-1)+2)-r_dih(2,1))**2)/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(2)+btheta*drh2dy)
     &                          *(x(3*(j-1)+2)-r_dih(2,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(1.d0/rh2**3-3.d0
     &                         *((x(3*(j-1)+2)-r_dih(2,2))**2)/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(2)+btheta*dr0dy)
     &                         *(x(3*(j-1)+2))/r0**3-
     &        q0*FN2(btheta*r0)*(1.d0/r0**3-3.d0*((x(3*(j-1)+2))**2)
     &                          /r0**5)

        dEydz=q*DFN2(btheta*rh1)*(rh1*dbbbdx(3)+btheta*drh1dz)
     &                          *(x(3*(j-1)+2)-r_dih(2,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(-3.d0*(x(3*(j-1)+2)-r_dih(2,1))
     &                          *(x(3*(j-1)+3)-r_dih(3,1))/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(3)+btheta*drh2dz)
     &                          *(x(3*(j-1)+2)-r_dih(2,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(-3.d0*(x(3*(j-1)+2)-r_dih(2,2))
     &                          *(x(3*(j-1)+3)-r_dih(3,2))/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(3)+btheta*dr0dz)
     &                          *(x(3*(j-1)+2))/r0**3-
     &        q0*FN2(btheta*r0)*(-3.d0*(x(3*(j-1)+2))*(x(3*(j-1)+3)))
     &                          /r0**5

        dEzdx=q*DFN2(btheta*rh1)*(rh1*dbbbdx(1)+btheta*drh1dx)
     &                          *(x(3*(j-1)+3)-r_dih(3,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(-3.d0*(x(3*(j-1)+3)-r_dih(3,1))
     &                          *(x(3*(j-1)+1)-r_dih(1,1))/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(1)+btheta*drh2dx)
     &                          *(x(3*(j-1)+3)-r_dih(3,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(-3.d0*(x(3*(j-1)+3)-r_dih(3,2))
     &                          *(x(3*(j-1)+1)-r_dih(1,2))/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(1)+btheta*dr0dx)
     &                          *(x(3*(j-1)+3))/r0**3-
     &        q0*FN2(btheta*r0)*(-3.d0*(x(3*(j-1)+3))*(x(3*(j-1)+1)))
     &                          /r0**5


        dEzdy=q*DFN2(btheta*rh1)*(rh1*dbbbdx(2)+btheta*drh1dy)
     &                          *(x(3*(j-1)+3)-r_dih(3,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(-3.d0*(x(3*(j-1)+3)-r_dih(3,1))
     &                          *(x(3*(j-1)+2)-r_dih(2,1))/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(2)+btheta*drh2dy)
     &                          *(x(3*(j-1)+3)-r_dih(3,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(-3.d0*(x(3*(j-1)+3)-r_dih(3,2))
     &                          *(x(3*(j-1)+2)-r_dih(2,2))/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(2)+btheta*dr0dy)
     &                          *(x(3*(j-1)+3))/r0**3-
     &        q0*FN2(btheta*r0)*(-3.d0*(x(3*(j-1)+3))*(x(3*(j-1)+2)))
     &                          /r0**5

        dEzdz=q*DFN2(btheta*rh1)*(rh1*dbbbdx(3)+btheta*drh1dz)
     &                          *(x(3*(j-1)+3)-r_dih(3,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(1.d0/rh1**3-3.d0
     &                         *((x(3*(j-1)+3)-r_dih(3,1))**2)/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(3)+btheta*drh2dz)
     &                         *(x(3*(j-1)+3)-r_dih(3,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(1.d0/rh2**3-3.d0
     &                         *((x(3*(j-1)+3)-r_dih(3,2))**2)/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(3)+btheta*dr0dz)
     &                         *(x(3*(j-1)+3))/r0**3-
     &        q0*FN2(btheta*r0)*(1.d0/r0**3-3.d0*((x(3*(j-1)+3))**2)
     &                         /r0**5)


       dExtot=Ex0*dExdx+Ey0*dEydx+Ez0*dEzdx
       dEytot=Ex0*dExdy+Ey0*dEydy+Ez0*dEzdy
       dEztot=Ex0*dExdz+Ey0*dEydz+Ez0*dEzdz


       V(3*(J-1)+1)=V(3*(J-1)+1)-alpha*cte*dExtot
       V(3*(J-1)+2)=V(3*(J-1)+2)-alpha*cte*dEytot
       V(3*(J-1)+3)=V(3*(J-1)+3)-alpha*cte*dEztot

       END IF

      END DO

      ENERGY3=-0.5d0*alpha*cte*ENERGY3

      RETURN
      END SUBROUTINE He_dihydrogen
      end module mHe_dihydrogen
