if (COMP_NAME STREQUAL gptl)
  string(APPEND CPPDEFS " -DHAVE_VPRINTF -DHAVE_GETTIMEOFDAY -DHAVE_BACKTRACE -DHAVE_SLASHPROC")
endif()
string(APPEND CMAKE_Fortran_FLAGS_RELEASE " -fno-unsafe-math-optimizations")
string(APPEND CMAKE_EXE_LINKER_FLAGS " -L$ENV{CURL_PATH}/lib -lcurl")
