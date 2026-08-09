import QtQuick
import QtQuick.Effects
import QtQuick.Window
import MarketQueen

// One icon from the Remix set, in any colour.
//
// The set ships every glyph as `fill="currentColor"`, which QtSvg does not
// resolve -- it draws them in whatever it falls back to, which is black and
// therefore invisible in the dark skin. So the shape is used as a *mask* over a
// plain rectangle of the colour we actually want: the result is exact in both
// skins and does not depend on what the renderer decided the fill was.
//
// `name` is the bare file name; the categories are flattened into icons/ by the
// resource aliases, so nothing here has to know that "close-line" lives under
// System and "play-fill" under Media.
Item {
    id: root

    property string name: ""
    property int size: 16
    property color color: Theme.textDim

    implicitWidth: size
    implicitHeight: size

    Image {
        id: glyph

        anchors.fill: parent
        source: root.name !== "" ? "icons/" + root.name + ".svg" : ""
        // SVGs rasterise at sourceSize, so it has to carry the device ratio or
        // every icon is soft on a high-DPI screen.
        sourceSize.width: root.size * Screen.devicePixelRatio
        sourceSize.height: root.size * Screen.devicePixelRatio
        smooth: true
        visible: false
        layer.enabled: true
    }

    Rectangle {
        id: paint
        anchors.fill: parent
        color: root.color
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: paint
        maskEnabled: true
        maskSource: glyph
        visible: glyph.status === Image.Ready
    }
}
