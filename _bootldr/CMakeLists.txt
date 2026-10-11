# Bootloader sources use the shared ReactOS SDK and build infrastructure.
add_subdirectory(freeldr)
add_subdirectory(rtl)

# Stage the BIOS loader and an NT 5.2 configuration for a WRK installation.
if((ARCH STREQUAL "i386" OR ARCH STREQUAL "amd64")
   AND NOT (SARCH STREQUAL "pc98" OR SARCH STREQUAL "xbox"))
    set(WRK_BOOT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/wrk")
    add_custom_target(wrkboot
        COMMAND ${CMAKE_COMMAND} -E make_directory "${WRK_BOOT_DIRECTORY}/bootsect"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_BINARY_DIR}/freeldr/freeldr/freeldr.sys"
            "${WRK_BOOT_DIRECTORY}/freeldr.sys"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "$<TARGET_FILE:rosload>" "${WRK_BOOT_DIRECTORY}/rosload.exe"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/wrk/freeldr.ini" "${WRK_BOOT_DIRECTORY}/freeldr.ini"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_BINARY_DIR}/freeldr/bootsect/dosmbr.bin"
            "${CMAKE_CURRENT_BINARY_DIR}/freeldr/bootsect/fat.bin"
            "${CMAKE_CURRENT_BINARY_DIR}/freeldr/bootsect/fat32.bin"
            "${CMAKE_CURRENT_BINARY_DIR}/freeldr/bootsect/ntfs.bin"
            "${WRK_BOOT_DIRECTORY}/bootsect"
        DEPENDS freeldr rosload dosmbr fat fat32 ntfsvbr
        COMMENT "Staging the FreeLoader BIOS binaries and WRK boot configuration"
        VERBATIM)
endif()
