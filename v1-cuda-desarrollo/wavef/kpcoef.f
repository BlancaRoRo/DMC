      subroutine ajusta(m1i,m2i,m3i,n2i,nnpi,i2i,i3i,r1i,x1i,x2i,x3i,yi)
      implicit double precision  (a-h,o-z)
      PARAMETER(NN=50,maxpts=2000,nnn=nn*nn)
      integer m1i,m2i,m3i,n2i,nnpi
      integer i2i(maxpts),i3i(maxpts)
      double precision r1i,x1i(nn),x2i(nn),x3i(nn),yi(nn,nnn)
      integer nnp_req
      common/rkhs/x1a(NN),x2a(NN),x3a(NN),m1,m2,m3
      common/indexr/ind2(maxpts),ind3(maxpts),n2
      common/keep2/r1e
      common/keep/ y2a(nn,nnn)
      dimension ya(nn,nnn)
      dimension ytmp(nnn),y2tmp(nnn)

       m1=m1i
       m2=m2i
       m3=m3i
       n2=n2i
       nnp_req=nnpi
       r1e=r1i

       do i=1,maxpts
         ind2(i)=i2i(i)
         ind3(i)=i3i(i)
       enddo
       do i=1,nn
         x1a(i)=x1i(i)
         x2a(i)=x2i(i)
         x3a(i)=x3i(i)
       enddo
       do j=1,nnn
         do i=1,nn
           ya(i,j)=yi(i,j)
         enddo
       enddo
     
c 
c     Generate RKHS coefficients.  At each value of r_CO, calculate
c     the RKHS coefficients alpha by solving a set of linear equations
c     in fit_rkhs2.  Each row of y2a() contains the RKHS coefficents for the
c     corresponding value of r_CO.
         do i=1,m1
            do j=1,n2
               ytmp(j)=ya(i,j)
            enddo
            call fit_rkhs2(i,ytmp,y2tmp)
            do j=1,n2
               y2a(i,j)=y2tmp(j)
            enddo
         enddo

c     Set up polynomial fitting matrix G for vibrational averaging.
c     The results are stored in polyfit common block for use by rkhs2coef.
        call gen_polyfit(x1a, m1, nnp_req)

        write(6,'("kpcoef setup completed successfully")')

        return
      end 

      subroutine kpcoef(x2,x3,vr1coef)
      implicit double precision  (a-h,o-z)
      double precision x2, x3, vr1coef(*)
      PARAMETER(NN=50,maxpts=2000,nnn=nn*nn)
      common/rkhs/x1a(NN),x2a(NN),x3a(NN),m1,m2,m3
      common/indexr/ind2(maxpts),ind3(maxpts),n2
      common/keep2/r1e
      common/keep/ y2a(nn,nnn)
         
         x3i=(1.d0-(x3))/2.d0   ! scale angle to interval [0,1]

         call rkhs2coef(x2,x3i,y2a,vr1coef)

      return 
      end 
c

c   -----------------------------------------------------------------------

c  distance-like kernel q[2,5](x,y)
c  q[2,5](x,y) = (2/21)*xg**(-6)*(1-(3/4)*(xl/xg))
c  where xg is the greater of x and y and xl is the lesser
c  definition given in Ho and Rabitz, JCP 104, 2584 (1996), eqn. (17).
c  G. McBane 15 June 2002
c  
c  obscure coding intended for speed, though it might not be necessary
       double precision function rkhsdk(x,y)
       implicit none
       double precision x, y
       double precision oob7, a, b
       double precision to21, moo14
       parameter(to21 = 2.0d0/21.0d0, moo14 = -1.0d0/14.0d0)

       if (x .lt. y) then
          a = x
          b = y
       else
          a = y
          b = x
       end if
       oob7 = b*b*b
       oob7 = oob7*oob7
       oob7 = oob7*b
       oob7 = 1.0d0/oob7

       rkhsdk = oob7*(b*to21 + a*moo14)
       return
       end
c

c     Angle kernel

       double precision function rkhsak(x,y)
       implicit none
       double precision x, y
       double precision a, b
       double precision moo3
       parameter(moo3 = -1.0d0/3.0d0)
       
       if((x.eq.0.d0).or.(y.eq.0.d0)) then
          rkhsak=1.d0
          return  
       endif

       if (x .lt. y) then
          a = x
          b = y
       else
          a = y
          b = x
       end if

       rkhsak = 1.0d0 + a*(b+2.0d0*a*(b+moo3*a))
       return
       end

