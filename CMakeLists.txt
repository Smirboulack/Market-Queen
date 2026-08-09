cmake_minimum_required(VERSION 3.21)

project(MarketQueen
    VERSION 0.1.0
    DESCRIPTION "Open-source UGC video studio. Bring your own API keys."
    LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick QuickControls2 QuickDialogs2 Network Svg Multimedia
                                         LinguistTools)

qt_standard_project_setup(REQUIRES 6.5)

set(APP_SOURCES
    src/main.cpp
    src/core/Crypto.h            src/core/Crypto.cpp
    src/core/Paths.h             src/core/Paths.cpp
    src/core/LogModel.h          src/core/LogModel.cpp
    src/core/SettingsStore.h     src/core/SettingsStore.cpp
    src/core/Pricing.h           src/core/Pricing.cpp
    src/core/Http.h              src/core/Http.cpp
    src/i18n/Translator.h        src/i18n/Translator.cpp
    src/providers/Types.h
    src/providers/ProviderTask.h src/providers/ProviderTask.cpp
    src/providers/Registry.h     src/providers/Registry.cpp
    src/providers/TextProviders.h   src/providers/TextProviders.cpp
    src/providers/ImageProviders.h  src/providers/ImageProviders.cpp
    src/providers/VideoProviders.h  src/providers/VideoProviders.cpp
    src/providers/AvatarProviders.h src/providers/AvatarProviders.cpp
    src/providers/VoiceProviders.h  src/providers/VoiceProviders.cpp
    src/media/Ffmpeg.h           src/media/Ffmpeg.cpp
    src/pipeline/Pipeline.h      src/pipeline/Pipeline.cpp
    src/app/SceneModel.h         src/app/SceneModel.cpp
    src/app/AdProject.h          src/app/AdProject.cpp
    src/app/Casting.h            src/app/Casting.cpp
    src/app/ActorLibrary.h       src/app/ActorLibrary.cpp
    src/app/VoiceBooth.h         src/app/VoiceBooth.cpp
    src/app/Director.h           src/app/Director.cpp
    src/app/LibraryModel.h       src/app/LibraryModel.cpp
    src/app/App.h                src/app/App.cpp
)

if(WIN32)
    list(APPEND APP_SOURCES assets/app.rc)
endif()

qt_add_executable(MarketQueen WIN32 MACOSX_BUNDLE ${APP_SOURCES})

