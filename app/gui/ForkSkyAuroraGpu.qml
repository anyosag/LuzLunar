// [fork] The night sky's aurora on the GPU (D13): shaders/aurora.frag evaluates the canvas's aurora
// columns per pixel into a layer of 1 px per logical px (the canvas's bitmap), a quarter-size copy of
// it is blurred for the glow, and shaders/screen.frag screens glow and layer over the sky gradient.
// Per frame the CPU only sets one uniform (the time). Decorative: no input, no accessibility.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

Item {
    id: gpu

    property real skyWidth: 1280
    property real skyHeight: 900
    property real bandTop: skyHeight - 620
    // ms, like the canvas's rAF timestamp
    property real time: 12000
    property bool active: false
    readonly property real drawMs: 0
    signal frameReady()

    width: skyWidth
    height: 520
    y: bandTop
    clip: true

    readonly property int gw: Math.max(8, Math.round(skyWidth / 4))
    readonly property int gh: 130

    // M: the curtains, 1 px per logical px. Not shown itself: the sources below take it
    ShaderEffect {
        id: columns
        width: gpu.skyWidth; height: 520
        visible: false
        property real t: gpu.time / 1000
        // the shader's block takes `width` and `height` from this item, plus t and gain
        property real gain: 1
        fragmentShader: "shaders/aurora.frag.qsb"
    }

    ShaderEffectSource {
        id: mainSrc
        sourceItem: columns
        width: gpu.skyWidth; height: 520
        textureSize: Qt.size(gpu.skyWidth, 520)
        hideSource: true
        smooth: true
        live: gpu.active
        visible: false
    }

    // the glow: M at 1/4 size (the canvas's 320 x 130 bitmap), blurred by 16 px = 4 px there
    ShaderEffectSource {
        id: small
        sourceItem: columns
        width: gpu.gw; height: gpu.gh
        textureSize: Qt.size(gpu.gw, gpu.gh)
        mipmap: true
        smooth: true
        live: gpu.active
        visible: false
    }
    Item {
        id: glowWrap
        width: gpu.gw; height: gpu.gh
        visible: false
        layer.enabled: true
        layer.smooth: true
        MultiEffect {
            anchors.fill: parent
            source: small
            blurEnabled: true
            blurMax: 64
            // blurMax 64: blur 0.25 -> sigma 3.8 px, 0.27 -> about 4
            blur: 0.265
        }
    }

    ShaderEffect {
        anchors.fill: parent
        property variant mainTex: mainSrc
        property variant glowTex: glowWrap
        property real bandTop: gpu.bandTop
        property real skyHeight: gpu.skyHeight
        property real bandHeight: 520
        fragmentShader: "shaders/screen.frag.qsb"
    }

    function dump(prefix) {}
}
