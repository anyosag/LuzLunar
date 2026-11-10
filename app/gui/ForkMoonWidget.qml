// [fork] "Tonight's moon": the phase name, how much is lit and when it's full, and a 48 px disc with
// the lit part drawn from today's date (carousel.md §2.5, the canvas's formula: the mean lunar month
// counted from the new moon of 6 Jan 2000 18:14 UTC). `nowMs` can be pinned for screenshots.
import QtQuick
import QtQuick.Shapes
import ForkPcPrefs // [fork] screenshot runs use the geometry renderer (a hidden grab drops curve shapes)
import QtQuick.Effects
import ForkTheme

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
        var synodic = 29.530588853
        var age = ((((ms - Date.UTC(2000, 0, 6, 18, 14)) / 86400000) % synodic) + synodic) % synodic
        var phase = age / synodic
        var lit = (1 - Math.cos(2 * Math.PI * phase)) / 2
        var name = phase < 0.034 ? qsTr("New moon") : phase < 0.216 ? qsTr("Waxing crescent") : phase < 0.284 ? qsTr("First quarter")
                 : phase < 0.466 ? qsTr("Waxing gibbous") : phase < 0.534 ? qsTr("Full moon") : phase < 0.716 ? qsTr("Waning gibbous")
                 : phase < 0.784 ? qsTr("Last quarter") : phase < 0.966 ? qsTr("Waning crescent") : qsTr("New moon")
        var R = 19
        var rx = Math.max(0.001, Math.abs(Math.cos(2 * Math.PI * phase)) * R)
        var d = phase < 0.5
            ? "M0 " + (-R) + "A" + R + " " + R + " 0 0 1 0 " + R + "A" + rx + " " + R + " 0 0 " + (phase < 0.25 ? 0 : 1) + " 0 " + (-R) + "Z"
            : "M0 " + (-R) + "A" + R + " " + R + " 0 0 0 0 " + R + "A" + rx + " " + R + " 0 0 " + (phase < 0.75 ? 0 : 1) + " 0 " + (-R) + "Z"
        var toFull = Math.round(((phase < 0.5 ? 0.5 : 1.5) - phase) * synodic)
        var pct = Math.round(lit * 100)
        var line = toFull === 0 ? qsTr("%1% lit · full tonight").arg(pct)
                 : (toFull === 1 ? qsTr("%1% lit · full in 1 day").arg(pct) : qsTr("%1% lit · full in %2 days").arg(pct).arg(toFull))
        return { d: d, name: name, line: line, phase: phase, visible: lit > 0.004 }
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
