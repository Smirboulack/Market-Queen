import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// Step 3 -- the words.
//
// The model no longer writes the script: it is the one part of an ad where a
// human knows something the model does not. S4 turns this into a scene-by-scene
// editor; the beats below are already the shape that editor will take.
ColumnLayout {
    id: root

    readonly property var project: App.project

    spacing: Theme.gapLarge

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Text {
            text: qsTr("What do they say?")
            color: Theme.text
            font.pixelSize: Theme.fontHeading
            font.weight: Font.DemiBold
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Write it the way you would say it out loud. No duration to pick: the ad lasts as long as the words do.")
            color: Theme.textDim
            font.pixelSize: Theme.fontBody
            wrapMode: Text.WordWrap
        }
    }

    SectionCard {
        LabeledArea {
            id: scriptField
            placeholder: qsTr("I bought this thinking it was another gimmick...")
            areaHeight: 220
            text: root.project.script
            onTextChanged: root.project.script = text
        }

        RowLayout {
            Layout.fillWidth: true

            Text {
                //: %1 is a duration in seconds
                text: qsTr("About %1 s spoken").arg(root.project.spokenSeconds.toFixed(1))
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall
            }

            Item { Layout.fillWidth: true }

            Text {
                text: qsTr("15 to 30 s converts best")
                color: Theme.textFaint
                font.pixelSize: Theme.fontSmall
            }
        }
    }

    // Guidance, never enforcement: these are the beats that tend to work, not a
    // template the script has to fit.
    SectionCard {
        title: qsTr("If you are stuck")
        subtitle: qsTr("A structure that works for most UGC ads. Ignore it freely.")

        Repeater {
            model: [
                { beat: qsTr("Hook"),    hint: qsTr("Name the frustration in one sentence. You have three seconds.") },
                { beat: qsTr("Problem"), hint: qsTr("Make it concrete. What did you try that failed?") },
                { beat: qsTr("Product"), hint: qsTr("Introduce it as what finally worked, not as a product.") },
                { beat: qsTr("Proof"),   hint: qsTr("One specific detail. A number, a timeframe, a moment.") },
                { beat: qsTr("Ask"),     hint: qsTr("Say what to do next, casually.") }
            ]

            RowLayout {
                required property var modelData

                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.preferredWidth: 62
                    Layout.alignment: Qt.AlignTop
                    text: modelData.beat
                    color: Theme.accent
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    text: modelData.hint
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        GhostButton {
            text: qsTr("Back")
            onClicked: root.project.currentStep = 1
        }

        Item { Layout.fillWidth: true }

        PrimaryButton {
            text: qsTr("Next: review")
            enabled: root.project.stepStates[2] !== undefined
                     && root.project.stepStates[2].valid
            onClicked: root.project.currentStep = 3
        }
    }

    Connections {
        target: App.project
        function onCleared() { scriptField.text = ""; }
    }
}
