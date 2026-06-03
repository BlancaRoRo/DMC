module mentradatos

 use mparametros
 use mvaziz
 use mhh_heocs
 use mkp_heco
 use mrandom

  implicit none
  integer, private, parameter :: i4=selected_int_kind(9)
  integer, private, parameter :: i8=selected_int_kind(15)
  integer, private, parameter :: r8=selected_real_kind(15,9)

   character(len=3), private, save, allocatable :: atomo(:)
   real(kind=r8), private, save, allocatable :: zatmol(:),matmol(:)
   integer(kind=i4), private :: unidis
   logical, private, save :: impurtras

contains

 subroutine leedatos
  integer(kind=i4) :: iamol
  integer(kind=i4) :: il 
  logical :: empieza

   datosbien=.true.

   empieza=.true.
   call escribein(empieza)
   open(unit=5,file="in.copia",status="old")
   rewind(5)

   read(5,*)
   read(5,*)   !DATOS DEL SISTEMA
   read(5,*)
   read(5,*) libre
   read(5,*) mhe4
   read(5,*) mhe3
   read(5,*) nhe4
   read(5,*) nhe3
   read(5,*) namol
   call checkmax(namol,namolmax,"numero maximo de atomos en la molecula")
   if(namol.gt.0) then
     allocate (atomo(namol))
     allocate (zatmol(namol),matmol(namol))
     do iamol=1,namol
       read(5,'(a)') atomo(iamol)
       read(5,*) matmol(iamol)
     enddo
     do iamol=2,namol
       read(5,*) zatmol(iamol)
     enddo
     read(5,*) unidis
     read(5,*)
     read(5,*)  !opot=0 He-atomo   Potencial tipo Aziz
     read(5,*)  !opot=1 He-OCS Paesani and Whaley, JCP 121, 4180 (2004)
     read(5,*)  !opot=2 He-OCS Howson and Hutson,  JCP 115, 5059 (2001)
     read(5,*)  !opot=3 He-CO Peterson and McBane, JCP 123, 084314 (2005)
     read(5,*)  !opot=4 He-H2+ Breton et al  Preprint 2023   energias en meV
     read(5,*)
     read(5,*) opot
     read(5,'(a)') fichpot
     read(5,*) impurtras
     read(5,*) rotamol
     impurfija=.not.impurtras
   endif

   read(5,*)
   read(5,*)   !DATOS MONTE CARLO
   read(5,*)
   read(5,*) irncal
   read(5,*) opcion
   read(5,*) enermin
   read(5,*) deltahe4
   read(5,*) deltahe3
   if(namol.gt.0) read(5,*) deltax
   if(namol.gt.1) read(5,*) deltaa
   read(5,*) etrial
   read(5,*) dtau
   read(5,*) nblockeq
   read(5,*) npasosdc
   read(5,*) nblock
   read(5,*) npasos
   read(5,*) nwalkers
   read(5,*) ncetrial

   read(5,*)
   read(5,*)   !DATOS FUNCION DE ONDA
   read(5,*)
   read(5,*)
   read(5,*) ! he-he: f(r)=exp(-0.5*(b/r)**nu-alfa*r)
   read(5,*)
   read(5,*) bhe4,dbhe4
   read(5,*) nuhe4,dnuhe4
   read(5,*) alfahe4,dalfahe4
   read(5,*) bhe3,dbhe3
   read(5,*) nuhe3,dnuhe3
   read(5,*) alfahe3,dalfahe3
   read(5,*) bback,dbback
   read(5,*) bmix,dbmix
   read(5,*) numix,dnumix
   read(5,*) alfamix,dalfamix
   if(namol.gt.0) then
     read(5,*)
     read(5,*)  ! X-he
     read(5,*)  ! f(r,theta)=exp(u(r,theta))
     read(5,*)  ! u(r,theta)=sum_{l=0}^lmax u_l(r) P_l(cos(theta))
     read(5,*)  ! u_l(r)=-0.5*(b_l/r)**nu_l-alfa_l*r**p4-p5*ln(r)
     read(5,*)
     read(5,*) lxhe4
     call checkmax(lxhe4,lmax,"lmax impureza he4")
     if(.not.datosbien) then
       lxhe4=0
       lxhe3=0
       ncadapvm=0
       return
     endif
     do il=0,lxhe4
       read(5,*)
       read(5,*) bxhe4(il),dbxhe4(il)
       read(5,*) nuxhe4(il),dnuxhe4(il)
       read(5,*) alfaxhe4(il),dalfaxhe4(il)
       read(5,*) p4xhe4(il),dp4xhe4(il)
       read(5,*) p5xhe4(il),dp5xhe4(il)
     enddo
     read(5,*) lxhe3
     call checkmax(lxhe3,lmax,"lmax impureza he3")
     if(.not.datosbien) then
       lxhe3=0
       ncadapvm=0
       return
     endif
     do il=0,lxhe3
       read(5,*)
       read(5,*) bxhe3(il),dbxhe3(il)
       read(5,*) nuxhe3(il),dnuxhe3(il)
       read(5,*) alfaxhe3(il),dalfaxhe3(il)
       read(5,*) p4xhe3(il),dp4xhe3(il)
       read(5,*) p5xhe3(il),dp5xhe3(il)
     enddo
   endif

   read(5,*)
   read(5,*)
   read(5,*)   !DATOS CALCULO EN PARALELO
   read(5,*)
   read(5,*)
   read(5,*) ncadapvm

   close(unit=5)


 end subroutine leedatos

 subroutine escribedatos
  real(kind=r8) :: zcm
  integer(kind=i4) :: ihe3
  integer(kind=i4) :: iamol
  integer(kind=i4) :: nlen,ilen
  integer(kind=i4) :: jval,njval=6
  character(len=10) :: molecula
  character(len=3) :: bb,ff
  character(len=1) :: espacio=" "
  integer(kind=i4) :: il


   write(6,'(//)')
   write(6,'("VALORES DE LAS CONSTANTES EN ESTE CALCULO")')
   write(6,'(t5,"Constantes fisicas segun CODATA 2010")')
   write(6,'("velocidad de la luz en m/s",t45,f15.1)') cluz
   write(6,'("radio de Bohr en A",t45,f15.12)') rbohr
   write(6,'("k_Boltzmann en eV/K",t40,es20.10)') kb
   write(6,'("hbarra*c en MeV*fm",t40,f20.10)') hbc
   write(6,'("uma en MeV/c**2",t40,f20.10)') umac2
   write(6,'("hbar**2/(2m) en uma*K A**2",t40,f20.10)') hb2
   write(6,'("hbar**2/(2m) en uma* cm-1",t40,f20.10)') hb2cm
   write(6,'("1 cm-1 en K",t40,f20.10)') cmtok
   write(6,'("K en meV ",t40,f20.10)') k2mev_bh
   write(6,'("hbar**2/(2m) en uma*eV A**2",t40,f20.10)') hb2*k2mev_bh
   write(6,'("Esquema de ocupacion de los espines")')
   write(6,'("N de atomos de helio3",t26,9i4)') (ihe3,ihe3=0,8)
   write(6,'("Ocupacion up",t26,9i4)') nnup
   write(6,'("Ocupacion down",t26,9i4)') nndw
   write(6,'("Si hay mas de 8 he3: polarizacion de espin minima")')
   write(6,'("pi",t45,f15.9)') pi


   write(6,'(//)')
   write(6,'("DATOS DEL SISTEMA")')
   if(opot.eq.4) then
      write(6,'("Energias en meV y distancias en A")')
   else
      write(6,'("Energias en K y distancias en A")')
   endif

   write(6,'(//)')
   write(6,'("DATOS DEL SISTEMA")')
   write(6,'("calculo sin interaccion",t30,l10)') libre
   write(6,'("masa helio 4 en uma",t30,f10.6)') mhe4
   write(6,'("masa helio 3 en uma",t30,f10.6)') mhe3
   write(6,'("numero de atomos de he4",t30,i10)') nhe4
   write(6,'("numero de atomos de he3",t30,i10)') nhe3
   write(6,'("atomos en la impureza molecular",t35,i5)') namol
   if(namol.gt.0) then
     do iamol=1,namol
       write(6,'("atomo",t6,i3,t12,"nombre",t20,a2,t23,"masa",t30,f10.5)')  &
 &             iamol,atomo(iamol),matmol(iamol)
     enddo
     if(unidis.eq.1) then
       write(6,'(t5,"las distancias en la molecula se leen en ua")') 
       do iamol=2,namol
         write(6,'(t5,"distancia en ua",t36,2a2,f10.5)') atomo(iamol-1),       &
 &             atomo(iamol),zatmol(iamol)
               zatmol(iamol)=zatmol(iamol)*rbohr
       enddo
     endif
     do iamol=2,namol
       write(6,'(t5,"distancia en A",t36,2a2,f10.5)') atomo(iamol-1),       &
 &             atomo(iamol),zatmol(iamol)
     enddo
     zatmol(1)=0.0_r8
     do iamol=2,namol
       zatmol(iamol)=zatmol(iamol)+zatmol(iamol-1)
     enddo
     call calbrot
     zcm=0.0_r8
     write(6,'("Coordenadas de los atomos en el sistema intrinseco")')
     do iamol=1,namol
       write(6,'(t2,a2,3f12.7)') atomo(iamol),cintr(:,iamol)
       zcm=zcm+matmol(iamol)*cintr(3,iamol)
     enddo
     write(6,'(t2,"CM en el sistema intrinseco",t30,f10.6)') zcm
     nlen=1
     do iamol=1,namol
       ilen=len(trim(atomo(iamol)))
       molecula(nlen:nlen+ilen-1)=trim(atomo(iamol))
       nlen=nlen+ilen
     enddo
     write(6,'("tipo de potencial X-He",t30,i10)') opot
     write(6,'("fichero potencial X-He",t30,a)') trim(fichpot)
     write(6,'("la impureza se traslada",t30,l10)') impurtras
     write(6,'("la impureza no se traslada",t30,l10)') impurfija
     write(6,'("la impureza rota",t30,l10)') rotamol
   else
    molecula="Pura"
    impurfija=.true.
    rotamol=.false.
    nlen=5
   endif
   do ilen=nlen,10
     molecula(ilen:ilen)=espacio
   enddo

   write(6,'(//)')
   write(6,'("DATOS MONTE CARLO")')
   write(6,'("semilla num aleatorios",t24,i16)') irncal
   write(6,'("opcion de calculo",t30,i10)') opcion
   write(6,'("enermin energia minima",t30,l10)') enermin
   if (enermin) then
     write(6,'("minimiza energia con Metropolis")')
   else
     write(6,'("minimiza varianza con Metropolis")')
   endif
   write(6,'("delta pasos metropolis he4",t30,f10.6)') deltahe4
   write(6,'("delta pasos metropolis he3",t30,f10.6)') deltahe3
   if(namol.gt.0) then
     write(6,'("delta pasos metropol impureza",t30,f10.6)') deltax
     if(namol.gt.1) then
       write(6,'("delta giros metropol grados",t30,f10.6)') deltaa
       deltaa=deltaa*pi/180.0_r8
       write(6,'("delta giros metropol rad",t30,f10.6)') deltaa
     endif
   endif
   write(6,'("etrial energia prueba dmc",t26,f14.7)') etrial
   write(6,'("dtau paso de tiempo dmc",t30,f10.6)') dtau
   write(6,'("bloques de equilibrio",t30,i10)') nblockeq
   write(6,'("pasos de descorrelacion",t30,i10)') npasosdc
   write(6,'("bloques de calculo",t30,i10)') nblock
   write(6,'("pasos por bloque",t30,i10)') npasos
   write(6,'("numero de walkers",t30,i10)') nwalkers
   write(6,'("pasos para cambiar etrial",t30,i10)') ncetrial

   write(6,'(//)')
   write(6,'("DATOS FUNCION DE ONDA")')
   write(6,'(t5," << f(r)=exp(-0.5*(b/r)**nu+alfa*r) >> ")')
   write(6,'(t5," << eta(r)=bb/r**3) >> ")')
   write(6,'("b he4, incremento simplex",t40,2f10.6)') bhe4,dbhe4
   write(6,'("nu he4, incremento simplex",t40,2f10.6)') nuhe4,dnuhe4
   write(6,'("alfa he4, incremento simplex",t40,2f10.6)') alfahe4,dalfahe4
   write(6,'("b he3, incremento simplex",t40,2f10.6)') bhe3,dbhe3
   write(6,'("nu he3, incremento simplex",t40,2f10.6)') nuhe3,dnuhe3
   write(6,'("alfa he3, incremento simplex",t40,2f10.6)') alfahe3,dalfahe3
   write(6,'("bb backflow, incremento simplex",t40,2f10.6)') bback,dbback
   write(6,'("b mezclas, incremento simplex",t40,2f10.6)') bmix,dbmix
   write(6,'("nu mezclas, incremento simplex",t40,2f10.6)') numix,dnumix
   write(6,'("alfa mezclas, incremento simplex",t40,2f10.6)') alfamix,dalfamix
   if(namol.gt.0) then
     write(6,'(t5," << f_l(r)=exp(-0.5*(b_l/r)**nu_l+alfa*r**p4_l-p5_l*ln(r)) >> ")')
     write(6,'("lmax Legendre impureza-he4",t40,i10)') lxhe4
     do il=0,lxhe4
       write(6,'("l=",i5,t10,"b he4",t40,2f10.6)') il,bxhe4(il),dbxhe4(il)
       write(6,'("l=",i5,t10,"nu he4",t40,2f10.6)')il, nuxhe4(il),dnuxhe4(il)
       write(6,'("l=",i5,t10,"alfa he4",t40,2f10.6)') il,alfaxhe4(il),dalfaxhe4(il)
       write(6,'("l=",i5,t10,"p4 he4",t40,2f10.6)') il,p4xhe4(il),dp4xhe4(il)
       write(6,'("l=",i5,t10,"p5 he4",t40,2f10.6)') il,p5xhe4(il),dp5xhe4(il)
     enddo
     write(6,'("lmax Legendre impureza-he3",t40,i10)') lxhe3
     do il=0,lxhe3
       write(6,'("l=",i5,t10,"b he3",t40,2f10.6)') il,bxhe3(il),dbxhe3(il)
       write(6,'("l=",i5,t10,"nu he3",t40,2f10.6)')il, nuxhe3(il),dnuxhe3(il)
       write(6,'("l=",i5,t10,"alfa he3",t40,2f10.6)') il,alfaxhe3(il),dalfaxhe3(il)
       write(6,'("l=",i5,t10,"p4 he3",t40,2f10.6)') il,p4xhe3(il),dp4xhe3(il)
       write(6,'("l=",i5,t10,"p5 he3",t40,2f10.6)') il,p5xhe3(il),dp5xhe3(il)
     enddo
   endif


   if(nhe3.le.8) then
     nhe3up=nnup(nhe3)
     nhe3dw=nndw(nhe3)
   else
     nhe3up=(nhe3+1)/2
     nhe3dw=nhe3-nhe3up
   endif

   if(nhe3up.gt.nfermax.or.nhe3dw.gt.nfermax) then
      write(6,*) 'numero maximo de fermiones que se admite',nfermax
      write(6,*) 'numero de he3 con espin up ',nhe3up
      write(6,*) 'numero de he3 con espin dw ',nhe3dw
      write(6,*) 'se para el calculo'
      datosbien=.false.
   endif

   hb2he4=hb2/mhe4
   hb2he3=hb2/mhe3

   if(namol.gt.0) then
     impureza=.true.
   else
     impureza=.false.
     impurmol=.false.
   endif

   if(impureza) then
     if(namol.gt.1) then
       impurmol=.true.
     else
       impurmol=.false.
     endif
   endif

   ngatom=nhe4+nhe3
   if(impureza) then
     natom=ngatom+1
     hb2x=hb2/mx
     if(impurmol) then
        brot=hb2/momi
     else
        brot=0.0_r8
        deltaa=0.0_r8
        lxhe4=0
        lxhe3=0
     endif
   else
     natom=ngatom
     hb2x=0.0_r8
     brot=0.0_r8
     deltax=0.0_r8
     deltaa=0.0_r8
     lxhe4=0
     lxhe3=0
   endif

   ncmtras=ngatom
   if(impureza.and..not.impurfija) ncmtras=natom

   phe4(1)=0.50_r8*(bhe4**nuhe4)
   phe4(2)=nuhe4
   phe4(3)=alfahe4
   phe3(1)=0.50_r8*(bhe3**nuhe3)
   phe3(2)=nuhe3
   phe3(3)=alfahe3
   phe3(4)=bback
   pmix(1)=0.50_r8*(bmix**numix)
   pmix(2)=numix
   pmix(3)=alfamix
   if(namol.gt.0) then
     do il=0,lxhe4
       pxhe4(1,il)=0.50_r8*(bxhe4(il)**nuxhe4(il))
       pxhe4(2,il)=nuxhe4(il)
       pxhe4(3,il)=alfaxhe4(il)
       pxhe4(4,il)=p4xhe4(il)
       pxhe4(5,il)=p5xhe4(il)
     enddo
     do il=0,lxhe3
       pxhe3(1,il)=0.50_r8*(bxhe3(il)**nuxhe3(il))
       pxhe3(2,il)=nuxhe3(il)
       pxhe3(3,il)=alfaxhe3(il)
       pxhe3(4,il)=p4xhe3(il)
       pxhe3(5,il)=p5xhe3(il)
     enddo
   endif

   write(bb,'(i3)') 100+nhe4
   write(ff,'(i3)') 100+(ngatom-nhe4)
   nombre=bb(2:3)//"."//ff(2:3)//"."//molecula
   do ilen=6+nlen,16
     nombre(ilen:ilen)=espacio
   enddo

   write(6,'(//)')
   write(6,'("numero de constituyentes del sistema",t40,i10)') natom
   write(6,'("numero de atomos en la gota (he4 y he3)",t40,i10)') ngatom
   write(6,'("numero de cm que se trasladan",t40,i10)') ncmtras
   if(impureza) then
     write(6,'("hay impureza en la gota",t40,l10)') impureza
     write(6,'("nombre de la impureza",t50,a10)') molecula
     write(6,'("masa de la impureza en uma",t40,f10.6)') mx
     if(impurmol) then
       write(6,'("la impureza es una molecula",t40,l10)') impurmol
       write(6,'("momento de inercia molecular",t40,f10.6)') momi
       write(6,'("la molecula rota",t40,l10)') rotamol
     else
       write(6,'("la impureza es un atomo",t40,l10)') .not.impurmol
     endif
     if(impurfija) then
       write(6,'("la impureza no realiza traslacion",t40,l10)') impurfija
       write(6,'("constituyentes del sistema=atomos en la gota+1",t50,2i10)') & 
 &                natom,ngatom+1
       write(6,'("cm que se trasladan=atomos en la gota",t50,2i10)')          &
 &                ncmtras,ngatom
     else
       write(6,'("la impureza realiza traslacion ",t40,l10)')  .not.impurfija
       write(6,'("constituyentes del sistema=atomos en la gota+1",t50,2i10)')  &
 &                natom,ngatom+1
       write(6,'("cm que se trasladan=constituyentes del sistema",t50,2i10)')  &
 &                ncmtras,natom
     endif
   else
     write(6,'("no hay impureza en la gota",t40,l10)') .not.impureza
     write(6,'("constituyentes del sistema=atomos en la gota",t50,2i10)')      &
 &              natom,ngatom
     write(6,'("cm que se trasladan=constituyentes del sistema",t50,2i10)')    &
 &              ncmtras,natom
   endif
   write(6,*)
   if(nhe3.gt.0) then
     write(6,'("atomos de he3 up",t30,i10)') nhe3up
     write(6,'("atomos de he3 down",t30,i10)') nhe3dw
   endif
   if(opot.eq.4) then
       hb2he4=hb2he4*k2mev_bh
       hb2he3=hb2he3*k2mev_bh
       write(6,'("hb2/(2*mhe4) en meV A**2",t30,f10.6)') hb2he4
       write(6,'("hb2/(2*mhe3) en meV A**2",t30,f10.6)') hb2he3
     else
         write(6,'("hb2/(2*mhe4) en K A**2",t30,f10.6)') hb2he4
         write(6,'("hb2/(2*mhe3) en K A**2",t30,f10.6)') hb2he3
     endif

   write(6,*)
   if(impureza) then
     if(opot.eq.4) then
        hb2x=hb2x*k2mev_bh
        write(6,'("hb2/(2*mx) en meV A**2",t30,f10.6)') hb2x
     else
        write(6,'("hb2/(2*mx) en K A**2",t30,f10.6)') hb2x
     endif
     if(impurmol) then
       if(opot.eq.4) then
         brot=brot*k2mev_bh
         write(6,'("B=hb2/(2*I) en meV ",t30,f10.6)') brot
       else
         write(6,'("B=hb2/(2*I) en K ",t30,f10.6)') brot
       endif
       write(6,'("B=hb2/(2*I) en cm-1 ",t30,f10.6)') hb2cm/momi
       write(6,'("B=hb2/(2*I) en MHz ",t20,f20.10)') hb2cm/momi*cluz*1.d-4
       do jval=1,njval
         if(opot.eq.4) then
           write(6,'("J, E_J=J*(J+1)*B en meV",t28,i2,f10.5)') jval,jval*(jval+1)*brot
         else
           write(6,'("J, E_J=J*(J+1)*B en K",t28,i2,f10.5)') jval,jval*(jval+1)*brot
         endif
       enddo
     endif
   endif
   write(6,*)
   if(libre) then
     etrial=0.0_r8
     write(6,'("Calculo sin interaccion. Cambiamos etrial")')
     write(6,'("etrial energia prueba dmc",t26,f14.7)') etrial
   else
     write(6,'("Parametros he4:    0.5*(b**nu),nu,alfa",t42,3f12.5)') phe4
     write(6,'("Parametros he3:    0.5*(b**nu),nu,alfa,bb",t42,4f12.5)') phe3
     write(6,'("Parametros mezcla: 0.5*(b**nu),nu,alfa",t42,4f12.5)') pmix
     if(namol.ne.0) then
       write(6,'("Parametros impureza he4: 0.5*(b**nu),nu,alfa,p4,p5")') 
       do il=0,lxhe4
         write(6,'("l=",i3,t21,5f12.5)') il,pxhe4(:,il)
       enddo
       write(6,'("Parametros impureza he3: 0.5*(b**nu),nu,alfa,p4,p5")') 
       do il=0,lxhe3
         write(6,'("l=",i3,t21,5f12.5)') il,pxhe3(:,il)
       enddo
     endif
   endif

   if(impureza) then
    select case (opot)
      case (0)
        write(6,'("Leyendo los parametros del potencial aziz Atomo-He")')
        call leeazizgen(fichpot)
      case (1)
        write(6,'("Leyendo los parametros del potencial OCS-He")')
        call pw_leevheocs(fichpot)
      case (2)
        write(6,'("Leyendo los parametros del potencial OCS-He")')
        call hh_leevheocs(fichpot)
      case (3)
        write(6,'("Leyendo los parametros del potencial CO-He")')
        call kp_leevheco(fichpot)
      case (4)
        write(6,'("Leyendo los parametros del potencial H2p-He")')
        call bh_leevheh2m(fichpot)
      case default
        write(6,*) 'en escribedatos'
        write(6,*) 'valor de opot no valido'
        write(6,*) 'valores validos ',0,1,2,3,4
        write(6,*) 'valor leido',opot
    end select
   endif
 
   write(6,'(//)')
   write(6,'(t20,"NOMBRE DEL CALCULO:",t40,a16)') nombre



   write(6,'(//)')
   write(6,'("DATOS CALCULO EN PARALELO")')
   write(6,'("procesos en cada maquina (solo PVM)",t40,i10)') ncadapvm



   if(impurmol) then
     deallocate (atomo)
     deallocate (zatmol,matmol)
   endif

   call flush(6)

 end subroutine escribedatos


  subroutine escribein(empieza)
  logical, intent (in) :: empieza
  character (len=90) :: frase
  integer  (kind=i4) :: icont,iamol,il

  if(empieza) then
    open(unit=105,file="in.copia",status="unknown")
  else
    open(unit=5,file="in.copia",status="old")
    open(unit=105,file="in.opt",status="unknown")
    rewind(5)
  endif
  rewind(105)

   do icont=1,8
     read(5,'(a90)') frase
     write(105,'(a90)') frase
   enddo
   if(empieza) then
     read(5,*) namol
     write(105,'(i2,t22,a42)') namol,"!numero de atomos en la impureza molecular"
   else
     read(5,'(a90)') frase
     write(105,'(a90)') frase
   endif
   if(namol.gt.0) then
     do iamol=1,namol
       read(5,'(a90)')  frase
       write(105,'(a90)') frase
       read(5,'(a90)') frase
       write(105,'(a90)') frase
     enddo
     do iamol=2,namol
       read(5,'(a90)') frase
       write(105,'(a90)') frase
     enddo
     do icont=1,12
       read(5,'(a90)') frase
       write(105,'(a90)') frase
     enddo
   endif

   do icont=1,8
     read(5,'(a90)') frase
     write(105,'(a90)') frase
   enddo
   if(namol.gt.0)  then
     read(5,'(a90)') frase
     write(105,'(a90)') frase
   endif
   if(namol.gt.1) then
     read(5,'(a90)') frase
     write(105,'(a90)') frase
   endif
   do icont=1,8
     read(5,'(a90)') frase
     write(105,'(a90)') frase
   enddo

   do icont=1,6
     read(5,'(a90)') frase
     write(105,'(a90)') frase
   enddo

   if(empieza) then
     do icont=1,10
       read(5,'(a90)') frase
       write(105,'(a90)') frase
     enddo
   else
     do icont=1,10
       read(5,'(a90)') frase
     enddo
     write(105,'(f10.6,2x,f11.7,t31,a6)') bhe4,dbhe4,"!b he4"
     write(105,'(f10.6,2x,f11.7,t31,a11)') nuhe4,dnuhe4,"!nu he4 he4"
     write(105,'(f10.6,2x,f11.7,t31,a9)') alfahe4,dalfahe4,"!alfa he4"
     write(105,'(f10.6,2x,f11.7,t31,a6)') bhe3,dbhe3,"!b he3"
     write(105,'(f10.6,2x,f11.7,t31,a11)') nuhe3,dnuhe3,"!nu he3 he3"
     write(105,'(f10.6,2x,f11.7,t31,a9)') alfahe3,dalfahe3,"!alfa he3"
     write(105,'(f10.6,2x,f11.7,t31,a33)') bback,dbback,"!b backflow he3;   eta(r)=bb/r**3"
     write(105,'(f10.6,2x,f11.7,t31,a10)') bmix,dbmix,"!b mezclas"
     write(105,'(f10.6,2x,f11.7,t31,a11)') numix,dnumix,"!nu mezclas"
     write(105,'(f10.6,2x,f11.7,t31,a13)') alfamix,dalfamix,"!alfa mezclas"
   endif



   if(namol.gt.0) then
     do icont=1,6
       read(5,'(a90)') frase
       write(105,'(a90)') frase
     enddo
     if(empieza) then
       read(5,*) lxhe4
       write(105,'(i2,t22,a41)') lxhe4,"!lmax polinomios de Legendre impureza-he4"
       do il=0,lxhe4
         do icont=1,6
           read(5,'(a90)') frase
           write(105,'(a90)') frase
         enddo
       enddo
       read(5,*) lxhe3
       write(105,'(i2,t22,a41)') lxhe3,"!lmax polinomios de Legendre impureza-he3"
       do il=0,lxhe3
         do icont=1,6
           read(5,'(a90)') frase
           write(105,'(a90)') frase
         enddo
       enddo
     else
       read(5,'(a90)') frase
       write(105,'(a90)') frase
       do il=0,lxhe4
         read(5,'(a90)') frase
         write(105,'(a3,i1)') "!l=",il
         read(5,'(a90)') frase
         write(105,'(f10.6,2x,f11.7,t31,a15)') bxhe4(il),dbxhe4(il),"!b he4 impureza"
         read(5,'(a90)') frase
         write(105,'(f10.6,2x,f11.7,t31,a16)') nuxhe4(il),dnuxhe4(il),"!nu he4 impureza"
         read(5,'(a90)') frase
         write(105,'(f10.6,2x,f11.7,t31,a18)') alfaxhe4(il),dalfaxhe4(il),"!alfa he4 impureza"
         read(5,'(a90)') frase
         write(105,'(f10.6,2x,f11.7,t31,a16)') p4xhe4(il),dp4xhe4(il),"!p4 he4 impureza"
         read(5,'(a90)') frase
         write(105,'(f10.6,2x,f11.7,t31,a16)') p5xhe4(il),dp5xhe4(il),"!p5 he4 impureza"
       enddo
       read(5,'(a90)') frase
       write(105,'(a90)') frase
       do il=0,lxhe3
         read(5,'(a90)') frase
         write(105,'(a3,i1)') "!l=",il
         read(5,'(a90)') frase
         write(105,'(f10.6,2x,f11.7,t31,a15)') bxhe3(il),dbxhe3(il),"!b he3 impureza"
         read(5,'(a90)') frase
         write(105,'(f10.6,2x,f11.7,t31,a16)') nuxhe3(il),dnuxhe3(il),"!nu he3 impureza"
         read(5,'(a90)') frase
         write(105,'(f10.6,2x,f11.7,t31,a18)') alfaxhe3(il),dalfaxhe3(il),"!alfa he3 impureza"
         read(5,'(a90)') frase
         write(105,'(f10.6,2x,f11.7,t31,a16)') p4xhe3(il),dp4xhe3(il),"!p4 he3 impureza"
         read(5,'(a90)') frase
         write(105,'(f10.6,2x,f11.7,t31,a16)') p5xhe3(il),dp5xhe3(il),"!p5 he3 impureza"
       enddo
     endif


   endif

   do icont=1,6
     read(5,'(a90)') frase
     write(105,'(a90)') frase
   enddo

  if(empieza) then
    rewind(105)
    close(unit=105)
  else
    close(unit=5)
    close(unit=105)
  endif

  end subroutine escribein


 subroutine calbrot
   real(kind=r8) :: zcm
   integer(kind=i4) :: iamol

    zcm=0.0_r8
    mx=0.0_r8
    do iamol=1,namol
      zcm=zcm+matmol(iamol)*zatmol(iamol)
      mx=mx+matmol(iamol)
    enddo
    zcm=zcm/mx

    momi=0.0_r8
    do iamol=1,namol
      momi=momi+matmol(iamol)*(zatmol(iamol)-zcm)**2
    enddo

    cintr=0.0_r8
    do iamol=1,namol
      cintr(3,iamol)=zatmol(iamol)-zcm
    enddo

 end subroutine calbrot

 subroutine fecha(cabecera)
  character(len=15), intent(in) :: cabecera
  integer :: diahora(8)
  character (len=10) :: fc(3)
  character (len=1) :: dp=":",up=".",co=","
  character (len=10) :: mes (12)=                                       &
