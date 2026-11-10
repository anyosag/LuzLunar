// [fork] The glass of the window's header and footer bars (sky-chrome.md §5.1): the sky behind the
// bar, blurred (sigma 18) and saturated 1.4x, under the bar's tint (ForkTheme.cv.barGlass). Without
// a `skySource` it paints the flat colour that recipe resolves to over the sky's top or bottom
// edge. `opaque` paints the plain bar colour instead (the first-run page's bars).
import QtQuick
import QtQuick.Effects

import ForkTheme 1.0

Item {
    id: root

    // The sky (or any item) to blur; null paints the flat resolved glass
    property Item skySource: null
    // Where this bar's top-left sits in skySource's coordinates
    property real sourceX: 0
    property real sourceY: 0
    // "top" or "bottom": which edge of the sky the flat fallback imitates
    property string edge: "top"
    property bool opaque: false

    // What the sky looks like under the bar (back-solved from the canvas's measured bar colours,
    // sky-chrome.md §5.1 and §6.1), under the tint
    readonly property color flatSky: edge === "top" ? (ForkTheme.dark ? "#050813" : "#E4E0FF")
                                                     : (ForkTheme.dark ? "#121E58" : "#FDEFE4")
    readonly property bool blurring: skySource !== null && !opaque

    clip: true

    Rectangle {
        anchors.fill: parent
        color: root.opaque ? ForkTheme.cv.bar : root.flatSky
    }

    ShaderEffectSource {
        id: capture
        visible: false
        live: root.blurring && root.visible
        sourceItem: root.blurring ? root.skySource : null
        sourceRect: Qt.rect(root.sourceX, root.sourceY, root.width, root.height)
        textureSize: Qt.size(root.width * Screen.devicePixelRatio, root.height * Screen.devicePixelRatio)
    }

    MultiEffect {
        anchors.fill: parent
        visible: root.blurring
        source: capture
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 48
        blur: 0.75
        saturation: 0.4
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.opaque
        color: ForkTheme.cv.barGlass
    }
}
