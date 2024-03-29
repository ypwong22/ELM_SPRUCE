!|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
!
!  seaice_velocity_solver_weak
!
!> \brief
!> \author Adrian K. Turner, LANL
!> \date 2013-2014
!> \details
!>
!
!-----------------------------------------------------------------------

module seaice_velocity_solver_weak

  use mpas_derived_types
  use mpas_pool_routines

  implicit none

  private
  save

  public :: &
       seaice_init_velocity_solver_weak, &
       seaice_strain_tensor_weak, &
       seaice_stress_tensor_weak, &
       seaice_stress_divergence_weak, &
       seaice_final_divergence_shear_weak

contains

!-----------------------------------------------------------------------
! Initialization
!-----------------------------------------------------------------------

!|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
!
!  seaice_init_velocity_solver_weak
!
!> \brief
!> \author Adrian K. Turner, LANL
!> \date 2013-2014
!> \details
!>
!
!-----------------------------------------------------------------------

  subroutine seaice_init_velocity_solver_weak(domain)!{{{

    use seaice_mesh, only: &
         seaice_normal_vectors

    type (domain_type), intent(inout) :: &
         domain !< Input/Output:

    type(block_type), pointer :: &
         blockPtr

    type(MPAS_pool_type), pointer :: &
         meshPool, &
         velocityWeakPool, &
         boundaryPool

    logical, pointer :: &
         config_rotate_cartesian_grid

    real(kind=RKIND), dimension(:,:,:), pointer :: &
         normalVectorPolygon, &
         normalVectorTriangle

    real(kind=RKIND), dimension(:), pointer :: &
         latCellRotated, &
         latVertexRotated

    integer, dimension(:), pointer :: &
         interiorVertex

    blockPtr => domain % blocklist
    do while (associated(blockPtr))

       call MPAS_pool_get_config(domain % configs, "config_rotate_cartesian_grid", config_rotate_cartesian_grid)

       call MPAS_pool_get_subpool(blockPtr % structs, "velocity_weak", velocityWeakPool)
       call MPAS_pool_get_subpool(blockPtr % structs, "mesh", meshPool)
       call MPAS_pool_get_subpool(blockPtr % structs, "boundary", boundaryPool)

       call MPAS_pool_get_array(velocityWeakPool, "normalVectorPolygon", normalVectorPolygon)
       call MPAS_pool_get_array(velocityWeakPool, "normalVectorTriangle", normalVectorTriangle)
       call MPAS_pool_get_array(velocityWeakPool, "latCellRotated", latCellRotated)
       call MPAS_pool_get_array(velocityWeakPool, "latVertexRotated", latVertexRotated)
       call MPAS_pool_get_array(boundaryPool, "interiorVertex", interiorVertex)

       call seaice_normal_vectors(&
            meshPool, &
            normalVectorPolygon, &
            normalVectorTriangle, &
            interiorVertex, &
            config_rotate_cartesian_grid, &
            .true., &
            latCellRotated, &
            latVertexRotated)

       blockPtr => blockPtr % next
    enddo

  end subroutine seaice_init_velocity_solver_weak!}}}

!-----------------------------------------------------------------------
! Time step
!-----------------------------------------------------------------------

