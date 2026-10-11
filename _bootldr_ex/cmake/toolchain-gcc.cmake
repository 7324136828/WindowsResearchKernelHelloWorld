# Retain explicit toolchain prefixes during CMake's compiler probes as well as
# in the real build. The upstream toolchain only forwards ARCH to try_compile.
include("${CMAKE_CURRENT_LIST_DIR}/../toolchain-gcc.cmake")
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
     MINGW_TOOLCHAIN_PREFIX MINGW_TOOLCHAIN_SUFFIX)
