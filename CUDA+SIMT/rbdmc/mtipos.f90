module mtipos

 implicit none
 ! Usando valores de kind estándar para compatibilidad
 integer, private, parameter :: i4=4
 integer, private, parameter :: i8=8
 integer, private, parameter :: r8=selected_real_kind(15,9)
 ! r16 eliminado - usar r8 para compatibilidad con nvfortran

 ! ============================================================
 ! SOA (Structure of Arrays) para comunicación con GPU/CUDA
 ! Declaraciones de variables globales para SOA
 ! ============================================================

 ! Variables globales para SOA
 integer(kind=i4), private, save :: soa_nwalkers = 0
 integer(kind=i4), private, save :: soa_natoms = 0
 logical, private, save :: soa_allocated = .false.

 ! Arrays SOA para GPU - usando pointer para permitir asignacion de punteros
 real(kind=r8), private, save, pointer :: soa_atom(:,:,:) => null()    ! (3, natom, 2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_dwf(:,:,:) => null()     ! (3, natom, 2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_delta(:,:) => null()     ! (natom, 2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_hb2m(:,:) => null()      ! (natom, 2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_sigma1(:,:) => null()    ! (natom, 2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_sigma2(:,:) => null()    ! (natom, 2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_sprop(:,:,:) => null()   ! (3, 3, 2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_dangle(:) => null()      ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_b(:) => null()           ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_sig1rot(:) => null()     ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_sig2rot(:) => null()     ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_sig1hrot(:) => null()    ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_sig2hrot(:) => null()    ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_dphi(:,:) => null()      ! (2, 2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_eje0(:,:) => null()      ! (3, 2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_pos0(:,:) => null()      ! (3, 2*nwalkers)
 ! Datos de vloc (lw)
 real(kind=r8), private, save, pointer :: soa_wf(:) => null()          ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_wfhe4(:) => null()       ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_wfhe3(:) => null()       ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_wfm(:) => null()         ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_wfx(:) => null()         ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_kin(:) => null()         ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_pot(:) => null()         ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_ene(:) => null()         ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_erot(:) => null()        ! (2*nwalkers)
 real(kind=r8), private, save, pointer :: soa_eimp(:) => null()        ! (2*nwalkers)
 integer(kind=i4), private, save, pointer :: soa_signoup(:) => null()  ! (2*nwalkers)
 integer(kind=i4), private, save, pointer :: soa_signodw(:) => null()  ! (2*nwalkers)
 integer(kind=i4), allocatable, target, save :: soa_nsons(:)

 type :: vec3
   real (kind=r8) :: comp(3)
 end type

 type :: vloc
   real(kind=r8) :: wf
   real(kind=r8) :: wfhe4,wfhe3,wfm,wfx
!  real(kind=r8) :: wf,wfhe4,wfhe3,wfm,wfx
   real(kind=r8) :: kin,pot,ene,erot,eimp
   integer(kind=i4) :: signoup,signodw
 end type

 type :: walker
   type (vloc) :: lw
   type (vec3), allocatable :: atom(:),dwf(:)
   real (kind=r8), allocatable :: delta(:),hb2m(:),sigma1(:),sigma2(:)
   type (vec3) :: sprop(3)
   real (kind=r8) :: dangle,b,sig1rot,sig2rot,sig1hrot,sig2hrot
   real (kind=r8) :: dphi(2)
   type (vec3) :: eje0,pos0
   integer (kind=i4) :: nsons
 end type

 interface assignment (=)
   module procedure inicivec3
   module procedure copiavec3
   module procedure copialoc
   module procedure copiawalker
 end interface

 interface operator (+)
   module procedure sumavec3
 end interface

 interface operator (-)
   module procedure restavec3
 end interface

 interface operator (*)
   module procedure escporvec3
   module procedure vec3poresc
   module procedure prodvec
 end interface

 contains

  function escporvec3(x,v2) result (v1)
   real(kind=r8), intent (in) :: x
   type(vec3), intent (in) :: v2
   type(vec3) :: v1

    v1%comp=x*v2%comp

  end function escporvec3

  function vec3poresc(v2,x) result (v1)
   real(kind=r8), intent (in) :: x
   type(vec3), intent (in) :: v2
   type(vec3) :: v1

    v1%comp=v2%comp*x

  end function vec3poresc

  function prodvec(v2,v3) result (v1)
   type(vec3), intent (in) :: v2,v3
   type(vec3) :: v1

   v1%comp(1)=v2%comp(2)*v3%comp(3)-v2%comp(3)*v3%comp(2)
   v1%comp(2)=v2%comp(3)*v3%comp(1)-v2%comp(1)*v3%comp(3)
   v1%comp(3)=v2%comp(1)*v3%comp(2)-v2%comp(2)*v3%comp(1)


  end function prodvec

  function restavec3(v2,v3) result (v1)
   type(vec3), intent (in) :: v2,v3
   type(vec3) :: v1

    v1%comp=v2%comp-v3%comp

  end function restavec3

  function sumavec3(v2,v3) result (v1)
   type(vec3), intent (in) :: v2,v3
   type(vec3) :: v1

    v1%comp=v2%comp+v3%comp

  end function sumavec3

  subroutine inicivec3(v1,e)
   real(kind=r8), intent (in) :: e
   type(vec3), intent (out) :: v1

     v1%comp=e

  end subroutine inicivec3

  subroutine copiavec3(v1,v2)
   type (vec3), intent (out) :: v1
   type (vec3), intent (in) :: v2

    v1%comp=v2%comp

  end subroutine copiavec3

  subroutine copialoc(l1,l2)
    type (vloc), intent (out) :: l1
    type (vloc), intent (in) :: l2

      l1%wf   =l2%wf
      l1%wfhe4=l2%wfhe4
      l1%wfhe3=l2%wfhe3
      l1%wfm  =l2%wfm
      l1%wfx  =l2%wfx
      l1%kin  =l2%kin
      l1%pot  =l2%pot
      l1%ene  =l2%ene
      l1%erot  =l2%erot
      l1%eimp  =l2%eimp
      l1%signoup=l2%signoup
      l1%signodw=l2%signodw

  end subroutine copialoc

  subroutine copiawalker(w1,w2)
   type (walker), intent (inout) :: w1
   type (walker), intent (in) :: w2

    w1%atom=w2%atom
    w1%dwf =w2%dwf
    w1%lw  =w2%lw
    w1%delta=w2%delta
    w1%hb2m=w2%hb2m
    w1%sigma1=w2%sigma1
    w1%sigma2=w2%sigma2
    w1%sprop=w2%sprop
    w1%dangle=w2%dangle
    w1%b=w2%b
    w1%sig1rot=w2%sig1rot
    w1%sig2rot=w2%sig2rot
    w1%sig1hrot=w2%sig1hrot
    w1%sig2hrot=w2%sig2hrot
    w1%dphi=w2%dphi
    w1%eje0=w2%eje0
    w1%pos0=w2%pos0

  end subroutine copiawalker

  subroutine allocatewalker(w,n)
   type (walker), intent(out) :: w
   integer (kind=i4), intent(in) :: n

    allocate(w%atom(n))
    allocate(w%dwf(n))
    allocate(w%delta(n))
    allocate(w%hb2m(n))
    allocate(w%sigma1(n))
    allocate(w%sigma2(n))

  end subroutine allocatewalker

  subroutine deallocatewalker(w)
   type (walker) :: w

    deallocate(w%atom)
    deallocate(w%dwf)
    deallocate(w%delta)
    deallocate(w%hb2m)
    deallocate(w%sigma1)
    deallocate(w%sigma2)

  end subroutine deallocatewalker


  subroutine allocate_walkers_soa(nw, na)
   integer(kind=i4), intent(in) :: nw, na
   integer :: ierr

   if (soa_allocated) call deallocate_walkers_soa

   soa_nwalkers = nw
   soa_natoms = na

   allocate(soa_atom(3, na, 2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_atom")')

   allocate(soa_dwf(3, na, 2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_dwf")')

   allocate(soa_delta(na, 2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_delta")')

   allocate(soa_hb2m(na, 2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_hb2m")')

   allocate(soa_sigma1(na, 2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_sigma1")')

   allocate(soa_sigma2(na, 2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_sigma2")')

   allocate(soa_sprop(3, 3, 2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_sprop")')

   allocate(soa_dangle(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_dangle")')

   allocate(soa_b(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_b")')

   allocate(soa_sig1rot(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_sig1rot")')

   allocate(soa_sig2rot(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_sig2rot")')

   allocate(soa_sig1hrot(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_sig1hrot")')

   allocate(soa_sig2hrot(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_sig2hrot")')

   allocate(soa_dphi(2, 2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_dphi")')

   allocate(soa_eje0(3, 2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_eje0")')

   allocate(soa_pos0(3, 2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_pos0")')

   allocate(soa_wf(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_wf")')

   allocate(soa_wfhe4(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_wfhe4")')

   allocate(soa_wfhe3(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_wfhe3")')

   allocate(soa_wfm(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_wfm")')

   allocate(soa_wfx(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_wfx")')

   allocate(soa_kin(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_kin")')

   allocate(soa_pot(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_pot")')

   allocate(soa_ene(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_ene")')

   allocate(soa_erot(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_erot")')

   allocate(soa_eimp(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_eimp")')

   allocate(soa_signoup(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_signoup")')

   allocate(soa_signodw(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_signodw")')

   allocate(soa_nsons(2*nw), stat=ierr)
   if (ierr /= 0) write(6,'("Error allocating soa_nsons")')

   soa_allocated = .true.

  end subroutine allocate_walkers_soa

  subroutine deallocate_walkers_soa

   if (.not. soa_allocated) return

   deallocate(soa_atom)
   deallocate(soa_dwf)
   deallocate(soa_delta)
   deallocate(soa_hb2m)
   deallocate(soa_sigma1)
   deallocate(soa_sigma2)
   deallocate(soa_sprop)
   deallocate(soa_dangle)
   deallocate(soa_b)
   deallocate(soa_sig1rot)
   deallocate(soa_sig2rot)
   deallocate(soa_sig1hrot)
   deallocate(soa_sig2hrot)
   deallocate(soa_dphi)
   deallocate(soa_eje0)
   deallocate(soa_pos0)
   deallocate(soa_wf)
   deallocate(soa_wfhe4)
   deallocate(soa_wfhe3)
   deallocate(soa_wfm)
   deallocate(soa_wfx)
   deallocate(soa_kin)
   deallocate(soa_pot)
   deallocate(soa_ene)
   deallocate(soa_erot)
   deallocate(soa_eimp)
   deallocate(soa_signoup)
   deallocate(soa_signodw)
   if (allocated(soa_nsons)) deallocate(soa_nsons)

   soa_nwalkers = 0
   soa_natoms = 0
   soa_allocated = .false.

  end subroutine deallocate_walkers_soa

  subroutine aos_to_soa(wsim, nw, na)
   type(walker), intent(in) :: wsim(:)
   integer(kind=i4), intent(in) :: nw, na
   integer(kind=i4) :: iwalker, iatom

   if (.not. soa_allocated) then
     write(6,'("ERROR: SOA no allocated en aos_to_soa")')
     return
   endif

   if (size(wsim) < 2*nw) then
     write(6,'("ERROR: Tamaño de wsim insuficiente en aos_to_soa")')
     return
   endif

   do iwalker = 1, 2*nw
     ! atom positions
     do iatom = 1, na
       soa_atom(1, iatom, iwalker) = wsim(iwalker)%atom(iatom)%comp(1)
       soa_atom(2, iatom, iwalker) = wsim(iwalker)%atom(iatom)%comp(2)
       soa_atom(3, iatom, iwalker) = wsim(iwalker)%atom(iatom)%comp(3)
       ! dwf
       soa_dwf(1, iatom, iwalker) = wsim(iwalker)%dwf(iatom)%comp(1)
       soa_dwf(2, iatom, iwalker) = wsim(iwalker)%dwf(iatom)%comp(2)
       soa_dwf(3, iatom, iwalker) = wsim(iwalker)%dwf(iatom)%comp(3)
       ! scalars per atom
       soa_delta(iatom, iwalker) = wsim(iwalker)%delta(iatom)
       soa_hb2m(iatom, iwalker) = wsim(iwalker)%hb2m(iatom)
       soa_sigma1(iatom, iwalker) = wsim(iwalker)%sigma1(iatom)
       soa_sigma2(iatom, iwalker) = wsim(iwalker)%sigma2(iatom)
     enddo

     ! sprop (3 vec3)
     do iatom = 1, 3
       soa_sprop(1, iatom, iwalker) = wsim(iwalker)%sprop(iatom)%comp(1)
       soa_sprop(2, iatom, iwalker) = wsim(iwalker)%sprop(iatom)%comp(2)
       soa_sprop(3, iatom, iwalker) = wsim(iwalker)%sprop(iatom)%comp(3)
     enddo

     ! scalars per walker
     soa_dangle(iwalker) = wsim(iwalker)%dangle
     soa_b(iwalker) = wsim(iwalker)%b
     soa_sig1rot(iwalker) = wsim(iwalker)%sig1rot
     soa_sig2rot(iwalker) = wsim(iwalker)%sig2rot
     soa_sig1hrot(iwalker) = wsim(iwalker)%sig1hrot
     soa_sig2hrot(iwalker) = wsim(iwalker)%sig2hrot
     soa_dphi(1, iwalker) = wsim(iwalker)%dphi(1)
     soa_dphi(2, iwalker) = wsim(iwalker)%dphi(2)

     ! eje0 and pos0
     soa_eje0(1, iwalker) = wsim(iwalker)%eje0%comp(1)
     soa_eje0(2, iwalker) = wsim(iwalker)%eje0%comp(2)
     soa_eje0(3, iwalker) = wsim(iwalker)%eje0%comp(3)
     soa_pos0(1, iwalker) = wsim(iwalker)%pos0%comp(1)
     soa_pos0(2, iwalker) = wsim(iwalker)%pos0%comp(2)
     soa_pos0(3, iwalker) = wsim(iwalker)%pos0%comp(3)

     ! vloc data (lw)
     soa_wf(iwalker) = wsim(iwalker)%lw%wf
     soa_wfhe4(iwalker) = wsim(iwalker)%lw%wfhe4
     soa_wfhe3(iwalker) = wsim(iwalker)%lw%wfhe3
     soa_wfm(iwalker) = wsim(iwalker)%lw%wfm
     soa_wfx(iwalker) = wsim(iwalker)%lw%wfx
     soa_kin(iwalker) = wsim(iwalker)%lw%kin
     soa_pot(iwalker) = wsim(iwalker)%lw%pot
     soa_ene(iwalker) = wsim(iwalker)%lw%ene
     soa_erot(iwalker) = wsim(iwalker)%lw%erot
     soa_eimp(iwalker) = wsim(iwalker)%lw%eimp
     soa_signoup(iwalker) = wsim(iwalker)%lw%signoup
     soa_signodw(iwalker) = wsim(iwalker)%lw%signodw
     soa_nsons(iwalker) = wsim(iwalker)%nsons
   enddo

  end subroutine aos_to_soa

  subroutine soa_to_aos(wsim, nw, na)
   type(walker), intent(inout) :: wsim(:)
   integer(kind=i4), intent(in) :: nw, na
   integer(kind=i4) :: iwalker, iatom

   if (.not. soa_allocated) then
     write(6,'("ERROR: SOA no allocated en soa_to_aos")')
     return
   endif

   if (size(wsim) < 2*nw) then
     write(6,'("ERROR: Tamaño de wsim insuficiente en soa_to_aos")')
     return
   endif

   do iwalker = 1, 2*nw
     ! atom positions
     do iatom = 1, na
       wsim(iwalker)%atom(iatom)%comp(1) = soa_atom(1, iatom, iwalker)
       wsim(iwalker)%atom(iatom)%comp(2) = soa_atom(2, iatom, iwalker)
       wsim(iwalker)%atom(iatom)%comp(3) = soa_atom(3, iatom, iwalker)
       ! dwf
       wsim(iwalker)%dwf(iatom)%comp(1) = soa_dwf(1, iatom, iwalker)
       wsim(iwalker)%dwf(iatom)%comp(2) = soa_dwf(2, iatom, iwalker)
       wsim(iwalker)%dwf(iatom)%comp(3) = soa_dwf(3, iatom, iwalker)
       ! scalars per atom
       wsim(iwalker)%delta(iatom) = soa_delta(iatom, iwalker)
       wsim(iwalker)%hb2m(iatom) = soa_hb2m(iatom, iwalker)
       wsim(iwalker)%sigma1(iatom) = soa_sigma1(iatom, iwalker)
       wsim(iwalker)%sigma2(iatom) = soa_sigma2(iatom, iwalker)
     enddo

     ! sprop (3 vec3)
     do iatom = 1, 3
       wsim(iwalker)%sprop(iatom)%comp(1) = soa_sprop(1, iatom, iwalker)
       wsim(iwalker)%sprop(iatom)%comp(2) = soa_sprop(2, iatom, iwalker)
       wsim(iwalker)%sprop(iatom)%comp(3) = soa_sprop(3, iatom, iwalker)
     enddo

     ! scalars per walker
     wsim(iwalker)%dangle = soa_dangle(iwalker)
     wsim(iwalker)%b = soa_b(iwalker)
     wsim(iwalker)%sig1rot = soa_sig1rot(iwalker)
     wsim(iwalker)%sig2rot = soa_sig2rot(iwalker)
     wsim(iwalker)%sig1hrot = soa_sig1hrot(iwalker)
     wsim(iwalker)%sig2hrot = soa_sig2hrot(iwalker)
     wsim(iwalker)%dphi(1) = soa_dphi(1, iwalker)
     wsim(iwalker)%dphi(2) = soa_dphi(2, iwalker)

     ! eje0 and pos0
     wsim(iwalker)%eje0%comp(1) = soa_eje0(1, iwalker)
     wsim(iwalker)%eje0%comp(2) = soa_eje0(2, iwalker)
     wsim(iwalker)%eje0%comp(3) = soa_eje0(3, iwalker)
     wsim(iwalker)%pos0%comp(1) = soa_pos0(1, iwalker)
     wsim(iwalker)%pos0%comp(2) = soa_pos0(2, iwalker)
     wsim(iwalker)%pos0%comp(3) = soa_pos0(3, iwalker)

     ! vloc data (lw)
     wsim(iwalker)%lw%wf = soa_wf(iwalker)
     wsim(iwalker)%lw%wfhe4 = soa_wfhe4(iwalker)
     wsim(iwalker)%lw%wfhe3 = soa_wfhe3(iwalker)
     wsim(iwalker)%lw%wfm = soa_wfm(iwalker)
     wsim(iwalker)%lw%wfx = soa_wfx(iwalker)
     wsim(iwalker)%lw%kin = soa_kin(iwalker)
     wsim(iwalker)%lw%pot = soa_pot(iwalker)
     wsim(iwalker)%lw%ene = soa_ene(iwalker)
     wsim(iwalker)%lw%erot = soa_erot(iwalker)
     wsim(iwalker)%lw%eimp = soa_eimp(iwalker)
     wsim(iwalker)%lw%signoup = soa_signoup(iwalker)
     wsim(iwalker)%lw%signodw = soa_signodw(iwalker)
     wsim(iwalker)%nsons = soa_nsons(iwalker)
   enddo

  end subroutine soa_to_aos

  ! Funciones para obtener punteros a los arrays SOA (para CUDA)
  subroutine get_soa_pointers( &
       p_atom, p_dwf, p_delta, p_hb2m, p_sigma1, p_sigma2, &
       p_sprop, p_dangle, p_b, p_sig1rot, p_sig2rot, &
       p_sig1hrot, p_sig2hrot, p_dphi, p_eje0, p_pos0, &
       p_wf, p_wfhe4, p_wfhe3, p_wfm, p_wfx, &
       p_kin, p_pot, p_ene, p_erot, p_eimp, &
       p_signoup, p_signodw, p_nsons, nw, na)

   real(kind=r8), pointer, intent(out) :: p_atom(:,:,:)
   real(kind=r8), pointer, intent(out) :: p_dwf(:,:,:)
   real(kind=r8), pointer, intent(out) :: p_delta(:,:)
   real(kind=r8), pointer, intent(out) :: p_hb2m(:,:)
   real(kind=r8), pointer, intent(out) :: p_sigma1(:,:)
   real(kind=r8), pointer, intent(out) :: p_sigma2(:,:)
   real(kind=r8), pointer, intent(out) :: p_sprop(:,:,:)
   real(kind=r8), pointer, intent(out) :: p_dangle(:)
   real(kind=r8), pointer, intent(out) :: p_b(:)
   real(kind=r8), pointer, intent(out) :: p_sig1rot(:)
   real(kind=r8), pointer, intent(out) :: p_sig2rot(:)
   real(kind=r8), pointer, intent(out) :: p_sig1hrot(:)
   real(kind=r8), pointer, intent(out) :: p_sig2hrot(:)
   real(kind=r8), pointer, intent(out) :: p_dphi(:,:)
   real(kind=r8), pointer, intent(out) :: p_eje0(:,:)
   real(kind=r8), pointer, intent(out) :: p_pos0(:,:)
   real(kind=r8), pointer, intent(out) :: p_wf(:)
   real(kind=r8), pointer, intent(out) :: p_wfhe4(:)
   real(kind=r8), pointer, intent(out) :: p_wfhe3(:)
   real(kind=r8), pointer, intent(out) :: p_wfm(:)
   real(kind=r8), pointer, intent(out) :: p_wfx(:)
   real(kind=r8), pointer, intent(out) :: p_kin(:)
   real(kind=r8), pointer, intent(out) :: p_pot(:)
   real(kind=r8), pointer, intent(out) :: p_ene(:)
   real(kind=r8), pointer, intent(out) :: p_erot(:)
   real(kind=r8), pointer, intent(out) :: p_eimp(:)
   integer(kind=i4), pointer, intent(out) :: p_signoup(:)
   integer(kind=i4), pointer, intent(out) :: p_signodw(:)
   integer(kind=i4), intent(out) :: nw, na
   integer(kind=i4), pointer, intent(out) :: p_nsons(:)

   if (.not. soa_allocated) then
     write(6,'("ERROR: SOA no allocated en get_soa_pointers")')
     nw = 0
     na = 0
     return
   endif

   p_atom => soa_atom
   p_dwf => soa_dwf
   p_delta => soa_delta
   p_hb2m => soa_hb2m
   p_sigma1 => soa_sigma1
   p_sigma2 => soa_sigma2
   p_sprop => soa_sprop
   p_dangle => soa_dangle
   p_b => soa_b
   p_sig1rot => soa_sig1rot
   p_sig2rot => soa_sig2rot
   p_sig1hrot => soa_sig1hrot
   p_sig2hrot => soa_sig2hrot
   p_dphi => soa_dphi
   p_eje0 => soa_eje0
   p_pos0 => soa_pos0
   p_wf => soa_wf
   p_wfhe4 => soa_wfhe4
   p_wfhe3 => soa_wfhe3
   p_wfm => soa_wfm
   p_wfx => soa_wfx
   p_kin => soa_kin
   p_pot => soa_pot
   p_ene => soa_ene
   p_erot => soa_erot
   p_eimp => soa_eimp
   p_signoup => soa_signoup
   p_signodw => soa_signodw
   p_nsons   => soa_nsons

   nw = soa_nwalkers
   na = soa_natoms

  end subroutine get_soa_pointers

  ! Funcion para verificar si SOA esta allocated
  function is_soa_allocated() result(res)
   logical :: res
   res = soa_allocated
  end function is_soa_allocated

end module mtipos
