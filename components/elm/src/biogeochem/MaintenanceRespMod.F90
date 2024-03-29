module MaintenanceRespMod

  !-----------------------------------------------------------------------
  ! !DESCRIPTION:
  ! Module holding maintenance respiration routines for coupled carbon
  ! nitrogen code.
  !
  ! !USES:
  use shr_kind_mod        , only : r8 => shr_kind_r8
  use elm_varpar          , only : nlevgrnd, nlevdecomp
  use shr_const_mod       , only : SHR_CONST_TKFRZ
  use decompMod           , only : bounds_type
  use abortutils          , only : endrun
  use shr_log_mod         , only : errMsg => shr_log_errMsg
  use pftvarcon           , only : npcropmin
  use SharedParamsMod     , only : ParamsShareInst
  use AllocationMod       , only : AllocParamsInst
  use VegetationPropertiesType , only : veg_vp
  use SoilStateType       , only : soilstate_type
  use CanopyStateType     , only : canopystate_type
  use CNStateType         , only : cnstate_type
  use TemperatureType     , only : temperature_type
  use PhotosynthesisType  , only : photosyns_type
  use CNCarbonFluxType    , only : carbonflux_type
  use CNCarbonStateType   , only : carbonstate_type
  use CNNitrogenStateType , only : nitrogenstate_type
  use ColumnDataType      , only : col_es, col_ns, col_ps
  use VegetationType      , only : veg_pp
  use VegetationDataType  , only : veg_es, veg_cs, veg_cf, veg_ns
  use elm_varctl          , only: iulog
  use pftvarcon           , only: ndllf_evr_brl_tree, ndllf_dcd_brl_tree, nbrdlf_dcd_brl_shrub, nc3_arctic_grass
  !
  implicit none
  save
  private
  !
  ! !PUBLIC MEMBER FUNCTIONS:
  public :: MaintenanceResp
  public :: readMaintenanceRespParams

  type, private :: MaintenanceRespParamsType
     real(r8):: br_mr        !base rate for maintenance respiration(gC/gN/s)
     real(r8):: dormant_mr_temp ! Temperature for dormancy (K)
     real(r8):: dormant_mr_factor ! Dormancy multiplier for maint resp (unitless)
  end type MaintenanceRespParamsType

  !type(MaintenanceRespParamsType),private ::  MaintenanceRespParamsInst
  real(r8), public :: br_mr_Inst
  real(r8), public :: dormant_mr_temp_Inst
  real(r8), public :: dormant_mr_factor_Inst
  !$acc declare create(br_mr_Inst)
  !$acc declare create(dormant_mr_temp_Inst)
  !$acc declare create(dormant_mr_factor_Inst)
  !-----------------------------------------------------------------------

