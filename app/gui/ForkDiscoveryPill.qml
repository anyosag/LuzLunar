// [fork] "Looking for PCs on your network": a 30 px pill with a green dot in a static halo
// (carousel.md §2.6). `text` follows the discovery state; `active` is false when discovery is off.
import QtQuick
import ForkTheme

Rectangle {
    id: pill

    property string text: qsTr("Looking for PCs on your network")
    property bool active: true

    implicitWidth: label.x + label.implicitWidth + 14
    implicitHeight: 30
    radius: 15
    color: ForkTheme.cv.chip

    Accessible.role: Accessible.StaticText
    Accessible.name: text

    Rectangle {
        id: halo
        x: 12 - 4
        anchors.verticalCenter: parent.verticalCenter
        width: 16; height: 16; radius: 8
        color: pill.active ? ForkTheme.cv.discRing : "transparent"
        Accessible.ignored: true
        Rectangle {
            anchors.centerIn: parent
            width: 8; height: 8; radius: 4
            color: pill.active ? ForkTheme.st.green : ForkTheme.cv.faint
        }
    }

    Text {
        id: label
        x: 12 + 8 + 10
        anchors.verticalCenter: parent.verticalCenter
        text: pill.text
        font.family: ForkTheme.uiFamily
        font.pixelSize: 12.5
        color: ForkTheme.cv.muted
    }
}
