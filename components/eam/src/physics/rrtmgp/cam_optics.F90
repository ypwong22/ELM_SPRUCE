module cam_optics

   use shr_kind_mod, only: r8=>shr_kind_r8
   use assertions, only: assert, assert_valid, assert_range
   use radconstants, only: nswbands, nlwbands
   use rad_constituents, only: icecldoptics, liqcldoptics
   use cam_abortutils, only: endrun
   use ppgrid, only: pcols, pver

   implicit none
   private

   public get_cloud_optics_sw, &
          get_cloud_optics_lw, &
          sample_cloud_optics_sw, &
          sample_cloud_optics_lw, &
          set_aerosol_optics_sw, &
          set_aerosol_optics_lw

contains

   !-------------------------------------------------------------------------------

   subroutine get_cloud_optics_sw( &
         ncol, nlev, nbnd, do_snow, cld, cldfsnow, iclwp, iciwp, icswp, &
         lambdac, mu, dei, des, rel, rei, &
         tau_out, ssa_out, asm_out, &
         liq_tau_out, ice_tau_out, snw_tau_out)

      use ppgrid, only: pcols
      use physics_types, only: physics_state
      use cloud_rad_props, only: mitchell_ice_optics_sw, gammadist_liq_optics_sw
      use ebert_curry, only: ec_ice_optics_sw
      use slingo, only: slingo_liq_optics_sw

      integer, intent(in) :: ncol, nlev, nbnd
      logical, intent(in) :: do_snow
      real(r8), intent(in), dimension(:,:) :: &
         cld, cldfsnow, iclwp, iciwp, icswp, &
         lambdac, mu, dei, des, rel, rei

      ! Outputs are shortwave cloud optical properties *by band*. Dimensions should
      ! be nswbands,ncol,nlev. Generally, this should be able to handle cases were
      ! ncol might be something like nday, and nlev could be arbitrary so long as
      ! corresponding fields were defined for all indices of nlev. This
      ! isn't the case right now I don't think, as cloud_rad_props makes explicit
      ! assumptions about array sizes.
      real(r8), intent(out), dimension(:,:,:) :: &
         tau_out, ssa_out, asm_out, liq_tau_out, ice_tau_out, snw_tau_out

      ! Temporary variables to hold cloud optical properties before combining into
      ! output arrays. Same shape as output arrays, so get shapes from output.
      real(r8), dimension(nbnd,pcols,nlev) :: &
            liq_tau, liq_tau_ssa, liq_tau_ssa_g, liq_tau_ssa_f, &
            ice_tau, ice_tau_ssa, ice_tau_ssa_g, ice_tau_ssa_f, &
            cld_tau, cld_tau_ssa, cld_tau_ssa_g, cld_tau_ssa_f, &
            snow_tau, snow_tau_ssa, snow_tau_ssa_g, snow_tau_ssa_f, &
            combined_tau, combined_tau_ssa, combined_tau_ssa_g, combined_tau_ssa_f

      integer :: iband, ilev, icol

      ! Initialize outputs
      tau_out = 0._r8
      ssa_out = 0._r8
      asm_out = 0._r8
      liq_tau_out = 0._r8
      ice_tau_out = 0._r8
      snw_tau_out = 0._r8

      ! Initialize local variables
      ice_tau = 0._r8
      ice_tau_ssa = 0._r8
      ice_tau_ssa_g = 0._r8
      ice_tau_ssa_f = 0._r8
      liq_tau = 0._r8
      liq_tau_ssa = 0._r8
      liq_tau_ssa_g = 0._r8
      liq_tau_ssa_f = 0._r8
      snow_tau = 0._r8
      snow_tau_ssa = 0._r8
      snow_tau_ssa_g = 0._r8
      snow_tau_ssa_f = 0._r8
      combined_tau = 0._r8
      combined_tau_ssa = 0._r8
      combined_tau_ssa_g = 0._r8
      combined_tau_ssa_f = 0._r8

      ! Get ice cloud optics
      if (trim(icecldoptics) == 'mitchell') then
         call mitchell_ice_optics_sw( &
            ncol, nlev, iciwp, dei, &
            ice_tau, ice_tau_ssa, &
            ice_tau_ssa_g, ice_tau_ssa_f &
         )
      else if (trim(icecldoptics) == 'ebertcurry') then
         call ec_ice_optics_sw(ncol, nlev, cld, iciwp, rei, ice_tau, ice_tau_ssa, ice_tau_ssa_g, ice_tau_ssa_f)
      else
         call endrun('icecldoptics ' // trim(icecldoptics) // ' not supported.')
      end if
      call assert_range(ice_tau(1:nbnd,1:ncol,1:nlev), 0._r8, 1e20_r8, &
                        'get_cloud_optics_sw: ice_tau')
      
      ! Get liquid cloud optics
      if (trim(liqcldoptics) == 'gammadist') then
         call gammadist_liq_optics_sw( &
            ncol, nlev, iclwp, lambdac, mu, &
            liq_tau, liq_tau_ssa, &
            liq_tau_ssa_g, liq_tau_ssa_f &
         )
      else if (trim(liqcldoptics) == 'slingo') then
         call slingo_liq_optics_sw( &
            ncol, nlev, cld, iclwp, rel, &
            liq_tau, liq_tau_ssa, &
            liq_tau_ssa_g, liq_tau_ssa_f &
         )
      else
         call endrun('liqcldoptics ' // trim(liqcldoptics) // ' not supported.')
      end if

      call assert_range(liq_tau(1:nbnd,1:ncol,1:nlev), 0._r8, 1e20_r8, &
                        'get_cloud_optics_sw: liq_tau')

      ! Get snow cloud optics
      if (do_snow) then
         call mitchell_ice_optics_sw( &
            ncol, nlev, icswp, des, &
            snow_tau, snow_tau_ssa, &
            snow_tau_ssa_g, snow_tau_ssa_f &
         )
      else
         ! We are not doing snow optics, so set these to zero so we can still use 
         ! the arrays without additional logic
         snow_tau(:,:,:) = 0._r8
         snow_tau_ssa(:,:,:) = 0._r8
         snow_tau_ssa_g(:,:,:) = 0._r8
         snow_tau_ssa_f(:,:,:) = 0._r8
      end if

      ! Combine all cloud optics from CAM routines
      cld_tau = ice_tau + liq_tau
      cld_tau_ssa = ice_tau_ssa + liq_tau_ssa
      cld_tau_ssa_g = ice_tau_ssa_g + liq_tau_ssa_g
      if (do_snow) then
         call combine_properties( &
            nbnd, ncol, nlev, &
            cld(1:ncol,1:nlev), cld_tau(1:nbnd,1:ncol,1:nlev), &
            cldfsnow(1:ncol,1:nlev), snow_tau(1:nbnd,1:ncol,1:nlev), &
            combined_tau(1:nbnd,1:ncol,1:nlev) &
         )
         call combine_properties( &
            nbnd, ncol, nlev, &
            cld(1:ncol,1:nlev), cld_tau_ssa(1:nbnd,1:ncol,1:nlev), &
            cldfsnow(1:ncol,1:nlev), snow_tau_ssa(1:nbnd,1:ncol,1:nlev), &
            combined_tau_ssa(1:nbnd,1:ncol,1:nlev) &
         )
         call combine_properties( &
            nbnd, ncol, nlev, &
            cld(1:ncol,1:nlev), cld_tau_ssa_g(1:nbnd,1:ncol,1:nlev), &
            cldfsnow(1:ncol,1:nlev), snow_tau_ssa_g(1:nbnd,1:ncol,1:nlev), &
            combined_tau_ssa_g(1:nbnd,1:ncol,1:nlev) &
         )
      else
         combined_tau = cld_tau
         combined_tau_ssa = cld_tau_ssa
         combined_tau_ssa_g = cld_tau_ssa_g
      end if

      ! Copy to output arrays, converting to optical depth, single scattering
      ! albedo, and assymmetry parameter from the products that the CAM routines
      ! return. Make sure we do not try to divide by zero...
      do iband = 1,nbnd
         tau_out(:ncol,:nlev,iband) = combined_tau(iband,:ncol,:nlev)
         where (combined_tau(iband,:ncol,:nlev) > 0)
            ssa_out(:ncol,:nlev,iband) &
               = combined_tau_ssa(iband,:ncol,:nlev) / combined_tau(iband,:ncol,:nlev)
         elsewhere
            ssa_out(:ncol,:nlev,iband) = 1._r8
         endwhere
         where (combined_tau_ssa(iband,:ncol,:nlev) > 0)
            asm_out(:ncol,:nlev,iband) &
               = combined_tau_ssa_g(iband,:ncol,:nlev) / combined_tau_ssa(iband,:ncol,:nlev)
         elsewhere
            asm_out(:ncol,:nlev,iband) = 0._r8
         end where

         ! Re-order diagnostics outputs
         liq_tau_out(:ncol,:nlev,iband) = liq_tau(iband,:ncol,:nlev)
         ice_tau_out(:ncol,:nlev,iband) = ice_tau(iband,:ncol,:nlev)
         snw_tau_out(:ncol,:nlev,iband) = snow_tau(iband,:ncol,:nlev)
      end do

      ! Check values
      call assert_range(tau_out(:ncol,:nlev,:nbnd), 0._r8, 1e20_r8, &
                        'get_cloud_optics_sw: tau_out')
      call assert_range(ssa_out(:ncol,:nlev,:nbnd), 0._r8, 1._r8, &
                        'get_cloud_optics_sw: ssa_out')
      call assert_range(asm_out(:ncol,:nlev,:nbnd), -1._r8, 1._r8, &
                        'get_cloud_optics_sw: asm_out')
   end subroutine get_cloud_optics_sw

   !----------------------------------------------------------------------------

   subroutine get_cloud_optics_lw( &
         ncol, nlev, nbnd, do_snow, cld, cldfsnow, iclwp, iciwp, icswp, &
         lambdac, mu, dei, des, rei, &
         tau_out, liq_tau_out, ice_tau_out, snw_tau_out)

      use ppgrid, only: pcols
      use cloud_rad_props, only: gammadist_liq_optics_lw, mitchell_ice_optics_lw
      use ebert_curry, only: ec_ice_optics_lw
      use slingo, only: slingo_liq_optics_lw
      use radconstants, only: nlwbands

      integer, intent(in) :: ncol, nlev, nbnd
      logical, intent(in) :: do_snow
      real(r8), intent(in), dimension(:,:) :: &
         cld, cldfsnow, &
         iclwp, iciwp, icswp, &
         mu, lambdac, dei, des, rei
      real(r8), intent(out), dimension(:,:,:) :: tau_out, liq_tau_out, ice_tau_out, snw_tau_out

      ! Temporary variables to hold absorption optical depth
      real(r8), dimension(nbnd,pcols,nlev) :: &
            ice_tau, liq_tau, snow_tau, cld_tau, combined_tau

      integer :: iband

      ! Initialize outputs
      tau_out = 0._r8
      liq_tau_out = 0._r8
      ice_tau_out = 0._r8
      snw_tau_out = 0._r8

      ! Initialize local variables
      ice_tau(:,:,:) = 0._r8
      liq_tau(:,:,:) = 0._r8
      snow_tau(:,:,:) = 0._r8
      cld_tau(:,:,:) = 0._r8
      combined_tau(:,:,:) = 0._r8

      ! Get ice optics
      if (trim(icecldoptics) == 'mitchell') then
         call mitchell_ice_optics_lw(ncol, nlev, iciwp, dei, ice_tau)
      else if (trim(icecldoptics) == 'ebertcurry') then
         call ec_ice_optics_lw(ncol, nlev, cld, iclwp, iciwp, rei, ice_tau)
      else
         call endrun('icecldoptics ' // trim(icecldoptics) // ' not supported.')
      end if

      ! Get liquid optics
      if (trim(liqcldoptics) == 'gammadist') then
         call gammadist_liq_optics_lw(ncol, nlev, iclwp, lambdac, mu, liq_tau)
      else if (trim(liqcldoptics) == 'slingo') then
         call slingo_liq_optics_lw(ncol, nlev, cld, iclwp, iciwp, liq_tau)
      else
         call endrun('liqcldoptics ' // trim(liqcldoptics) // ' not supported.')
      end if

      ! Combined cloud optics
      cld_tau = liq_tau + ice_tau

      ! Get snow optics?
      if (do_snow) then
         call mitchell_ice_optics_lw(ncol, nlev, icswp, des, snow_tau)
         call combine_properties(nbnd, ncol, nlev, &
            cld(1:ncol,1:nlev), cld_tau(1:nbnd,1:ncol,1:nlev), &
            cldfsnow(1:ncol,1:nlev), snow_tau(1:nbnd,1:ncol,1:nlev), &
            combined_tau(1:nbnd,1:ncol,1:nlev) &
         )
      else
         combined_tau(1:nbnd,1:ncol,1:nlev) = cld_tau(1:nbnd,1:ncol,1:nlev)
      end if

      ! Set output optics
      do iband = 1,nbnd
         tau_out(1:ncol,1:nlev,iband) = combined_tau(iband,1:ncol,1:nlev)
         liq_tau_out(1:ncol,1:nlev,iband) = liq_tau(iband,1:ncol,1:nlev)
         ice_tau_out(1:ncol,1:nlev,iband) = ice_tau(iband,1:ncol,1:nlev)
         snw_tau_out(1:ncol,1:nlev,iband) = snow_tau(iband,1:ncol,1:nlev)
      end do

      ! Check values
      call assert_range(tau_out(:ncol,:nlev,:nbnd), 0._r8, 1e20_r8, &
                        'get_cloud_optics_lw: tau_out')

   end subroutine get_cloud_optics_lw

   !----------------------------------------------------------------------------

   ! Provide a procedure to combine cloud optical properties by weighting
   ! contributions by fraction present. I.e., for combining cloud and snow
   ! optical properties, we weight the cloud and snow properties by the fraction
   ! of cloud and snow present.
   subroutine combine_properties(nbands, ncols, nlevs, &
                                 fraction1, property1, &
                                 fraction2, property2, &
                                 combined_property)
      
      ! Input dimensions for automatic error checking
      integer, intent(in) :: nbands, ncols, nlevs

      ! Input fractions of each type of constituent
      real(r8), intent(in) :: fraction1(ncols,nlevs), fraction2(ncols,nlevs)

      ! Individual optical properties for each constituent
      real(r8), intent(in) :: property1(nbands,ncols,nlevs), property2(nbands,ncols,nlevs)

      ! Combined optical property
      real(r8), intent(out) :: combined_property(nbands,ncols,nlevs)

      ! Combined fraction (max of property 1 and 2)
      real(r8) :: combined_fraction(ncols,nlevs)

      ! Loop variables
      integer :: iband, icol, ilev

      ! Combined fraction
      combined_fraction = max(fraction1, fraction2)

      ! Combine optical properties by weighting by amount of cloud and snow
      combined_property = 0._r8
      do ilev = 1,nlevs
         do icol = 1,ncols
            do iband = 1,nbands
               if (combined_fraction(icol,ilev) > 0) then
                  combined_property(iband,icol,ilev) = ( &
                     fraction1(icol,ilev) * property1(iband,icol,ilev) &
                   + fraction2(icol,ilev) * property2(iband,icol,ilev) &
                  ) / combined_fraction(icol,ilev)
               else
                  combined_property(iband,icol,ilev) = 0._r8
               end if
            end do
         end do
      end do

   end subroutine combine_properties

   !----------------------------------------------------------------------------

   ! Do MCICA sampling of optics here. This will map bands to gpoints,
   ! while doing stochastic sampling of cloud state
   subroutine sample_cloud_optics_sw( &
         ncol, nlev, ngpt, gpt2bnd, &
         pmid, cld, cldfsnow, &
         tau_bnd, ssa_bnd, asm_bnd, &
         tau_gpt, ssa_gpt, asm_gpt)
      use mcica_subcol_gen, only: mcica_subcol_mask
      integer, intent(in) :: ncol, nlev, ngpt
      integer, intent(in), dimension(:) :: gpt2bnd
      real(r8), intent(in), dimension(:,:) :: pmid, cld, cldfsnow
      real(r8), intent(in), dimension(:,:,:) :: tau_bnd, ssa_bnd, asm_bnd
      real(r8), intent(out), dimension(:,:,:) :: tau_gpt, ssa_gpt, asm_gpt
      real(r8), dimension(ncol,nlev) :: combined_cld
      logical, dimension(ngpt,ncol,nlev) :: iscloudy

      ! For MCICA sampling routine, how many times to permute random seed
      integer, parameter :: changeseed = 1

      ! Loop variables
      integer :: icol, ilev, igpt

      ! Combined snow and cloud fraction
      combined_cld(1:ncol,1:nlev) = max(cld(1:ncol,1:nlev), &
                                        cldfsnow(1:ncol,1:nlev))
      ! Get stochastic subcolumn cloud mask
      call mcica_subcol_mask(ngpt, ncol, nlev, changeseed, &
                             pmid(1:ncol,1:nlev), &
                             combined_cld(1:ncol,1:nlev), &
                             iscloudy(1:ngpt,1:ncol,1:nlev))
      ! Generate subcolumns for homogeneous clouds
      do igpt = 1,ngpt
         do ilev = 1,nlev
            do icol = 1,ncol
               if (iscloudy(igpt,icol,ilev) .and. combined_cld(icol,ilev) > 0._r8) then
                  tau_gpt(icol,ilev,igpt) = tau_bnd(icol,ilev,gpt2bnd(igpt))
                  ssa_gpt(icol,ilev,igpt) = ssa_bnd(icol,ilev,gpt2bnd(igpt))
                  asm_gpt(icol,ilev,igpt) = asm_bnd(icol,ilev,gpt2bnd(igpt))
               else
                  tau_gpt(icol,ilev,igpt) = 0._r8
                  ssa_gpt(icol,ilev,igpt) = 1._r8
                  asm_gpt(icol,ilev,igpt) = 0._r8
               end if
            end do
         end do
      end do
   end subroutine sample_cloud_optics_sw

   !----------------------------------------------------------------------------

   !----------------------------------------------------------------------------

   ! Do MCICA sampling of optics here. This will map bands to gpoints,
   ! while doing stochastic sampling of cloud state
   subroutine sample_cloud_optics_lw( &
         ncol, nlev, ngpt, gpt2bnd, &
         pmid, cld, cldfsnow, &
         tau_bnd, tau_gpt)
      use mcica_subcol_gen, only: mcica_subcol_mask

      integer, intent(in) :: ncol, nlev, ngpt
      integer, intent(in), dimension(:) :: gpt2bnd
      real(r8), intent(in), dimension(:,:) :: pmid, cld, cldfsnow
      real(r8), intent(in), dimension(:,:,:) :: tau_bnd
      real(r8), intent(out), dimension(:,:,:) :: tau_gpt
      real(r8), dimension(ncol,nlev) :: combined_cld
      logical, dimension(ngpt,ncol,nlev) :: iscloudy

      ! For MCICA sampling routine, how many times to permute random seed
      integer, parameter :: changeseed = 1

      ! Loop variables
      integer :: icol, ilev, igpt

      ! Combine cloud and snow fractions for MCICA sampling
      combined_cld(1:ncol,1:nlev) = max(cld(1:ncol,1:nlev), &
                                        cldfsnow(1:ncol,1:nlev))

      ! Get the stochastic subcolumn cloudy mask
      call mcica_subcol_mask(ngpt, ncol, nlev, changeseed, &
                             pmid(1:ncol,1:nlev), &
                             combined_cld(1:ncol,1:nlev), &
                             iscloudy(1:ngpt,1:ncol,1:nlev))

      ! Map optics to g-points, selecting a single subcolumn for each
      ! g-point. This implementation generates homogeneous clouds, but it would be
      ! straightforward to extend this to handle horizontally heterogeneous clouds
      ! as well.
      do igpt = 1,ngpt
         do ilev = 1,nlev
            do icol = 1,ncol
               if (iscloudy(igpt,icol,ilev) .and. combined_cld(icol,ilev) > 0._r8) then
                  tau_gpt(icol,ilev,igpt) = tau_bnd(icol,ilev,gpt2bnd(igpt))
               else
                  tau_gpt(icol,ilev,igpt) = 0._r8
               end if
            end do
         end do
      end do
   end subroutine sample_cloud_optics_lw

   !----------------------------------------------------------------------------

   subroutine set_aerosol_optics_sw(icall, dt, state, pbuf, &
                                    night_indices, &
                                    is_cmip6_volc, &
                                    tau_out, ssa_out, asm_out, &
                                    clear_rh)
      use ppgrid, only: pcols, pver
      use physics_types, only: physics_state
      use physics_buffer, only: physics_buffer_desc
      use aer_rad_props, only: aer_rad_props_sw
      use radconstants, only: nswbands, idx_sw_diag
#if defined(MMF_SAMXX) || defined(MMF_PAM)
      use prescribed_macv2, only: do_macv2sp
#endif
      use cam_history, only: outfld
      integer, intent(in) :: icall
      real(r8), intent(in):: dt
      type(physics_state), intent(in) :: state
      type(physics_buffer_desc), pointer :: pbuf(:)
      integer, intent(in) :: night_indices(:)
      logical, intent(in) :: is_cmip6_volc
      real(r8), intent(out), dimension(:,:,:) :: tau_out, ssa_out, asm_out
      real(r8), optional,  intent(in)    :: clear_rh(pcols,pver) ! optional clear air relative humidity
                                                                 ! that gets passed to modal_aero_wateruptake_dr

      ! NOTE: aer_rad_props expects 0:pver indexing on these! It appears this is to
      ! account for the extra layer added above model top, but it is not entirely
      ! clear. This is not done for the longwave, and it is not really documented
      ! anywhere that I can find. Regardless, optical properties for the zero index
      ! are set to zero in aer_rad_props_sw as far as I can tell.
      !
      ! NOTE: dimension ordering is different than for cloud optics!
      real(r8), dimension(pcols,0:pver,nswbands) :: tau, tau_w, tau_w_g, tau_w_f
      ! NOTE: MACv2 array only has pver levels, so initialize differently
      real(r8), dimension(pcols,1:pver,nswbands) :: mac_tau, mac_tau_w, &
           mac_tau_w_g, mac_tau_w_f
      real(r8) :: itau
      real(r8) :: itauw(2)
      real(r8) :: itaug(2)

      integer :: ncol
      integer :: icol, ilay
      integer :: isw              ! additional loop indices

      ! Everyone needs a name
      character(len=*), parameter :: subroutine_name = 'set_aerosol_optics_sw'

#if !defined(MMF_SAMXX) && !defined(MMF_PAM)
      logical :: do_macv2sp = .false.
#endif

      ncol = state%ncol

      ! Get aerosol absorption optical depth from CAM routine
      tau = 0._r8
      tau_w = 0._r8
      tau_w_g = 0._r8
      tau_w_f = 0._r8
      call aer_rad_props_sw(icall, dt, state, pbuf, &
           count(night_indices > 0), night_indices, is_cmip6_volc, &
           tau, tau_w, tau_w_g, tau_w_f, clear_rh=clear_rh)

      ! Combine MACv2-SP aerosol optical properties with natural aerosols
      ! note that AEROD_v is already written to history file in aer_rad_props_sw
      ! so the MACv2SP effect is not included
               
      if ( (icall == 0) .AND. (do_macv2sp) ) then
         mac_tau     = 0._r8
         mac_tau_w   = 0._r8
         mac_tau_w_g = 0._r8
         mac_tau_w_f = 0._r8

         call outfld('NAT_TAU',     tau(    :,1:pver,idx_sw_diag), pcols, state%lchnk)
         call outfld('NAT_TAU_W',   tau_w(  :,1:pver,idx_sw_diag), pcols, state%lchnk)
         call outfld('NAT_TAU_W_G', tau_w_g(:,1:pver,idx_sw_diag), pcols, state%lchnk)
         call outfld('NAT_TAU_W_F', tau_w_f(:,1:pver,idx_sw_diag), pcols, state%lchnk)
         
         call set_macv2_aerosol_optics(state, pbuf, mac_tau, &
              mac_tau_w, mac_tau_w_g, mac_tau_w_f)

         call outfld('MAC_TAU',     mac_tau(    :,1:pver,idx_sw_diag), pcols, state%lchnk)
         call outfld('MAC_TAU_W',   mac_tau_w(  :,1:pver,idx_sw_diag), pcols, state%lchnk)
         call outfld('MAC_TAU_W_G', mac_tau_w_g(:,1:pver,idx_sw_diag), pcols, state%lchnk)
         call outfld('MAC_TAU_W_F', mac_tau_w_f(:,1:pver,idx_sw_diag), pcols, state%lchnk)

         do isw = 1, nswbands
            do ilay = 1, pver
               do icol = 1, ncol
                  ! A quick reference for how to combine optical properties
                  ! t = tau; w = SSA; g = asymmetry parameter
                  ! t = t1 + t2
                  ! w = (w1*t1 + w2*t2) / (t1 + t2)
                  ! g = (g1*w1*t1 + g2*w2*t2) / (w1*t1 + w2*t2)
                  !
                  ! So if tau_w_g = (g1*w1*t1 + g2*tw*t2)
                  !       tau_w   = (w1*t1 + w2*t2)
                  !       tau     = (t1 + t2)
                  ! Then, g = tau_w_g / tau_w, w = tau_w / tau, and t = tau, as desired
                  tau_w_f(icol,ilay,isw) = tau_w_f(icol,ilay,isw) + mac_tau_w_f(icol,ilay,isw)
                  tau_w_g(icol,ilay,isw) = tau_w_g(icol,ilay,isw) + mac_tau_w_g(icol,ilay,isw)
                  tau_w(  icol,ilay,isw) = tau_w(  icol,ilay,isw) + mac_tau_w(  icol,ilay,isw)
                  tau(    icol,ilay,isw) = tau(    icol,ilay,isw) + mac_tau(    icol,ilay,isw)
                                                
               end do
            end do
         end do
                                                             
         !these 3 variables has pver+1 levels
         call outfld('AER_TAU',     tau(    :,1:pver,idx_sw_diag), pcols, state%lchnk)
         call outfld('AER_TAU_W',   tau_w(  :,1:pver,idx_sw_diag), pcols, state%lchnk)
         call outfld('AER_TAU_W_G', tau_w_g(:,1:pver,idx_sw_diag), pcols, state%lchnk)
         call outfld('AER_TAU_W_F', tau_w_f(:,1:pver,idx_sw_diag), pcols, state%lchnk)

      end if

      ! Extract quantities from products
      do icol = 1,ncol
         ! Copy cloud optical depth over directly
         tau_out(icol,1:pver,1:nswbands) = tau(icol,1:pver,1:nswbands)
         ! Extract single scattering albedo from the product-defined fields
         where (tau(icol,1:pver,1:nswbands) > 0)
            ssa_out(icol,1:pver,1:nswbands) &
               = tau_w(icol,1:pver,1:nswbands) / tau(icol,1:pver,1:nswbands)
         elsewhere
            ssa_out(icol,1:pver,1:nswbands) = 1._r8
         endwhere
         ! Extract assymmetry parameter from the product-defined fields
         where (tau_w(icol,1:pver,1:nswbands) > 0)
            asm_out(icol,1:pver,1:nswbands) &
               = tau_w_g(icol,1:pver,1:nswbands) / tau_w(icol,1:pver,1:nswbands)
         elsewhere
            asm_out(icol,1:pver,1:nswbands) = 0._r8
         endwhere
      end do

   end subroutine set_aerosol_optics_sw

   !----------------------------------------------------------------------------

   subroutine set_aerosol_optics_lw(icall, dt, state, pbuf, is_cmip6_volc, tau)
     
      use ppgrid, only: pcols, pver
      use physics_types, only: physics_state
      use physics_buffer, only: physics_buffer_desc, pbuf_get_index, &
                                pbuf_get_field, pbuf_old_tim_idx
      use aer_rad_props, only: aer_rad_props_lw
      use radconstants, only: nlwbands

      integer, intent(in) :: icall
      real(r8), intent(in) :: dt   ! time step(s)
      type(physics_state), intent(in) :: state
      type(physics_buffer_desc), pointer :: pbuf(:)
      logical, intent(in) :: is_cmip6_volc
      real(r8), intent(out), dimension(:,:,:) :: tau(pcols,pver,nlwbands)

      ! Subroutine name for error messages
      character(len=*), parameter :: subroutine_name = 'set_aerosol_optics_lw'

      ! Get aerosol absorption optical depth from CAM routine
      tau = 0._r8
      call aer_rad_props_lw(is_cmip6_volc, icall, dt, state, pbuf, tau)

   end subroutine set_aerosol_optics_lw

   !----------------------------------------------------------------------------

   subroutine set_macv2_aerosol_optics(state, pbuf, &
                                       tau, tau_w, tau_w_g, tau_w_f)

      use ppgrid,           only: pcols, pver
      use physics_types,    only: physics_state
      use physics_buffer,   only: physics_buffer_desc
      use aer_rad_props,    only: aer_rad_props_sw
      use radconstants,     only: nswbands, wavenum_sw_lower, wavenum_sw_upper
#if defined(MMF_SAMXX) || defined(MMF_PAM)
      use prescribed_macv2, only: do_macv2sp, sp_aop_profile, swbandnum
#endif
      use time_manager,     only: get_curr_date, get_curr_calday
      use physconst,        only: gravit
      use cam_history,      only: addfld, outfld
      use phys_grid,        only: get_rlat_all_p, get_rlon_all_p
      
      type(physics_state), intent(in)         :: state
      type(physics_buffer_desc), pointer      :: pbuf(:)
      real(r8), intent(out), dimension(:,:,:) :: tau, tau_w, tau_w_g, tau_w_f

      ! add variables for MACv2-SP
      integer  :: yr, mon, day     ! year, month, and day components of date
      integer  :: ncsec            ! current time of day [seconds]
      real(r8) :: calday           ! current calendar day
      real(r8) :: clat(pcols)      ! current latitudes(radians)
      real(r8) :: clon(pcols)      ! current longitudes(radians)
      integer  :: isw              ! additional loop indices
      real(r8) :: lambda           !SW wavelengh input to MACV2
      real(r8) :: year_fr
      real(r8) :: aod_prof(pcols,pver,nswbands)  ! profile of aerosol optical depth
      real(r8) :: ssa_prof(pcols,pver,nswbands)  ! profile of single scattering albedo
      real(r8) :: asy_prof(pcols,pver,nswbands)  ! profile of asymmetry parameter
      integer  :: ncol
      integer  :: icol, ilay

      ! Subroutine name for error messages
      character(len=*), parameter :: subroutine_name = 'set_macv2_aerosol_optics'

#if !defined(MMF_SAMXX) && !defined(MMF_PAM)
      logical :: do_macv2sp = .false.
      character(len=5) :: swbandnum(nswbands) =(/'_sw01','_sw02','_sw03','_sw04','_sw05','_sw06','_sw07','_sw08','_sw09','_sw10','_sw11','_sw12','_sw13','_sw14'/)
#endif

      if ( .not. do_macv2sp ) return

      ! calculate MACv2-SP aerosol direct effects 
      ! get year fraction for MACv2-SP's prescribed annual cycle and year-to-year variability

      ncol    = state%ncol

      call get_curr_date(yr, mon, day, ncsec)
      calday  = get_curr_calday()
      year_fr = yr + calday/365.0_r8

      call get_rlat_all_p(state%lchnk, ncol, clat(1:ncol))
      call get_rlon_all_p(state%lchnk, ncol, clon(1:ncol))

      do isw = 1, nswbands
               
      !get the bin-center wavelength from the wave number bin  (in the units of nm)
      !this is an input to the sp_aop_profile subroutine of MACv2-SP
         lambda = 10.0_r8**7*( wavenum_sw_lower(isw)**(-1) + wavenum_sw_upper(isw)**(-1) )/2.0_r8 

#if defined(MMF_SAMXX) || defined(MMF_PAM)
         call sp_aop_profile (ncol, lambda, state%phis/gravit, clon, clat, year_fr, state%zm, &
              aod_prof(:,:,isw), ssa_prof(:,:,isw), asy_prof(:,:,isw), state%lchnk, isw)
#endif
      ! state%phis/gravit for orography in [m]

      ! output diagnostic variables for MACv2-SP, only for the mid-visible wavelength
         call outfld('MACv2_aod'//swbandnum(isw),  aod_prof(:,:,isw),  pcols, state%lchnk)
         call outfld('MACv2_ssa'//swbandnum(isw),  ssa_prof(:,:,isw),  pcols, state%lchnk)
         call outfld('MACv2_asy'//swbandnum(isw),  asy_prof(:,:,isw),  pcols, state%lchnk)

      ! prepare arrays to be combined with EAM's aerosol optical parameters 
         ! e.g, single-scattering albedo multiplied by optical depth
         do icol = 1, ncol
            do ilay = 1, pver
               tau(    icol, ilay, isw) = aod_prof(icol, ilay, isw)
               tau_w(  icol, ilay, isw) = aod_prof(icol, ilay, isw) * ssa_prof(icol, ilay, isw)
               tau_w_g(icol, ilay, isw) = tau_w(   icol, ilay, isw) * asy_prof(icol, ilay, isw)
               tau_w_f(icol, ilay, isw) = tau_w_g( icol, ilay, isw) * asy_prof(icol, ilay, isw)
            end do
         end do
         
      end do ! isw = 1, nswbands

      

   end subroutine set_macv2_aerosol_optics

   !----------------------------------------------------------------------------
   !----------------------------------------------------------------------------

end module cam_optics
