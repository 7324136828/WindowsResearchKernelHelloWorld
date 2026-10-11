# Target initialization extracted from the ReactOS root CMakeLists.txt.
    # We don't need CMake importlib handling.
    unset(CMAKE_IMPORT_LIBRARY_SUFFIX)

    # Print build type(s)
    if(CMAKE_CONFIGURATION_TYPES)
        # Multi-config generators, like Visual Studio (MSBuild).
        message("-- Configuration types: ${CMAKE_CONFIGURATION_TYPES}")
    else()
        # Single-configuration generators, like Ninja.
        message("-- Build type: ${CMAKE_BUILD_TYPE}")
    endif()

    # Always add /MT in VS CMAKE_GENERATOR and define _SBCS otherwise VS thinks it's a multi-byte or whatever project
    if (MSVC_IDE)
        add_compile_options("/MT")
        add_compile_definitions(_SBCS)
    endif()


    # adjust the default behaviour of the FIND_XXX() commands:
    # search headers and libraries in the target environment, search
    # programs in the host environment
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE NEVER)

    # Add our own target properties
    # General module definitions
    define_property(TARGET PROPERTY REACTOS_MODULE_TYPE
        BRIEF_DOCS "The type of this module"
        FULL_DOCS [[
The type of this module.
One of "nativecui", "nativedll", "kernelmodedriver", "wdmdriver", "kerneldll", "win32cui", "win32gui", "win32dll", "win32ocx", "cpl" or "module"]])

    # C++
    define_property(TARGET PROPERTY WITH_CXX_EXCEPTIONS
        BRIEF_DOCS "Enable C++ exceptions on this target"
        FULL_DOCS [[
Enables C++ exception handling.
Enable this if the module uses try/catch or throw. You might also need this if you use a standard operator new (the one without nothrow).]])
    define_property(TARGET PROPERTY WITH_CXX_RTTI
        BRIEF_DOCS "Enable C++ RTTI on this target"
        FULL_DOCS [[
Enables run-time type information.
Enable this if the module uses typeid or dynamic_cast. You will probably need to link yith cpprt as well, if you are not already using STL.]])


    if(DBG)
        add_definitions(-DDBG=1 -D_SEH_ENABLE_TRACE)
    else()
        add_definitions(-DDBG=0)
    endif()

    if(ENABLE_CCACHE)
        message(WARNING "-- Disabling precompiled headers support (ccache).")
        option(PCH "Whether to use precompiled headers" OFF)
        set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE ccache)
    elseif(CMAKE_C_COMPILER_ID STREQUAL "GNU")
        message(WARNING "-- Disabling precompiled headers on GCC by default CORE-17108.")
        option(PCH "Whether to use precompiled headers" OFF)
    else()
        option(PCH "Whether to use precompiled headers" ON)
    endif()

    # Version Options
    add_definitions(-DWINVER=0x502
                    -D_WIN32_IE=0x603
                    -D_WIN32_WINNT=0x502
                    -D_WIN32_WINDOWS=0x502
                    -D_SETUPAPI_VER=0x502
                    -DMINGW_HAS_SECURE_API=1
                    -DD3D_UMD_INTERFACE_VERSION=0x000C # Vista
                    -DDXGKDDI_INTERFACE_VERSION=0x1052 # Vista
                    -DDLL_EXPORT_VERSION=${DLL_EXPORT_VERSION})

    # Arch Options
    if(ARCH STREQUAL "i386")
        # clang-cl defines this one for itself
        if(NOT (MSVC AND CMAKE_C_COMPILER_ID STREQUAL "Clang"))
            add_definitions(-D_M_IX86)
        endif()
        add_definitions(-D_X86_ -D__i386__ -Di386)
        if(SARCH STREQUAL "xbox")
            add_definitions(-DSARCH_XBOX)
        elseif(SARCH STREQUAL "pc98")
            add_definitions(-DSARCH_PC98)
        endif()
    elseif(ARCH STREQUAL "amd64")
        # clang-cl defines this one for itself
        if (NOT (MSVC AND CMAKE_C_COMPILER_ID STREQUAL "Clang"))
            add_compile_definitions(_M_AMD64 _M_X64)
        endif()
        add_definitions(-D_AMD64_ -D__x86_64__ -D_WIN64)
    elseif(ARCH STREQUAL "arm")
        # _M_ARM is already defined by toolchain
        add_definitions(-D_ARM_ -D__arm__ -DWIN32)
        if(SARCH STREQUAL "omap3-zoom2")
            add_definitions(-D_ZOOM2_)
        endif()
    elseif(ARCH STREQUAL "arm64")
        # GNU tools refer to arm64 as aarch64
        add_definitions(-D_ARM64_ -D__arm64__ -D__aarch64__ -D_WIN64)
    endif()

    # Other
    add_definitions(-D_NEW_DELETE_OPERATORS_)
    if(ARCH STREQUAL "i386")
        add_definitions(-DUSE_COMPILER_EXCEPTIONS -D_USE_32BIT_TIME_T)
    elseif(ARCH STREQUAL "amd64")
        add_compile_definitions(USE_COMPILER_EXCEPTIONS)
    elseif(ARCH STREQUAL "arm")
        add_compile_definitions(USE_COMPILER_EXCEPTIONS)
    elseif(ARCH STREQUAL "arm64")
        add_compile_definitions(USE_COMPILER_EXCEPTIONS)
    endif()

    # Activate support for assembly source files
    if (MSVC)
        enable_language(ASM_MASM)
    else()
        enable_language(ASM)
    endif()

    # Activate language support for resource files
    enable_language(RC)

    # Localization definitions
    include(sdk/cmake/localization.cmake)
    set(I18N_DEFS "")
    # This will set I18N_DEFS for later use
    set_i18n_language(${I18N_LANG})

    # Compiler specific definitions and macros
    if(MSVC)
        include(sdk/cmake/msvc.cmake)
    else()
        include(sdk/cmake/gcc.cmake)
    endif()

    # Generic macros
    include(sdk/cmake/CMakeMacros.cmake)

    # IDL macros for widl/midl
    # We're using widl now for both MSVC and GCC builds
    include(sdk/cmake/widl-support.cmake)

    include_directories(
        sdk/include
        sdk/include/crt
        sdk/include/ddk
        sdk/include/ndk
        sdk/include/psdk
        sdk/include/reactos
        sdk/include/reactos/libs
        sdk/include/vcruntime
        sdk/include/winrt
        ${REACTOS_BINARY_DIR}/sdk/include
        ${REACTOS_BINARY_DIR}/sdk/include/psdk
        ${REACTOS_BINARY_DIR}/sdk/include/ddk
        ${REACTOS_BINARY_DIR}/sdk/include/dxsdk
        ${REACTOS_BINARY_DIR}/sdk/include/reactos
        ${REACTOS_BINARY_DIR}/sdk/include/reactos/mc
        sdk/include/dxsdk
        sdk/lib/pseh/include
    )

    if(ARCH STREQUAL "arm")
        include_directories(${REACTOS_SOURCE_DIR}/sdk/include/reactos/arm)
    endif()

    add_dependency_header()

    add_subdirectory(sdk/include)

    if(ARCH MATCHES "64$")
        include(sdk/cmake/baseaddress64.cmake)
    elseif(NO_ROSSYM)
        include(sdk/cmake/baseaddress_dwarf.cmake)
    elseif(MSVC)
        include(sdk/cmake/baseaddress_msvc.cmake)
    else()
        include(sdk/cmake/baseaddress.cmake)
    endif()

    # For MSVC builds, this puts all debug symbols file in the same directory.
    if(MSVC)
        set(CMAKE_PDB_OUTPUT_DIRECTORY "${REACTOS_BINARY_DIR}/msvc_pdb")
    elseif(SEPARATE_DBG)
        set(CMAKE_PDB_OUTPUT_DIRECTORY "${REACTOS_BINARY_DIR}/symbols")
    endif()

