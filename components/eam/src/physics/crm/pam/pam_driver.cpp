#include "pam_coupler.h"
#include "Dycore.h"
#include "Microphysics.h"
#include "SGS.h"
#include "radiation.h"
#include "pam_interface.h"
#include "perturb_temperature.h"
#include "gcm_forcing.h"
#include "pam_feedback.h"
#include "pam_state.h"
#include "pam_radiation.h"
#include "pam_statistics.h"
#include "pam_output.h"
#include "sponge_layer.h"
#include "surface_friction.h"
#include "scream_cxx_interface_finalize.h"

#ifdef MMF_PAM_DEBUG_CHK
#include "pam_debug.h"
#else
void chk_state( pam::PamCoupler &coupler, std::string id ) { /* Dummy routine for GPU cases */ }
#endif

real constexpr enable_state_checks = false;

extern "C" void pam_driver() {
  //------------------------------------------------------------------------------------------------
  using yakl::intrinsics::abs;
  using yakl::intrinsics::maxval;
  auto &coupler = pam_interface::get_coupler();
  //------------------------------------------------------------------------------------------------
  // retreive coupler options
  auto nens          = coupler.get_option<int>("ncrms");
  auto gcm_nlev      = coupler.get_option<int>("gcm_nlev");
  auto crm_nz        = coupler.get_option<int>("crm_nz");
  auto crm_nx        = coupler.get_option<int>("crm_nx");
  auto crm_ny        = coupler.get_option<int>("crm_ny");
  auto gcm_dt        = coupler.get_option<real>("gcm_dt");
  auto crm_dt        = coupler.get_option<real>("crm_dt");
  auto is_first_step = coupler.get_option<bool>("is_first_step");
  //------------------------------------------------------------------------------------------------
  // set various coupler options
  coupler.set_option<real>("gcm_physics_dt",gcm_dt);
  coupler.set_option<std::string>("p3_lookup_data_path","./p3_data");
  coupler.set_option<int>("sponge_num_layers",crm_nz*0.25);
  coupler.set_option<real>("sponge_time_scale",60*6);
  //------------------------------------------------------------------------------------------------
  // Allocate the coupler state and retrieve host/device data managers
  coupler.allocate_coupler_state( crm_nz , crm_ny , crm_nx , nens );
  // set up the grid - this needs to happen before initializing coupler objects
  pam_state_set_grid(coupler);
  //------------------------------------------------------------------------------------------------
  // get seperate data manager objects for host and device
  auto &dm_device = coupler.get_data_manager_device_readwrite();
  auto &dm_host   = coupler.get_data_manager_host_readwrite();
  //------------------------------------------------------------------------------------------------
  // Create objects for dycor, microphysics, and turbulence and initialize them
  Microphysics micro;
  SGS          sgs;
  Dycore       dycore;
  Radiation    rad;
  micro .init(coupler);
  sgs   .init(coupler);
  dycore.init(coupler);
  rad   .init(coupler);
  //------------------------------------------------------------------------------------------------
  // update coupler GCM state with input GCM state
  pam_state_update_gcm_state(coupler);

  // Copy input CRM state (saved by the GCM) to coupler
  pam_state_copy_input_to_coupler(coupler);

  if (enable_state_checks) { chk_state(coupler, "0"); }

  // now that initial state is set, more dycor initialization
  coupler.update_hydrostasis();

  // Compute CRM forcing tendencies
  modules::compute_gcm_forcing_tendencies(coupler);

  // Copy input rad tendencies to coupler
  pam_radiation_copy_input_to_coupler(coupler);

  // initialize rad output variables
  pam_radiation_init(coupler);

  // initialize stat variables
  pam_statistics_init(coupler);

  // initilize surface "psuedo-friction" (psuedo => doesn't match "real" GCM friction)
  auto input_tau  = dm_host.get<real const,1>("input_tau00").createDeviceCopy();
  auto input_bflx = dm_host.get<real const,1>("input_bflxls").createDeviceCopy();
  modules::surface_friction_init(coupler, input_tau, input_bflx);

  // Perturb the CRM at the beginning of the run
  if (is_first_step) {
    auto gcolp = dm_host.get<int const,1>("gcolp").createDeviceCopy();
    modules::perturb_temperature( coupler , gcolp );
  }

  #if defined(MMF_PAM_DYCOR_SPAM)
    pam_state_update_reference_state(coupler, dycore);
    dycore.pre_time_loop(coupler);
  #endif

  //------------------------------------------------------------------------------------------------
  //------------------------------------------------------------------------------------------------
  //------------------------------------------------------------------------------------------------

  // Run the CRM
  real etime_crm = 0;
  while (etime_crm < gcm_dt) {
    if (crm_dt == 0.) { crm_dt = dycore.compute_time_step(coupler); }
    if (etime_crm + crm_dt > gcm_dt) { crm_dt = gcm_dt - etime_crm; }

    // std::cout<<"  WHDEBUG - etime_crm:"<<etime_crm<<std::endl;

    if (enable_state_checks) { chk_state(coupler, "1"); }

    // run a PAM time step
    coupler.run_module( "apply_gcm_forcing_tendencies" , modules::apply_gcm_forcing_tendencies );
    coupler.run_module( "radiation"                    , [&] (pam::PamCoupler &coupler) {rad   .timeStep(coupler);} );

    if (enable_state_checks) { chk_state(coupler, "2"); }

    #if defined(MMF_PAM_DYCOR_SPAM)
    // The anelastic option in PAM-C assumes that the total density never changes.
    // However, his is not valid for MMF, so update the anelastic reference state each time step.
    pam_state_update_reference_state(coupler, dycore);
    #endif

    pam_statistics_save_state(coupler);
    coupler.run_module( "dycore"                       , [&] (pam::PamCoupler &coupler) {dycore.timeStep(coupler);} );
    pam_statistics_aggregate_tendency(coupler,"dycor");

    if (enable_state_checks) { chk_state(coupler, "3"); }

    pam_statistics_save_state(coupler);
    coupler.run_module( "sponge_layer"                 , modules::sponge_layer );
    pam_statistics_aggregate_tendency(coupler,"sponge");

    if (enable_state_checks) { chk_state(coupler, "4"); }

    coupler.run_module( "compute_surface_friction"     , modules::compute_surface_friction );

    pam_statistics_save_state(coupler);
    coupler.run_module( "sgs"                          , [&] (pam::PamCoupler &coupler) {sgs   .timeStep(coupler);} );
    pam_statistics_aggregate_tendency(coupler,"sgs");

    if (enable_state_checks) { chk_state(coupler, "5"); }

    pam_statistics_save_state(coupler);
    coupler.run_module( "micro"                        , [&] (pam::PamCoupler &coupler) {micro .timeStep(coupler);} );
    pam_statistics_aggregate_tendency(coupler,"micro");

    if (enable_state_checks) { chk_state(coupler, "6"); }

    pam_radiation_timestep_aggregation(coupler);
    pam_statistics_timestep_aggregation(coupler);

    etime_crm += crm_dt;
  }
  //------------------------------------------------------------------------------------------------
  //------------------------------------------------------------------------------------------------
  //------------------------------------------------------------------------------------------------

  // Compute CRM feedback tendencies and copy to host
  pam_feedback_compute_tendencies(coupler,gcm_dt);
  pam_feedback_copy_to_host(coupler);
  
  // Copy the final CRM state to the host to be saved for next time step
  pam_state_copy_to_host(coupler);

  // Compute horizontal means of CRM state variables and copy to host
  pam_output_compute_means(coupler);
  pam_output_copy_to_host(coupler);

  // convert aggregated radiation quantities to means and copy to host
  pam_radiation_compute_means(coupler);
  pam_radiation_copy_to_host(coupler);

  // convert aggregated diagnostic quantities to means and copy to host
  pam_statistics_compute_means(coupler);
  pam_statistics_copy_to_host(coupler);

  //------------------------------------------------------------------------------------------------
  // Finalize and clean up
  micro .finalize(coupler);
  sgs   .finalize(coupler);
  dycore.finalize(coupler);
  rad   .finalize(coupler);
  pam_interface::finalize();
  //------------------------------------------------------------------------------------------------
}


extern "C" void pam_finalize() {
  #if defined(P3_CXX) || defined(SHOC_CXX)
  pam::deallocate_scream_cxx_globals();
  pam::call_kokkos_finalize();
  #endif
}
