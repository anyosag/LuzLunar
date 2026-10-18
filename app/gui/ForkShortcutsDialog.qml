import QtQuick
import QtQuick.Controls

import ForkTheme 1.0
import SystemProperties 1.0

// [fork] Help (the toolbar's ? button and ⌘?): LuzLunar's shortcuts while streaming, as keycaps,
// and a link to the online setup guide
NavigableDialog {
    id: shortcutsDialog

    title: qsTr("Shortcuts while streaming")
    standardButtons: Dialog.Ok

    onOpened: {
        var done = standardButton(Dialog.Ok)
        if (done) {
            done.text = qsTr("Done")
            done.forceActiveFocus(Qt.TabFocusReason)
        }
    }

    Column {
        width: 440
        spacing: 16

        ForkText {
            width: parent.width
            kind: "body"
            font.pixelSize: 14
            color: ForkTheme.text2
            text: qsTr("Hold Control, Option and Shift, then press the key.")
        }

        Column {
            width: parent.width

            Repeater {
                model: [
                    { "key": "Q", "text": qsTr("End the stream") },
                    { "key": "S", "text": qsTr("Show or hide performance stats") },
                    { "key": "Z", "text": qsTr("Let go of a held pointer") },
                    { "key": "M", "text": qsTr("Switch mouse mode") },
                    { "key": "U", "text": qsTr("Send this Mac's clipboard") },
                    { "key": "G", "text": qsTr("Get the PC's clipboard") }
                ]

                delegate: Item {
                    required property var modelData
                    required property int index

                    width: parent.width
                    height: 44

                    Accessible.role: Accessible.StaticText
                    Accessible.name: qsTr("%1: Control-Option-Shift-%2").arg(modelData.text).arg(modelData.key)

                    Rectangle {
                        visible: index > 0
                        width: parent.width
                        height: 1
                        color: ForkTheme.lineSoft
                    }

                    ForkText {
                        anchors.left: parent.left
                        anchors.right: keys.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "label"
                        font.pixelSize: 14
                        font.weight: Font.Normal
                        elide: Text.ElideRight
                        text: modelData.text
                    }

                    ForkKeys {
                        id: keys
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        key: modelData.key
                    }
                }
            }
        }

        ForkButton {
            visible: SystemProperties.hasBrowser
            kind: "link"
            symbol: "arrow.up.right.square"
            symbolSize: 13
            text: qsTr("Setup guide and troubleshooting")
            onClicked: Qt.openUrlExternally("https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide")
        }
    }
}
