import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import ForkTheme 1.0

// [fork] The moon art in the big card's header band (558 x 104; this item fills the band, so the
// coordinates below are the canvas's band coordinates). kind: live | waking | asleep | off | pair |
// lost. `tick` is the shared 1100 ms clock; `breathe` makes the live moon's glow swing (streaming).
Item {
    id: moon

    property string kind: "live"
    property int tick: 0
    property bool breathe: true
    property color sky: "#17163F"

    readonly property int ph: tick % 2

    width: 558
    height: 104
    Accessible.ignored: true

    // ---- live (and the derived waking one): a crescent whose glow shows only outside its disc
    Item {
        visible: moon.kind === "live"
        RectangularShadow {
            x: 456; y: 22; width: 58; height: 58
            radius: 29
            blur: moon.breathe && moon.ph ? 54 : 34
            color: Qt.rgba(245 / 255, 200 / 255, 120 / 255, moon.breathe && moon.ph ? 0.4 : 0.22)
            Behavior on blur { NumberAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
            Behavior on color { ColorAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
        }
        Rectangle { x: 456; y: 22; width: 58; height: 58; radius: 29; color: moon.sky }
        Shape {
            x: 456; y: 22; width: 58; height: 58
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; strokeWidth: 0; fillColor: "#F5C878"
                PathSvg { path: "M23.45 0.54A29 29 0 1 0 49.55 49.46A29 29 0 0 1 23.45 0.54Z" }
            }
        }
    }

    // waking: the same crescent in #FFC46B, rising; its glow is cut to a 72 x 64 box like the States board's
    Item {
        visible: moon.kind === "waking"
        x: 449; y: 40; width: 72; height: 64
        clip: true
        RectangularShadow {
            x: 7; y: 20; width: 58; height: 58
            radius: 29; blur: 34
            color: Qt.rgba(1, 179 / 255, 64 / 255, 0.35)
        }
        Rectangle { x: 7; y: 20; width: 58; height: 58; radius: 29; color: moon.sky }
        Shape {
            x: 7; y: 20; width: 58; height: 58
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; strokeWidth: 0; fillColor: "#FFC46B"
                PathSvg { path: "M23.45 0.54A29 29 0 1 0 49.55 49.46A29 29 0 0 1 23.45 0.54Z" }
            }
        }
    }

    // ---- asleep: a crescent sinking into the band's edge, and three z's drifting up
    Item {
        id: sleepBox
        visible: moon.kind === "asleep"
        x: 446; y: moon.ph ? 52 : 48; width: 76; height: 54
        clip: true
        Behavior on y { NumberAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
        Shape {
            x: 10; y: 24; width: 54; height: 54
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; strokeWidth: 0; fillColor: "#CFC8F3"
                PathSvg { path: "M22.59 0.36A27 27 0 1 0 44.41 47.64A27 27 0 0 1 22.59 0.36Z" }
            }
        }
    }
    Repeater {
        model: moon.kind === "asleep" ? 3 : 0
        delegate: ForkCardLabel {
            id: z
            required property int index
            readonly property int zp: (moon.tick + index) % 3
            readonly property var step: zp === 0 ? [0, 0, 1, 0] : (zp === 1 ? [8, -12, 1.2, 0.75] : [16, -24, 1.4, 0])
            property real zx: step[0]
            property real zy: step[1]
            property real zs: step[2]
            property real zo: step[3]
            Behavior on zx { enabled: z.zp !== 0; NumberAnimation { duration: 1100; easing.type: Easing.Linear } }
            Behavior on zy { enabled: z.zp !== 0; NumberAnimation { duration: 1100; easing.type: Easing.Linear } }
            Behavior on zs { enabled: z.zp !== 0; NumberAnimation { duration: 1100; easing.type: Easing.Linear } }
            Behavior on zo { enabled: z.zp !== 0; NumberAnimation { duration: 1100; easing.type: Easing.OutQuad } }
            x: 508 + zx
            y: 46 + zy
            scale: zs
            opacity: zo
            text: "z"
            color: Qt.rgba(1, 1, 1, 0.8)
            font.family: ForkTheme.uiFamily
            px: 11
            font.weight: 800
            lineHeightMode: Text.FixedHeight
            lineHeight: 11
        }
    }

    // ---- pair: a dashed ring turning behind a half disc
    ForkCardRing {
        visible: moon.kind === "pair"
        x: 458; y: 24
        size: 54
        dashed: true
        color: Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.75)
        rotation: moon.tick * 24
        Behavior on rotation { NumberAnimation { duration: 1100; easing.type: Easing.Linear } }
    }
    Shape {
        visible: moon.kind === "pair"
        x: 458; y: 24; width: 27; height: 54
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"; strokeWidth: 0; fillColor: "#F5C878"
            PathSvg { path: "M27 0A27 27 0 0 0 27 54Z" }
        }
    }

    // ---- off: a plain ring; lost: a dashed red ring with a question mark
    ForkCardRing {
        visible: moon.kind === "off"
        x: 458; y: 24
        size: 54
        color: Qt.rgba(207 / 255, 200 / 255, 243 / 255, 0.45)
    }
    ForkCardRing {
        visible: moon.kind === "lost"
        x: 458; y: 24
        size: 54
        dashed: true
        color: Qt.rgba(1, 105 / 255, 97 / 255, 0.7)
        ForkCardLabel {
            anchors.centerIn: parent
            text: "?"
            color: Qt.rgba(1, 105 / 255, 97 / 255, 0.9)
            font.family: ForkTheme.uiFamily
            px: 24
            font.weight: 700
        }
    }
}
