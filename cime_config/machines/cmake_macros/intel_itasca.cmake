string(APPEND CFLAGS " -O2 -fp-model precise -I/soft/intel/x86_64/2013/composer_xe_2013/composer_xe_2013_sp1.3.174/mkl/include")
if (compile_threaded)
  string(APPEND CFLAGS " -openmp")
endif()
string(APPEND CPPDEFS " -DFORTRANUNDERSCORE -DNO_R16")
string(APPEND CPPDEFS " -DCPRINTEL")
string(APPEND CXX_LDFLAGS " -cxxlib")
set(CXX_LINKER "FORTRAN")
string(APPEND FC_AUTO_R8 " -r8")
string(APPEND FFLAGS " -fp-model source -convert big_endian -assume byterecl -ftz -traceback -assume realloc_lhs -I/soft/intel/x86_64/2013/composer_xe_2013/composer_xe_2013_sp1.3.174/mkl/include")
if (compile_threaded)
  string(APPEND FFLAGS " -openmp")
endif()
if (DEBUG)
  string(APPEND FFLAGS " -O0 -g -check uninit -check bounds -check pointers -fpe0")
endif()
if (NOT DEBUG)
  string(APPEND FFLAGS " -O2")
endif()
string(APPEND FIXEDFLAGS " -fixed -132")
string(APPEND FREEFLAGS " -free")
if (compile_threaded)
  string(APPEND LDFLAGS " -openmp")
endif()
set(MPICC "mpiicc")
set(MPICXX "mpiicpc")
set(MPIFC "mpiifort")
set(SCC "icc")
set(SCXX "icpc")
set(SFC "ifort")
string(APPEND SLIBS " -L/soft/netcdf/fortran-4.4-intel-sp1-update3-parallel/lib -lnetcdff -L/soft/hdf5/hdf5-1.8.13-intel-2013-sp1-update3-impi-5.0.0.028/lib -openmp -fPIC -lnetcdf -lnetcdf -L/soft/intel/x86_64/2013/composer_xe_2013/composer_xe_2013_sp1.3.174/mkl/lib/intel64 -lmkl_intel_lp64 -lmkl_core -lmkl_intel_thread -lpthread -lm")
set(SUPPORTS_CXX "TRUE")
