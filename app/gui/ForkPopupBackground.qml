import QtQuick
import QtQuick.Effects

import ForkTheme 1.0

// [fork] The panel behind menus and drop-down lists (and, rounder, dialogs): the surface color,
// a hairline border and the design's soft shadow (0 18 48, darker in dark mode). The shadow is a
// separate layer, so the panel still draws where effects can't (the software renderer of
// offscreen screenshots).
Item {
    property real radius: ForkTheme.radiusMenu

    Rectangle {
        anchors.fill: parent
        visible: GraphicsInfo.api !== GraphicsInfo.Software
        radius: parent.radius
        color: ForkTheme.surface

        layer.enabled: visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: ForkTheme.shadow
            blurMax: 48
            shadowBlur: 1.0
            shadowVerticalOffset: 18
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: ForkTheme.surface
        border.width: 1
        border.color: ForkTheme.line
    }
}
