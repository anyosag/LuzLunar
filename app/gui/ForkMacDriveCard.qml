import QtQuick

import ForkPreferences 1.0
import ForkTheme 1.0

// [fork] Settings › This Mac › "This Mac on the PC": on LAN streams, Apollo shows this Mac's disk on
// the PC as a network drive (macdrive.*). The switch, what macOS still needs for it (File Sharing,
// Windows File Sharing for the account, a share of the whole disk), the password Apollo signs in
// with, and what the last LAN stream got. macOS's settings change in System Settings, so the card
// looks at them again every 2 seconds while it's shown.
ForkCard {
    id: card

    title: qsTr("This Mac on the PC")
    spacing: 8

    property var setup: ForkPreferences.macDriveSetup()

    readonly property string diskName: setup.diskShare !== "" ? setup.diskShare : setup.volumeName

    function refresh() {
        setup = ForkPreferences.macDriveSetup()
    }

    // What's missing, one line each
    function missing() {
        var lines = []
        if (!setup.fileSharing) {
            lines.push(qsTr("File Sharing is off. Turn it on in System Settings › General › Sharing."))
        }
        if (setup.windowsSharing === "off") {
            lines.push(qsTr("Windows can't sign in with your account yet: in Sharing, click ⓘ beside File Sharing, then Options…, and turn on %1 under Windows File Sharing.").arg(setup.userName))
        }
        if (setup.diskShare === "" && !setup.admin) {
            lines.push(qsTr("The PC gets your home folder, not the whole disk: add %1 to Shared Folders (ⓘ beside File Sharing), or use an administrator account.").arg(setup.volumeName))
        }
        if (!setup.passwordSaved) {
            lines.push(qsTr("Save your Mac password below."))
        }
        return lines
    }

    Timer {
        interval: 2000
        repeat: true
        running: card.visible && ForkPreferences.macDrive
        onTriggered: card.refresh()
    }

    Column {
        width: parent.width
        spacing: 0

        ForkSwitchRow {
            showDivider: false
            label: qsTr("Show this Mac's disk on the PC")
            help: qsTr("On streams over your local network to an Apollo PC, File Explorer gets this Mac's disk as a drive named after this Mac, until a minute after the stream ends. Apollo signs in to this Mac's File Sharing with your account. Streams over a VPN or the internet leave it out.")
            checked: ForkPreferences.macDrive
            onToggled: (on) => {
                ForkPreferences.macDrive = on
                card.refresh()
            }
        }
    }

    Column {
        visible: ForkPreferences.macDrive
        width: parent.width
        spacing: 14

        ForkWarnBox {
            warnings: card.missing()
            okText: qsTr("Ready: on LAN streams, the PC shows %1 as a drive.").arg(card.diskName)
        }

        // An administrator without a share of the disk relies on macOS's own share of each volume
        ForkText {
            width: parent.width
            visible: card.setup.diskShare === "" && card.setup.admin
            kind: "help"
            text: qsTr("If the PC gets only your home folder, add %1 to Shared Folders (ⓘ beside File Sharing in System Settings › General › Sharing).").arg(card.setup.volumeName)
        }

        ForkButton {
            symbol: "folder.badge.person.crop"
            text: qsTr("Open Sharing Settings")
            onClicked: ForkPreferences.openSharingSettings()
        }

        // The password Apollo signs in to this Mac with
        Column {
            width: parent.width
            spacing: 8

            ForkText {
                kind: "label"
                font.weight: Font.DemiBold
                text: qsTr("Mac password")
            }

            ForkText {
                width: parent.width
                kind: "help"
                text: qsTr("The password of %1, this Mac's account. LuzLunar checks it and keeps it in your keychain.").arg(card.setup.userName)
            }

            Row {
                visible: !card.setup.passwordSaved
                spacing: 10

                ForkTextField {
                    id: passwordField
                    width: 260
                    echoMode: TextInput.Password
                    placeholderText: qsTr("Password for %1").arg(card.setup.userName)
                    Accessible.name: qsTr("Mac password")
                    onTextChanged: invalid = false
                    onAccepted: saveButton.save()
                }

                ForkButton {
                    id: saveButton
                    kind: "accent"
                    text: qsTr("Save")
                    enabled: passwordField.text !== ""

                    function save() {
                        if (passwordField.text === "") {
                            return
                        }
                        var saved = ForkPreferences.saveMacDrivePassword(passwordField.text)
                        if (saved) {
                            passwordField.text = ""
                            card.refresh()
                        } else {
                            passwordField.invalid = true
                        }
                        if (window.forkToast) {
                            window.forkToast(saved ? qsTr("Mac password saved in your keychain")
                                                   : qsTr("That isn't the password of %1").arg(card.setup.userName))
                        }
                    }

                    onClicked: save()
                }
            }

            Row {
                visible: card.setup.passwordSaved
                spacing: 10

                ForkText {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "body"
                    text: qsTr("Saved in your keychain")
                }

                ForkButton {
                    kind: "quiet"
                    text: qsTr("Forget")
                    onClicked: {
                        ForkPreferences.forgetMacDrivePassword()
                        card.refresh()
                    }
                }
            }
        }

        ForkText {
            width: parent.width
            visible: card.setup.last !== ""
            kind: "help"
            text: qsTr("Last LAN stream: %1").arg(card.setup.last)
        }

        ForkTip {
            width: parent.width
            symbol: "lock.fill"
            symbolColor: ForkTheme.ok
            text: qsTr("The password goes to the PC only on LAN streams, over the paired, encrypted connection, and Apollo keeps it in memory only.")
        }
    }
}