!|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
!
!  seaice_strain_tensor_weak
!
!> \brief
!> \author Adrian K. Turner, LANL
!> \date 2013-2014
!> \details
!>
!
!-----------------------------------------------------------------------

  subroutine seaice_strain_tensor_weak(domain)!{{{

    use seaice_mesh_pool, only: &
         solveStress, &
         uVelocity, &
         vVelocity

    type(domain_type), intent(inout) :: &
         domain

    type(block_type), pointer :: &
         blockPtr

    type(MPAS_pool_type), pointer :: &
         meshPool, &
         velocityWeakPool

    real(kind=RKIND), dimension(:), pointer :: &
         strain11, &
         strain22, &
         strain12

    real(kind=RKIND), dimension(:), pointer :: &
         latCellRotated

    real(kind=RKIND), dimension(:,:,:), pointer :: &
         normalVectorPolygon

    integer :: &
         iCell, &
         iEdgeOnCell, &
         iEdge, &
         iVertexOnEdge, &
         iVertex

    real(kind=RKIND) :: &
         uVelocityEdge, &
         vVelocityEdge, &
         uCellCentre, &
         vCellCentre

    integer, pointer :: &
         nCells

    integer, dimension(:), pointer :: &
         nEdgesOnCell

    integer, dimension(:,:), pointer :: &
         verticesOnCell, &
         edgesOnCell, &
         verticesOnEdge

    real(kind=RKIND), pointer :: &
         sphere_radius

    real(kind=RKIND) :: &
         sphereRadius

    real(kind=RKIND), dimension(:), pointer :: &
         dvEdge, &
         areaCell

    blockPtr => domain % blocklist
    do while (associated(blockPtr))

       call MPAS_pool_get_subpool(blockPtr % structs, "mesh", meshPool)
       call MPAS_pool_get_subpool(blockPtr % structs, "velocity_weak", velocityWeakPool)

       call MPAS_pool_get_dimension(meshPool, "nCells", nCells)
       call MPAS_pool_get_config(meshPool, "sphere_radius", sphere_radius)

       call MPAS_pool_get_array(meshPool, "nEdgesOnCell", nEdgesOnCell)
       call MPAS_pool_get_array(meshPool, "verticesOnCell", verticesOnCell)
       call MPAS_pool_get_array(meshPool, "edgesOnCell", edgesOnCell)
       call MPAS_pool_get_array(meshPool, "verticesOnEdge", verticesOnEdge)
       call MPAS_pool_get_array(meshPool, "dvEdge", dvEdge)
       call MPAS_pool_get_array(meshPool, "areaCell", areaCell)

       call MPAS_pool_get_array(velocityWeakPool, "normalVectorPolygon", normalVectorPolygon)
       call MPAS_pool_get_array(velocityWeakPool, "latCellRotated", latCellRotated)
       call MPAS_pool_get_array(velocityWeakPool, "strain11", strain11)
       call MPAS_pool_get_array(velocityWeakPool, "strain22", strain22)
       call MPAS_pool_get_array(velocityWeakPool, "strain12", strain12)

       ! planar cases with zero sphere radius
       sphereRadius = sphere_radius
       if (sphereRadius == 0.0_RKIND) sphereRadius = 1.0_RKIND

       do iCell = 1, nCells

          strain11(iCell) = 0.0_RKIND
          strain22(iCell) = 0.0_RKIND
          strain12(iCell) = 0.0_RKIND

          if (solveStress(iCell) == 1) then

             uCellCentre = 0.0_RKIND
             vCellCentre = 0.0_RKIND

             do iEdgeOnCell = 1, nEdgesOnCell(iCell)

                ! cell centre velocities
                iVertex = verticesOnCell(iEdgeOnCell,iCell)

                uCellCentre = uCellCentre + uVelocity(iVertex)
                vCellCentre = vCellCentre + vVelocity(iVertex)

                ! interpolated edge velocity
                iEdge = edgesOnCell(iEdgeOnCell,iCell)

                uVelocityEdge = 0.0_RKIND
                vVelocityEdge = 0.0_RKIND

                do iVertexOnEdge = 1, 2

                   iVertex = verticesOnEdge(iVertexOnEdge,iEdge)

                   uVelocityEdge = uVelocityEdge + uVelocity(iVertex)
                   vVelocityEdge = vVelocityEdge + vVelocity(iVertex)

                enddo ! iVertexOnEdge

                uVelocityEdge = uVelocityEdge / 2.0_RKIND
                vVelocityEdge = vVelocityEdge / 2.0_RKIND

                ! summation over edges
                strain11(iCell) = strain11(iCell) + uVelocityEdge * normalVectorPolygon(1,iEdgeOnCell,iCell) * dvEdge(iEdge)
                strain22(iCell) = strain22(iCell) + vVelocityEdge * normalVectorPolygon(2,iEdgeOnCell,iCell) * dvEdge(iEdge)
                strain12(iCell) = strain12(iCell) + 0.5_RKIND * ( &
                     uVelocityEdge * normalVectorPolygon(2,iEdgeOnCell,iCell) + &
                     vVelocityEdge * normalVectorPolygon(1,iEdgeOnCell,iCell) ) * dvEdge(iEdge)

             enddo ! iEdgeOnCell

             uCellCentre = uCellCentre / real(nEdgesOnCell(iCell), RKIND)
             vCellCentre = vCellCentre / real(nEdgesOnCell(iCell), RKIND)

             strain11(iCell) = strain11(iCell) / areaCell(iCell)
             strain22(iCell) = strain22(iCell) / areaCell(iCell)
             strain12(iCell) = strain12(iCell) / areaCell(iCell)

             ! metric terms
             strain11(iCell) = strain11(iCell) - (vCellCentre * tan(latCellRotated(iCell))) / sphereRadius
             strain12(iCell) = strain12(iCell) + (uCellCentre * tan(latCellRotated(iCell)) * 0.5_RKIND) / sphereRadius

             !if (abs(strain11(iCell)) < 1e-10_RKIND) strain11(iCell) = 0.0_RKIND

          endif ! solveStress

       enddo ! iCell

       blockPtr => blockPtr % next
    end do

  end subroutine seaice_strain_tensor_weak!}}}

