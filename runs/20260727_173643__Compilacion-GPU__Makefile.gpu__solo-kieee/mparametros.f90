module mparametros

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: i8=selected_int_kind(15)
 integer, private, parameter :: r8=selected_real_kind(15,9)

  real(kind=r8), public, parameter :: pi=3.1415926535897930_r8
  real(kind=r8), public, parameter :: cluz=299792458.0_r8  ! m/s
  real(kind=r8), public, parameter :: rbohr=0.529177210670_r8
  real(kind=r8), public, parameter :: kb=8.6173324d-5      !kboltzmann en eV/K
  real(kind=r8), public, parameter :: hbc=197.32697180_r8  !hbarra*c en MeV*fm
  real(kind=r8), public, parameter :: umac2=931.494061_r8  !uma*c**2 en MeV
  real(kind=r8), public, parameter :: hb2=hbc**2/(2.0_r8*umac2)*1.d-4/kb 
                                      !hb**2/(2m) en K*A*uma
  real(kind=r8), public, parameter :: hb2cm=hbc**2/(2.0_r8*umac2)/(2.0_r8*pi*hbc)*1.d3
  real(kind=r8), public, parameter :: cmtok=2.0_r8*pi*hbc*1.d-7/kb !cm en K

  real(kind=r8), public, parameter :: k2cm_bh=0.6950_r8                  ! 1 K en cm-1
  real(kind=r8), public, parameter :: cm2h_bh=4.556335380d-6             ! 1cm-1 en hartree
  real(kind=r8), public, parameter :: h2mev_bh=27.20d3                   ! 1 hartree en meV
  real(kind=r8), public, parameter :: k2mev_bh=k2cm_bh*cm2h_bh*h2mev_bh  !K en meV

  integer(kind=i4), public, parameter, dimension(0:8) :: nnup=(/0,1,1,2,3,4,4,4,4/)
  integer(kind=i4), public, parameter, dimension(0:8) :: nndw=(/0,0,1,1,1,1,2,3,4/)
  integer(kind=i4), public, parameter :: namolmax=4

  real(kind=r8), public, parameter :: ratio=1.0d-7
  real(kind=r8), public, parameter :: grande=1.0d5

  logical, public :: datosbien
  logical, public :: libre
  logical, public :: impurfija,rotamol
  real(kind=r8), public :: mhe4,mhe3
  integer(kind=i4), public :: nhe4,nhe3
  integer(kind=i4), public :: namol
  real(kind=r8), public :: hb2he4,hb2he3
  integer(kind=i4), public :: opot
  character(len=100), public :: fichpot
  integer(kind=i4), public :: ngatom,natom,ncmtras
  real(kind=r8), public :: mx,momi
  real(kind=r8), public :: hb2x,brot
  real(kind=r8), public :: cintr(3,namolmax)
  character(len=16), public :: nombre
  logical :: impureza,impurmol

  integer(kind=i8), public :: irncal
  integer(kind=i4), public :: opcion
  logical, public :: enermin
  real(kind=r8), public :: deltahe4,deltahe3
  real(kind=r8), public :: deltax,deltaa
  real(kind=r8), public :: etrial,dtau
  integer(kind=i4), public :: nblockeq
  integer(kind=i4), public :: npasosdc
  integer(kind=i4), public :: nblock,npasos
  integer(kind=i4), public :: nwalkers
  integer(kind=i4), public :: ncetrial
  integer(kind=i4), public :: nhe3up,nhe3dw
  integer(kind=i4), public, parameter :: nfermax=20

  real(kind=r8), public :: bhe4,dbhe4
  real(kind=r8), public :: nuhe4,dnuhe4
  real(kind=r8), public :: alfahe4,dalfahe4
  real(kind=r8), public :: bhe3,dbhe3
  real(kind=r8), public :: nuhe3,dnuhe3
  real(kind=r8), public :: alfahe3,dalfahe3
  real(kind=r8), public :: bback,dbback
  real(kind=r8), public :: bmix,dbmix
  real(kind=r8), public :: numix,dnumix
  real(kind=r8), public :: alfamix,dalfamix
  real(kind=r8), public :: phe4(3),phe3(4),pmix(3)
  integer(kind=i4), public :: lxhe4,lxhe3
  integer(kind=i4), public, parameter :: lmax=20
  real(kind=r8), public :: bxhe4(0:lmax),dbxhe4(0:lmax)
  real(kind=r8), public :: nuxhe4(0:lmax),dnuxhe4(0:lmax)
  real(kind=r8), public :: alfaxhe4(0:lmax),dalfaxhe4(0:lmax)
  real(kind=r8), public :: p4xhe4(0:lmax),dp4xhe4(0:lmax)
  real(kind=r8), public :: p5xhe4(0:lmax),dp5xhe4(0:lmax)
  real(kind=r8), public :: bxhe3(0:lmax),dbxhe3(0:lmax)
  real(kind=r8), public :: nuxhe3(0:lmax),dnuxhe3(0:lmax)
  real(kind=r8), public :: alfaxhe3(0:lmax),dalfaxhe3(0:lmax)
  real(kind=r8), public :: p4xhe3(0:lmax),dp4xhe3(0:lmax)
  real(kind=r8), public :: p5xhe3(0:lmax),dp5xhe3(0:lmax)
  real(kind=r8), public :: pxhe4(5,0:lmax),pxhe3(5,0:lmax)

  integer(kind=i4), public :: ncadapvm

end module mparametros
