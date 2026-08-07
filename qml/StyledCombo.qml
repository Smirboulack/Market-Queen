import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import SuperInfinity

ComboBox {
    id: control

    implicitHeight: Theme.fieldHeight
    font.pixelSize: Theme.fontBody

    // Never steal the wheel: these sit inside a scrolling form, and silently
    // changing a model on scroll is worse than not scrolling at all.
    wheelEnabled: false

    // Editable combos double as free-text fields for model ids the catalogue
    // does not know about yet. ComboBox needs a real TextField here to drive
    // editing, but a live TextField also eats the click that should open the
    // popup -- so it is disabled (not hidden) when we are only displaying.
    contentItem: TextField {
        enabled: control.editable
        readOnly: !control.editable

        leftPadding: control.mirrored ? control.indicator.width + 8 : 10
        rightPadding: control.mirrored ? 10 : control.indicator.width + 8

        text: control.editable ? control.editText : control.displayText
        color: Theme.text
        placeholderTextColor: Theme.textFaint
        font: control.font
        verticalAlignment: Text.AlignVCenter
        selectByMouse: true
        selectionColor: Theme.accent
        selectedTextColor: "white"
        background: null

        onTextChanged: if (control.editable) control.editText = text
    }

    indicator: Canvas {
        // Anchors, not x: LayoutMirroring flips them for us.
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 10
        height: 6
        contextType: "2d"

        Connections {
            target: control
            function onPressedChanged() { control.indicator.requestPaint(); }
            function onHoveredChanged() { control.indicator.requestPaint(); }
        }

        Connections {
            target: Theme
            function onDarkChanged() { control.indicator.requestPaint(); }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.moveTo(0, 0);
            ctx.lineTo(width, 0);
            ctx.lineTo(width / 2, height);
            ctx.closePath();
            ctx.fillStyle = control.pressed || control.hovered ? Theme.text : Theme.textDim;
            ctx.fill();
        }
    }

    background: Rectangle {
        radius: Theme.radiusSmall
        color: Theme.surfaceAlt
        border.width: 1
        border.color: control.activeFocus || control.popup.visible ? Theme.accent
                    : control.hovered ? Theme.borderStrong
                    : Theme.border

        Behavior on border.color {
            ColorAnimation { duration: 120 }
        }
    }

    // The whole control is clickable, including the text area.
    HoverHandler {
        cursorShape: Qt.PointingHandCursor
        enabled: !control.editable
    }

    delegate: ItemDelegate {
        id: option

        required property var modelData
        required property int index

        readonly property bool current: control.currentIndex === index

        width: ListView.view.width
        height: 34
        highlighted: control.highlightedIndex === index

        contentItem: Text {
            text: control.textRole
                  ? (Array.isArray(control.model) ? option.modelData[control.textRole]
                                                  : option.modelData[control.textRole])
                  : option.modelData
            color: option.current ? Theme.accent : Theme.text
            font.pixelSize: Theme.fontBody
            font.weight: option.current ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
            leftPadding: 10
            rightPadding: 10
        }

        background: Rectangle {
            color: option.highlighted ? Theme.surfaceHover
                 : option.current ? Theme.accentSoft
                 : "transparent"
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }
    }

    popup: Popup {
        popupType: Popup.Item
        y: control.height + 4
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 280)
        padding: 4

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded

                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: 2
                    color: Theme.borderStrong
                }
            }
        }

        background: Rectangle {
            radius: Theme.radiusSmall
            color: Theme.surface
            border.width: 1
            border.color: Theme.borderStrong
        }
    }
}
