PROGRAM test_getenv
        character(len=256) :: ordenador
  call system('hostname > pepe')
! status=system('hostname')
  call get_environment_variable("hostname",ordenador)
  write(*,*) trim(ordenador)

END PROGRAM
