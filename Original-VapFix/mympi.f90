module mympi
!
! load balancing mpi routines -- these are rewrites by K.E. Schmidt
! of the mpi routines written by Michael A. Lee and I. Lomonosov for the
! parallel version of the Schmidt and Lee electronic structure GFMC code
! 
   implicit none
   include 'mpif.h'
   integer, private, parameter :: i4=selected_int_kind(9)
   integer, private, parameter :: i8=selected_int_kind(15)
   integer, private, parameter :: r8=selected_real_kind(15,9)
   integer(kind=i4), private, save :: irank,iproc,nleft,npart
   integer(kind=i4), private, allocatable, save :: numfig(:)
   logical, private, save :: nobal

interface bcast ! broadcast from process 0
   module procedure bcasti1,bcasti1d,bcasti2d,bcasti3d
   module procedure bcastr1,bcastr1d,bcastr2d,bcastr3d
end interface bcast

interface addall ! return sum to process 0
   module procedure addalli1,addalli1d
   module procedure addallr1,addallr1d,addallr2d
end interface addall

interface gather ! gather to process 0
   module procedure gatheri1,gatheri1d
   module procedure gatherr1,gatherr1d
end interface gather

contains
   subroutine init0 ! call this before anything else
   integer(kind=i4) :: ierror
   call mpi_init(ierror)
   call mpi_comm_rank(mpi_comm_world,irank,ierror)
   call mpi_comm_size(mpi_comm_world,iproc,ierror)
   allocate(numfig(0:iproc-1))
   if (mpi_integer8.eq.0) then
      write (6,'(''mpi_integer8 not defined'')')
      call abort
   endif
   end subroutine init0

   subroutine init1(npartin,nleftin) ! call this when everyone knows these
   integer(kind=i4) :: npartin,nleftin
   npart=npartin
   nleft=nleftin
   end subroutine init1

   subroutine done ! wrapper for finalize routine
   integer(kind=i4) :: ierror
   call mpi_finalize(ierror)
   end subroutine done

   subroutine bcasti1(i)
   integer(kind=i4) :: i,ierror
   call mpi_bcast(i,1,mpi_integer,0,mpi_comm_world,ierror)
   return
   end subroutine bcasti1

   subroutine bcasti1d(i)
   integer(kind=i4) :: i(:),ierror
   call mpi_bcast(i,size(i),mpi_integer,0,mpi_comm_world,ierror)
   return
   end subroutine bcasti1d

   subroutine bcasti2d(i)
   integer(kind=i4) :: i(:,:),ierror
   call mpi_bcast(i,size(i),mpi_integer,0,mpi_comm_world,ierror)
   return
   end subroutine bcasti2d

   subroutine bcasti3d(i)
   integer(kind=i4) :: i(:,:,:),ierror
   call mpi_bcast(i,size(i),mpi_integer,0,mpi_comm_world,ierror)
   return
   end subroutine bcasti3d

   subroutine bcastr1d(r)
   integer(kind=i4) :: ierror
   real(kind=r8) :: r(:)
   call mpi_bcast(r,size(r),mpi_double_precision,0,mpi_comm_world,ierror)
   return
   end subroutine bcastr1d

   subroutine bcastr2d(r)
   integer(kind=i4) :: ierror
   real(kind=r8) :: r(:,:)
   call mpi_bcast(r,size(r),mpi_double_precision,0,mpi_comm_world,ierror)
   return
   end subroutine bcastr2d

   subroutine bcastr3d(r)
   integer(kind=i4) :: ierror
   real(kind=r8) :: r(:,:,:)
   call mpi_bcast(r,size(r),mpi_double_precision,0,mpi_comm_world,ierror)
   return
   end subroutine bcastr3d

   subroutine bcastr1(r)
   integer(kind=i4) :: ierror
   real(kind=r8) :: r
   call mpi_bcast(r,1,mpi_double_precision,0,mpi_comm_world,ierror)
   return
   end subroutine bcastr1

   function myrank() ! which process am I?
   integer(kind=i4) :: myrank
   myrank=irank
   end function myrank

   function nproc() ! How many of use are there anyway?
   integer(kind=i4) :: nproc
   nproc=iproc
   end function nproc

   subroutine barrier ! wrapper for mpi_barrier
   integer(kind=i4) :: ierror
   call mpi_barrier(mpi_comm_world,ierror)
   end subroutine barrier

   subroutine addalli1(i,isum)
   integer(kind=i4) :: ierror,i,isum
   call mpi_reduce(i,isum,1,mpi_integer,mpi_sum,0,mpi_comm_world,ierror)
   return
   end subroutine addalli1

   subroutine addalli1d(i,isum)
   integer(kind=i4) :: ierror,i(:),isum(:)
   call mpi_reduce(i,isum,size(i),mpi_integer,mpi_sum,0,mpi_comm_world,ierror)
   return
   end subroutine addalli1d

   subroutine addallr1(r,rsum)
   integer(kind=i4) :: ierror
   real(kind=r8) :: r,rsum
   call mpi_reduce(r,rsum,1,mpi_double_precision,mpi_sum,0, &
      mpi_comm_world,ierror)
   return
   end subroutine addallr1

   subroutine addallr1d(r,rsum)
   real(kind=r8) :: r(:),rsum(:)
   integer(kind=i4) :: ierror
   call mpi_reduce(r,rsum,size(r),mpi_double_precision,mpi_sum,0, &
      mpi_comm_world,ierror)
   return
   end subroutine addallr1d

   subroutine addallr2d(r,rsum)
   real(kind=r8) :: r(:,:),rsum(:,:)
   integer(kind=i4) :: ierror
   call mpi_reduce(r,rsum,size(r),mpi_double_precision,mpi_sum,0, &
      mpi_comm_world,ierror)
   return
   end subroutine addallr2d

   subroutine gatheri1(i,igather)
   integer(kind=i4) :: i,igather(:),ierror
   call mpi_gather(i,1,mpi_integer,igather,1,mpi_integer,0, &
      mpi_comm_world,ierror)
   return
   end subroutine gatheri1

   subroutine gatheri1d(i,igather)
   integer(kind=i4) :: i(:),igather(:,:),ierror
   call mpi_gather(i,size(i),mpi_integer,igather,size(i),mpi_integer,0, &
      mpi_comm_world,ierror)
   return
   end subroutine gatheri1d

   subroutine gatherr1(r,rgather)
   real(kind=r8) :: r,rgather(:)
   integer(kind=i4) :: ierror
   call mpi_gather(r,1,mpi_double_precision,rgather,1, &
      mpi_double_precision,0,mpi_comm_world,ierror)
   return
   end subroutine gatherr1

   subroutine gatherr1d(r,rgather)
   real(kind=r8) :: r(:),rgather(:,:)
   integer(kind=i4) :: ierror
   call mpi_gather(r,size(r),mpi_double_precision,rgather,size(r) &
      ,mpi_double_precision,0,mpi_comm_world,ierror)
   return
   end subroutine gatherr1d

   subroutine abort
   integer(kind=i4) :: ierror
   call mpi_abort(mpi_comm_world,ierror)
   return
   end subroutine abort

   subroutine movewalkers(istack,nwalk,ifrom,ito,id)
   use stack
