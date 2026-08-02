module mwavef

 use mparametros
 use mtipos
 use mangwavef
 use mvaziz
 use mvmolecula
 use mrotaciones
 use mlineal
 use msistref

 implicit none
 integer, private, parameter :: i4=selected_int_kind(9)
 integer, private, parameter :: r8=selected_real_kind(15,9)
 
 real, private, parameter :: umax=200.0_r8, umin=-200.0_r8

contains

 subroutine hpsi(w1)
  type (walker), intent (inout) :: w1

  if(libre) then
   call valibre(w1)
  else
    call derananum(w1)
    call vpot(w1)
    w1%lw%ene=w1%lw%kin+w1%lw%pot
  endif

! write(*,*) 'wf',w1%lw%wf
! write(*,*) 'wfhe4',w1%lw%wfhe4
! write(*,*) 'wfhe3',w1%lw%wfhe3
! write(*,*) 'wfm',w1%lw%wfm
! write(*,*) 'wfx',w1%lw%wfx
! write(*,*) 'ene',w1%lw%ene
! write(*,*) 'pot',w1%lw%pot
! write(*,*) 'kin',w1%lw%kin

 end subroutine hpsi

 subroutine  derananum(w1)
  type(walker), intent (inout) :: w1
  type(vec3)    :: d1wfhe4(nhe4),d1wfhe3(nhe3),d1wfm(ngatom),d1wfx(natom)
  real(kind=r8) :: d2wfhe4(nhe4),d2wfhe3(nhe3),d2wfm(ngatom),d2wfx(natom)
  real(kind=r8) :: d1zwfx(2),d2zwfx
  real(kind=r8) :: der2
  integer(kind=i4) :: ihe3,iatom

   call wavef(w1)
   call derwavefhe4(w1,d1wfhe4,d2wfhe4)
   call derwavefhe3(w1,d1wfhe3,d2wfhe3)
   call derwavefm(w1,d1wfm,d2wfm)
   call derwavefx(w1,d1wfx,d2wfx,d1zwfx,d2zwfx)

   w1%lw%kin=0.0_r8
   do iatom=1,nhe4
     w1%dwf(iatom)=d1wfhe4(iatom)+d1wfm(iatom)+d1wfx(iatom)
     der2=d2wfhe4(iatom)+d2wfm(iatom)+d2wfx(iatom)                    &
 &       +2.0_r8*dot_product(d1wfhe4(iatom)%comp,d1wfm(iatom)%comp)   &
 &       +2.0_r8*dot_product(d1wfhe4(iatom)%comp,d1wfx(iatom)%comp)   &
 &       +2.0_r8*dot_product(d1wfm(iatom)%comp,d1wfx(iatom)%comp)
     w1%lw%kin=w1%lw%kin-w1%hb2m(iatom)*der2
   enddo

   do ihe3=1,nhe3
     iatom=nhe4+ihe3
     w1%dwf(iatom)=d1wfhe3(ihe3)+d1wfm(iatom)+d1wfx(iatom)
     der2=d2wfhe3(ihe3)+d2wfm(iatom)+d2wfx(iatom)                     &
 &       +2.0_r8*dot_product(d1wfhe3(ihe3)%comp,d1wfm(iatom)%comp)    &
 &       +2.0_r8*dot_product(d1wfhe3(ihe3)%comp,d1wfx(iatom)%comp)    &
 &       +2.0_r8*dot_product(d1wfm(iatom)%comp,d1wfx(iatom)%comp)
     w1%lw%kin=w1%lw%kin-w1%hb2m(iatom)*der2
   enddo

   if(.not.impurfija) then
     w1%dwf(natom)=d1wfx(natom)
     w1%lw%kin=w1%lw%kin-w1%hb2m(natom)*d2wfx(natom)
     w1%lw%eimp=-w1%hb2m(natom)*d2wfx(natom)
   else
     w1%lw%eimp=0.0_r8
   endif
   if(rotamol) then
     w1%dphi(:)=d1zwfx(:)
     w1%lw%kin=w1%lw%kin-w1%b*d2zwfx
     w1%lw%erot=-w1%b*d2zwfx
   else
     w1%lw%erot=0.0_r8
   endif

 end subroutine derananum

 subroutine wavefhe4(w1)
  type(walker), intent (inout) :: w1
  type(vec3) :: rtemp
  real(kind=r8) :: ujas,rij
  integer(kind=i4) :: iatom,jatom

  ujas=0.0_r8
  do iatom=1,nhe4-1
    do jatom=iatom+1,nhe4
      rtemp=w1%atom(iatom)-w1%atom(jatom)
      rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
      ujas=ujas-phe4(1)/rij**phe4(2)-phe4(3)*rij
    enddo
  enddo

  ujas=min(ujas,umax)
  ujas=max(ujas,umin)

  w1%lw%wfhe4=exp(ujas)

 end subroutine wavefhe4

 subroutine iwavefhe4(iatom,rold,w1,che4)
  integer(kind=i4), intent (in) :: iatom
  type(vec3), intent (in) :: rold
  type(walker), intent (inout) :: w1
  real(kind=r8), intent (out) :: che4
  type(vec3) :: rtemp
  real(kind=r8) :: unew,uold,rij
  integer(kind=i4) :: jatom

  unew=0.0_r8
  uold=0.0_r8
  do jatom=1,nhe4
    if(jatom.ne.iatom) then
      rtemp=w1%atom(iatom)-w1%atom(jatom)
      rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
      unew=unew-phe4(1)/rij**phe4(2)-phe4(3)*rij
      rtemp=rold-w1%atom(jatom)
      rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
      uold=uold-phe4(1)/rij**phe4(2)-phe4(3)*rij
    endif
  enddo

  che4=exp(unew-uold)
  w1%lw%wfhe4=w1%lw%wfhe4*che4

 end subroutine iwavefhe4

 subroutine derwavefhe4(w1,d1wf,d2wf)
  type(walker), intent (in) :: w1
  type(vec3), intent (out)   :: d1wf(nhe4)
  real(kind=r8), intent (out) :: d2wf(nhe4)
  type(vec3) :: rtemp
  integer(kind=i4) :: iatom,jatom
  real(kind=r8) :: ujasp,ujass,rij

   do iatom=1,nhe4
     d1wf(iatom)%comp(:)=0.0_r8
     d2wf(iatom)=0.0_r8
   enddo

   do iatom=1,nhe4-1
     do jatom=iatom+1,nhe4
         rtemp=w1%atom(iatom)-w1%atom(jatom)
         rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
         ujasp=phe4(1)*phe4(2)/rij**(phe4(2)+1)
         ujass=-(phe4(2)+1)*ujasp/rij
         ujasp=(ujasp-phe4(3))/rij
         d1wf(iatom)%comp(:)=d1wf(iatom)%comp(:)+ujasp*rtemp%comp(:)
         d1wf(jatom)%comp(:)=d1wf(jatom)%comp(:)-ujasp*rtemp%comp(:)
         d2wf(iatom)=d2wf(iatom)+ujass+2.0_r8*ujasp
         d2wf(jatom)=d2wf(jatom)+ujass+2.0_r8*ujasp
     enddo
   enddo
   do iatom=1,nhe4
     d2wf(iatom)=d2wf(iatom)+dot_product(d1wf(iatom)%comp,d1wf(iatom)%comp)
   enddo

 end subroutine derwavefhe4

 subroutine wavefm(w1)
  type (walker), intent (inout) :: w1
  type (vec3) :: rtemp
  real (kind=r8) :: ujas,rij
  integer (kind=i4) :: iatom,jatom

   ujas=0.0_r8
   do iatom=1,nhe4
     do jatom=nhe4+1,ngatom
       rtemp=w1%atom(iatom)-w1%atom(jatom)
       rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
       ujas=ujas-pmix(1)/rij**pmix(2)-pmix(3)*rij
     enddo
   enddo

   w1%lw%wfm=exp(ujas)

 end subroutine wavefm

 subroutine iwavefm(iatom,rold,w1,cmix)
  integer(kind=i4), intent (in) :: iatom
  type(vec3), intent (in) :: rold
  type(walker), intent (inout) :: w1
  real(kind=r8), intent (out) :: cmix
  type(vec3) :: rtemp
  real(kind=r8) :: unew,uold,rij
  integer (kind=i4) :: jatom

  uold=0.0_r8
  unew=0.0_r8
  if(iatom.le.nhe4) then
    do jatom=nhe4+1,ngatom
      rtemp=w1%atom(iatom)-w1%atom(jatom)
      rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
      unew=unew-pmix(1)/rij**pmix(2)-pmix(3)*rij
      rtemp=rold-w1%atom(jatom)
      rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
      uold=uold-pmix(1)/rij**pmix(2)-pmix(3)*rij
    enddo
  elseif(iatom.le.ngatom) then
    do jatom=1,nhe4
      rtemp=w1%atom(iatom)-w1%atom(jatom)
      rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
      unew=unew-pmix(1)/rij**pmix(2)-pmix(3)*rij
      rtemp=rold-w1%atom(jatom)
      rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
      uold=uold-pmix(1)/rij**pmix(2)-pmix(3)*rij
    enddo
  endif

  cmix=exp(unew-uold)
  w1%lw%wfm=w1%lw%wfm*cmix


 end subroutine iwavefm

 subroutine derwavefm(w1,d1wf,d2wf)
  type(walker), intent (in) :: w1
  type(vec3), intent (out)   :: d1wf(ngatom)
  real(kind=r8), intent (out) :: d2wf(ngatom)
  type(vec3) :: rtemp
  integer(kind=i4) :: iatom,jatom,jhe3
  real(kind=r8) :: ujasp,ujass,rij

   do iatom=1,ngatom
     d1wf(iatom)%comp(:)=0.0_r8
     d2wf(iatom)=0.0_r8
   enddo

   do iatom=1,nhe4
     do jhe3=1,nhe3
         jatom=nhe4+jhe3
         rtemp=w1%atom(iatom)-w1%atom(jatom)
         rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
         ujasp=pmix(1)*pmix(2)/rij**(pmix(2)+1)
         ujass=-(pmix(2)+1)*ujasp/rij
         ujasp=(ujasp-pmix(3))/rij
         d1wf(iatom)%comp(:)=d1wf(iatom)%comp(:)+ujasp*rtemp%comp(:)
         d1wf(jatom)%comp(:)=d1wf(jatom)%comp(:)-ujasp*rtemp%comp(:)
         d2wf(iatom)=d2wf(iatom)+ujass+2.0_r8*ujasp
         d2wf(jatom)=d2wf(jatom)+ujass+2.0_r8*ujasp
     enddo
   enddo
   do iatom=1,ngatom
     d2wf(iatom)=d2wf(iatom)+dot_product(d1wf(iatom)%comp,d1wf(iatom)%comp)
   enddo

 end subroutine derwavefm

 subroutine wavefx(w1)
  type (walker), intent (inout) :: w1
  type (vec3) :: rtemp
  real (kind=r8) :: ujas
  real (kind=r8) :: rij,cth
  real (kind=r8) :: dnor
  integer (kind=i4) :: jatom

   if(impureza) then
     cth=0.0_r8
     ujas=0.0_r8
     if(impurmol) dnor=sqrt(dot_product(w1%sprop(3)%comp,w1%sprop(3)%comp))
     do jatom=1,nhe4
       rtemp=w1%atom(jatom)-w1%atom(natom)
       rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
       if(impurmol) cth=dot_product(rtemp%comp,w1%sprop(3)%comp)/(dnor*rij)
       ujas=ujas+uhe4x(rij,cth)
