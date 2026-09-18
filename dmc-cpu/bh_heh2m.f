      subroutine potenbh(nhe4,xhe4,vpotbh)
      implicit none
      integer nhe4
      real*8  xhe4(3*nhe4),ejemol(3),vpotbh
      integer ndih,nHH
      parameter (ndih=2,nHH=1)
      real*8  r_dih(3,ndih)
      real*8  rHH(3,nHH), orHH(3,nHH)
      real*8  vhe4(3*nhe4)
      real*8 energy1,energy2,energy3,vtot
      real*8 dhcm
      real*8 dcont,zav,zor
      integer iHatom,jHatom,icontHH
      logical :: test
      common / datosbh / dhcm

       r_dih=0.0d0
       r_dih(3,1)= dhcm
       r_dih(3,2)=-dhcm
       rHH=0.d0
       orHH=0.d0
       orHH(3,1)=-2*dhcm
          
       test=.false.
       call He_dihydrogen(nhe4,r_dih,rHH,orHH,xhe4,vhe4,ENERGY1,
     >                    ENERGY2,ENERGY3,TEST)
       vpotbh=(energy1+energy2+energy3)


      end subroutine potenbh

      subroutine bh_leevheh2m(fichpot)
      implicit real*8(a-h,o-z)
!     character*(*)  fichpot
      character (len=100)  fichpot
      common / datosbh / dhcm
      character(len=50) :: referencia

        open(unit=10,file=fichpot,status="old")
        read (10,*) dhcm
        close(10)

        referencia="He-H2+ Breton et al. Preprint 2023"
        write(6,'("Referencia potencial ",t30,a)') trim(referencia)

      return
      end subroutine bh_leevheh2m

      subroutine sacabh(dhcmout)
      implicit real*8(a-h,o-z)
      common / datosbh / dhcm

       dhcmout=dhcm
   
      return 
      end subroutine sacabh

      subroutine metebh(dhcmin)
      implicit real*8(a-h,o-z)
      common /  datosbh / dhcm

       dhcm=dhcmin

      return
      end subroutine metebh
c
C*************************************************************************
C
C  Subroutine He_dihydrogen calculates the cartesian 
C  gradient derivative matrix analytically. 
C
C*************************************************************************
C
      SUBROUTINE He_dihydrogen (N, r_dih, rHH, orHH, X, V, ENERGY1, 
     &                          ENERGY2, ENERGY3, GTEST)
      IMPLICIT NONE
      INCLUDE 'param_atoms_bh.h'
      INTEGER N, J, J1, J2, J3, J4
      LOGICAL GTEST
      DOUBLE PRECISION X(3*N), ENERGY1,ENERGY2,ENERGY3,
     1     V(3*N), R2(N,N), R,
     2     G(N,N), DUMMY,V_hehe,Vp_hehe,
     3     r_RGTH(3),V_RGTH,dVdx(3),
     4     rHH(3,nHH),orHH(3,nHH),
     5     F00,F0,F1,F2,F3,F4,F5,F6,FN1,xdumm,
     6     DF0,DF1,DF2,DF3,DF4,DF5,DF6,DFN1,FN2,DFN2,
     7     cte,alpha,q,q0,r_dih(3,ndih),b,rvec(3),
     8     Ex0,Ey0,Ez0,E_total,rh1,rh2,rh3,r0,ror,
     9     dExdx,dEydx,dEzdx,dExdy,dEydy,dEzdy,
     &     dExdz,dEydz,dEzdz,dExtot,dEytot,dEztot,dFdr,dFdtheta,
     &     atheta,btheta,c6theta,rnorm,onorm,theta,dvdR,dvdtheta,
     &     datheta,dbtheta,dc6theta,drrdx(3),dthetadx(3),fi,dfidx(3),
     &     drh1dx,drh1dy,drh1dz,drh2dx,drh2dy,drh2dz,dr0dx,dr0dy,dr0dz,
     &     dbbbdx(3)
C      DOUBLE PRECISION a0,a1,a2,a3,b0,b1,b2,b3,c60,c61,c62,c63

C      common/refparam/a0,a1,a2,a3,b0,b1,b2,b3,c60,c61,c62,c63



