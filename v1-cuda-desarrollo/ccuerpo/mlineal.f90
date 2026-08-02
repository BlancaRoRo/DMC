module mlineal
 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: r8=selected_real_kind(15,9)

contains

 function det(n,b)
  integer (kind=i4), intent (in) :: n
  real (kind=r8), intent (in) :: b(n,n)
  real (kind=r8) :: det
  real (kind=r8) :: a(n,n),sum,pivot,piv
  integer (kind=i4) :: i,j,k
  integer (kind=i4) :: ipiv

  a=b

  det=1.0_r8
  do j=1,n
    if(j.ne.1) then
      do i=2,n
        sum=a(i,j)
        do k=1,min(i-1,j-1)
          sum=sum-a(i,k)*a(k,j)
        enddo
        a(i,j)=sum
      enddo
    endif
    pivot=0.0_r8
    do k=j,n
      piv=abs(a(k,j))
      if(piv.gt.pivot) then
         ipiv=k
         pivot=piv
      endif
    enddo
    if(ipiv.ne.j) then
      do i=1,n
        pivot=a(j,i)
        a(j,i)=a(ipiv,i)
        a(ipiv,i)=pivot
      enddo
      det=-det   
    endif
    pivot=a(j,j)
    if(j.ne.n) then
      do k=j+1,n
        a(k,j)=a(k,j)/pivot
      enddo
    endif
    det=det*pivot
  enddo

 end function det
          
 

end module mlineal
