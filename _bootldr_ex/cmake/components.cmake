# Compiled source dependencies for the HAL, boot DLLs, and FreeLoader.
# This file is also consumed by the configure-only source graph validator.
set(BOOTLDR_EX_KERNEL_IMPORT_LIBRARY "" CACHE FILEPATH
    "Optional kernel import library from the matching WRK build/toolchain")
if(BOOTLDR_EX_KERNEL_IMPORT_LIBRARY)
    if(NOT EXISTS "${BOOTLDR_EX_KERNEL_IMPORT_LIBRARY}")
        message(FATAL_ERROR "Kernel import library does not exist: ${BOOTLDR_EX_KERNEL_IMPORT_LIBRARY}")
    endif()
    add_library(libntoskrnl STATIC IMPORTED GLOBAL)
    set_target_properties(libntoskrnl PROPERTIES IMPORTED_LOCATION "${BOOTLDR_EX_KERNEL_IMPORT_LIBRARY}")
else()
    generate_import_lib(libntoskrnl ntoskrnl.exe ntoskrnl/ntoskrnl.spec
                        "--version=${DLL_EXPORT_VERSION}" "")
endif()

foreach(_dependency cmlib inflib cportlib crt pseh vcruntime fast486 drivers/arbiter)
    add_subdirectory("${REACTOS_SOURCE_DIR}/sdk/lib/${_dependency}"
                     "${REACTOS_BINARY_DIR}/sdk/lib/${_dependency}")
endforeach()
if(MSVC)
    add_subdirectory("${REACTOS_SOURCE_DIR}/sdk/lib/RunTmChk" "${REACTOS_BINARY_DIR}/sdk/lib/RunTmChk")
elseif(STACK_PROTECTOR)
    add_subdirectory("${REACTOS_SOURCE_DIR}/sdk/lib/gcc_ssp" "${REACTOS_BINARY_DIR}/sdk/lib/gcc_ssp")
endif()

foreach(_component hal drivers/base/bootvid drivers/base/kdcom _bootldr/rtl
                   _bootldr/freeldr/bootsect _bootldr/freeldr/freeldr)
    add_subdirectory("${REACTOS_SOURCE_DIR}/${_component}" "${REACTOS_BINARY_DIR}/${_component}")
endforeach()

set(BOOTLDR_EX_HAL_TARGET "hal" CACHE STRING "HAL target to stage as hal.dll")
if(NOT TARGET ${BOOTLDR_EX_HAL_TARGET})
    message(FATAL_ERROR "Unknown HAL target: ${BOOTLDR_EX_HAL_TARGET}")
endif()
set(_stage "${CMAKE_BINARY_DIR}/stage/components")
add_custom_target(bootldr_components
    COMMAND ${CMAKE_COMMAND} -E make_directory "${_stage}/system32" "${_stage}/bootsect"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:${BOOTLDR_EX_HAL_TARGET}>" "${_stage}/system32/hal.dll"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:bootvid>" "${_stage}/system32/bootvid.dll"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:kdcom>" "${_stage}/system32/kdcom.dll"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_BINARY_DIR}/_bootldr/freeldr/freeldr/freeldr.sys" "${_stage}/freeldr.sys"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:rosload>" "${_stage}/rosload.exe"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${REACTOS_SOURCE_DIR}/_bootldr/wrk/freeldr.ini" "${_stage}/freeldr.ini"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_BINARY_DIR}/_bootldr/freeldr/bootsect/dosmbr.bin"
        "${CMAKE_BINARY_DIR}/_bootldr/freeldr/bootsect/fat.bin"
        "${CMAKE_BINARY_DIR}/_bootldr/freeldr/bootsect/fat32.bin"
        "${CMAKE_BINARY_DIR}/_bootldr/freeldr/bootsect/ntfs.bin"
        "${_stage}/bootsect"
    DEPENDS ${BOOTLDR_EX_HAL_TARGET} bootvid kdcom freeldr rosload dosmbr fat fat32 ntfsvbr
    COMMENT "Staging ReactOS boot components for WRK integration testing"
    VERBATIM)