!      write(*,*) jatom,rij,cth
!      write(*,*) jatom,ujas,uhe4x(rij,cth)
     enddo
     do jatom=nhe4+1,ngatom
       rtemp=w1%atom(jatom)-w1%atom(natom)
       rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
       if(impurmol) cth=dot_product(rtemp%comp,w1%sprop(3)%comp)/(dnor*rij)
       ujas=ujas+uhe3x(rij,cth)
     enddo
!    write(*,*) ujas,exp(ujas)
!    write(*,*)
     w1%lw%wfx=exp(ujas)
   else
     w1%lw%wfx=1.0_r8
   endif

 end subroutine wavefx

 subroutine iwavefx(iatom,rold,w1,cimp)
  integer(kind=i4), intent (in) :: iatom
  type(vec3), intent (in) :: rold
  type(walker), intent (inout) :: w1
  real(kind=r8), intent (out) :: cimp
  type(vec3) :: rtemp
  real(kind=r8) :: unew,uold
  real(kind=r8) :: rij,cth
  real(kind=r8) :: dnor
  real(kind=r8) :: delu
  integer (kind=i4) :: jatom


   if(.not.impureza) then
     w1%lw%wfx=1.0_r8
     return
   endif

   if(impurmol) dnor=sqrt(dot_product(w1%sprop(3)%comp,w1%sprop(3)%comp))
   cth=0.0_r8

   if(iatom.eq.natom) then
     uold=0.0_r8
     unew=0.0_r8
     do jatom=1,nhe4
       rtemp=w1%atom(jatom)-w1%atom(natom)
       rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
       if(impurmol) cth=dot_product(rtemp%comp,w1%sprop(3)%comp)/(dnor*rij)
       unew=unew+uhe4x(rij,cth)
       rtemp=w1%atom(jatom)-rold
       rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
       if(impurmol) cth=dot_product(rtemp%comp,w1%sprop(3)%comp)/(dnor*rij)
       uold=uold+uhe4x(rij,cth)
     enddo
     do jatom=nhe4+1,ngatom
       rtemp=w1%atom(jatom)-w1%atom(natom)
       rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
       if(impurmol) cth=dot_product(rtemp%comp,w1%sprop(3)%comp)/(dnor*rij)
       unew=unew+uhe3x(rij,cth)
       rtemp=w1%atom(jatom)-rold
       rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
       if(impurmol) cth=dot_product(rtemp%comp,w1%sprop(3)%comp)/(dnor*rij)
       uold=uold+uhe3x(rij,cth)
     enddo
     delu=unew-uold
     delu=min(delu,umax)
     delu=max(delu,umin)
     cimp=exp(delu)
     w1%lw%wfx=w1%lw%wfx*cimp
     return
   endif

   if(iatom.le.nhe4) then
     jatom=iatom
     rtemp=w1%atom(jatom)-w1%atom(natom)
     rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
     if(impurmol) cth=dot_product(rtemp%comp,w1%sprop(3)%comp)/(dnor*rij)
     unew=uhe4x(rij,cth)
     rtemp=rold-w1%atom(natom)
     rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
     if(impurmol) cth=dot_product(rtemp%comp,w1%sprop(3)%comp)/(dnor*rij)
     uold=uhe4x(rij,cth)
     delu=unew-uold
     delu=min(delu,umax)
     delu=max(delu,umin)
     cimp=exp(delu)
     w1%lw%wfx=w1%lw%wfx*cimp
   elseif(iatom.le.ngatom) then
     jatom=iatom
     rtemp=w1%atom(jatom)-w1%atom(natom)
     rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
     if(impurmol) cth=dot_product(rtemp%comp,w1%sprop(3)%comp)/(dnor*rij)
     unew=uhe3x(rij,cth)
     rtemp=rold-w1%atom(natom)
     rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
     if(impurmol) cth=dot_product(rtemp%comp,w1%sprop(3)%comp)/(dnor*rij)
     uold=uhe3x(rij,cth)
     delu=unew-uold
     delu=min(delu,umax)
     delu=max(delu,umin)
     cimp=exp(delu)
     w1%lw%wfx=w1%lw%wfx*cimp
