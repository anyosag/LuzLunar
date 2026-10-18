import QtQuick

import ForkTheme 1.0
import StreamingPreferences 1.0

// [fork] The top of Your PCs: the title, and whether LuzLunar is looking for PCs on the network
// (on the title's baseline, at the right). The gaps above and below are the design's page rhythm.
Item {
    id: header

    implicitHeight: title.y + title.height + 28

    ForkText {
        id: title
        y: 36
        anchors.left: parent.left
        kind: "title"
        pixelSize: 44
        text: qsTr("Your PCs")
        Accessible.role: Accessible.Heading
    }

    ForkText {
        id: discoveryText
        anchors.right: parent.right
        anchors.baseline: title.baseline
        visible: header.width > 520
        kind: "body"
        font.pixelSize: 14
        color: ForkTheme.muted
        wrapMode: Text.NoWrap
        text: StreamingPreferences.enableMdns ? qsTr("Looking for more PCs on your network")
                                              : qsTr("Automatic PC discovery is off. Add PCs by their address.")
    }

    // A dot that sends out a ring while discovery runs; still with Reduce Motion
    Item {
        anchors.right: discoveryText.left
        anchors.rightMargin: 10
        anchors.verticalCenter: discoveryText.verticalCenter
        width: 8
        height: 8
        visible: discoveryText.visible && StreamingPreferences.enableMdns

        Rectangle {
            id: ring
            anchors.centerIn: parent
            visible: !ForkTheme.reduceMotion
            width: 8
            height: width
            radius: width / 2
            color: ForkTheme.ok

            ParallelAnimation {
                running: ring.visible && header.visible
                loops: Animation.Infinite
                NumberAnimation { target: ring; property: "width"; from: 8; to: 26; duration: 2000; easing.type: Easing.OutCubic }
                NumberAnimation { target: ring; property: "opacity"; from: 0.5; to: 0; duration: 2000; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: ForkTheme.ok
        }
    }
}
