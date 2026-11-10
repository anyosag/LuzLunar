// [fork] A small icon from an SVG path in a 24-unit box (the canvas's icons), stroked in `color`
// (round caps and joins) and optionally filled with it. Used by the PC page's pills, dots and menu.
import QtQuick
import QtQuick.Shapes

Item {
    id: glyph

    property string path: ""
    property real size: 16
    property color color: "white"
    property real strokeWidth: 1.8
    property bool filled: false

    width: size
    height: size
    Accessible.ignored: true

    Shape {
        width: 24; height: 24
        scale: glyph.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: glyph.filled ? glyph.color : "transparent"
            strokeColor: glyph.color
            strokeWidth: glyph.strokeWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            fillRule: ShapePath.WindingFill
            PathSvg { path: glyph.path }
        }
    }
}