!    return
   endif

 end subroutine iwavefx

 subroutine derwavefx(w1,d1wf,d2wf,d1zwf,d2zwf)
  type(walker), intent (in) :: w1
  type(vec3), intent (out)   :: d1wf(natom)
  real(kind=r8), intent (out) :: d2wf(natom)
  real(kind=r8), intent (out) :: d1zwf(2),d2zwf
  type(vec3) :: d1ux
  real(kind=r8) :: d2ux
  real(kind=r8) :: d1zux(2),d2zux
  type(vec3) :: rtemp,smol(3)
  real(kind=r8) :: dnor
  integer(kind=i4) :: iatom,jatom,jhe3
  integer(kind=i4) :: ic

   do iatom=1,natom
     d1wf(iatom)%comp(:)=0.0_r8
     d2wf(iatom)=0.0_r8
   enddo
   d1zwf=0.0_r8
   d2zwf=0.0_r8
   if(.not.impureza) return

   if(impurmol) then
     do ic=1,3
       dnor=sqrt(dot_product(w1%sprop(ic)%comp,w1%sprop(ic)%comp))
       smol(ic)%comp(:)=w1%sprop(ic)%comp(:)/dnor
     enddo
   endif

   do jatom=1,nhe4
     rtemp=w1%atom(jatom)-w1%atom(natom)
     call duhe4x(rtemp,smol,d1ux,d2ux,d1zux,d2zux)
     d1wf(jatom)%comp(:)=d1ux%comp(:)
     d1wf(natom)%comp(:)=d1wf(natom)%comp(:)-d1ux%comp(:)
     d2wf(jatom)=d2ux
     d2wf(natom)=d2wf(natom)+d2ux
     d1zwf(:)=d1zwf(:)+d1zux(:)
     d2zwf=d2zwf+d2zux
   enddo

   do jhe3=1,nhe3
     jatom=nhe4+jhe3
     rtemp=w1%atom(jatom)-w1%atom(natom)
     call duhe3x(rtemp,smol,d1ux,d2ux,d1zux,d2zux)
     d1wf(jatom)%comp(:)=d1ux%comp(:)
     d1wf(natom)%comp(:)=d1wf(natom)%comp(:)-d1ux%comp(:)
     d2wf(jatom)=d2ux
     d2wf(natom)=d2wf(natom)+d2ux
     d1zwf(:)=d1zwf(:)+d1zux(:)
     d2zwf=d2zwf+d2zux
   enddo

   do iatom=1,natom
     d2wf(iatom)=d2wf(iatom)+dot_product(d1wf(iatom)%comp,d1wf(iatom)%comp)
   enddo
   d2zwf=d2zwf+dot_product(d1zwf,d1zwf)

 end subroutine derwavefx

 subroutine ewavefx(zold,w1,crot)
  type(vec3), intent (in) :: zold
  type(walker), intent (inout) :: w1
  real(kind=r8), intent (out) :: crot
  type(vec3) :: rtemp
  real(kind=r8) :: dnew,dold
  real(kind=r8) :: unew,uold,delwf
  real(kind=r8) :: rij,cth
  real(kind=r8) :: delu
  integer (kind=i4) :: jatom

   if(.not.impurmol) then
     write(6,*) 'algo raro en ewavefx'
     write(6,*) 'solo llama si impurmol es true'
     write(6,*) impurmol
     return
   endif

   if(libre) then
     call valibre(w1)
     return
   endif

   if(.not.impureza) then
     w1%lw%wfx=1.0_r8
     return
   endif

   dnew=sqrt(dot_product(w1%sprop(3)%comp,w1%sprop(3)%comp))
   dold=sqrt(dot_product(zold%comp,zold%comp))
   unew=0.0_r8
   uold=0.0_r8
   do jatom=1,nhe4
     rtemp=w1%atom(jatom)-w1%atom(natom)
     rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
     cth=dot_product(rtemp%comp,w1%sprop(3)%comp)/(dnew*rij)
     unew=unew+uhe4x(rij,cth)
     cth=dot_product(rtemp%comp,zold%comp)/(dold*rij)
     uold=uold+uhe4x(rij,cth)
   enddo
   do jatom=nhe4+1,ngatom
     rtemp=w1%atom(jatom)-w1%atom(natom)
     rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
     cth=dot_product(rtemp%comp,w1%sprop(3)%comp)/(dnew*rij)
     unew=unew+uhe3x(rij,cth)
     cth=dot_product(rtemp%comp,zold%comp)/(dold*rij)
     uold=uold+uhe3x(rij,cth)
   enddo
   delu=unew-uold
   delu=min(delu,umax)
   delu=max(delu,umin)
   delwf=exp(delu)

   crot=delwf
   w1%lw%wfx=w1%lw%wfx*delwf

 end subroutine ewavefx

 subroutine wavefhe3(w1)
  type(walker), intent (inout) :: w1
  type(vec3) :: rtemp
  real(kind=r8) :: rcm(3)
  real(kind=r8) :: rb(3,nhe3),etaij
  real(kind=r8) :: ujas,rij
  real(kind=r8) :: slaterup,slaterdw
  integer (kind=i4) :: iatom,jatom
  integer (kind=i4) :: ihe3,jhe3

   call getcm(w1,rcm)

   do iatom=nhe4+1,ngatom
      ihe3=iatom-nhe4
      rb(:,ihe3)=w1%atom(iatom)%comp-rcm(:)
   enddo

   ujas=0.0_r8
   do iatom=nhe4+1,ngatom-1
     ihe3=iatom-nhe4
     do jatom=iatom+1,ngatom
       jhe3=jatom-nhe4
       rtemp%comp=w1%atom(iatom)%comp-w1%atom(jatom)%comp
       rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
       ujas=ujas-phe3(1)/rij**phe3(2)
       etaij=phe3(4)/rij**3
       rb(:,ihe3)=rb(:,ihe3)+etaij*rtemp%comp
       rb(:,jhe3)=rb(:,jhe3)-etaij*rtemp%comp
     enddo
   enddo

   do ihe3=1,nhe3-1
     do jhe3=ihe3+1,nhe3
       rtemp%comp=rb(:,ihe3)-rb(:,jhe3)
       ujas=ujas-phe3(3)*sqrt(dot_product(rtemp%comp,rtemp%comp))
     enddo
   enddo

   call slaterdet(nhe3up,rb,slaterup)
   call slaterdet(nhe3dw,rb(1,nhe3up+1),slaterdw)


   ujas=min(ujas,umax)
   ujas=max(ujas,umin)

   w1%lw%wfhe3=exp(ujas)*slaterup*slaterdw
   w1%lw%signoup=1
   w1%lw%signodw=1

   if(slaterup.lt.0.0_r8) w1%lw%signoup=-1
   if(slaterdw.lt.0.0_r8) w1%lw%signodw=-1

 end subroutine wavefhe3

 subroutine slaterdet(npart,rpart,slater)
  integer (kind=i4), parameter :: ndim=20
  integer (kind=i4), intent (in) :: npart
  real (kind=r8), intent (in) :: rpart(3,npart) 
  real (kind=r8), intent (out) :: slater
  real (kind=r8) :: x,y,z
  real (kind=r8) :: matriz(npart,ndim)
  integer (kind=i4) :: ipart

   if(npart.le.1) then
     slater=1.0_r8
     return
   endif

