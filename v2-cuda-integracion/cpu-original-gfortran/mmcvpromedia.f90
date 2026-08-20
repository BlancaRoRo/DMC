module mmcvpromedia

 use mtipos
 use mdensidades

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

  real(kind=r8), public, save :: pmcvacep,pmcvtot
  real(kind=r8), public, save :: pmcvacephe4,pmcvtothe4,pmcvacephe3,pmcvtothe3
  real(kind=r8), public, save :: pmcvacepx,pmcvtotx
  real(kind=r8), public, save :: pmcvaceprot,pmcvtotrot

  integer(kind=i4), private, parameter :: nvalblo=13

  integer(kind=i4), private, parameter :: nprop=5
  character(len=30), private :: nombprop(nprop)=                            &
&  (/ "Energia cinetica              ","Energia potencial             ",    &
&     "Energia total                 ",                                     &
&     "Energia rotacion molecula     ","Energia traslacion impureza   " /)
  real(kind=r8), private, save :: valb(0:nprop),valm(0:nprop),dtip(nprop)
       
contains

   subroutine mcvnumprop(mcvnvalblo,mcvnvaltot)
    integer(kind=i4), intent (out) :: mcvnvalblo,mcvnvaltot

     mcvnvalblo=nvalblo
     mcvnvaltot=2*nprop+1

   end subroutine mcvnumprop

   subroutine mcvescrini(equilbr)
    logical, intent (in) :: equilbr

     if(equilbr) then
       write(6,'(a80)') cabecera
       write(6,'(t20,"CALCULO Monte Carlo Variacional")')
       write(6,'(a80)') cabecera
       write(6,'(a80)') equilibracion
     else
       write(6,'(a80)') calculo
     endif

     write(6,'(3a10,2a18,a14,4a10)') "Bloque","Blq/Proc", "Proceso",               &
 &                        " <E_bloque> ","    <E_calculo> ",                       &
 &                        "%aceptacion","%ace he4","%ace he3","%ace imp","%ace rot"

    call flush(6)

   end subroutine mcvescrini

   subroutine mcvceroini

    pmcvacep=0.0_r8
    pmcvtot=0.0_r8
    pmcvacephe4=0.0_r8
    pmcvtothe4=0.0_r8
    pmcvacephe3=0.0_r8
    pmcvtothe3=0.0_r8
    pmcvacepx=0.0_r8
    pmcvtotx=0.0_r8
    pmcvaceprot=0.0_r8
    pmcvtotrot=0.0_r8

    valm=0.0_r8
    dtip=0.0_r8


   end subroutine mcvceroini

   subroutine mcvceroblo

    valb=0.0_r8

   end subroutine mcvceroblo

   subroutine mcvsumapaso(lp)
    type(vloc), intent (in) :: lp

    valb(0)=valb(0)+1.0_r8
    valb(1)=valb(1)+lp%kin
    valb(2)=valb(2)+lp%pot
    valb(3)=valb(3)+lp%ene
    valb(4)=valb(4)+lp%erot
    valb(5)=valb(5)+lp%eimp

  end subroutine mcvsumapaso

   subroutine mcvsumablo

    valm(0)=valm(0)+1.0_r8

    valb(1:nprop)=valb(1:nprop)/valb(0)
    valm(1:nprop)=valm(1:nprop)+valb(1:nprop)
    dtip(1:nprop)=dtip(1:nprop)+valb(1:nprop)**2

   
   end subroutine mcvsumablo

   subroutine mcvsumafin(emcv)
    real(kind=r8), intent (out) :: emcv(2)

    valm(1:nprop)=valm(1:nprop)/valm(0)
    dtip(1:nprop)=dtip(1:nprop)/valm(0)
    valm(0)=max(1.0_r8,valm(0)-1.0_r8)
    dtip(1:nprop)=sqrt(abs(dtip(1:nprop)-valm(1:nprop)**2)/valm(0))


    emcv(1)=valm(3)
    emcv(2)=dtip(3)
    
   
   end subroutine mcvsumafin

   subroutine mcvgetdatostot(pval)
    real(kind=r8), intent (out) :: pval(2*nprop+1)
    integer(kind=i4) :: iprop

     do iprop=1,nprop
       pval(iprop)=valm(iprop)
       pval(nprop+iprop)=dtip(iprop)
     enddo
     pval(2*nprop+1)=valm(0)

   end subroutine mcvgetdatostot

   subroutine mcvputdatostot(pval)
    real(kind=r8), intent (in) :: pval(2*nprop+1)
    integer(kind=i4) :: iprop

     do iprop=1,nprop
       valm(iprop)=pval(iprop)
       dtip(iprop)=pval(nprop+iprop)
     enddo
     valm(0)=pval(2*nprop+1)

   end subroutine mcvputdatostot

   subroutine mcvgetdatosblo(pval)
    real(kind=r8), intent (out) :: pval(nvalblo)

     pval(1)=valb(3)
     pval(2)=valm(3)
     pval(3)=valm(0)
     pval(4)=pmcvacep
     pval(5)=pmcvtot
     pval(6)=pmcvacephe4
     pval(7)=pmcvtothe4
     pval(8)=pmcvacephe3
     pval(9)=pmcvtothe3
     pval(10)=pmcvacepx
     pval(11)=pmcvtotx
     pval(12)=pmcvaceprot
     pval(13)=pmcvtotrot

   end subroutine mcvgetdatosblo

   subroutine mcvescrblo(icpar,ncpar,pval)
    integer(kind=i4), intent (in) :: icpar,ncpar
    real(kind=r8), intent (in) :: pval(nvalblo)
    real(kind=r8) :: pthe4,pthe3,ptx,ptr
    integer(kind=i4) :: nbcum

     nbcum=(int(pval(3))-1)*ncpar+icpar

     pthe4=max(pval(7),1.0_r8)
     pthe3=max(pval(9),1.0_r8)
     ptx=max(pval(11),1.0_r8)
     ptr=max(pval(13),1.0_r8)

    write(6,'(3i10,2f20.10,5f10.2)') nbcum,int(pval(3)),icpar,           &  
 &                                pval(1),pval(2)/pval(3),              &
 &                                100.0_r8*pval(4)/pval(5),             &
 &                                100.0_r8*pval(6)/pthe4,               &
 &                                100.0_r8*pval(8)/pthe3,               &
 &                                100.0_r8*pval(10)/ptx,                &
 &                                100.0_r8*pval(12)/ptr
    call flush(6)

   end subroutine mcvescrblo

   subroutine mcvescrfin(cmtok,k2mev,opot)
    real(kind=r8), intent (in) :: cmtok,k2mev
    integer(kind=i4), intent (in) ::opot
    integer(kind=i4) :: i

   write(6,'(a80)') cabecera
   write(6,'(/)')
   write(6,'(a80)') cabecera
   write(6,'(t10,a30)') resultados

   write(6,'("% aceptacion metropolis",5x,f10.5)')100.0_r8*pmcvacep/pmcvtot
   write(6,'(a80)') cabecera
   if(opot.eq.4) then
      write(6,'("Resultados en meV")')
      do i=1,nprop
        write(6,'(a4,a30,t25," = ",f16.8," +/- ",f14.8)') "meV ",        &
  &                        nombprop(i),valm(i),dtip(i)
      enddo
      valm=valm/k2mev
      dtip=dtip/k2mev
      write(6,'(a80)') cabecera
   endif
   write(6,'("Resultados en K")')
   do i=1,nprop
     write(6,'(a4,a20,t25," = ",f16.8," +/- ",f14.8)') "K   ",                 &
  &                           nombprop(i),valm(i),dtip(i)
   enddo
   write(6,'(a80)') cabecera
   write(6,'("Resultados en cm-1")')
   do i=1,nprop
     write(6,'(a5,a20,t25," = ",f16.8," +/- ",f14.8)') "cm-1 ",               &
 &                            nombprop(i),valm(i)/cmtok,dtip(i)/cmtok
   enddo
   write(6,'(a80)') cabecera


   end subroutine mcvescrfin

end module mmcvpromedia
