module mtipos

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: i8=8
 integer, private, parameter :: r8=selected_real_kind(15,9)
 ! r16 eliminado: selected_real_kind(30) devuelve -1 en nvfortran (no soporta quad)
 integer, private, parameter :: r16=r8

 type :: vec3
   real (kind=r8) :: comp(3)
 end type

 type :: vloc
   real(kind=r8) :: wf
   real(kind=r8) :: wfhe4,wfhe3,wfm,wfx
   real(kind=r8) :: kin,pot,ene,erot,eimp
   integer(kind=i4) :: signoup,signodw
 end type

 type :: walker
   type (vloc) :: lw
   type (vec3), allocatable :: atom(:),dwf(:)
   real (kind=r8), allocatable :: delta(:),hb2m(:),sigma1(:),sigma2(:)
   type (vec3) :: sprop(3)
   real (kind=r8) :: dangle,b,sig1rot,sig2rot,sig1hrot,sig2hrot
   real (kind=r8) :: dphi(2)
   type (vec3) :: eje0,pos0
 end type

 interface assignment (=)
   module procedure inicivec3
   module procedure copiavec3
   module procedure copialoc
   module procedure copiawalker
 end interface

 interface operator (+)
   module procedure sumavec3
 end interface

 interface operator (-)
   module procedure restavec3
 end interface

 interface operator (*)
   module procedure escporvec3
   module procedure vec3poresc
   module procedure prodvec
 end interface

 contains

  function escporvec3(x,v2) result (v1)
   real(kind=r8), intent (in) :: x
   type(vec3), intent (in) :: v2
   type(vec3) :: v1

    v1%comp=x*v2%comp

  end function escporvec3

  function vec3poresc(v2,x) result (v1)
   real(kind=r8), intent (in) :: x
   type(vec3), intent (in) :: v2
   type(vec3) :: v1

    v1%comp=v2%comp*x

  end function vec3poresc

  function prodvec(v2,v3) result (v1)
   type(vec3), intent (in) :: v2,v3
   type(vec3) :: v1

   v1%comp(1)=v2%comp(2)*v3%comp(3)-v2%comp(3)*v3%comp(2)
   v1%comp(2)=v2%comp(3)*v3%comp(1)-v2%comp(1)*v3%comp(3)
   v1%comp(3)=v2%comp(1)*v3%comp(2)-v2%comp(2)*v3%comp(1)


  end function prodvec

  function restavec3(v2,v3) result (v1)
   type(vec3), intent (in) :: v2,v3
   type(vec3) :: v1

    v1%comp=v2%comp-v3%comp

  end function restavec3

  function sumavec3(v2,v3) result (v1)
   type(vec3), intent (in) :: v2,v3
   type(vec3) :: v1

    v1%comp=v2%comp+v3%comp

  end function sumavec3

  subroutine inicivec3(v1,e)
   real(kind=r8), intent (in) :: e
   type(vec3), intent (out) :: v1

     v1%comp=e

  end subroutine inicivec3

  subroutine copiavec3(v1,v2)
   type (vec3), intent (out) :: v1
   type (vec3), intent (in) :: v2

    v1%comp=v2%comp

  end subroutine copiavec3

  subroutine copialoc(l1,l2)
    type (vloc), intent (out) :: l1
    type (vloc), intent (in) :: l2

      l1%wf   =l2%wf
      l1%wfhe4=l2%wfhe4
      l1%wfhe3=l2%wfhe3
      l1%wfm  =l2%wfm
      l1%wfx  =l2%wfx
      l1%kin  =l2%kin
      l1%pot  =l2%pot
      l1%ene  =l2%ene
      l1%erot  =l2%erot
      l1%eimp  =l2%eimp
      l1%signoup=l2%signoup
      l1%signodw=l2%signodw

  end subroutine copialoc

  subroutine copiawalker(w1,w2)
   type (walker), intent (inout) :: w1
   type (walker), intent (in) :: w2
   ! Use array-section syntax (:) to force value copy without reallocation.
   ! Plain allocatable assignment (w1%atom = w2%atom) does a shallow pointer
   ! copy in nvfortran CUDA mode, causing a double-free in deallocatewalker.
    w1%atom(:)=w2%atom(:)
    w1%dwf(:) =w2%dwf(:)
    w1%lw  =w2%lw
    w1%delta(:)=w2%delta(:)
    w1%hb2m(:)=w2%hb2m(:)
    w1%sigma1(:)=w2%sigma1(:)
    w1%sigma2(:)=w2%sigma2(:)
    w1%sprop=w2%sprop
    w1%dangle=w2%dangle
    w1%b=w2%b
    w1%sig1rot=w2%sig1rot
    w1%sig2rot=w2%sig2rot
    w1%sig1hrot=w2%sig1hrot
    w1%sig2hrot=w2%sig2hrot
    w1%dphi=w2%dphi
    w1%eje0=w2%eje0
    w1%pos0=w2%pos0

  end subroutine copiawalker

  subroutine allocatewalker(w,n)
   type (walker), intent(out) :: w
   integer (kind=i4), intent(in) :: n

    allocate(w%atom(n))
    allocate(w%dwf(n))
    allocate(w%delta(n))
    allocate(w%hb2m(n))
    allocate(w%sigma1(n))
    allocate(w%sigma2(n))

  end subroutine allocatewalker

  subroutine deallocatewalker(w)
   type (walker) :: w

    deallocate(w%atom)
    deallocate(w%dwf)
    deallocate(w%delta)
    deallocate(w%hb2m)
    deallocate(w%sigma1)
    deallocate(w%sigma2)

  end subroutine deallocatewalker

end module mtipos
