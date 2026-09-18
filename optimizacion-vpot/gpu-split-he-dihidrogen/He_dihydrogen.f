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
      use glibc_exp_mod, only: myexp
      IMPLICIT NONE
      DOUBLE PRECISION FN1, XDUMM, F00X
      F00X=myexp(-XDUMM)
      FN1=(1.d0-F00X)
      FN1=FN1+(-F00X*XDUMM)
      FN1=FN1+(-F00X*XDUMM**2/2.d0)
      FN1=FN1+(-F00X*XDUMM**3/6.d0)
      FN1=FN1+(-F00X*XDUMM**4/24.d0)
      FN1=FN1+(-F00X*XDUMM**5/120.d0)
      FN1=FN1+(-F00X*XDUMM**6/720.d0)
      END FUNCTION FN1

      attributes(host,device) FUNCTION DFN1(XDUMM)
      use glibc_exp_mod, only: myexp
      IMPLICIT NONE
      DOUBLE PRECISION DFN1, XDUMM, F00X
      F00X=myexp(-XDUMM)
      DFN1=F00X
      DFN1=DFN1+(F00X*XDUMM-F00X)
      DFN1=DFN1+(F00X*XDUMM**2/2.d0-XDUMM*F00X)
      DFN1=DFN1+(F00X*XDUMM**3/6.d0-XDUMM*XDUMM*F00X/2.d0)
      DFN1=DFN1+(F00X*XDUMM**4/24.d0-XDUMM*XDUMM*XDUMM*F00X/6.d0)
      DFN1=DFN1+(F00X*XDUMM**5/120.d0
     &          -XDUMM*XDUMM*XDUMM*XDUMM*F00X/24.d0)
      DFN1=DFN1+(F00X*XDUMM**6/720.d0
     &          -XDUMM*XDUMM*XDUMM*XDUMM*XDUMM*F00X/120.d0)
      END FUNCTION DFN1

      attributes(host,device) FUNCTION FN2(XDUMM)
      use glibc_exp_mod, only: myexp
      IMPLICIT NONE
      DOUBLE PRECISION FN2, XDUMM, F00X
      F00X=myexp(-XDUMM)
      FN2=(1.d0-F00X)
      FN2=FN2+(-F00X*XDUMM)
      FN2=FN2+(-F00X*XDUMM**2/2.d0)
      END FUNCTION FN2

      attributes(host,device) FUNCTION DFN2(XDUMM)
      use glibc_exp_mod, only: myexp
      IMPLICIT NONE
      DOUBLE PRECISION DFN2, XDUMM, F00X
      F00X=myexp(-XDUMM)
      DFN2=F00X
      DFN2=DFN2+(F00X*XDUMM-F00X)
      DFN2=DFN2+(F00X*XDUMM**2/2.d0-XDUMM*F00X)
      END FUNCTION DFN2

