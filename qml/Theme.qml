pragma Singleton

import QtQuick
import SuperInfinity

// One palette, two skins. Light is the default; the choice lives in settings so
// every window picks it up and it survives a restart.
QtObject {
    id: root

    readonly property bool dark: App.settings.darkMode

    // Surfaces
    readonly property color background: dark ? "#0B0D12" : "#F4F5F8"
    readonly property color surface: dark ? "#12151C" : "#FFFFFF"
    readonly property color surfaceAlt: dark ? "#171C26" : "#F0F2F6"
    readonly property color surfaceHover: dark ? "#1D2330" : "#E7EAF0"
    readonly property color border: dark ? "#242B3A" : "#E3E7EE"
    readonly property color borderStrong: dark ? "#323B4F" : "#C9D0DB"

    // Text
    readonly property color text: dark ? "#E9EDF6" : "#131720"
    readonly property color textDim: dark ? "#8A93A8" : "#59616F"
    readonly property color textFaint: dark ? "#5C6478" : "#8B93A1"

    // Accents. The light variants are darkened so they stay readable on white.
    readonly property color accent: dark ? "#6C5CE7" : "#5B4BD6"
    readonly property color accentHover: dark ? "#7D6EF0" : "#4A3BC4"
    readonly property color accentSoft: dark ? "#211E3D" : "#EDEAFC"
    readonly property color pink: dark ? "#FF5FA2" : "#E8437F"
    readonly property color success: dark ? "#2FD07A" : "#0E9F55"
    readonly property color warning: dark ? "#F5A623" : "#B26A00"
    readonly property color danger: dark ? "#FF5C5C" : "#D53A3A"

    // Metrics
    readonly property int radius: 10
    readonly property int radiusSmall: 6
    readonly property int gap: 12
    readonly property int gapLarge: 20
    readonly property int pagePadding: 28
    readonly property int fieldHeight: 38

    // Interaction spec, applied by every clickable in the app:
    //  - exactly one hover source per control: the control's own `hovered`,
    //    or a single HoverHandler on plain items - never two trackers on the
    //    same item;
    //  - entering hover or pressed is instant, so the item under the pointer
    //    is always the only fully lit one; only the way back to rest fades,
    //    over hoverDuration. Grouped rows (nav entries, segments, popup
    //    options, library cards) snap both ways, like native menus, so a fast
    //    sweep never tints two of them at once;
    //  - a fill and its border always change together;
    //  - TapHandlers use ReleaseWithinBounds: the handler takes the exclusive
    //    grab on press, so a click target nested inside another one can never
    //    fire both.
    readonly property int hoverDuration: 120

    readonly property int fontSmall: 11
    readonly property int fontBody: 13
    readonly property int fontTitle: 15
    readonly property int fontHeading: 22

    function levelColor(level) {
        switch (level) {
        case 1: return success;
        case 2: return warning;
        case 3: return danger;
        default: return textDim;
        }
    }

    // Tinted background for a status pill, readable in both skins.
    function tint(base) {
        return Qt.alpha(base, dark ? 0.18 : 0.12);
    }
}
