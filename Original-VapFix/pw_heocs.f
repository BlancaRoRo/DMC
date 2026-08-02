      subroutine pw_vheocs(rjac,cth,v,nv)
      implicit real*8(a-h,o-z)
      parameter (npun=231,n=300,nlam=37,maxy=10000)
      dimension xa(npun,nlam),ya(npun,nlam),y2a(npun,nlam)
      common /datos /xa,ya,y2a
      dimension rjac(nv),cth(nv),v(nv),p(maxy,nlam+1)
      dimension y(maxy,nlam)

c ----------- loop over jacobi coordinates

        if(nv.le.maxy) then
        call vpleg(nlam,cth,p,maxy,nv)
        call splint(xa,ya,y2a,npun,rjac,y,maxy,nv,nlam)

      do i=1,nv
        vtot=0.0d0 
        do j=1,nlam
         vtot=vtot+y(i,j)*p(i,j)
        end do
        v(i)=vtot
      end do
      else
       write(6,'(/a/)') ' ny is larger than maxy in heco00'
      end if
      return
      end subroutine pw_vheocs

      subroutine vpleg(lmax,y,p,maxy,ny)
      implicit double precision (a-h,o-z)
      dimension p(maxy,*),y(ny)
c
      if(ny.gt.maxy) then
        write(6,'(/a/)') ' ny is larger than maxy in vpleg '
      else
        do i=1,ny
          p(i,1)=1.d0
          p(i,2)=y(i)
        end do
        if(lmax.gt.1) then  
          do 10 l=2,lmax
            lp=l+1
            lm=l-1
            xlml=dble(lm+l)
            xlm=dble(lm)
            xli=1.d0/dble(l)
            do i=1,ny
              p(i,lp)=(xlml*y(i)*p(i,l)-xlm*p(i,lm))*xli
            end do
 10       continue
        end if
      end if
      return
      end

      subroutine spline(xa,ya,n,yp1,ypn,y2a)
      implicit double precision (a-h,o-z)
      parameter (nmax=10000)
      dimension xa(n),ya(n),y2a(n),u(nmax)
      if (yp1.gt..99d30) then
        y2a(1)=0.d0
        u(1)=0.d0
      else
        y2a(1)=-0.5d0
        u(1)=(3.d0/(xa(2)-xa(1)))*((ya(2)-ya(1))/(xa(2)-xa(1))-yp1)
      endif
      do 11 i=2,n-1
        sig=(xa(i)-xa(i-1))/(xa(i+1)-xa(i-1))
        p=sig*y2a(i-1)+2.d0
        y2a(i)=(sig-1.d0)/p
        u(i)=(6.d0*((ya(i+1)-ya(i))/(xa(i+1)-xa(i))-(ya(i)-ya(i-1))
     &      /(xa(i)-xa(i-1)))/(xa(i+1)-xa(i-1))-sig*u(i-1))/p
11    continue
      if (ypn.gt..99d30) then
        qn=0.d0
        un=0.d0
      else
        qn=0.5d0
        un=(3.d0/(xa(n)-xa(n-1)))*(ypn-(ya(n)-ya(n-1))/(xa(n)-xa(n-1)))
      endif
      y2a(n)=(un-qn*u(n-1))/(qn*y2a(n-1)+1.)
      do 12 k=n-1,1,-1
        y2a(k)=y2a(k)*y2a(k+1)+u(k)
12    continue
      return
      end

      subroutine splint(xa,ya,y2a,n,rjac,y,maxy,ny,nlam)
      implicit double precision (a-h,o-z)
      dimension xa(n),ya(n,nlam),y2a(n,nlam),y(maxy,nlam)
      dimension rjac(ny)



c
      do i=1,ny
        x=rjac(i)

      if(x.lt.xa(1)) x=xa(1)
      if(x.ge.xa(n)) x=xa(n)-0.00001d0

      h=(xa(2)-xa(1))
      hinv=1.d0/h
      klo=(x-xa(1))*hinv+1
      khi=klo+1

c
c     klo=1
c     khi=n
c1     if (khi-klo.gt.1) then
c       k=(khi+klo)/2
c       if(xa(k).gt.x)then
c         khi=k
c       else
c         klo=k
c       endif
c     goto 1
c     endif
c     h=xa(khi)-xa(klo)
c     if (h.eq.0.d0) then
c       write(6,*) khi,klo,xa(khi),xa(klo)
c       pause 'bad xa input.'
c     end if
c
      a=(xa(khi)-x)*hinv
      b=(x-xa(klo))*hinv


        do j=1,nlam
            y(i,j)=a*ya(klo,j)+b*ya(khi,j)+
     &      ((a**3-a)*y2a(klo,j)+(b**3-b)*y2a(khi,j))*(h**2)/6.d0
        end do
       end do
      return
      end

c
      subroutine pw_leevheocs(fichpot)
      implicit real*8(a-h,o-z)
      character*(*)  fichpot
      parameter (npun=231,n=300,nlam=37,maxy=10000)
      dimension xa(npun,nlam),ya(npun,nlam),y2a(npun,nlam)
      common /datos /xa,ya,y2a
      character(len=50) :: referencia


      
c   ------ initialization done only in first call

        open(unit=1,file=fichpot,status="old")
        ypn=.0d0 
        do j=1,nlam
          do i=1,npun
           read(1,*) xa(i,j),ya(i,j)
          end do
          yp1=(ya(2,j)-ya(1,j))/(xa(2,j)-xa(1,j))
          call spline(xa(1,j),ya(1,j),npun,yp1,ypn,y2a(1,j))
        end do
        close(1)

       referencia="He-OCS Paesani and Whaley, JCP 121, 4180 (2004)"
       write(6,'("Referencia potencial ",t30,a)') trim(referencia)

      return
      end subroutine pw_leevheocs

      subroutine sacapw(xaout,yaout,y2aout)
      implicit real*8(a-h,o-z)
      parameter (npun=231,n=300,nlam=37,maxy=10000)
      dimension xa(npun,nlam),ya(npun,nlam),y2a(npun,nlam)
      common /datos /xa,ya,y2a
      dimension xaout(npun*nlam),yaout(npun*nlam),y2aout(npun*nlam)
    
      k=0
      do j=1,nlam
        do i=1,npun
          k=k+1
          xaout(k)=xa(i,j)
          yaout(k)=ya(i,j)
          y2aout(k)=y2a(i,j)
        enddo
      enddo

      end subroutine sacapw

      subroutine metepw(xain,yain,y2ain)
      implicit real*8(a-h,o-z)
      parameter (npun=231,n=300,nlam=37,maxy=10000)
      dimension xa(npun,nlam),ya(npun,nlam),y2a(npun,nlam)
      common /datos /xa,ya,y2a
      dimension xain(npun*nlam),yain(npun*nlam),y2ain(npun*nlam)

      k=0
      do j=1,nlam
        do i=1,npun
          k=k+1
          xa(i,j)=xain(k)
          ya(i,j)=yain(k)
          y2a(i,j)=y2ain(k)
        enddo
      enddo

      end subroutine metepw

