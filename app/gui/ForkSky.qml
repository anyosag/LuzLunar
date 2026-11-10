// [fork] The window's background sky, ported from the design canvas (Main.dc.html "Your PCs"): a night
// sky in dark mode (gradient, a slowly turning star field with the Milky Way, a Canvas aurora, the Big
// Dipper, a satellite, shooting stars, a horizon glow, mountains) and a dawn sky in light mode, with a
// frosted scrim under the header. See spec/sky-chrome.md section 4 and contract-sky.md.
// One instance, filling the window and painted below everything. Decorative: no input, no focus.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import ForkTheme

Item {
    id: root

    // "main": Your PCs (night/dawn, sky-chrome.md section 4); "library": the All apps page's sky
    // (Appendix B.1); "none": nothing is drawn and every timer stops
    property string variant: "main"
    property bool dark: ForkTheme.dark
    // One deterministic frame (aurora at t = 12 s, no twinkle, no satellite or shooting star) for CI
    property bool still: false
    // The header and footer heights: the scrim starts under the header, the mountains stand on the footer
    property real headerHeight: 52
    property real footerHeight: 36
    // the aurora's renderer: "auto" (GPU shaders, Canvas in software rendering), "gpu" or "canvas"
    property string auroraMode: "auto"

    // False when the window isn't visible or active, under Reduce Motion, in still mode, or with no sky
    readonly property bool running: variant !== "none" && !still && !ForkTheme.reduceMotion
                                    && visible && Window.window !== null && Window.window.visible && Window.active
    readonly property bool night: dark && variant === "main"
    readonly property bool shown: variant !== "none"

    // Milliseconds of animation time; only advances while running
    property real elapsed: 0
    readonly property int tick: Math.floor(elapsed / 1100)
    readonly property real fieldAngle: elapsed * 0.025 / 1100
    // Aurora's clock: starts where the still frame is, so the first moving frame matches it
    readonly property real auroraTime: 12000 + elapsed
    readonly property real fieldScale: Math.max(1, width / 1280, height / 900)

    function dumpAurora(prefix) { aurora.dump(prefix) }
    readonly property real auroraDrawMs: aurora.drawMs

    Accessible.ignored: true
    activeFocusOnTab: false
    visible: shown

    Timer {
        id: clock
        property real last: 0
        interval: 33
        repeat: true
        running: root.running
        onRunningChanged: if (running) last = Date.now()
        onTriggered: {
            var now = Date.now()
            root.elapsed += Math.min(now - last, 100)
            last = now
        }
    }

    // ---- the sky stack. Everything the scrim blurs is inside `skyContent`
    Item {
        id: skyContent
        anchors.fill: parent

        // 1.1 background gradient over the whole window, under both bars
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: root.dark ? "#05070F" : "#E4E0FA" }
                GradientStop { position: root.dark ? 0.4 : 0.45; color: root.dark ? "#0A0E20" : "#EFEAF7" }
                GradientStop { position: 0.78; color: root.dark ? "#111833" : "#F5EDEE" }
                GradientStop { position: 1; color: root.dark ? "#18204A" : "#F9EFE8" }
            }
        }

        // 1.3 dawn curtains (light, main variant)
        ForkSkyDawn {
            anchors.fill: parent
            visible: root.variant === "main" && !root.dark
            running: root.running
            still: root.still || ForkTheme.reduceMotion
        }

        // 1.4-1.5 canvas aurora (night, main variant)
        ForkSkyAurora {
            id: aurora
            visible: root.night
            mode: root.auroraMode
            active: root.night && (root.running || root.still || ForkTheme.reduceMotion)
            skyWidth: root.width
            skyHeight: root.height
            time: (root.still || ForkTheme.reduceMotion) ? 12000 : root.auroraTime
        }

        // 1.2 star field, Milky Way (main, night) / the library's still stars
        ForkSkyStars {
            anchors.fill: parent
            visible: root.dark && root.shown
            library: root.variant === "library"
            tick: root.running ? root.tick : 0
            angle: root.running ? root.fieldAngle : 0
            animated: root.running
            fieldScale: root.fieldScale
        }

        // 1.6-1.8 Big Dipper, satellite, shooting star
        ForkSkyNight {
            anchors.fill: parent
            visible: root.night
            showDipper: false
            tick: root.running ? root.tick : 0
            active: root.night && !root.still && !ForkTheme.reduceMotion
            running: root.running
            skyWidth: root.width
        }

        // 1.9 horizon glow
        Rectangle {
            visible: root.variant === "main"
            x: 0
            width: parent.width
            height: 260
            y: parent.height - root.footerHeight - 260
            gradient: Gradient {
                GradientStop { position: 0; color: root.dark ? Qt.rgba(70 / 255, 200 / 255, 160 / 255, 0) : Qt.rgba(255 / 255, 200 / 255, 170 / 255, 0) }
                GradientStop { position: 1; color: root.dark ? Qt.rgba(70 / 255, 200 / 255, 160 / 255, 0.2) : Qt.rgba(255 / 255, 200 / 255, 170 / 255, 0.4) }
            }
        }

        // 1.10 mountains: far then near, stretched to the width, 160 px tall, standing on the footer
        Item {
            x: 0
            width: parent.width
            height: 160
            y: parent.height - root.footerHeight - 160
            Shape {
                width: 1280; height: 160
                transform: Scale { xScale: root.width / 1280 }
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: root.dark ? "#0D1A2C" : "#D8D2EE"
                    strokeColor: "transparent"
                    PathSvg { path: "M0 90L80 60L150 78L230 40L310 70L380 52L460 82L560 48L640 72L720 38L800 66L880 50L960 76L1040 44L1120 70L1200 54L1280 74L1280 160L0 160Z" }
                }
                ShapePath {
                    fillColor: root.dark ? "#07090F" : "#C9C1E6"
                    strokeColor: "transparent"
                    PathSvg { path: "M0 120L60 104L120 116L190 92L260 112L330 100L420 124L500 106L590 118L680 98L760 120L840 108L930 126L1010 104L1090 118L1180 100L1280 114L1280 160L0 160Z" }
                }
            }
        }
    }

    // ---- 2 scrim: the sky behind the heading, blurred, tinted and faded out
    ForkSkyScrim {
        visible: root.variant === "main"
        x: 0
        y: root.headerHeight
        width: parent.width
        height: 190
        source: skyContent
        dark: root.dark
        refresh: root.running
    }

    // the Big Dipper stays crisp through the scrim on the canvas
    ForkSkyNight {
        anchors.fill: parent
        visible: root.night
        showMovers: false
        tick: root.running ? root.tick : 0
        running: root.running
        skyWidth: root.width
    }
}
