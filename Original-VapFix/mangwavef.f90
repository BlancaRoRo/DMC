module mangwavef

 use mparametros
 use mtipos
 use mlegendre

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: r8=selected_real_kind(15,9)

contains

 subroutine duhe4x(rivec,smol,d1ux,d2ux,d1zux,d2zux)
  type(vec3), intent (in) :: rivec,smol(3)
  type(vec3), intent (out) :: d1ux
  real(kind=r8), intent (out) :: d2ux
  real(kind=r8), intent (out) :: d1zux(2),d2zux
  type(vec3) :: grz,grpl,grul
  real(kind=r8) :: rij,cth,zpr,grz2,lapz
  real(kind=r8) :: gpz(2),lpz,gpz2
  real(kind=r8) :: ulx,ulxp,ulxs,lapl
  real(kind=r8) :: rijp2,rijp4
  real(kind=r8) :: pl(0:lxhe4),d1pl(0:lxhe4),d2pl(0:lxhe4)
  integer(kind=i4) :: il

   rij=sqrt(dot_product(rivec%comp,rivec%comp))
   if(impurmol) then
     cth=dot_product(rivec%comp,smol(3)%comp)/rij
     zpr=cth/rij
     grz%comp=(smol(3)%comp-zpr*rivec%comp)/rij
     grz2=dot_product(grz%comp,grz%comp)
     lapz=-2.0_r8*zpr/rij
     gpz(1)=-dot_product(rivec%comp,smol(2)%comp)/rij
     gpz(2)= dot_product(rivec%comp,smol(1)%comp)/rij
     gpz2=dot_product(gpz,gpz)
     lpz=-cth-cth
   else
     cth=0.0_r8
     grz=0.0_r8
     grz2=0.0_r8
     lapz=0.0_r8
     gpz=0.0_r8
     lpz=0.0_r8
   endif
   call calderpleg(lxhe4,cth,pl,d1pl,d2pl)
   do il=1,lxhe4
     pl(il)=1.0_r8-pl(il)
     d1pl(il)=-d1pl(il)
     d2pl(il)=-d2pl(il)
   enddo

   d1ux%comp=0.0_r8
   d2ux=0.0_r8
   d1zux=0.0_r8
   d2zux=0.0_r8
   do il=0,lxhe4
     rijp2=rij**pxhe4(2,il)
     rijp4=rij**pxhe4(4,il)
     ulx=  -pxhe4(1,il)/rijp2                                   &
 &         -pxhe4(3,il)*rijp4-pxhe4(5,il)*log(rij)
     ulxp=( pxhe4(1,il)*pxhe4(2,il)/rijp2                       &
 &         -pxhe4(3,il)*pxhe4(4,il)*rijp4-pxhe4(5,il))/rij                
     ulxs=(-pxhe4(1,il)*pxhe4(2,il)*(pxhe4(2,il)+1.0_r8)/rijp2  &
 &         -pxhe4(3,il)*pxhe4(4,il)*(pxhe4(4,il)-1.0_r8)*rijp4  &
 &         +pxhe4(5,il))/rij**2
     ulxs=ulxs+2.0_r8*ulxp/rij
     grul%comp=ulxp/rij*rivec%comp
     grpl%comp=d1pl(il)*grz%comp
     lapl=lapz*d1pl(il)+grz2*d2pl(il)
     d1ux%comp=d1ux%comp+pl(il)*grul%comp+ulx*grpl%comp
     d2ux=d2ux+pl(il)*ulxs+ulx*lapl+2.0_r8*dot_product(grul%comp,grpl%comp)
     d1zux(:)=d1zux(:)+ulx*d1pl(il)*gpz(:)
     d2zux=d2zux+ulx*(d1pl(il)*lpz+d2pl(il)*gpz2)
   enddo

 end subroutine duhe4x

 subroutine duhe3x(rivec,smol,d1ux,d2ux,d1zux,d2zux)
  type(vec3), intent (in) :: rivec,smol(3)
  type(vec3), intent (out) :: d1ux
  real(kind=r8), intent (out) :: d2ux
  real(kind=r8), intent (out) :: d1zux(2),d2zux
  type(vec3) :: grz,grpl,grul
  real(kind=r8) :: rij,cth,zpr,grz2,lapz
  real(kind=r8) :: gpz(2),lpz,gpz2
  real(kind=r8) :: rijp2,rijp4
  real(kind=r8) :: ulx,ulxp,ulxs,lapl
  real(kind=r8) :: pl(0:lxhe3),d1pl(0:lxhe3),d2pl(0:lxhe3)
  integer(kind=i4) :: il

   rij=sqrt(dot_product(rivec%comp,rivec%comp))
   if(impurmol) then
     cth=dot_product(rivec%comp,smol(3)%comp)/rij
     zpr=cth/rij
     grz%comp=(smol(3)%comp-zpr*rivec%comp)/rij
     grz2=dot_product(grz%comp,grz%comp)
     lapz=-2.0_r8*zpr/rij
     gpz(1)=-dot_product(rivec%comp,smol(2)%comp)/rij
     gpz(2)= dot_product(rivec%comp,smol(1)%comp)/rij
     gpz2=dot_product(gpz,gpz)
     lpz=-cth-cth
   else
     cth=0.0_r8
     grz=0.0_r8
     grz2=0.0_r8
     lapz=0.0_r8
     gpz=0.0_r8
     lpz=0.0_r8
   endif

   call calderpleg(lxhe3,cth,pl,d1pl,d2pl)
   do il=1,lxhe3
     pl(il)=1.0_r8-pl(il)
     d1pl(il)=-d1pl(il)
     d2pl(il)=-d2pl(il)
   enddo

   d1ux%comp=0.0_r8
   d2ux=0.0_r8
   d1zux=0.0_r8
   d2zux=0.0_r8
   do il=0,lxhe3
