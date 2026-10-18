import QtQuick
import QtQuick.Shapes

import ForkTheme 1.0

// [fork] The screen of a PC card: a small moon scene that shows the PC's state, and a pill naming
// it (the "PC status moons" design). status is one of:
//   ready        a full moon with a breathing glow, its reflection shimmering slowly
//   streaming    the brand's crescent sending rings out, its reflection flowing like a signal
//   waking       the moon rising out of the water, its reflection lighting up
//   asleep       a silver crescent setting on the horizon, breathing; stars twinkle
//   offline      a dark new moon over a dashed horizon, still
//   checking     the moon going through its phases
//   unpaired     half a moon, the other half a dashed outline that marches
//   unsupported  a red eclipse, still
// Drawn on the design's 245 x 150 grid: the moon sits 73 pt from the right edge, the horizon at
// y 100. With Reduce Motion (ForkTheme.reduceMotion) nothing moves and each state shows a
// still frame that still reads as that state.
Rectangle {
    id: scene

    property string status: "ready"

    // One clock drives every animation, and only while the scene is shown and something moves
    readonly property bool still: status === "offline" || status === "unsupported"
    readonly property bool animate: !ForkTheme.reduceMotion && !still && visible
    property real ms: 0
    NumberAnimation on ms {
        running: scene.animate
        from: 0
        to: 3600000
        duration: 3600000
        loops: Animation.Infinite
    }

    // 0 → 1 → 0 over period, eased like the design's ease-in-out keyframes
    function wave(period, delay) {
        return 0.5 - 0.5 * Math.cos(2 * Math.PI * (ms - delay) / period)
    }
    // Where in its cycle a looping animation is, 0 to 1
    function phase(period, delay) {
        var p = ((ms - delay) % period) / period
        return p < 0 ? p + 1 : p
    }
    function easeOut(t) {
        return 1 - Math.pow(1 - Math.max(0, Math.min(1, t)), 3)
    }

    // The brand's crescent (the circle less a smaller, offset one) at any center and radius
    function crescentPath(cx, cy, r) {
        var k = r / 18
        function px(x) { return (cx + (x - 50) * k).toFixed(2) }
        function py(y) { return (cy + (y - 40) * k).toFixed(2) }
        return "M" + px(47.17) + " " + py(22.22) + "A" + r + " " + r + " 0 1 0 " + px(66.27) + " " + py(47.7) +
               "A" + (16 * k).toFixed(2) + " " + (16 * k).toFixed(2) + " 0 0 1 " + px(47.17) + " " + py(22.22) + "Z"
    }

    // Colors: the theme's, plus the scene's own sky tones
    readonly property color moon: ForkTheme.markInk
    readonly property color glow: ForkTheme.accent
    readonly property color star: ForkTheme.dark ? ForkTheme.text2 : ForkTheme.trackEdge
    readonly property color horizon: ForkTheme.dark ? "#2B3566" : "#C9CEDF"
    readonly property color silver: ForkTheme.dark ? ForkTheme.muted : ForkTheme.faint
    readonly property color newMoon: ForkTheme.dark ? "#080B17" : "#F4F5FA"

    readonly property real moonX: width - 73

    // A soft glow around the moon: rings fading outward, so it has no hard edge
    Component {
        id: glowRings
        Item {
            property color tint: scene.glow
            property real strength: 1
            Repeater {
                model: [[25.5, 0.11], [28.5, 0.07], [31.5, 0.04]]
                delegate: Rectangle {
                    required property var modelData
                    x: scene.moonX - modelData[0]
                    y: 50 - modelData[0]
                    width: modelData[0] * 2
                    height: width
                    radius: modelData[0]
                    color: parent.tint
                    opacity: modelData[1] * parent.strength
                }
            }
        }
    }
    readonly property real sx: width / 245

    readonly property string label: status === "streaming" ? qsTr("An app is running")
                                  : status === "waking" ? qsTr("Waking up…")
                                  : status === "asleep" ? qsTr("Asleep")
                                  : status === "offline" ? qsTr("Offline")
                                  : status === "checking" ? qsTr("Checking…")
                                  : status === "unpaired" ? qsTr("Pair once to stream")
                                  : status === "unsupported" ? qsTr("Needs a newer host")
                                  : qsTr("Ready to stream")

    implicitHeight: 150
    radius: 12
    clip: true
    color: status === "streaming" ? ForkTheme.tile
         : status === "waking" ? (ForkTheme.dark ? "#161C3B" : ForkTheme.bar)
         : status === "asleep" || status === "offline" ? ForkTheme.bar
         : ForkTheme.raised
    border.color: status === "streaming" ? "transparent" : ForkTheme.lineSoft

    Accessible.role: Accessible.StaticText
    Accessible.name: label

    // A star, from a list of [x, y, size, brightness, twinkle period, twinkle delay]: its x is
    // scaled across the scene's width
    Component {
        id: starDelegate
        Rectangle {
            required property var modelData
            readonly property real size: modelData[2]
            x: modelData[0] * scene.sx - size
            y: modelData[1] - size
            width: size * 2
            height: size * 2
            radius: size
            color: scene.star
            opacity: modelData[4] > 0 && scene.animate ? modelData[3] * (1 - 0.82 * scene.wave(modelData[4], modelData[5])) : modelData[3]
        }
    }

    // The horizon
    Component {
        id: horizonLine
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: scene.horizon
                strokeWidth: 1.2
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"
                startX: 16; startY: 100
                PathLine { x: scene.width - 16; y: 100 }
            }
        }
    }

    // The bars of the full reflection, from the brand mark: x from the moon, y, width, opacity
    readonly property var reflection: [[-19.5, 107, 39, 1], [-14.3, 114, 28.6, 0.82], [-18.2, 121.5, 13, 0.64],
                                       [0, 121.5, 11.7, 0.64], [-10.4, 128.5, 16.9, 0.44], [-4.5, 136, 6.5, 0.28]]

    Loader {
        anchors.fill: parent
        sourceComponent: scene.status === "streaming" ? streamingScene
                       : scene.status === "waking" ? wakingScene
                       : scene.status === "asleep" ? asleepScene
                       : scene.status === "offline" ? offlineScene
                       : scene.status === "checking" ? checkingScene
                       : scene.status === "unpaired" ? unpairedScene
                       : scene.status === "unsupported" ? unsupportedScene
                       : readyScene
    }

    // Ready: a full moon, its glow breathing, its reflection shimmering slowly
    Component {
        id: readyScene
        Item {
            Repeater { model: [[28, 22, 1.1, 1, 3600, 0], [54, 44, 0.8, 0.6, 0, 0], [86, 16, 1, 1, 3600, 1300], [118, 36, 0.8, 0.5, 0, 0], [214, 20, 0.9, 1, 3600, 2200]]; delegate: starDelegate }

            // The glow breathes: it fades and spreads, then gathers again
            Loader {
                id: readyGlow
                readonly property real w: scene.animate ? scene.wave(4800, 0) : 0.4
                anchors.fill: parent
                sourceComponent: glowRings
                opacity: Math.min(1, 1.3 - 0.8 * w)
                transform: Scale { origin.x: scene.moonX; origin.y: 50; xScale: 1 + 0.18 * readyGlow.w; yScale: 1 + 0.18 * readyGlow.w }
            }
            Rectangle {
                x: scene.moonX - 22
                y: 28
                width: 44
                height: 44
                radius: 22
                color: scene.moon
            }
            Loader { anchors.fill: parent; sourceComponent: horizonLine }
            Repeater {
                model: scene.reflection
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    x: scene.moonX + modelData[0]; y: modelData[1]; width: modelData[2]; height: 4.2; radius: 2.1; color: scene.moon
                    opacity: modelData[3] * (scene.animate ? 0.25 + 0.75 * scene.wave(3200, [0, 250, 500, 550, 750, 1000][index]) : 1)
                }
            }
        }
    }

    // Streaming: the brand's crescent sends out rings; its reflection flows like a signal
    Component {
        id: streamingScene
        Item {
            Repeater { model: [[40, 26, 1, 0.7, 0, 0], [104, 18, 0.9, 0.5, 0, 0], [222, 66, 0.8, 0.6, 0, 0]]; delegate: starDelegate }

            Repeater {
                model: [0, 1200]
                delegate: Rectangle {
                    required property var modelData
                    readonly property real p: scene.easeOut(scene.phase(2400, modelData))
                    visible: scene.animate
                    x: scene.moonX - 22
                    y: 28
                    width: 44
                    height: 44
                    radius: 22
                    color: "transparent"
                    border.width: 1.2
                    border.color: scene.moon
                    scale: 1 + 0.75 * p
                    opacity: 0.6 * (1 - p)
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    strokeWidth: 0
                    fillColor: scene.moon
                    PathSvg { path: scene.crescentPath(scene.moonX, 50, 22) }
                }
            }
            Loader { anchors.fill: parent; sourceComponent: horizonLine }
            Repeater {
                model: scene.reflection
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property real w: scene.animate ? scene.wave(1200, [0, 120, 240, 240, 360, 480][index]) : 1
                    x: scene.moonX + modelData[0]; y: modelData[1]; width: modelData[2]; height: 4.2; radius: 2.1; color: scene.moon
                    opacity: modelData[3] * (0.35 + 0.65 * w)
                    transform: Scale { origin.x: width / 2; xScale: 0.5 + 0.5 * w }
                }
            }
        }
    }

    // Waking: the moon rises out of the water and its reflection lights up as it clears
    Component {
        id: wakingScene
        Item {
            id: wakeRoot
            readonly property real p: scene.phase(3600, 0)
            // How far below its place the moon is: 50 at the start of each rise, 0 once risen
            readonly property real drop: scene.animate ? (p < 0.62 ? 50 * (1 - scene.easeOut(p / 0.62)) : 0) : 18

            Repeater { model: [[28, 22, 1, 0.7, 0, 0], [86, 16, 0.9, 0.6, 0, 0], [118, 36, 0.8, 0.45, 0, 0], [214, 20, 0.9, 0.6, 0, 0]]; delegate: starDelegate }

            // The sky: the moon is hidden below the horizon
            Item {
                width: parent.width
                height: 100
                clip: true

                Loader {
                    width: parent.width
                    height: 150
                    y: wakeRoot.drop
                    sourceComponent: glowRings
                }
                Rectangle {
                    x: scene.moonX - 22
                    y: 28 + wakeRoot.drop
                    width: 44
                    height: 44
                    radius: 22
                    color: scene.moon
                }
            }
            Loader { anchors.fill: parent; sourceComponent: horizonLine }
            Repeater {
                model: scene.reflection
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property real q: scene.phase(3600, [0, 100, 200, 200, 300, 400][index])
                    x: scene.moonX + modelData[0]; y: modelData[1]; width: modelData[2]; height: 4.2; radius: 2.1; color: scene.moon
                    opacity: modelData[3] * (scene.animate ? (q < 0.42 ? 0 : q < 0.78 ? scene.easeOut((q - 0.42) / 0.36) : 1) : 0.5)
                }
            }
        }
    }

    // Asleep: a silver crescent setting on the horizon, breathing slowly; the stars twinkle
    Component {
        id: asleepScene
        Item {
            Repeater { model: [[28, 22, 1.1, 1, 6000, 0], [54, 44, 0.8, 1, 6000, 2000], [86, 16, 1, 1, 6000, 4000], [118, 36, 0.8, 0.6, 0, 0], [140, 12, 1.1, 1, 6000, 1000], [214, 20, 0.9, 0.7, 0, 0], [226, 64, 0.8, 1, 6000, 3000]]; delegate: starDelegate }

            Item {
                width: parent.width
                height: 100
                clip: true

                Shape {
                    width: scene.width
                    height: 150
                    preferredRendererType: Shape.CurveRenderer
                    opacity: scene.animate ? 0.55 + 0.3 * scene.wave(6000, 0) : 0.7
                    ShapePath {
                        strokeColor: "transparent"
                        strokeWidth: 0
                        fillColor: scene.silver
                        PathSvg { path: scene.crescentPath(scene.moonX, 92, 18) }
                    }
                }
            }
            Loader { anchors.fill: parent; sourceComponent: horizonLine }
            Rectangle { x: scene.moonX - 14; y: 107; width: 28; height: 3.6; radius: 1.8; color: scene.silver; opacity: 0.22 }
            Rectangle { x: scene.moonX - 9; y: 114; width: 18; height: 3.6; radius: 1.8; color: scene.silver; opacity: 0.14 }
        }
    }

    // Offline: a dark new moon over a dashed horizon; nothing moves
    Component {
        id: offlineScene
        Item {
            Rectangle {
                x: scene.moonX - 22
                y: 28
                width: 44
                height: 44
                radius: 22
                color: scene.newMoon
                border.width: 1.5
                border.color: ForkTheme.lineStrong
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: ForkTheme.line
                    strokeWidth: 1.2
                    capStyle: ShapePath.RoundCap
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [2.5, 4.2]
                    fillColor: "transparent"
                    startX: 16; startY: 100
                    PathLine { x: scene.width - 16; y: 100 }
                }
            }
        }
    }

    // Checking: the moon goes through its phases, as a shadow in the scene's color sweeps across it
    Component {
        id: checkingScene
        Item {
            Repeater { model: [[40, 26, 1, 0.5, 0, 0], [104, 18, 0.9, 0.4, 0, 0]]; delegate: starDelegate }

            Rectangle {
                x: scene.moonX - 22
                y: 28
                width: 44
                height: 44
                radius: 22
                color: ForkTheme.muted
                opacity: 0.9
            }
            Rectangle {
                x: scene.moonX - 22 + (scene.animate ? -46 + 92 * scene.phase(2600, 0) : -18)
                y: 28
                width: 44
                height: 44
                radius: 22
                color: scene.color
            }
            Rectangle {
                x: scene.moonX - 22
                y: 28
                width: 44
                height: 44
                radius: 22
                color: "transparent"
                border.width: 1.2
                border.color: Qt.rgba(ForkTheme.muted.r, ForkTheme.muted.g, ForkTheme.muted.b, 0.35)
            }
            Loader { anchors.fill: parent; sourceComponent: horizonLine }
            Rectangle { x: scene.moonX - 19.5; y: 107; width: 39; height: 4.2; radius: 2.1; color: ForkTheme.muted; opacity: 0.2 }
            Rectangle { x: scene.moonX - 14.3; y: 114; width: 28.6; height: 4.2; radius: 2.1; color: ForkTheme.muted; opacity: 0.14 }
            Rectangle { x: scene.moonX - 10.4; y: 121.5; width: 16.9; height: 4.2; radius: 2.1; color: ForkTheme.muted; opacity: 0.1 }
        }
    }

    // Not paired: half a moon, the other half a dashed outline that marches until it's paired
    Component {
        id: unpairedScene
        Item {
            Repeater { model: [[28, 22, 1, 0.7, 0, 0], [86, 16, 0.9, 0.55, 0, 0], [214, 20, 0.9, 0.6, 0, 0]]; delegate: starDelegate }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    strokeWidth: 0
                    fillColor: scene.moon
                    startX: scene.moonX; startY: 28
                    PathArc { x: scene.moonX; y: 72; radiusX: 22; radiusY: 22; direction: PathArc.Counterclockwise }
                    PathLine { x: scene.moonX; y: 28 }
                }
                ShapePath {
                    strokeColor: scene.moon
                    strokeWidth: 1.5
                    capStyle: ShapePath.RoundCap
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [2, 2.4]
                    dashOffset: scene.animate ? -8.8 * scene.phase(1600, 0) : 0
                    fillColor: "transparent"
                    startX: scene.moonX; startY: 28
                    PathArc { x: scene.moonX; y: 72; radiusX: 22; radiusY: 22; direction: PathArc.Clockwise }
                }
            }
            Loader { anchors.fill: parent; sourceComponent: horizonLine }
            Rectangle { x: scene.moonX - 19.5; y: 107; width: 19.5; height: 4.2; radius: 2.1; color: scene.moon; opacity: 0.7 }
            Rectangle { x: scene.moonX - 14.3; y: 114; width: 14.3; height: 4.2; radius: 2.1; color: scene.moon; opacity: 0.5 }
            Rectangle { x: scene.moonX - 18.2; y: 121.5; width: 13; height: 4.2; radius: 2.1; color: scene.moon; opacity: 0.36 }
        }
    }

    // Needs a newer host: a red eclipse; nothing moves
    Component {
        id: unsupportedScene
        Item {
            Repeater { model: [[40, 26, 1, 0.5, 0, 0], [214, 20, 0.9, 0.45, 0, 0]]; delegate: starDelegate }

            Loader {
                anchors.fill: parent
                sourceComponent: glowRings
                onLoaded: {
                    item.tint = ForkTheme.danger
                    item.strength = 0.7
                }
            }
            Rectangle {
                x: scene.moonX - 22
                y: 28
                width: 44
                height: 44
                radius: 22
                color: ForkTheme.dangerLine
                border.width: 1.4
                border.color: ForkTheme.danger
            }
            Loader { anchors.fill: parent; sourceComponent: horizonLine }
            Rectangle { x: scene.moonX - 19.5; y: 107; width: 39; height: 4.2; radius: 2.1; color: ForkTheme.danger; opacity: 0.28 }
            Rectangle { x: scene.moonX - 14.3; y: 114; width: 28.6; height: 4.2; radius: 2.1; color: ForkTheme.danger; opacity: 0.18 }
        }
    }

    // The state's name, bottom left
    Rectangle {
        x: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        width: pillRow.implicitWidth + 20
        height: 24
        radius: 12
        color: ForkTheme.chipScrim

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6

            // Online and ready: a dot
            Rectangle {
                visible: scene.status === "ready"
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                radius: 3.5
                color: ForkTheme.ok
            }

            // Asleep or offline: a ring
            Rectangle {
                visible: scene.status === "asleep" || scene.status === "offline"
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                radius: 3.5
                color: "transparent"
                border.width: 1.5
                border.color: ForkTheme.muted
            }

            ForkSymbol {
                visible: scene.status === "streaming" || scene.status === "unpaired" || scene.status === "unsupported"
                anchors.verticalCenter: parent.verticalCenter
                symbol: scene.status === "streaming" ? "play.fill" : scene.status === "unpaired" ? "lock.fill" : "exclamationmark.triangle.fill"
                size: 10
                color: scene.status === "streaming" ? ForkTheme.ok : scene.status === "unsupported" ? ForkTheme.danger : ForkTheme.text
            }

            // Waking or checking: a small spinner
            Shape {
                visible: scene.status === "waking" || scene.status === "checking"
                anchors.verticalCenter: parent.verticalCenter
                width: 11
                height: 11
                preferredRendererType: Shape.CurveRenderer
                rotation: scene.animate ? 360 * scene.phase(900, 0) : 0

                ShapePath {
                    strokeColor: Qt.rgba(ForkTheme.muted.r, ForkTheme.muted.g, ForkTheme.muted.b, 0.4)
                    strokeWidth: 1.6
                    fillColor: "transparent"
                    startX: 5.5; startY: 1
                    PathArc { x: 5.5; y: 10; radiusX: 4.5; radiusY: 4.5 }
                    PathArc { x: 5.5; y: 1; radiusX: 4.5; radiusY: 4.5 }
                }
                ShapePath {
                    strokeColor: ForkTheme.text
                    strokeWidth: 1.6
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    startX: 5.5; startY: 1
                    PathArc { x: 10; y: 5.5; radiusX: 4.5; radiusY: 4.5 }
                }
            }

            ForkText {
                anchors.verticalCenter: parent.verticalCenter
                kind: "body"
                font.pixelSize: 12
                font.weight: Font.Medium
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 1
                wrapMode: Text.NoWrap
                text: scene.label
            }
        }
    }
}
