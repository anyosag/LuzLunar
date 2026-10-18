import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import ComputerManager 1.0
import ComputerModel 1.0
import ForkTheme 1.0
import StreamingPreferences 1.0

// [fork] Settings › Host & network: what the host PC does when a stream ends, how LuzLunar finds
// PCs and checks the network, and the PCs it knows, with Rename and Remove as upstream's PC list
// offers them (its context menu). The switches set the same preferences as upstream's Host
// Settings and mDNS / blocked-connection checkboxes. Testing the network stays a per-PC action in
// the PC list's menu.
Column {
    id: hostSection

    spacing: ForkTheme.gap

    // The PCs, built the way the PC list builds its model. It follows PCs that come and go.
    property ComputerModel computerModel: createModel()

    function createModel() {
        var model = Qt.createQmlObject('import ComputerModel 1.0; ComputerModel {}', hostSection, '')
        model.initialize(ComputerManager)
        return model
    }

    // A text field's placeholder can't be set to plain, and the host picks its name, so markup in
    // one is escaped to show as it's spelled (as PcView does). Text without "<" holds no markup.
    function escapeMarkup(text) {
        if (!text || text.indexOf("<") < 0) {
            return text
        }
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    // A short confirmation at the bottom of the window (main.qml's forkToast)
    function toast(text) {
        if (window.forkToast) {
            window.forkToast(text)
        }
    }

    // ---- On the PC --------------------------------------------------------------------------

    ForkCard {
        title: qsTr("On the PC")
        spacing: 8
        // The card is 8 shorter below its last row (the design's rows cards)
        height: implicitHeight - 8

        Column {
            width: parent.width
            spacing: 0

            ForkSwitchRow {
                showDivider: false
                label: qsTr("Optimize game settings for streaming")
                help: qsTr("Lets the host change a game's resolution and quality to match the stream.")
                checked: StreamingPreferences.gameOptimizations
                onToggled: (on) => StreamingPreferences.gameOptimizations = on
            }

            ForkSwitchRow {
                label: qsTr("Quit app on host PC after ending stream")
                help: qsTr("Off: the game keeps running, so you can resume where you left off.")
                checked: StreamingPreferences.quitAppAfter
                onToggled: (on) => StreamingPreferences.quitAppAfter = on
            }
        }

        ForkWarnBox {
            warnings: StreamingPreferences.quitAppAfter
                      ? [qsTr("This will close the app or game you are streaming when you end your stream. You will lose any unsaved progress!")]
                      : []
        }
    }

    // ---- Network ----------------------------------------------------------------------------

    ForkCard {
        title: qsTr("Network")
        spacing: 8
        // The card is 8 shorter below its last row (the design's rows cards)
        height: implicitHeight - 8

        Column {
            width: parent.width
            spacing: 0

            ForkSwitchRow {
                showDivider: false
                label: qsTr("Automatically find PCs on the local network")
                help: qsTr("Recommended. Turn it off to add every PC by its address.")
                checked: StreamingPreferences.enableMdns
                onToggled: (on) => {
                    // Only do the work if the value actually changed
                    if (StreamingPreferences.enableMdns !== on) {
                        StreamingPreferences.enableMdns = on

                        // Restart polling so the mDNS change takes effect
                        if (window.pollingActive) {
                            ComputerManager.stopPollingAsync()
                            ComputerManager.startPolling()
                        }
                    }
                }
            }

            ForkSwitchRow {
                label: qsTr("Automatically detect blocked connections")
                help: qsTr("Recommended. Warns when a network's firewall is stopping the stream.")
                checked: StreamingPreferences.detectNetworkBlocking
                onToggled: (on) => StreamingPreferences.detectNetworkBlocking = on
            }
        }
    }

    // ---- Paired PCs -------------------------------------------------------------------------

    ForkCard {
        spacing: 4
        // The card is 8 shorter below its last row (the design's rows cards)
        height: implicitHeight - 8

        Item {
            width: parent.width
            height: Math.max(pcsTitle.implicitHeight, addPcButton.implicitHeight)

            ForkText {
                id: pcsTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                kind: "eyebrow"
                text: qsTr("Paired PCs")
                Accessible.role: Accessible.Heading
            }

            ForkButton {
                id: addPcButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                kind: "link"
                text: qsTr("Add a PC")
                onClicked: addPcDialog.open()
            }
        }

        Column {
            id: pcList
            width: parent.width
            spacing: 0

            Repeater {
                id: pcRepeater
                model: hostSection.computerModel

                delegate: Item {
                    id: pcRow

                    required property int index
                    required property string name
                    required property bool online
                    required property bool paired
                    required property bool statusUnknown
                    required property string hostSoftware

                    // "Apollo · online" for a PC that's paired, whose host software is known;
                    // "Online · paired", "Offline · paired" or "Online · not paired" otherwise
                    readonly property string status: {
                        if (statusUnknown) {
                            return qsTr("Checking…")
                        }
                        if (hostSoftware !== "") {
                            return online ? qsTr("%1 · online").arg(hostSoftware) : qsTr("%1 · offline").arg(hostSoftware)
                        }
                        return qsTr("%1 · %2").arg(online ? qsTr("Online") : qsTr("Offline"))
                                             .arg(paired ? qsTr("paired") : qsTr("not paired"))
                    }

                    width: pcList.width
                    height: Math.max(pcTile.height, pcTexts.implicitHeight, pcButtons.implicitHeight) + 20

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: ForkTheme.lineSoft
                    }

                    Rectangle {
                        id: pcTile
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 40
                        radius: 10
                        color: ForkTheme.raised
                        Accessible.ignored: true

                        ForkSymbol {
                            anchors.centerIn: parent
                            symbol: "desktopcomputer"
                            size: 20
                            color: ForkTheme.text2
                        }
                    }

                    Column {
                        id: pcTexts
                        anchors.left: pcTile.right
                        anchors.leftMargin: 16
                        anchors.right: pcButtons.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        // The host picks its name, so ForkText keeps it plain
                        ForkText {
                            width: parent.width
                            kind: "label"
                            elide: Text.ElideRight
                            text: pcRow.name
                        }

                        Row {
                            width: parent.width
                            spacing: 6

                            Rectangle {
                                id: statusDot
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 8
                                radius: 4
                                color: pcRow.online && !pcRow.statusUnknown ? ForkTheme.ok : "transparent"
                                border.width: 1.5
                                border.color: pcRow.online && !pcRow.statusUnknown ? ForkTheme.ok : ForkTheme.muted
                                Accessible.ignored: true
                            }

                            ForkText {
                                width: parent.width - statusDot.width - parent.spacing
                                kind: "help"
                                elide: Text.ElideRight
                                text: pcRow.status
                            }
                        }
                    }

                    Row {
                        id: pcButtons
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        ForkButton {
                            text: qsTr("Rename")
                            Accessible.name: qsTr("Rename %1").arg(pcRow.name)
                            onClicked: {
                                renameDialog.pcIndex = pcRow.index
                                renameDialog.originalName = pcRow.name
                                renameDialog.open()
                            }
                        }

                        ForkButton {
                            kind: "danger"
                            text: qsTr("Remove")
                            Accessible.name: qsTr("Remove %1").arg(pcRow.name)
                            onClicked: {
                                removeDialog.pcIndex = pcRow.index
                                removeDialog.pcName = pcRow.name
                                removeDialog.open()
                            }
                        }
                    }
                }
            }

            ForkText {
                visible: pcRepeater.count === 0
                width: parent.width
                topPadding: 4
                kind: "help"
                text: qsTr("No PCs yet. Add one by its address.")
            }
        }
    }

    // ---- Dialogs ----------------------------------------------------------------------------

    // Like the PC list's rename dialog
    NavigableDialog {
        id: renameDialog

        property int pcIndex: -1
        property string originalName: ""

        standardButtons: Dialog.Ok | Dialog.Cancel

        onOpened: {
            // Force keyboard focus on the textbox so keyboard navigation works
            renameField.forceActiveFocus()
        }

        onClosed: {
            renameField.clear()
        }

        onAccepted: {
            if (renameField.text) {
                hostSection.computerModel.renameComputer(pcIndex, renameField.text)
                hostSection.toast(qsTr("Renamed to %1").arg(renameField.text))
            }
        }

        ColumnLayout {
            Label {
                text: qsTr("Enter the new name for this PC:")
                font.bold: true
            }

            ForkTextField {
                id: renameField
                placeholderText: hostSection.escapeMarkup(renameDialog.originalName)
                Layout.fillWidth: true
                focus: true
                Accessible.name: qsTr("New name")

                Keys.onReturnPressed: renameDialog.accept()
                Keys.onEnterPressed: renameDialog.accept()
            }
        }
    }

    // Like the PC list's delete dialog, with the design's wording and a red Remove
    NavigableMessageDialog {
        id: removeDialog

        property int pcIndex: -1
        property string pcName: ""

        destructive: true
        title: qsTr("Remove %1?").arg(pcName)
        text: qsTr("You'll need to pair again to stream from it.")
        standardButtons: Dialog.Yes | Dialog.No

        onAboutToShow: {
            // The confirming button says what it does
            var yes = standardButton(Dialog.Yes)
            if (yes) {
                yes.text = qsTr("Remove")
            }
            var no = standardButton(Dialog.No)
            if (no) {
                no.text = qsTr("Cancel")
            }
        }

        onAccepted: {
            var removed = pcName
            hostSection.computerModel.deleteComputer(pcIndex)
            hostSection.toast(qsTr("Removed %1").arg(removed))
        }
    }
}
