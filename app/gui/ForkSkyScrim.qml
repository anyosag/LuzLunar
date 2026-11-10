// [fork] The frosted band under the header (Main.dc.html 1632, sky-chrome.md 4.11): the sky behind it
// blurred (18 px) and slightly saturated, tinted, and faded out over its last 30 %. Decorative.
import QtQuick
import QtQuick.Effects

Item {
    id: scrim

    // The sky to blur (everything below the scrim)
    property Item source
    property bool dark: true
    // true while the sky behind moves: the copy is refreshed ten times a second
    property bool refresh: false

    clip: true

    function update() { copy.scheduleUpdate() }
    onDarkChanged: Qt.callLater(update)
    onWidthChanged: Qt.callLater(update)
    onYChanged: Qt.callLater(update)
    Component.onCompleted: Qt.callLater(update)
    Timer { interval: 100; repeat: true; running: scrim.refresh && scrim.visible; onTriggered: scrim.update() }
    Timer { interval: 300; running: scrim.visible; onTriggered: scrim.update() }

    ShaderEffectSource {
        id: copy
        visible: false
        sourceItem: scrim.source
        sourceRect: Qt.rect(0, scrim.y, scrim.width, scrim.height)
        width: scrim.width; height: scrim.height
        live: false
        hideSource: false
    }

    Rectangle {
        id: maskItem
        visible: false
        anchors.fill: parent
        layer.enabled: true
        gradient: Gradient {
            GradientStop { position: 0; color: "#FF000000" }
            GradientStop { position: 0.7; color: "#FF000000" }
            GradientStop { position: 1; color: "#00000000" }
        }
    }

    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: maskItem
            maskThresholdMin: 0.0
            maskSpreadAtMin: 0.0
        }
        MultiEffect {
            anchors.fill: parent
            source: copy
            blurEnabled: true
            // sigma 18: blurMax 64 at 0.93 measures about 18 px
            blurMax: 64
            blur: 0.93
            saturation: 0.1
            autoPaddingEnabled: false
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: scrim.dark ? Qt.rgba(6 / 255, 8 / 255, 18 / 255, 0.42) : Qt.rgba(250 / 255, 250 / 255, 252 / 255, 0.5) }
                GradientStop { position: 0.6; color: scrim.dark ? Qt.rgba(6 / 255, 8 / 255, 18 / 255, 0.26) : Qt.rgba(250 / 255, 250 / 255, 252 / 255, 0.3) }
                GradientStop { position: 1; color: scrim.dark ? Qt.rgba(6 / 255, 8 / 255, 18 / 255, 0) : Qt.rgba(250 / 255, 250 / 255, 252 / 255, 0) }
            }
        }
    }
}
