import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import ForkPcPrefs
import ForkTheme 1.0
import ForkWakeOutside

// [fork] Wake from Outside: what waking a PC from outside its home network takes (a port forward to
// it, a network card that still answers the router while the PC sleeps, Sleep rather than Shut
// Down), with what LuzLunar found when it checked from home, and Check Again. The words are
// ForkWakeOutside.status()'s (wakeoutsiderules.h). Open it with openFor().
NavigableDialog {
    id: outsideDialog

    property string pcUuid: ""
    property string pcName: ""

    // Only while open: status() looks the route to the PC up
    readonly property var info: visible && ForkWakeOutside.revision >= 0 && ForkPcPrefs.revision >= 0 && pcUuid !== ""
                                ? ForkWakeOutside.status(pcUuid) : ({})
    readonly property bool checking: !!info.checking

    title: qsTr("Wake %1 from outside").arg(pcName)
    standardButtons: Dialog.Close

    function openFor(uuid, name) {
        pcUuid = uuid
        pcName = name
        open()
    }

    onAboutToShow: {
        // At home with the PC on: check now, so the steps say what's true today
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

            ForkText {
                Layout.fillWidth: true
                kind: "body"
                color: ForkTheme.text2
                text: outsideDialog.info.intro || ""
            }

            ForkWakeRows {
                Layout.fillWidth: true
                rows: outsideDialog.info.rows || []
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8

                ForkBusyIndicator {
                    visible: outsideDialog.checking
                    running: visible
                }

                ForkText {
                    Layout.fillWidth: true
                    kind: "help"
                    text: outsideDialog.checking ? qsTr("Checking your home's address from here…") : (outsideDialog.info.blocker || "")
                }

                ForkButton {
                    kind: "default"
                    text: qsTr("Check Again")
                    visible: outsideDialog.info.blocker === ""
                    enabled: !outsideDialog.checking
                    onClicked: ForkWakeOutside.check(outsideDialog.pcUuid)
                }
            }
        }
    }
}
