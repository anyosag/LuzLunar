import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import ForkTheme 1.0

// [fork] The "Add a PC" card of Your PCs (the canvas's Main board): a dashed card with a plus disc
// and a small grey moon that sleeps with z's drifting up, and now and then wakes, blinks, looks at the
// plus and sends out a ring. Presentational: signals for the plus and the setup guide.
Item {
    id: card

    property bool focused: true
    // The first-open entrance (the art scales in): see ForkPcCard
    property bool settled: true
    property bool revealed: true
    property bool autoEntrance: false
    property int sharedTick: -1
    property bool motion: true
    // The moon's wake-up timeline. Runs by itself unless the page drives awake, blink and glance
    property bool ownTimeline: true
    property bool awake: false
    property bool blink: false
    property bool glance: false

    readonly property alias hovered: cardHover.hovered

    signal addClicked()
    signal guideClicked()
    // A click while the card isn't focused
    signal picked()

    readonly property bool dark: ForkTheme.dark
    readonly property bool animating: motion && visible && !ForkTheme.reduceMotion && width > 0
    readonly property int tick: animating ? (sharedTick >= 0 ? sharedTick : ownClock.tick) : 0
    readonly property int ph: tick % 2

    // The greys (card.md 4.4)
    readonly property color gFill: dark ? "#E8E8EC" : "#A6A6AE"
    readonly property color gCheek: dark ? "#B4B4BC" : "#8A8A92"
    readonly property color gStar: dark ? "#C7C7CC" : "#8E8E96"
    readonly property color gSparkA: dark ? "#FFFFFF" : "#6E6E76"
    readonly property color gSparkB: dark ? "#D1D1D6" : "#A6A6AE"
    readonly property color gGlowOn: dark ? Qt.rgba(1, 1, 1, 0.42) : Qt.rgba(0, 0, 0, 0.18)
    readonly property color gGlowOff: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color gRing: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.35)

    width: 560
    height: 540
    implicitWidth: 560
    implicitHeight: 540

    Accessible.role: Accessible.Pane
    Accessible.name: "Add a PC"

    ForkCardClock {
        id: ownClock
        running: card.animating && card.sharedTick < 0
    }

    // The wake-up timeline: each wait is measured from the previous step
    Timer {
        id: timeline
        property int step: 0
        readonly property var steps: [[6500, "awake", true], [1000, "blink", true], [140, "blink", false],
                                      [650, "glance", true], [900, "glance", false], [450, "awake", false]]
        interval: steps[step][0]
        repeat: true
        running: card.ownTimeline && card.animating
        onTriggered: {
            card[steps[step][1]] = steps[step][2]
            step = (step + 1) % steps.length
        }
    }
    onAnimatingChanged: if (!animating && ownTimeline) { awake = false; blink = false; glance = false; timeline.step = 0 }

    Timer { id: settleTimer; interval: 120; onTriggered: card.settled = true }
    Timer { id: revealTimer; interval: 1600; onTriggered: card.revealed = true }
    Component.onCompleted: {
        if (autoEntrance && !ForkTheme.reduceMotion) {
            settled = false
            revealed = false
            settleTimer.start()
            revealTimer.start()
        }
    }

    // ---- shadow and the dashed border
    RectangularShadow {
        anchors.fill: face
        radius: 24
        offset.y: !card.focused ? 18 : (card.hovered ? 36 : 26)
        blur: !card.focused ? 44 : (card.hovered ? 80 : 60)
        color: card.dark ? Qt.rgba(0, 0, 0, !card.focused ? 0.45 : (card.hovered ? 0.7 : 0.6))
                         : Qt.rgba(24 / 255, 26 / 255, 46 / 255, !card.focused ? 0.10 : (card.hovered ? 0.26 : 0.18))
        Behavior on offset.y { NumberAnimation { duration: 300 } }
        Behavior on blur { NumberAnimation { duration: 300 } }
    }
    Rectangle {
        id: face
        anchors.fill: parent
        radius: 24
        color: ForkTheme.cv.surface
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.GeometryRenderer
        ShapePath {
            strokeColor: card.focused ? ForkTheme.cv.muted : ForkTheme.cv.lineStrong
            strokeWidth: 1
            fillColor: "transparent"
            strokeStyle: ShapePath.DashLine
            dashPattern: [2.5, 2.5]
            PathSvg { path: "M 24 0.5 L 536 0.5 A 23.5 23.5 0 0 1 559.5 24 L 559.5 516 A 23.5 23.5 0 0 1 536 539.5 L 24 539.5 A 23.5 23.5 0 0 1 0.5 516 L 0.5 24 A 23.5 23.5 0 0 1 24 0.5 Z" }
        }
    }

    HoverHandler {
        id: cardHover
        enabled: card.focused
    }

    // ---- content, centered
    Item {
        id: inner
        anchors.fill: parent
        enabled: card.focused

        Column {
            anchors.centerIn: parent
            spacing: 6

            // The art box
            Item {
                id: art
                width: 200; height: 168
                anchors.horizontalCenter: parent.horizontalCenter

                readonly property bool shown: card.settled || card.revealed
                opacity: shown ? 1 : 0
                scale: shown ? 1 : 0.88
                Behavior on opacity {
                    enabled: !card.revealed
                    SequentialAnimation {
                        PauseAnimation { duration: card.focused ? 80 : 0 }
                        NumberAnimation { duration: 400; easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] }
                    }
                }
                Behavior on scale {
                    enabled: !card.revealed
                    SequentialAnimation {
                        PauseAnimation { duration: card.focused ? 80 : 0 }
                        NumberAnimation { duration: 560; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 1.3, 0.4, 1, 1, 1] }
                    }
                }

                // Stars
                Repeater {
                    model: [[10, 30, 3, 0], [4, 104, 2, 1], [186, 96, 3, 1], [158, 152, 2, 0], [36, 158, 2, 0]]
                    delegate: Rectangle {
                        required property var modelData
                        x: modelData[0]; y: modelData[1]
                        width: modelData[2]; height: modelData[2]; radius: modelData[2] / 2
                        color: card.gStar
                        opacity: (modelData[3] === 0) === (card.ph === 1) ? 0.75 : 0.3
                        Behavior on opacity { NumberAnimation { duration: 1100; easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] } }
                    }
                }

                // The ripple: hidden under the plus while the moon sleeps
                Rectangle {
                    x: 40; y: 24; width: 120; height: 120; radius: 60
                    color: "transparent"
                    border.width: 2
                    border.color: card.gRing
                    scale: card.awake ? 1.38 : 1
                    opacity: card.awake ? 0 : 0.9
                    Behavior on scale { enabled: card.awake; NumberAnimation { duration: 1300; easing.type: Easing.OutQuad } }
                    Behavior on opacity { NumberAnimation { duration: card.awake ? 1300 : 600; easing.type: card.awake ? Easing.OutQuad : Easing.InOutQuad } }
                }

                // The plus disc
                Item {
                    id: plus
                    x: 40; y: 24; width: 120; height: 120
                    scale: card.focused && card.hovered ? 1.05 : 1
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 1.3, 0.4, 1, 1, 1] } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Add a PC"
                    Accessible.onPressAction: card.addClicked()

                    RectangularShadow {
                        anchors.fill: disc
                        radius: 60
                        offset.y: card.dark ? 14 : 12
                        blur: card.dark ? 34 : 28
                        color: card.dark ? Qt.rgba(0, 0, 0, 0.5) : Qt.rgba(20 / 255, 22 / 255, 40 / 255, 0.22)
                    }
                    Rectangle {
                        id: disc
                        anchors.fill: parent
                        radius: 60
                        color: card.dark ? "#E8E8EC" : "#1D1D1F"
                    }
                    // The inset white highlight along the top edge (dark only)
                    Shape {
                        visible: card.dark
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        // a 1 px crescent: the circle minus itself moved 1 px down
                        ShapePath {
                            strokeColor: "transparent"; strokeWidth: 0; fillColor: Qt.rgba(1, 1, 1, 0.7)
                            PathSvg { path: "M 0.002 60.5 A 60 60 0 1 1 119.998 60.5 A 60 60 0 0 0 0.002 60.5 Z" }
                        }
                    }
                    ForkPathIcon {
                        anchors.centerIn: parent
                        name: "plus"
                        size: 48
                        color: card.dark ? "#111114" : "#FFFFFF"
                        strokeWidth: 2.2
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: card.addClicked() }
                }

                // The moon, beside the plus
                Item {
                    id: moonWrap
                    x: 123
                    y: card.awake ? -15 : -11
                    width: 72; height: 72
                    Behavior on y { NumberAnimation { duration: 900; easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] } }
                    rotation: card.awake ? 0 : -18
                    Behavior on rotation { NumberAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
                    transform: Translate {
                        y: card.awake ? 0 : (card.ph ? 2 : -1)
                        Behavior on y { NumberAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
                    }

                    Item {
                        id: moonArt
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true

                        // 0.81 px per unit, origin at the center
                        Item {
                            x: 36; y: 36
                            scale: 0.81
                            transformOrigin: Item.TopLeft
                            Shape {
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    strokeColor: "transparent"; strokeWidth: 0; fillColor: card.gFill
                                    PathSvg { path: "M -0.99 -33.99 A 34 34 0 1 0 28.77 18.11 A 30 30 0 0 1 -0.99 -33.99 Z" }
                                }
                            }
                            Rectangle { x: -26 - 2.8; y: 11 - 2.8; width: 5.6; height: 5.6; radius: 2.8; color: card.gCheek; opacity: 0.5 }
                            // eyes shut
                            Shape {
                                opacity: !card.awake || card.blink ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    strokeColor: "#2B2B30"; strokeWidth: 1.6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                    PathSvg { path: "M -23 4 Q -20 7.5 -17 4" }
                                }
                            }
                            // eyes open
                            Item {
                                opacity: card.awake && !card.blink ? 1 : 0
                                x: card.glance ? -1.8 : 0
                                y: card.glance ? 1.6 : 0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                Behavior on x { NumberAnimation { duration: 320 } }
                                Behavior on y { NumberAnimation { duration: 320 } }
                                Rectangle { x: -20 - 2.7; y: 4.5 - 2.7; width: 5.4; height: 5.4; radius: 2.7; color: "#2B2B30" }
                                Rectangle { x: -19.1 - 0.9; y: 3.6 - 0.9; width: 1.8; height: 1.8; radius: 0.9; color: "white" }
                            }
                            // mouth: a dot asleep, a smile awake
                            Rectangle {
                                x: -19 - 1.5; y: 13.5 - 1.5; width: 3; height: 3; radius: 1.5; color: "#2B2B30"
                                opacity: card.awake ? 0 : 1
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                            }
                            Shape {
                                opacity: card.awake ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    strokeColor: "#2B2B30"; strokeWidth: 1.6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                    PathSvg { path: "M -22.5 12.5 Q -19 16 -15.5 12.5" }
                                }
                            }
                        }
                    }
                    MultiEffect {
                        anchors.fill: moonArt
                        source: moonArt
                        autoPaddingEnabled: true
                        shadowEnabled: true
                        shadowBlur: (card.awake ? 14 : 6) / 32
                        shadowColor: card.awake ? card.gGlowOn : card.gGlowOff
                        shadowOpacity: 1
                        Behavior on shadowBlur { NumberAnimation { duration: 900 } }
                    }
                }

                // z's drifting up from the moon
                Repeater {
                    model: 3
                    delegate: ForkCanvasText {
                        id: z
                        required property int index
                        readonly property int zp: (card.tick + index) % 3
                        readonly property var step: zp === 0 ? [0, 0, 1, 0] : (zp === 1 ? [10, -14, 1.25, 0.85] : [20, -30, 1.5, 0])
                        property real zx: step[0]
                        property real zy: step[1]
                        property real zs: step[2]
                        property real zo: step[3]
                        Behavior on zx { enabled: z.zp !== 0; NumberAnimation { duration: 1100; easing.type: Easing.Linear } }
                        Behavior on zy { enabled: z.zp !== 0; NumberAnimation { duration: 1100; easing.type: Easing.Linear } }
                        Behavior on zs { enabled: z.zp !== 0; NumberAnimation { duration: 1100; easing.type: Easing.Linear } }
                        Behavior on zo { enabled: z.zp !== 0; NumberAnimation { duration: 1100; easing.type: Easing.OutQuad } }
                        x: 176 + zx; y: 2 + zy
                        scale: zs
                        opacity: card.awake ? 0 : zo
                        text: "z"
                        color: card.gStar
                        px: 12; weight: 800; lineHeightPx: 12
                    }
                }

                // Sparkles pop in when the moon wakes
                Item {
                    x: 21 - 7; y: 61 - 7; width: 14; height: 14
                    opacity: card.awake ? 1 : 0
                    scale: card.awake ? 1 : 0.3
                    Behavior on opacity { NumberAnimation { duration: 400 } }
                    Behavior on scale { NumberAnimation { duration: 400 } }
                    Shape {
                        x: 7; y: 7
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: "transparent"; strokeWidth: 0; fillColor: card.gSparkA
                            PathSvg { path: "M0 -6.5 L1.6 -1.6 L6.5 0 L1.6 1.6 L0 6.5 L-1.6 1.6 L-6.5 0 L-1.6 -1.6 Z" }
                        }
                    }
                }
                Item {
                    x: 179 - 5; y: 135 - 5; width: 10; height: 10
                    opacity: card.awake ? 1 : 0
                    scale: card.awake ? 1 : 0.3
                    Behavior on opacity { NumberAnimation { duration: 400 } }
                    Behavior on scale { NumberAnimation { duration: 400 } }
                    Shape {
                        x: 5; y: 5
                        scale: 10 / 14
                        transformOrigin: Item.TopLeft
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: "transparent"; strokeWidth: 0; fillColor: card.gSparkB
                            PathSvg { path: "M0 -6.5 L1.6 -1.6 L6.5 0 L1.6 1.6 L0 6.5 L-1.6 1.6 L-6.5 0 L-1.6 -1.6 Z" }
                        }
                    }
                }
            }

            Item {
                width: 320; height: 36
                anchors.horizontalCenter: parent.horizontalCenter
                ForkCanvasText {
                    y: 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Add a PC"
                    color: ForkTheme.cv.text
                    px: 22; weight: 700; tracking: -0.33; lineHeightPx: 28
                }
            }
            ForkCanvasText {
                width: 320
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "Type its address, or pick one LuzLunar finds on your network."
                color: ForkTheme.cv.muted
                px: 13.5; lineHeightPx: 20
            }
            Item {
                width: guideLabel.implicitWidth + 20; height: 32
                anchors.horizontalCenter: parent.horizontalCenter
                Accessible.role: Accessible.Button
                Accessible.name: "Setup guide"
                Accessible.onPressAction: card.guideClicked()
                ForkCanvasText {
                    id: guideLabel
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 1
                    text: "Setup guide"
                    color: ForkTheme.cv.text2
                    px: 13; weight: 500
                    font.underline: true
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.guideClicked() }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        visible: !card.focused
        cursorShape: Qt.PointingHandCursor
        Accessible.role: Accessible.Button
        Accessible.name: "Show Add a PC"
        Accessible.onPressAction: card.picked()
        onClicked: card.picked()
    }
}
