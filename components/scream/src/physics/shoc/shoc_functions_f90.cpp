#include "shoc_functions_f90.hpp"

#include "ekat/scream_assert.hpp"
#include "ekat/util/scream_utils.hpp"
#include "ekat/util/scream_kokkos_utils.hpp"
#include "ekat/scream_pack_kokkos.hpp"
#include "shoc_f90.hpp"

#include <random>

using scream::Real;
using scream::Int;

//
// A C++ interface to SHOC fortran calls and vice versa
//

extern "C" {

void shoc_init_c(int nlev, Real gravit, Real rair, Real rh2o, Real cpair,
                 Real zvir, Real latvap, Real latice, Real karman,
                 Real* pref_mid, int nbot_shoc, int ntop_shoc);

void shoc_grid_c(int shcol, int nlev, int nlevi, Real* zt_grid, Real* zi_gri,
                 Real* pdel, Real* dz_dt, Real*, Real* rho_zt);
}

namespace scream {
namespace shoc {

// helper functions

// In all C++ -> Fortran bridge functions you should see shoc_init(nlev, true).
// We are provisionally following P3 here in case SHOC uses global data. The
// 'true' argument is to set shoc to use its fortran implementations instead of
// calling back to C++. We want this behavior since it doesn't make much sense
// for C++ to bridge over to fortran only to have fortran bridge back to C++.
// Anyone who wants the C++ implementation should call it directly.

struct SHOCSubroutineData // example data struct
{
  // In
  Real in1, in2, in3;

  // Out
  Real out1, out2, out3;
};

void shoc_subroutine(SHOCSubroutineData& d) // example wrapper function
{
  Int nlev = 128;
  shoc_init(nlev, true);
  // shoc_subroutine_c(d.in1, d.in2, d.in3, &d.out1, &d.out2, &d.out3);
}


void shoc_grid(Int nlev, SHOCGridData& d)
{
  shoc_init(nlev, true);
  shoc_grid_c(d.shcol, d.nlev, d.nlevi, d.zt_grid, d.zi_grid, d.pdel, d.dz_zt, d.dz_zi, d.rho_zt);
}

} // namespace shoc
} // namespace scream
