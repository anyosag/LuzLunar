import QtQuick

import ForkTheme 1.0
import QtQuick.Templates as T

// [fork] An on/off switch in the theme's gold. It doesn't flip itself: bind checked to the
// setting, and set the setting in onClicked (ForkSwitchRow does).
T.Switch {
    id: control

    checkable: false
    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    padding: 0
    // The track is 52 × 32; the switch takes a 60 × 44 target around it
    implicitWidth: 60
    implicitHeight: 44
    opacity: enabled ? 1 : 0.45

    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: checked

    indicator: Rectangle {
        anchors.centerIn: parent
        width: 52
        height: 32
        radius: 16
        color: control.checked ? ForkTheme.accent : ForkTheme.trackOff
        border.width: 1
        border.color: control.checked ? ForkTheme.selEdge : ForkTheme.trackEdge

        Behavior on color {
            enabled: !ForkTheme.reduceMotion
            ColorAnimation { duration: 150 }
        }

        Item {
            id: knob
            x: control.checked ? parent.width - width - 4 : 4
            y: 4
            width: 24
            height: 24

            Behavior on x {
                enabled: !ForkTheme.reduceMotion
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            // The knob's small shadow
            Rectangle {
                y: 1
                width: parent.width
                height: parent.height
                radius: 12
                color: Qt.rgba(0, 0, 0, 0.2)
            }

            Rectangle {
                anchors.fill: parent
                radius: 12
                color: control.checked ? ForkTheme.knobOn : ForkTheme.knobOff
            }
        }

        // The focus ring, 2 pt outside the track
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            visible: control.visualFocus
            radius: 20
            color: "transparent"
            border.width: 2
            border.color: ForkTheme.selEdge
        }
    }

    contentItem: Item {}
}
