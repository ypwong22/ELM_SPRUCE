#include <catch2/catch.hpp>

#include "share/grid/point_grid.hpp"
#include "share/grid/se_grid.hpp"
#include "share/grid/grids_manager.hpp"
#include "share/grid/grid_utils.hpp"
#include "share/scream_types.hpp"

#include "ekat/ekat_pack.hpp"

namespace {

using namespace scream;
using namespace scream::ShortFieldTagsNames;

TEST_CASE("point_grid", "") {

  ekat::Comm comm(MPI_COMM_WORLD);

  const int num_procs = comm.size();
  const int num_local_cols = 128;
  const int num_global_cols = num_local_cols*num_procs;
  const int num_levels = 72;

  auto grid = create_point_grid("my_grid", num_global_cols, num_levels, comm);
  REQUIRE(grid->type() == GridType::Point);
  REQUIRE(grid->name() == "my_grid");
  REQUIRE(grid->get_num_vertical_levels() == num_levels);
  REQUIRE(grid->get_num_local_dofs()  == num_local_cols);
  REQUIRE(grid->get_num_global_dofs() == num_global_cols);
  REQUIRE(grid->is_unique());

  auto lid_to_idx = grid->get_lid_to_idx_map();
  auto host_lid_to_idx = Kokkos::create_mirror_view(lid_to_idx);
  Kokkos::deep_copy(host_lid_to_idx, lid_to_idx);
  for (int i = 0; i < grid->get_num_local_dofs(); ++i) {
    REQUIRE(host_lid_to_idx.extent_int(1) == 1);
    REQUIRE(i == host_lid_to_idx(i, 0));
  }

  auto layout = grid->get_2d_scalar_layout();
  REQUIRE(layout.tags().size() == 1);
  REQUIRE(layout.tag(0) == COL);
}

TEST_CASE("se_grid", "") {
  // Assume a "strip" of elements:
  //
  //  *---*---*     *---*
  //  |   |   | ... |   *
  //  *---*---*     *---*
  //
  // partitioned evenly across ranks. Use this config to establish
  // a unique numbering for each element, using the following:
  //
  //   1--5--9-13  13-17-21-25
  //   |  |  |  |   |  |  |  |
  //   2--6-10-14  14-18-22-26
  //   |  |  |  |   |  |  |  |
  //   3--7-11-15  15-19-23-27
  //   |  |  |  |   |  |  |  |
  //   4--8-12-16  16-20-24-28

  ekat::Comm comm(MPI_COMM_WORLD);

  const int num_local_elems = 10;
  const int num_gp = 4;
  const int num_levels = 72;

  SEGrid grid("se_grid",num_local_elems,num_gp,num_levels,comm);
  REQUIRE(grid.type() == GridType::SE);
  REQUIRE(grid.name() == "se_grid");
  REQUIRE(grid.get_num_vertical_levels() == num_levels);
  REQUIRE(grid.get_num_local_dofs() == num_local_elems*num_gp*num_gp);

  auto layout = grid.get_2d_scalar_layout();
  REQUIRE(layout.tags().size() == 3);
  REQUIRE(layout.tag(0) == EL);
  REQUIRE(layout.tag(1) == GP);
  REQUIRE(layout.tag(2) == GP);

  // Set up the degrees of freedom.
  SEGrid::dofs_list_type dofs("", num_local_elems*num_gp*num_gp);
  auto host_dofs = Kokkos::create_mirror_view(dofs);
  SEGrid::lid_to_idx_map_type dofs_map("", num_local_elems*num_gp*num_gp, 3);
  auto host_dofs_map = Kokkos::create_mirror_view(dofs_map);

  // Count unique local dofs. On all elems except the very last one (on rank N),
  // we have num_gp*(num_gp-1) unique dofs;
  int num_elem_unique_dofs = num_gp*(num_gp-1);
  int num_local_unique_dofs = num_local_elems*num_elem_unique_dofs;
  int offset = num_local_unique_dofs*comm.rank();

  for (int ie = 0; ie < num_local_elems; ++ie) {
    for (int igp = 0; igp < num_gp-1; ++igp) {
      for (int jgp = 0; jgp < num_gp; ++jgp) {
        int idof = ie*num_gp*num_gp + igp*num_gp + jgp;
        int gid = offset + ie*num_elem_unique_dofs + igp*num_gp + jgp;
        host_dofs(idof) = gid;
        host_dofs_map(idof, 0) = ie;
        host_dofs_map(idof, 1) = igp;
        host_dofs_map(idof, 2) = jgp;
      }
    }
    for (int jgp = 0; jgp < num_gp; ++jgp) {
      int idof = ie*num_gp*num_gp + (num_gp-1)*num_gp + jgp;
      int gid = offset + (ie+1)*num_elem_unique_dofs + jgp;
      host_dofs(idof) = gid;
      host_dofs_map(idof, 0) = ie;
      host_dofs_map(idof, 1) = num_gp-1;
      host_dofs_map(idof, 2) = jgp;
    }
  }

  // Move the data to the device and set the DOFs.
  Kokkos::deep_copy(dofs, host_dofs);
  Kokkos::deep_copy(dofs_map, host_dofs_map);
  grid.set_dofs(dofs);
  grid.set_lid_to_idx_map(dofs_map);

  // Dofs gids are replicated along edges, so the SE grid should *not* be unique
  REQUIRE (not grid.is_unique());
}

} // anonymous namespace
