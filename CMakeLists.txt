cmake_minimum_required(VERSION 3.21)

project(SuperInfinity
    VERSION 0.1.0
    DESCRIPTION "Open-source UGC video studio. Bring your own API keys."
    LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick QuickControls2 QuickDialogs2 Network Svg
                                         LinguistTools)

qt_standard_project_setup(REQUIRES 6.5)

set(APP_SOURCES
    src/main.cpp
    src/core/Crypto.h            src/core/Crypto.cpp
    src/core/Paths.h             src/core/Paths.cpp
    src/core/LogModel.h          src/core/LogModel.cpp
    src/core/SettingsStore.h     src/core/SettingsStore.cpp
    src/core/Http.h              src/core/Http.cpp
    src/i18n/Translator.h        src/i18n/Translator.cpp
    src/providers/Types.h
    src/providers/ProviderTask.h src/providers/ProviderTask.cpp
    src/providers/Registry.h     src/providers/Registry.cpp
    src/providers/TextProviders.h   src/providers/TextProviders.cpp
    src/providers/ImageProviders.h  src/providers/ImageProviders.cpp
    src/providers/VideoProviders.h  src/providers/VideoProviders.cpp
    src/providers/VoiceProviders.h  src/providers/VoiceProviders.cpp
    src/media/Ffmpeg.h           src/media/Ffmpeg.cpp
    src/pipeline/Pipeline.h      src/pipeline/Pipeline.cpp
    src/app/LibraryModel.h       src/app/LibraryModel.cpp
    src/app/App.h                src/app/App.cpp
)

if(WIN32)
    list(APPEND APP_SOURCES assets/app.rc)
endif()

qt_add_executable(SuperInfinity WIN32 MACOSX_BUNDLE ${APP_SOURCES})

set(APP_QML_FILES
    qml/Main.qml
    qml/Theme.qml
    qml/SideNav.qml
    qml/CreatePage.qml
    qml/LibraryPage.qml
    qml/SettingsPage.qml
    qml/SectionCard.qml
    qml/LabeledField.qml
    qml/LabeledArea.qml
    qml/PrimaryButton.qml
    qml/GhostButton.qml
    qml/StyledCombo.qml
    qml/SegmentedControl.qml
    qml/ModelPicker.qml
    qml/ImageDropField.qml
    qml/StepList.qml
    qml/LogPanel.qml
    qml/KeyField.qml
)

# The .qml files live in qml/ but belong at the root of the QML module, so each
# one is aliased to its bare file name.
foreach(qml_file IN LISTS APP_QML_FILES)
    get_filename_component(qml_name ${qml_file} NAME)
    set_source_files_properties(${qml_file} PROPERTIES QT_RESOURCE_ALIAS ${qml_name})
endforeach()

set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(SuperInfinity
    URI SuperInfinity
    VERSION 1.0
    QML_FILES ${APP_QML_FILES}
    RESOURCES
        assets/icon-full.png
        assets/icon-head.png
)

# The per-directory entries are what the generated QML type registration file
# needs: it includes headers by bare name.
target_include_directories(SuperInfinity PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/app
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core
    ${CMAKE_CURRENT_SOURCE_DIR}/src/i18n
    ${CMAKE_CURRENT_SOURCE_DIR}/src/media
    ${CMAKE_CURRENT_SOURCE_DIR}/src/pipeline
    ${CMAKE_CURRENT_SOURCE_DIR}/src/providers
)

target_compile_definitions(SuperInfinity PRIVATE
    APP_VERSION="${PROJECT_VERSION}"
    QT_DISABLE_DEPRECATED_BEFORE=0x060000
)

target_link_libraries(SuperInfinity PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::QuickDialogs2
    Qt6::Network
    Qt6::Svg
)

if(WIN32)
    # Dark title bar.
    target_link_libraries(SuperInfinity PRIVATE dwmapi)
endif()

# Interface languages. The .qm files are compiled at build time and embedded
# under :/i18n/. Run `cmake --build build --target update_translations` after
# adding or changing a qsTr()/tr() string.
set(APP_LANGUAGES fr es de it pt nl pl ru zh ar)
set(APP_TS_FILES "")
foreach(lang IN LISTS APP_LANGUAGES)
    list(APPEND APP_TS_FILES ${CMAKE_CURRENT_SOURCE_DIR}/i18n/superinfinity_${lang}.ts)
endforeach()

qt_add_translations(SuperInfinity
    TS_FILES ${APP_TS_FILES}
    RESOURCE_PREFIX "/i18n"
    LUPDATE_OPTIONS -no-obsolete -locations none
)

set_target_properties(SuperInfinity PROPERTIES
    OUTPUT_NAME "SuperInfinity"
    MACOSX_BUNDLE_BUNDLE_NAME "Super Infinity"
    MACOSX_BUNDLE_GUI_IDENTIFIER "io.github.superinfinity"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
)

include(GNUInstallDirs)
install(TARGETS SuperInfinity
    BUNDLE  DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

qt_generate_deploy_qml_app_script(
    TARGET SuperInfinity
    OUTPUT_SCRIPT deploy_script
    MACOS_BUNDLE_POST_BUILD
    NO_UNSUPPORTED_PLATFORM_ERROR
)
install(SCRIPT ${deploy_script})
