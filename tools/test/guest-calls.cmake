# Pass as CMAKE_PROJECT_PS2RetroX_INCLUDE when configuring the runtime.
# Defer until the runtime and recompiler targets have been declared.
if(NOT TARGET ps2_runtime)
    if(GOW_GUEST_CALLS_DEFERRED)
        message(FATAL_ERROR "Guest-call tests require PS2X_BUILD_RUNTIME=ON")
    endif()
    set(GOW_GUEST_CALLS_DEFERRED TRUE)
    cmake_language(EVAL CODE "cmake_language(DEFER CALL include [[${CMAKE_CURRENT_LIST_FILE}]])")
    return()
endif()
if(NOT TARGET ps2_recomp_lib)
    message(FATAL_ERROR "Guest-call tests require PS2X_BUILD_RECOMP=ON")
endif()
add_executable(gow_guest_calls "${CMAKE_CURRENT_LIST_DIR}/guest_calls.cpp"
    "${CMAKE_SOURCE_DIR}/ps2xTest/src/test_function_table.cpp")
target_compile_features(gow_guest_calls PRIVATE cxx_std_20)
target_include_directories(gow_guest_calls PRIVATE
    "${CMAKE_SOURCE_DIR}/ps2xRuntime/include"
    "${CMAKE_SOURCE_DIR}/ps2xRecomp/include")
target_link_libraries(gow_guest_calls PRIVATE ps2_runtime ps2_recomp_lib)
add_executable(gow_codegen_tests "${CMAKE_CURRENT_LIST_DIR}/guest_codegen_tests.cpp"
    "${CMAKE_SOURCE_DIR}/ps2xTest/src/code_generator_tests.cpp"
    "${CMAKE_SOURCE_DIR}/ps2xTest/src/test_function_table.cpp")
target_compile_features(gow_codegen_tests PRIVATE cxx_std_20)
target_include_directories(gow_codegen_tests PRIVATE
    "${CMAKE_SOURCE_DIR}/ps2xTest/include"
    "${CMAKE_SOURCE_DIR}/ps2xRuntime/include"
    "${CMAKE_SOURCE_DIR}/ps2xRecomp/include")
target_link_libraries(gow_codegen_tests PRIVATE ps2_runtime ps2_recomp_lib)
# The upstream suite reads instructions.h relative to its working directory.
enable_testing()
add_executable(gow_frame_metrics "${CMAKE_CURRENT_LIST_DIR}/frame_metrics.cpp")
target_compile_features(gow_frame_metrics PRIVATE cxx_std_20)
target_include_directories(gow_frame_metrics PRIVATE "${CMAKE_SOURCE_DIR}/ps2xRuntime/include")
add_test(NAME gow_frame_metrics COMMAND gow_frame_metrics)
add_test(NAME gow_codegen_tests COMMAND gow_codegen_tests)
set_tests_properties(gow_codegen_tests PROPERTIES WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
if(MSVC)
    target_link_options(gow_guest_calls PRIVATE /STACK:8388608)
    target_link_options(gow_codegen_tests PRIVATE /STACK:8388608)
elseif(MINGW)
    target_link_options(gow_guest_calls PRIVATE -Wl,--stack,8388608)
    target_link_options(gow_codegen_tests PRIVATE -Wl,--stack,8388608)
endif()
