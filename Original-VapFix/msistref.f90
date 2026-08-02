module msistref

 use mparametros
 use mtipos

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: r8=selected_real_kind(15,9)
 

contains

 subroutine ccuerpo(w1,rhesal)
  type(walker), intent (in) :: w1
  real(kind=r8), intent (out) :: rhesal(3*ngatom)
  type(vec3) :: rtemp
  integer(kind=i4) :: iatom,jatom,ic,jc

    iatom=0
      do jatom=1,ngatom
          rtemp=w1%atom(jatom)-w1%atom(ngatom+1)
         do ic=1,3
           rhesal(iatom+ic)=0.0_r8
           do jc=1,3
             rhesal(iatom+ic)=rhesal(iatom+ic)+w1%sprop(ic)%comp(jc)*rtemp%comp(jc)
           enddo
         enddo
         iatom=iatom+3
      enddo

  
 end subroutine ccuerpo

 subroutine cespacio(w1,ratsal)
  type(walker), intent (in) :: w1
  real(kind=r8), intent (out) :: ratsal(3*namol)
  type(vec3) :: rtemp
  integer(kind=i4) :: iatom,iamol,ic,jc
  integer(kind=i4) :: natom

    natom=ngatom+1
    iatom=0
    do iamol=1,namol
      rtemp=0.0_r8
      do ic=1,3
        do jc=1,3
          rtemp%comp(ic)=rtemp%comp(ic)+w1%sprop(jc)%comp(ic)*cintr(jc,iamol)
        enddo
        ratsal(iatom+ic)=w1%atom(natom)%comp(ic)+rtemp%comp(ic)
      enddo
      iatom=iatom+3
    enddo

  
 end subroutine cespacio


end module msistref