********************************************************************************
C  damping functions and their derivatives

      F00(XDUMM)=dexp(-XDUMM)
      F0(XDUMM)=1.d0-F00(XDUMM)
      DF0(XDUMM)=F00(XDUMM)
      F1(XDUMM)=-F00(XDUMM)*XDUMM
      DF1(XDUMM)=DF0(XDUMM)*XDUMM-F00(XDUMM)
      F2(XDUMM)=-F00(XDUMM)*(XDUMM)**2/2.d0
      DF2(XDUMM)=DF0(XDUMM)*(XDUMM)**2/2.d0-XDUMM*F00(XDUMM)
      F3(XDUMM)=-F00(XDUMM)*(XDUMM)**3/6.d0
      DF3(XDUMM)=DF0(XDUMM)*(XDUMM)**3/6.d0-XDUMM*XDUMM*F00(XDUMM)/2.d0
      F4(XDUMM)=-F00(XDUMM)*(XDUMM)**4/24.d0
      DF4(XDUMM)=DF0(XDUMM)*(XDUMM)**4/24.d0
     &           -XDUMM*XDUMM*XDUMM*F00(XDUMM)/6.d0
      F5(XDUMM)=-F00(XDUMM)*(XDUMM)**5/120.d0
      DF5(XDUMM)=DF0(XDUMM)*(XDUMM)**5/120.d0
     &           -XDUMM*XDUMM*XDUMM*XDUMM*F00(XDUMM)/24.d0
      F6(XDUMM)=-F00(XDUMM)*(XDUMM)**6/720.d0
      DF6(XDUMM)=DF0(XDUMM)*(XDUMM)**6/720.d0
     &           -XDUMM*XDUMM*XDUMM*XDUMM*XDUMM*F00(XDUMM)/120.d0

      FN1(XDUMM)=F0(XDUMM)+F1(XDUMM)+F2(XDUMM)+F3(XDUMM)+
     &           F4(XDUMM)+F5(XDUMM)+F6(XDUMM)
      DFN1(XDUMM)=DF0(XDUMM)+DF1(XDUMM)+DF2(XDUMM)+DF3(XDUMM)+
     &            DF4(XDUMM)+DF5(XDUMM)+DF6(XDUMM)
      FN2(XDUMM)=F0(XDUMM)+F1(XDUMM)+F2(XDUMM)
      DFN2(XDUMM)=DF0(XDUMM)+DF1(XDUMM)+DF2(XDUMM)

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

      ENERGY2=0.d0
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


       atheta=a1*(dcos(theta))**2.d0+a2*(dcos(theta))**4.d0+
     &        a3*(dcos(theta))**6.d0
       btheta=b0+b1*(dcos(theta))**2.d0+b2*(dcos(theta))**4.d0+
     &        b3*(dcos(theta))**6.d0
       c6theta=c60+c61*(dsin(theta))**2.d0+c62*(dsin(theta))**4.d0+
     &        c63*(dsin(theta))**6.d0

       ENERGY2=ENERGY2+a0*dexp(atheta-rnorm*btheta)
     &         -FN1(rnorm*btheta)*c6theta/rnorm**6.d0
       IF (GTEST) THEN
        datheta=-(2.d0*a1*(dcos(theta))+4.d0*a2*(dcos(theta))**3.d0+
     &            6.d0*a3*(dcos(theta))**5.d0)*dsin(theta)
        dbtheta=-(2.d0*b1*(dcos(theta))+4.d0*b2*(dcos(theta))**3.d0+
     &            6.d0*b3*(dcos(theta))**5.d0)*dsin(theta)
        dc6theta=(2.d0*c61*(dsin(theta))+4.d0*c62*(dsin(theta))**3.d0+
     &            6.d0*c63*(dsin(theta))**5.d0)*dcos(theta)

        dvdR=a0*dexp(atheta-rnorm*btheta)*(-btheta)
     &      -DFN1(rnorm*btheta)*btheta*c6theta/rnorm**6.d0
     &      +6.d0*FN1(rnorm*btheta)*c6theta/rnorm**7.d0

        dvdtheta=a0*dexp(atheta-rnorm*btheta)*(datheta-rnorm*dbtheta)
     &          -DFN1(rnorm*btheta)*rnorm*dbtheta*c6theta/rnorm**6.d0
     &          -FN1(rnorm*btheta)*dc6theta/rnorm**6.d0

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

       btheta=b0+b1*(dcos(theta))**2.d0+b2*(dcos(theta))**4.d0+
     &        b3*(dcos(theta))**6.d0


       Ex0=q*FN2(btheta*rh1)*(x(3*(j-1)+1)-r_dih(1,1))/rh1**3+
     &     q*FN2(btheta*rh2)*(x(3*(j-1)+1)-r_dih(1,2))/rh2**3-
     &     q0*FN2(btheta*r0)*(x(3*(j-1)+1))/r0**3

       Ey0=q*FN2(btheta*rh1)*(x(3*(j-1)+2)-r_dih(2,1))/rh1**3+
     &     q*FN2(btheta*rh2)*(x(3*(j-1)+2)-r_dih(2,2))/rh2**3-
     &     q0*FN2(btheta*r0)*(x(3*(j-1)+2))/r0**3

       Ez0=q*FN2(btheta*rh1)*(x(3*(j-1)+3)-r_dih(3,1))/rh1**3+
     &     q*FN2(btheta*rh2)*(x(3*(j-1)+3)-r_dih(3,2))/rh2**3-
     &     q0*FN2(btheta*r0)*(x(3*(j-1)+3))/r0**3


       ENERGY3=ENERGY3+Ex0*Ex0+Ey0*Ey0+Ez0*Ez0

       IF (GTEST) THEN

       dbtheta=-(2.d0*b1*(dcos(theta))+4.d0*b2*(dcos(theta))**3.d0+
     &         6.d0*b3*(dcos(theta))**5.d0)*dsin(theta)

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
      END

