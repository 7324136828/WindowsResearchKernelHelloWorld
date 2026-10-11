include_guard(GLOBAL)

# Host tools are passed explicitly so this data build works both in the native
# tool build and in the ReactOS cross build with its native-* imported targets.
function(bootldr_ex_add_data mkhive_target txt2nls_target utf16le_target)
    foreach(_tool IN ITEMS "${mkhive_target}" "${txt2nls_target}" "${utf16le_target}")
        if(NOT TARGET "${_tool}")
            message(FATAL_ERROR "bootldr_ex_add_data: missing host tool target ${_tool}")
        endif()
    endforeach()

    set(BOOTLDR_EX_REGISTRY_INF_FILES
        "boot/bootdata/hivecls.inf;boot/bootdata/hivedef.inf;boot/bootdata/hivesft.inf;boot/bootdata/hivesys.inf"
        CACHE STRING "Semicolon-separated registry INF inputs, relative to the bundle root or absolute")
    set(BOOTLDR_EX_EXTRA_REGISTRY_INF_FILES "" CACHE STRING
        "Semicolon-separated additional registry INF inputs, applied after the core inputs")

    set(_inf_dir "${REACTOS_BINARY_DIR}/data/inf")
    set(_hive_dir "${REACTOS_BINARY_DIR}/stage/reactos-hives")
    set(_nls_dir "${REACTOS_BINARY_DIR}/stage/nls")
    set(_registry_inputs ${BOOTLDR_EX_REGISTRY_INF_FILES} ${BOOTLDR_EX_EXTRA_REGISTRY_INF_FILES})
    if(NOT _registry_inputs)
        message(FATAL_ERROR "At least one BOOTLDR_EX_REGISTRY_INF_FILES input is required")
    endif()

    # Convert each input separately. Hashing the full path also permits distinct
    # extra files with the same basename (e.g. driver registry fragments).
    set(_converted_registry)
    foreach(_inf IN LISTS _registry_inputs)
        if(NOT IS_ABSOLUTE "${_inf}")
            set(_inf "${REACTOS_SOURCE_DIR}/${_inf}")
        endif()
        get_filename_component(_inf "${_inf}" ABSOLUTE)
        if(NOT EXISTS "${_inf}")
            message(FATAL_ERROR "Registry INF input does not exist: ${_inf}")
        endif()
        get_filename_component(_inf_name "${_inf}" NAME_WE)
        string(SHA1 _inf_id "${_inf}")
        string(SUBSTRING "${_inf_id}" 0 12 _inf_id)
        set(_converted "${_inf_dir}/${_inf_name}-${_inf_id}.inf")
        if(NOT _converted IN_LIST _converted_registry)
            add_custom_command(
                OUTPUT "${_converted}"
                COMMAND "${CMAKE_COMMAND}" -E make_directory "${_inf_dir}"
                COMMAND "$<TARGET_FILE:${utf16le_target}>" "${_inf}" "${_converted}"
                DEPENDS ${utf16le_target} "${_inf}"
                COMMENT "Converting registry input ${_inf_name} to UTF-16LE"
                VERBATIM)
            list(APPEND _converted_registry "${_converted}")
        endif()
    endforeach()

    foreach(_special_inf IN ITEMS setupreg hivebcd)
        set(_source "${REACTOS_SOURCE_DIR}/boot/bootdata/${_special_inf}.inf")
        set(_converted "${_inf_dir}/${_special_inf}.inf")
        if(NOT EXISTS "${_source}")
            message(FATAL_ERROR "Registry INF input does not exist: ${_source}")
        endif()
        add_custom_command(
            OUTPUT "${_converted}"
            COMMAND "${CMAKE_COMMAND}" -E make_directory "${_inf_dir}"
            COMMAND "$<TARGET_FILE:${utf16le_target}>" "${_source}" "${_converted}"
            DEPENDS ${utf16le_target} "${_source}"
            COMMENT "Converting ${_special_inf}.inf to UTF-16LE"
            VERBATIM)
    endforeach()

    set(_system_hives)
    foreach(_hive IN ITEMS SYSTEM SOFTWARE DEFAULT SAM SECURITY)
        list(APPEND _system_hives "${_hive_dir}/${_hive}")
    endforeach()

    # These are example ReactOS hives, built from the selected INF seeds. They
    # are staged separately from WRK runtime modules and are not an installed
    # Windows registry or a replacement for its account/security database.
    add_custom_command(
        OUTPUT ${_system_hives}
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${_hive_dir}"
        COMMAND "$<TARGET_FILE:${mkhive_target}>"
            "-h:SYSTEM,SOFTWARE,DEFAULT,SAM,SECURITY" -u "-d:${_hive_dir}"
            ${_converted_registry}
        DEPENDS ${mkhive_target} ${_converted_registry}
        COMMENT "Generating example ReactOS SYSTEM and companion hives"
        VERBATIM)
    add_custom_command(
        OUTPUT "${_hive_dir}/SETUPREG.HIV"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${_hive_dir}"
        COMMAND "$<TARGET_FILE:${mkhive_target}>" -h:SETUPREG -u "-d:${_hive_dir}"
            ${_converted_registry} "${_inf_dir}/setupreg.inf"
        DEPENDS ${mkhive_target} ${_converted_registry} "${_inf_dir}/setupreg.inf"
        COMMENT "Generating example ReactOS setup hive"
        VERBATIM)
    add_custom_command(
        OUTPUT "${_hive_dir}/BCD"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${_hive_dir}"
        COMMAND "$<TARGET_FILE:${mkhive_target}>" -h:BCD -u "-d:${_hive_dir}"
            "${_inf_dir}/hivebcd.inf"
        DEPENDS ${mkhive_target} "${_inf_dir}/hivebcd.inf"
        COMMENT "Generating example ReactOS BCD hive"
        VERBATIM)
    add_custom_target(bootldr_hives
        DEPENDS ${_system_hives} "${_hive_dir}/SETUPREG.HIV" "${_hive_dir}/BCD")

    # The current ReactOS NLS build uses txt2nls with these bundled mappings.
    # l_intl.nls and the other manually generated tables are copied below.
    file(GLOB _codepage_sources CONFIGURE_DEPENDS
        "${REACTOS_SOURCE_DIR}/media/nls/src/c_*.txt")
    file(GLOB _binary_tables CONFIGURE_DEPENDS
        "${REACTOS_SOURCE_DIR}/media/nls/*.nls")
    if(NOT _codepage_sources OR NOT _binary_tables)
        message(FATAL_ERROR "The bundle is missing media/nls codepage inputs or binary NLS tables")
    endif()

    set(_nls_outputs)
    foreach(_source IN LISTS _codepage_sources)
        get_filename_component(_name "${_source}" NAME_WE)
        set(_output "${_nls_dir}/${_name}.nls")
        add_custom_command(
            OUTPUT "${_output}"
            COMMAND "${CMAKE_COMMAND}" -E make_directory "${_nls_dir}"
            COMMAND "$<TARGET_FILE:${txt2nls_target}>" "${_source}" "${_output}"
            DEPENDS ${txt2nls_target} "${_source}"
            COMMENT "Generating ${_name}.nls"
            VERBATIM)
        list(APPEND _nls_outputs "${_output}")
    endforeach()
    foreach(_source IN LISTS _binary_tables)
        get_filename_component(_name "${_source}" NAME)
        set(_output "${_nls_dir}/${_name}")
        if(_output IN_LIST _nls_outputs)
            message(FATAL_ERROR "NLS table has both generated and binary inputs: ${_name}")
        endif()
        add_custom_command(
            OUTPUT "${_output}"
            COMMAND "${CMAKE_COMMAND}" -E make_directory "${_nls_dir}"
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${_source}" "${_output}"
            DEPENDS "${_source}"
            COMMENT "Staging ${_name}"
            VERBATIM)
        list(APPEND _nls_outputs "${_output}")
    endforeach()
    foreach(_required IN ITEMS c_1252.nls c_437.nls l_intl.nls)
        set(_required_path "${_nls_dir}/${_required}")
        if(NOT _required_path IN_LIST _nls_outputs)
            message(FATAL_ERROR "The bundle is missing boot NLS table ${_required}")
        endif()
    endforeach()

    add_custom_target(bootldr_nls DEPENDS ${_nls_outputs})
    add_custom_target(bootldr_data)
    add_dependencies(bootldr_data bootldr_hives bootldr_nls)
endfunction()
