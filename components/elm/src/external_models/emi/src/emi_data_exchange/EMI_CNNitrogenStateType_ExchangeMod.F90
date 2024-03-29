module EMI_CNNitrogenStateType_ExchangeMod
  !
  use shr_kind_mod                          , only : r8 => shr_kind_r8
  use shr_log_mod                           , only : errMsg => shr_log_errMsg
  use abortutils                            , only : endrun
  use elm_varctl                            , only : iulog
  use EMI_DataMod                           , only : emi_data_list, emi_data
  use EMI_DataDimensionMod                  , only : emi_data_dimension_list_type
  use ColumnDataType       , only : column_nitrogen_state
  use EMI_Atm2LndType_Constants
  use EMI_CanopyStateType_Constants
  use EMI_ChemStateType_Constants
  use EMI_CNCarbonStateType_Constants
  use EMI_CNNitrogenStateType_Constants
  use EMI_CNNitrogenFluxType_Constants
  use EMI_CNCarbonFluxType_Constants
  use EMI_ColumnEnergyStateType_Constants
  use EMI_ColumnWaterStateType_Constants
  use EMI_ColumnWaterFluxType_Constants
  use EMI_EnergyFluxType_Constants
  use EMI_SoilHydrologyType_Constants
  use EMI_SoilStateType_Constants
  use EMI_TemperatureType_Constants
  use EMI_WaterFluxType_Constants
  use EMI_WaterStateType_Constants
  use EMI_Filter_Constants
  use EMI_ColumnType_Constants
  use EMI_Landunit_Constants
  !
  implicit none
  !
  !
  public :: EMI_Pack_CNNitrogenStateType_at_Column_Level_for_EM
  public :: EMI_Unpack_CNNitrogenStateType_at_Column_Level_from_EM

contains
  
!-----------------------------------------------------------------------
  subroutine EMI_Pack_CNNitrogenStateType_at_Column_Level_for_EM(data_list, em_stage, &
        num_filter, filter, col_ns)
    !
    ! !DESCRIPTION:
    ! Pack data from ALM col_ns for EM
    !
    ! !USES:
    use elm_varpar             , only : nlevdecomp_full
    use elm_varpar             , only : ndecomp_pools
    !
    implicit none
    !
    ! !ARGUMENTS:
    class(emi_data_list)        , intent(in) :: data_list
    integer                     , intent(in) :: em_stage
    integer                     , intent(in) :: num_filter
    integer                     , intent(in) :: filter(:)
    type(column_nitrogen_state) , intent(in) :: col_ns
    !
    ! !LOCAL_VARIABLES:
    integer                             :: fc,c,j,k
    class(emi_data), pointer            :: cur_data
    logical                             :: need_to_pack
    integer                             :: istage
    integer                             :: count

    associate(& 
         decomp_npools_vr => col_ns%decomp_npools_vr , &
         smin_nh4_vr      => col_ns%smin_nh4_vr      , &
         smin_no3_vr      => col_ns%smin_no3_vr        &
         )

    count = 0
    cur_data => data_list%first
    do
       if (.not.associated(cur_data)) exit
       count = count + 1

       need_to_pack = .false.
       do istage = 1, cur_data%num_em_stages
          if (cur_data%em_stage_ids(istage) == em_stage) then
             need_to_pack = .true.
             exit
          endif
       enddo

       if (need_to_pack) then

          select case (cur_data%id)

          case (L2E_STATE_NITROGEN_POOLS_VERTICALLY_RESOLVED)
             do fc = 1, num_filter
                c = filter(fc)
                do j = 1, nlevdecomp_full
                   do k = 1, ndecomp_pools
                      cur_data%data_real_3d(c,j,k) = decomp_npools_vr(c,j,k)
                   enddo
                enddo
             enddo
             cur_data%is_set = .true.

          case (L2E_STATE_NH4_VERTICALLY_RESOLVED)
             do fc = 1, num_filter
                c = filter(fc)
                do j = 1, nlevdecomp_full
                   cur_data%data_real_2d(c,j) = smin_nh4_vr(c,j)
                enddo
             enddo
             cur_data%is_set = .true.

          case (L2E_STATE_NO3_VERTICALLY_RESOLVED)
             do fc = 1, num_filter
                c = filter(fc)
                do j = 1, nlevdecomp_full
                   cur_data%data_real_2d(c,j) = smin_no3_vr(c,j)
                enddo
             enddo
             cur_data%is_set = .true.

          end select

       endif

       cur_data => cur_data%next
    enddo

    end associate

  end subroutine EMI_Pack_CNNitrogenStateType_at_Column_Level_for_EM