!  do ipart=1,npart
!    matriz(ipart,1)=1.0_r8
!    x=rpart(1,ipart)
!    matriz(ipart,2)=x
!     if(npart.eq.2) cycle
!     y=rpart(2,ipart)
!    matriz(ipart,3)=y
!     if(npart.eq.3) cycle
!    matriz(ipart,4)=x**2-y**2
!     if(npart.eq.4) cycle
!    matriz(ipart,5)=x*y
!     if(npart.eq.5) cycle
!    matriz(ipart,6)=x**3-y**3
!     if(npart.eq.6) cycle
!    matriz(ipart,7)=x**2*y-x*y**2
!     if(npart.eq.7) cycle
!    write(*,*) 'error en slaterdet'
!    write(*,*) 'nfermiones',npart
!    write(*,*) 'ese valor debe ser inferior a 7'
!  enddo


   do ipart=1,npart
     matriz(ipart,1)=1.0_r8
     x=rpart(1,ipart)
     matriz(ipart,2)=x
     if(npart.eq.2) cycle
     y=rpart(2,ipart)
     matriz(ipart,3)=y
     if(npart.eq.3) cycle
     z=rpart(3,ipart)
     matriz(ipart,4)=z
     if(npart.eq.4) cycle
     matriz(ipart,5)=x**2
     matriz(ipart,6)=y**2
     matriz(ipart,7)=z**2
     if(npart.le.7) cycle
     matriz(ipart,8)=x*y
     matriz(ipart,9)=x*z
     matriz(ipart,10)=y*z
     if(npart.le.10) cycle
     matriz(ipart,11)=x*x*x
     matriz(ipart,12)=y*y*y
     matriz(ipart,13)=z*z*z
     matriz(ipart,14)=x*x*y
     matriz(ipart,15)=x*x*z
     matriz(ipart,16)=x*y*y
     matriz(ipart,17)=z*y*y
     matriz(ipart,18)=x*z*z
     matriz(ipart,19)=y*z*z
     matriz(ipart,20)=y*z*x
   enddo

   slater=det(npart,matriz)

 end subroutine slaterdet

 subroutine wavef(w1)
  type(walker), intent (inout) :: w1
