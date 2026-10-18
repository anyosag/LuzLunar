import QtQuick

import ForkTheme 1.0
import QtQuick.Shapes

// [fork] LuzLunar's "moon path" mark: a crescent above its reflection on water, broken into lines
// like a video signal. On its tile it's the app icon; without one (tile: false) it's drawn in the
// theme's gold. shimmer makes the reflection ripple, for the stream launch screen.
Item {
    id: mark

    property real size: 24
    property bool tile: true
    property bool shimmer: false
    readonly property color ink: tile ? "#F5C878" : ForkTheme.markInk

    width: size
    height: size
    implicitWidth: size
    implicitHeight: size

    // Drawn on a 100x100 grid, scaled to size
    Item {
        width: 100
        height: 100
        transform: Scale {
            xScale: mark.size / 100
            yScale: mark.size / 100
        }

        Rectangle {
            visible: mark.tile
            anchors.fill: parent
            radius: 22.5
            color: ForkTheme.markTile
        }

        // The crescent: the circle (50, 40, r 18) less the circle (58, 34, r 16)
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                strokeWidth: 0
                fillColor: mark.ink
                PathSvg {
                    path: "M47.17 22.22A18 18 0 1 0 66.27 47.7A16 16 0 0 1 47.17 22.22Z"
                }
            }
        }

        // The horizon
        Rectangle {
            x: 18
            y: 62.8
            width: 64
            height: 1.4
            radius: 0.7
            color: mark.tile ? "#2B3566" : ForkTheme.lineStrong
        }

        // The reflection: x, y, width and opacity of each line
        Repeater {
            model: [[35, 68.5, 30, 1.0], [39, 74, 22, 0.82], [36, 79.5, 10, 0.64],
                    [50, 79.5, 9, 0.64], [42, 85, 13, 0.44], [46.5, 90.5, 5, 0.28]]

            delegate: Rectangle {
                id: bar
                required property var modelData
                required property int index

                x: modelData[0]
                y: modelData[1]
                width: modelData[2]
                height: 3.4
                radius: 1.7
                color: mark.ink
                opacity: modelData[3]

                // The design's shimmer: 2.4 s, each line in turn; still with Reduce Motion
                SequentialAnimation on opacity {
                    running: mark.shimmer && !ForkTheme.reduceMotion
                    loops: Animation.Infinite
                    PauseAnimation { duration: [0, 200, 400, 450, 600, 800][bar.index] }
                    NumberAnimation { to: 0.25; duration: 1200; easing.type: Easing.InOutSine }
                    NumberAnimation { to: bar.modelData[3]; duration: 1200; easing.type: Easing.InOutSine }
                    onStopped: bar.opacity = bar.modelData[3]
                }
            }
        }
    }
}
