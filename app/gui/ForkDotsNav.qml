// [fork] "Pick a PC": one chip per PC (and Add a PC) in the PC's own color, the selected one a
// pill, and, in the autoplay demo, a divider and the Pause demo button (carousel.md §3.9, §5).
import QtQuick
import ForkTheme

Item {
    id: nav

    // [{ name, dot }]: dot is a color
    property var chips: []
    property int current: 0
    property bool showDemo: false
    property bool demoOn: false
    signal picked(int index)
    signal toggleDemo()

    implicitHeight: 28
    implicitWidth: row.width
    Accessible.role: Accessible.PageTabList
    Accessible.name: qsTr("Pick a PC")

    Row {
        id: row
        spacing: 6
        anchors.horizontalCenter: parent.horizontalCenter
        height: 28

        Repeater {
            model: nav.chips
            delegate: Rectangle {
                id: chip
                required property var modelData
                required property int index
                readonly property bool sel: index === nav.current
                width: chipRow.width + 24
                height: 28
                radius: 14
                color: sel ? ForkTheme.cv.surface : "transparent"
                border.width: 1
                border.color: sel ? ForkTheme.cv.lineStrong : "transparent"
                Behavior on color { enabled: !ForkTheme.reduceMotion; ColorAnimation { duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] } }
                Behavior on border.color { enabled: !ForkTheme.reduceMotion; ColorAnimation { duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] } }

                Accessible.role: Accessible.Button
                Accessible.name: modelData.name
                Accessible.checked: sel
                Accessible.onPressAction: nav.picked(index)

                Row {
                    id: chipRow
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; radius: 4
                        color: chip.modelData.dot
                        Accessible.ignored: true
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.name
                        font.family: ForkTheme.uiFamily
                        font.pixelSize: 12.5
                        font.weight: chip.sel ? 600 : 500
                        color: chip.sel ? ForkTheme.cv.text : ForkTheme.cv.muted
                        Behavior on color { enabled: !ForkTheme.reduceMotion; ColorAnimation { duration: 250 } }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: nav.picked(chip.index)
                }
            }
        }

        Rectangle {
            visible: nav.showDemo
            anchors.verticalCenter: parent.verticalCenter
            width: 13; height: 18
            color: "transparent"
            Rectangle { x: 6; width: 1; height: 18; color: ForkTheme.cv.lineStrong }
            Accessible.ignored: true
        }

        Rectangle {
            id: demoBtn
            visible: nav.showDemo
            height: 28
            width: demoRow.width + 22
            radius: 14
            color: ForkTheme.cv.chip
            border.width: 1
            border.color: ForkTheme.cv.line
            Accessible.role: Accessible.CheckBox
            Accessible.name: nav.demoOn ? qsTr("Pause demo") : qsTr("Play demo")
            Accessible.checked: nav.demoOn
            Accessible.onPressAction: nav.toggleDemo()
            Row {
                id: demoRow
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                ForkStoryGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    path: nav.demoOn ? "M9 6v12M15 6v12" : "M8 5.8v12.4L18.2 12z"
                    size: 14
                    strokeWidth: 2.2
                    filled: !nav.demoOn
                    color: ForkTheme.cv.text2
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: nav.demoOn ? qsTr("Pause demo") : qsTr("Play demo")
                    font.family: ForkTheme.uiFamily
                    font.pixelSize: 12.5
                    font.weight: 500
                    color: ForkTheme.cv.text2
                }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: nav.toggleDemo() }
        }
    }
}
