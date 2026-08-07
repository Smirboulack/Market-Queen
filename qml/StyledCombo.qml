import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import SuperInfinity

ComboBox {
    id: control

    implicitHeight: Theme.fieldHeight
    font.pixelSize: Theme.fontBody

    // Editable combos double as free-text fields for model ids the catalogue
    // does not know about yet.
    contentItem: TextField {
        // Swapped in right-to-left layouts, where the arrow sits on the left.
        leftPadding: control.mirrored ? control.indicator.width + 8 : 10
        rightPadding: control.mirrored ? 10 : control.indicator.width + 8
        text: control.editable ? control.editText : control.displayText
        readOnly: !control.editable
        color: Theme.text
        placeholderTextColor: Theme.textFaint
        font: control.font
        verticalAlignment: Text.AlignVCenter
        selectByMouse: true
        selectionColor: Theme.accent
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
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.moveTo(0, 0);
            ctx.lineTo(width, 0);
            ctx.lineTo(width / 2, height);
            ctx.closePath();
            ctx.fillStyle = control.pressed ? Theme.text : Theme.textDim;
            ctx.fill();
        }
    }

    background: Rectangle {
        radius: Theme.radiusSmall
        color: Theme.surfaceAlt
        border.width: 1
        border.color: control.activeFocus || control.popup.visible ? Theme.accent : Theme.border

        Behavior on border.color {
            ColorAnimation { duration: 120 }
        }
    }

    delegate: ItemDelegate {
        width: control.width
        height: 34
        highlighted: control.highlightedIndex === index

        contentItem: Text {
            text: control.textRole ? (Array.isArray(control.model)
                                      ? modelData[control.textRole]
                                      : model[control.textRole])
                                   : modelData
            color: highlighted ? Theme.text : Theme.textDim
            font.pixelSize: Theme.fontBody
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
            leftPadding: 10
            rightPadding: 10
        }

        background: Rectangle {
            color: highlighted ? Theme.surfaceHover : "transparent"
        }
    }

    popup: Popup {
        y: control.height + 4
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 260)
        padding: 4

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }

        background: Rectangle {
            radius: Theme.radiusSmall
            color: Theme.surface
            border.width: 1
            border.color: Theme.borderStrong
        }
    }
}
