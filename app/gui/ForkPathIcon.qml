import QtQuick
import QtQuick.Shapes

import "ForkIconPaths.js" as Paths

// [fork] An icon of the redesign canvas: the path for `name` from ForkIconPaths.js, drawn from the
// canvas's 24-unit viewBox with round caps and joins, scaled to `size`. Stroke widths are in
// viewBox units like the canvas's (a 14 px icon at 1.9 is a 1.1 px line). A name that isn't in
// ForkIconPaths.js draws nothing. Decorative: hidden from accessibility.
Item {
    id: root

    // A key of ForkIconPaths.js, e.g. "play"
    property string name: ""
    // Or raw SVG path data in the 24-unit viewBox (used when name is empty or unknown)
    property string path: ""
    property real size: 16
    property color color: "#FFFFFF"
    // In viewBox units; the icon's own default when negative
    property real strokeWidth: -1
    // Filled with `color` as well; the icon's own default when not set
    property bool filled: entry ? !!entry.fill : false
    // Drawn with a stroke; the icon's own default when not set
    property bool stroked: entry ? !entry.noStroke : true

    readonly property var entry: Paths.get(name)
    readonly property string pathData: entry ? entry.d : path
    readonly property var box: entry && entry.vb ? entry.vb : [0, 0, 24, 24]
    readonly property real effectiveStroke: strokeWidth >= 0 ? strokeWidth : (entry ? entry.sw : 1.8)

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Accessible.ignored: true

    Shape {
        visible: root.pathData !== ""
        x: -root.box[0] * root.size / root.box[2]
        y: -root.box[1] * root.size / root.box[2]
        width: root.box[2]
        height: root.box[3]
        // Scale from the top left; the viewBox origin moves to 0,0
        transformOrigin: Item.TopLeft
        scale: root.size / root.box[2]
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.stroked && root.effectiveStroke > 0 ? root.color : "transparent"
            strokeWidth: root.stroked ? root.effectiveStroke : 0
            fillColor: root.filled ? root.color : "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: root.pathData
            }
        }
    }
}
