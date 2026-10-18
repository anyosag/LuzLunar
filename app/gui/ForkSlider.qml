import QtQuick

import ForkTheme 1.0
import QtQuick.Templates as T

// [fork] A slider with a gold fill, for the bitrate
T.Slider {
    id: control

    implicitWidth: 300
    implicitHeight: 32
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    snapMode: T.Slider.SnapOnRelease
    opacity: enabled ? 1 : 0.5

    // A gold fill over a visible track, and a solid gold thumb
    background: Rectangle {
        x: control.leftPadding
        y: control.topPadding + (control.availableHeight - height) / 2
        width: control.availableWidth
        height: 6
        radius: 3
        color: ForkTheme.lineStrong

        Rectangle {
            width: control.visualPosition * parent.width
            height: parent.height
            radius: 3
            color: ForkTheme.accent
        }
    }

    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + (control.availableHeight - height) / 2
        width: 20
        height: 20
        radius: 10
        color: control.pressed ? Qt.darker(ForkTheme.accent, 1.06) : ForkTheme.accent
        border.width: 1
        border.color: ForkTheme.selEdge

        // The focus ring, 2 pt outside the thumb
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            visible: control.visualFocus
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: ForkTheme.selEdge
        }
    }
}