! real(kind=r8) :: chico=1.0_r8

     call wavefhe4(w1)
     call wavefhe3(w1)
     call wavefm(w1)
     call wavefx(w1)


     w1%lw%wf=(w1%lw%wfhe4)*(w1%lw%wfhe3)*(w1%lw%wfm)*(w1%lw%wfx)
!    chico=tiny(chico)
!    w1%lw%wf=max(w1%lw%wf,chico)

 end subroutine wavef

 subroutine iwavef(iatom,rold,w1,ctot)
  integer(kind=i4), intent (in) :: iatom
  type(vec3), intent (in) :: rold
  type(walker), intent (inout) :: w1
  real(kind=r8), intent (out) :: ctot
  real(kind=r8) :: che4,che3,cmix,cimp

   che4=1.0_r8
   che3=1.0_r8
   cmix=1.0_r8
   cimp=1.0_r8

   if(libre) then
     call valibre(w1)
     return
   endif

   if(iatom.le.nhe4) then
     call iwavefhe4(iatom,rold,w1,che4)
   elseif(iatom.le.ngatom) then
     che3=w1%lw%wfhe3
     call wavefhe3(w1)
     che3=w1%lw%wfhe3/che3
   endif

   if(iatom.le.ngatom) call iwavefm(iatom,rold,w1,cmix)
   if(impureza) call iwavefx(iatom,rold,w1,cimp)
  

   w1%lw%wf=(w1%lw%wfhe4)*(w1%lw%wfhe3)*(w1%lw%wfm)*(w1%lw%wfx)

   ctot=che4*che3*cmix*cimp

 end subroutine iwavef

 subroutine derwavefhe3(w1,d1wf,d2wf)
  type(walker), intent (inout) :: w1
  type(vec3), intent (out)    :: d1wf(nhe3)
  real(kind=r8), intent (out) :: d2wf(nhe3)
  type(vec3) :: rtemp
  real(kind=r8) :: wfmas,wfmen,dend1,dend2
  real(kind=r8) :: wf0,sumd2
  integer (kind=i4) :: ihe3,iatom,ic
  real (kind=r8), parameter :: dx=1.d-3

   wf0=w1%lw%wfhe3
   dend1=2.0_r8*dx*wf0
   dend2=dx**2*wf0

   do ihe3=1,nhe3
     iatom=nhe4+ihe3
     rtemp=w1%atom(iatom)
     sumd2=0.0_r8
     do ic=1,3
       w1%atom(iatom)%comp(ic)=rtemp%comp(ic)+dx
       call wavefhe3(w1)
       wfmas=w1%lw%wfhe3
       w1%atom(iatom)%comp(ic)=rtemp%comp(ic)-dx
       call wavefhe3(w1)
       wfmen=w1%lw%wfhe3
       w1%atom(iatom)%comp(ic)=rtemp%comp(ic)
       d1wf(ihe3)%comp(ic)=(wfmas-wfmen)/dend1
       sumd2=sumd2+(wfmas+wfmen-2.0_r8*wf0)
     enddo
     d2wf(ihe3)=sumd2/dend2
   enddo

   w1%lw%wfhe3=wf0

 end subroutine derwavefhe3

 subroutine dernumeri(w1)
  integer, parameter :: r16=max(selected_real_kind(2*precision(1.0_r8)),r8)
  type(walker), intent (inout) :: w1
  type(vec3) :: rtemp,etemp(3)
  type(vloc) :: ltemp
  real(kind=r8) :: wfxo
  real(kind=r16) :: wfmas,wfmen,dend1,dend2,der2,wf0
  real(kind=r8) :: crotmas,crotmen