!|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
!
!  seaice_stress_tensor_weak
!
!> \brief
!> \author Adrian K. Turner, LANL
!> \date 2013-2014
!> \details
!>
!
!-----------------------------------------------------------------------

  subroutine seaice_stress_tensor_weak(domain)!{{{

    use seaice_mesh_pool, only: &
         icePressure, &
         solveStress

    use seaice_velocity_solver_constitutive_relation, only: &
         constitutiveRelationType, &
         EVP_CONSTITUTIVE_RELATION, &
         REVISED_EVP_CONSTITUTIVE_RELATION, &
         LINEAR_CONSTITUTIVE_RELATION, &
         seaice_evp_constitutive_relation, &
         seaice_evp_constitutive_relation_revised, &
         seaice_linear_constitutive_relation

    type(domain_type), intent(inout) :: &
         domain

    type(block_type), pointer :: &
         blockPtr

    type(MPAS_pool_type), pointer :: &
         meshPool, &
         velocitySolverPool, &
         velocityWeakPool

    real(kind=RKIND), dimension(:), pointer :: &
         replacementPressure

    real(kind=RKIND), dimension(:), pointer :: &
         strain11, &
         strain22, &
         strain12, &
         stress11, &
         stress22, &
         stress12

    real(kind=RKIND), pointer :: &
         elasticTimeStep

    integer :: &
         iCell

    integer, pointer :: &
         nCells

    real(kind=RKIND), dimension(:), pointer :: &
         areaCell

    blockPtr => domain % blocklist
    do while (associated(blockPtr))

       call MPAS_pool_get_subpool(blockPtr % structs, "mesh", meshPool)
       call MPAS_pool_get_subpool(blockPtr % structs, "velocity_solver", velocitySolverPool)
       call MPAS_pool_get_subpool(blockPtr % structs, "velocity_weak", velocityWeakPool)

       call MPAS_pool_get_dimension(meshPool, "nCells", nCells)

       call MPAS_pool_get_array(meshPool, "areaCell", areaCell)

       call MPAS_pool_get_array(velocitySolverPool, "elasticTimeStep", elasticTimeStep)

       call MPAS_pool_get_array(velocityWeakPool, "strain11", strain11)
       call MPAS_pool_get_array(velocityWeakPool, "strain22", strain22)
       call MPAS_pool_get_array(velocityWeakPool, "strain12", strain12)
       call MPAS_pool_get_array(velocityWeakPool, "stress11", stress11)
       call MPAS_pool_get_array(velocityWeakPool, "stress22", stress22)
       call MPAS_pool_get_array(velocityWeakPool, "stress12", stress12)
       call MPAS_pool_get_array(velocityWeakPool, "replacementPressure", replacementPressure)

       if (constitutiveRelationType == EVP_CONSTITUTIVE_RELATION) then

          do iCell = 1, nCells

             if (solveStress(iCell) == 1) then

                call seaice_evp_constitutive_relation(&
                     stress11(iCell), &
                     stress22(iCell), &
                     stress12(iCell), &
                     strain11(iCell), &
                     strain22(iCell), &
                     strain12(iCell), &
                     icePressure(iCell), &
                     replacementPressure(iCell), &
                     areaCell(iCell), &
                     elasticTimeStep)

             else

                stress11(iCell) = 0.0_RKIND
                stress22(iCell) = 0.0_RKIND
                stress12(iCell) = 0.0_RKIND

             endif ! solveStress

          end do ! iCell

       else if (constitutiveRelationType == REVISED_EVP_CONSTITUTIVE_RELATION) then

          do iCell = 1, nCells

             if (solveStress(iCell) == 1) then

                call seaice_evp_constitutive_relation_revised(&
                     stress11(iCell), &
                     stress22(iCell), &
                     stress12(iCell), &
                     strain11(iCell), &
                     strain22(iCell), &
                     strain12(iCell), &
                     icePressure(iCell), &
                     replacementPressure(iCell), &
                     areaCell(iCell))

             else

                stress11(iCell) = 0.0_RKIND
                stress22(iCell) = 0.0_RKIND
                stress12(iCell) = 0.0_RKIND

             endif ! solveStress

          end do ! iCell

       else if (constitutiveRelationType == LINEAR_CONSTITUTIVE_RELATION) then

          do iCell = 1, nCells

             if (solveStress(iCell) == 1) then

                call seaice_linear_constitutive_relation(&
                     stress11(iCell), &
                     stress22(iCell), &
                     stress12(iCell), &
                     strain11(iCell), &
                     strain22(iCell), &
                     strain12(iCell))

             else

                stress11(iCell) = 0.0_RKIND
                stress22(iCell) = 0.0_RKIND
                stress12(iCell) = 0.0_RKIND

             endif ! solveStress

          enddo ! iCell

       endif ! constitutiveRelationType

       blockPtr => blockPtr % next
    end do

  end subroutine seaice_stress_tensor_weak!}}}

