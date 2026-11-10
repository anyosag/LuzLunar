import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import ForkTheme 1.0

// [fork] The moon art in the small card's header band (279 x 64; band coordinates). Static, as on
// the States board. kind: live | waking | asleep | off | pair | lost.
Item {
    id: moon

    property string kind: "live"
    property color sky: "#17163F"

    width: 279
    height: 64
    Accessible.ignored: true

    Item {
        visible: moon.kind === "live"
        RectangularShadow {
            x: 220; y: 14; width: 34; height: 34
            radius: 17; blur: 22
            color: Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.25)
        }
        Rectangle { x: 220; y: 14; width: 34; height: 34; radius: 17; color: moon.sky }
        Shape {
            x: 220; y: 14; width: 34; height: 34
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; strokeWidth: 0; fillColor: "#F5C878"
                PathSvg { path: "M13.63 0.34A17 17 0 1 0 29.37 28.66A17 17 0 0 1 13.63 0.34Z" }
            }
        }
    }

    Item {
        visible: moon.kind === "waking"
        x: 216; y: 26; width: 42; height: 38
        clip: true
        RectangularShadow {
            x: 4; y: 12; width: 34; height: 34
            radius: 17; blur: 20
            color: Qt.rgba(1, 179 / 255, 64 / 255, 0.35)
        }
        Rectangle { x: 4; y: 12; width: 34; height: 34; radius: 17; color: moon.sky }
        Shape {
            x: 4; y: 12; width: 34; height: 34
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; strokeWidth: 0; fillColor: "#FFC46B"
                PathSvg { path: "M13.63 0.34A17 17 0 1 0 29.37 28.66A17 17 0 0 1 13.63 0.34Z" }
            }
        }
    }

    Item {
        visible: moon.kind === "asleep"
        x: 216; y: 34; width: 42; height: 30
        clip: true
        Shape {
            x: 4; y: 14; width: 34; height: 34
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; strokeWidth: 0; fillColor: "#CFC8F3"
                PathSvg { path: "M13.67 0.33A17 17 0 1 0 28.33 29.67A17 17 0 0 1 13.67 0.33Z" }
            }
        }
    }
    ForkCanvasText {
        visible: moon.kind === "asleep"
        x: 254; y: 24
        text: "z"; color: Qt.rgba(1, 1, 1, 0.5)
        px: 10; weight: 700
    }
    ForkCanvasText {
        visible: moon.kind === "asleep"
        x: 262; y: 14
        text: "z"; color: Qt.rgba(1, 1, 1, 0.4)
        px: 12; weight: 700
    }

    ForkCardRing {
        visible: moon.kind === "off"
        x: 220; y: 15; size: 34
        color: Qt.rgba(207 / 255, 200 / 255, 243 / 255, 0.45)
    }
    ForkCardRing {
        visible: moon.kind === "pair"
        x: 220; y: 15; size: 34
        dashed: true
        color: Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.75)
    }
    Shape {
        visible: moon.kind === "pair"
        x: 220; y: 15; width: 17; height: 34
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"; strokeWidth: 0; fillColor: "#F5C878"
            PathSvg { path: "M17 0A17 17 0 0 0 17 34Z" }
        }
    }
    ForkCardRing {
        visible: moon.kind === "lost"
        x: 220; y: 15; size: 34
        dashed: true
        color: Qt.rgba(1, 105 / 255, 97 / 255, 0.7)
        ForkCanvasText {
            anchors.centerIn: parent
            text: "?"
            color: Qt.rgba(1, 105 / 255, 97 / 255, 0.9)
            px: 15; weight: 700
        }
    }
}