! real(kind=r8) :: wfmas,wfmen,dend1,dend2,der2,wf0
  real(kind=r8) :: ekin,eimpureza,erotacion
  real(kind=r8) :: phi
  real(kind=r8) :: cwfmas,cwfmen
  integer(kind=i4) :: iatom,ic
  real(kind=r8), parameter :: dx=1.d-3
  real (kind=r8), parameter :: da=1.d-4

   call wavef(w1)
   ltemp=w1%lw
!  wf0=ltemp%wf
!  dend1=2.0_r8*dx*wf0
!  dend2=dx**2*wf0

   ekin=0.0_r8
   eimpureza=0.0_r8
   do iatom=1,ncmtras
     rtemp=w1%atom(iatom)
     do ic=1,3
       w1%atom(iatom)%comp(ic)=rtemp%comp(ic)+dx
       w1%lw=ltemp
       call iwavef(iatom,rtemp,w1,cwfmas)
!      wfmas=w1%lw%wf
       w1%atom(iatom)%comp(ic)=rtemp%comp(ic)-dx
       w1%lw=ltemp
       call iwavef(iatom,rtemp,w1,cwfmen)
!      wfmen=w1%lw%wf
       w1%atom(iatom)=rtemp
!      w1%dwf(iatom)%comp(ic)=(wfmas-wfmen)/dend1
       w1%dwf(iatom)%comp(ic)=(cwfmas-cwfmen)/(2.0_r8*dx)
!      der2=(wfmas+wfmen-2.0_r8*wf0)/dend2
       der2=(cwfmas+cwfmen-2.0_r8)/dx**2
       ekin=ekin-w1%hb2m(iatom)*der2
       if(.not.impurfija.and.iatom.eq.natom) eimpureza=eimpureza-w1%hb2m(iatom)*der2
     enddo
   enddo
   w1%lw%wfx=ltemp%wfx

   erotacion=0.0_r8
   if(rotamol) then
     wfxo=w1%lw%wfx
     etemp(:)=w1%sprop(:)
     dend1=2.0_r8*da*wfxo
     dend2=da**2*wfxo
     do ic=1,2
       phi=da
       w1%sprop(:)=etemp(:)
       call rota(ic,phi,w1%sprop)
       w1%lw%wfx=wfxo
       call ewavefx(etemp(3),w1,crotmas)
       wfmas=w1%lw%wfx
       phi=-da
       w1%sprop(:)=etemp(:)
       call rota(ic,phi,w1%sprop)
       w1%lw%wfx=wfxo
       call ewavefx(etemp(3),w1,crotmen)
       wfmen=w1%lw%wfx
       w1%dphi(ic)=(wfmas-wfmen)/dend1
       der2=(wfmas+wfmen-2.0_r8*wfxo)/dend2
       ekin=ekin-w1%b*der2
       erotacion=erotacion-w1%b*der2
     enddo
     w1%lw%wfx=wfxo
     w1%sprop(:)=etemp(:)
   endif

   w1%lw%kin=ekin
   w1%lw%eimp=eimpureza
   w1%lw%erot=erotacion

 end subroutine dernumeri


 subroutine restacm(w1)
  type (walker), intent (inout) :: w1
  real (kind=r8) :: rcm(3)
  integer(kind=i4) :: iatom

   call getcm(w1,rcm)

