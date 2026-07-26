module mdmcpromedia

 use mtipos

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: r8=selected_real_kind(15,9)

  character (len=80), private, parameter :: cabecera=                       &
&"================================================================================"
  character (len=80), private, parameter :: equilibracion=                  &
&"==================Bloques para EQUILIBRIO======================================="
  character (len=80), private, parameter :: calculo=                        &
&"=====================Bloques de CALCULO========================================="
  character (len=30), private, parameter :: resultados=                     &
 &  "RESULTADOS DEL CALCULO"

    integer(kind=i4), private, parameter :: nvalblo=5

  integer(kind=i4), private, parameter :: nprop=8
  integer(kind=i4), private, parameter :: npropw=5,numener=6
  character(len=20), private :: nombprop(nprop)=                            &
&  (/ "Energia cinetica    ","Energia potencial   ","Energia total       ", &
&     "Energia rotacion    ","Energia trasl impur "                       , & 
&     "Energia growth      ","Poblacion media     ","Estadistica         " /)

  real(kind=r8), private, save :: valb(0:nprop),valm(0:nprop),dtip(nprop)

       
contains


   subroutine dmcnumprop(dmcnvalblo,dmcnvaltot)
    integer(kind=i4), intent (out) :: dmcnvalblo,dmcnvaltot

     dmcnvalblo=nvalblo
     dmcnvaltot=2*nprop+1

   end subroutine dmcnumprop

   subroutine dmcescrini(equilbr)
    logical, intent (in) :: equilbr

     if(equilbr) then
       write(6,'(/)')
       write(6,'(a80)') cabecera
       write(6,'(t20,"CALCULO Diffusion Monte Carlo")')
       write(6,'(a80)') cabecera
       write(6,'(a80)') equilibracion
     else
       write(6,'(a80)') calculo
     endif

     write(6,'(3a10,3a15,a12)') "Bloque","Blq/Proc", "Proceso",                    &
 &                        " <E_bloque>    ","   <E_calculo> ","  <E_growth>   ",   &
 &                        "<Poblacion> "

    call flush(6)

   end subroutine dmcescrini

   subroutine dmcceroini

    valm=0.0_r8
    dtip=0.0_r8

   end subroutine dmcceroini

   subroutine dmcceroblo

    valb=0.0_r8

   end subroutine dmcceroblo

   subroutine dmcsumapaso(nwpaso,egrow,wsim)
    integer(kind=i4), intent (in) :: nwpaso
    real(kind=r8), intent (in) :: egrow
    type(walker), intent (in) :: wsim(nwpaso)
    integer(kind=i4) :: iwalker

    do iwalker=1,nwpaso
      valb(0)=valb(0)+1.0_r8
      valb(1)=valb(1)+wsim(iwalker)%lw%kin
      valb(2)=valb(2)+wsim(iwalker)%lw%pot
      valb(3)=valb(3)+wsim(iwalker)%lw%ene
      valb(4)=valb(4)+wsim(iwalker)%lw%erot
      valb(5)=valb(5)+wsim(iwalker)%lw%eimp
    enddo
    valb(6)=valb(6)+egrow
    valb(7)=valb(7)+nwpaso
    valb(8)=valb(8)+1.0_r8

  end subroutine dmcsumapaso

   subroutine dmcsumablo

     valm(0)=valm(0)+1.0_r8

     valb(1:npropw)=valb(1:npropw)/valb(0)
     valb(npropw+1:nprop-1)=valb(npropw+1:nprop-1)/valb(nprop)
     valb(nprop)=valb(0)

     valm(1:nprop)=valm(1:nprop)+valb(1:nprop)
     dtip(1:nprop)=dtip(1:nprop)+valb(1:nprop)**2

   end subroutine dmcsumablo

   subroutine dmcsumafin

    valm(1:nprop)=valm(1:nprop)/valm(0)
    dtip(1:nprop)=dtip(1:nprop)/valm(0)
    valm(0)=max(1.0_r8,valm(0)-1.0_r8)
    dtip(1:nprop)=sqrt(abs(dtip(1:nprop)-valm(1:nprop)**2)/valm(0))

   end subroutine dmcsumafin

   subroutine dmcgetdatostot(pval)
    real(kind=r8), intent (out) :: pval(2*nprop+1)

     pval(1:nprop)=valm(1:nprop)
     pval(nprop+1:2*nprop)=dtip(1:nprop)
     pval(2*nprop+1)=valm(0)

   end subroutine dmcgetdatostot

   subroutine dmcputdatostot(pval)
    real(kind=r8), intent (in) ::  pval(2*nprop+1)

     valm(1:nprop)=pval(1:nprop)
     dtip(1:nprop)=pval(nprop+1:2*nprop)
     valm(0)=pval(2*nprop+1)

   end subroutine dmcputdatostot

   subroutine dmcgetdatosblo(pval)
    real(kind=r8), intent (out) :: pval(nvalblo)

     pval(1)=valb(3)
     pval(2)=valm(3)
     pval(3)=valm(0)
     pval(4)=valm(6)
     pval(5)=valm(7)

   end subroutine dmcgetdatosblo

   subroutine dmcescrblo(icpar,ncpar,pval)
    integer(kind=i4), intent (in) :: icpar,ncpar
    real(kind=r8), intent (in) :: pval(nvalblo)
    real(kind=r8) :: pthe4,pthe3,ptx,ptr
    integer(kind=i4) :: nbcum

     nbcum=(int(pval(3))-1)*ncpar+icpar

      write(6,'(3i8,3f16.8,f10.2)') nbcum,int(pval(3)),icpar,                  &
 &                                  pval(1),pval(2)/pval(3),pval(4)/pval(3),   &
 &                                  pval(5)/pval(3)

      call flush(6)


   end subroutine dmcescrblo

   subroutine dmcescrfin(dtau,cmtok,k2mev,opot)
    real(kind=r8), intent (in) :: dtau,cmtok,k2mev
    integer(kind=i4), intent (in) :: opot
    integer(kind=i4) :: i

   write(6,'(a80)') cabecera
   write(6,'(/)')
   write(6,'(a80)') cabecera
   write(6,'(t10,a30)') resultados
   write(6,'(a80)') cabecera
   if(opot.eq.4) then
      write(6,'("Resultados en meV")')
      do i=1,nprop-1
        write(6,'(a4,a20,t25," = ",f10.7,f20.10," +/- ",f16.8)') "meV ",        &
  &                        nombprop(i),dtau,valm(i),dtip(i)
      enddo
      i=nprop
      write(6,'(a4,a20,t25," = ",f10.7,es20.10," +/- ",es16.8)') "meV ",        &
  &                        nombprop(i),dtau,valm(i),dtip(i)
      valm=valm/k2mev
      dtip=dtip/k2mev
      write(6,'(a80)') cabecera
   endif
   write(6,'("Resultados en K")')
   do i=1,numener
     write(6,'(a2,a20,t25," = ",f10.7,f20.10," +/- ",f16.8)') "K ",             &
 &                   nombprop(i),dtau,valm(i),dtip(i)
   enddo
   write(6,'(a80)') cabecera
   write(6,'("Resultados en cm-1")')
   do i=1,numener
     write(6,'(a5,a20,t25," = ",f10.7,f20.10," +/- ",f16.8)')  "cm-1 ",             &
 &                    nombprop(i),dtau,valm(i)/cmtok,dtip(i)/cmtok
   enddo
   write(6,'(a80)') cabecera
   do i=numener+1,nprop
     write(6,'(a20," = ",es14.6," +/- ",es12.5)') nombprop(i),valm(i),dtip(i)
   enddo

   end subroutine dmcescrfin


end module mdmcpromedia