contains

  !-----------------------------------------------------------------------
   subroutine readMaintenanceRespParams ( ncid )
     !
     ! !DESCRIPTION:
     ! Read parameters
     !
     ! !USES:
     use ncdio_pio , only : file_desc_t,ncd_io
     !
     ! !ARGUMENTS:
     implicit none
     type(file_desc_t),intent(inout) :: ncid   ! pio netCDF file id
     !
     ! !LOCAL VARIABLES:
     character(len=32)  :: subname = 'MaintenanceRespParamsType'
     character(len=100) :: errCode = '-Error reading in parameters file:'
     logical            :: readv ! has variable been read in or not
     real(r8)           :: tempr ! temporary to read in constant
     character(len=100) :: tString ! temp. var for reading
     !-----------------------------------------------------------------------

     tString='br_mr'
     call ncd_io(varname=trim(tString),data=tempr, flag='read', ncid=ncid, readvar=readv)
     if ( .not. readv ) call endrun(msg=trim(errCode)//trim(tString)//errMsg(__FILE__, __LINE__))
     br_mr_Inst = tempr

     ! Add parameters for dormant maintenance resp
     tString='dormant_mr_temp'
     call ncd_io(varname=trim(tString),data=tempr, flag='read', ncid=ncid, readvar=readv)
     ! Default value: 0, so if it's missing the whole process is turned off
     if ( .not. readv ) then
        dormant_mr_temp_Inst=0.0_r8
     else
        dormant_mr_temp_Inst=tempr
     end if

     tString='dormant_mr_factor'
     call ncd_io(varname=trim(tString),data=tempr, flag='read', ncid=ncid, readvar=readv)
     if ( .not. readv .and. dormant_mr_temp_Inst == 0.0_r8) then
        ! Neither dormancy param is defined, so we can ignore both
        dormant_mr_temp_Inst=0.0_r8
     elseif ( .not. readv ) then
        ! Doesn't work if dormancy temp is defined and factor is not
        call endrun(msg=trim('-Error: dormant_mr_temp defined but dormant_mr_factor is not')//trim(tString)//errMsg(__FILE__,__LINE__))
     else
        dormant_mr_factor_Inst=tempr
     end if

     
   end subroutine readMaintenanceRespParams

  !-----------------------------------------------------------------------
  ! FIX(SPM,032414) this shouldn't even be called with ED on.
  !
  subroutine MaintenanceResp(bounds, &
       num_soilc, filter_soilc, num_soilp, filter_soilp, &
       canopystate_vars, soilstate_vars, photosyns_vars, cnstate_vars)
    !
    ! !DESCRIPTION:
    !
    ! !USES:
    use pftvarcon            , only: ndllf_dcd_brl_tree, nbrdlf_dcd_brl_shrub
    !
    ! !ARGUMENTS:
      !$acc routine seq
    type(bounds_type)        , intent(in)    :: bounds
    integer                  , intent(in)    :: num_soilc       ! number of soil points in column filter
    integer                  , intent(in)    :: filter_soilc(:) ! column filter for soil points
    integer                  , intent(in)    :: num_soilp       ! number of soil points in patch filter
    integer                  , intent(in)    :: filter_soilp(:) ! patch filter for soil points
    type(canopystate_type)   , intent(in)    :: canopystate_vars
    type(soilstate_type)     , intent(in)    :: soilstate_vars
    type(photosyns_type)     , intent(in)    :: photosyns_vars
    type(cnstate_type)       , intent(in)    :: cnstate_vars
    !
    ! !LOCAL VARIABLES:
    integer :: c,p,j ! indices
    integer :: fp    ! soil filter patch index
    integer :: fc    ! soil filter column index
    real(r8):: br_mr ! base rate (gC/gN/s)
    real(r8):: dormant_mr_temp ! Temperature for dormancy
    real(r8):: dormant_mr_factor ! Multiplication factor that replaces Q10
    real(r8):: q10   ! temperature dependence
    real(r8):: tc    ! temperature correction, 2m air temp (unitless)
    real(r8):: tcsoi(bounds%begc:bounds%endc,nlevgrnd) ! temperature correction by soil layer (unitless)
    real(r8):: mm, mmp ! used to allocate between fungi and active uptake
    !-----------------------------------------------------------------------

    associate(                                                        &
         ivt            =>    veg_pp%itype                             , & ! Input:  [integer  (:)   ]  patch vegetation type
         woody          =>    veg_vp%woody                      , & ! Input:  [real(r8) (:)   ]  binary flag for woody lifeform (1=woody, 0=not woody)
         br_xr          =>    veg_vp%br_xr                      , & ! Input:  [real(r8) (:)   ]  base rate for excess respiration
#if (defined HUM_HOL)
         br_mr_pft       =>    veg_vp%br_mr_pft                   , & ! Input: [real(r8) (:)   ]  base rate for maintenance respiration (pft-specific)
         q10_mr_pft      =>    veg_vp%q10_mr_pft                  , & ! Input: [real(r8) (:)   ] temperature sensitivity for maint respiration (pft-specific)
#endif
         frac_veg_nosno =>    canopystate_vars%frac_veg_nosno_patch , & ! Input:  [integer  (:)   ]  fraction of vegetation not covered by snow (0 OR 1) [-]
         laisun         =>    canopystate_vars%laisun_patch         , & ! Input:  [real(r8) (:)   ]  sunlit projected leaf area index
         laisha         =>    canopystate_vars%laisha_patch         , & ! Input:  [real(r8) (:)   ]  shaded projected leaf area index

         rootfr         =>    soilstate_vars%rootfr_patch           , & ! Input:  [real(r8) (:,:) ]  fraction of roots in each soil layer  (nlevgrnd)

         t_soisno       =>    col_es%t_soisno         , & ! Input:  [real(r8) (:,:) ]  soil temperature (Kelvin)  (-nlevsno+1:nlevgrnd)
         t_ref2m        =>    veg_es%t_ref2m          , & ! Input:  [real(r8) (:)   ]  2 m height surface air temperature (Kelvin)

         lmrsun         =>    photosyns_vars%lmrsun_patch           , & ! Input:  [real(r8) (:)   ]  sunlit leaf maintenance respiration rate (umol CO2/m**2/s)
         lmrsha         =>    photosyns_vars%lmrsha_patch           , & ! Input:  [real(r8) (:)   ]  shaded leaf maintenance respiration rate (umol CO2/m**2/s)

         cpool          =>    veg_cs%cpool          , & ! Input: [real(r8) (:)   ]   plant carbon pool (gC m-2)

#ifdef HUM_HOL
         dormant_flag_root  => cnstate_vars%dormant_flag_root_patch  , & ! Output: [real(r8)  (:)   ]  dormancy flag
#endif

         leaf_mr        =>    veg_cf%leaf_mr         , & ! Output: [real(r8) (:)   ]
         froot_mr       =>    veg_cf%froot_mr        , & ! Output: [real(r8) (:)   ]
         livestem_mr    =>    veg_cf%livestem_mr     , & ! Output: [real(r8) (:)   ]
         livecroot_mr   =>    veg_cf%livecroot_mr    , & ! Output: [real(r8) (:)   ]
         grain_mr       =>    veg_cf%grain_mr        , & ! Output: [real(r8) (:)   ]
         xr             =>    veg_cf%xr              , & ! Output: [real(r8) (:)   ]  (gC/m2) respiration of excess C
         totvegc        =>    veg_cs%totvegc         , &
         leafc          =>    veg_cs%leafc           , &

         frootn         =>    veg_ns%frootn       , & ! Input:  [real(r8) (:)   ]  (gN/m2) fine root N
         livestemn      =>    veg_ns%livestemn    , & ! Input:  [real(r8) (:)   ]  (gN/m2) live stem N
         livecrootn     =>    veg_ns%livecrootn   , & ! Input:  [real(r8) (:)   ]  (gN/m2) live coarse root N
         grainn         =>    veg_ns%grainn       , & ! Output: [real(r8) (:)   ]  (kgN/m2) grain N

#ifdef HUM_HOL
         sminn          => col_ns%sminn           , & ! Input: [real(r8) (:) ]  (gN/m2) soil mineral N
         sminp          => col_ps%sminp             & ! Input: [real(r8) (:) ]  (gN/m2) soil mineral P
#endif
         )

      ! base rate for maintenance respiration is from:
      ! M. Ryan, 1991. Effects of climate change on plant respiration.
      ! Ecological Applications, 1(2), 157-167.
      ! Original expression is br = 0.0106 molC/(molN h)
      ! Conversion by molecular weights of C and N gives 2.525e-6 gC/(gN s)
      ! set constants
      br_mr = br_mr_Inst

      ! Ben Sulman: Adding dormant maintenance resp
      dormant_mr_temp = dormant_mr_temp_Inst
      dormant_mr_factor = dormant_mr_factor_Inst

      ! Peter Thornton: 3/13/09 
      ! Q10 was originally set to 2.0, an arbitrary choice, but reduced to 1.5 as part of the tuning
      ! to improve seasonal cycle of atmospheric CO2 concentration in global
      ! simulatoins

      ! Set Q10 from SharedParamsMod
      Q10 = ParamsShareInst%Q10_mr

      ! column loop to calculate temperature factors in each soil layer
      do j=1,nlevgrnd
         do fc = 1, num_soilc
            c = filter_soilc(fc)

            ! calculate temperature corrections for each soil layer, for use in
            ! estimating fine root maintenance respiration with depth
            ! Ben Sulman: Adding lower dormant maintenance resp below a certain
            ! temperature
            if (t_soisno(c,j) > dormant_mr_temp) then
                tcsoi(c,j) = Q10**((t_soisno(c,j)-SHR_CONST_TKFRZ - 20.0_r8)/10.0_r8)
            else
                tcsoi(c,j) = dormant_mr_factor
            end if
         end do
      end do

      ! patch loop for leaves and live wood
      do fp = 1, num_soilp
         p = filter_soilp(fp)

         ! calculate maintenance respiration fluxes in
         ! gC/m2/s for each of the live plant tissues.
         ! Leaf and live wood MR

         ! Ben Sulman: Add dormant MR level below a certain temperature
         if(t_ref2m(p) > dormant_mr_temp) then
#if (defined HUM_HOL)
             tc = q10_mr_pft(ivt(p))**((t_ref2m(p)-SHR_CONST_TKFRZ - 20.0_r8)/10.0_r8)
             br_mr = br_mr_pft(ivt(p))
#else
             tc = Q10**((t_ref2m(p)-SHR_CONST_TKFRZ - 20.0_r8)/10.0_r8)
#endif
         else
             tc = dormant_mr_factor
         end if

         if (frac_veg_nosno(p) == 1) then
            leaf_mr(p) = lmrsun(p) * laisun(p) * 12.011e-6_r8 + &
                         lmrsha(p) * laisha(p) * 12.011e-6_r8

         else !nosno
            leaf_mr(p) = 0._r8

         end if

         if (woody(ivt(p)) >= 1) then
            livestem_mr(p) = livestemn(p)*br_mr*tc
            livecroot_mr(p) = livecrootn(p)*br_mr*tc
         else if (ivt(p) >= npcropmin .and. livestemn(p) .gt. 0._r8) then
            livestem_mr(p) = livestemn(p)*br_mr*tc
            grain_mr(p) = grainn(p)*br_mr*tc
         else ! Graminoid rhizomes
            livecroot_mr(p) = livecrootn(p)*br_mr*tc
         end if
         if (br_xr(ivt(p)) .gt. 1e-9_r8 .and. totvegc(p) .gt. 1e-10_r8) then
            !xr(p) = cpool(p) * br_xr(ivt(p)) * tc
            ! this is to limit the size of cpool
            xr(p) = cpool(p) * br_xr(ivt(p)) * exp((min(cpool(p) / totvegc(p),0.3335_r8) - 0.2_r8)/0.02_r8) * tc 
         else
            xr(p) = 0._r8
         end if
      end do

      ! soil and patch loop for fine root

      do j = 1,nlevdecomp
         do fp = 1,num_soilp
            p = filter_soilp(fp)
            c = veg_pp%column(p)

            ! Fine root MR
            ! rootfr(j) sums to 1.0 over all soil layers, and
            ! describes the fraction of root mass that is in each
            ! layer.  This is used with the layer temperature correction
            ! to estimate the total fine root maintenance respiration as a
            ! function of temperature and N content.
#if (defined HUM_HOL)
            ! recalculate pft-specific rates
            if (t_soisno(c,j) > dormant_mr_temp) then
               tcsoi(c,j) = q10_mr_pft(ivt(p))**((t_soisno(c,j) - SHR_CONST_TKFRZ - 20.0_r8)/10.0_r8)

               ! But 1% MR during dormancy
               if ((dormant_flag_root(p) == 1._r8) .and. (ivt(p) /= nc3_arctic_grass)) then
                  tcsoi(c,j) = 0.01_r8
               end if
            else
                tcsoi(c,j) = dormant_mr_factor
            end if
            br_mr = br_mr_pft(ivt(p))

            ! increase by a factor due to transfer to fungi: 
            ! the ratio is determined by relative uptake from fungi and mineral nutrients, 
            ! see AllocationMod.F90
            mm = AllocParamsInst%cpool_pft_sminn(ivt(p)) / AllocParamsInst%compet_pft_sminn(ivt(p))
            mmp = AllocParamsInst%cpool_pft_sminp(ivt(p)) / AllocParamsInst%compet_pft_sminp(ivt(p))
            if (ivt(p) == nbrdlf_dcd_brl_shrub) then
               ! fungi uptake declines
               mm = mm * (1._r8 - sminn(c) / (AllocParamsInst%kmin_nuptake(ivt(p)) + sminn(c)))
               mmp = mmp * (1._r8 - sminp(c) / (AllocParamsInst%kmin_puptake(ivt(p)) + sminp(c)))
            end if
            br_mr = br_mr * (0.9_r8 + 0.5 * (mm + mmp) / 2._r8)
#endif
            froot_mr(p) = froot_mr(p) + frootn(p)*br_mr*tcsoi(c,j)*rootfr(p,j)
         end do
      end do

    end associate

  end subroutine MaintenanceResp

end module MaintenanceRespMod