!  rcm=0.0_r8

   do iatom=1,natom
     w1%atom(iatom)%comp=w1%atom(iatom)%comp-rcm
   enddo

 end subroutine restacm

 subroutine getcm(w1,rcm)
  type(walker), intent (in) :: w1
  real(kind=r8), intent (out) :: rcm(3)
  integer(kind=i4) :: iatom

   rcm=0.0_r8
   do iatom=1,nhe4
     rcm=rcm+mhe4*w1%atom(iatom)%comp
   enddo
   do iatom=nhe4+1,ngatom
     rcm=rcm+mhe3*w1%atom(iatom)%comp
   enddo
   if(impureza) then
     rcm=rcm+mx*w1%atom(natom)%comp
     rcm=rcm/(nhe4*mhe4+nhe3*mhe3+mx)
   else
     rcm=rcm/(nhe4*mhe4+nhe3*mhe3)
   endif

 end subroutine getcm

 subroutine vpot(w1)
  type(walker), intent (inout) :: w1
  type(vec3) :: rtemp
  real(kind=r8) :: rhe(3*ngatom),ejemol(3),vpotbh
  real(kind=r8) :: rij
  real(kind=r8) :: dnor,cth
  integer(kind=i4) :: iatom,jatom

  if(opot.eq.4) then
      call ccuerpo(w1,rhe)
      call potenbh(ngatom,rhe,vpotbh)
      w1%lw%pot=vpotbh
   return
  endif


   w1%lw%pot=0.0_r8
   do iatom=1,ngatom-1
     do jatom=iatom+1,ngatom
       rtemp%comp=w1%atom(iatom)%comp-w1%atom(jatom)%comp
       rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
       w1%lw%pot=w1%lw%pot+aziz_nuevo(rij)
     enddo
   enddo

   if(.not.impureza) return

   if(impurmol) then
     dnor=sqrt(dot_product(w1%sprop(3)%comp,w1%sprop(3)%comp))
     do jatom=1,ngatom
       rtemp=w1%atom(jatom)-w1%atom(natom)
       rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
       cth=dot_product(rtemp%comp,w1%sprop(3)%comp)/(dnor*rij)
       w1%lw%pot=w1%lw%pot+vatomol(opot,cmtok,rij,cth)
     enddo
     else
     do jatom=1,ngatom
       rtemp=w1%atom(jatom)-w1%atom(natom)
       rij=sqrt(dot_product(rtemp%comp,rtemp%comp))
       w1%lw%pot=w1%lw%pot+azizgen(rij)
      enddo
   endif

 end subroutine vpot

 subroutine valibre(w1)
   type(walker), intent (inout) :: w1
   integer(kind=i4) :: iatom

    w1%lw%wf=1.0_r8
    w1%lw%wfhe4=1.0_r8
    w1%lw%wfhe3=1.0_r8
    w1%lw%wfm=1.0_r8
    w1%lw%wfx=1.0_r8
    w1%lw%kin=0.0_r8
    w1%lw%pot=0.0_r8
    w1%lw%ene=0.0_r8
    w1%lw%signoup=1
    w1%lw%signodw=1

    do iatom=1,natom
      w1%dwf(iatom)=0.0_r8
    enddo
    w1%dphi(:)=0.0_r8


 end subroutine valibre


 subroutine dibuja
  integer(kind=i4), parameter :: lxmax=9
  real(kind=r8) :: jhe4,jhe3,jmix
  real(kind=r8) :: etaij
  real(kind=r8) :: ulxhe,jlxhe
  real(kind=r8) :: rmax,rmin,dr,rij
  real(kind=r8) :: xmin,xmax,ymin,ymax,dx,dy,xp,yp
  real(kind=r8) :: thmax,thmin,dth,th,cth,sth,vrth,vmin
  real(kind=r8) :: wfxrth,wf4max,wf3max
  real(kind=r8) :: pl(0:lxmax)
  real(kind=r8) :: cunid=1.0_r8
  real(kind=r8) :: ujas
  integer(kind=i4) :: ir,nrmax
  integer(kind=i4) :: ith,nthmax
  integer(kind=i4) :: il,ifile

  nrmax=2000
  rmax=200.0_r8
  rmin=0.0_r8
  dr=(rmax-rmin)/(nrmax-1)
  rmin=0.01_r8*dr

  nthmax=180
  thmax=180.0_r8
  thmin=0.0_r8
  dth=(thmax-thmin)/(nthmax-1)

  write(10,'("# Jastrow he4-he4, he3-he3,  he4-he3")')
  write(11,'("# Backflow eta")')
  write(12,'("# Potencial he-he")')
  if(impureza) then
    do il=0,lxhe4
      ifile=20+il
      write(ifile,'("# r, u_l, exp(u_l)  X-he4  l= ",t35,i5)') il
    enddo
    do il=0,lxhe3
      ifile=40+il
      write(ifile,'("# r, u_l, exp(u_l)  X-he3  l= ",t35,i5)') il
    enddo
    do il=0,lxmax
      ifile=60+il
      write(ifile,'("# z, P_l(z) l= ",t20,i5)') il
    enddo
  endif

  do ir=1,nrmax
    rij=rmin+(ir-1)*dr
    ujas=-phe4(1)/rij**phe4(2)-phe4(3)*rij
    ujas=min(ujas,umax) 
    ujas=max(ujas,umin) 
    jhe4=exp(ujas)
    ujas=-phe3(1)/rij**phe3(2)-phe3(3)*rij
    ujas=min(ujas,umax) 
    ujas=max(ujas,umin) 
    jhe3=exp(ujas)
    ujas=-pmix(1)/rij**pmix(2)-pmix(3)*rij
    ujas=min(ujas,umax) 
    ujas=max(ujas,umin) 
    jmix=exp(ujas)
    etaij=phe3(4)/rij**3
    write(10,'(f10.5,3f20.10)') rij,jhe4,jhe3,jmix
    write(11,'(f10.5,f20.10)') rij,etaij
    write(12,'(f10.5,f20.10)') rij,aziz_nuevo(rij)
    if(impureza) then
      do il=0,lxhe4
        ifile=20+il
        ulxhe=-pxhe4(1,il)/rij**pxhe4(2,il)-pxhe4(3,il)*rij**pxhe4(4,il)  &
 &            -pxhe4(5,il)*log(rij)
        ulxhe=min(ulxhe,umax)
        ulxhe=max(ulxhe,umin)
        jlxhe=exp(ulxhe)
        write(ifile,'(f10.5,2es20.10)') rij,ulxhe,jlxhe
      enddo
      do il=0,lxhe3
        ifile=40+il
        ulxhe=-pxhe3(1,il)/rij**pxhe3(2,il)-pxhe3(3,il)*rij**pxhe3(4,il)  &
 &            -pxhe3(5,il)*log(rij)
        ulxhe=min(ulxhe,umax)
        ulxhe=max(ulxhe,umin)
        jlxhe=exp(ulxhe)
        write(ifile,'(f10.5,2es20.10)') rij,ulxhe,jlxhe
      enddo
    endif
  enddo

  if(impureza) then
    if(.not.impurmol) then
      write(13,'("# Potencial X-he")')
      do ir=1,nrmax
        rij=rmin+(ir-1)*dr
        write(13,'(f10.5,f20.10)') rij,azizgen(rij)
      enddo
    else
      do ith=1,nthmax
        th=thmin+(ith-1)*dth
        cth=cos(pi/180.0_r8*th)
        call calpleg(lxmax,cth,pl)
        do il=0,lxmax
           ifile=60+il
           write(ifile,'(f10.5,f20.10)') cth,pl(il)
        enddo
      enddo
      write(81,'("# Potencial X-he  r,theta,v(r,theta)")')
      write(82,'("# Potencial X-he  rho,z,v(rho,z)")')
      write(83,'("# Potencial X-he  theta,vmin(theta)")')
      write(91,'("# wf X-he4  r,theta,wf(r,theta)")')
      write(92,'("# wf X-he4  rho,z,wf(rho,z)")')
      write(93,'("# wf X-he4  theta,wfmax(theta)")')
      write(96,'("# wf X-he3  r,theta,wf(r,theta)")')
      write(97,'("# wf X-he3  rho,z,wf(rho,z)")')
      write(98,'("# wf X-he3  theta,wfmax(theta)")')
      nrmax=100
      rmax=9.2_r8
      rmin=3.00_r8
      dr=(rmax-rmin)/(nrmax-1)
      do ir=1,nrmax
        rij=rmin+(ir-1)*dr
        do ith=1,nthmax
          th=thmin+(ith-1)*dth
          cth=cos(pi/180.0_r8*th)
          sth=sqrt(1.0_r8-cth**2)
          vrth=vatomol(opot,cunid,rij,cth)
          write(81,'(2f10.5,es20.10E3)') rij,th,vrth
