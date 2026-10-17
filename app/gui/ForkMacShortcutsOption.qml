import QtQuick
import QtQuick.Controls

import ForkPreferences 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0

// Under "Capture system keyboard shortcuts" in SettingsView (macOS): which Mac shortcuts capture takes
// from the Mac and sends to the host. forksystemshortcuts.cpp applies it while streaming.
Column {
    id: macShortcutsOption

    readonly property bool captureOn: StreamingPreferences.captureSysKeysMode !== StreamingPreferences.CSK_OFF

    visible: SystemProperties.isDarwin
    leftPadding: 20
    spacing: 5

    Label {
        width: parent.width - parent.leftPadding
        text: !ForkPreferences.macShortcutsSelectable
              ? qsTr("This macOS doesn't let LuzLunar pick shortcuts, so while capturing, the Mac keeps them all unless every shortcut goes to the host.")
              : macShortcutsOption.captureOn
                ? qsTr("Checked Mac shortcuts go to the host PC while capturing; the rest stay with the Mac. Keys arrive after the Mac key remapping (Keyboard & Clipboard), so ⌘Space arrives as Ctrl+Space and ⌃← as Win+←. Force Quit (⌥⌘Esc) always stays with the Mac, and Ctrl+Option+Shift+K gives the Mac its shortcuts back for the rest of a stream.")
                : qsTr("Turn on capture to send these Mac shortcuts to the host PC.")
        font.pointSize: 9
        wrapMode: Text.Wrap
    }

    Repeater {
        model: SystemProperties.isDarwin ? ForkPreferences.macShortcutGroups() : []

        delegate: CheckBox {
            width: macShortcutsOption.width - macShortcutsOption.leftPadding
            hoverEnabled: true
            text: modelData.label
            font.pointSize: 12
            enabled: macShortcutsOption.captureOn && ForkPreferences.macShortcutsSelectable && !ForkPreferences.macShortcutsAll

            Component.onCompleted: {
                checked = ForkPreferences.macShortcutToHost(modelData.key)
            }

            // ::onToggled only fires when a person changes it
            onToggled: {
                ForkPreferences.setMacShortcutToHost(modelData.key, checked)
            }
        }
    }

    CheckBox {
        width: parent.width - parent.leftPadding
        hoverEnabled: true
        text: qsTr("Send every Mac shortcut to the host, screenshots included")
        font.pointSize: 12
        enabled: macShortcutsOption.captureOn
        checked: ForkPreferences.macShortcutsAll
        onToggled: {
            ForkPreferences.macShortcutsAll = checked
        }

        ToolTip.delay: 1000
        ToolTip.timeout: 10000
        ToolTip.visible: hovered
        ToolTip.text: qsTr("Moonlight's behavior: while capturing, every system shortcut goes to the host, including screenshots (⇧⌘4) and other apps' global shortcuts.")
    }
}