!    ulx=-pxhe3(1,il)/rij**pxhe3(2,il)-pxhe3(3,il)*rij
!    ulxp=pxhe3(1,il)*pxhe3(2,il)/rij**(pxhe3(2,il)+1)-pxhe3(3,il)
!    ulxs=-pxhe3(1,il)*pxhe3(2,il)*(pxhe3(2,il)+1.0_r8)/rij**(pxhe3(2,il)+2)
     rijp2=rij**pxhe3(2,il)
     rijp4=rij**pxhe3(4,il)
     ulx=  -pxhe3(1,il)/rijp2                                   &
 &         -pxhe3(3,il)*rijp4-pxhe3(5,il)*log(rij)
     ulxp=( pxhe3(1,il)*pxhe3(2,il)/rijp2                       &
 &         -pxhe3(3,il)*pxhe3(4,il)*rijp4-pxhe3(5,il))/rij                
     ulxs=(-pxhe3(1,il)*pxhe3(2,il)*(pxhe3(2,il)+1.0_r8)/rijp2  &
 &         -pxhe3(3,il)*pxhe3(4,il)*(pxhe3(4,il)-1.0_r8)*rijp4  &
 &         +pxhe3(5,il))/rij**2
     ulxs=ulxs+2.0_r8*ulxp/rij
     grul%comp=ulxp/rij*rivec%comp
     grpl%comp=d1pl(il)*grz%comp
     lapl=lapz*d1pl(il)+grz2*d2pl(il)
     d1ux%comp=d1ux%comp+pl(il)*grul%comp+ulx*grpl%comp
     d2ux=d2ux+pl(il)*ulxs+ulx*lapl+2.0_r8*dot_product(grul%comp,grpl%comp)
     d1zux(:)=d1zux(:)+ulx*d1pl(il)*gpz(:)
     d2zux=d2zux+ulx*(d1pl(il)*lpz+d2pl(il)*gpz2)
   enddo

 end subroutine duhe3x

 function uhe4x(rij,cth)
  real(kind=r8) :: uhe4x
  real(kind=r8), intent (in) :: rij,cth
  real(kind=r8) :: pl(0:lxhe4)
  real(kind=r8) :: ul
  integer(kind=i4) :: il

   call calpleg(lxhe4,cth,pl)
   do il=1,lxhe4
     pl(il)=1.0_r8-pl(il)
   enddo

   uhe4x=0.0_r8
   do il=0,lxhe4
     ul=-pxhe4(1,il)/rij**pxhe4(2,il)-pxhe4(3,il)*rij**pxhe4(4,il)  &
 &      -pxhe4(5,il)*log(rij)
     uhe4x=uhe4x+ul*pl(il)
   enddo


 end function uhe4x

 function uhe3x(rij,cth)
  real(kind=r8) :: uhe3x
  real(kind=r8), intent (in) :: rij,cth
  real(kind=r8) :: pl(0:lxhe3)
  real(kind=r8) :: ul
  integer(kind=i4) :: il

   call calpleg(lxhe3,cth,pl)
   do il=1,lxhe3
     pl(il)=1.0_r8-pl(il)
   enddo

   uhe3x=0.0_r8
   do il=0,lxhe3
     ul=-pxhe3(1,il)/rij**pxhe3(2,il)-pxhe3(3,il)*rij**pxhe3(4,il)  &
 &      -pxhe3(5,il)*log(rij)
     uhe3x=uhe3x+ul*pl(il)
   enddo

 end function uhe3x

end module mangwavef