C  v3-cuda-optimizacion/optimizacion-vpot/split-he-dihidrogen: bloque de
C  dispersion (antes lineas 413-437 de He_dihydrogen) sacado a subrutina
C  hermana dentro del mismo modulo (para poder llamar a FN1 directamente
C  sin depender de otro modulo). Entradas theta/rnorm; salidas
C  eterm1/eterm2 (el resultado real) + coshi/coslo/sinhi/sinlo/normhi/
C  normlo/atheta/btheta/c6theta/norm6 (variables que He_dihydrogen sigue
C  necesitando mas abajo: btheta se usa SIN CONDICION en el termino de
C  induccion, el resto solo dentro de IF(GTEST), pero GTEST=.false. es
C  PARAMETER y el bloque igual tiene que compilar). cos2/cos4/cos6/sin2/
C  sin4/sin6 SI quedan puramente locales aqui, ya no se declaran en
C  He_dihydrogen. Ver split-he-dihidrogen.md para la hipotesis (motivada
C  por fusion-angle-hehe.md, donde INLINEAR subio registros 106->136 --
C  aqui se prueba el efecto inverso, EXTRAER).
!$pgi noinline
      attributes(host, device) SUBROUTINE termino_dispersion(theta,
     &     rnorm, eterm1, eterm2, coshi, coslo, sinhi, sinlo, normhi,
     &     normlo, atheta, btheta, c6theta, norm6)
      use glibc_exp_mod, only: myexp
      use glibc_sincos_mod, only: mysin, mycos
      use glibc_pow_mod, only: mypow_log, mypow_desde_log
      IMPLICIT NONE
      INCLUDE 'param_atoms_bh.h'
      DOUBLE PRECISION theta, rnorm, eterm1, eterm2
      DOUBLE PRECISION coshi, coslo, sinhi, sinlo
      DOUBLE PRECISION normhi, normlo, atheta, btheta, c6theta, norm6
      DOUBLE PRECISION cos2,cos4,cos6,sin2,sin4,sin6

       call mypow_log(abs(mycos(theta)), coshi, coslo)
       cos2=mypow_desde_log(coshi,coslo,2.0d0)
       cos4=mypow_desde_log(coshi,coslo,4.0d0)
       cos6=mypow_desde_log(coshi,coslo,6.0d0)
       call mypow_log(abs(mysin(theta)), sinhi, sinlo)
       sin2=mypow_desde_log(sinhi,sinlo,2.0d0)
       sin4=mypow_desde_log(sinhi,sinlo,4.0d0)
       sin6=mypow_desde_log(sinhi,sinlo,6.0d0)
       call mypow_log(rnorm, normhi, normlo)
       norm6=mypow_desde_log(normhi,normlo,6.0d0)

       atheta=a1*cos2
       atheta=atheta+a2*cos4
       atheta=atheta+a3*cos6
       btheta=b0
       btheta=btheta+b1*cos2
       btheta=btheta+b2*cos4
       btheta=btheta+b3*cos6
       c6theta=c60
       c6theta=c6theta+c61*sin2
       c6theta=c6theta+c62*sin4
       c6theta=c6theta+c63*sin6

       eterm1=a0*myexp(atheta-rnorm*btheta)
       eterm2=FN1(rnorm*btheta)*c6theta/norm6
      END SUBROUTINE termino_dispersion

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

C  v3-cuda-optimizacion/myexp-optimizacion: GTEST ya no es un argumento
C  -- el UNICO sitio real que llama a esta version (potenbh,
C  mpotenbh_mod.cuf) siempre pasaba GTEST=.false. (confirmado con
C  grep: "gtest.*=.*\.true\." no aparece en ningun sitio del arbol
C  vivo). GTEST no es un dato de entrada de la simulacion (como nhe3,
C  que SI puede variar segun in.mcv) -- es una decision de diseno fija
C  en el codigo, asi que se fija aqui como PARAMETER en vez de dejarla
C  como argumento en tiempo de ejecucion. Con GTEST como constante de
C  compilacion, el compilador puede demostrar que las 3 ramas
C  IF(GTEST) de mas abajo son inalcanzables y eliminarlas -- ya no
C  hace falta reservar registros para dvdR/dvdtheta/dExdx...dEzdz/
C  dbbbdx/etc, que antes se quedaban "vivas" solo porque el compilador
C  no podia demostrar en tiempo de compilacion que GTEST=.false.
C  siempre (era un argumento normal, no una constante). Si algun dia
C  hiciera falta el calculo de fuerzas, basta con cambiar este
C  PARAMETER a .true. y recompilar -- no hace falta mantener una
C  segunda copia de la rutina. Verificado bit a bit en
C  myexp-optimizacion.md antes de usarse aqui.
      attributes(host,device) SUBROUTINE He_dihydrogen (N, r_dih, rHH,
     &                          orHH, X, V, ENERGY1,
     &                          ENERGY2, ENERGY3)
      use mVheheVphehe, only: V_hehe, Vp_hehe, V_and_Vp_hehe
      use angle_scalar_vec, only: angle, scalar_product, vec_norm
      use glibc_exp_mod, only: myexp
      use glibc_sincos_mod, only: mysin, mycos
      use glibc_pow_mod, only: mypow_log, mypow_desde_log
      IMPLICIT NONE
      INCLUDE 'param_atoms_bh.h'
      INTEGER N, J, J1, J2, J3, J4
      LOGICAL, PARAMETER :: GTEST = .false.
      DOUBLE PRECISION X(3*N), ENERGY1,ENERGY2,ENERGY3,
     1     V(3*N), R2(natms,natms), R,
     2     G(natms,natms), DUMMY, v_tmp, vp_tmp,
     3     r_RGTH(3),dVdx(3),
     4     rHH(3,nHH),orHH(3,nHH),
     7     cte,alpha,q,q0,r_dih(3,ndih),rvec(3),
     8     Ex0,Ey0,Ez0,rh1,rh2,r0,ror,
     9     dExdx,dEydx,dEzdx,dExdy,dEydy,dEzdy,
     &     dExdz,dEydz,dEzdz,dExtot,dEytot,dEztot,
     &     atheta,btheta,c6theta,rnorm,onorm,theta,dvdR,dvdtheta,
     &     datheta,dbtheta,dc6theta,drrdx(3),dthetadx(3),fi,dfidx(3),
     &     drh1dx,drh1dy,drh1dz,drh2dx,drh2dy,drh2dz,dr0dx,dr0dy,dr0dz,
     &     dbbbdx(3),eterm1,eterm2,e2terms(2*natms)
