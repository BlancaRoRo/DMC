module mparalelo

 use mtipos
 use mrandom
 use mrandom2
 use mvaziz
 use mvmolecula
 use mparametros

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: i8=selected_int_kind(15)
 integer, private, parameter :: r8=selected_real_kind(15,9)

   integer(kind=i4), private,save ::  ncpar
   logical, private, save :: soydire

contains

 subroutine iniciaparalelo

  soydire=.true.

 end subroutine iniciaparalelo

 subroutine iniprocesos

   ncpar=1

   if(soydire) write(6,'("calculo en serie")') 
   if(soydire) write(6,'("numero de calculos",t40,i10)') ncpar

 end subroutine iniprocesos

 subroutine quiensoy(soydireval)
  logical, intent (out) :: soydireval

   soydireval=soydire

 end subroutine quiensoy

 subroutine cuantosparalelos(ncparval)
  integer(kind=i4), intent (out) :: ncparval

   ncparval=ncpar

 end subroutine cuantosparalelos

 subroutine reparteentrada

   if(.not.datosbien) call fincalculo

 end subroutine reparteentrada

 subroutine repartepotencial

 end subroutine repartepotencial

 subroutine compruebatodos
  integer(kind=i8) :: irnpar

   call sacasemilla(irnpar)
   write(6,*) 'proceso numero',ncpar
   write(6,*) 'numero de walkers en este proceso',nwalkers
   write(6,*) 'semilla para este proceso',irnpar

 end subroutine compruebatodos

 subroutine distribuyesemillas
  real(kind=r8) :: rn
  integer(kind=i8) :: irnpar

   call sacasemilla(irnpar)
   call rand1p(rn,irnpar)
   call fijasemilla(irnpar)

 end subroutine distribuyesemillas

 subroutine sumareal(rval)
  real(kind=r8), intent (inout) :: rval

 end subroutine sumareal

 subroutine sumareales(ndim,rval)
  integer(kind=i4), intent (in) :: ndim
  real(kind=r8), intent (inout) :: rval(ndim)

 end subroutine sumareales


 subroutine repartewalker(w1)
  type(walker), intent (in) :: w1

 end subroutine repartewalker


 subroutine direrecibereales(itid,nval,pval)
  integer(kind=i4), intent (in) ::  itid
  integer(kind=i4), intent (in) ::  nval
  real(kind=r8), intent (in) :: pval(nval)

 end subroutine direrecibereales

 subroutine otrorecibereales(nval,pval)
  integer(kind=i4), intent (in) ::  nval
  real(kind=r8), intent (in) :: pval(nval)

 end subroutine otrorecibereales

 subroutine repartereales(ndim,rval)
  integer(kind=i4), intent (in) :: ndim
  real(kind=r8), intent (in) :: rval(ndim)

 end subroutine repartereales

 subroutine otroenviareales(nval,pval)
  integer(kind=i4), intent (in) :: nval
  real(kind=r8), intent (in) :: pval(nval)


 end subroutine otroenviareales

 subroutine fincalculo

  stop

 end subroutine fincalculo

end module mparalelo
