module mhh_heocs

 implicit none
 integer, parameter, private :: i4=selected_int_kind(9)
 integer, parameter, private :: r8=selected_real_kind(15,9)

  real(kind=r8), parameter, private :: pi=3.1415926535897930_r8
  real(kind=r8), parameter, private :: ro=1.680290_r8
  real(kind=r8), parameter, private :: rs=1.037310_r8

  integer(kind=i4), parameter :: n19=19,n13=13,n10=10

  real(kind=r8), private, save :: ro2,rs2,romrs
  real(kind=r8), private, save :: alpha(n19,n13),x(n19),vx(n10),ax(n10)
  integer(kind=i4), private, save :: npl,npts,n_lam

contains

  function hh_vheocs(r,cth)      !r angstroms, hh_vheocs in cm-1
   real(kind=r8) :: hh_vheocs
   real(kind=r8), intent (in) :: r,cth
   real(kind=r8) :: r2
   real(kind=r8) :: ra,rb,rnw,cthnw
   real(kind=r8) :: pl2,eps_scal,r_scal,x_k
   real(kind=r8) :: pot,vpp
   integer(kind=i4) :: i_nlam,ipts
   double precision :: plm

    r2=r**2
    ra=sqrt(r2+rs2+2.0_r8*r*rs*cth)
    rb=sqrt(r2+ro2-2.0_r8*r*ro*cth)
    rnw=(ra+rb)/romrs
    cthnw=(ra-rb)/romrs

    pl2=0.50_r8*(3.0_r8*cthnw**2-1.0_r8)
    eps_scal=vx(1)+cthnw*vx(2)+pl2*vx(3)
    r_scal=rnw*(ax(1)+cthnw*ax(2)+pl2*ax(3))

    pot=0.0_r8
    do i_nlam=1,n_lam
      vpp=0.0_r8
      do ipts=1,npts
        x_k=x(ipts)
        vpp=vpp+alpha(ipts,i_nlam)*rad_kernel(x_k,r_scal)
      enddo
      pot=pot+vpp*plm(i_nlam-1,0,cthnw)
    enddo
    hh_vheocs=eps_scal*pot

  end function hh_vheocs

  function rad_kernel(x,r)
   real(kind=r8) :: rad_kernel
   real(kind=r8), intent (in) :: x,r
   real(kind=r8) :: x_l,x_s

    x_s=min(x,r)
    x_l=max(x,r)
 
    rad_kernel=1.0_r8/(14.0_r8*x_l**7)*(1.0_r8-7.0_r8*x_s/(9.0_r8*x_l))

  end function rad_kernel

  subroutine hh_leevheocs(fichpot)
   character*(*), intent (in) ::  fichpot
   integer(kind=i4) :: ipl,ipts,i_lam
   character(len=50) :: referencia

   ro2=ro**2
   rs2=rs**2
   romrs=ro+rs

   vx=0.0_r8
   ax=0.0_r8

   open(10,file=fichpot,status="old")

   read(10,*) npl
   do ipl=1,npl
     read(10,*) vx(ipl), ax(ipl)
   enddo

   read(10,*) npts, n_lam
   do i_lam=1,n_lam
     do ipts=1,npts
        read(10,*) x(ipts),alpha(ipts,i_lam)
     enddo
   enddo

   close(10)

   referencia="He-OCS Howson and Hutson,  JCP 115, 5059 (2001)"
   write(6,'("Referencia potencial ",t30,a)') trim(referencia)

  end subroutine hh_leevheocs

  subroutine sacahh(nplout,nptsout,n_lamout,alphaout,xout,vxout,axout)
    integer(kind=i4), intent (out) :: nplout,nptsout,n_lamout
    real(kind=r8), intent (out) :: alphaout(n19*n13),xout(n19),vxout(n10),axout(n10)
    integer(kind=i4) :: ipl,ipts,i_lam
    integer(kind=i4) :: ialpha

     nplout=npl
     nptsout=npts
     n_lamout=n_lam

     do ipl=1,n10
       vxout(ipl)=vx(ipl)
       axout(ipl)=ax(ipl)
     enddo

     do ipts=1,n19
       xout(ipts)=x(ipts)
     enddo

     ialpha=0
     do i_lam=1,n13
       do ipts=1,n19
         ialpha=ialpha+1
         alphaout(ialpha)=alpha(ipts,i_lam)
       enddo
     enddo

     ro2=ro**2
     rs2=rs**2
     romrs=ro+rs

  end subroutine sacahh

  subroutine metehh(nplin,nptsin,n_lamin,alphain,xin,vxin,axin)
    integer(kind=i4), intent (in) :: nplin,nptsin,n_lamin
    real(kind=r8), intent (in) :: alphain(n19*n13),xin(n19),vxin(n10),axin(n10)
    integer(kind=i4) :: ipl,ipts,i_lam
    integer(kind=i4) :: ialpha

     npl=nplin
     npts=nptsin
     n_lam=n_lamin

     do ipl=1,n10
       vx(ipl)=vxin(ipl)
       ax(ipl)=axin(ipl)
     enddo

     do ipts=1,n19
       x(ipts)=xin(ipts)
     enddo

     ialpha=0
     do i_lam=1,n13
       do ipts=1,n19
         ialpha=ialpha+1
         alpha(ipts,i_lam)=alphain(ialpha)
       enddo
     enddo

     ro2=ro**2
     rs2=rs**2
     romrs=ro+rs


  end subroutine metehh


end module mhh_heocs