c     Main evaluation routine.

       subroutine rkhs2coef(x2,x3,coef,vr1coef)

       implicit double precision (a-h,o-z)
       double precision vr1coef(*)
       parameter(nn=50,maxpts=2000,nnn=nn*nn)
       common/rkhs/r1(nn),r2(nn),theta(nn),m1,m2,m3
       common/indexr/ind2(maxpts),ind3(maxpts),n2
       common/keep2/r1e

c  Polyfit common block appears only here and in gen_polyfit

c  Polyfit common block: used in gen_polyfit and in rkhs2coef
c  note that nn must be known in any routine that includes this file

c      include 'polyfit.fi'
      integer maxnnp
      parameter (maxnnp = 4)
      common /polyfit/ fitmat,  nnp
      integer nnp
      double precision fitmat(maxnnp, nn)


       dimension coef(nn,nnn),e(nn)
       double precision kern_dp(nnn), kern_r2(nn), kern_theta(nn)
       integer index

c     Get rkhs kernel values for r2 and theta. (We have a rectangular
c     grid of ab points, so the positions of available (r2, theta)
c     points are the same no matter what r1 is.) There is still some
c     redundancy here; since x2 and x3 are the same on every call within
c     the loops, some work is being duplicated in the kernel functions
c     on calls after the first.  And since the r2 and theta vectors
c     never change, functions that involve only them are being
c     needlessly recalculated also. But I think this inefficiency is
c     minor.

       do j = 1, m2
          kern_r2(j) = rkhsdk(x2, r2(j))
       end do
       do j = 1, m3
          kern_theta(j) = rkhsak(x3, theta(j)) 
       end do

c     form direct product vector, arranged as it is in
c     the setup code (loop over R and theta with theta
c     innermost.) 
       index = 0
       do j = 1, m2
          do i = 1, m3
             index = index+1
             kern_dp(index)  = kern_r2(j)*kern_theta(i)
          end do
       end do

c     now generate V(R, theta), returned in vector e, for different r1
c     at these values of R, theta.  All the potential information is
c     contained in coef matrix, which is the set of RKHS coefficients;
c     each row is the coefficients (alpha) for one value of r1.

       call dgemv('N', m1, n2, 1.0d0, coef, nn, kern_dp, 1, 0.0d0, e, 1)

c     determine polynomial fit coefficients.  fitmat was set up
c     in gen_polyfit by SVD; it is the G matrix described in the paper.
       
       call dgemv('N', nnp, m1, 1.0d0, fitmat, maxnnp, e, 1, 0.0d0, 
     1      vr1coef, 1)

       return
       end
c
c
c     Initialization routine: generate RKHS coefficients by fitting to
c     2-d direct product of distance & angle kernels


       subroutine fit_rkhs2(n,y3,coef)
       implicit double precision (a-h,o-z)
       parameter(nn=50,maxpts=2000,nnn=nn*nn)
       parameter(lwork=nnn*20)
       dimension work(lwork),s(nnn)
       common/rkhs/x1a(NN),x2a(NN),x3a(NN),m1,m2,m3
       common/indexr/ind2(maxpts),ind3(maxpts),n2
       dimension coef(nnn),a(nnn,nnn),b(nnn),y3(nnn)
       data rcond/1.d-12/
c
       ii=(n-1)*n2
       do k=1,n2
          do l=1,n2
            a(k,l) =
     >               rkhsdk(x2a(ind2(ii+k)),x2a(ind2(ii+l)))*
     >               rkhsak(x3a(ind3(ii+k)),x3a(ind3(ii+l)))
          enddo
          b(k)=y3(k)
       enddo
c  do SVD fit and return coefficients
       call dgelss(n2,n2,1,a,nnn,b,nnn,s,rcond,irank,work,
     >              lwork,info)
c       print *, 'info= ',info,', nparms= ',n2,', rank= ',irank
c       write(6,10) rcond,s(1)/s(n2)
c 10     format('rcond= ',e9.1,', s(1)/s(np)= ',e9.1/)
c      write(35,'(e9.3)') (s(i),i=1,n2)
       do j=1,n2
        coef(j)=b(j)
       enddo
