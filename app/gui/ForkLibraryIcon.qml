import QtQuick
import QtQuick.Shapes

// [fork] A stroke icon of the All apps page (the design's paths, 24 unit viewBox), drawn at `size`.
// Self-contained: the page's icons live here so it doesn't depend on another part's icon set.
Item {
    id: icon

    property string name: ""
    property real size: 16
    property color color: "#FFFFFF"
    // Stroke width in viewBox units; 0 takes the icon's own
    property real strokeWidth: 0
    // Fill the shape with `color` (the play and stop glyphs); -1 takes the icon's own
    property int filled: -1
    // 0 draws no outline (the Quit glyph), -1 takes the icon's own
    property int stroked: -1

    // name: [path, stroke width, filled, stroked]
    readonly property var table: ({
        "back": ["M14.5 5.5 8 12l6.5 6.5", 2.2, false, true],
        "magnifier": ["M10.5 4a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13zM15.3 15.3 20 20", 2, false, true],
        "clear": ["M7 7l10 10M17 7 7 17", 2.6, false, true],
        "copy": ["M9.5 9h9a1.5 1.5 0 0 1 1.5 1.5v9a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 8 19.5v-9A1.5 1.5 0 0 1 9.5 9zM5 15.5V5.5A1.5 1.5 0 0 1 6.5 4h9", 2.2, false, true],
        "play": ["M8 5.8v12.4L18.2 12z", 2, true, true],
        "stop": ["M8 6.5h8A1.5 1.5 0 0 1 17.5 8v8a1.5 1.5 0 0 1-1.5 1.5H8A1.5 1.5 0 0 1 6.5 16V8A1.5 1.5 0 0 1 8 6.5z", 1.8, false, true],
        "power": ["M12 3.5v8M7.05 6.55a7 7 0 1 0 9.9 0", 2, false, true],
        "sliders": ["M4 7h9M17 7h3M4 12h3M11 12h9M4 17h11M19 17h1M15 5v4M9 10v4M17 15v4", 1.8, false, true],
        "bolt": ["M13.2 3 5.8 13.2h5.6L10.6 21l7.6-10.4h-5.6z", 1.8, false, true],
        "eyeSlash": ["M3 12s3.3-6 9-6c1.7 0 3.2.5 4.4 1.3M21 12s-3.3 6-9 6c-1.7 0-3.2-.5-4.4-1.3M9.9 9.9a3 3 0 0 0 4.2 4.2M4 4l16 16", 1.8, false, true],
        "moon": ["M15 4.2a7.8 7.8 0 1 0 4.8 13.1A6.6 6.6 0 0 1 15 4.2z", 0, true, false],
        "checkCircle": ["M12 3a9 9 0 1 1 0 18 9 9 0 0 1 0-18zM8.3 12.3l2.5 2.5 5-5.2", 2, false, true],
        "more": ["M6 12h.01M12 12h.01M18 12h.01", 2.8, false, true],
        "check": ["M5 12.5l4.2 4.2L19 7", 2.4, false, true]
    })
    readonly property var spec: table[name] || ["", 0, false, false]
    readonly property bool doStroke: stroked >= 0 ? stroked === 1 : spec[3]
    readonly property bool doFill: filled >= 0 ? filled === 1 : spec[2]

    width: size
    height: size
    visible: spec[0] !== ""
    Accessible.ignored: true

    Shape {
        width: 24
        height: 24
        scale: icon.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: icon.doStroke ? icon.color : "transparent"
            strokeWidth: icon.doStroke ? (icon.strokeWidth > 0 ? icon.strokeWidth : icon.spec[1]) : 0
            fillColor: icon.doFill ? icon.color : "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.spec[0] }
        }
    }
}