C  v3-cuda-optimizacion/optimizacion-mypow: coshi/coslo, sinhi/sinlo,
C  normhi/normlo = log(base) de mycos(theta)/mysin(theta)/rnorm,
C  calculado UNA vez por atomo con mypow_log; cosN/sinN/normN son los
C  mypow_desde_log(base,N) que antes se recalculaban por separado en
C  el bloque de dispersion Y en el de induccion (ver mas abajo, ambos
C  bloques ahora fusionados en un solo DO). Verificado bit a bit contra
C  mypow(base,N) directo antes de usarse aqui (ver optimizacion-mypow.md).
      DOUBLE PRECISION coshi,coslo,cos3,cos5
      DOUBLE PRECISION sinhi,sinlo,sin3,sin5
      DOUBLE PRECISION normhi,normlo,norm6,norm7
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
          call V_and_Vp_hehe(R, v_tmp, vp_tmp)
          G(J2,J1)=vp_tmp/R
          G(J1,J2)=G(J2,J1)
          ENERGY1=ENERGY1+v_tmp
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
CCCCCCCC    rep+disp TT + Induction (FUSIONADOS)  CCCCCCCC
C  v3-cuda-optimizacion/optimizacion-mypow: el bloque de dispersion
C  (antiguo "rep+disp TT") y el de induccion (antiguo "Induction term",
C  mas abajo en el original) recorrian los DOS el mismo rango de
C  atomos 1..N y calculaban, cada uno por su cuenta, el mismo
C  rvec/rnorm/onorm/theta (mismo X, mismo orHH, mismo indice de atomo)
C  y el mismo btheta/dbtheta (misma formula, mismo theta). Se fusionan
C  aqui en un unico DO J1=1,N: el bloque de dispersion se queda igual
C  (mismo orden de calculo), y el de induccion, justo despues dentro
C  de la MISMA iteracion, reutiliza rvec/rnorm/onorm/theta/btheta/
C  dbtheta ya calculados en vez de recalcularlos. ENERGY2 se sigue
C  rellenando por asignacion en e2terms (no depende del orden de
C  calculo) y el treesum/kahansum se sigue haciendo una sola vez, al
C  final, sobre el array completo. ENERGY3 y V(:) se siguen acumulando
C  exactamente en el mismo orden de atomos 1..N que antes -- ningun
C  otro atomo toca el mismo elemento de V entre medias, asi que
C  fusionar el bucle no reordena ninguna suma en coma flotante.
C  Verificado bit a bit contra la version sin fusionar (ver
C  optimizacion-mypow.md, seccion He_dihydrogen) antes de usarse aqui.
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

      ENERGY3=0.d0
      cte=14393.894d0 ! (meV)
      alpha=1.38d0*(0.5291772d0)**3
      q=0.7435d0
      q0=2.d0*q-1.d0

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
C  v3-cuda-optimizacion/optimizacion-mypow: mypow_log(base) una vez y
C  mypow_desde_log(base,N) por exponente -- cos2/cos4/cos6 se calculan
C  aqui UNA vez y se usan tanto en atheta como en btheta (antes cada
C  una llamaba a mypow por separado con el mismo (base,exponente)).
       call termino_dispersion(theta, rnorm, eterm1, eterm2, coshi,
     &     coslo, sinhi, sinlo, normhi, normlo, atheta, btheta,
     &     c6theta, norm6)