!|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
!
!  seaice_stress_tensor_weak_linear
!
!> \brief
!> \author Adrian K. Turner, LANL
!> \date 2013-2014
!> \details
!>
!
!-----------------------------------------------------------------------

  subroutine seaice_stress_tensor_weak_linear(domain)!{{{

    use seaice_velocity_solver_constitutive_relation, only: &
         seaice_linear_constitutive_relation

    use seaice_mesh_pool, only: &
         nCells, &
         solveStress

    type(domain_type), intent(inout) :: &
         domain

    type(block_type), pointer :: &
         blockPtr

    type(MPAS_pool_type), pointer :: &
         meshPool, &
         velocityWeakPool

    real(kind=RKIND), dimension(:), pointer :: &
         stress11, & !< Output:
         stress22, & !< Output:
         stress12    !< Output:

    real(kind=RKIND), dimension(:), pointer :: &
         strain11, & !< Input:
         strain22, & !< Input:
         strain12    !< Input:

    integer :: &
         iCell

    blockPtr => domain % blocklist
    do while (associated(blockPtr))

       call MPAS_pool_get_subpool(blockPtr % structs, "mesh", meshPool)
       call MPAS_pool_get_subpool(blockPtr % structs, "velocity_weak", velocityWeakPool)

       call MPAS_pool_get_array(velocityWeakPool, "strain11", strain11)
       call MPAS_pool_get_array(velocityWeakPool, "strain22", strain22)
       call MPAS_pool_get_array(velocityWeakPool, "strain12", strain12)
       call MPAS_pool_get_array(velocityWeakPool, "stress11", stress11)
       call MPAS_pool_get_array(velocityWeakPool, "stress22", stress22)
       call MPAS_pool_get_array(velocityWeakPool, "stress12", stress12)

       do iCell = 1, nCells

          if (solveStress(iCell) == 1) then

             call seaice_linear_constitutive_relation(&
                  stress11(iCell), &
                  stress22(iCell), &
                  stress12(iCell), &
                  strain11(iCell), &
                  strain22(iCell), &
                  strain12(iCell))

          else

             stress11(iCell) = 0.0_RKIND
             stress22(iCell) = 0.0_RKIND
             stress12(iCell) = 0.0_RKIND

          endif ! solveStress

       enddo ! iCell

       blockPtr => blockPtr % next
    end do

  end subroutine seaice_stress_tensor_weak_linear!}}}

