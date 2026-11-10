// [fork] The sky's star field: the Milky Way and 390 stars on a 1500 x 1500 field that turns about a
// point above the cards (Main.dc.html 1199-1234, sky-chrome.md 4.2), or, for the All apps page,
// its 80 still stars (Library.dc.html 617-630, Appendix B.1). Decorative.
import QtQuick

Item {
    id: stars

    property bool library: false
    // The twinkle clock (one step per 1100 ms) and the field's turn, in degrees
    property int tick: 0
    property real angle: 0
    property bool animated: false
    property real fieldScale: 1

    // mulberry32 with the canvas's seed: the same numbers as the JS board, so the field matches
    function mainStars() {
        var s = 20261109
        function rnd() {
            s = (s + 0x6D2B79F5) | 0
            var x = Math.imul(s ^ (s >>> 15), 1 | s)
            x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) ^ x
            return ((x ^ (x >>> 14)) >>> 0) / 4294967296
        }
        var colors = ["#FFFFFF", "#FFFFFF", "#D6E4FF", "#FFEBC8"]
        var out = []
        for (var k = 0; k < 390; k++) {
            var band = k >= 300
            var x, y
            if (band) {
                var u = rnd()
                x = -150 + u * 1800
                y = 1010 - u * 576 + (rnd() - 0.5) * 130
            } else {
                x = rnd() * 1500
                y = rnd() * 1500
            }
            var r = rnd()
            var size = r < 0.72 ? 1 : r < 0.95 ? 1.6 : 2.4
            var color = colors[Math.floor(rnd() * colors.length)]
            var bright = band ? 0.25 + rnd() * 0.45 : 0.35 + rnd() * 0.6
            out.push({ k: k, x: Math.round(x * 10) / 10, y: Math.round(y * 10) / 10, size: size, color: color,
                       bright: Math.round(bright * 100) / 100 })
        }
        return out
    }

    // Park-Miller, seed 9157; each star's draws in the canvas's order
    function libraryStars() {
        var seed = 9157
        function rnd() {
            seed = (seed * 16807) % 2147483647
            return seed / 2147483647
        }
        var out = []
        for (var k = 0; k < 80; k++) {
            var size = rnd() < 0.8 ? 1 : 2
            var left = Math.round(rnd() * 1280)
            var top = Math.round(rnd() * 760)
            var op = Math.round((0.3 + rnd() * 0.6) * 100) / 100
            out.push({ k: k, x: left, y: top, size: size, color: "#FFFFFF", bright: op })
        }
        return out
    }

    // The 390 stars: nothing to do in the library variant, and the field is built once
    property var fieldData: library ? [] : mainStars()
    property var libData: library ? libraryStars() : []

    // ---- the turning field
    Item {
        id: field
        visible: !stars.library
        width: 1500; height: 1500
        x: stars.width / 2 - 750
        y: 380 - 750
        scale: stars.fieldScale
        rotation: stars.angle

        // The Milky Way: a soft band rising to the right (blur 14 px on the canvas)
        Rectangle {
            x: -350; y: 615
            width: 2200; height: 260
            rotation: -17.7
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(160 / 255, 150 / 255, 1, 0) }
                GradientStop { position: 0.35; color: Qt.rgba(160 / 255, 150 / 255, 1, 0.07) }
                GradientStop { position: 0.5; color: Qt.rgba(225 / 255, 215 / 255, 1, 0.11) }
                GradientStop { position: 0.65; color: Qt.rgba(160 / 255, 150 / 255, 1, 0.07) }
                GradientStop { position: 1; color: Qt.rgba(160 / 255, 150 / 255, 1, 0) }
            }
        }

        Repeater {
            model: stars.fieldData
            delegate: Item {
                id: st
                required property var modelData
                readonly property bool dimNow: (stars.tick + modelData.k) % 4 === 0
                x: modelData.x; y: modelData.y
                width: modelData.size; height: modelData.size
                opacity: dimNow ? modelData.bright * 0.3 : modelData.bright
                Behavior on opacity {
                    enabled: stars.animated
                    NumberAnimation {
                        duration: 900 + (st.modelData.k % 5) * 280
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.42, 0, 0.58, 1, 1, 1]
                    }
                }
                // box-shadow: 0 0 6px <color> on the 2.4 px stars
                Loader {
                    active: st.modelData.size > 2
                    anchors.centerIn: parent
                    sourceComponent: Item {
                        Repeater {
                            model: [[10, 0.10], [7.5, 0.14], [5.2, 0.2]]
                            Rectangle {
                                required property var modelData
                                width: modelData[0]; height: modelData[0]; radius: width / 2
                                x: (st.width - width) / 2; y: (st.height - height) / 2
                                color: st.modelData.color; opacity: modelData[1]
                            }
                        }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: st.modelData.color
                    antialiasing: true
                }
            }
        }
    }

    // ---- the All apps page's own still stars
    Repeater {
        model: stars.libData
        delegate: Rectangle {
            required property var modelData
            x: modelData.x; y: modelData.y
            width: modelData.size; height: modelData.size
            radius: width / 2
            color: "#FFFFFF"
            opacity: modelData.bright
        }
    }
}
