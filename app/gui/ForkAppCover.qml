import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

import ForkTheme 1.0

// [fork] A cover for an app the host has no art for (it sends a placeholder), drawn like the All
// apps design's generated covers: a starry gradient with a glow, a big letter and the app's name
// along the bottom. The color is one of eight: the app's own key when it has one, else picked from
// the name (so an app keeps its color). Drawn 3:4 like box art; the header's thumbnail and the
// dialog's art use the same cover with `kind` "thumb" and "dialog" (no stars, no name).
Item {
    id: cover

    property string name: ""
    // "orange", "pink", "red", "blue", "teal", "purple", "gold" or "graphite"; empty picks one from the name
    property string colorKey: ""
    property real radius: ForkTheme.radiusTile
    // "tile" (stars, letter, name), "thumb" (letter only, 36 px at 24 %) or "dialog" (letter 28 px at 30 %)
    property string kind: "tile"
    // The name along the bottom; off where the cover is too small to read it
    property bool showName: kind === "tile"

    readonly property var keys: ["orange", "pink", "red", "blue", "teal", "purple", "gold", "graphite"]
    // top, bottom, glow
    readonly property var palettes: ({
        "orange": ["#B8541C", "#3E1606", "#F39A4E"],
        "pink": ["#B23A72", "#3A0C26", "#F07AB0"],
        "red": ["#B03A36", "#3A0E0E", "#F2786E"],
        "blue": ["#2F5FC4", "#0F1C48", "#6FA2FF"],
        "teal": ["#1E8A84", "#08303A", "#5ED6C8"],
        "purple": ["#6B45C2", "#1E0E46", "#A88BFF"],
        "gold": ["#A8792A", "#3A2608", "#F0C878"],
        "graphite": ["#5A5E6E", "#1C1E26", "#9AA0B4"]
    })
    readonly property var colors: palettes[colorKey] || palettes[hashKey(name)] || palettes.graphite
    readonly property bool fx: GraphicsInfo.api !== GraphicsInfo.Software

    // The key for an app with none: the same name always gets the same color
    function hashKey(text) {
        if (colorKey !== "") {
            return "graphite" // an unknown key falls back to graphite
        }
        var h = 0
        for (var i = 0; i < text.length; i++) {
            h = (h * 31 + text.charCodeAt(i)) % 65521
        }
        return keys[h % keys.length]
    }

    // The first letter or digit of the name, or ?
    function initial(text) {
        var letters = text.replace(/[^A-Za-z0-9]/g, "")
        return (letters.length > 0 ? letters.charAt(0) : "?").toUpperCase()
    }

    Rectangle {
        anchors.fill: parent
        radius: cover.radius
        gradient: Gradient {
            GradientStop { position: 0; color: cover.colors[0] }
            GradientStop { position: 1; color: cover.colors[1] }
        }
    }

    // The glow, an ellipse (75 % × 55 % of the cover) at 50 % 40 %, alpha 0.40 fading to 0, on a
    // 120 × 160 grid scaled to the cover. It fades out before the corners.
    Shape {
        width: 120
        height: 160
        transform: Scale { xScale: cover.width / 120; yScale: cover.height / 160 }
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: 60; centerY: 64
                focalX: 60; focalY: 64
                centerRadius: 90
                GradientStop { position: 0; color: Qt.rgba(Qt.color(cover.colors[2]).r, Qt.color(cover.colors[2]).g, Qt.color(cover.colors[2]).b, 0.4) }
                GradientStop { position: 1; color: Qt.rgba(Qt.color(cover.colors[2]).r, Qt.color(cover.colors[2]).g, Qt.color(cover.colors[2]).b, 0) }
            }
            PathSvg { path: "M0 0H120V160H0Z" }
        }
    }

    // Four sparkles and three dots (the grid stretches to the cover)
    Shape {
        visible: cover.kind === "tile"
        width: 120
        height: 160
        transform: Scale { xScale: cover.width / 120; yScale: cover.height / 160 }
        preferredRendererType: Shape.CurveRenderer

        ShapePath { fillColor: Qt.rgba(1, 1, 1, 0.7); strokeColor: "transparent"
            PathSvg { path: "M17 10L18.25 13.75L22 15L18.25 16.25L17 20L15.75 16.25L12 15L15.75 13.75Z" } }
        ShapePath { fillColor: Qt.rgba(1, 1, 1, 0.75); strokeColor: "transparent"
            PathSvg { path: "M98 4.5L99.9 10.1L105.5 12L99.9 13.9L98 19.5L96.1 13.9L90.5 12L96.1 10.1Z" } }
        ShapePath { fillColor: Qt.rgba(1, 1, 1, 0.6); strokeColor: "transparent"
            PathSvg { path: "M104 66L105 69L108 70L105 71L104 74L103 71L100 70L103 69Z" } }
        ShapePath { fillColor: Qt.rgba(1, 1, 1, 0.55); strokeColor: "transparent"
            PathSvg { path: "M14 92.5L14.9 95.1L17.5 96L14.9 96.9L14 99.5L13.1 96.9L10.5 96L13.1 95.1Z" } }
        ShapePath { fillColor: Qt.rgba(1, 1, 1, 0.6); strokeColor: "transparent"
            PathSvg { path: "M42.9 28a0.9 0.9 0 1 0 -1.8 0a0.9 0.9 0 1 0 1.8 0Z" } }
        ShapePath { fillColor: Qt.rgba(1, 1, 1, 0.5); strokeColor: "transparent"
            PathSvg { path: "M78.8 44a0.8 0.8 0 1 0 -1.6 0a0.8 0.8 0 1 0 1.6 0Z" } }
        ShapePath { fillColor: Qt.rgba(1, 1, 1, 0.5); strokeColor: "transparent"
            PathSvg { path: "M26.8 60a0.8 0.8 0 1 0 -1.6 0a0.8 0.8 0 1 0 1.6 0Z" } }
    }

    // The letter: 66 px at 24 % of a 173.333 wide tile (800 weight, -0.04em, a soft shadow)
    ForkCanvasText {
        id: letter
        readonly property real size: cover.kind === "tile" ? 66 * cover.width / 173.333 : (cover.kind === "thumb" ? 36 : 28)
        anchors.left: parent.left
        anchors.right: parent.right
        y: cover.height * (cover.kind === "dialog" ? 0.30 : 0.24) - 0.09 * size
        horizontalAlignment: Text.AlignHCenter
        text: cover.initial(cover.name)
        color: "#F5EBD3"
        px: size
        weight: 800
        tracking: -0.04 * size
        lineHeightPx: size
        height: size
        layer.enabled: cover.fx
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.28)
            shadowVerticalOffset: 6
            shadowBlur: 1.0
            blurMax: 24
        }
    }

    // The name, centered along the bottom
    ForkCanvasText {
        visible: cover.showName
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12 * cover.width / 173.333
        anchors.rightMargin: 12 * cover.width / 173.333
        anchors.bottomMargin: 16 * cover.width / 173.333
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: cover.name
        color: "#FFFFFF"
        px: 14 * cover.width / 173.333
        weight: 650
        lineHeightPx: 17 * cover.width / 173.333
        layer.enabled: cover.fx && visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.35)
            shadowVerticalOffset: 1
            shadowBlur: 0.4
            blurMax: 8
        }
    }
}
