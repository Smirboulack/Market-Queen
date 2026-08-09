import QtQuick
import QtQuick.Controls.Basic
import MarketQueen

// A bare glyph that only exists on hover. Used for the per-scene controls, where
// a row of labelled buttons would weigh more than the line it acts on.
Rectangle {
    id: root

    property string icon: ""
    property string tip: ""
    property bool destructive: false

    signal clicked()

    implicitWidth: 26
    implicitHeight: 26
    radius: Theme.radiusSmall
    opacity: enabled ? 1.0 : 0.3
    color: hover.hovered && root.enabled ? Theme.surfaceHover : "transparent"

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: 16
        color: root.destructive && hover.hovered ? Theme.danger : Theme.textDim
    }

    ToolTip.visible: root.tip !== "" && hover.hovered
    ToolTip.text: root.tip
    ToolTip.delay: 400

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: if (root.enabled) root.clicked()
    }
}
