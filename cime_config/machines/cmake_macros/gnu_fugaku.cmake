string(APPEND CPPDEFS " -DHAVE_SLASHPROC")
string(APPEND CMAKE_C_FLAGS_RELEASE " -O2")
string(APPEND CMAKE_Fortran_FLAGS_RELEASE " -O2")
if (COMP_NAME MATCHES "^pio")
  string(APPEND SPIO_CMAKE_OPTS " -DPIO_ENABLE_TOOLS:BOOL=OFF")
endif()
