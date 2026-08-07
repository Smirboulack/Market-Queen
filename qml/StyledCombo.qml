import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import SuperInfinity

// Fixed-choice picker. There is deliberately no inline editing: an editable
// ComboBox puts a live TextField over the control, which swallows the click and
// keeps the text cursor over the arrow. Free text lives in its own field, next
// to the combo (see PickerWithCustom).
ComboBox {
    id: control

    implicitHeight: Theme.fieldHeight
    font.pixelSize: Theme.fontBody

    // Never steal the wheel: these sit inside a scrolling form, and silently
    // changing a model on scroll is worse than not scrolling at all.
    wheelEnabled: false

    contentItem: Text {
        leftPadding: control.mirrored ? control.indicator.width + 20 : 12
        rightPadding: control.mirrored ? 12 : control.indicator.width + 20

        text: control.displayText
        color: control.enabled ? Theme.text : Theme.textFaint
        font: control.font
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
        elide: Text.ElideRight
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
        color: control.pressed || control.popup.visible ? Theme.surfaceHover : Theme.surfaceAlt
        border.width: 1
        border.color: control.activeFocus || control.popup.visible ? Theme.accent
                    : control.hovered ? Theme.borderStrong
                    : Theme.border

        Behavior on color {
            ColorAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
        }
        Behavior on border.color {
            ColorAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
        }
    }

    // Covers the whole control, arrow included: nothing on top intercepts it.
    HoverHandler {
        cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
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
            text: control.textRole ? option.modelData[control.textRole] : option.modelData
            color: option.current ? Theme.accent : Theme.text
            font.pixelSize: Theme.fontBody
            font.weight: option.current ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
            leftPadding: 12
            rightPadding: 12
        }

        background: Rectangle {
            color: option.highlighted ? Theme.surfaceHover
                 : option.current ? Theme.accentSoft
                 : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
            }
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }
    }

    popup: Popup {
        // Rendered in the scene, not as a native window: identical styling
        // everywhere, and Qt still flips it above the field when there is no
        // room below.
        popupType: Popup.Item
        y: control.height + 4
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 300)
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