!         write(82,'(2f10.5,es20.10E3)') rij*cth,rij*sth,vrth
          write(82,'(2f10.5,es20.10E2)') rij*cth,rij*sth,vrth
          wfxrth=uhe4x(rij,cth)
          wfxrth=min(wfxrth,umax)
          wfxrth=max(wfxrth,umin)
          write(91,'(2f10.5,2es20.10E3)') rij,th,wfxrth,exp(wfxrth)
          write(92,'(2f10.5,2es20.10E3)') rij*cth,rij*sth,wfxrth,exp(wfxrth)
          wfxrth=uhe3x(rij,cth)
          wfxrth=min(wfxrth,umax)
          wfxrth=max(wfxrth,umin)
          write(96,'(2f10.5,2es20.10E3)') rij,th,wfxrth,exp(wfxrth)
          write(97,'(2f10.5,2es20.10E3)') rij*cth,rij*sth,wfxrth,exp(wfxrth)
        enddo
        write(81,*)
        write(82,*)
        write(91,*)
        write(92,*)
        write(96,*)
        write(97,*)
      enddo
      nrmax=1000
      dr=(rmax-rmin)/(nrmax-1)
      do ith=1,nthmax
        th=thmin+(ith-1)*dth
        cth=cos(pi/180.0_r8*th)
        vmin=1.d10
        wf4max=-1.0_r8
        wf3max=-1.0_r8
        do ir=1,nrmax
          rij=rmin+(ir-1)*dr
          vrth=vatomol(opot,cunid,rij,cth)
          if(vrth.lt.vmin) vmin=vrth
          wfxrth=uhe4x(rij,cth)
          wfxrth=min(wfxrth,umax)
          wfxrth=max(wfxrth,umin)
          wfxrth=exp(wfxrth)
          if(wfxrth.gt.wf4max) wf4max=wfxrth
          wfxrth=uhe3x(rij,cth)
          wfxrth=min(wfxrth,umax)
          wfxrth=max(wfxrth,umin)
          wfxrth=exp(wfxrth)
          if(wfxrth.gt.wf3max) wf3max=wfxrth
        enddo
        write(83,'(f10.5,es20.10E3)') th,vmin
        write(93,'(f10.5,2es20.10E3)') th,wf4max,wf4max**2
        write(98,'(f10.5,2es20.10E3)') th,wf3max,wf3max**2
      enddo
    endif
  endif

 end subroutine dibuja


end module mwavef
