import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// One line, already written.
//
// At rest it is text: a number, the words, how long they take. Everything else
// -- reordering, the type, the visual, deleting -- only exists while the pointer
// is on it. A row of six always-visible buttons per scene is what made the old
// editor look like a spreadsheet.
Rectangle {
    id: root

    property int position: 0
    property int total: 1
    property string line: ""
    property string kind: "talking"
    property string imagePrompt: ""
    property real seconds: 0
    property bool directed: false

    property bool editing: false

    signal lineEdited(string text)
    signal kindToggled()
    signal moveRequested(int to)
    signal removeRequested()

    function beginEdit() {
        editing = true;
        editor.text = root.line;
        editor.forceActiveFocus();
        editor.selectAll();
    }

    function commit() {
        if (!editing)
            return;
        editing = false;
        if (editor.text.trim() !== root.line)
            root.lineEdited(editor.text.trim());
    }

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + 20
    radius: Theme.radius
    color: hover.hovered || root.editing ? Theme.surfaceAlt : "transparent"
    border.width: 1
    border.color: root.editing ? Theme.accent
                : hover.hovered ? Theme.border
                : "transparent"

    HoverHandler { id: hover }

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        // Number, or the b-roll marker: the one thing about a scene worth
        // seeing without hovering.
        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            radius: 13
            color: root.kind === "broll" ? "transparent" : Theme.accentSoft
            border.width: 1
            border.color: root.kind === "broll" ? Theme.borderStrong : Theme.accent

            Text {
                anchors.centerIn: parent
                text: root.kind === "broll" ? "▣" : String(root.position + 1).padStart(2, "0")
                color: root.kind === "broll" ? Theme.textFaint : Theme.accent
                font.pixelSize: Theme.fontSmall
                font.weight: Font.Bold
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            Text {
                Layout.fillWidth: true
                text: root.line
                visible: !root.editing
                color: Theme.text
                font.pixelSize: Theme.fontBody
                wrapMode: Text.WordWrap
            }

            TextArea {
                id: editor

                Layout.fillWidth: true
                visible: root.editing
                color: Theme.text
                font.pixelSize: Theme.fontBody
                wrapMode: TextArea.Wrap
                selectByMouse: true
                selectionColor: Theme.accent
                selectedTextColor: "white"
                background: null
                padding: 0

                Keys.onReturnPressed: function (event) {
                    if (event.modifiers & Qt.ShiftModifier) {
                        event.accepted = false;
                        return;
                    }
                    event.accepted = true;
                    root.commit();
                }
                Keys.onEscapePressed: root.editing = false
                onActiveFocusChanged: if (!activeFocus) root.commit()
            }

            Text {
                Layout.fillWidth: true
                text: root.imagePrompt
                visible: root.directed && !root.editing && hover.hovered
                color: Theme.textFaint
                font.pixelSize: Theme.fontSmall
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        Text {
            Layout.alignment: Qt.AlignTop
            //: %1 is a duration in seconds
            text: qsTr("%1 s").arg(root.seconds.toFixed(1))
            color: Theme.textFaint
            font.pixelSize: Theme.fontSmall
            font.family: "monospace"
            visible: !hover.hovered
        }

        // The controls, only while you are here.
        RowLayout {
            Layout.alignment: Qt.AlignTop
            spacing: 2
            visible: hover.hovered && !root.editing

            IconButton {
                glyph: root.kind === "broll" ? "▣" : "☺"
                tip: root.kind === "broll" ? qsTr("Product shot") : qsTr("Talking")
                onClicked: root.kindToggled()
            }

            IconButton {
                glyph: "↑"
                enabled: root.position > 0
                onClicked: root.moveRequested(root.position - 1)
            }

            IconButton {
                glyph: "↓"
                enabled: root.position < root.total - 1
                onClicked: root.moveRequested(root.position + 1)
            }

            IconButton {
                glyph: "✎"
                onClicked: root.beginEdit()
            }

            IconButton {
                glyph: "×"
                destructive: true
                onClicked: root.removeRequested()
            }
        }
    }

    TapHandler {
        enabled: !root.editing
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onDoubleTapped: root.beginEdit()
    }
}