C  eterm1/eterm2 de cada atomo se guardan en e2terms en vez de
C  acumularse aqui mismo -- la suma de verdad (treesum o kahansum,
C  ver USE_TREESUM arriba) se hace de una vez, despues del DO, sobre
C  los 2*N terminos completos. Ver docs-kernels/He_dihydrogen.md
C  Parte 7-8.
       e2terms(2*J1-1)=eterm1
       e2terms(2*J1)=-eterm2
       IF (GTEST) THEN
        cos3=mypow_desde_log(coshi,coslo,3.0d0)
        cos5=mypow_desde_log(coshi,coslo,5.0d0)
        sin3=mypow_desde_log(sinhi,sinlo,3.0d0)
        sin5=mypow_desde_log(sinhi,sinlo,5.0d0)
        norm7=mypow_desde_log(normhi,normlo,7.0d0)

        datheta=-(2.d0*a1*(mycos(theta))+4.d0*a2*SIGN(1.d0,
     &            mycos(theta))*cos3
     &            +6.d0*a3*SIGN(1.d0,mycos(theta))
     &            *cos5)*mysin(theta)
        dbtheta=-(2.d0*b1*(mycos(theta))+4.d0*b2*SIGN(1.d0,
     &            mycos(theta))*cos3
     &            +6.d0*b3*SIGN(1.d0,mycos(theta))
     &            *cos5)*mysin(theta)
        dc6theta=(2.d0*c61*(mysin(theta))+4.d0*c62*SIGN(1.d0,
     &            mysin(theta))*sin3
     &            +6.d0*c63*SIGN(1.d0,mysin(theta))
     &            *sin5)*mycos(theta)

        dvdR=a0*myexp(atheta-rnorm*btheta)*(-btheta)
     &      -DFN1(rnorm*btheta)*btheta*c6theta/norm6
     &      +6.d0*FN1(rnorm*btheta)*c6theta/norm7

        dvdtheta=a0*myexp(atheta-rnorm*btheta)*(datheta-rnorm*dbtheta)
     &          -DFN1(rnorm*btheta)*rnorm*dbtheta*c6theta
     &          /norm6
     &          -FN1(rnorm*btheta)*dc6theta/norm6

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

