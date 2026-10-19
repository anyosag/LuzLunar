import QtQuick

import ComputerManager 1.0
import ComputerModel 1.0
import ForkHostUpdates 1.0
import ForkTheme 1.0
import ForkUpdater 1.0

// [fork] Settings › Updates: LuzLunar's own over-the-air updates (ForkUpdater) and each paired
// Apollo PC's (ForkHostUpdates). Both come from the fork's master builds, signed by its CI.
Column {
    id: updatesSection

    spacing: ForkTheme.gap

    // The PCs, built the way the PC list builds its model
    property ComputerModel computerModel: createModel()

    function createModel() {
        var model = Qt.createQmlObject('import ComputerModel 1.0; ComputerModel {}', updatesSection, '')
        model.initialize(ComputerManager)
        return model
    }

    Component.onCompleted: ForkHostUpdates.refreshAll()

    // How many of the PCs are paired Apollo PCs
    function apolloCount() {
        var count = 0
        for (var i = 0; i < apolloRepeater.count; i++) {
            var row = apolloRepeater.itemAt(i)
            if (row && row.isApollo) {
                count++
            }
        }
        return count
    }

    // ---- LuzLunar ---------------------------------------------------------------------------

    ForkCard {
        title: qsTr("LuzLunar")
        spacing: 8
        // The card is 8 shorter below its last row (the design's rows cards)
        height: implicitHeight - 8

        Item {
            width: parent.width
            implicitHeight: Math.max(appTexts.implicitHeight, appButtons.implicitHeight) + 16

            Column {
                id: appTexts
                anchors.left: parent.left
                anchors.right: appButtons.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                ForkText {
                    width: parent.width
                    kind: "label"
                    elide: Text.ElideRight
                    text: qsTr("Version %1").arg(ForkUpdater.buildId)
                }

                ForkText {
                    width: parent.width
                    kind: "help"
                    text: ForkUpdater.masterBuild
                          ? qsTr("Build %1 of the fork's master branch.").arg(ForkUpdater.run)
                          : qsTr("A build from a branch or this Mac, not from master: it updates only when you click Install.")
                }

                ForkText {
                    width: parent.width
                    kind: "help"
                    visible: text !== ""
                    color: ForkUpdater.state === "failed" ? ForkTheme.danger : ForkTheme.muted
                    text: ForkUpdater.message
                }
            }

            Row {
                id: appButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                ForkButton {
                    text: qsTr("Check now")
                    enabled: ForkUpdater.state !== "checking" && ForkUpdater.state !== "downloading" && ForkUpdater.state !== "installing"
                    onClicked: ForkUpdater.check()
                }

                ForkButton {
                    kind: "primary"
                    visible: ForkUpdater.updateReady && ForkUpdater.supported
                    text: qsTr("Install and restart")
                    onClicked: ForkUpdater.installNow()
                }
            }
        }

        // What's new: the commit the update was built from
        Column {
            width: parent.width
            spacing: 4
            visible: ForkUpdater.updateAvailable && ForkUpdater.latestVersion !== ""

            ForkText {
                width: parent.width
                kind: "label"
                text: qsTr("New: %1").arg(ForkUpdater.latestVersion)
            }

            ForkText {
                width: parent.width
                kind: "help"
                visible: text !== ""
                text: ForkUpdater.latestNotes
            }
        }

        ForkText {
            width: parent.width
            kind: "help"
            visible: ForkUpdater.lastResult !== ""
            text: qsTr("Last install: %1").arg(ForkUpdater.lastResult)
        }

        // macOS can require this before an app replaces itself
        Item {
            width: parent.width
            visible: ForkUpdater.needsAppManagement
            implicitHeight: visible ? Math.max(appManagementText.implicitHeight, appManagementButton.implicitHeight) + 16 : 0

            ForkText {
                id: appManagementText
                anchors.left: parent.left
                anchors.right: appManagementButton.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                kind: "help"
                text: qsTr("Allow LuzLunar in Privacy & Security › App Management, so it can replace itself with updates.")
            }

            ForkButton {
                id: appManagementButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Open Privacy & Security")
                onClicked: ForkUpdater.openAppManagementSettings()
            }
        }

        ForkSwitchRow {
            label: qsTr("Install LuzLunar updates automatically")
            help: qsTr("When you quit LuzLunar, or after 10 minutes in the background with no stream. If a new build doesn't start, the previous one comes back.")
            enabled: ForkUpdater.supported
            checked: ForkUpdater.automatic
            onToggled: (on) => ForkUpdater.automatic = on
        }

        ForkText {
            width: parent.width
            kind: "help"
            visible: !ForkUpdater.supported
            text: qsTr("This build can't update itself because it isn't signed with LuzLunar's certificate. Install the next build by hand once; it updates itself after that.")
        }
    }

    // ---- Apollo PCs -------------------------------------------------------------------------

    ForkCard {
        title: qsTr("Apollo PCs")
        spacing: 4
        // The card is 8 shorter below its last row (the design's rows cards)
        height: implicitHeight - 8

        ForkText {
            width: parent.width
            kind: "help"
            // The arguments only make it re-count when PCs come, go or change
            visible: updatesSection.apolloCount(apolloRepeater.count, ForkHostUpdates.revision) === 0
            text: qsTr("No paired Apollo PCs. Pair one in Host & network.")
        }

        Column {
            id: apolloList
            width: parent.width
            spacing: 0

            Repeater {
                id: apolloRepeater
                model: updatesSection.computerModel

                delegate: Column {
                    id: pcRow

                    required property string name
                    required property bool online
                    required property bool paired
                    required property string hostSoftware
                    required property string uuid

                    readonly property bool isApollo: paired && hostSoftware === "Apollo"
                    readonly property var info: ForkHostUpdates.revision >= 0 ? ForkHostUpdates.status(uuid) : ({})
                    readonly property bool canUpdate: !!info.known && !!info.supported && !!info.permitted

                    // The line under the PC's name
                    readonly property string statusText: {
                        if (!online) {
                            return qsTr("Offline")
                        }
                        if (info.updating) {
                            return qsTr("Apollo is updating. The PC is offline for a minute while it restarts.")
                        }
                        if (!info.known) {
                            return qsTr("Checking…")
                        }
                        if (!info.supported) {
                            return qsTr("This Apollo can't update itself yet. Install the latest build on the PC once.")
                        }
                        if (!info.permitted) {
                            return qsTr("This Mac isn't allowed to update Apollo. Turn on \"Update Apollo\" for it in Apollo's Web UI, on the PIN page's client list.")
                        }
                        var text = info.update ? qsTr("Apollo %1 · %2 is available").arg(info.version).arg(info.latestVersion)
                                               : qsTr("Apollo %1 · up to date").arg(info.version)
                        if (info.error) {
                            return text + "\n" + info.error
                        }
                        if (info.message && info.state !== "idle") {
                            return text + "\n" + info.message
                        }
                        return text
                    }

                    width: apolloList.width
                    visible: isApollo
                    spacing: 0

                    Item {
                        width: parent.width
                        implicitHeight: Math.max(pcTexts.implicitHeight, pcButtons.implicitHeight) + 20

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: ForkTheme.lineSoft
                        }

                        Column {
                            id: pcTexts
                            anchors.left: parent.left
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

                            ForkText {
                                width: parent.width
                                kind: "help"
                                text: pcRow.statusText
                            }

                            ForkText {
                                width: parent.width
                                kind: "help"
                                visible: pcRow.canUpdate && !!pcRow.info.update && text !== ""
                                text: pcRow.info.latestNotes || ""
                            }

                            ForkText {
                                width: parent.width
                                kind: "help"
                                visible: pcRow.canUpdate && text !== ""
                                text: pcRow.info.lastResult ? qsTr("Last install: %1").arg(pcRow.info.lastResult) : ""
                            }
                        }

                        Row {
                            id: pcButtons
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            ForkButton {
                                visible: pcRow.canUpdate && pcRow.online
                                enabled: !pcRow.info.busy && !pcRow.info.updating
                                text: qsTr("Check")
                                Accessible.name: qsTr("Check %1 for updates").arg(pcRow.name)
                                onClicked: ForkHostUpdates.check(pcRow.uuid)
                            }

                            ForkButton {
                                kind: "primary"
                                visible: pcRow.canUpdate && pcRow.online && !!pcRow.info.update && !pcRow.info.updating
                                enabled: !pcRow.info.busy
                                text: qsTr("Update Apollo now")
                                Accessible.name: qsTr("Update Apollo on %1").arg(pcRow.name)
                                onClicked: ForkHostUpdates.install(pcRow.uuid)
                            }
                        }
                    }

                    ForkSwitchRow {
                        visible: pcRow.canUpdate
                        label: qsTr("Install Apollo updates automatically")
                        help: qsTr("Saved on the PC, so it updates even when LuzLunar isn't running: while nobody streams and no app runs. If a new build doesn't start, the previous one comes back.")
                        enabled: pcRow.online && !pcRow.info.busy
                        checked: !!pcRow.info.automatic
                        onToggled: (on) => ForkHostUpdates.setAutomatic(pcRow.uuid, on)
                    }
                }
            }
        }
    }
}
