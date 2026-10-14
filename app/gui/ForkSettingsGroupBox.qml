import QtQuick 2.9
import QtQuick.Controls 2.2

import ForkPreferences 1.0
import SystemProperties 1.0

// Settings added by the fork, shown in SettingsView between Input and Gamepad settings.
GroupBox {
    id: forkSettingsGroupBox
    padding: 12
    title: qsTr("Keyboard & Clipboard") // [fork] plain title for the native style
    font.pointSize: 12

    Column {
        anchors.fill: parent
        spacing: 5

        Label {
            width: parent.width
            visible: SystemProperties.isDarwin
            text: qsTr("Choose what each Mac modifier key sends to the host PC. LuzLunar's own shortcuts (Ctrl+Option+Shift+…) always use the physical keys.")
            font.pointSize: 9
            wrapMode: Text.Wrap
        }

        Repeater {
            model: SystemProperties.isDarwin ? [
                { "label": qsTr("Command (⌘) sends"), "property": "commandKeyTarget" },
                { "label": qsTr("Control (⌃) sends"), "property": "controlKeyTarget" },
                { "label": qsTr("Option (⌥) sends"), "property": "optionKeyTarget" }
            ] : []

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
            visible: SystemProperties.isDarwin
            text: qsTr("While streaming with Command not set to the Windows key, Cmd+Q and Cmd+H go to the host instead of quitting or hiding LuzLunar. End a stream with Ctrl+Option+Shift+Q.")
            font.pointSize: 9
            wrapMode: Text.Wrap
        }

        CheckBox {
            width: parent.width
            visible: SystemProperties.isDarwin
            hoverEnabled: true
            text: qsTr("Show the app, stream stats and messages beside the notch")
            font.pointSize: 12
            checked: ForkPreferences.notchBar
            onCheckedChanged: {
                ForkPreferences.notchBar = checked
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 10000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("On a MacBook with a camera notch, fullscreen streams leave the strip beside the notch empty. This shows the app's name on the left and frame rate, latency, bitrate, codec and loss on the right. Connection warnings and clipboard messages appear beside the notch instead of over the stream.")
        }

        Row {
            spacing: 5
            width: parent.width

            Label {
                width: 180
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Clipboard sync")
                font.pointSize: 12
            }

            AutoResizingComboBox {
                // Item order matches ForkPreferences.ClipboardSyncMode
                model: [qsTr("Off"), qsTr("Shortcuts only"), qsTr("Automatic")]
                font.pointSize: 12

                Component.onCompleted: {
                    currentIndex = ForkPreferences.clipboardSyncMode
                    recalculateWidth()
                }

                // ::onActivated must be used, as it only listens for when the index is changed by a human
                onActivated: {
                    ForkPreferences.clipboardSyncMode = currentIndex
                }
            }
        }

        Label {
            width: parent.width
            text: qsTr("Shares the clipboard with Apollo hosts while streaming: text, formatted text from Word, Excel, PowerPoint and other apps, and images. Formatting and images need LuzLunar's Apollo build; other Apollo versions share text only. Automatic sends your clipboard when you switch to the stream and fetches the PC's when you switch away, transferring only what changed. Ctrl+Option+Shift+U sends and Ctrl+Option+Shift+G fetches at any time. Apollo must give this device its Clipboard permissions.")
            font.pointSize: 9
            wrapMode: Text.Wrap
        }
    }
}
