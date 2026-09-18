module mlegendre

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: r8=selected_real_kind(15,9)

 contains
 
 subroutine calpleg(l,x,pl)
  integer(kind=i4), intent (in) :: l
  real(kind=r8), intent (in) :: x
  real(kind=r8), intent (out) :: pl(0:l)
  integer(kind=i4) :: il

   pl(0)=1.0_r8
   pl(1)=x
   do il=1,l-1
     pl(il+1)=((2.0_r8*il+1.0_r8)*x*pl(il)-il*pl(il-1))/(il+1.0_r8)
   enddo
 end subroutine calpleg

 subroutine calderpleg(l,x,pl,d1pl,d2pl)
  integer(kind=i4), intent (in) :: l
  real(kind=r8), intent (in) :: x
  real(kind=r8), intent (out) :: pl(0:l),d1pl(0:l),d2pl(0:l)
  integer(kind=i4) :: il

   pl(0)=1.0_r8
   pl(1)=x
   d1pl(0)=0.0_r8
   d1pl(1)=1.0_r8
   d2pl(0)=0.0_r8
   d2pl(1)=0.0_r8
   do il=1,l-1
     pl(il+1)=((2.0_r8*il+1.0_r8)*x*pl(il)-il*pl(il-1))/(il+1.0_r8)
     d1pl(il+1)=(2.0_r8*il+1.0_r8)*pl(il)+d1pl(il-1)
     d2pl(il+1)=(2.0_r8*il+1.0_r8)*d1pl(il)+d2pl(il-1)
   enddo
 end subroutine calderpleg

 
end module mlegendre
