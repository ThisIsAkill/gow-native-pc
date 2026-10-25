# gow-native-pc installer (setup.cpp): plain Win32 + GDI+, no Qt, so the packed setup is one self-contained .exe.
# Built and packed by tools/pipeline/build.ps1 -Stages installer (which runs the package stage first).
cmake_minimum_required(VERSION 3.21)
project(GowNativePcSetup VERSION 1.0.0 LANGUAGES CXX RC)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# static CRT: the setup must start on a PC without the Visual C++ runtime
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")

# setup.manifest (asInvoker, per-monitor DPI) is merged into the exe by CMake's manifest handling
add_executable(gow-setup WIN32 setup.cpp setup.rc setup.manifest)
target_compile_definitions(gow-setup PRIVATE UNICODE _UNICODE GOW_VERSION="${PROJECT_VERSION}")
target_compile_options(gow-setup PRIVATE /W3 /O2 /utf-8)
target_link_libraries(gow-setup PRIVATE user32 gdi32 gdiplus shell32 ole32 cabinet advapi32)
