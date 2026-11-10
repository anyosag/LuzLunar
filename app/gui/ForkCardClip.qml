import QtQuick
import QtQuick.Effects

// [fork] Clips its children to a rounded rectangle, and can dim them the way the canvas dims an
// asleep PC's tiles (`saturate(0.8) brightness(0.88)` at dim = 1). MultiEffect's saturation and
// brightness are close to, not the same math as, the CSS filter.
Item {
    id: clip

    property real radius: 12
    property color background: "transparent"
    // 0 = as drawn, 1 = fully dimmed
    property real dim: 0
    default property alias content: holder.data

    Item {
        id: source
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true

        Rectangle {
            anchors.fill: parent
            radius: clip.radius
            color: clip.background
        }
        Item {
            id: holder
            anchors.fill: parent
        }
    }

    Item {
        id: maskItem
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true
        Rectangle {
            anchors.fill: parent
            radius: clip.radius
            color: "black"
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: source
        maskEnabled: true
        maskSource: maskItem
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
        saturation: -0.2 * clip.dim
        brightness: -0.12 * clip.dim
    }
}
