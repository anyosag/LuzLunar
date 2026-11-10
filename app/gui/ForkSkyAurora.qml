// [fork] The night sky's aurora: the GPU version (ForkSkyAuroraGpu, shaders/*.frag.qsb) by default and
// the Canvas version (ForkSkyAuroraCanvas) when Qt Quick renders in software (GraphicsInfo.Software).
// Both have the same inputs. Decorative.
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: aurora

    property real skyWidth: 1280
    property real skyHeight: 900
    property real bandTop: skyHeight - 620
    // ms, like the canvas's rAF timestamp; the animation is a pure function of it
    property real time: 12000
    // paint frames while true (the owner throttles `time` to 30 fps)
    property bool active: false
    // smoothed ms of CPU the Canvas version spends per frame; 0 on the GPU
    // qmllint disable missing-property
    readonly property real drawMs: loader.item ? loader.item.drawMs : 0
    // force a version: "auto" (default), "gpu" or "canvas"
    property string mode: "auto"
    readonly property bool gpu: mode === "gpu" || (mode === "auto" && GraphicsInfo.api !== GraphicsInfo.Software)

    width: skyWidth
    height: 520
    y: bandTop

    Loader {
        id: loader
        anchors.fill: parent
        sourceComponent: aurora.gpu ? gpuComp : canvasComp
    }
    Component {
        id: gpuComp
        ForkSkyAuroraGpu {
            y: 0
            skyWidth: aurora.skyWidth
            skyHeight: aurora.skyHeight
            bandTop: aurora.bandTop
            time: aurora.time
            active: aurora.active
        }
    }
    Component {
        id: canvasComp
        ForkSkyAuroraCanvas {
            y: 0
            skyWidth: aurora.skyWidth
            skyHeight: aurora.skyHeight
            bandTop: aurora.bandTop
            time: aurora.time
            active: aurora.active
        }
    }

    // for tests: save the canvas version's bitmaps
    function dump(prefix) { if (loader.item) loader.item.dump(prefix) }
    // qmllint enable missing-property
}
