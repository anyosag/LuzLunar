import QtQuick
import QtQuick.Shapes

import ForkTheme 1.0
import SfSymbols 1.0

// [fork] A cover for an app the host has no art for (it sends a placeholder), drawn like Apollo's
// own covers: a starry gradient with a glow, a big letter (a display for the Desktop) and the
// app's name along the bottom. Its color is one of eight, picked from the name, so an app keeps
// its color. Meant to be drawn 3:4, like box art.
Item {
    id: cover

    property string name: ""
    property real radius: ForkTheme.radiusTile
    // The name along the bottom; off where the cover is too small to read it
    property bool showName: true

    // Each color's top, bottom and glow (the design's covers)
    readonly property var palettes: [
        ["#B8541C", "#3E1606", "#F39A4E"],  // orange
        ["#B23A72", "#3A0C26", "#F07AB0"],  // pink
        ["#B03A36", "#3A0E0E", "#F2786E"],  // red
        ["#2F5FC4", "#0F1C48", "#6FA2FF"],  // blue
        ["#1E8A84", "#08303A", "#5ED6C8"],  // teal
        ["#6B45C2", "#1E0E46", "#A88BFF"],  // purple
        ["#A8792A", "#3A2608", "#F0C878"],  // gold
        ["#5A5E6E", "#1C1E26", "#9AA0B4"]   // graphite
    ]
    readonly property var colors: palettes[colorIndex(name)]
    readonly property bool desktop: name === "Desktop" && SfSymbols.available

    function colorIndex(text) {
        var h = 0
        for (var i = 0; i < text.length; i++) {
            h = (h * 31 + text.charCodeAt(i)) % 65521
        }
        return h % palettes.length
    }

    // The first letter or digit of the name
    function initial(text) {
        var letters = text.replace(/[^A-Za-z0-9]/g, "")
        return (letters.length > 0 ? letters.charAt(0) : text.charAt(0)).toUpperCase()
    }

    Rectangle {
        anchors.fill: parent
        radius: cover.radius
        gradient: Gradient {
            GradientStop { position: 0; color: cover.colors[0] }
            GradientStop { position: 1; color: cover.colors[1] }
        }
    }

    // The glow and the stars, on a 120 × 160 grid scaled to the cover. The glow fades out before
    // the corners, so the grid's square corners never show past the cover's round ones.
    Shape {
        width: 120
        height: 160
        scale: cover.width / 120
        transformOrigin: Item.TopLeft

        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: 60
                centerY: 66
                centerRadius: 88
                focalX: 60
                focalY: 66
                GradientStop { position: 0; color: "#59" + cover.colors[2].substring(1) }
                GradientStop { position: 1; color: "#00" + cover.colors[2].substring(1) }
            }
            startX: 0
            startY: 0
            PathLine { x: 120; y: 0 }
            PathLine { x: 120; y: 160 }
            PathLine { x: 0; y: 160 }
            PathLine { x: 0; y: 0 }
        }

        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: "#B3FFFFFF"
            PathSvg {
                path: "M17 10L18.25 13.75L22 15L18.25 16.25L17 20L15.75 16.25L12 15L15.75 13.75Z " +
                      "M82 10.5L83.9 16.1L89.5 18L83.9 19.9L82 25.5L80.1 19.9L74.5 18L80.1 16.1Z " +
                      "M104 66L105 69L108 70L105 71L104 74L103 71L100 70L103 69Z " +
                      "M14 92.5L14.9 95.1L17.5 96L14.9 96.9L14 99.5L13.1 96.9L10.5 96L13.1 95.1Z"
            }
        }
    }

    Text {
        visible: !cover.desktop
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.2)
        text: cover.initial(cover.name)
        textFormat: Text.PlainText
        font.family: ForkTheme.uiFamily
        font.pixelSize: Math.max(12, Math.round(cover.width * 0.4))
        font.weight: Font.Black
        color: "#F5EBD3"
    }

    ForkSymbol {
        visible: cover.desktop
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.24)
        symbol: "display"
        size: Math.max(12, Math.round(cover.width * 0.36))
        color: "#F5EBD3"
    }

    Text {
        visible: cover.showName
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Math.round(cover.width * 0.07)
        anchors.rightMargin: anchors.leftMargin
        anchors.bottomMargin: Math.round(cover.width * 0.09)
        horizontalAlignment: Text.AlignHCenter
        text: cover.name
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        font.family: ForkTheme.uiFamily
        font.pixelSize: Math.max(11, Math.round(cover.width * 0.082))
        font.weight: Font.DemiBold
        color: "#FFFFFF"
    }
}