! He-He potential (LM2M2), Aziz and Slaman: JCP 94(12) 8047 (1991)
! function V_hehe(r)
! function Vp_hehe(r)

      function V_hehe(r)
         ! He-He LM2LM2 potential
         ! Aziz and Slaman: JCP 94(12) 8047 (1991)
         implicit none
      INCLUDE 'param_atoms_bh.h'
         double precision, intent(in) :: r ! (in bohr)
         double precision :: V_hehe        ! (in Hartrees)
         double precision :: x, x2, x6, x8, x10, F, sum, addin
C         x  = r/req_HeHe/convr
         x  = r/req_HeHe
         x2 = x*x
         x6 = x2*x2*x2
         x8 = x6*x2
         x10= x8*x2
         F = 1.d0
         if(x < D_HeHe) F=dexp(-(D_HeHe/x-1.d0)**2)
         sum = c6_HeHe/x6 + c8_HeHe/x8 + c10_HeHe/x10
         sum = A_HeHe*dexp(-alpha_HeHe*x + beta_HeHe*x2) - F*sum
         ! ADD-IN PORTIONS:
         addin=0.d0
         if (x >= xx1_HeHe .and. x <=xx2_HeHe) then
            addin = Aa_HeHe*(dsin( Ba_HeHe*(x-xx1_HeHe)-pi12)+1.d0)
         end if
         !addin=0.d0
         V_hehe = sum + addin
         V_hehe = eps_HeHe * V_hehe
         ! V_hehe = V_hehe/kB
         ! warning: Potential 10 times bigger
         !V_hehe = V_hehe *10.d0
      end function V_hehe

      function Vp_hehe(r)
         ! He-He LM2LM2 potential derivative
         ! Aziz and Slaman: JCP 94(12) 8047 (1991)
         implicit none
      INCLUDE 'param_atoms_bh.h'
         double precision :: r, x, x2, x3, x6, x7, x8, x9, x10, x11,
     &                       F, Fp, sum1, sum2
         double precision :: Vp, Vap, Vbp, Vp_hehe
C         x  = r/req_HeHe/convr
         x  = r/req_HeHe
         x2 = x*x
         x3 = x2*x
         x6 = x3*x3
         x7 = x6*x
         x8 = x6*x2
         x9 = x8*x
         x10= x8*x2
         x11= x10*x
         F  = 1.d0
         Fp = 0.d0
         if(x < D_HeHe) then
            F =dexp(-(D_HeHe/x-1.d0)**2)
            Fp=2.d0*(D_HeHe/x-1.d0)*(D_HeHe/x2) * F
         end if

         sum1 = c6_HeHe/x6 + c8_HeHe/x8 + c10_HeHe/x10
         sum2 = 6.d0*c6_HeHe/x7 + 8.d0*c8_HeHe/x9 + 10.d0*c10_HeHe/x11
         Vbp = A_HeHe*(-alpha_HeHe+2.d0*beta_HeHe*x)
     &         *dexp(-alpha_HeHe*x + beta_HeHe*x2) - Fp*sum1 + F*sum2

         ! ADD-IN PORTIONS:
C  FIX (v1-cuda-desarrollo): Vap no se inicializaba fuera de la
C  ventana [xx1_HeHe,xx2_HeHe], quedando en memoria sin inicializar
C  (ver docs-kernels/V_hehe_Vp_hehe.md Sec.5). Se recupera la
C  intencion original que sugiere el "!Vap=0.d0" comentado justo
C  debajo, sin tocar ninguna otra formula.
         Vap = 0.d0
         if (x >= xx1_HeHe .and. x <=xx2_HeHe) then
            Vap = Aa_HeHe * Ba_HeHe* dcos(Ba_HeHe*(x-xx1_HeHe)-pi12)
         end if

         Vp_hehe = (eps_HeHe/req_HeHe) * (Vap+Vbp)
         !Vp_hehe = Vp_hehe * conve
         !Vp_hehe = Vp_hehe/kB

      end function Vp_hehe

      subroutine angle(vec1,vec2,ang)
      ! Angle between vectors 'vec1' and 'vec2'
      implicit none
      double precision, intent(in)  :: vec1(3), vec2(3)
      double precision, intent(out) :: ang
      integer :: id
      double precision :: x1,x2,sprod,norm1,norm2
      sprod=0.d0
      norm1=0.d0
      norm2=0.d0
      do id=1,3
         x1=vec1(id)
         x2=vec2(id)
         sprod=sprod+x1*x2
         norm1=norm1+x1*x1
         norm2=norm2+x2*x2
      end do
      norm1=dsqrt(norm1)
      norm2=dsqrt(norm2)
      ang=dacos(sprod/(norm1*norm2))
      end subroutine angle

      subroutine scalar_product(vec1,vec2,sprod)
      ! Scalar product of two vectors
      double precision, intent(in)  :: vec1(3), vec2(3)
      double precision, intent(out) :: sprod
      integer :: id
      sprod=0.d0
      do id=1,3
         sprod=sprod+vec1(id)*vec2(id)
      end do
      end subroutine scalar_product

      subroutine vec_norm(vec,xnorm)
      ! Norm of a vector
      double precision, intent(in)  :: vec(3)
      double precision, intent(out) :: xnorm
      integer :: id
      xnorm=0.d0
      do id=1,3
         xnorm=xnorm+vec(id)*vec(id)
      end do
         xnorm=dsqrt(xnorm)
      end subroutine vec_norm


      subroutine normalize(vec)
      double precision, intent(inout)  :: vec(3)
      double precision :: xnorm
      integer :: id
      xnorm=0.d0
      do id=1,3
         xnorm=xnorm+vec(id)*vec(id)
      end do
      vec=vec/dsqrt(xnorm)
      end subroutine normalize

      subroutine vectorial_product(vec1,vec2,vec3)
      double precision, intent(in)  :: vec1(3), vec2(3)
      double precision, intent(out) :: vec3(3)
      double precision :: x1,y1,z1,x2,y2,z2
      x1=vec1(1)
      y1=vec1(2)
      z1=vec1(3)
      x2=vec2(1)
      y2=vec2(2)
      z2=vec2(3)
      vec3(1)=y1*z2-y2*z1
      vec3(2)=x2*z1-x1*z2
      vec3(3)=x1*y2-x2*y1
      end subroutine vectorial_product

      subroutine dihedral_angle(vec1,vec2,vec3,gam)
      ! Angle formed by planes (vec1,vec2) and (vec2,vec3)
      double precision, intent(in)  :: vec1(:), vec2(:), vec3(:)
      double precision, intent(out) :: gam
      double precision :: v1(3),v2(3),v3(3),u1(3),u2(3)
      v1=vec1
      v2=vec2
      v3=vec3
      call normalize(v1)
      call normalize(v2)
      call normalize(v3)
      call vectorial_product(v1,v2,u1)
      call vectorial_product(v2,v3,u2)
      call scalar_product(u1,u2,gam)
      end subroutine dihedral_angle