!|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
!
!  seaice_stress_divergence_weak
!
!> \brief
!> \author Adrian K. Turner, LANL
!> \date 2013-2014
!> \details
!>
!
!-----------------------------------------------------------------------

  subroutine seaice_stress_divergence_weak(domain)!{{{

    use seaice_mesh_pool, only: &
         solveVelocity

    type(domain_type), intent(inout) :: &
         domain

    type(block_type), pointer :: &
         blockPtr

    type(MPAS_pool_type), pointer :: &
         meshPool, &
         velocitySolverPool, &
         velocityWeakPool

    real(kind=RKIND), dimension(:), pointer :: &
         stressDivergenceU, &
         stressDivergenceV

    real(kind=RKIND), dimension(:), pointer :: &
         stress11, &
         stress22, &
         stress12, &
         latVertexRotated

    real(kind=RKIND), dimension(:,:,:), pointer :: &
         normalVectorTriangle

    real(kind=RKIND) :: &
         stress11Edge, &
         stress22Edge, &
         stress12Edge, &
         stress11Vertex, &
         stress22Vertex, &
         stress12Vertex

    integer :: &
         iVertex, &
         iVertexDegree, &
         iEdge, &
         iCellOnEdge, &
         iCell

    integer, pointer :: &
         nVerticesSolve, &
         vertexDegree

    integer, dimension(:,:), pointer :: &
         cellsOnVertex, &
         edgesOnVertex, &
         cellsOnEdge

    real(kind=RKIND), pointer :: &
         sphere_radius

    real(kind=RKIND) :: &
         sphereRadius

    real(kind=RKIND), dimension(:), pointer :: &
         areaTriangle, &
         dcEdge

    blockPtr => domain % blocklist
    do while (associated(blockPtr))

       call MPAS_pool_get_subpool(blockPtr % structs, "mesh", meshPool)
       call MPAS_pool_get_subpool(blockPtr % structs, "velocity_weak", velocityWeakPool)
       call MPAS_pool_get_subpool(blockPtr % structs, "velocity_solver", velocitySolverPool)

       call MPAS_pool_get_dimension(meshPool, "nVertices", nVerticesSolve)
       call MPAS_pool_get_dimension(meshPool, "vertexDegree", vertexDegree)
       call MPAS_pool_get_config(meshPool, "sphere_radius", sphere_radius)

       call MPAS_pool_get_array(meshPool, "cellsOnVertex", cellsOnVertex)
       call MPAS_pool_get_array(meshPool, "edgesOnVertex", edgesOnVertex)
       call MPAS_pool_get_array(meshPool, "cellsOnEdge", cellsOnEdge)
       call MPAS_pool_get_array(meshPool, "areaTriangle", areaTriangle)
       call MPAS_pool_get_array(meshPool, "dcEdge", dcEdge)

       call MPAS_pool_get_array(velocitySolverPool, "stressDivergenceU", stressDivergenceU)
       call MPAS_pool_get_array(velocitySolverPool, "stressDivergenceV", stressDivergenceV)

       call MPAS_pool_get_array(velocityWeakPool, "normalVectorTriangle", normalVectorTriangle)
       call MPAS_pool_get_array(velocityWeakPool, "latVertexRotated", latVertexRotated)
       call MPAS_pool_get_array(velocityWeakPool, "stress11", stress11)
       call MPAS_pool_get_array(velocityWeakPool, "stress22", stress22)
       call MPAS_pool_get_array(velocityWeakPool, "stress12", stress12)

       ! planar cases with zero sphere radius
       sphereRadius = sphere_radius
       if (sphereRadius == 0.0_RKIND) sphereRadius = 1.0_RKIND

       do iVertex = 1, nVerticesSolve

          stressDivergenceU(iVertex) = 0.0_RKIND
          stressDivergenceV(iVertex) = 0.0_RKIND

          if (solveVelocity(iVertex) == 1) then

             stress11Vertex = 0.0_RKIND
             stress22Vertex = 0.0_RKIND
             stress12Vertex = 0.0_RKIND

             do iVertexDegree = 1, vertexDegree

                ! vertex stresses
                iCell = cellsOnVertex(iVertexDegree,iVertex)

                stress11Vertex = stress11Vertex + stress11(iCell)
                stress22Vertex = stress22Vertex + stress22(iCell)
                stress12Vertex = stress12Vertex + stress12(iCell)

                ! interpolated edge velocity
                iEdge = edgesOnVertex(iVertexDegree,iVertex)

                stress11Edge = 0.0_RKIND
                stress22Edge = 0.0_RKIND
                stress12Edge = 0.0_RKIND

                do iCellOnEdge = 1, 2

                   iCell = cellsOnEdge(iCellOnEdge,iEdge)

                   stress11Edge = stress11Edge + stress11(iCell)
                   stress22Edge = stress22Edge + stress22(iCell)
                   stress12Edge = stress12Edge + stress12(iCell)

                enddo ! iCellOnEdge

                stress11Edge = stress11Edge / 2.0_RKIND
                stress22Edge = stress22Edge / 2.0_RKIND
                stress12Edge = stress12Edge / 2.0_RKIND

                stressDivergenceU(iVertex) = stressDivergenceU(iVertex) + &
                     (stress11Edge * normalVectorTriangle(1,iVertexDegree,iVertex) + &
                     stress12Edge * normalVectorTriangle(2,iVertexDegree,iVertex)) * dcEdge(iEdge)

                stressDivergenceV(iVertex) = stressDivergenceV(iVertex) + &
                     (stress22Edge * normalVectorTriangle(2,iVertexDegree,iVertex) + &
                     stress12Edge * normalVectorTriangle(1,iVertexDegree,iVertex)) * dcEdge(iEdge)

             enddo ! iVertexDegree

             stress11Vertex = stress11Vertex / real(vertexDegree, RKIND)
             stress22Vertex = stress22Vertex / real(vertexDegree, RKIND)
             stress12Vertex = stress12Vertex / real(vertexDegree, RKIND)

             stressDivergenceU(iVertex) = stressDivergenceU(iVertex) / areaTriangle(iVertex)
             stressDivergenceV(iVertex) = stressDivergenceV(iVertex) / areaTriangle(iVertex)

             ! metric terms
             stressDivergenceU(iVertex) = stressDivergenceU(iVertex) - &
                  (tan(latVertexRotated(iVertex)) * stress12Vertex) / sphereRadius
             stressDivergenceV(iVertex) = stressDivergenceV(iVertex) + &
                  (tan(latVertexRotated(iVertex)) * stress11Vertex) / sphereRadius

          endif ! solveVelocity

       enddo ! iVertex

       blockPtr => blockPtr % next
    end do

  end subroutine seaice_stress_divergence_weak!}}}

