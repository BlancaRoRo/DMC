module mrotaciones

 use mtipos

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: r8=selected_real_kind(15,9)


contains
 subroutine rota(i1,phi,ejes)
  integer(kind=i4), intent (in) :: i1
  real(kind=r8), intent (in) :: phi
  type(vec3), intent (inout) :: ejes(3)
  real(kind=r8) :: c,s,t
  integer(kind=i4) :: j1,k1,ic
 
   j1=i1+1
   if(j1.gt.3) j1=1
   k1=j1+1 
   if(k1.gt.3) k1=1

   c=cos(phi)
   s=sin(phi)

   do ic=1,3
     t=                 c*ejes(j1)%comp(ic)+s*ejes(k1)%comp(ic)
     ejes(k1)%comp(ic)=-s*ejes(j1)%comp(ic)+c*ejes(k1)%comp(ic)
     ejes(j1)%comp(ic)=t
   enddo

  
 end subroutine rota


end module mrotaciones
