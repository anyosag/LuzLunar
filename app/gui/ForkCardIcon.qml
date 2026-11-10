import QtQuick
import QtQuick.Shapes

// [fork] A card icon: an SVG path from a 24-unit grid, stroked (round caps and joins) and/or
// filled in `color`, drawn at `size`. Stroke widths are in grid units, like the canvas's.
Item {
    id: icon

    property string path: ""
    property real size: 16
    property color color: "white"
    property real strokeWidth: 1.9
    property bool filled: false
    property bool stroked: true

    width: size
    height: size
    implicitWidth: size
    implicitHeight: size
    Accessible.ignored: true

    Shape {
        width: 24
        height: 24
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: icon.size / 24; yScale: icon.size / 24 }

        ShapePath {
            strokeColor: icon.stroked ? icon.color : "transparent"
            strokeWidth: icon.stroked ? icon.strokeWidth : 0
            fillColor: icon.filled ? icon.color : "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.path }
        }
    }
}
