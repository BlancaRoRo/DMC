! driver_verifica_prereparto.f90
!
! v3-cuda-optimizacion/fase3: antes de escribir k_fase_h (histograma
! fusionado en el pipeline GPU), se verifica en CPU pura, contra la
! denssumapaso REAL (mdensidades.f90, sin modificar -- solo se le
! anadieron 3 getters de solo lectura, densgetblo_r/_c/_y, ver esa
! cabecera), que:
!
!   histograma(denssumapaso real sobre poblacion POST-reparto)
!     ==
!   histograma(poblacion PRE-reparto, pesando cada walker por nsons(i))
!
! Razon del pesado: cuando un walker se clona (nsons>1), sus copias son
! posiciones IDENTICAS al padre en este instante (el reparto solo
! duplica/reordena, no mueve nada mas) -- por eso sumar nsons(i) veces
! sobre el walker pre-reparto debe dar exactamente el mismo resultado
! que sumar 1 vez por cada una de sus nsons(i) copias post-reparto. Si
! esto se confirma bit a bit, k_fase_h puede usar nsons_p directamente
! (ya calculado y residente en el device al final del grafo) sin
! necesitar reparto en GPU ni ninguna copia H2D adicional de posiciones.
!
! Metodologia (ver MEMORY.md, "verificar contra el original"): la
! referencia es la propia denssumapaso real, llamada sobre una
! poblacion post-reparto construida con la MISMA logica de reparto que
! msteps.f90:486-517 -- no una reimplementacion aparte.
!
! nhr/nhc/nhs/rmax/cmax/smax: mismas constantes FIJAS que mdensidades.f90
! (son parametros del histograma, no vienen de in.mcv) -- replicadas
! aqui porque son private en ese modulo.
program driver_verifica_prereparto

 use mparametros
 use mtipos
 use mdensidades
 implicit none
 integer, parameter :: i4 = selected_int_kind(9)
 integer, parameter :: r8 = selected_real_kind(15,9)

 real(kind=r8), parameter :: rmax=20.0_r8
 integer(kind=i4), parameter :: nhr=2000
 real(kind=r8), parameter :: dhr=rmax/nhr
 real(kind=r8), parameter :: cmax=6.0_r8
 integer(kind=i4), parameter :: nhc=60
 real(kind=r8), parameter :: dhc=cmax/nhc
 real(kind=r8), parameter :: smax=6.0_r8
 integer(kind=i4), parameter :: nhs=60
 real(kind=r8), parameter :: dhs=smax/nhs

 integer(kind=i4), parameter :: nwpaso_pre = 500
 integer(kind=i4), parameter :: nmax_post  = nwpaso_pre*4

 type(walker), allocatable :: wsim_pre(:), wsim_post(:)
 integer(kind=i4) :: nsons(nwpaso_pre)
 integer(kind=i4) :: iw, iatom, isp, nwfin, nwrep, isons
 real(kind=r8) :: seed, seed2

 ! ---- referencia (denssumapaso real, post-reparto) ----
 real(kind=r8) :: ref_44(nhr), ref_33(nhr), ref_43(nhr)
 real(kind=r8) :: ref_i4(nhr), ref_i3(nhr), ref_ia(nhr)
 real(kind=r8) :: ref_bhe4(-nhc:nhc,nhs), ref_bhe3(-nhc:nhc,nhs), ref_bhe(-nhc:nhc,nhs)
 real(kind=r8) :: ref_ybhe4(-nhc:nhc,-nhs:nhs), ref_ybhe3(-nhc:nhc,-nhs:nhs), ref_ybhe(-nhc:nhc,-nhs:nhs)

 ! ---- propuesta (pre-reparto, pesado por nsons) ----
 real(kind=r8) :: prop_44(nhr), prop_33(nhr), prop_43(nhr)
 real(kind=r8) :: prop_i4(nhr), prop_i3(nhr), prop_ia(nhr)
 real(kind=r8) :: prop_bhe4(-nhc:nhc,nhs), prop_bhe3(-nhc:nhc,nhs), prop_bhe(-nhc:nhc,nhs)
 real(kind=r8) :: prop_ybhe4(-nhc:nhc,-nhs:nhs), prop_ybhe3(-nhc:nhc,-nhs:nhs), prop_ybhe(-nhc:nhc,-nhs:nhs)

 ! ---- prueba de confirmacion: variante que suma 1/sth SECUENCIALMENTE
 ! nsons(iw) veces (en vez de w/sth en una sola operacion), pero SIN
 ! reproducir el orden exacto del reparto (que intercala primarios y
 ! clones de walkers distintos) -- si esto SIGUE sin coincidir bit a
 ! bit con la referencia, confirma que el problema no es "una
 ! multiplicacion en vez de una suma", sino el ORDEN global de
 ! acumulacion entre walkers distintos, que exigiria reconstruir el
 ! reparto para arreglarse -- justo lo que k_fase_h quiere evitar ----
 real(kind=r8) :: prop2_bhe4(-nhc:nhc,nhs)
 real(kind=r8) :: prop2_ybhe4(-nhc:nhc,-nhs:nhs)

 logical :: todo_ok
 integer(kind=i4) :: n_dif_total

  ! ---- parametros reales del proyecto (mismos valores confirmados en
  ! toda la investigacion de fase3: nhe4=20, nhe3=0, impurmol=true, ver
  ! test_histograma.cuf y fase3-arquitecturas-alternativas.md) -- fijados
  ! a mano en vez de leedatos: leedatos exige la secuencia completa de
  ! inicializacion "paralela" (iniciaparalelo/quiensoy, mserie.f90) cuyo
  ! comportamiento fuera del lanzador real (PVM) deja natom/ngatom en 0
  ! de forma silenciosa (confirmado con prints temporales) -- denssumapaso
  ! en si no depende de COMO se fijaron estas variables, solo de sus
  ! valores, asi que fijarlas aqui directamente es equivalente y evita
  ! esa dependencia ajena al problema que se quiere verificar ----
  nhe4 = 20
  nhe3 = 0
  ngatom = nhe4 + nhe3
  impureza = .true.
  impurmol = .true.
  natom = ngatom + 1

  write(*,'(a,i0,a,i0,a,i0,a,l1,a,l1)') 'parametros reales: natom=', natom, &
    ' nhe4=', nhe4, ' ngatom=', ngatom, ' impureza=', impureza, ' impurmol=', impurmol
  call flush(6)

  ! ---- poblacion sintetica PRE-reparto: posiciones deterministas
  ! (mismo patron que test_histograma.cuf), y nsons ciclando por 0..4
  ! para cubrir muertes (0) y clones (2,3,4) ----
  allocate(wsim_pre(nwpaso_pre))
  do iw=1,nwpaso_pre
    call allocatewalker(wsim_pre(iw), natom)
    do iatom=1,natom
      seed = real(iw,r8)*0.37_r8 + real(iatom,r8)*1.91_r8
      wsim_pre(iw)%atom(iatom)%comp(1) = sin(seed)*3.0_r8
      wsim_pre(iw)%atom(iatom)%comp(2) = cos(seed*1.3_r8)*3.0_r8
      wsim_pre(iw)%atom(iatom)%comp(3) = sin(seed*0.7_r8)*3.0_r8
      wsim_pre(iw)%dwf(iatom)%comp = 0.0_r8
    enddo
    wsim_pre(iw)%delta = 0.0_r8
    wsim_pre(iw)%hb2m = 0.0_r8
    wsim_pre(iw)%sigma1 = 0.0_r8
    wsim_pre(iw)%sigma2 = 0.0_r8
    do isp=1,3
      seed2 = real(iw,r8)*0.53_r8 + real(isp,r8)*2.17_r8
      wsim_pre(iw)%sprop(isp)%comp(1) = sin(seed2)
      wsim_pre(iw)%sprop(isp)%comp(2) = cos(seed2*1.1_r8)
      wsim_pre(iw)%sprop(isp)%comp(3) = sin(seed2*0.9_r8)
    enddo
    nsons(iw) = mod(iw,5)   ! 0,1,2,3,4,0,1,2,3,4,...
  enddo

  ! ---- reparto REAL: misma logica exacta que msteps.f90:486-517
  ! (pasodmc_gpu_pipeline), sin la parte de decorrelacion de semillas
  ! (irn) porque no afecta a las posiciones que denssumapaso usa ----
  allocate(wsim_post(nmax_post))
  nwfin=0
  nwrep=0
  do iw=1,nwpaso_pre
    if (nsons(iw).gt.0) then
      nwfin=nwfin+1
      wsim_post(nwfin) = wsim_pre(iw)
      do isons=2,nsons(iw)
        nwrep=nwrep+1
        wsim_post(nwpaso_pre+nwrep) = wsim_pre(iw)
      enddo
    endif
  enddo
  do iw=1,nwrep
    nwfin=nwfin+1
    wsim_post(nwfin) = wsim_post(nwpaso_pre+iw)
  enddo

  write(*,'(a,i0,a,i0)') 'poblacion pre-reparto = ', nwpaso_pre, &
    ' -> post-reparto (nwfin) = ', nwfin

  ! ---- referencia: denssumapaso REAL sobre la poblacion post-reparto ----
  call densceroblo
  call denssumapaso(nwfin, wsim_post(1:nwfin))

  call densgetblo_r(1,ref_44); call densgetblo_r(2,ref_33); call densgetblo_r(3,ref_43)
  call densgetblo_r(4,ref_i4); call densgetblo_r(5,ref_i3); call densgetblo_r(6,ref_ia)
  call densgetblo_c(7,ref_bhe4); call densgetblo_c(8,ref_bhe3); call densgetblo_c(9,ref_bhe)
  call densgetblo_y(10,ref_ybhe4); call densgetblo_y(11,ref_ybhe3); call densgetblo_y(12,ref_ybhe)

  ! ---- propuesta: pre-reparto, pesado por nsons(i) -- replica LINEA A
  ! LINEA la geometria de denssumapaso, pero recorriendo wsim_pre y
  ! pesando el incremento por nsons(iw) en vez de recorrer copias ya
  ! materializadas ----
  prop_44=0.0_r8; prop_33=0.0_r8; prop_43=0.0_r8
  prop_i4=0.0_r8; prop_i3=0.0_r8; prop_ia=0.0_r8
  prop_bhe4=0.0_r8; prop_bhe3=0.0_r8; prop_bhe=0.0_r8
  prop_ybhe4=0.0_r8; prop_ybhe3=0.0_r8; prop_ybhe=0.0_r8
  prop2_bhe4=0.0_r8; prop2_ybhe4=0.0_r8

  call acumula_prereparto

  todo_ok = .true.
  n_dif_total = 0
  call compara_r('drb44 ', ref_44, prop_44)
  call compara_r('drb33 ', ref_33, prop_33)
  call compara_r('drb43 ', ref_43, prop_43)
  call compara_r('drbi4 ', ref_i4, prop_i4)
  call compara_r('drbi3 ', ref_i3, prop_i3)
  call compara_r('drbia ', ref_ia, prop_ia)
  call compara_c('d2bhe4 ', ref_bhe4, prop_bhe4)
  call compara_c('d2bhe3 ', ref_bhe3, prop_bhe3)
  call compara_c('d2bhe  ', ref_bhe, prop_bhe)
  call compara_y('d2ybhe4', ref_ybhe4, prop_ybhe4)
  call compara_y('d2ybhe3', ref_ybhe3, prop_ybhe3)
  call compara_y('d2ybhe ', ref_ybhe, prop_ybhe)

  if (todo_ok) then
    write(*,*) 'PASA: los 12 histogramas (pre-reparto pesado vs. denssumapaso real post-reparto) son EXACTAMENTE identicos'
  else
    write(*,'(a,i0,a)') 'FALLA: ', n_dif_total, ' diferencias encontradas (ver arriba)'
  endif

  ! ---- prueba de confirmacion (no cuenta para el veredicto de arriba):
  ! variante "secuencial sin reordenar" -- si TAMBIEN falla, confirma
  ! que el problema es el orden GLOBAL entre walkers, no la operacion
  ! multiplicar-en-vez-de-sumar en si ----
  write(*,*) '--- prueba de confirmacion: suma secuencial (nsons veces), sin reproducir el orden del reparto ---'
  block
    integer(kind=i4) :: nd1, nd2
    nd1=0; nd2=0
    do iw=1,nhs
      do isp=-nhc,nhc
        if (ref_bhe4(isp,iw)/=prop_bhe4(isp,iw)) nd1=nd1+1
        if (ref_bhe4(isp,iw)/=prop2_bhe4(isp,iw)) nd2=nd2+1
      enddo
    enddo
    write(*,'(a,i0,a,i0)') 'd2bhe4 (', size(ref_bhe4), ' bins): diferencias con w/sth (una operacion) = ', nd1
    write(*,'(a,i0)') 'd2bhe4: diferencias con suma secuencial SIN reordenar = ', nd2
  end block

