import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import SuperInfinity

Item {
    id: root

    readonly property bool busy: App.pipeline.running
    readonly property bool canGenerate: productName.text.trim() !== "" && !busy

    function buildRequest() {
        return {
            "productName": productName.text.trim(),
            "productDescription": productDescription.text.trim(),
            "audience": audience.text.trim(),
            "tone": tone.editText,
            "language": language.editText,
            "avatarBrief": avatarBrief.text.trim(),
            "extraInstructions": extraInstructions.text.trim(),
            "script": ownScript.text.trim(),
            "durationSeconds": parseInt(duration.currentValue),
            "aspectRatio": aspect.currentValue,
            "productImagePath": productPhoto.filePath,
            "useProductPhotoAsFrame": useOwnPhoto.checked,
            "textProvider": textPicker.providerId,
            "textModel": textPicker.modelId,
            "imageProvider": imagePicker.providerId,
            "imageModel": imagePicker.modelId,
            "videoProvider": videoPicker.providerId,
            "videoModel": videoPicker.modelId,
            "voiceProvider": voicePicker.providerId,
            "voiceModel": voicePicker.modelId,
            "voiceId": voiceBox.editText,
            "captionsEnabled": captions.checked,
            "captionsProvider": "openai-whisper",
            "captionsModel": "whisper-1"
        };
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // -------------------------------------------------------------- form
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 460
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: Theme.gapLarge

                Item { implicitHeight: 4 }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.pagePadding
                    Layout.rightMargin: Theme.gapLarge
                    spacing: 4

                    Text {
                        text: qsTr("Create a UGC ad")
                        color: Theme.text
                        font.pixelSize: Theme.fontHeading
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: qsTr("Script, visual, voice-over, video and subtitles. Your API keys, your files.")
                        color: Theme.textDim
                        font.pixelSize: Theme.fontBody
                    }
                }

                SectionCard {
                    Layout.leftMargin: Theme.pagePadding
                    Layout.rightMargin: Theme.gapLarge
                    step: 1
                    title: qsTr("Your product")
                    subtitle: qsTr("What are we selling, and to whom?")

                    LabeledField {
                        id: productName
                        label: qsTr("Product name")
                        placeholder: qsTr("e.g. Lumen glow serum")
                    }

                    LabeledArea {
                        id: productDescription
                        label: qsTr("What it is")
                        placeholder: qsTr("A vitamin C serum that clears dull skin in two weeks. Fragrance free, 30 ml.")
                        areaHeight: 84
                    }

                    LabeledField {
                        id: audience
                        label: qsTr("Target audience")
                        placeholder: qsTr("e.g. women 25-35 who care about clean beauty")
                    }

                    ImageDropField {
                        id: productPhoto
                    }

                    CheckBox {
                        id: useOwnPhoto
                        text: qsTr("Use my photo as the opening frame (skip image generation)")
                        enabled: productPhoto.filePath !== ""
                        font.pixelSize: Theme.fontSmall + 1

                        indicator: Rectangle {
                            width: 16
                            height: 16
                            x: 0
                            y: (useOwnPhoto.height - height) / 2
                            radius: 4
                            color: useOwnPhoto.checked ? Theme.accent : Theme.surfaceAlt
                            border.width: 1
                            border.color: useOwnPhoto.checked ? Theme.accent : Theme.border

                            Text {
                                anchors.centerIn: parent
                                text: "✓"
                                color: "white"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                visible: useOwnPhoto.checked
                            }
                        }

                        contentItem: Text {
                            text: useOwnPhoto.text
                            color: useOwnPhoto.enabled ? Theme.textDim : Theme.textFaint
                            font: useOwnPhoto.font
                            leftPadding: 24
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                SectionCard {
                    Layout.leftMargin: Theme.pagePadding
                    Layout.rightMargin: Theme.gapLarge
                    step: 2
                    title: qsTr("The ad")
                    subtitle: qsTr("How it should sound and how long it runs.")

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.gap

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 5

                            Text {
                                text: qsTr("Tone")
                                color: Theme.textDim
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }

                            StyledCombo {
                                id: tone
                                Layout.fillWidth: true
                                editable: true
                                model: [qsTr("excited and casual"), qsTr("calm and honest"),
                                        qsTr("funny"), qsTr("straight to the point"),
                                        qsTr("storytelling")]
                                Component.onCompleted: editText = model[0]
                            }
                        }

                        ColumnLayout {
                            Layout.preferredWidth: 150
                            spacing: 5

                            Text {
                                text: qsTr("Language")
                                color: Theme.textDim
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }

                            StyledCombo {
                                id: language
                                Layout.fillWidth: true
                                editable: true
                                model: ["English", "Français", "Español", "Deutsch", "Italiano",
                                        "Português", "Nederlands"]
                                // Defaults to the interface language: someone
                                // running the app in French usually wants a
                                // French ad. callLater, because assigning the
                                // model resets editText to the first entry.
                                property bool ready: false

                                Component.onCompleted: {
                                    const saved = App.settings.pref("language", "");
                                    Qt.callLater(function () {
                                        language.editText = saved !== "" ? saved
                                                                         : App.translator.currentLabel;
                                        language.ready = true;
                                    });
                                }

                                onEditTextChanged: if (ready) App.settings.setPref("language", editText)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.gap

                        ColumnLayout {
                            Layout.preferredWidth: 130
                            spacing: 5

                            Text {
                                text: qsTr("Length")
                                color: Theme.textDim
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }

                            StyledCombo {
                                id: duration
                                Layout.fillWidth: true
                                model: ["15", "20", "30", "45"]
                                currentIndex: 1
                                //: %1 is a number of seconds
                                displayText: qsTr("%1 s").arg(currentValue)
                            }
                        }

                        ColumnLayout {
                            Layout.preferredWidth: 130
                            spacing: 5

                            Text {
                                text: qsTr("Format")
                                color: Theme.textDim
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }

                            StyledCombo {
                                id: aspect
                                Layout.fillWidth: true
                                model: ["9:16", "1:1", "16:9"]
                                currentIndex: 0
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    LabeledField {
                        id: avatarBrief
                        label: qsTr("Person on camera")
                        placeholder: qsTr("e.g. woman in her late twenties, bathroom, morning light")
                    }

                    LabeledArea {
                        id: extraInstructions
                        label: qsTr("Anything else")
                        placeholder: qsTr("Mention the 20% launch discount. Do not say \"revolutionary\".")
                        areaHeight: 64
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: qsTr("Your own script (optional)")
                                color: Theme.textDim
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: qsTr("skips the writer")
                                color: Theme.textFaint
                                font.pixelSize: Theme.fontSmall
                                visible: ownScript.text.trim() !== ""
                            }
                        }

                        LabeledArea {
                            id: ownScript
                            placeholder: qsTr("Leave empty to let the model write it.")
                            areaHeight: 72
                        }
                    }
                }

                SectionCard {
                    Layout.leftMargin: Theme.pagePadding
                    Layout.rightMargin: Theme.gapLarge
                    step: 3
                    title: qsTr("Models")
                    subtitle: qsTr("Mix and match. You are billed by each provider directly.")

                    ModelPicker {
                        id: textPicker
                        category: "text"
                        label: qsTr("Script writer")
                    }

                    ModelPicker {
                        id: imagePicker
                        category: "image"
                        label: qsTr("Opening frame")
                        opacity: useOwnPhoto.checked ? 0.45 : 1.0
                        enabled: !useOwnPhoto.checked
                    }

                    ModelPicker {
                        id: videoPicker
                        category: "video"
                        label: qsTr("Video")
                    }

                    ModelPicker {
                        id: voicePicker
                        category: "voice"
                        label: qsTr("Voice")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledCombo {
                            id: voiceBox
                            Layout.fillWidth: true
                            editable: true
                            model: []

                            Component.onCompleted: editText = App.settings.pref("voiceId", "")
                            onEditTextChanged: App.settings.setPref("voiceId", editText)
                        }

                        GhostButton {
                            text: qsTr("Load voices")
                            onClicked: App.loadVoices(voicePicker.providerId)
                        }
                    }

                    CheckBox {
                        id: captions
                        text: qsTr("Burn in subtitles (uses OpenAI Whisper)")
                        font.pixelSize: Theme.fontSmall + 1

                        // Restore first, then persist: a plain binding would be
                        // overwritten by the initial unchecked state.
                        property bool ready: false

                        Component.onCompleted: {
                            checked = App.settings.pref("captions", true);
                            ready = true;
                        }

                        onCheckedChanged: if (ready) App.settings.setPref("captions", checked)

                        indicator: Rectangle {
                            width: 16
                            height: 16
                            x: 0
                            y: (captions.height - height) / 2
                            radius: 4
                            color: captions.checked ? Theme.accent : Theme.surfaceAlt
                            border.width: 1
                            border.color: captions.checked ? Theme.accent : Theme.border

                            Text {
                                anchors.centerIn: parent
                                text: "✓"
                                color: "white"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                visible: captions.checked
                            }
                        }

                        contentItem: Text {
                            text: captions.text
                            color: Theme.textDim
                            font: captions.font
                            leftPadding: 24
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Item { implicitHeight: Theme.gapLarge }
            }
        }

        // ------------------------------------------------------------- panel
        Rectangle {
            // Fixed width: the form takes whatever is left.
            Layout.preferredWidth: 340
            Layout.minimumWidth: 340
            Layout.maximumWidth: 340
            Layout.fillHeight: true
            color: Theme.surface

            Rectangle {
                width: 1
                height: parent.height
                color: Theme.border
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.gapLarge
                spacing: Theme.gap

                PrimaryButton {
                    Layout.fillWidth: true
                    text: root.busy ? qsTr("Generating...") : qsTr("Generate UGC ad")
                    loading: root.busy
                    enabled: root.canGenerate
                    onClicked: App.pipeline.start(root.buildRequest())
                }

                GhostButton {
                    Layout.fillWidth: true
                    text: qsTr("Cancel")
                    destructive: true
                    visible: root.busy
                    onClicked: App.pipeline.cancel()
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Add a product name to start.")
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontSmall
                    visible: productName.text.trim() === "" && !root.busy
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: Theme.surfaceAlt
                    visible: root.busy || App.pipeline.progress > 0

                    Rectangle {
                        width: parent.width * App.pipeline.progress
                        height: parent.height
                        radius: 2
                        color: Theme.accent

                        Behavior on width {
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }
                    }
                }

                StepList {
                    steps: App.pipeline.steps
                }

                Text {
                    Layout.fillWidth: true
                    text: App.pipeline.status
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    visible: text !== ""
                }

                // Result card
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: resultColumn.implicitHeight + 24
                    radius: Theme.radius
                    color: Theme.accentSoft
                    border.width: 1
                    border.color: Theme.accent
                    visible: !root.busy && App.pipeline.outputFile !== ""

                    ColumnLayout {
                        id: resultColumn
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        Text {
                            text: qsTr("Your ad is ready")
                            color: Theme.text
                            font.pixelSize: Theme.fontBody
                            font.weight: Font.DemiBold
                        }

                        RowLayout {
                            spacing: 8

                            GhostButton {
                                text: qsTr("Play")
                                onClicked: App.openPath(App.pipeline.outputFile)
                            }

                            GhostButton {
                                text: qsTr("Show file")
                                onClicked: App.revealPath(App.pipeline.outputFile)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: qsTr("Activity")
                        color: Theme.textDim
                        font.pixelSize: Theme.fontSmall
                        font.weight: Font.DemiBold
                    }

                    Item { Layout.fillWidth: true }

                    GhostButton {
                        text: qsTr("Clear")
                        onClicked: App.log.clear()
                    }
                }

                LogPanel {}
            }
        }
    }

    Connections {
        target: App

        function onVoicesLoaded(providerId, voices) {
            const ids = voices.map(function (v) {
                return v.description ? v.id + "  ·  " + v.label + " (" + v.description + ")"
                                     : v.id + "  ·  " + v.label;
            });
            voiceList.entries = voices;
            voiceBox.model = ids;
            App.log.append(0, qsTr("%1 voices loaded.").arg(voices.length));
        }

        function onVoicesFailed(providerId, error) {
            App.log.append(3, qsTr("Could not load voices: %1").arg(error));
        }
    }

    // Keeps the raw voice objects so the combo can map a label back to an id.
    QtObject {
        id: voiceList
        property var entries: []
    }

    // The combo shows "id · Name (traits)"; the pipeline needs the id alone.
    Connections {
        target: voiceBox

        function onActivated(index) {
            if (index >= 0 && index < voiceList.entries.length)
                voiceBox.editText = voiceList.entries[index].id;
        }
    }
}
