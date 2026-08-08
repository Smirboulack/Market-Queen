import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// Step 2 -- who is on camera.
//
// S2 turns this into a casting studio: generated portraits, structured traits,
// a saved library. For now it collects the same description the pipeline
// already knows how to use, so the step is real rather than a placeholder.
ColumnLayout {
    id: root

    readonly property var project: App.project

    spacing: Theme.gapLarge

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Text {
            text: qsTr("Who says it?")
            color: Theme.text
            font.pixelSize: Theme.fontHeading
            font.weight: Font.DemiBold
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("A real-looking person beats a polished one. Ordinary face, ordinary room.")
            color: Theme.textDim
            font.pixelSize: Theme.fontBody
            wrapMode: Text.WordWrap
        }
    }

    SectionCard {
        LabeledArea {
            id: briefField
            label: qsTr("The person")
            placeholder: qsTr("e.g. a woman in her thirties, tired but friendly, no makeup, messy bun")
            areaHeight: 84
            text: root.project.actor.brief !== undefined ? root.project.actor.brief : ""
            onTextChanged: root.project.setActorField("brief", text)
        }

        LabeledArea {
            id: decorField
            label: qsTr("Where they are")
            placeholder: qsTr("e.g. a small bathroom, towels on the floor, morning light through blinds")
            areaHeight: 72
            text: root.project.actor.decor !== undefined ? root.project.actor.decor : ""
            onTextChanged: root.project.setActorField("decor", text)
        }
    }

    SectionCard {
        title: qsTr("Delivery")
        subtitle: qsTr("How they speak, and in what language.")

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Theme.gap

            // Values stay English: they go into the prompt, not on screen.
            PickerWithCustom {
                id: tone

                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                label: qsTr("Tone")
                customPlaceholder: qsTr("Describe the tone in your own words")
                options: [
                    { label: qsTr("excited and casual"), value: "excited and casual" },
                    { label: qsTr("calm and honest"), value: "calm and honest" },
                    { label: qsTr("funny"), value: "funny" },
                    { label: qsTr("straight to the point"), value: "straight to the point" },
                    { label: qsTr("storytelling"), value: "storytelling" }
                ]

                Component.onCompleted: {
                    const saved = root.project.actor.tone;
                    setValue(saved !== undefined && saved !== "" ? saved : "calm and honest");
                    root.project.setActorField("tone", value);
                }

                onValueEdited: function (v) { root.project.setActorField("tone", v); }
            }

            PickerWithCustom {
                id: language

                Layout.preferredWidth: 190
                Layout.alignment: Qt.AlignTop
                label: qsTr("Language")
                customPlaceholder: qsTr("Any other language")
                options: [
                    { label: "English", value: "English" },
                    { label: "Français", value: "Français" },
                    { label: "Español", value: "Español" },
                    { label: "Deutsch", value: "Deutsch" },
                    { label: "Italiano", value: "Italiano" },
                    { label: "Português", value: "Português" },
                    { label: "Nederlands", value: "Nederlands" },
                    { label: "Polski", value: "Polski" },
                    { label: "Русский", value: "Русский" },
                    { label: "中文", value: "中文" },
                    { label: "العربية", value: "العربية" },
                    { label: "日本語", value: "日本語" }
                ]

                Component.onCompleted: {
                    const saved = root.project.actor.language;
                    setValue(saved !== undefined && saved !== ""
                             ? saved : App.translator.currentLabel);
                    root.project.setActorField("language", value);
                }

                onValueEdited: function (v) { root.project.setActorField("language", v); }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 8

            PickerWithCustom {
                id: voiceBox

                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                label: qsTr("Voice")
                options: []
                customLabel: qsTr("Other voice id...")
                customPlaceholder: qsTr("Paste a voice id")
                hint: options.length === 0
                      ? qsTr("Load the voices on your account to pick one.") : ""

                Component.onCompleted: {
                    const saved = root.project.actor.voiceId;
                    setValue(saved !== undefined ? saved : "");
                }

                onValueEdited: function (v) { root.project.setActorField("voiceId", v); }
            }

            GhostButton {
                Layout.alignment: Qt.AlignTop
                text: qsTr("Load voices")
                onClicked: App.loadVoices(App.settings.pref("voiceProvider", "elevenlabs"))
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        GhostButton {
            text: qsTr("Back")
            onClicked: root.project.currentStep = 0
        }

        Item { Layout.fillWidth: true }

        PrimaryButton {
            text: qsTr("Next: write the script")
            enabled: root.project.stepStates[1] !== undefined
                     && root.project.stepStates[1].valid
            onClicked: root.project.currentStep = 2
        }
    }

    Connections {
        target: App

        function onVoicesLoaded(providerId, voices) {
            const current = voiceBox.value;
            voiceBox.options = voices.map(function (v) {
                return {
                    label: v.description ? v.label + " - " + v.description : v.label,
                    value: v.id
                };
            });
            voiceBox.setValue(current);
            App.log.append(0, qsTr("%1 voices loaded.").arg(voices.length));
        }

        function onVoicesFailed(providerId, error) {
            App.log.append(3, qsTr("Could not load voices: %1").arg(error));
        }
    }

    Connections {
        target: App.project
        function onCleared() {
            briefField.text = "";
            decorField.text = "";
        }
    }
}