contains

  subroutine compara_r(nombre_h, a, b)
   character(len=*), intent(in) :: nombre_h
   real(kind=r8), intent(in) :: a(nhr), b(nhr)
   integer(kind=i4) :: k, nd
    nd=0
    do k=1,nhr
      if (a(k)/=b(k)) then
        nd=nd+1
        if (nd.le.3) write(*,'(a,a,a,i0,a,f14.4,a,f14.4)') 'DIFERENCIA ', nombre_h, ' bin=', k, ': ref=', a(k), ' prop=', b(k)
      endif
    enddo
    if (nd.gt.0) then
      todo_ok=.false.; n_dif_total=n_dif_total+nd
    endif
  end subroutine compara_r

  subroutine compara_c(nombre_h, a, b)
   character(len=*), intent(in) :: nombre_h
   real(kind=r8), intent(in) :: a(-nhc:nhc,nhs), b(-nhc:nhc,nhs)
   integer(kind=i4) :: ix,iy,nd
    nd=0
    do iy=1,nhs
      do ix=-nhc,nhc
        if (a(ix,iy)/=b(ix,iy)) then
          nd=nd+1
          if (nd.le.3) write(*,'(a,a,a,i0,a,i0,a,es24.16,a,es24.16,a,es10.2)') 'DIFERENCIA ', nombre_h, ' ix=', ix, ' iy=', iy, ': ref=', a(ix,iy), ' prop=', b(ix,iy), ' delta=', a(ix,iy)-b(ix,iy)
        endif
      enddo
    enddo
    if (nd.gt.0) then
      todo_ok=.false.; n_dif_total=n_dif_total+nd
    endif
  end subroutine compara_c

  subroutine compara_y(nombre_h, a, b)
   character(len=*), intent(in) :: nombre_h
   real(kind=r8), intent(in) :: a(-nhc:nhc,-nhs:nhs), b(-nhc:nhc,-nhs:nhs)
   integer(kind=i4) :: ix,iy,nd
    nd=0
    do iy=-nhs,nhs
      do ix=-nhc,nhc
        if (a(ix,iy)/=b(ix,iy)) then
          nd=nd+1
          if (nd.le.3) write(*,'(a,a,a,i0,a,i0,a,es24.16,a,es24.16,a,es10.2)') 'DIFERENCIA ', nombre_h, ' ix=', ix, ' iy=', iy, ': ref=', a(ix,iy), ' prop=', b(ix,iy), ' delta=', a(ix,iy)-b(ix,iy)
        endif
      enddo
    enddo
    if (nd.gt.0) then
      todo_ok=.false.; n_dif_total=n_dif_total+nd
    endif
  end subroutine compara_y

  ! ---- replica EXACTA (misma formula, mismos indices) del cuerpo de
  ! denssumapaso, recorriendo wsim_pre y pesando por nsons(iw) ----
  subroutine acumula_prereparto
   type(vec3) :: rtemp
   real(kind=r8) :: rij,cth,sth,dnor,cval,sval,w
   real(kind=r8) :: rhe(3*ngatom)
   integer(kind=i4) :: ia,ja,izatom,ihr,ihc,ihs,iwl

    do iwl=1,nwpaso_pre
      if (nsons(iwl).le.0) cycle
      w = real(nsons(iwl),r8)

      do ia=1,nhe4-1
        do ja=ia+1,nhe4
          rtemp=wsim_pre(iwl)%atom(ia)-wsim_pre(iwl)%atom(ja)
          rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
          ihr=int(rij/dhr)+1; ihr=min(ihr,nhr)
          prop_44(ihr)=prop_44(ihr)+w
        enddo
      enddo

      do ia=nhe4+1,ngatom
        do ja=ia+1,ngatom
          rtemp=wsim_pre(iwl)%atom(ia)-wsim_pre(iwl)%atom(ja)
          rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
          ihr=int(rij/dhr)+1; ihr=min(ihr,nhr)
          prop_33(ihr)=prop_33(ihr)+w
        enddo
      enddo

      do ia=1,nhe4
        do ja=nhe4+1,ngatom
          rtemp=wsim_pre(iwl)%atom(ia)-wsim_pre(iwl)%atom(ja)
          rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
          ihr=int(rij/dhr)+1; ihr=min(ihr,nhr)
          prop_43(ihr)=prop_43(ihr)+w
        enddo
      enddo

      if (impureza) then
        if (impurmol) then
          dnor=sqrt(dot_product(wsim_pre(iwl)%sprop(3)%comp,wsim_pre(iwl)%sprop(3)%comp))
          call ccuerpo(wsim_pre(iwl),rhe)
          izatom=3
        endif

        do ia=1,nhe4
          rtemp=wsim_pre(iwl)%atom(ia)-wsim_pre(iwl)%atom(natom)
          rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
          ihr=int(rij/dhr)+1; ihr=min(ihr,nhr)
          prop_i4(ihr)=prop_i4(ihr)+w
          prop_ia(ihr)=prop_ia(ihr)+w
          if (impurmol) then
            cval=dot_product(rtemp%comp,wsim_pre(iwl)%sprop(3)%comp)/dnor
            cth=cval/rij; sth=sqrt(1.0_r8-cth**2); sval=rij*sth
            if (cval.gt.0.0_r8) then
              ihc=int(cval/dhc)+1; ihc=min(ihc,nhc)
            else
              ihc=int(cval/dhc)-1; ihc=max(ihc,-nhc)
            endif
            ihs=int(sval/dhs)+1; ihs=min(ihs,nhs)
            prop_bhe4(ihc,ihs)=prop_bhe4(ihc,ihs)+w/sth
            prop_bhe(ihc,ihs)=prop_bhe(ihc,ihs)+w/sth
            block
              integer(kind=i4) :: kseq
              do kseq=1,nsons(iwl)
                prop2_bhe4(ihc,ihs)=prop2_bhe4(ihc,ihs)+1.0_r8/sth
              enddo
            end block
            if (rhe(izatom-1).lt.0.0_r8) then
              ihs=int(-sval/dhs)-1; ihs=max(ihs,-nhs)
            endif
            prop_ybhe4(ihc,ihs)=prop_ybhe4(ihc,ihs)+w/sth
            prop_ybhe(ihc,ihs)=prop_ybhe(ihc,ihs)+w/sth
            block
              integer(kind=i4) :: kseq
              do kseq=1,nsons(iwl)
                prop2_ybhe4(ihc,ihs)=prop2_ybhe4(ihc,ihs)+1.0_r8/sth
              enddo
            end block
            izatom=izatom+3
          endif
        enddo

        do ia=nhe4+1,ngatom
          rtemp=wsim_pre(iwl)%atom(ia)-wsim_pre(iwl)%atom(natom)
          rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
          ihr=int(rij/dhr)+1; ihr=min(ihr,nhr)
          prop_i3(ihr)=prop_i3(ihr)+w
          prop_ia(ihr)=prop_ia(ihr)+w
          if (impurmol) then
            cval=dot_product(rtemp%comp,wsim_pre(iwl)%sprop(3)%comp)/dnor
            cth=cval/rij; sth=sqrt(1.0_r8-cth**2); sval=rij*sth
            if (cval.gt.0.0_r8) then
              ihc=int(cval/dhc)+1; ihc=min(ihc,nhc)
            else
              ihc=int(cval/dhc)-1; ihc=max(ihc,-nhc)
            endif
            ihs=int(sval/dhs)+1; ihs=min(ihs,nhs)
            prop_bhe3(ihc,ihs)=prop_bhe3(ihc,ihs)+w/sth
            prop_bhe(ihc,ihs)=prop_bhe(ihc,ihs)+w/sth
            if (rhe(izatom-1).lt.0.0_r8) then
              ihs=int(-sval/dhs)-1; ihs=max(ihs,-nhs)
            endif
            prop_ybhe3(ihc,ihs)=prop_ybhe3(ihc,ihs)+w/sth
            prop_ybhe(ihc,ihs)=prop_ybhe(ihc,ihs)+w/sth
            izatom=izatom+3
          endif
        enddo
      endif

    enddo

  end subroutine acumula_prereparto

end program driver_verifica_prereparto
