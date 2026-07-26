program promedia
 implicit none
 integer, parameter :: i4=selected_int_kind(9)
 integer, parameter :: r8=selected_real_kind(15,9)

  character(len=100) :: fichero
  integer(kind=i4) :: datini,datfin
  integer(kind=i4) :: nparal
  integer(kind=i4) :: opcion


  read(5,'(a)') fichero
  read(5,*) datini
  read(5,*) datfin
  read(5,*) nparal
  read(5,*) opcion

  write(6,'("fichero lectura de datos",t30,a)') trim(fichero)
  write(6,'("primera linea que se lee",t30,i10)') datini 
  write(6,'("ultima  linea que se lee",t30,i10)') datfin
  write(6,'("numero de procesos en paralelo",t30,i10)') nparal
  write(6,'("1=mcv, 2=dmc",t30,i10)') opcion

  call leedatos

contains

 subroutine leedatos
  integer(kind=i4) :: nval(3)
  real(kind=r8) :: rval(7),rsum(7),rcum(7),rsum2(7)
  integer(kind=i4) :: ilee,nlee,ncum

   nlee=0
   ncum=0
   rval=0.0_r8
   rsum=0.0_r8
   rsum2=0.0_r8
   rcum=0.0_r8

   open(unit=10,file=fichero,status="old")

     do ilee=1,datini-1
       read(10,*)
     enddo

     select case (opcion)
       case (1)
         do ilee=datini,datfin
           read(10,'(3i10,2f16.8,5f10.2)') nval,rval
           write(20,'(3i10,2f16.8,5f10.2)') nval,rval
           nlee=nlee+1
           rsum=rsum+rval
           rsum2=rsum2+rval**2
           if(ilee.gt.datfin-nparal) then
             ncum=ncum+1
             rcum=rcum+rval
           endif
         enddo
       case (2)
         do ilee=datini,datfin
           read(10,'(3i8,3f16.8,f10.2)') nval,rval(1:4)
           write(20,'(3i8,3f16.8,f10.2)') nval,rval(1:4)
           nlee=nlee+1
           rsum=rsum+rval
         enddo
       case default
         write(6,*) 'error en opcion',opcion
         write(6,*) 'debe valer 1 o 2'
     end select

     write(*,*) datfin-datini+1
     write(*,*) nlee
     write(*,*) nparal
     write(*,*) ncum

     rsum=rsum/nlee
     rsum2=rsum2/nlee
     rsum2=sqrt((rsum2-rsum**2)/(nlee-1))
     write(*,*) rsum
     write(*,*) rsum2
     write(*,*) 
     write(*,*) rcum/ncum
     

   close(10)

 end subroutine leedatos

end program promedia
