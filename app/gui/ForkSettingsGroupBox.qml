import QtQuick 2.9
import QtQuick.Controls 2.2

import ForkPreferences 1.0
import SystemProperties 1.0

// Settings added by the fork, shown in SettingsView between Input and Gamepad settings.
GroupBox {
    id: forkSettingsGroupBox
    padding: 12
    title: "<font color=\"skyblue\">" + qsTr("Mac Keyboard") + "</font>"
    font.pointSize: 12
    visible: SystemProperties.isDarwin

    Column {
        anchors.fill: parent
        spacing: 5

        Label {
            width: parent.width
            text: qsTr("Choose what each Mac modifier key sends to the host PC. Moonlight's own shortcuts (Ctrl+Option+Shift+…) always use the physical keys.")
            font.pointSize: 9
            wrapMode: Text.Wrap
        }

        Repeater {
            model: [
                { "label": qsTr("Command (⌘) sends"), "property": "commandKeyTarget" },
                { "label": qsTr("Control (⌃) sends"), "property": "controlKeyTarget" },
                { "label": qsTr("Option (⌥) sends"), "property": "optionKeyTarget" }
            ]

            delegate: Row {
                spacing: 5
                width: parent.width

                Label {
                    width: 180
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    font.pointSize: 12
                }

                AutoResizingComboBox {
                    // Item order matches ForkPreferences.ModifierTarget
                    model: [qsTr("Nothing"), qsTr("Ctrl"), qsTr("Alt"), qsTr("Windows key")]
                    font.pointSize: 12

                    Component.onCompleted: {
                        currentIndex = ForkPreferences[modelData.property]
                        recalculateWidth()
                    }

                    // ::onActivated must be used, as it only listens for when the index is changed by a human
                    onActivated: {
                        ForkPreferences[modelData.property] = currentIndex
                    }
                }
            }
        }

        Label {
            width: parent.width
            text: qsTr("While streaming with Command not set to the Windows key, Cmd+Q and Cmd+H go to the host instead of quitting or hiding Moonlight. End a stream with Ctrl+Option+Shift+Q.")
            font.pointSize: 9
            wrapMode: Text.Wrap
        }
    }
}
