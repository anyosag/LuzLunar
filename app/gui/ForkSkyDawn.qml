// [fork] The light theme's dawn glow: two big soft ellipses (peach to lavender on the left, apricot to
// sky blue on the right) that drift between four shapes every 4 s (Main.dc.html 1235-1256,
// sky-chrome.md 4.5). The canvas blurs them by 28 px; here they are drawn in a quarter-size layer and
// blurred there, which is cheap while they move. Decorative.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

Item {
    id: dawn

    property bool running: false
    // one fixed frame (frames 0 and 1), no drift
    property bool still: false

    readonly property var frames: [
        { x: -60, k: -14, s: 0.9, o: 0.55 },
        { x: 20, k: -4, s: 1.12, o: 0.85 },
        { x: 70, k: 10, s: 0.96, o: 0.7 },
        { x: -10, k: -6, s: 1.18, o: 0.9 }
    ]
    property int step: 0

    Timer { interval: 200; running: dawn.running && !dawn.still; onTriggered: dawn.step++ }
    Timer { interval: 4000; repeat: true; running: dawn.running && !dawn.still; onTriggered: dawn.step++ }

    // blur sigma 28 px, in a layer at 1/4 size: sigma 7 there
    readonly property real layerScale: 0.25

    MultiEffect {
        anchors.fill: parent
        source: art
        blurEnabled: true
        blurMax: 64
        blur: dawn.sigmaToBlur(28 * dawn.layerScale)
    }

    Item {
        id: art
        width: Math.max(1, Math.round(dawn.width * dawn.layerScale))
        height: Math.max(1, Math.round(dawn.height * dawn.layerScale))
        layer.enabled: true
        layer.smooth: true
        visible: false

        // the whole window's art, drawn at 1/4 size into the layer
        Item {
        width: dawn.width; height: dawn.height
        scale: dawn.layerScale
        transformOrigin: Item.TopLeft

        Repeater {
            model: [
                { left: -120, top: 300, w: 1000, h: 300, rot: -8, c1: Qt.rgba(1, 190 / 255, 170 / 255, 0.35), c2: Qt.rgba(200 / 255, 180 / 255, 1, 0.32), c3: Qt.rgba(200 / 255, 180 / 255, 1, 0), c0a: Qt.rgba(1, 190 / 255, 170 / 255, 0) },
                { left: 520, top: 270, w: 900, h: 260, rot: 6, c1: Qt.rgba(1, 214 / 255, 170 / 255, 0.30), c2: Qt.rgba(170 / 255, 215 / 255, 1, 0.30), c3: Qt.rgba(170 / 255, 215 / 255, 1, 0), c0a: Qt.rgba(1, 214 / 255, 170 / 255, 0) }
            ]
            delegate: Item {
                id: cur
                required property var modelData
                required property int index
                readonly property var f: dawn.frames[dawn.still ? index : (dawn.step + index) % 4]
                property real fx: f.x
                property real fk: f.k
                property real fs: f.s
                property real fo: f.o
                Behavior on fx { enabled: !dawn.still; NumberAnimation { duration: 4000; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.42, 0, 0.58, 1, 1, 1] } }
                Behavior on fk { enabled: !dawn.still; NumberAnimation { duration: 4000; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.42, 0, 0.58, 1, 1, 1] } }
                Behavior on fs { enabled: !dawn.still; NumberAnimation { duration: 4000; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.42, 0, 0.58, 1, 1, 1] } }
                Behavior on fo { enabled: !dawn.still; NumberAnimation { duration: 4000; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.42, 0, 0.58, 1, 1, 1] } }

                x: modelData.left; y: modelData.top
                width: modelData.w; height: modelData.h
                opacity: fo
                transformOrigin: Item.TopLeft
                // rotate(rot) translateX(X) skewX(K) scaleY(S) about the box centre
                transform: Matrix4x4 {
                    readonly property real r: cur.modelData.rot * Math.PI / 180
                    readonly property real kk: Math.tan(cur.fk * Math.PI / 180)
                    readonly property real cx: cur.width / 2
                    readonly property real cy: cur.height / 2
                    readonly property real a: Math.cos(r)
                    readonly property real b: Math.sin(r)
                    readonly property real c: cur.fs * (Math.cos(r) * kk - Math.sin(r))
                    readonly property real d: cur.fs * (Math.sin(r) * kk + Math.cos(r))
                    matrix: Qt.matrix4x4(a, c, 0, cx - a * cx - c * cy + cur.fx * Math.cos(r),
                                         b, d, 0, cy - b * cx - d * cy + cur.fx * Math.sin(r),
                                         0, 0, 1, 0,
                                         0, 0, 0, 1)
                }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: "transparent"
                        fillGradient: LinearGradient {
                            x1: 0; y1: 0; x2: 0; y2: cur.height
                            GradientStop { position: 0; color: cur.modelData.c0a }
                            GradientStop { position: 0.32; color: cur.modelData.c1 }
                            GradientStop { position: 0.64; color: cur.modelData.c2 }
                            GradientStop { position: 1; color: cur.modelData.c3 }
                        }
                        PathAngleArc {
                            centerX: cur.width / 2; centerY: cur.height / 2
                            radiusX: cur.width / 2; radiusY: cur.height / 2
                            startAngle: 0; sweepAngle: 360
                        }
                    }
                }
            }
        }
        }
    }

    // MultiEffect's blur is mip-based, not a plain sigma. Measured with blurMax 64 (sigma in texture px):
    // blur 0.25 -> 3.8, 0.5 -> 10.3, 1.0 -> 20.3; this inverts it piecewise-linearly
    function sigmaToBlur(sigma) {
        if (sigma <= 3.8) return 0.25 * sigma / 3.8
        if (sigma <= 10.3) return 0.25 + 0.25 * (sigma - 3.8) / 6.5
        return Math.min(1, 0.5 + 0.5 * (sigma - 10.3) / 10)
    }
}