set(APP_QML_FILES
    qml/Main.qml
    qml/Theme.qml
    qml/Format.qml
    qml/SideNav.qml
    qml/StudioPage.qml
    qml/StepRail.qml
    qml/RecapPanel.qml
    qml/RecapBlock.qml
    qml/StepProduct.qml
    qml/StepScenario.qml
    qml/ActorPanel.qml
    qml/PromptBar.qml
    qml/Chip.qml
    qml/ChoiceChip.qml
    qml/SceneBubble.qml
    qml/IconButton.qml
    qml/Icon.qml
    qml/LabeledSlider.qml
    qml/Storyboard.qml
    qml/StepSummary.qml
    qml/LibraryPage.qml
    qml/SettingsPage.qml
    qml/SectionCard.qml
    qml/EstimateCard.qml
    qml/LabeledField.qml
    qml/LabeledArea.qml
    qml/PrimaryButton.qml
    qml/GhostButton.qml
    qml/StyledCombo.qml
    qml/StyledCheck.qml
    qml/SegmentedControl.qml
    qml/PickerWithCustom.qml
    qml/ModelPicker.qml
    qml/ImageDropField.qml
    qml/ImageDropGrid.qml
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

# Only the glyphs the interface actually uses are embedded: the set ships
# 3229 of them. Each is aliased to a flat icons/<name>.svg so no QML has to
# know which category a glyph came from.
set(APP_ICONS
    "assets/icons/Media/clapperboard-line.svg"
    "assets/icons/Media/movie-2-line.svg"
    "assets/icons/System/settings-3-line.svg"
    "assets/icons/Finance/shopping-bag-3-line.svg"
    "assets/icons/Document/draft-line.svg"
    "assets/icons/System/check-double-line.svg"
    "assets/icons/System/check-line.svg"
    "assets/icons/System/add-line.svg"
    "assets/icons/System/close-line.svg"
    "assets/icons/System/delete-bin-line.svg"
    "assets/icons/System/refresh-line.svg"
    "assets/icons/System/star-fill.svg"
    "assets/icons/System/star-line.svg"
    "assets/icons/System/eye-line.svg"
    "assets/icons/System/eye-off-line.svg"
    "assets/icons/Design/edit-line.svg"
    "assets/icons/Design/magic-line.svg"
    "assets/icons/Arrows/arrow-up-s-line.svg"
    "assets/icons/Arrows/arrow-down-s-line.svg"
    "assets/icons/Business/send-plane-fill.svg"
    "assets/icons/Media/image-line.svg"
    "assets/icons/Media/image-add-line.svg"
    "assets/icons/Media/mic-line.svg"
    "assets/icons/Media/play-fill.svg"
    "assets/icons/Media/pause-fill.svg"
    "assets/icons/System/loader-4-line.svg"
    "assets/icons/User & Faces/user-smile-line.svg"
    "assets/icons/User & Faces/user-add-line.svg"
    "assets/icons/User & Faces/user-voice-line.svg"
)

set_source_files_properties("assets/icons/Media/clapperboard-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/clapperboard-line.svg")
set_source_files_properties("assets/icons/Media/movie-2-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/movie-2-line.svg")
set_source_files_properties("assets/icons/System/settings-3-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/settings-3-line.svg")
set_source_files_properties("assets/icons/Finance/shopping-bag-3-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/shopping-bag-3-line.svg")
set_source_files_properties("assets/icons/Document/draft-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/draft-line.svg")
set_source_files_properties("assets/icons/System/check-double-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/check-double-line.svg")
set_source_files_properties("assets/icons/System/check-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/check-line.svg")
set_source_files_properties("assets/icons/System/add-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/add-line.svg")
set_source_files_properties("assets/icons/System/close-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/close-line.svg")
set_source_files_properties("assets/icons/System/delete-bin-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/delete-bin-line.svg")
set_source_files_properties("assets/icons/System/refresh-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/refresh-line.svg")
set_source_files_properties("assets/icons/System/star-fill.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/star-fill.svg")
set_source_files_properties("assets/icons/System/star-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/star-line.svg")
set_source_files_properties("assets/icons/System/eye-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/eye-line.svg")
set_source_files_properties("assets/icons/System/eye-off-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/eye-off-line.svg")
set_source_files_properties("assets/icons/Design/edit-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/edit-line.svg")
set_source_files_properties("assets/icons/Design/magic-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/magic-line.svg")
set_source_files_properties("assets/icons/Arrows/arrow-up-s-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/arrow-up-s-line.svg")
set_source_files_properties("assets/icons/Arrows/arrow-down-s-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/arrow-down-s-line.svg")
set_source_files_properties("assets/icons/Business/send-plane-fill.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/send-plane-fill.svg")
set_source_files_properties("assets/icons/Media/image-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/image-line.svg")
set_source_files_properties("assets/icons/Media/image-add-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/image-add-line.svg")
set_source_files_properties("assets/icons/Media/mic-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/mic-line.svg")
set_source_files_properties("assets/icons/Media/play-fill.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/play-fill.svg")
set_source_files_properties("assets/icons/Media/pause-fill.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/pause-fill.svg")
set_source_files_properties("assets/icons/System/loader-4-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/loader-4-line.svg")
set_source_files_properties("assets/icons/User & Faces/user-smile-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/user-smile-line.svg")
set_source_files_properties("assets/icons/User & Faces/user-add-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/user-add-line.svg")
set_source_files_properties("assets/icons/User & Faces/user-voice-line.svg"
    PROPERTIES QT_RESOURCE_ALIAS "icons/user-voice-line.svg")

set_source_files_properties(qml/Theme.qml qml/Format.qml
                            PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(MarketQueen
    URI MarketQueen
    VERSION 1.0
    QML_FILES ${APP_QML_FILES}
    RESOURCES
        assets/icon-full.png
        assets/icon-head.png
        resources/pricing.json
        resources/casting.json
        ${APP_ICONS}
)

# The per-directory entries are what the generated QML type registration file
# needs: it includes headers by bare name.
target_include_directories(MarketQueen PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/app
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core
    ${CMAKE_CURRENT_SOURCE_DIR}/src/i18n
    ${CMAKE_CURRENT_SOURCE_DIR}/src/media
    ${CMAKE_CURRENT_SOURCE_DIR}/src/pipeline
    ${CMAKE_CURRENT_SOURCE_DIR}/src/providers
)

target_compile_definitions(MarketQueen PRIVATE
    APP_VERSION="${PROJECT_VERSION}"
    QT_DISABLE_DEPRECATED_BEFORE=0x060000
)

target_link_libraries(MarketQueen PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::QuickDialogs2
    Qt6::Network
    Qt6::Svg
    Qt6::Multimedia
)

if(WIN32)
    # Dark title bar.
    target_link_libraries(MarketQueen PRIVATE dwmapi)
endif()

# Interface languages. The .qm files are compiled at build time and embedded
# under :/i18n/. Run `cmake --build build --target update_translations` after
# adding or changing a qsTr()/tr() string.
set(APP_LANGUAGES fr es de it pt nl pl ru zh ar)
set(APP_TS_FILES "")
foreach(lang IN LISTS APP_LANGUAGES)
    list(APPEND APP_TS_FILES ${CMAKE_CURRENT_SOURCE_DIR}/i18n/marketqueen_${lang}.ts)
endforeach()

qt_add_translations(MarketQueen
    TS_FILES ${APP_TS_FILES}
    RESOURCE_PREFIX "/i18n"
    LUPDATE_OPTIONS -no-obsolete -locations none
)

set_target_properties(MarketQueen PROPERTIES
    OUTPUT_NAME "MarketQueen"
    MACOSX_BUNDLE_BUNDLE_NAME "Market Queen"
    MACOSX_BUNDLE_GUI_IDENTIFIER "io.github.marketqueen"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
)

# A model the price list has never heard of drops out of the cost estimate
# without a word, so the two lists have to be checked against each other.
find_package(Python3 COMPONENTS Interpreter QUIET)
if(Python3_FOUND)
    enable_testing()
    add_test(NAME pricing_catalogue
             COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/check_pricing.py)
endif()

include(GNUInstallDirs)
install(TARGETS MarketQueen
    BUNDLE  DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

qt_generate_deploy_qml_app_script(
    TARGET MarketQueen
    OUTPUT_SCRIPT deploy_script
    MACOS_BUNDLE_POST_BUILD
    NO_UNSUPPORTED_PLATFORM_ERROR
)
install(SCRIPT ${deploy_script})
