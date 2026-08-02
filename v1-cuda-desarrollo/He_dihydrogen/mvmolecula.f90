module mvmolecula

 use mhh_heocs
 use mkp_heco

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: r8=selected_real_kind(15,9)

 contains

  function vatomol(opot,cunid,r,cth)
   real(kind=r8) :: vatomol
   integer(kind=i4), intent (in) :: opot
   real(kind=r8), intent (in) ::  cunid
   real(kind=r8), intent (in) :: r,cth
   real(kind=r8), parameter :: rmin=2.0_r8
   integer(kind=i4), parameter :: nv=1
   real*8 :: v(nv),rv(nv),cthv(nv)

    select case (opot)

     case (1)  
      rv(1)=max(r,rmin)
      cthv(1)=cth
      call pw_vheocs(rv,cthv,v,nv)
      vatomol=cunid*v(1)

     case (2)
      vatomol=cunid*hh_vheocs(r,cth)

     case (3)
      vatomol=cunid*hecokp2d(r,cth)

    end select

  end function vatomol

 end module mvmolecula