!
! routine to move nwalk walkers on istack from process ifrom to
! process ito. id is an arbitrary integer identifier
!
   integer(kind=i4) :: nwalk,ifrom,ito,id,i,istack
   integer(kind=i4) :: istatus(mpi_status_size),ierror
   real(kind=r8), target ::  x(3,npart),dpsi(3,npart)
   logical empty
   type (walker) w
   w%x=>x
   w%dpsi=>dpsi
   if (ifrom.eq.ito) return
   if (irank.eq.ito) then
      do i=1,nwalk
         call mpi_recv(w%psil,1,mpi_double_precision,ifrom,id, &
            mpi_comm_world,istatus,ierror)
         call mpi_recv(w%d2psi,1,mpi_double_precision,ifrom,id, &
            mpi_comm_world,istatus,ierror)
         call mpi_recv(w%v,1,mpi_double_precision,ifrom,id, &
            mpi_comm_world,istatus,ierror)
         call mpi_recv(w%weight,1,mpi_double_precision,ifrom,id, &
            mpi_comm_world,istatus,ierror)
         call mpi_recv(w%x,3*npart,mpi_double_precision,ifrom,id, &
            mpi_comm_world,istatus,ierror)
         call mpi_recv(w%dpsi,3*npart,mpi_double_precision,ifrom,id, &
            mpi_comm_world,istatus,ierror)
         call mpi_recv(w%is,1,mpi_integer,ifrom,id, &
            mpi_comm_world,istatus,ierror)
         call mpi_recv(w%irn,1,mpi_integer8,ifrom,id, &
            mpi_comm_world,istatus,ierror)
         call push(istack,w)
      enddo
   else if (irank.eq.ifrom) then
      do i=1,nwalk
         call pop(istack,w,empty)
         if (empty) then
            write (6,'(''stack empty in movewalker'')')
            call abort
         endif
         call mpi_send(w%psil,1,mpi_double_precision,ito,id, &
            mpi_comm_world,ierror)
         call mpi_send(w%d2psi,1,mpi_double_precision,ito,id, &
            mpi_comm_world,ierror)
         call mpi_send(w%v,1,mpi_double_precision,ito,id, &
            mpi_comm_world,ierror)
         call mpi_send(w%weight,1,mpi_double_precision,ito,id, &
            mpi_comm_world,ierror)
         call mpi_send(w%x,3*npart,mpi_double_precision,ito,id, &
            mpi_comm_world,ierror)
         call mpi_send(w%dpsi,3*npart,mpi_double_precision,ito,id, &
            mpi_comm_world,ierror)
         call mpi_send(w%is,1,mpi_integer,ito,id, &
            mpi_comm_world,ierror)
         call mpi_send(w%irn,1,mpi_integer8,ito,id, &
            mpi_comm_world,ierror)
      enddo
   endif
   return
   end subroutine movewalkers

   subroutine loadme(finished,istack)
