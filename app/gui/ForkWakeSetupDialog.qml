import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import ForkHostPower 1.0
import ForkPcPrefs
import ForkTheme 1.0
import ForkWakeOutside

// [fork] Set Up Wake from Off: what stops Wake PC from turning a PC on once it's off, from its
// Apollo's /actions/wake (ForkHostPower.wakeStatus(), words from wakesetuprules.h), with Fix on PC
// and Undo Changes, the BIOS settings only someone at the PC can check, and what waking it from
// outside the home network takes (ForkWakeOutside.status(), wakeoutsiderules.h). Open it with
// openFor().
NavigableDialog {
    id: wakeDialog

    property string pcUuid: ""
    property string pcName: ""

    readonly property var info: ForkHostPower.revision >= 0 && pcUuid !== "" ? ForkHostPower.wakeStatus(pcUuid) : ({})
    // Only while open: status() looks the route to the PC up
    readonly property var outside: visible && ForkWakeOutside.revision >= 0 && ForkPcPrefs.revision >= 0 && pcUuid !== ""
                                   ? ForkWakeOutside.status(pcUuid) : ({})
    readonly property bool busy: !!info.busy || !!info.applying
    readonly property var rows: info.rows || []

    title: qsTr("Turn %1 on from off").arg(pcName)
    standardButtons: Dialog.Close

    function openFor(uuid, name) {
        pcUuid = uuid
        pcName = name
        open()
    }

    onAboutToShow: {
        ForkHostPower.refreshWake(pcUuid)
        if (ForkWakeOutside.status(pcUuid).blocker === "") {
            ForkWakeOutside.check(pcUuid)
        }
        if (standardButton(Dialog.Close)) {
            standardButton(Dialog.Close).text = qsTr("Done")
        }
    }

    ScrollView {
        id: scroller
        implicitWidth: 540
        implicitHeight: Math.min(body.implicitHeight, Overlay.overlay ? Overlay.overlay.height - 240 : 560)
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            id: body
            width: scroller.availableWidth
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // A PC that doesn't answer isn't asked: no spinner, its last answer instead
                ForkBusyIndicator {
                    visible: wakeDialog.busy || (!wakeDialog.info.known && !wakeDialog.info.asleep)
                    running: visible
                    Layout.alignment: Qt.AlignTop
                }

                ForkText {
                    Layout.fillWidth: true
                    kind: "body"
                    color: ForkTheme.text2
                    text: !!wakeDialog.info.known && !wakeDialog.info.supported ? qsTr("%1's Apollo can't set up wake from off. Update Apollo on it first.").arg(wakeDialog.pcName)
                        : !!wakeDialog.info.known && !wakeDialog.info.permitted ? qsTr("This Mac doesn't have the Sleep and Shut Down PC permission on %1.").arg(wakeDialog.pcName)
                        : (wakeDialog.info.summary || "")
                }
            }

            // A row per check: a checkmark, a warning or an info sign, the line and what it means
            ForkWakeRows {
                Layout.fillWidth: true
                visible: wakeDialog.rows.length > 0
                rows: wakeDialog.rows
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8
                visible: !!wakeDialog.info.supported && !!wakeDialog.info.permitted

                Item { Layout.fillWidth: true }

                ForkButton {
                    kind: "default"
                    text: qsTr("Undo Changes")
                    visible: !!wakeDialog.info.canUndo
                    enabled: !wakeDialog.busy
                    onClicked: undoConfirmation.open()
                }

                ForkButton {
                    kind: "primary"
                    text: wakeDialog.busy && !!wakeDialog.info.applying ? qsTr("Changing…") : qsTr("Fix on PC")
                    visible: !!wakeDialog.info.canFix || (wakeDialog.info.fromOff === "fixable")
                    enabled: !!wakeDialog.info.canFix && !wakeDialog.busy
                    onClicked: fixConfirmation.open()
                }
            }

            // Waking it from outside the home network: the same steps as Wake from Outside…
            ForkText {
                Layout.fillWidth: true
                Layout.topMargin: 6
                kind: "heading"
                text: qsTr("From outside your home network")
            }

            ForkText {
                Layout.fillWidth: true
                kind: "help"
                text: wakeDialog.outside.intro || ""
            }

            ForkWakeRows {
                Layout.fillWidth: true
                rows: wakeDialog.outside.rows || []
            }
        }
    }

    NavigableMessageDialog {
        id: fixConfirmation
        title: qsTr("Change %1's wake settings?").arg(wakeDialog.pcName)
        text: wakeDialog.info.fixConfirmation || ""
        forkShowIcon: false
        standardButtons: Dialog.Yes | Dialog.No

        onAboutToShow: {
            if (standardButton(Dialog.Yes)) {
                standardButton(Dialog.Yes).text = qsTr("Fix on PC")
            }
            if (standardButton(Dialog.No)) {
                standardButton(Dialog.No).text = qsTr("Cancel")
            }
        }

        onAccepted: ForkHostPower.fixWake(wakeDialog.pcUuid)
    }

    NavigableMessageDialog {
        id: undoConfirmation
        title: qsTr("Undo the changes on %1?").arg(wakeDialog.pcName)
        text: qsTr("Apollo puts back the settings it changed, unless someone changed them since. The network adapter may restart, so %1 drops off the network for a few seconds.").arg(wakeDialog.pcName)
        forkShowIcon: false
        standardButtons: Dialog.Yes | Dialog.No

        onAboutToShow: {
            if (standardButton(Dialog.Yes)) {
                standardButton(Dialog.Yes).text = qsTr("Undo Changes")
            }
            if (standardButton(Dialog.No)) {
                standardButton(Dialog.No).text = qsTr("Cancel")
            }
        }

        onAccepted: ForkHostPower.undoWake(wakeDialog.pcUuid)
    }
}