c
       return
       end
c

c  Initialization routine: generate fitting matrix for polynomial fit in r1
c  by singular value decomposition.  Uses recommended sequence of
c  LAPACK calls for overdetermined system.
c  Begun 5 September 2000 G. C. McBane

       subroutine gen_polyfit(r, np, nnp_req)
       implicit none

c     r : vector of ab initio positions. 
c     np : length of r
c     nnp_req: requested order of polynomial fit in r1

       integer np, nnp_req
       double precision r(np)

       integer nn
       parameter(nn=50)

c     Polyfit common block is used for communication between this routine
c     and rkhs2coef
c  Polyfit common block: used in gen_polyfit and in rkhs2coef
c  note that nn must be known in any routine that includes this file
c      include 'polyfit.fi'

      integer maxnnp
      parameter (maxnnp = 4)
      common /polyfit/ fitmat,  nnp
      integer nnp
      double precision fitmat(maxnnp, nn)


c     fitmat : fitting matrix G (effective inverse of design matrix
c     A).  Given a vector V of potential values at the np fitting
c     points, the coefficients of the best-fit polynomial through those
c     points will be fitmat*V.
c     nnp_req: the requested number of coefficients of the polynomial expansion.  
c     maxnnp: maximum number of coefficients for which storage
c     is available.
      
       common/keep2/r1e
       double precision r1e
       integer i, k, l
       integer  lwork

       parameter(lwork=nn*20)
       double precision work(lwork)
       double precision a(nn,maxnnp)
       double precision  d(maxnnp), e(maxnnp)
       double precision tauq(maxnnp), taup(maxnnp)
       double precision q(nn, maxnnp), pt(nn, maxnnp)
       integer info

       double precision diff, rcond, maxs
       data rcond/1.d-12/

       if (nnp_req .gt. maxnnp) then
          write(*, 1000) nnp_req, maxnnp
          stop
       else
          nnp = nnp_req
       end if
 1000  format(1x, 'nnp_req (',I2, ') too large in gen_polyfit.',
     1       '  Bailing out.', /, 
     2      1x, 'Change max_nnp in polyfit.fi and recompile.' )

c  form the (Vandermonde) design matrix A.
       do k = 1, np
          a(k,1) = 1.0d0
          diff = r(k) - r1e
          do l = 2, nnp
             a(k, l) = a(k, l-1)*diff
          end do
       end do

c     reduce A to band diagonal form

       call dgebrd(np, nnp, a, nn, d, e, tauq, taup,
     1      work, lwork, info)

c  copy a into q and pt (only one copy really necessary)
      do i = 1, nnp
         call dcopy(np, a(1,i), 1, q(1,i), 1)
         call dcopy(np, a(1,i), 1, pt(1,i), 1)
      end do 

c     generate first nnp columns of Q matrix 
      call dorgbr('Q', np, nnp, nnp, q, nn, tauq, work, lwork, info)
c     generate PT matrix (square, nnp x nnp)
      call dorgbr('P', nnp, nnp, np, pt, nn, taup, work, lwork, info)

c     perform SVD of band diagonal matrix. a is here as a dummy argument;
c     nothing will be done with it.  U and V^T matrices from SVD 
c     are returned in q and pt respectively.

      call dbdsqr('U', nnp, nnp, np, 0, d, e, pt, nn, q, nn, a, nn, 
     1     work, info)


c     scale columns of U (stored in q) by reciprocal singular values,
c     unless the singular values are too small, in which case we zero
c     those columns

      maxs = d(1)
      do i = 1, nnp
         if (d(i)/maxs .ge. rcond) then
            call dscal(np, 1.0d0/d(i), q(1,i), 1)
         else
            call dscal(np, 0.0d0, q(1,i), 1)
            write(*, 1010) i, d(i)/maxs
         end if
      end do

 1010 format('Note; polynomial fitting matrix is rank-deficient.  ',/,
     1     's(i)/smax for column ', I2, 'is ', G10.2)

c     now V*U^T gets us the effective inverse matrix

      call dgemm('T', 'T', nnp, np, nnp, 1.0d0, pt, nn,
     1     q, nn, 0.0d0, fitmat, maxnnp)



      return
      end





