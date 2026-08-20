program qmccluster

 use mentradatos
 use mmontecarlo
 use mminimiza
 use mparametros
 use mparalelo

 implicit none
 integer, parameter :: r8=selected_real_kind(15,9)

  real(kind=r8) :: emcv(2)
  logical :: soydire

   call iniciaparalelo

   call quiensoy(soydire)

   if(soydire) then
     call leedatos
     call escribedatos
   endif

   call iniprocesos

   call reparteentrada
   call repartepotencial

   call inimontecarlo

   call compruebatodos

   call iniwalkers

   if(soydire) call tiempos
     
   select case (opcion)
    case (0)
      call checkder
    case (1)
      call mcv(emcv)
    case (2,3)
     call calmin
    case (4)
     call dmc
    end select

   if(soydire) call tiempos
     
    call finwalkers
    call fincalculo

end program qmccluster
