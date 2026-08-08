import QtMultimedia
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import MarketQueen

// The actor's voice, and the chance to hear it.
//
// An audition costs a fraction of a cent; the ad it saves you from re-rendering
// costs a dollar. So the order here is: pick, tune, listen, and only then move
// on. Nothing about a voice is judgeable from four numbers on a screen.
ColumnLayout {
    id: root

    readonly property var project: App.project
    readonly property var actor: project.actor

    property string auditionLine: qsTr("Honestly, I did not think this would work. Two weeks later I am still using it.")
    property var auditionCost: ({ known: false, amount: 0 })

    function setting(key, fallback) {
        return root.actor[key] !== undefined ? root.actor[key] : fallback;
    }

    function refreshCost() {
        auditionCost = App.voiceBooth.estimate(root.auditionLine);
    }

    function readSettings() {
        stability.value = setting("voiceStability", 0.45);
        similarity.value = setting("voiceSimilarity", 0.8);
        style.value = setting("voiceStyle", 0.35);
        speed.value = setting("voiceSpeed", 1.0);
        voiceBox.setValue(setting("voiceId", ""));
    }

    spacing: Theme.gap
    Layout.fillWidth: true

    Component.onCompleted: {
        refreshCost();
        readSettings();
    }

    // ---------------------------------------------------------------- pick
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

            onValueEdited: function (v) { root.project.setActorField("voiceId", v); }
        }

        GhostButton {
            Layout.alignment: Qt.AlignTop
            text: qsTr("Load voices")
            onClicked: App.loadVoices(App.settings.pref("voiceProvider", "elevenlabs"))
        }
    }

    // ---------------------------------------------------------------- tune
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Theme.gapLarge
        rowSpacing: Theme.gap

        LabeledSlider {
            id: stability
            label: qsTr("Stability")
            hint: qsTr("Low wanders and sounds alive. High is even and safe.")
            onEdited: function (v) { root.project.setActorField("voiceStability", v); }
        }

        LabeledSlider {
            id: similarity
            label: qsTr("Similarity")
            hint: qsTr("How closely it holds to the original voice.")
            onEdited: function (v) { root.project.setActorField("voiceSimilarity", v); }
        }

        LabeledSlider {
            id: style
            label: qsTr("Style")
            hint: qsTr("Pushes the delivery. Past halfway it starts acting.")
            onEdited: function (v) { root.project.setActorField("voiceStyle", v); }
        }

        LabeledSlider {
            id: speed
            label: qsTr("Speed")
            hint: qsTr("Leave at 1.00 unless the read drags.")
            from: 0.7
            to: 1.2
            value: 1.0
            onEdited: function (v) { root.project.setActorField("voiceSpeed", v); }
        }
    }

    // ------------------------------------------------------------- audition
    LabeledArea {
        id: lineField
        label: qsTr("Audition line")
        areaHeight: 56
        text: root.auditionLine
        onTextChanged: {
            root.auditionLine = text;
            root.refreshCost();
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        PrimaryButton {
            text: App.voiceBooth.auditioning ? qsTr("Recording...") : qsTr("Hear them")
            loading: App.voiceBooth.auditioning
            enabled: !App.voiceBooth.auditioning && !App.voiceBooth.cloning
            onClicked: App.voiceBooth.audition(root.actor, root.auditionLine)
        }

        GhostButton {
            text: player.playbackState === MediaPlayer.PlayingState
                  ? qsTr("Stop") : qsTr("Play again")
            visible: App.voiceBooth.samplePath !== ""
            onClicked: {
                if (player.playbackState === MediaPlayer.PlayingState)
                    player.stop();
                else
                    player.play();
            }
        }

        Text {
            text: root.auditionCost.known
                  ? Format.estimated(root.auditionCost.amount)
                  : qsTr("price unknown")
            color: Theme.textDim
            font.pixelSize: Theme.fontSmall
        }

        Item { Layout.fillWidth: true }
    }

    Text {
        Layout.fillWidth: true
        text: App.voiceBooth.error
        visible: text !== ""
        color: Theme.danger
        font.pixelSize: Theme.fontSmall
        wrapMode: Text.WordWrap
    }

    // ---------------------------------------------------------------- clone
    ColumnLayout {
        id: cloneSection

        property bool expanded: false

        Layout.fillWidth: true
        spacing: Theme.gap

        GhostButton {
            text: cloneSection.expanded
                  ? qsTr("Hide voice cloning") : qsTr("Clone a voice from a recording")
            onClicked: cloneSection.expanded = !cloneSection.expanded
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: cloneSection.expanded

            Text {
                Layout.fillWidth: true
                text: qsTr("Drop one or more clean recordings of the voice. A minute of speech is plenty.")
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: App.voiceBooth.cloneSamples

                RowLayout {
                    id: sample

                    required property string modelData
                    required property int index

                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: sample.modelData
                        color: Theme.textDim
                        font.pixelSize: Theme.fontSmall
                        elide: Text.ElideMiddle
                    }

                    GhostButton {
                        text: qsTr("Remove")
                        destructive: true
                        onClicked: App.voiceBooth.removeCloneSample(sample.index)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                GhostButton {
                    text: qsTr("Add recordings")
                    onClicked: sampleDialog.open()
                }

                LabeledField {
                    id: cloneName
                    Layout.fillWidth: true
                    placeholder: qsTr("Name for the cloned voice")
                }
            }

            // This one leaves the machine and does not come back: it uploads
            // the recordings and adds a permanent voice to the account. It says
            // so, and it is never the button you press by accident.
            Text {
                Layout.fillWidth: true
                text: qsTr("This uploads your recordings to ElevenLabs and adds a permanent voice to your account. Only clone a voice you have the right to use.")
                color: Theme.warning
                font.pixelSize: Theme.fontSmall
                wrapMode: Text.WordWrap
            }

            GhostButton {
                text: App.voiceBooth.cloning
                      ? qsTr("Cloning...") : qsTr("Clone onto my ElevenLabs account")
                enabled: !App.voiceBooth.cloning && App.voiceBooth.cloneSamples.length > 0
                onClicked: App.voiceBooth.cloneVoice(cloneName.text)
            }
        }
    }

    MediaPlayer {
        id: player
        source: App.voiceBooth.samplePath !== ""
                ? App.toFileUrl(App.voiceBooth.samplePath) : ""
        audioOutput: AudioOutput {}
    }

    FileDialog {
        id: sampleDialog
        title: qsTr("Choose voice recordings")
        fileMode: FileDialog.OpenFiles
        nameFilters: [qsTr("Audio (*.mp3 *.wav *.m4a *.ogg)")]
        onAccepted: App.voiceBooth.addCloneSamples(selectedFiles)
    }

    Connections {
        target: App.voiceBooth

        // A fresh audition plays itself: pressing "hear them" and then having to
        // press play would be one click too many.
        function onSamplePathChanged() {
            if (App.voiceBooth.samplePath !== "")
                player.play();
        }

        function onCloned(voiceId, name) {
            root.project.setActorField("voiceId", voiceId);
            voiceBox.options = [{ label: name, value: voiceId }].concat(voiceBox.options);
            voiceBox.setValue(voiceId);
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
        function onCleared() { root.readSettings(); }
        function onActorReset() { root.readSettings(); }
    }
}
