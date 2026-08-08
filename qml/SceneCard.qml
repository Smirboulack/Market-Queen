import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// One scene: a line, how long it takes to say, and what the camera does.
//
// The line is the only field the user has to fill in. Everything else is either
// derived (the duration) or written for them (the visuals) -- and the visuals
// stay editable, because a director that cannot be overruled is a director you
// end up fighting.
Rectangle {
    id: root

    property int position: 0
    property int total: 1
    property string line: ""
    property string kind: "talking"
    property string imagePrompt: ""
    property string videoPrompt: ""
    property real seconds: 0
    property bool directed: false
    property string beatHint: ""

    signal lineEdited(string text)
    signal kindEdited(string kind)
    signal imagePromptEdited(string text)
    signal videoPromptEdited(string text)
    signal moveRequested(int to)
    signal removeRequested()

    property bool showVisual: false

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + 2 * Theme.gap
    radius: Theme.radius
    color: Theme.surface
    border.width: 1
    border.color: cardHover.hovered ? Theme.borderStrong : Theme.border

    HoverHandler { id: cardHover }

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Theme.gap
        spacing: 8

        // ------------------------------------------------------------ header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: 12
                color: Theme.accentSoft
                border.width: 1
                border.color: Theme.accent

                Text {
                    anchors.centerIn: parent
                    text: String(root.position + 1).padStart(2, "0")
                    color: Theme.accent
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.Bold
                }
            }

            SegmentedControl {
                options: [
                    { label: qsTr("Talking"), value: "talking" },
                    { label: qsTr("Product"), value: "broll" }
                ]
                value: root.kind
                onPicked: function (v) { root.kindEdited(v); }
            }

            Item { Layout.fillWidth: true }

            Text {
                //: %1 is a duration in seconds
                text: qsTr("%1 s").arg(root.seconds.toFixed(1))
                color: root.seconds > 0 ? Theme.textDim : Theme.textFaint
                font.pixelSize: Theme.fontSmall
                font.family: "monospace"
            }

            GhostButton {
                text: "↑"
                enabled: root.position > 0
                onClicked: root.moveRequested(root.position - 1)
            }

            GhostButton {
                text: "↓"
                enabled: root.position < root.total - 1
                onClicked: root.moveRequested(root.position + 1)
            }

            GhostButton {
                text: "×"
                destructive: true
                onClicked: root.removeRequested()
            }
        }

        // -------------------------------------------------------------- line
        LabeledArea {
            id: lineField
            placeholder: root.beatHint
            areaHeight: 56
            text: root.line
            onTextChanged: root.lineEdited(text)
        }

        // ------------------------------------------------------------ visual
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            GhostButton {
                text: root.showVisual ? qsTr("Hide the visual") : qsTr("Visual")
                onClicked: root.showVisual = !root.showVisual
            }

            Text {
                Layout.fillWidth: true
                text: root.directed
                      ? root.imagePrompt
                      : qsTr("Not directed yet")
                color: root.directed ? Theme.textFaint : Theme.textFaint
                font.pixelSize: Theme.fontSmall
                elide: Text.ElideRight
                visible: !root.showVisual
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: root.showVisual

            LabeledArea {
                id: imageField
                label: qsTr("What the camera sees")
                placeholder: qsTr("Press Direct the shots, or write it yourself.")
                areaHeight: 64
                text: root.imagePrompt
                onTextChanged: root.imagePromptEdited(text)
            }

            LabeledArea {
                id: videoField
                label: qsTr("How it moves")
                placeholder: qsTr("One small gesture, one small camera movement.")
                areaHeight: 52
                text: root.videoPrompt
                onTextChanged: root.videoPromptEdited(text)
            }
        }
    }

    // The model is authoritative after a reorder or a direction pass; the text
    // fields dropped their bindings the moment they were typed in.
    function resync() {
        lineField.text = root.line;
        imageField.text = root.imagePrompt;
        videoField.text = root.videoPrompt;
    }
}
