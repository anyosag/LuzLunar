import QtQuick
import ForkTheme 1.0

// [fork] A chip of a PC card: an icon and a label. `warm` is the orange button chip (Update Apollo).
Item {
    id: chip

    property string text: ""
    property string iconName: ""
    property color ink: ForkTheme.cv.text2
    property bool warm: false
    property bool big: true

    signal clicked()

    implicitWidth: row.implicitWidth + (big ? 20 : 17)
    implicitHeight: big ? 28 : 24
    width: implicitWidth
    height: implicitHeight

    Accessible.role: warm ? Accessible.Button : Accessible.StaticText
    Accessible.name: text
    Accessible.onPressAction: if (warm) chip.clicked()

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: chip.warm ? (ForkTheme.dark ? Qt.rgba(1, 159 / 255, 10 / 255, 0.12) : Qt.rgba(168 / 255, 90 / 255, 0, 0.07)) : ForkTheme.cv.chip
        border.width: chip.warm ? 1 : 0
        border.color: ForkTheme.dark ? Qt.rgba(1, 159 / 255, 10 / 255, 0.4) : Qt.rgba(168 / 255, 90 / 255, 0, 0.3)
    }

    Row {
        id: row
        x: chip.big ? 9 : 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: chip.big ? 6 : 5

        ForkPathIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: chip.iconName
            size: chip.big ? 14 : 12
            color: chip.ink
            strokeWidth: chip.big ? 1.9 : 2
        }
        ForkCanvasText {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.text
            color: chip.ink
            px: chip.big ? 12 : 11.5
            weight: chip.warm ? 600 : 500
        }
    }

    TapHandler {
        enabled: chip.warm
        onTapped: chip.clicked()
    }
    HoverHandler {
        enabled: chip.warm
        cursorShape: Qt.PointingHandCursor
    }
}
