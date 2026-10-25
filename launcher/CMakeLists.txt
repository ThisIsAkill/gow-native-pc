# God of War Native PC launcher (Qt 6 Quick): installs (runtime, discs, build) and plays. Based on the Tobiichi
# Launcher by YYOzcan (GPL-3.0); see CREDITS.md.
# Build: cmake -S launcher -B launcher/build -G Ninja -DCMAKE_BUILD_TYPE=Release && ninja -C launcher/build
cmake_minimum_required(VERSION 3.21)
project(GowNativePcLauncher VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(gow-launcher WIN32
    src/main.cpp
    src/lanzador.cpp
    src/lanzador.h
    src/installer_backend.cpp
    src/installer_backend.h
    gow-launcher.rc
)

set(ARCHIVOS_QML
    qml/Main.qml
    qml/Tema.qml
    qml/Textos.js
    qml/Ascuas.qml
    qml/NavItem.qml
    qml/Fila.qml
    qml/Selector.qml
    qml/Interruptor.qml
    qml/Deslizador.qml
    qml/BotonJugar.qml
    qml/BotonSecundario.qml
    qml/CampoRuta.qml
    qml/Tecla.qml
    qml/TeclaAsignable.qml
    qml/Teclas.js
    qml/PaginaGrafico.qml
    qml/PaginaRendimiento.qml
    qml/InstallPage.qml
    qml/PaginaControles.qml
    qml/PaginaTrucos.qml
    qml/PaginaOtros.qml
)
# The QML files sit at the module root (no "qml/"), so their folder's implicit import is the module itself and
# Tema (the theme) loads as a singleton.
foreach(archivo IN LISTS ARCHIVOS_QML)
    get_filename_component(nombre "${archivo}" NAME)
    set_source_files_properties(${archivo} PROPERTIES QT_RESOURCE_ALIAS ${nombre})
endforeach()
set_source_files_properties(qml/Tema.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(gow-launcher
    URI Tobiichi
    VERSION 1.0
    RESOURCE_PREFIX /qt/qml
    QML_FILES ${ARCHIVOS_QML}
)

target_compile_definitions(gow-launcher PRIVATE TOBIICHI_VERSION="${PROJECT_VERSION}")
target_link_libraries(gow-launcher PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2)

install(TARGETS gow-launcher RUNTIME DESTINATION bin)
