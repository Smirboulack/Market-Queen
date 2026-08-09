import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// The one input shape this app uses now: a field that grows, a row of chips
// under it, and a send button.
//
// Everything the old panels asked for in labelled fields is either typed here or
// carried by a chip. The chips sit inside the bar rather than above it so the
// whole thing reads as one object you are addressing, which is what makes it a
// prompt bar and not a form with a border.
Rectangle {
    id: root

    property alias text: field.text
    property string placeholder: ""
    property int minHeight: 44
    property int maxHeight: 160
    property bool busy: false
    property bool canSubmit: field.text.trim() !== ""
    property string submitGlyph: "↵"
    // Chips go here.
    default property alias chips: chipRow.data

    signal submitted(string text)

    function clear() { field.text = ""; }
    function focusInput() { field.forceActiveFocus(); }

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + 20
    radius: Theme.radius
    color: Theme.surfaceAlt
    border.width: 1
    border.color: field.activeFocus ? Theme.accent
                : hover.hovered ? Theme.borderStrong
                : Theme.border

    Behavior on border.color {
        ColorAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
    }

    HoverHandler { id: hover }

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(root.minHeight,
                                             Math.min(root.maxHeight, field.implicitHeight))
            clip: true

            TextArea {
                id: field

                placeholderText: root.placeholder
                color: Theme.text
                placeholderTextColor: Theme.textFaint
                font.pixelSize: Theme.fontBody
                wrapMode: TextArea.Wrap
                selectByMouse: true
                selectionColor: Theme.accent
                selectedTextColor: "white"
                background: null
                padding: 0

                // Enter sends, Shift+Enter breaks the line. That is the contract
                // every chat input has taught people, and it is the reason this
                // needs no "add" button.
                Keys.onReturnPressed: function (event) {
                    if (event.modifiers & Qt.ShiftModifier) {
                        event.accepted = false;
                        return;
                    }
                    event.accepted = true;
                    if (root.canSubmit && !root.busy)
                        root.submitted(field.text.trim());
                }
                Keys.onEnterPressed: function (event) {
                    event.accepted = true;
                    if (root.canSubmit && !root.busy)
                        root.submitted(field.text.trim());
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            RowLayout {
                id: chipRow
                spacing: 6
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 16
                enabled: root.canSubmit && !root.busy
                opacity: enabled ? 1.0 : 0.35
                color: sendHover.hovered && enabled ? Theme.accentHover : Theme.accent

                Text {
                    anchors.centerIn: parent
                    text: root.busy ? "…" : root.submitGlyph
                    color: "white"
                    font.pixelSize: Theme.fontBody
                    font.weight: Font.Bold
                }

                HoverHandler {
                    id: sendHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: {
                        if (root.canSubmit && !root.busy)
                            root.submitted(field.text.trim());
                    }
                }
            }
        }
    }
}