!-----------------------------------------------------------------------
  subroutine EMI_Unpack_CNNitrogenStateType_at_Column_Level_from_EM(data_list, em_stage, &
        num_filter, filter, col_ns)
    !
    ! !DESCRIPTION:
    ! Unpack data for ALM col_ns from EM
    !
    ! !USES:
    use elm_varpar             , only : nlevdecomp_full
    use elm_varpar             , only : ndecomp_pools
    !
    implicit none
    !
    ! !ARGUMENTS:
    class(emi_data_list)        , intent(in) :: data_list
    integer                     , intent(in) :: em_stage
    integer                     , intent(in) :: num_filter
    integer                     , intent(in) :: filter(:)
    type(column_nitrogen_state) , intent(in) :: col_ns
    !
    ! !LOCAL_VARIABLES:
    integer                             :: fc,c,j,k
    class(emi_data), pointer            :: cur_data
    logical                             :: need_to_pack
    integer                             :: istage
    integer                             :: count

    associate(& 
         decomp_npools_vr => col_ns%decomp_npools_vr , &
         smin_nh4_vr      => col_ns%smin_nh4_vr      , &
         smin_no3_vr      => col_ns%smin_no3_vr      , &
         DON_vr           => col_ns%DON_vr             &
         )

    count = 0
    cur_data => data_list%first
    do
       if (.not.associated(cur_data)) exit
       count = count + 1

       need_to_pack = .false.
       do istage = 1, cur_data%num_em_stages
          if (cur_data%em_stage_ids(istage) == em_stage) then
             need_to_pack = .true.
             exit
          endif
       enddo

       if (need_to_pack) then

          select case (cur_data%id)

          case (E2L_STATE_NITROGEN_POOLS_VERTICALLY_RESOLVED)
             do fc = 1, num_filter
                c = filter(fc)
                do j = 1, nlevdecomp_full
                   do k = 1, ndecomp_pools
                      decomp_npools_vr(c,j,k) = cur_data%data_real_3d(c,j,k)
                   enddo
                enddo
             enddo
             cur_data%is_set = .true.

          case (E2L_STATE_NH4_VERTICALLY_RESOLVED)
             do fc = 1, num_filter
                c = filter(fc)
                do j = 1, nlevdecomp_full
                   smin_nh4_vr(c,j) = cur_data%data_real_2d(c,j)
                enddo
             enddo
             cur_data%is_set = .true.

          case (E2L_STATE_NO3_VERTICALLY_RESOLVED)
             do fc = 1, num_filter
                c = filter(fc)
                do j = 1, nlevdecomp_full
                   smin_no3_vr(c,j) = cur_data%data_real_2d(c,j)
                enddo
             enddo
             cur_data%is_set = .true.

          case (E2L_STATE_DON_VERTICALLY_RESOLVED)
             do fc = 1, num_filter
                c = filter(fc)
                do j = 1, nlevdecomp_full
                   DON_vr(c,j) = cur_data%data_real_2d(c,j)
                enddo
             enddo
             cur_data%is_set = .true.

          end select

       endif

       cur_data => cur_data%next
    enddo

    end associate

  end subroutine EMI_Unpack_CNNitrogenStateType_at_Column_Level_from_EM


end module EMI_CNNitrogenStateType_ExchangeMod
