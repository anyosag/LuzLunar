// [fork] "Tonight's moon": the phase name, how much is lit and when it's next full (or, once it
// wanes, when it's new), and a 48 px disc with the lit part drawn (carousel.md §2.5). The moon is
// where the Moon and the Sun actually are (ForkMoonPhase.js), not the canvas's mean lunar month,
// which put it up to 17 hours off. `nowMs` can be pinned for screenshots.
import QtQuick
import QtQuick.Shapes
import ForkPcPrefs // [fork] screenshot runs use the geometry renderer (a hidden grab drops curve shapes)
import QtQuick.Effects
import ForkTheme
import "ForkMoonPhase.js" as MoonPhase

Item {
    id: moon

    property double nowMs: Date.now()
    readonly property var info: compute(nowMs)
    property alias phaseName: nameText.text

    implicitWidth: textCol.width + 12 + 48
    implicitHeight: 49

    Accessible.role: Accessible.StaticText
    Accessible.name: qsTr("Tonight's moon: %1, %2").arg(info.name).arg(info.line)

    function compute(ms) {
        var m = MoonPhase.at(ms)
        var phase = m.phase
        var name = phase < 0.034 ? qsTr("New moon") : phase < 0.216 ? qsTr("Waxing crescent") : phase < 0.284 ? qsTr("First quarter")
                 : phase < 0.466 ? qsTr("Waxing gibbous") : phase < 0.534 ? qsTr("Full moon") : phase < 0.716 ? qsTr("Waning gibbous")
                 : phase < 0.784 ? qsTr("Last quarter") : phase < 0.966 ? qsTr("Waning crescent") : qsTr("New moon")
        var R = 19
        var rx = Math.max(0.001, Math.abs(Math.cos(2 * Math.PI * phase)) * R)
        var d = phase < 0.5
            ? "M0 " + (-R) + "A" + R + " " + R + " 0 0 1 0 " + R + "A" + rx + " " + R + " 0 0 " + (phase < 0.25 ? 0 : 1) + " 0 " + (-R) + "Z"
            : "M0 " + (-R) + "A" + R + " " + R + " 0 0 0 0 " + R + "A" + rx + " " + R + " 0 0 " + (phase < 0.75 ? 0 : 1) + " 0 " + (-R) + "Z"
        // Waxing, the days to full; once it wanes, "full last night" for a day, then the days to new
        // (the canvas counted to the next full moon all month, so the day after one it said "Full
        // moon · 100% lit · full in 29 days")
        var when
        if (m.waxing) {
            var toFull = Math.round(m.toFull)
            when = toFull === 0 ? qsTr("full tonight") : toFull === 1 ? qsTr("full in 1 day") : qsTr("full in %1 days").arg(toFull)
        } else {
            var sinceFull = Math.round(m.sinceFull)
            var toNew = Math.round(m.toNew)
            when = sinceFull === 0 ? qsTr("full tonight") : sinceFull === 1 ? qsTr("full last night")
                 : toNew === 0 ? qsTr("new tonight") : toNew === 1 ? qsTr("new in 1 day") : qsTr("new in %1 days").arg(toNew)
        }
        var line = qsTr("%1% lit · %2").arg(Math.round(m.lit * 100)).arg(when)
        return { d: d, name: name, line: line, phase: phase, visible: m.lit > 0.004 }
    }

    Column {
        id: textCol
        anchors.right: disc.left
        anchors.rightMargin: 12
        y: 0
        spacing: 1
        ForkCanvasText {
            anchors.right: parent.right
            text: qsTr("Tonight’s moon")
            px: 10.5
            weight: 700
            tracking: 1.26
            upper: true
            color: ForkTheme.cv.faint
        }
        ForkCanvasText {
            id: nameText
            anchors.right: parent.right
            text: moon.info.name
            px: 14
            weight: 650
            height: 19
            verticalAlignment: Text.AlignVCenter
            color: ForkTheme.cv.text
        }
        ForkCanvasText {
            anchors.right: parent.right
            text: moon.info.line
            px: 12
            color: ForkTheme.cv.muted
        }
    }

    Item {
        id: disc
        width: 48; height: 48
        anchors.right: parent.right
        y: 0.5
        Accessible.ignored: true

        Rectangle { anchors.centerIn: parent; width: 46; height: 46; radius: 23; color: "#141936" }
        Rectangle {
            anchors.centerIn: parent
            width: 39; height: 39; radius: 19.5
            color: Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.08)
            border.width: 1
            border.color: Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.35)
        }
        Item {
            id: lit
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.55)
                shadowBlur: 0.55
                shadowOpacity: 1
                autoPaddingEnabled: true
            }
            Shape {
                x: 24; y: 24
                visible: moon.info.visible
                preferredRendererType: ForkPcPrefs.screenshotMode ? Shape.GeometryRenderer : Shape.CurveRenderer
                ShapePath {
                    fillColor: "#F5C878"
                    strokeColor: "transparent"
                    PathSvg { path: moon.info.d }
                }
            }
        }
    }
}
