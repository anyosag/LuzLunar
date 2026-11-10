import QtQuick
import QtQuick.Shapes

// [fork] A soft glow around a disc, painted only outside the disc (the canvas's outer box-shadow:
// 0 0 <blur> <color> is clipped to outside its own shape). The disc's radius is `radius`; the
// blur's sigma is radius / 1.35 (the moons' 46 px / 34 px and 54 px / 40 px glows). The gaussian
// falloff is a radial gradient of the exact blurred-disc coverage; `color` carries the glow's alpha.
// The item is centered on its parent's `anchors.centerIn` target by the user.
Item {
    id: glow

    property real radius: 23
    property color color: Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.25)

    readonly property real extent: radius * 3.37
    readonly property var profile: [0.3427, 0.2959, 0.2508, 0.2086, 0.1702, 0.1361, 0.1067, 0.0819, 0.0616,
                                    0.0454, 0.0327, 0.023, 0.0159, 0.0107, 0.0071, 0.0046, 0.0029, 0.0018,
                                    0.0011, 0.0006, 0.0004]
    function tone(i) {
        return Qt.rgba(color.r, color.g, color.b, color.a * profile[i])
    }

    width: extent * 2
    height: extent * 2
    visible: color.a > 0
    enabled: false
    Accessible.ignored: true

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.GeometryRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: glow.extent; centerY: glow.extent
                centerRadius: glow.extent
                focalX: glow.extent; focalY: glow.extent
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.2966; color: "transparent" }
                GradientStop { position: 0.2967; color: glow.tone(0) }
                GradientStop { position: 0.3319; color: glow.tone(1) }
                GradientStop { position: 0.367; color: glow.tone(2) }
                GradientStop { position: 0.4022; color: glow.tone(3) }
                GradientStop { position: 0.4374; color: glow.tone(4) }
                GradientStop { position: 0.4725; color: glow.tone(5) }
                GradientStop { position: 0.5077; color: glow.tone(6) }
                GradientStop { position: 0.5429; color: glow.tone(7) }
                GradientStop { position: 0.578; color: glow.tone(8) }
                GradientStop { position: 0.6132; color: glow.tone(9) }
                GradientStop { position: 0.6484; color: glow.tone(10) }
                GradientStop { position: 0.6835; color: glow.tone(11) }
                GradientStop { position: 0.7187; color: glow.tone(12) }
                GradientStop { position: 0.7538; color: glow.tone(13) }
                GradientStop { position: 0.789; color: glow.tone(14) }
                GradientStop { position: 0.8242; color: glow.tone(15) }
                GradientStop { position: 0.8945; color: glow.tone(17) }
                GradientStop { position: 0.9648; color: glow.tone(19) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            startX: 0; startY: 0
            PathLine { x: glow.width; y: 0 }
            PathLine { x: glow.width; y: glow.height }
            PathLine { x: 0; y: glow.height }
            PathLine { x: 0; y: 0 }
        }
    }
}