!
! processes should call this routine when they want more work
!
   logical :: finished
   integer(kind=i4) :: istack
   integer(kind=i4) :: i,iprobe,istatus(mpi_status_size),ierror,iflag,ii,mr
   finished=nobal
   if (finished) return
!
! send message to everyone else and wait
!
   do i=0,iproc-1
      if (i.ne.irank) call mpi_send(irank,1,mpi_integer,i &
         ,1000,mpi_comm_world,ierror)
   enddo
   call barrier
!
! Others may have sent messages so clear those and proceed to
! load balancing routine
!
   call mpi_iprobe(mpi_any_source,1000,mpi_comm_world,iflag,istatus,ierror)
   do while (iflag.eq.1)
      mr=istatus(mpi_source)
      call mpi_recv(ii,1,mpi_integer,mr,1000,mpi_comm_world,istatus,ierror)
      call mpi_iprobe(mpi_any_source,1000,mpi_comm_world,iflag,istatus,ierror)
   enddo
   call load(istack)
   return
   end subroutine loadme

   subroutine loadcheck(istack)
!
! processes should call this routine to see if others need work
!
   integer(kind=i4) :: istack
   integer(kind=i4) :: i,iprobe,istatus(mpi_status_size),ierror,iflag,ii,mr
   if (nobal) return
   call mpi_iprobe(mpi_any_source,1000,mpi_comm_world,iflag,istatus,ierror)
   if (iflag.eq.1) then ! return if no one requests work
      mr=istatus(mpi_source)
      call mpi_recv(ii,1,mpi_integer,mr,1000,mpi_comm_world, &
         istatus,ierror) ! clear the first message and wait for others
      call barrier
!
! clear any other messages and proceed to load balancing
!
      call mpi_iprobe(mpi_any_source,1000,mpi_comm_world,iflag,istatus,ierror)
      do while (iflag.eq.1)
         mr=istatus(mpi_source)
         call mpi_recv(ii,1,mpi_integer,mr,1000,mpi_comm_world, &
            istatus,ierror)
         call mpi_iprobe(mpi_any_source,1000,mpi_comm_world,iflag, &
            istatus,ierror)
      enddo
      call load(istack)
   endif
   return
   end subroutine loadcheck

   subroutine load(istack)
   use stack
   integer(kind=i4) :: istack
   integer(kind=i4) :: n1,numfig(0:iproc-1),nt,ierror,nave,isum,k
   integer(kind=i4) :: nr(0:iproc-1),ns(0:iproc-1),npos,nneg,isend,irec,ntrans
   n1=numstack(istack)
   call mpi_gather(n1,1,mpi_integer,numfig,1,mpi_integer,0, &
      mpi_comm_world,ierror)
   call bcast(numfig) !everyone knows how many walkers the others have
   nt=sum(numfig)
   if (nt.lt.nleft) then
      call loadoff
      return
   endif
   nave=(nt+iproc-1)/iproc
   numfig=numfig-nave
   isum=-sum(numfig)
   numfig(0:isum-1)=numfig(0:isum-1)+1 ! numfig = the number of excess walkers
   npos=0
   nneg=0
   do k=0,iproc-1
      if (numfig(k).gt.0) then
         ns(npos)=k
         npos=npos+1
      endif
      if (numfig(k).lt.0) then
         nr(nneg)=k
         nneg=nneg+1
      endif
   enddo
   isend=0
   irec=0
   do k=1,iproc+1
      if (isend.eq.npos) then
         if (irec.eq.nneg) then
            return
         else
            write (6,'(1x,''error in load,4i5)') irec,nneg,isend,npos
         endif
      endif
      ntrans=min(numfig(ns(isend)),-numfig(nr(irec)))
      call movewalkers(istack,ntrans,ns(isend),nr(irec),k)
      numfig(ns(isend))=numfig(ns(isend))-ntrans
      numfig(nr(irec))=numfig(nr(irec))+ntrans
      if (numfig(ns(isend)).eq.0) isend=isend+1
      if (numfig(nr(irec)).eq.0) irec=irec+1
   enddo

   end subroutine load

   subroutine loadon
   nobal=.false.
   return
   end subroutine loadon

   subroutine loadoff
   nobal=.true.
   return
   end subroutine loadoff

end module mympi