& (/"Enero     ","Febrero   ","Marzo     ","Abril     ","Mayo      ",   &
&   "Junio     ","Julio     ","Agosto    ","Septiembre","Octubre   ",   &
&   "Noviembre ","Diciembre " /)
  integer :: silee
  character (len=256) :: nombre

   call date_and_time(fc(1),fc(2),fc(3),diahora)

   open(unit=10, file="ordenador.txt",status="unknown",action="read")
   read(10,'(a)',iostat=silee) nombre
   close(10)

   write(6,'(//)')
   write(6,*)"*****************************************************"
   write(6,'(t2,a12,i2," de ",a," de ",i4,a1,2x,i2,a1,i2,a1,i2,a1,i3)')  &
&    cabecera,                                                           &
&    diahora(3),trim(mes(diahora(2))),diahora(1),co,                     &
&    diahora(5),dp,diahora(6),dp,diahora(7),up,diahora(8)
   if(silee.eq.0) write(6,'(t2,"Calculo en el ordenador: ",t27,a)') trim(nombre)
   write(6,*)"*****************************************************"

 end subroutine fecha

 subroutine tiempos
  logical, save :: inicio=.true.
  real,  save :: t1
  real :: t2
  integer(kind=i8), save :: w1, count_rate
  integer(kind=i8) :: w2
  real(kind=r8) :: wall_time
  character(len=15) :: cabecera
  integer :: silee
  character (len=256) :: nombre

   if(inicio) then
     call system('hostname > ordenador.txt')
     cabecera="Comienza el "
     call fecha(cabecera)
     call cpu_time(t1)
     call system_clock(w1, count_rate)
     inicio=.false.
   else
     cabecera="Finaliza el "
     call fecha(cabecera)
     call cpu_time(t2)
     call system_clock(w2)
     wall_time = real(w2-w1, r8) / real(count_rate, r8)
     write(6,'(/)')
     write(6,*)"*****************************************************"
     write(6,*)'tiempo de CPU en s',(t2-t1)
     write(6,*)'tiempo de CPU en m',(t2-t1)/60
     write(6,*)'tiempo de CPU en h',(t2-t1)/(60*60)
     write(6,*)'tiempo de CPU en d',(t2-t1)/(60*60*24)
     write(6,*)"*****************************************************"
     write(6,*)"*****************************************************"
     write(6,*)'tiempo de pared en s', wall_time
     write(6,*)'tiempo de pared en m', wall_time/60.0_r8
     write(6,*)'tiempo de pared en h', wall_time/3600.0_r8
     write(6,*)"*****************************************************"
     call system('rm ordenador.txt')
   endif

 end subroutine tiempos

 subroutine checkmax(valin,valmax,texto)
  integer(kind=i4), intent (in) :: valin,valmax
  character*(*) ,intent (in)  :: texto

  if(valin.gt.valmax) then
    datosbien=.false.
    write(6,'(t5,a)') texto
    write(6,*)'valor de entrada en el fichero lx',valin
    write(6,*)'valor maximo en el programa    lx',valmax
    write(6,*)'paramos el calculo'
  endif

 end subroutine checkmax

 end module mentradatos
