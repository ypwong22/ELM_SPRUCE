#include <catch2/catch.hpp>

#include "dynamics/homme/physics_dynamics_remapper.hpp"
#include "dynamics/homme/interface/scream_homme_interface.hpp"
#include "share/field/field.hpp"
#include "share/grid/se_grid.hpp"
#include "share/grid/point_grid.hpp"

#include "mpi/BoundaryExchange.hpp"
#include "mpi/Comm.hpp"

#include "dynamics/homme/homme_dimensions.hpp"

#include "ekat/ekat_pack.hpp"
#include "ekat/util/ekat_test_utils.hpp"

#include <random>
#include <numeric>

extern "C" {
// These are specific C/F calls for these tests (i.e., not part of scream_homme_interface.hpp)
void init_cube_geometry_f90 (const int& ne_in);
void cleanup_geometry_f90 ();
}

namespace {

TEST_CASE("remap", "") {

  using namespace scream;
  using namespace ShortFieldTagsNames;

  // Some type defs
  using PackType = ekat::Pack<Homme::Real,HOMMEXX_VECTOR_SIZE>;
  using Remapper = PhysicsDynamicsRemapper<Homme::Real>;
  using IPDF = std::uniform_int_distribution<int>;
  using FID = FieldIdentifier;
  using FL  = FieldLayout;

  std::random_device rd;
  const unsigned int catchRngSeed = Catch::rngSeed();
  const unsigned int seed = catchRngSeed==0 ? rd() : catchRngSeed;
  std::cout << "seed: " << seed << (catchRngSeed==0 ? " (catch rng seed was 0)\n" : "\n");
  std::mt19937_64 engine(seed);

  // We'll use this extensively, so let's use a short ref name
  auto& c = Homme::Context::singleton();

  // Set a value for qsize that is not the full qsize_d
  auto& sp = c.create<Homme::SimulationParams>();
  sp.qsize = std::max(HOMMEXX_QSIZE_D/2,1);

  // Create a comm
  auto& comm = c.create<Homme::Comm>();
  comm.reset_mpi_comm(MPI_COMM_WORLD);

  // Init a simple cubed geometry
  constexpr int ne = 2;
  constexpr int nlev = HOMMEXX_NUM_LEV;
  constexpr int np   = HOMMEXX_NP;

  if (!is_parallel_inited_f90()) {
    auto comm_f = MPI_Comm_c2f(MPI_COMM_WORLD);
    init_parallel_f90(comm_f);
  }
  init_cube_geometry_f90(ne);

  // Local counters
  const int num_local_elems = get_num_owned_elems_f90();
  const int num_local_cols = get_num_owned_columns_f90();
  EKAT_REQUIRE_MSG(num_local_cols>0, "Internal test error! Fix homme_pd_remap_tests, please.\n");

  // Create the columns global id mappings
  typename AbstractGrid::dofs_list_type p_dofs("p dofs",num_local_cols);
  typename AbstractGrid::dofs_list_type d_dofs("d dofs",num_local_elems*np*np);

  typename AbstractGrid::lid_to_idx_map_type p_lid2idx("p_lid2idx",num_local_cols,1);
  typename AbstractGrid::lid_to_idx_map_type d_lid2idx("d_lid2idx",num_local_elems*np*np,3);

  auto h_p_dofs = Kokkos::create_mirror_view(p_dofs);
  auto h_d_dofs = Kokkos::create_mirror_view(d_dofs);
  auto h_p_lid2idx = Kokkos::create_mirror_view(p_lid2idx);
  auto h_d_lid2idx = Kokkos::create_mirror_view(d_lid2idx);

  get_cols_gids_f90 (h_p_dofs.data(),true);
  std::iota(h_p_lid2idx.data(),h_p_lid2idx.data()+h_p_lid2idx.size(),0);
  get_cols_specs_f90 (h_d_dofs.data(),h_d_lid2idx.data(),false);

  Kokkos::deep_copy(p_dofs,h_p_dofs);
  Kokkos::deep_copy(d_dofs,h_d_dofs);
  Kokkos::deep_copy(p_lid2idx,h_p_lid2idx);
  Kokkos::deep_copy(d_lid2idx,h_d_lid2idx);

  // Create the physics and dynamics grids
  auto phys_grid = std::make_shared<PointGrid>("Physics", p_dofs, nlev);
  auto dyn_grid  = std::make_shared<SEGrid>("Dynamics",num_local_elems, np, nlev);

  dyn_grid->set_dofs(d_dofs,d_lid2idx);

  constexpr int NVL = HOMMEXX_NUM_PHYSICAL_LEV;
  constexpr int NTL = HOMMEXX_NUM_TIME_LEVELS;
  constexpr int NTQ = HOMMEXX_Q_NUM_TIME_LEVELS;
  constexpr int NQ  = HOMMEXX_QSIZE_D;
  const int nle = num_local_elems;
  const int nlc = num_local_cols;
  const auto units = ekat::units::m;  // Placeholder units (we don't care about units here)

  const int np1 = IPDF(0,NTL-1)(engine);
  const int np1_qdp = IPDF(0,NTQ-1)(engine);

  c.create_if_not_there<Homme::TimeLevel>();
  auto& tl = c.get<Homme::TimeLevel>();
  tl.np1 = np1;
  tl.nm1 = (np1+1) % NTL;
  tl.n0  = (np1+2) % NTL;
  tl.np1_qdp = np1_qdp;
  tl.n0_qdp  = (np1_qdp+1) % NTQ;

  // Note on prefixes: s=scalar, v=vector, ss=scalar state, vs=vector_state, ts=tracer state

  // Create tags and dimensions
  std::vector<FieldTag> s_2d_dyn_tags   = {EL,          GP, GP    };
  std::vector<FieldTag> v_2d_dyn_tags   = {EL,     CMP, GP, GP    };
  std::vector<FieldTag> s_3d_dyn_tags   = {EL,          GP, GP, VL};
  std::vector<FieldTag> v_3d_dyn_tags   = {EL,     CMP, GP, GP, VL};
  std::vector<FieldTag> ss_3d_dyn_tags  = {EL, TL,      GP, GP, VL};
  std::vector<FieldTag> vs_3d_dyn_tags  = {EL, TL, CMP, GP, GP, VL};

  std::vector<FieldTag> s_2d_phys_tags  = {COL         };
  std::vector<FieldTag> v_2d_phys_tags  = {COL, CMP    };
  std::vector<FieldTag> s_3d_phys_tags  = {COL,      VL};
  std::vector<FieldTag> v_3d_phys_tags  = {COL, CMP, VL};
  std::vector<FieldTag> vs_3d_phys_tags = {COL, CMP, VL};
  std::vector<FieldTag> ss_3d_phys_tags = {COL,      VL};

  std::vector<int> s_2d_dyn_dims   = {nle,          np, np     };
  std::vector<int> v_2d_dyn_dims   = {nle,       2, np, np     };
  std::vector<int> s_3d_dyn_dims   = {nle,          np, np, NVL};
  std::vector<int> v_3d_dyn_dims   = {nle,       2, np, np, NVL};
  std::vector<int> ss_3d_dyn_dims  = {nle, NTL,     np, np, NVL};
  std::vector<int> vs_3d_dyn_dims  = {nle, NTL,  2, np, np, NVL};
  std::vector<int> ts_3d_dyn_dims  = {nle, NTQ, NQ, np, np, NVL};

  std::vector<int> s_2d_phys_dims  = {nlc         };
  std::vector<int> v_2d_phys_dims  = {nlc,  2     };
  std::vector<int> s_3d_phys_dims  = {nlc,     NVL};
  std::vector<int> v_3d_phys_dims  = {nlc,  2, NVL};
  std::vector<int> ss_3d_phys_dims = {nlc,     NVL};
  std::vector<int> vs_3d_phys_dims = {nlc,  2, NVL};
  std::vector<int> ts_3d_phys_dims = {nlc, NQ, NVL};

  // Create identifiers
  const auto dgn = dyn_grid->name();
  const auto pgn = phys_grid->name();
  FID s_2d_dyn_fid  ("s_2d_dyn", FL(s_2d_dyn_tags,  s_2d_dyn_dims), units, dgn);
  FID v_2d_dyn_fid  ("v_2d_dyn", FL(v_2d_dyn_tags,  v_2d_dyn_dims), units, dgn);
  FID s_3d_dyn_fid  ("s_3d_dyn", FL(s_3d_dyn_tags,  s_3d_dyn_dims), units, dgn);
  FID v_3d_dyn_fid  ("v_3d_dyn", FL(v_3d_dyn_tags,  v_3d_dyn_dims), units, dgn);
  FID ss_3d_dyn_fid ("ss_3d_dyn", FL(ss_3d_dyn_tags, ss_3d_dyn_dims),units, dgn);
  FID vs_3d_dyn_fid ("vs_3d_dyn", FL(vs_3d_dyn_tags, vs_3d_dyn_dims),units, dgn);
  FID ts_3d_dyn_fid ("ts_3d_dyn", FL(vs_3d_dyn_tags, ts_3d_dyn_dims),units, dgn);

  FID s_2d_phys_fid ("s_2d_phys",  FL(s_2d_phys_tags, s_2d_phys_dims),units, pgn);
  FID v_2d_phys_fid ("v_2d_phys",  FL(v_2d_phys_tags, v_2d_phys_dims),units, pgn);
  FID s_3d_phys_fid ("s_3d_phys",  FL(s_3d_phys_tags, s_3d_phys_dims),units, pgn);
  FID v_3d_phys_fid ("v_3d_phys",  FL(v_3d_phys_tags, v_3d_phys_dims),units, pgn);
  FID ss_3d_phys_fid ("ss_3d_phys", FL(ss_3d_phys_tags, ss_3d_phys_dims),units, pgn);
  FID vs_3d_phys_fid ("vs_3d_phys", FL(vs_3d_phys_tags, vs_3d_phys_dims),units, pgn);
  FID ts_3d_phys_fid ("ts_3d_phys", FL(vs_3d_phys_tags, ts_3d_phys_dims),units, pgn);

  // Create fields
  Field<Real> s_2d_field_phys (s_2d_phys_fid);
  Field<Real> v_2d_field_phys (v_2d_phys_fid);
  Field<Real> s_3d_field_phys (s_3d_phys_fid);
  Field<Real> v_3d_field_phys (v_3d_phys_fid);
  Field<Real> ss_3d_field_phys (ss_3d_phys_fid);
  Field<Real> vs_3d_field_phys (vs_3d_phys_fid);
  Field<Real> ts_3d_field_phys (ts_3d_phys_fid);

  Field<Real> s_2d_field_dyn(s_2d_dyn_fid);
  Field<Real> v_2d_field_dyn(v_2d_dyn_fid);
  Field<Real> s_3d_field_dyn(s_3d_dyn_fid);
  Field<Real> v_3d_field_dyn(v_3d_dyn_fid);
  Field<Real> ss_3d_field_dyn (ss_3d_dyn_fid);
  Field<Real> vs_3d_field_dyn (vs_3d_dyn_fid);
  Field<Real> ts_3d_field_dyn (ts_3d_dyn_fid);

  // Request allocation to fit packs of reals for 3d views
  s_3d_field_phys.get_header().get_alloc_properties().request_value_type_allocation<PackType>();
  v_3d_field_phys.get_header().get_alloc_properties().request_value_type_allocation<PackType>();
  ss_3d_field_phys.get_header().get_alloc_properties().request_value_type_allocation<PackType>();
  vs_3d_field_phys.get_header().get_alloc_properties().request_value_type_allocation<PackType>();
  ts_3d_field_phys.get_header().get_alloc_properties().request_value_type_allocation<PackType>();

  s_3d_field_dyn.get_header().get_alloc_properties().request_value_type_allocation<PackType>();
  v_3d_field_dyn.get_header().get_alloc_properties().request_value_type_allocation<PackType>();
  ss_3d_field_dyn.get_header().get_alloc_properties().request_value_type_allocation<PackType>();
  vs_3d_field_dyn.get_header().get_alloc_properties().request_value_type_allocation<PackType>();
  ts_3d_field_dyn.get_header().get_alloc_properties().request_value_type_allocation<PackType>();
  ts_3d_field_dyn.get_header().set_extra_data("Is Tracer State", true);

  // Allocate view
  s_2d_field_phys.allocate_view();
  v_2d_field_phys.allocate_view();
  s_3d_field_phys.allocate_view();
  v_3d_field_phys.allocate_view();
  ss_3d_field_phys.allocate_view();
  vs_3d_field_phys.allocate_view();
  ts_3d_field_phys.allocate_view();

  s_2d_field_dyn.allocate_view();
  v_2d_field_dyn.allocate_view();
  s_3d_field_dyn.allocate_view();
  v_3d_field_dyn.allocate_view();
  ss_3d_field_dyn.allocate_view();
  vs_3d_field_dyn.allocate_view();
  ts_3d_field_dyn.allocate_view();

  // Set extra data on tracers fields, so the remapper knows to grab the tracers timelevel
  // from Homme's TimeLevel data structure (instead of the state timelevel)
  ekat::any tracer;
  tracer.reset<bool>(true);
  ts_3d_field_dyn.get_header_ptr()->set_extra_data("Is Tracer State",tracer,false);

  // Build the remapper, and register the fields
  std::shared_ptr<Remapper> remapper(new Remapper(phys_grid,dyn_grid));
  remapper->registration_begins();
  remapper->register_field(s_2d_field_phys, s_2d_field_dyn);
  remapper->register_field(v_2d_field_phys, v_2d_field_dyn);
  remapper->register_field(s_3d_field_phys, s_3d_field_dyn);
  remapper->register_field(v_3d_field_phys, v_3d_field_dyn);
  remapper->register_field(ss_3d_field_phys, ss_3d_field_dyn);
  remapper->register_field(vs_3d_field_phys, vs_3d_field_dyn);
  remapper->register_field(ts_3d_field_phys, ts_3d_field_dyn);
  remapper->registration_ends();

  SECTION ("remap") {

    for (bool fwd : {true, false}) {
      std::cout << " -> Remap " << (fwd ? " forward\n" : " backward\n");

      // Note: for the dyn->phys test to run correctly, the dynamics input v must be synced,
      //       meaning that the values at the interface between two elements must match.
      //       To do this, we initialize each entry in the dynamic v with the id
      //       of the corresponding column.
      //       But since this approach makes checking answers much easier, we use it also for phys->dyn.

      if (fwd) {
        auto s_2d_view = s_2d_field_phys.get_reshaped_view<Homme::Real*>();
        auto v_2d_view = v_2d_field_phys.get_reshaped_view<Homme::Real**>();
        auto s_3d_view = s_3d_field_phys.get_reshaped_view<Homme::Real**>();
        auto v_3d_view = v_3d_field_phys.get_reshaped_view<Homme::Real***>();
        auto ss_3d_view = ss_3d_field_phys.get_reshaped_view<Homme::Real**>();
        auto vs_3d_view = vs_3d_field_phys.get_reshaped_view<Homme::Real***>();
        auto ts_3d_view = ts_3d_field_phys.get_reshaped_view<Homme::Real***>();

        auto h_s_2d_view = Kokkos::create_mirror_view(s_2d_view);
        auto h_v_2d_view = Kokkos::create_mirror_view(v_2d_view);
        auto h_s_3d_view = Kokkos::create_mirror_view(s_3d_view);
        auto h_v_3d_view = Kokkos::create_mirror_view(v_3d_view);
        auto h_ss_3d_view = Kokkos::create_mirror_view(ss_3d_view);
        auto h_vs_3d_view = Kokkos::create_mirror_view(vs_3d_view);
        auto h_ts_3d_view = Kokkos::create_mirror_view(ts_3d_view);
        for (int idof=0; idof<num_local_cols; ++idof) {
          auto gid = h_p_dofs(idof);
          h_s_2d_view(idof) = gid;
          h_v_2d_view(idof,0) = gid;
          h_v_2d_view(idof,1) = gid;
          for (int il=0; il<NVL; ++ il) {
            h_s_3d_view(idof,il) = gid;
            h_v_3d_view(idof,0,il) = gid;
            h_v_3d_view(idof,1,il) = gid;

            h_ss_3d_view(idof,il) = gid;
            h_vs_3d_view(idof,0,il) = gid;
            h_vs_3d_view(idof,1,il) = gid;
            for (int iq=0; iq<NTQ; ++iq) {
              h_ts_3d_view(idof,iq,il) = gid;
            }
          }
        }
        Kokkos::deep_copy(s_2d_view,h_s_2d_view);
        Kokkos::deep_copy(v_2d_view,h_v_2d_view);
        Kokkos::deep_copy(s_3d_view,h_s_3d_view);
        Kokkos::deep_copy(v_3d_view,h_v_3d_view);

        Kokkos::deep_copy(ss_3d_view,h_ss_3d_view);
        Kokkos::deep_copy(vs_3d_view,h_vs_3d_view);
        Kokkos::deep_copy(ts_3d_view,h_ts_3d_view);
      } else {
        auto s_2d_view = s_2d_field_dyn.get_reshaped_view<Homme::Real***>();
        auto v_2d_view = v_2d_field_dyn.get_reshaped_view<Homme::Real****>();
        auto s_3d_view = s_3d_field_dyn.get_reshaped_view<Homme::Real****>();
        auto v_3d_view = v_3d_field_dyn.get_reshaped_view<Homme::Real*****>();
        auto ss_3d_view = ss_3d_field_dyn.get_reshaped_view<Homme::Real*****>();
        auto vs_3d_view = vs_3d_field_dyn.get_reshaped_view<Homme::Real******>();
        auto ts_3d_view = ts_3d_field_dyn.get_reshaped_view<Homme::Real******>();

        auto h_s_2d_view = Kokkos::create_mirror_view(s_2d_view);
        auto h_v_2d_view = Kokkos::create_mirror_view(v_2d_view);
        auto h_s_3d_view = Kokkos::create_mirror_view(s_3d_view);
        auto h_v_3d_view = Kokkos::create_mirror_view(v_3d_view);
        auto h_ss_3d_view = Kokkos::create_mirror_view(ss_3d_view);
        auto h_vs_3d_view = Kokkos::create_mirror_view(vs_3d_view);
        auto h_ts_3d_view = Kokkos::create_mirror_view(ts_3d_view);
        for (int ie=0; ie<num_local_elems; ++ie) {
          for (int ip=0; ip<NP; ++ip) {
            for (int jp=0; jp<NP; ++jp) {
              const int idof = ie*NP*NP + ip*NP + jp;
              auto gid = h_d_dofs(idof);
              h_s_2d_view(ie,ip,jp) = gid;
              h_v_2d_view(ie,0,ip,jp) = gid;
              h_v_2d_view(ie,1,ip,jp) = gid;
              for (int il=0; il<NVL; ++ il) {
                h_s_3d_view(ie,ip,jp,il) = gid;
                h_v_3d_view(ie,0,ip,jp,il) = gid;
                h_v_3d_view(ie,1,ip,jp,il) = gid;

                for (int itl=0; itl<NTL; ++itl) {
                  h_ss_3d_view(ie,itl,ip,jp,il) = gid;
                  h_vs_3d_view(ie,itl,0,ip,jp,il) = gid;
                  h_vs_3d_view(ie,itl,1,ip,jp,il) = gid;
                }
                for (int itl=0; itl<NTQ; ++itl) {
                  for (int iq=0; iq<NTQ; ++iq) {
                    h_ts_3d_view(ie,itl,iq,ip,jp,il) = gid;
                  }
                }
              }
            }
          }
        }
        Kokkos::deep_copy(s_2d_view,h_s_2d_view);
        Kokkos::deep_copy(v_2d_view,h_v_2d_view);
        Kokkos::deep_copy(s_3d_view,h_s_3d_view);
        Kokkos::deep_copy(v_3d_view,h_v_3d_view);

        Kokkos::deep_copy(ss_3d_view,h_ss_3d_view);
        Kokkos::deep_copy(vs_3d_view,h_vs_3d_view);
        Kokkos::deep_copy(ts_3d_view,h_ts_3d_view);
      }

      // Remap
      remapper->remap(fwd);

      // Check
      {
        // 2d scalar
        auto phys = Kokkos::create_mirror_view(s_2d_field_phys.template get_reshaped_view<Homme::Real*>());
        auto dyn = Kokkos::create_mirror_view(s_2d_field_dyn.template get_reshaped_view<Homme::Real***>());
        Kokkos::deep_copy(phys,s_2d_field_phys.template get_reshaped_view<Homme::Real*>());
        Kokkos::deep_copy(dyn,s_2d_field_dyn.template get_reshaped_view<Homme::Real***>());
        
        if (fwd) {
          for (int idof=0; idof<dyn_grid->get_num_local_dofs(); ++idof) {
            int ie = h_d_lid2idx(idof,0);    
            int ip = h_d_lid2idx(idof,1);    
            int jp = h_d_lid2idx(idof,2);    
            if (dyn(ie,ip,jp)!=h_d_dofs(idof)) {
                printf(" ** 2D Scalar ** \n");
                printf("d_out(%d,%d,%d): %2.16f\n",ie,ip,jp,dyn(ie,ip,jp));
                printf("expected: = %ld\n",h_d_dofs(idof));
            }
            REQUIRE (dyn(ie,ip,jp)==h_d_dofs(idof));
          }
        } else {
          for (int idof=0; idof<phys_grid->get_num_local_dofs(); ++idof) {
            if (phys(idof)!=h_p_dofs(idof)) {
                printf(" ** 2D Scalar ** \n");
                printf("  p_out(%d) = %2.16f\n",idof,phys(idof));
                printf("  expected: = %ld\n",h_p_dofs(idof));
            }
            REQUIRE (phys(idof)==h_p_dofs(idof));
          }
        }
      }

      {
        // 2d vector
        auto phys = Kokkos::create_mirror_view(v_2d_field_phys.template get_reshaped_view<Homme::Real**>());
        auto dyn = Kokkos::create_mirror_view(v_2d_field_dyn.template get_reshaped_view<Homme::Real****>());
        Kokkos::deep_copy(phys,v_2d_field_phys.template get_reshaped_view<Homme::Real**>());
        Kokkos::deep_copy(dyn,v_2d_field_dyn.template get_reshaped_view<Homme::Real****>());
        if (fwd) {
          for (int idof=0; idof<dyn_grid->get_num_local_dofs(); ++idof) {
            int ie = h_d_lid2idx(idof,0);    
            int ip = h_d_lid2idx(idof,1);    
            int jp = h_d_lid2idx(idof,2);    
            for (int icomp=0; icomp<2; ++icomp) {
              if (dyn(ie,icomp,ip,jp)!=h_d_dofs(idof)) {
                  printf(" ** 2D Vector ** \n");
                  printf("d_out(%d,%d,%d,%d): %2.16f\n",ie,ip,jp,icomp,dyn(ie,icomp,ip,jp));
                  printf("expected: = %ld\n",h_d_dofs(idof));
              }
              REQUIRE (dyn(ie,icomp,ip,jp)==h_d_dofs(idof));
            }
          }
        } else {
          for (int idof=0; idof<phys_grid->get_num_local_dofs(); ++idof) {
            for (int icomp=0; icomp<2; ++icomp) {
              if (phys(idof,icomp)!=h_p_dofs(idof)) {
                  printf(" ** 2D Vector ** \n");
                  printf("p_out(%d, %d) = %2.16f\n",idof,icomp,phys(idof,icomp));
                  printf("expected: = %ld\n",h_p_dofs(idof));
              }
              REQUIRE (phys(idof,icomp)==h_p_dofs(idof));
            }
          }
        }
      }

      {
        // 3d scalar
        auto phys = Kokkos::create_mirror_view(s_3d_field_phys.template get_reshaped_view<Homme::Real**>());
        auto dyn = Kokkos::create_mirror_view(s_3d_field_dyn.template get_reshaped_view<Homme::Real****>());
        Kokkos::deep_copy(phys,s_3d_field_phys.template get_reshaped_view<Homme::Real**>());
        Kokkos::deep_copy(dyn,s_3d_field_dyn.template get_reshaped_view<Homme::Real****>());
        if (fwd) {
          for (int idof=0; idof<dyn_grid->get_num_local_dofs(); ++idof) {
            int ie = h_d_lid2idx(idof,0);    
            int ip = h_d_lid2idx(idof,1);    
            int jp = h_d_lid2idx(idof,2);    
            for (int ilev=0; ilev<NVL; ++ilev) {
              if (dyn(ie,ip,jp,ilev)!=h_d_dofs(idof)) {
                  printf(" ** 3D Scalar ** \n");
                  printf("d_out(%d,%d,%d,%d): %2.16f\n",ie,ip,jp,ilev,dyn(ie,ip,jp,ilev));
                  printf("expected: = %ld\n",h_d_dofs(idof));
              }
              REQUIRE (dyn(ie,ip,jp,ilev)==h_d_dofs(idof));
            }
          }
        } else {
          for (int idof=0; idof<phys_grid->get_num_local_dofs(); ++idof) {
            for (int ilev=0; ilev<NVL; ++ilev) {
              if (phys(idof,ilev)!=h_p_dofs(idof)) {
                  printf(" ** 3D Scalar ** \n");
                  printf("p_out(%d,%d) = %2.16f\n",idof,ilev,phys(idof,ilev));
                  printf("expected: = %ld\n",h_p_dofs(idof));
              }
              REQUIRE (phys(idof,ilev)==h_p_dofs(idof));
            }
          }
        }
      }

      {
        // 3d vector
        auto phys = Kokkos::create_mirror_view(v_3d_field_phys.template get_reshaped_view<Homme::Real***>());
        auto dyn = Kokkos::create_mirror_view(v_3d_field_dyn.template get_reshaped_view<Homme::Real*****>());
        Kokkos::deep_copy(phys,v_3d_field_phys.template get_reshaped_view<Homme::Real***>());
        Kokkos::deep_copy(dyn,v_3d_field_dyn.template get_reshaped_view<Homme::Real*****>());
        if (fwd) {
          for (int idof=0; idof<dyn_grid->get_num_local_dofs(); ++idof) {
            int ie = h_d_lid2idx(idof,0);    
            int ip = h_d_lid2idx(idof,1);    
            int jp = h_d_lid2idx(idof,2);    
            for (int icomp=0; icomp<2; ++icomp) {
              for (int ilev=0; ilev<NVL; ++ilev) {
                if (dyn(ie,icomp,ip,jp,ilev)!=h_d_dofs(idof)) {
                    printf(" ** 3D Vector ** \n");
                    printf("d_out(%d,%d,%d,%d,%d): %2.16f\n",ie,icomp,ip,jp,ilev,dyn(ie,icomp,ip,jp,ilev));
                    printf("expected: = %ld\n",h_d_dofs(idof));
                }
                REQUIRE (dyn(ie,icomp,ip,jp,ilev)==h_d_dofs(idof));
              }
            }
          }
        } else {
          for (int idof=0; idof<phys_grid->get_num_local_dofs(); ++idof) {
            for (int icomp=0; icomp<2; ++icomp) {
              for (int ilev=0; ilev<NVL; ++ilev) {
                if (phys(idof,icomp,ilev)!=h_p_dofs(idof)) {
                    printf(" ** 3D Vector ** \n");
                    printf("p_out(%d,%d,%d) = %2.16f\n",idof,icomp,ilev,phys(idof,icomp,ilev));
                    printf("expected: = %ld\n",h_p_dofs(idof));
                }
                REQUIRE (phys(idof,icomp,ilev)==h_p_dofs(idof));
              }
            }
          }
        }
      }

      {
        // 3d scalar state
        const int itl = tl.np1;
        auto phys = Kokkos::create_mirror_view(ss_3d_field_phys.template get_reshaped_view<Homme::Real**>());
        auto dyn = Kokkos::create_mirror_view(ss_3d_field_dyn.template get_reshaped_view<Homme::Real*****>());
        Kokkos::deep_copy(phys,ss_3d_field_phys.template get_reshaped_view<Homme::Real**>());
        Kokkos::deep_copy(dyn,ss_3d_field_dyn.template get_reshaped_view<Homme::Real*****>());
        if (fwd) {
          for (int ilev=0; ilev<NVL; ++ilev) {
            for (int idof=0; idof<dyn_grid->get_num_local_dofs(); ++idof) {
              int ie = h_d_lid2idx(idof,0);
              int ip = h_d_lid2idx(idof,1);
              int jp = h_d_lid2idx(idof,2);
              auto gid = h_d_dofs(idof);
              if (dyn(ie,itl,ip,jp,ilev)!=gid) {
                  printf(" ** 3D Scalar State ** \n");
                  printf("d_out(%d,%d,%d,%d,%d): %2.16f\n",ie,itl,ip,jp,ilev,dyn(ie,itl,ip,jp,ilev));
                  printf("expected: = %ld\n",gid);
              }
              REQUIRE (dyn(ie,itl,ip,jp,ilev)==gid);
            }
          }
        } else {
          for (int idof=0; idof<phys_grid->get_num_local_dofs(); ++idof) {
            for (int ilev=0; ilev<NVL; ++ilev) {
              if (phys(idof,ilev)!=h_p_dofs(idof)) {
                  printf(" ** 3D Scalar State ** \n");
                  printf("p_out(%d,%d) = %2.16f\n",idof,ilev,phys(idof,ilev));
                  printf("expected: = %ld\n",h_p_dofs(idof));
              }
              REQUIRE (phys(idof,ilev)==h_p_dofs(idof));
            }
          }
        }
      }

      {
        // 3d vector state
        const int itl = tl.np1;
        auto phys = Kokkos::create_mirror_view(vs_3d_field_phys.template get_reshaped_view<Homme::Real***>());
        auto dyn = Kokkos::create_mirror_view(vs_3d_field_dyn.template get_reshaped_view<Homme::Real******>());
        Kokkos::deep_copy(phys,vs_3d_field_phys.template get_reshaped_view<Homme::Real***>());
        Kokkos::deep_copy(dyn,vs_3d_field_dyn.template get_reshaped_view<Homme::Real******>());
        if (fwd) {
          for (int idof=0; idof<dyn_grid->get_num_local_dofs(); ++idof) {
            int ie = h_d_lid2idx(idof,0);    
            int ip = h_d_lid2idx(idof,1);    
            int jp = h_d_lid2idx(idof,2);    
            for (int icomp=0; icomp<2; ++icomp) {
              for (int ilev=0; ilev<NVL; ++ilev) {
                if (dyn(ie,itl,icomp,ip,jp,ilev)!=h_d_dofs(idof)) {
                    printf(" ** 3D Vector State ** \n");
                    printf("d_out(%d,%d,%d,%d,%d): %2.16f\n",ie,icomp,ip,jp,ilev,dyn(ie,itl,icomp,ip,jp,ilev));
                    printf("expected: = %ld\n",h_d_dofs(idof));
                }
                REQUIRE (dyn(ie,itl,icomp,ip,jp,ilev)==h_d_dofs(idof));
              }
            }
          }
        } else {
          for (int idof=0; idof<phys_grid->get_num_local_dofs(); ++idof) {
            for (int icomp=0; icomp<2; ++icomp) {
              for (int ilev=0; ilev<NVL; ++ilev) {
                if (phys(idof,icomp,ilev)!=h_p_dofs(idof)) {
                    printf(" ** 3D Vector State ** \n");
                    printf("p_out(%d,%d,%d) = %2.16f\n",idof,icomp,ilev,phys(idof,icomp,ilev));
                    printf("expected: = %ld\n",h_p_dofs(idof));
                }
                REQUIRE (phys(idof,icomp,ilev)==h_p_dofs(idof));
              }
            }
          }
        }
      }

      {
        // 3d tracer state
        const int itl = tl.np1_qdp;
        auto phys = Kokkos::create_mirror_view(ts_3d_field_phys.template get_reshaped_view<Homme::Real***>());
        auto dyn = Kokkos::create_mirror_view(ts_3d_field_dyn.template get_reshaped_view<Homme::Real******>());
        Kokkos::deep_copy(phys,ts_3d_field_phys.template get_reshaped_view<Homme::Real***>());
        Kokkos::deep_copy(dyn,ts_3d_field_dyn.template get_reshaped_view<Homme::Real******>());
        if (fwd) {
          for (int idof=0; idof<dyn_grid->get_num_local_dofs(); ++idof) {
            int ie = h_d_lid2idx(idof,0);    
            int ip = h_d_lid2idx(idof,1);    
            int jp = h_d_lid2idx(idof,2);    
            for (int iq=0; iq<2; ++iq) {
              for (int ilev=0; ilev<NVL; ++ilev) {
                if (dyn(ie,itl,iq,ip,jp,ilev)!=h_d_dofs(idof)) {
                    printf(" ** 3D Tracer State ** \n");
                    printf("d_out(%d,%d,%d,%d,%d): %2.16f\n",ie,iq,ip,jp,ilev,dyn(ie,itl,iq,ip,jp,ilev));
                    printf("expected: = %ld\n",h_d_dofs(idof));
                }
                REQUIRE (dyn(ie,itl,iq,ip,jp,ilev)==h_d_dofs(idof));
              }
            }
          }
        } else {
          for (int idof=0; idof<phys_grid->get_num_local_dofs(); ++idof) {
            for (int iq=0; iq<2; ++iq) {
              for (int ilev=0; ilev<NVL; ++ilev) {
                if (phys(idof,iq,ilev)!=h_p_dofs(idof)) {
                    printf(" ** 3D Tracer State ** \n");
                    printf("p_out(%d,%d,%d) = %2.16f\n",idof,iq,ilev,phys(idof,iq,ilev));
                    printf("expected: = %ld\n",h_p_dofs(idof));
                }
                REQUIRE (phys(idof,iq,ilev)==h_p_dofs(idof));
              }
            }
          }
        }
      }
    }
  }

  // Delete remapper before finalizing the mpi context, since the remapper has some MPI stuff in it
  remapper = nullptr;

  // Finalize Homme::MpiContext (deletes buffers manager)
  Homme::Context::finalize_singleton();

  // Cleanup f90 structures
  cleanup_geometry_f90();
}

} // anonymous namespace
