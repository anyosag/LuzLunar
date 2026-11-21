// [fork] "Looking for PCs on your network": a 30 px pill with a green dot in a static halo
// (carousel.md §2.6). `text` follows the discovery state; `active` is false when discovery is off.
// With `warn` (macOS blocks LuzLunar's Local Network access, ForkLocalNetwork) the dot is amber and
// the pill is a button: `clicked` opens System Settings.
import QtQuick
import ForkTheme

Rectangle {
    id: pill

    property string text: qsTr("Looking for PCs on your network")
    property bool active: true
    property bool warn: false

    signal clicked()

    implicitWidth: label.x + label.implicitWidth + 14
    implicitHeight: 30
    radius: 15
    color: warn ? ForkTheme.warnBg : ForkTheme.cv.chip
    border.width: warn ? 1 : 0
    border.color: ForkTheme.warnLine

    Accessible.role: warn ? Accessible.Button : Accessible.StaticText
    Accessible.name: text
    Accessible.onPressAction: if (warn) pill.clicked()

    Rectangle {
        id: halo
        x: 12 - 4
        anchors.verticalCenter: parent.verticalCenter
        width: 16; height: 16; radius: 8
        color: pill.active && !pill.warn ? ForkTheme.cv.discRing : "transparent"
        Accessible.ignored: true
        Rectangle {
            anchors.centerIn: parent
            width: 8; height: 8; radius: 4
            color: pill.warn ? ForkTheme.st.amber : pill.active ? ForkTheme.st.green : ForkTheme.cv.faint
        }
    }

    ForkCanvasText {
        id: label
        x: 12 + 8 + 10
        anchors.verticalCenter: parent.verticalCenter
        text: pill.text
        px: 12.5
        color: pill.warn ? ForkTheme.warnText : ForkTheme.cv.muted
    }

    MouseArea {
        anchors.fill: parent
        enabled: pill.warn
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.clicked()
    }
}
