// [fork] The night sky's three details: the Big Dipper, a satellite crossing the top, and a shooting
// star now and then (Main.dc.html 1257-1297 and 375-444, sky-chrome.md 4.6-4.8). Decorative.
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import ForkTheme

Item {
    id: night

    property int tick: 0
    property bool running: false
    property real skyWidth: 1280

    // ---- Big Dipper, 170 x 74 at (width - 296, 198)
    Item {
        id: dipper
        x: night.skyWidth - 296; y: 198
        width: 170; height: 74

        Shape {
            ShapePath {
                strokeColor: Qt.rgba(190 / 255, 205 / 255, 1, 0.22)
                strokeWidth: 1
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                joinStyle: ShapePath.MiterJoin
                PathSvg { path: "M0 0L34 8L62 14L90 22L138 12L142 46L98 48L90 22" }
            }
        }
        Repeater {
            model: [[0, 0], [34, 8], [62, 14], [90, 22], [138, 12], [142, 46], [98, 48]]
            delegate: Item {
                id: dp
                required property var modelData
                required property int index
                readonly property real r: index === 4 || index === 5 ? 2.1 : 1.7
                x: modelData[0]; y: modelData[1]
                opacity: (night.tick + index) % 3 === 0 ? 0.55 : 0.95
                Behavior on opacity {
                    enabled: night.running
                    NumberAnimation { duration: 1100; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.42, 0, 0.58, 1, 1, 1] }
                }
                // drop-shadow(0 0 3px rgba(255,255,255,0.8))
                Repeater {
                    model: [[3.2, 0.10], [2.4, 0.14], [1.6, 0.2]]
                    Rectangle {
                        required property var modelData
                        width: (dp.r + modelData[0]) * 2; height: width; radius: width / 2
                        x: -width / 2; y: -width / 2
                        color: "white"; opacity: modelData[1]
                    }
                }
                Rectangle { width: dp.r * 2; height: width; radius: r; x: -r; y: -r; color: "white"; antialiasing: true
                    readonly property real r: dp.r }
            }
        }
        Text {
            x: 0; width: 170
            y: 70 - baselineOffset
            horizontalAlignment: Text.AlignHCenter
            text: "BIG DIPPER"
            color: Qt.rgba(200 / 255, 210 / 255, 1, 0.42)
            font.family: ForkTheme.uiFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 1.4
            transformOrigin: Item.Center
            scale: 0.95
            leftPadding: 0
            Accessible.ignored: true
        }
    }

    // ---- satellite: crosses in 46 s, the cycle is 47.06 s, the first one after 3 s
    Rectangle {
        id: sat
        width: 2; height: 2; radius: 1
        color: "white"
        x: -20; y: 150; opacity: 0
        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; opacity: 0.12; z: -1 }
        Rectangle { anchors.centerIn: parent; width: 5.5; height: 5.5; radius: 3; color: "white"; opacity: 0.18; z: -1 }
    }
    SequentialAnimation {
        id: satAnim
        running: night.running
        loops: Animation.Infinite
        // the first cycle waits 3 s; later ones wait out the second left over from the last
        PauseAnimation { duration: 3000 }
        ScriptAction { script: { sat.x = -20; sat.y = 150; sat.opacity = 0 } }
        PauseAnimation { duration: 60 }
        ParallelAnimation {
            NumberAnimation { target: sat; property: "x"; to: night.skyWidth + 20; duration: 46000 }
            NumberAnimation { target: sat; property: "y"; to: 96; duration: 46000 }
            NumberAnimation { target: sat; property: "opacity"; to: 0.85; duration: 3000; easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] }
        }
        // 46000 - 3000 of the opacity run is spent, so the cycle's tail is 1 s; later cycles skip the 3 s head
        PauseAnimation { duration: 1000 }
        ScriptAction { script: { sat.opacity = 0; sat.x = -20; sat.y = 150 } }
    }

    // ---- shooting star: a 150 x 2 streak whose head flies along `ang`
    property real shX: 0
    property real shY: 0
    property real shAng: 0
    property real shDist: 0
    property real shT: 0
    property real shSx: 0.3
    property real shOp: 0

    Item {
        id: shoot
        x: night.shX - 150; y: night.shY
        width: 150; height: 2
        opacity: night.shOp
        transform: [
            Scale { origin.x: 150; origin.y: 1; xScale: night.shSx },
            Translate { x: night.shT },
            Rotation { origin.x: 150; origin.y: 1; angle: night.shAng }
        ]
        // box-shadow: 0 0 6px rgba(200,220,255,0.6)
        Rectangle {
            x: -3; y: -3; width: 156; height: 8; radius: 4
            color: Qt.rgba(200 / 255, 220 / 255, 1, 0.14)
        }
        Rectangle {
            x: -1.5; y: -1.5; width: 153; height: 5; radius: 2.5
            color: Qt.rgba(200 / 255, 220 / 255, 1, 0.2)
        }
        Rectangle {
            anchors.fill: parent
            radius: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: 0.7; color: Qt.rgba(210 / 255, 225 / 255, 1, 0.55) }
                GradientStop { position: 1; color: "white" }
            }
        }
    }

    function reroll() {
        var fromLeft = Math.random() < 0.6
        var w = night.skyWidth / 1280
        shX = (fromLeft ? 160 + Math.random() * 640 : 520 + Math.random() * 640) * w
        shY = 50 + Math.random() * 230
        shAng = fromLeft ? 18 + Math.random() * 18 : 144 + Math.random() * 18
        shDist = 260 + Math.random() * 200
        shT = 0; shSx = 0.3; shOp = 0
    }

    SequentialAnimation {
        id: shootAnim
        running: night.running
        loops: Animation.Infinite
        PauseAnimation { duration: 1800 }
        // each shot: start (jump), fly, fade, idle 3.5 - 9 s
        SequentialAnimation {
            id: shot
            loops: Animation.Infinite
            ScriptAction { script: night.reroll() }
            PauseAnimation { duration: 40 }
            ParallelAnimation {
                NumberAnimation { target: night; property: "shT"; to: night.shDist; duration: 760
                    easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.6, 0.3, 1, 1, 1] }
                NumberAnimation { target: night; property: "shSx"; to: 1; duration: 760
                    easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.6, 0.3, 1, 1, 1] }
                NumberAnimation { target: night; property: "shOp"; to: 1; duration: 180
                    easing.type: Easing.BezierSpline; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] }
            }
            ParallelAnimation {
                NumberAnimation { target: night; property: "shT"; to: night.shDist + 90; duration: 380 }
                NumberAnimation { target: night; property: "shSx"; to: 0.6; duration: 380 }
                NumberAnimation { target: night; property: "shOp"; to: 0; duration: 380
                    easing.type: Easing.BezierSpline; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] }
            }
            PauseAnimation { duration: 40 }
            ScriptAction { script: { night.shOp = 0; shot.pause_ = 3500 + Math.random() * 5500 } }
            PauseAnimation { id: idle; duration: 3500 }
        }
    }
}
