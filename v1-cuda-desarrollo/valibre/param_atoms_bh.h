      INTEGER natms,ndih,nHH,najust,n_simul,maxiter,mup,n_minima
      REAL*8 a0,a1,a2,a3,b0,b1,b2,b3,c60,c61,c62,c63
      REAL*8 convr,conve,autoEv,convm,conve2,conve3
      REAL*8 hbar,kB,pi,pi12
      REAL*8 mO,mH,mCl,m4He,m3He,mCs
      REAL*8 A_HeHe,c6_HeHe,c8_HeHe,c10_HeHe
      REAL*8 gp_HeHe,gp2_HeHe 
      REAL*8 alpha_HeHe,beta_HeHe,D_HeHe,req_HeHe,eps_HeHe
      REAL*8 Aa_HeHe,xx1_HeHe,xx2_HeHe,Ba_HeHe
      PARAMETER (ndih=2,nHH=1)
!      PARAMETER (a0=79482.86920d0,a1=-0.31785d0,a2=4.12121d0,a3=0.67320d0)
!      PARAMETER (b0=3.71492d0,b1=0.20404d0,b2=1.56688d0,b3=0.63928d0)
!      PARAMETER (c60=3259.90728d0,c61=183.97076d0,c62=-69.55693d0,c63=-188.77855d0)
       PARAMETER (a0=65344.8145d0,a1= -0.42497d0,a2=3.95634d0,
     &            a3=0.07852d0)
      PARAMETER (b0=3.49361d0,b1=0.13908d0,b2=1.89258d0,b3=-0.01065d0)
      PARAMETER (c60=4091.45747d0,c61=106.89633d0,c62=226.68798d0,
     &           c63=-117.37656d0)
      PARAMETER (convr=0.5291772d0,conve=4.55633538d-6,
     &           autoeV=27.2113957d0)
      PARAMETER (convm=1822.88853d0,conve2=627.5095d0,conve3=27.2d3)
      PARAMETER (hbar=1.d0,kB=0.695d0*conve,pi=3.141592d0,pi12=pi/2.d0)
      PARAMETER (mO=16.0d0*convm,mH=1.0d0*1.0078250321*convm,
     &           mCl=34.96885*convm)
      PARAMETER (m4He=4.00260324d0*convm,m3He=3.0160374d0*convm,
     &           mCs=132.9054519d0*convm)
      PARAMETER (A_HeHe=1.89635353d5,c6_HeHe=1.34687065d0,
     &           c8_HeHe=0.41308398d0)
      PARAMETER (c10_HeHe=0.17060159d0,gp_HeHe=1.d0,gp2_HeHe=1.d0)
      PARAMETER (alpha_HeHe=10.70203539d0*gp_HeHe,
     &           beta_HeHe =-1.90740649D0*gp_HeHe)
      PARAMETER (D_HeHe=1.4088D0*gp2_HeHe,req_HeHe=2.9695d0,
     &           eps_HeHe=10.97d0*kB)
      PARAMETER (Aa_HeHe=0.0026d0,xx1_HeHe=1.003535949d0,
     &           xx2_HeHe=1.454790369d0)
      PARAMETER (Ba_HeHe=2.d0*pi/(xx2_HeHe-xx1_HeHe))
      PARAMETER (najust=100,n_simul=4)
      PARAMETER (mup=7,maxiter=1000,n_minima=50000)
      PARAMETER (natms=30)
!
    ! ----------------------------------------------------------------------
!   ! Conversion factors:
!   ! Input   Units (E:cm-1, M:uma, L:Angstrom, T:s  )
!   ! Working Units (E:a.u., M:me,  L:bohr    , T:atu)
!   double precision, parameter :: convr=0.5291772d0     ! 1 a.u.    = 0.5291772d0 Amstrongs
!   double precision, parameter :: conve=4.55633538d-6   ! 1 cm-1    = 4.55633538d-6 a.u.
!   double precision, parameter :: autoeV=27.2113957d0
!   double precision, parameter :: convm=1822.88853d0    ! 1 uma     = 1822.88853d0 me
!   double precision, parameter :: conve2=627.5095       ! 1 Hartree = 627.5095 Kcal/mol
!   double precision, parameter :: conve3=27.2107d3       ! 1 Hartree = 27.2107d3 meV
!
!   ! Physical constants
!   double precision, parameter :: hbar=1.d0      ! E.a.u. * t.a.u.
!   double precision, parameter :: kB=0.695*conve ! E.a.u./Kelvin
!
!   ! Masses:
!   double precision, parameter :: mO=16.0d0*convm
!   double precision, parameter :: mH=1.0d0*1.0078250321*convm
!   double precision, parameter :: mCl=34.96885*convm
!   double precision, parameter :: m4He=4.00260324d0*convm   ! (4He)
!   double precision, parameter :: m3He=3.0160374d0*convm    ! (3He)
!   double precision, parameter :: mCs=132.9054519d0*convm
!
!! He-He (LM2M2) potential parameters -------------------------------------------
!
!      ! Aziz and Slaman: JCP 94(12) 8047 (1991)
!            double precision, parameter :: A_HeHe  = 1.89635353d5
!            double precision, parameter :: c6_HeHe = 1.34687065d0
!            double precision, parameter :: c8_HeHe = 0.41308398d0
!            double precision, parameter :: c10_HeHe= 0.17060159d0
!            ! gp y gp2 son parametros que ha metido Pablo para modificar el potencial:
!            ! En el articulo original de Aziz, ambos valen 1:
!            ! double precision, parameter :: gp_HeHe=1.014d0
!            ! double precision, parameter :: gp2_HeHe=1.048d0
!            double precision, parameter :: gp_HeHe=1.d0
!            double precision, parameter :: gp2_HeHe=1.d0
!            double precision, parameter :: alpha_HeHe=10.70203539d0*gp_HeHe
!            double precision, parameter :: beta_HeHe =-1.90740649D0*gp_HeHe
!            double precision, parameter :: D_HeHe=1.4088D0*gp2_HeHe
!!            double precision, parameter :: req_HeHe=2.9695d0/convr
!            double precision, parameter :: req_HeHe=2.9695d0
!            double precision, parameter :: eps_HeHe= 10.97d0 * kB
!
!            ! Add-in portions:
!            double precision, parameter :: Aa_HeHe  = 0.0026d0
!            double precision, parameter :: xx1_HeHe = 1.003535949d0
!            double precision, parameter :: xx2_HeHe = 1.454790369d0
!            double precision, parameter :: Ba_HeHe  = 2.d0*pi/(xx2_HeHe-xx1_HeHe)
!      ! ----------------------------------------------------------------------
