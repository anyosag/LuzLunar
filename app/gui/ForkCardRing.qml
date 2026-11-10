import QtQuick
import QtQuick.Shapes

// [fork] A 1 px ring (the canvas draws its 1.5 px borders at 1 px), solid or dashed, in a size x size
// box. dashed uses the canvas's pattern: dashes of 3 px with gaps of 1.9 px.
Item {
    id: ring

    property real size: 54
    property color color: "white"
    property bool dashed: false

    width: size
    height: size
    Accessible.ignored: true

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            readonly property real r: (ring.size - 1) / 2
            strokeColor: ring.color
            strokeWidth: 1
            fillColor: "transparent"
            strokeStyle: ring.dashed ? ShapePath.DashLine : ShapePath.SolidLine
            dashPattern: [3, 1.9]
            PathSvg {
                path: "M " + (ring.size / 2 + parent.r) + " " + ring.size / 2
                      + " A " + parent.r + " " + parent.r + " 0 1 1 " + (ring.size / 2 - parent.r) + " " + ring.size / 2
                      + " A " + parent.r + " " + parent.r + " 0 1 1 " + (ring.size / 2 + parent.r) + " " + ring.size / 2 + " Z"
            }
        }
    }
}
