import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import SuperInfinity

ScrollView {
    id: root

    contentWidth: availableWidth
    clip: true

    ColumnLayout {
        width: root.availableWidth
        spacing: Theme.gapLarge

        Item { implicitHeight: 4 }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.pagePadding
            Layout.rightMargin: Theme.pagePadding
            spacing: 4

            Text {
                text: qsTr("Settings")
                color: Theme.text
                font.pixelSize: Theme.fontHeading
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Keys are encrypted on this machine and sent only to the provider they belong to.")
                color: Theme.textDim
                font.pixelSize: Theme.fontBody
                wrapMode: Text.WordWrap
            }
        }

        SectionCard {
            Layout.leftMargin: Theme.pagePadding
            Layout.rightMargin: Theme.pagePadding
            title: qsTr("Appearance")
            subtitle: qsTr("The interface language applies immediately, no restart.")

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap

                Text {
                    Layout.preferredWidth: 130
                    text: qsTr("Theme")
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.DemiBold
                }

                SegmentedControl {
                    options: [
                        { label: qsTr("Light"), value: false },
                        { label: qsTr("Dark"), value: true }
                    ]
                    value: App.settings.darkMode
                    onPicked: function (v) { App.settings.darkMode = v; }
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap

                Text {
                    Layout.preferredWidth: 130
                    text: qsTr("Language")
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.DemiBold
                }

                StyledCombo {
                    id: languageCombo

                    Layout.preferredWidth: 260
                    model: App.translator.languages()
                    textRole: "label"
                    valueRole: "code"

                    Component.onCompleted: currentIndex = indexOfValue(App.translator.currentLanguage)

                    onActivated: App.settings.uiLanguage = currentValue

                    // Keep the box in sync when the language is set elsewhere.
                    Connections {
                        target: App.translator
                        function onLanguageChanged() {
                            languageCombo.currentIndex =
                                languageCombo.indexOfValue(App.translator.currentLanguage);
                        }
                    }
                }

                GhostButton {
                    text: qsTr("Use system language")
                    onClicked: {
                        App.settings.uiLanguage = "";
                        App.translator.applyLanguage("");
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        SectionCard {
            Layout.leftMargin: Theme.pagePadding
            Layout.rightMargin: Theme.pagePadding
            title: qsTr("API keys")
            subtitle: qsTr("You only need the ones you actually use. An empty field means the provider is off.")

            Repeater {
                // credentialList (not credentials()) so the descriptions follow
                // a language change.
                model: App.registry.credentialList

                KeyField {
                    required property var modelData
                    credential: modelData
                }
            }
        }

        SectionCard {
            Layout.leftMargin: Theme.pagePadding
            Layout.rightMargin: Theme.pagePadding
            title: qsTr("Files")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5

                Text {
                    text: qsTr("Projects folder")
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.DemiBold
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    LabeledField {
                        id: projectsField
                        Layout.fillWidth: true
                        text: App.settings.projectsDir
                        readOnly: true
                    }

                    GhostButton {
                        text: qsTr("Change")
                        onClicked: folderDialog.open()
                    }

                    GhostButton {
                        text: qsTr("Open")
                        onClicked: App.openPath(App.settings.projectsDir)
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: qsTr("FFmpeg")
                        color: Theme.textDim
                        font.pixelSize: Theme.fontSmall
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        radius: 3
                        color: App.ffmpegPath !== "" ? Theme.success : Theme.warning
                    }

                    Text {
                        text: App.ffmpegPath !== "" ? App.ffmpegPath : qsTr("not found")
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontSmall
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    LabeledField {
                        Layout.fillWidth: true
                        placeholder: qsTr("Leave empty to use the one on your PATH")
                        Component.onCompleted: text = App.settings.ffmpegPath
                        onEditingFinished: App.settings.ffmpegPath = text
                    }

                    GhostButton {
                        text: qsTr("Locate")
                        onClicked: ffmpegDialog.open()
                    }

                    GhostButton {
                        text: qsTr("Download")
                        onClicked: App.openExternal("https://ffmpeg.org/download.html")
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("FFmpeg merges the clip, the voice-over and the subtitles into the final MP4. Without it the app still generates every piece, but cannot assemble them.")
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontSmall
                    wrapMode: Text.WordWrap
                }
            }
        }

        SectionCard {
            Layout.leftMargin: Theme.pagePadding
            Layout.rightMargin: Theme.pagePadding
            title: qsTr("About")

            Text {
                Layout.fillWidth: true
                text: qsTr("Super Infinity %1 - free and open source. There is no account and no server: every request goes straight from your machine to the provider you picked, with your key.")
                          .arg(App.version)
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall + 1
                wrapMode: Text.WordWrap
            }

            RowLayout {
                spacing: 8

                GhostButton {
                    text: qsTr("Config folder")
                    onClicked: App.openPath(App.settings.configLocation)
                }
            }
        }

        Item { implicitHeight: Theme.gapLarge }
    }

    FolderDialog {
        id: folderDialog
        title: qsTr("Choose where projects are saved")
        onAccepted: App.settings.projectsDir = App.toLocalFile(selectedFolder.toString())
    }

    FileDialog {
        id: ffmpegDialog
        title: qsTr("Locate the ffmpeg executable")
        onAccepted: App.settings.ffmpegPath = App.toLocalFile(selectedFile.toString())
    }
}
