if (compile_threaded)
  string(APPEND CMAKE_C_FLAGS " -static-intel")
  string(APPEND CMAKE_Fortran_FLAGS " -static-intel")
  string(APPEND CMAKE_EXE_LINKER_FLAGS " -static-intel")
  string(APPEND CMAKE_C_FLAGS_DEBUG " -heap-arrays")
  string(APPEND CMAKE_Fortran_FLAGS_DEBUG " -heap-arrays")
endif()
if (COMP_NAME STREQUAL gptl)
  string(APPEND CPPDEFS " -DHAVE_SLASHPROC")
endif()
string(APPEND CMAKE_Fortran_FLAGS_RELEASE " -qno-opt-dynamic-align")
if (MPILIB STREQUAL impi)
  set(MPICC "mpiicc")
  set(MPICXX "mpiicpc")
  set(MPIFC "mpiifort")
endif()
set(PIO_FILESYSTEM_HINTS "gpfs")