!|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
!
!  final_divergence_shear_weak
!
!> \brief
!> \author Adrian K. Turner, LANL
!> \date July 9th 2015
!> \details
!>
!
!-----------------------------------------------------------------------

  subroutine seaice_final_divergence_shear_weak(domain)

    use seaice_velocity_solver_constitutive_relation, only: &
         eccentricitySquared

    use seaice_mesh_pool, only: &
         nCells, &
         solveStress, &
         nEdgesOnCell

    type(domain_type), intent(inout) :: &
         domain

    type(block_type), pointer :: &
         blockPtr

    type(MPAS_pool_type), pointer :: &
         meshPool, &
         velocityWeakPool, &
         velocitySolverPool, &
         ridgingPool

    real(kind=RKIND), dimension(:), pointer :: &
         strain11, &
         strain22, &
         strain12, &
         divergence, &
         shear, &
         ridgeConvergence, &
         ridgeShear

    real(kind=RKIND), dimension(:), allocatable :: &
         Delta

    real(kind=RKIND) :: &
         strainDivergence, &
         strainTension, &
         strainShearing

    logical, pointer :: &
         config_use_column_physics

    integer :: &
         iCell

    blockPtr => domain % blocklist
    do while (associated(blockPtr))

       call MPAS_pool_get_subpool(blockPtr % structs, "mesh", meshPool)
       call MPAS_pool_get_subpool(blockPtr % structs, "velocity_weak", velocityWeakPool)
       call MPAS_pool_get_subpool(blockPtr % structs, "velocity_solver", velocitySolverPool)

       call MPAS_pool_get_array(velocityWeakPool, "strain11", strain11)
       call MPAS_pool_get_array(velocityWeakPool, "strain22", strain22)
       call MPAS_pool_get_array(velocityWeakPool, "strain12", strain12)

       call MPAS_pool_get_array(velocitySolverPool, "divergence", divergence)
       call MPAS_pool_get_array(velocitySolverPool, "shear", shear)

       allocate(Delta(nCells))

       do iCell = 1, nCells

          if (solveStress(iCell) == 1) then

             strainDivergence = strain11(iCell) + strain22(iCell)
             strainTension    = strain11(iCell) - strain22(iCell)
             strainShearing   = strain12(iCell) * 2.0_RKIND

             Delta(iCell) = sqrt(strainDivergence**2 + (strainTension**2 + strainShearing**2) / eccentricitySquared)

             divergence(iCell) = strainDivergence
             shear(iCell)      = sqrt(strainTension**2 + strainShearing**2)

          else

             divergence(iCell)   = 0.0_RKIND
             shear(iCell)        = 0.0_RKIND

          endif

       enddo ! iCell

       ! ridging parameters
       call MPAS_pool_get_config(blockPtr % configs, "config_use_column_physics", config_use_column_physics)

       if (config_use_column_physics) then

          call MPAS_pool_get_subpool(blockPtr % structs, "ridging", ridgingPool)

          call MPAS_pool_get_array(ridgingPool, "ridgeConvergence", ridgeConvergence)
          call MPAS_pool_get_array(ridgingPool, "ridgeShear", ridgeShear)

          do iCell = 1, nCells

             if (solveStress(iCell) == 1) then

                ridgeConvergence(iCell) = -min(divergence(iCell),0.0_RKIND)
                ridgeShear(iCell)       = 0.5_RKIND * (Delta(iCell) - abs(divergence(iCell)))

             else

                ridgeConvergence(iCell) = 0.0_RKIND
                ridgeShear(iCell)       = 0.0_RKIND

             endif

          enddo ! iCell

       endif ! config_use_column_physics

       ! cleanup
       deallocate(Delta)

       blockPtr => blockPtr % next
    enddo

  end subroutine seaice_final_divergence_shear_weak

!-----------------------------------------------------------------------

end module seaice_velocity_solver_weak