C  v3-cuda-optimizacion/optimizacion-mypow: aqui empieza lo que antes
C  era el bloque "Induction term" (segundo DO j=1,N separado, mas
C  abajo en el original) -- fusionado en esta misma iteracion J1.
C  rvec/rnorm/onorm/theta/btheta/dbtheta NO se recalculan: son los
C  mismos valores ya calculados arriba para este mismo atomo (mismo X,
C  mismo orHH, misma formula -- verificado bit a bit). dbtheta solo
C  hace falta si GTEST, y en ese caso ya se calculo unas lineas mas
C  arriba, dentro del mismo IF(GTEST) de dispersion (los dos bloques
C  comparten el mismo GTEST, no hay desincronizacion posible).
       rh1=(X(3*(J1-1)+1)-r_dih(1,1))**2+(X(3*(J1-1)+2)-r_dih(2,1))**2+
     &     (X(3*(J1-1)+3)-r_dih(3,1))**2
       rh1=DSQRT(rh1)

       rh2=(X(3*(J1-1)+1)-r_dih(1,2))**2+(X(3*(J1-1)+2)-r_dih(2,2))**2+
     &     (X(3*(J1-1)+3)-r_dih(3,2))**2
       rh2=DSQRT(rh2)

       r0=(X(3*(J1-1)+1))**2+(X(3*(J1-1)+2))**2+
     &    (X(3*(J1-1)+3))**2
       r0=DSQRT(r0)

       drh1dx=(X(3*(J1-1)+1)-r_dih(1,1))/rh1
       drh1dy=(X(3*(J1-1)+2)-r_dih(2,1))/rh1
       drh1dz=(X(3*(J1-1)+3)-r_dih(3,1))/rh1

       drh2dx=(X(3*(J1-1)+1)-r_dih(1,2))/rh2
       drh2dy=(X(3*(J1-1)+2)-r_dih(2,2))/rh2
       drh2dz=(X(3*(J1-1)+3)-r_dih(3,2))/rh2

       dr0dx=X(3*(J1-1)+1)/r0
       dr0dy=X(3*(J1-1)+2)/r0
       dr0dz=X(3*(J1-1)+3)/r0

       Ex0=q*FN2(btheta*rh1)*(X(3*(J1-1)+1)-r_dih(1,1))/rh1**3
       Ex0=Ex0+q*FN2(btheta*rh2)*(X(3*(J1-1)+1)-r_dih(1,2))/rh2**3
       Ex0=Ex0-q0*FN2(btheta*r0)*(X(3*(J1-1)+1))/r0**3

       Ey0=q*FN2(btheta*rh1)*(X(3*(J1-1)+2)-r_dih(2,1))/rh1**3
       Ey0=Ey0+q*FN2(btheta*rh2)*(X(3*(J1-1)+2)-r_dih(2,2))/rh2**3
       Ey0=Ey0-q0*FN2(btheta*r0)*(X(3*(J1-1)+2))/r0**3

       Ez0=q*FN2(btheta*rh1)*(X(3*(J1-1)+3)-r_dih(3,1))/rh1**3
       Ez0=Ez0+q*FN2(btheta*rh2)*(X(3*(J1-1)+3)-r_dih(3,2))/rh2**3
       Ez0=Ez0-q0*FN2(btheta*r0)*(X(3*(J1-1)+3))/r0**3


       ENERGY3=ENERGY3+Ex0*Ex0
       ENERGY3=ENERGY3+Ey0*Ey0
       ENERGY3=ENERGY3+Ez0*Ez0

       IF (GTEST) THEN

       dbbbdx(:)=dbtheta*dthetadx(:)

       dExdx=q*DFN2(btheta*rh1)*(rh1*dbbbdx(1)+btheta*drh1dx)
     &            *(X(3*(J1-1)+1)-r_dih(1,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(1.d0/rh1**3-3.d0
     &            *((X(3*(J1-1)+1)-r_dih(1,1))**2)/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(1)+btheta*drh2dx)
     &            *(X(3*(J1-1)+1)-r_dih(1,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(1.d0/rh2**3-3.d0
     &            *((X(3*(J1-1)+1)-r_dih(1,2))**2)/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(1)+btheta*dr0dx)
     &            *(X(3*(J1-1)+1))/r0**3-
     &        q0*FN2(btheta*r0)*(1.d0/r0**3-3.d0*((X(3*(J1-1)+1))**2)
     &                          /r0**5)

        dExdy=q*DFN2(btheta*rh1)*(rh1*dbbbdx(2)+btheta*drh1dy)
     &             *(X(3*(J1-1)+1)-r_dih(1,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(-3.d0*(X(3*(J1-1)+1)-r_dih(1,1))
     &             *(X(3*(J1-1)+2)-r_dih(2,1))/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(2)+btheta*drh2dy)
     &             *(X(3*(J1-1)+1)-r_dih(1,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(-3.d0*(X(3*(J1-1)+1)-r_dih(1,2))
     &             *(X(3*(J1-1)+2)-r_dih(2,2))/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(2)+btheta*dr0dy)
     &             *(X(3*(J1-1)+1))/r0**3-
     &        q0*FN2(btheta*r0)*(-3.d0*(X(3*(J1-1)+1))*(X(3*(J1-1)+2)))
     &             /r0**5

        dExdz=q*DFN2(btheta*rh1)*(rh1*dbbbdx(3)+btheta*drh1dz)
     &             *(X(3*(J1-1)+1)-r_dih(1,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(-3.d0*(X(3*(J1-1)+1)-r_dih(1,1))
     &             *(X(3*(J1-1)+3)-r_dih(3,1))/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(3)+btheta*drh2dz)
     &             *(X(3*(J1-1)+1)-r_dih(1,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(-3.d0*(X(3*(J1-1)+1)-r_dih(1,2))
     &             *(X(3*(J1-1)+3)-r_dih(3,2))/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(3)+btheta*dr0dz)
     &             *(X(3*(J1-1)+1))/r0**3-
     &        q0*FN2(btheta*r0)*(-3.d0*(X(3*(J1-1)+1))*(X(3*(J1-1)+3)))
     &             /r0**5

        dEydx=q*DFN2(btheta*rh1)*(rh1*dbbbdx(1)+btheta*drh1dx)
     &                          *(X(3*(J1-1)+2)-r_dih(2,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(-3.d0*(X(3*(J1-1)+2)-r_dih(2,1))
     &                          *(X(3*(J1-1)+1)-r_dih(1,1))/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(1)+btheta*drh2dx)
     &                          *(X(3*(J1-1)+2)-r_dih(2,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(-3.d0*(X(3*(J1-1)+2)-r_dih(2,2))
     &                          *(X(3*(J1-1)+1)-r_dih(1,2))/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(1)+btheta*dr0dx)
     &                          *(X(3*(J1-1)+2))/r0**3-
     &        q0*FN2(btheta*r0)*(-3.d0*(X(3*(J1-1)+2))*(X(3*(J1-1)+1)))
     &                          /r0**5

        dEydy=q*DFN2(btheta*rh1)*(rh1*dbbbdx(2)+btheta*drh1dy)
     &                          *(X(3*(J1-1)+2)-r_dih(2,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(1.d0/rh1**3-3.d0
     &                         *((X(3*(J1-1)+2)-r_dih(2,1))**2)/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(2)+btheta*drh2dy)
     &                          *(X(3*(J1-1)+2)-r_dih(2,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(1.d0/rh2**3-3.d0
     &                         *((X(3*(J1-1)+2)-r_dih(2,2))**2)/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(2)+btheta*dr0dy)
     &                         *(X(3*(J1-1)+2))/r0**3-
     &        q0*FN2(btheta*r0)*(1.d0/r0**3-3.d0*((X(3*(J1-1)+2))**2)
     &                          /r0**5)

        dEydz=q*DFN2(btheta*rh1)*(rh1*dbbbdx(3)+btheta*drh1dz)
     &                          *(X(3*(J1-1)+2)-r_dih(2,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(-3.d0*(X(3*(J1-1)+2)-r_dih(2,1))
     &                          *(X(3*(J1-1)+3)-r_dih(3,1))/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(3)+btheta*drh2dz)
     &                          *(X(3*(J1-1)+2)-r_dih(2,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(-3.d0*(X(3*(J1-1)+2)-r_dih(2,2))
     &                          *(X(3*(J1-1)+3)-r_dih(3,2))/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(3)+btheta*dr0dz)
     &                          *(X(3*(J1-1)+2))/r0**3-
     &        q0*FN2(btheta*r0)*(-3.d0*(X(3*(J1-1)+2))*(X(3*(J1-1)+3)))
     &                          /r0**5

        dEzdx=q*DFN2(btheta*rh1)*(rh1*dbbbdx(1)+btheta*drh1dx)
     &                          *(X(3*(J1-1)+3)-r_dih(3,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(-3.d0*(X(3*(J1-1)+3)-r_dih(3,1))
     &                          *(X(3*(J1-1)+1)-r_dih(1,1))/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(1)+btheta*drh2dx)
     &                          *(X(3*(J1-1)+3)-r_dih(3,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(-3.d0*(X(3*(J1-1)+3)-r_dih(3,2))
     &                          *(X(3*(J1-1)+1)-r_dih(1,2))/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(1)+btheta*dr0dx)
     &                          *(X(3*(J1-1)+3))/r0**3-
     &        q0*FN2(btheta*r0)*(-3.d0*(X(3*(J1-1)+3))*(X(3*(J1-1)+1)))
     &                          /r0**5


        dEzdy=q*DFN2(btheta*rh1)*(rh1*dbbbdx(2)+btheta*drh1dy)
     &                          *(X(3*(J1-1)+3)-r_dih(3,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(-3.d0*(X(3*(J1-1)+3)-r_dih(3,1))
     &                          *(X(3*(J1-1)+2)-r_dih(2,1))/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(2)+btheta*drh2dy)
     &                          *(X(3*(J1-1)+3)-r_dih(3,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(-3.d0*(X(3*(J1-1)+3)-r_dih(3,2))
     &                          *(X(3*(J1-1)+2)-r_dih(2,2))/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(2)+btheta*dr0dy)
     &                          *(X(3*(J1-1)+3))/r0**3-
     &        q0*FN2(btheta*r0)*(-3.d0*(X(3*(J1-1)+3))*(X(3*(J1-1)+2)))
     &                          /r0**5

        dEzdz=q*DFN2(btheta*rh1)*(rh1*dbbbdx(3)+btheta*drh1dz)
     &                          *(X(3*(J1-1)+3)-r_dih(3,1))/rh1**3+
     &        q*FN2(btheta*rh1)*(1.d0/rh1**3-3.d0
     &                         *((X(3*(J1-1)+3)-r_dih(3,1))**2)/rh1**5)+
     &        q*DFN2(btheta*rh2)*(rh2*dbbbdx(3)+btheta*drh2dz)
     &                         *(X(3*(J1-1)+3)-r_dih(3,2))/rh2**3+
     &        q*FN2(btheta*rh2)*(1.d0/rh2**3-3.d0
     &                         *((X(3*(J1-1)+3)-r_dih(3,2))**2)/rh2**5)-
     &        q0*DFN2(btheta*r0)*(r0*dbbbdx(3)+btheta*dr0dz)
     &                         *(X(3*(J1-1)+3))/r0**3-
     &        q0*FN2(btheta*r0)*(1.d0/r0**3-3.d0*((X(3*(J1-1)+3))**2)
     &                         /r0**5)


       dExtot=Ex0*dExdx+Ey0*dEydx+Ez0*dEzdx
       dEytot=Ex0*dExdy+Ey0*dEydy+Ez0*dEzdy
       dEztot=Ex0*dExdz+Ey0*dEydz+Ez0*dEzdz


       V(3*(J1-1)+1)=V(3*(J1-1)+1)-alpha*cte*dExtot
       V(3*(J1-1)+2)=V(3*(J1-1)+2)-alpha*cte*dEytot
       V(3*(J1-1)+3)=V(3*(J1-1)+3)-alpha*cte*dEztot

       END IF

      END DO

      IF (USE_TREESUM) THEN
        ENERGY2=treesum(e2terms,2*N)
      ELSE
        ENERGY2=kahansum(e2terms,2*N)
      END IF

      ENERGY3=-0.5d0*alpha*cte*ENERGY3

      RETURN
      END SUBROUTINE He_dihydrogen
      end module mHe_dihydrogen
