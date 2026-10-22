import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Controls.impl 2.15 // [fork] IconImage for tinted, theme-aware icons
import SfSymbols 1.0 // [fork]
import ForkTheme 1.0 // [fork]
import ForkHostUpdates 1.0 // [fork]
import ForkHostPower 1.0 // [fork]
import QtQuick.Layouts 1.3

import ComputerModel 1.0

import ComputerManager 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0

CenteredGridView {
    property ComputerModel computerModel : createModel()

    id: pcGrid
    focus: true
    activeFocusOnTab: true
    topMargin: 0 // [fork] the header holds the page's top space (was 20)
    bottomMargin: 24 // [fork] was 5
    objectName: "LuzLunar" // [fork] the window title; the page's own title is in ForkPcHeader (was qsTr("Computers"))

    // [fork] The design's grid: cards at least 250 wide, 20 apart, stretched to fill a centered
    // block at most 1152 wide (CenteredGridView), each 330 high (was 310x330 cells)
    forkStretch: true
    forkMinItemWidth: 250
    forkGap: 20
    readonly property real forkCardHeight: 330
    cellWidth: forkItemWidth + forkGap
    cellHeight: forkCardHeight + forkGap

    // [fork] The redesign's title above the PCs, and Add a PC and This Mac below them, as wide as the block
    header: ForkPcHeader { width: pcGrid.forkContentWidth }
    footer: ForkPcFooter {
        width: pcGrid.forkContentWidth
        count: pcGrid.count
        columns: pcGrid.itemsPerRow
        cellWidth: pcGrid.cellWidth
        cellHeight: pcGrid.cellHeight
        cardWidth: pcGrid.forkItemWidth
        cardHeight: pcGrid.forkCardHeight
        onAddPc: addPcDialog.open()
    }

    Component.onCompleted: {
        // Don't show any highlighted item until interacting with them.
        // We do this here instead of onActivated to avoid losing the user's
        // selection when backing out of a different page of the app.
        currentIndex = -1
    }

    // Note: Any initialization done here that is critical for streaming must
    // also be done in CliStartStreamSegue.qml, since this code does not run
    // for command-line initiated streams.
    StackView.onActivated: {
        // Setup signals on CM
        ComputerManager.computerAddCompleted.connect(addComplete)

        // Highlight the first item if a gamepad is connected
        if (currentIndex === -1 && SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            currentIndex = 0
        }
    }

    StackView.onDeactivating: {
        ComputerManager.computerAddCompleted.disconnect(addComplete)
    }

    function pairingComplete(error)
    {
        // [fork] On success the PIN dialog says so and offers the PC's apps (was closed in both cases)
        if (error === undefined) {
            if (pairDialog.visible) {
                pairDialog.paired = true
            }
            else {
                window.forkToast(qsTr("Paired with %1").arg(pairDialog.pcName))
            }
            return
        }

        // Close the PIN dialog
        pairDialog.close()

        // Display a failed dialog if we got an error
        if (error !== undefined) {
            errorDialog.text = error
            errorDialog.helpText = ""
            errorDialog.open()
        }
    }

    function addComplete(success, detectedPortBlocking)
    {
        // [fork] The design confirms a PC that was found
        if (success) {
            window.forkToast(addPcDialog.lastAddress !== "" ? qsTr("Found %1").arg(addPcDialog.lastAddress) : qsTr("Found the PC"))
        }

        if (!success) {
            errorDialog.text = qsTr("Unable to connect to the specified PC.")

            if (detectedPortBlocking) {
                errorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking Moonlight. Streaming over the Internet may not work while connected to this network.")
            }
            else {
                errorDialog.helpText = qsTr("Click the Help button for possible solutions.")
            }

            errorDialog.open()
        }
    }

    // [fork] A text field's placeholder can't be set to plain, and the host picks its name, so
    // markup in one is escaped to show as it's spelled. Text without "<" holds no markup and is left alone.
    function escapeMarkup(text)
    {
        if (!text || text.indexOf("<") < 0) {
            return text
        }
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function createModel()
    {
        var model = Qt.createQmlObject('import ComputerModel 1.0; ComputerModel {}', parent, '')
        model.initialize(ComputerManager)
        model.pairingCompleted.connect(pairingComplete)
        model.connectionTestCompleted.connect(testConnectionDialog.connectionTestComplete)
        return model
    }

    Row {
        anchors.centerIn: parent
        spacing: 5
        visible: pcGrid.count === 0

        ForkBusyIndicator { // [fork] was BusyIndicator
            id: searchSpinner
            visible: StreamingPreferences.enableMdns
            running: visible
        }

        Label {
            height: Math.max(searchSpinner.height, implicitHeight) // [fork] was searchSpinner.height
            elide: Label.ElideRight
            text: StreamingPreferences.enableMdns ? qsTr("Searching for compatible hosts on your local network...")
                                                  : qsTr("Automatic PC discovery is disabled. Add your PC manually.")
            font.pointSize: 15 // [fork] was 20
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }
    }

    model: computerModel

    delegate: NavigableItemDelegate {
        id: pcDelegate // [fork]
        width: pcGrid.forkItemWidth; height: pcGrid.forkCardHeight; // [fork] the design's card (was 300x320)
        grid: pcGrid
        cornerRadius: 20 // [fork] the card's corners

        property alias pcContextMenu : pcContextMenuLoader.item

        // [fork] VoiceOver names the card after the PC and its state
        Accessible.name: model.name
        Accessible.description: (model.online ? qsTr("Online") : qsTr("Offline")) + ", " + (model.paired ? qsTr("paired") : qsTr("not paired"))

        // [fork] Waking: from sending Wake-on-LAN until the PC comes online (or a minute passes),
        // the card says so; then a toast says it's awake
        property bool forkWaking: false
        readonly property bool forkOnline: model.online

        // [fork] A newer Apollo build is out and this Mac may install it (ForkHostUpdates)
        readonly property bool forkHostUpdate: {
            var info = ForkHostUpdates.revision >= 0 ? ForkHostUpdates.status(model.uuid) : {}
            return !!info.update && !!info.permitted && !!info.supported && !info.updating
        }
        // [fork] Whether this Mac may put the PC to sleep, and what's running on it (ForkHostPower)
        readonly property var forkSleepInfo: ForkHostPower.revision >= 0 ? ForkHostPower.status(model.uuid) : ({})
        function forkWake() {
            forkWaking = true
            forkWakeTimeout.restart()
            computerModel.wakeComputer(index)
        }
        onForkOnlineChanged: {
            if (forkOnline && forkWaking) {
                forkWaking = false
                window.forkToast(qsTr("%1 is awake").arg(model.name))
            }
        }
        Timer {
            id: forkWakeTimeout
            interval: 60000
            onTriggered: pcDelegate.forkWaking = false
        }

        // [fork] The redesign's card (ForkHostCard) instead of the computer icon, state icon, spinner and name
        ForkHostCard {
            anchors.fill: parent
            name: model.name
            online: model.online
            paired: model.paired
            busy: model.busy
            wakeable: model.wakeable
            waking: pcDelegate.forkWaking
            statusUnknown: model.statusUnknown
            serverSupported: model.serverSupported
            hostSoftware: model.hostSoftware
            hostUpdate: pcDelegate.forkHostUpdate
            highlighted: parent.highlighted || parent.visualFocus
            hovered: parent.hovered

            onActivate: parent.clicked()
            onWake: pcDelegate.forkWake()
            onDetails: {
                showPcDetailsDialog.pcDetails = model.details
                showPcDetailsDialog.open()
            }
            onMenu: pcContextMenu.open()
        }

        Loader {
            id: pcContextMenuLoader
            asynchronous: true
            sourceComponent: NavigableMenu {
                id: pcContextMenu
                initiator: pcContextMenuLoader.parent
                onAboutToShow: ForkHostPower.refresh(model.uuid) // [fork] whether Sleep PC fits now
                MenuItem {
                    text: qsTr("PC Status: %1").arg(model.online ? qsTr("Online") : qsTr("Offline"))
                    font.bold: true
                    palette.windowText: ForkTheme.muted // [fork] a quiet heading in the redesign's menu
                    palette.text: ForkTheme.muted // [fork]
                    enabled: false
                }
                NavigableMenuItem {
                    symbol: "square.grid.2x2" // [fork]
                    text: qsTr("View All Apps")
                    onTriggered: {
                        var component = Qt.createComponent("AppView.qml")
                        var appView = component.createObject(stackView, {"computerIndex": index, "objectName": model.name, "showHiddenGames": true})
                        stackView.push(appView)
                    }
                    visible: model.online && model.paired
                }
                NavigableMenuItem {
                    symbol: "power" // [fork]
                    text: qsTr("Wake PC")
                    onTriggered: pcDelegate.forkWake() // [fork] shows the waking state (was computerModel.wakeComputer(index))
                    visible: !model.online && model.wakeable
                }
                // [fork] Apollo's over-the-air update (ForkHostUpdates; Settings › Updates has the rest)
                NavigableMenuItem {
                    symbol: "arrow.down.circle"
                    text: qsTr("Update Apollo")
                    onTriggered: {
                        ForkHostUpdates.install(model.uuid)
                        window.forkToast(qsTr("Updating Apollo on %1").arg(model.name))
                    }
                    visible: model.online && pcDelegate.forkHostUpdate
                }
                // [fork] Sleep PC, the pair to Wake PC (ForkHostPower)
                NavigableMenuItem {
                    symbol: "moon.zzz"
                    text: qsTr("Sleep PC")
                    onTriggered: {
                        sleepPcDialog.pcUuid = model.uuid
                        sleepPcDialog.pcName = model.name
                        sleepPcDialog.open()
                    }
                    visible: model.online && model.paired && !!pcDelegate.forkSleepInfo.supported && !!pcDelegate.forkSleepInfo.permitted
                }
                NavigableMenuItem {
                    symbol: "network" // [fork]
                    text: qsTr("Test Network")
                    onTriggered: {
                        computerModel.testConnectionForComputer(index)
                        testConnectionDialog.open()
                    }
                }

                NavigableMenuItem {
                    symbol: "pencil" // [fork]
                    text: qsTr("Rename PC")
                    onTriggered: {
                        renamePcDialog.pcIndex = index
                        renamePcDialog.originalName = model.name
                        renamePcDialog.open()
                    }
                }
                NavigableMenuItem {
                    symbol: "info.circle" // [fork] before the line, as in the design (was after Delete)
                    text: qsTr("View Details")
                    onTriggered: {
                        showPcDetailsDialog.pcDetails = model.details
                        showPcDetailsDialog.open()
                    }
                }
                ForkMenuSeparator {} // [fork]
                NavigableMenuItem {
                    symbol: "trash" // [fork]
                    destructive: true // [fork]
                    text: qsTr("Delete PC")
                    onTriggered: {
                        deletePcDialog.pcIndex = index
                        deletePcDialog.pcName = model.name
                        deletePcDialog.open()
                    }
                }
            }
        }

        onClicked: {
            if (model.online) {
                if (!model.serverSupported) {
                    errorDialog.text = qsTr("The version of GeForce Experience on %1 is not supported by this build of Moonlight. You must update Moonlight to stream from %1.").arg(model.name)
                    errorDialog.helpText = ""
                    errorDialog.open()
                }
                else if (model.paired) {
                    // go to game view
                    var component = Qt.createComponent("AppView.qml")
                    var appView = component.createObject(stackView, {"computerIndex": index, "objectName": model.name,
                                                                     // [fork] the toolbar's subtitle, e.g. "Apollo · online"
                                                                     "forkHostStatus": model.hostSoftware !== "" ? qsTr("%1 · online").arg(model.hostSoftware) : qsTr("Online")})
                    stackView.push(appView)
                }
                else {
                    var pin = computerModel.generatePinString()

                    // Kick off pairing in the background
                    computerModel.pairComputer(index, pin)

                    // Display the pairing dialog
                    pairDialog.pin = pin
                    pairDialog.pcIndex = index // [fork]
                    pairDialog.pcName = model.name // [fork]
                    pairDialog.paired = false // [fork]
                    pairDialog.open()
                }
            } else if (!model.online) {
                // Using open() here because it may be activated by keyboard
                pcContextMenu.open()
            }
        }

        onPressAndHold: {
            // popup() ensures the menu appears under the mouse cursor
            if (pcContextMenu.popup) {
                pcContextMenu.popup()
            }
            else {
                // Qt 5.9 doesn't have popup()
                pcContextMenu.open()
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton;
            onClicked: {
                parent.pressAndHold()
            }
        }

        Keys.onMenuPressed: {
            // We must use open() here so the menu is positioned on
            // the ItemDelegate and not where the mouse cursor is
            pcContextMenu.open()
        }

        Keys.onDeletePressed: {
            deletePcDialog.pcIndex = index
            deletePcDialog.pcName = model.name
            deletePcDialog.open()
        }
    }

    ErrorMessageDialog {
        id: errorDialog

        // Using Setup-Guide here instead of Troubleshooting because it's likely that users
        // will arrive here by forgetting to enable GameStream or not forwarding ports.
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide"
    }

    // [fork] The design's pairing dialog: the PIN large in a box while LuzLunar waits for the PC,
    // then "Paired with <PC>" and a way to its apps (was a message dialog with the PIN in a sentence)
    NavigableDialog {
        id: pairDialog
        closePolicy: Popup.CloseOnEscape

        // don't allow edits to the rest of the window while open
        property string pin : "0000"
        property string pcName: ""
        property int pcIndex: -1
        property bool paired: false

        title: paired ? qsTr("Paired with %1").arg(pcName) : qsTr("Pair with %1").arg(pcName)
        standardButtons: paired ? (Dialog.Ok | Dialog.Close) : Dialog.Cancel

        function nameButtons() {
            var showApps = standardButton(Dialog.Ok)
            if (showApps) {
                showApps.text = qsTr("Show apps")
                showApps.forceActiveFocus(Qt.TabFocusReason)
            }
        }
        onPairedChanged: Qt.callLater(nameButtons)
        onClosed: paired = false

        onAccepted: {
            if (paired) {
                var component = Qt.createComponent("AppView.qml")
                var appView = component.createObject(stackView, {"computerIndex": pcIndex, "objectName": pcName, "forkHostStatus": qsTr("Online")})
                stackView.push(appView)
            }
        }
        onRejected: {
            // FIXME: We should interrupt pairing here
        }

        Column {
            width: 420
            spacing: 16

            ForkText {
                width: parent.width
                kind: "body"
                font.pixelSize: 14
                color: ForkTheme.text2
                text: pairDialog.paired ? qsTr("You can stream from %1 now.").arg(pairDialog.pcName)
                                        : qsTr("Enter this PIN on %1. With Apollo or Sunshine, enter it in the host's web UI.").arg(pairDialog.pcName)
            }

            Rectangle {
                visible: !pairDialog.paired
                width: parent.width
                height: pinText.implicitHeight + 36
                radius: 14
                color: ForkTheme.bar
                border.color: ForkTheme.lineSoft

                Text {
                    id: pinText
                    anchors.centerIn: parent
                    text: pairDialog.pin
                    textFormat: Text.PlainText
                    font.family: ForkTheme.monoFamily
                    font.pixelSize: 44
                    font.weight: Font.DemiBold
                    font.letterSpacing: 8.8
                    color: ForkTheme.accentInk
                    Accessible.name: qsTr("PIN %1").arg(pairDialog.pin.split("").join(" "))
                }
            }

            Row {
                visible: !pairDialog.paired
                spacing: 10

                ForkBusyIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    running: pairDialog.visible && !pairDialog.paired
                }

                ForkText {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "body"
                    color: ForkTheme.muted
                    wrapMode: Text.NoWrap
                    text: qsTr("Waiting for the PC…")
                }
            }
        }
    }

    NavigableMessageDialog {
        id: deletePcDialog
        // don't allow edits to the rest of the window while open
        property int pcIndex : -1
        property string pcName : ""
        // [fork] The design's wording, a red Remove and no icon (was "Are you sure you want to remove '%1'?" with Yes/No)
        title: qsTr("Remove %1?").arg(pcName)
        text: qsTr("You'll need to pair again to stream from it.")
        destructive: true
        forkShowIcon: false
        standardButtons: Dialog.Yes | Dialog.No

        onAboutToShow: {
            if (standardButton(Dialog.Yes)) {
                standardButton(Dialog.Yes).text = qsTr("Remove")
            }
            if (standardButton(Dialog.No)) {
                standardButton(Dialog.No).text = qsTr("Cancel")
            }
        }

        onAccepted: {
            computerModel.deleteComputer(pcIndex)
            window.forkToast(qsTr("Removed %1").arg(pcName)) // [fork]
        }
    }

    // [fork] Sleep PC's confirmation; it warns when an app is still running on the PC, which sleeping
    // quits first (ForkHostPower)
    NavigableMessageDialog {
        id: sleepPcDialog
        property string pcUuid : ""
        property string pcName : ""
        readonly property var info: ForkHostPower.revision >= 0 && pcUuid !== "" ? ForkHostPower.status(pcUuid) : ({})
        readonly property string runningApp: info.reason === "app_running" ? info.app : ""
        title: qsTr("Put %1 to sleep?").arg(pcName)
        text: runningApp !== "" ? qsTr("%1 is still running on %2. Sleep quits it first; anything unsaved in it is lost.").arg(runningApp).arg(pcName)
                                : qsTr("Wake PC wakes it again.")
        destructive: runningApp !== ""
        forkShowIcon: false
        standardButtons: Dialog.Yes | Dialog.No

        onAboutToShow: {
            ForkHostPower.refresh(pcUuid)
            if (standardButton(Dialog.Yes)) {
                standardButton(Dialog.Yes).text = qsTr("Sleep")
            }
            if (standardButton(Dialog.No)) {
                standardButton(Dialog.No).text = qsTr("Cancel")
            }
        }

        onAccepted: ForkHostPower.sleep(pcUuid, runningApp)
    }

    NavigableMessageDialog {
        id: testConnectionDialog
        closePolicy: Popup.CloseOnEscape
        standardButtons: Dialog.Ok

        onAboutToShow: {
            testConnectionDialog.text = qsTr("Moonlight is testing your network connection to determine if any required ports are blocked.") + "\n\n" + qsTr("This may take a few seconds…")
            showSpinner = true
        }

        function connectionTestComplete(result, blockedPorts)
        {
            if (result === -1) {
                text = qsTr("The network test could not be performed because none of Moonlight's connection testing servers were reachable from this PC. Check your Internet connection or try again later.")
                imageSrc = "qrc:/res/baseline-warning-24px.svg"
            }
            else if (result === 0) {
                text = qsTr("This network does not appear to be blocking Moonlight. If you still have trouble connecting, check your PC's firewall settings.") + "\n\n" + qsTr("If you are trying to stream over the Internet, install the Moonlight Internet Hosting Tool on your gaming PC and run the included Internet Streaming Tester to check your gaming PC's Internet connection.")
                imageSrc = "qrc:/res/baseline-check_circle_outline-24px.svg"
            }
            else {
                text = qsTr("Your PC's current network connection seems to be blocking Moonlight. Streaming over the Internet may not work while connected to this network.") + "\n\n" + qsTr("The following network ports were blocked:") + "\n"
                text += blockedPorts
                imageSrc = "qrc:/res/baseline-error_outline-24px.svg"
            }

            // Stop showing the spinner and show the image instead
            showSpinner = false
        }
    }

    NavigableDialog {
        id: renamePcDialog
        property string label: qsTr("Name") // [fork] the design's label (was "Enter the new name for this PC:")
        property string originalName
        property int pcIndex : -1;

        title: qsTr("Rename %1").arg(originalName) // [fork]
        standardButtons: Dialog.Ok | Dialog.Cancel

        // [fork] The design's Save button
        onAboutToShow: {
            if (standardButton(Dialog.Ok)) {
                standardButton(Dialog.Ok).text = qsTr("Save")
            }
        }

        onOpened: {
            // Force keyboard focus on the textbox so keyboard navigation works
            editText.forceActiveFocus()
        }

        onClosed: {
            editText.clear()
        }

        onAccepted: {
            if (editText.text) {
                computerModel.renameComputer(pcIndex, editText.text)
                window.forkToast(qsTr("Renamed to %1").arg(editText.text)) // [fork]
            }
        }

        ColumnLayout {
            spacing: 8 // [fork]

            ForkText { // [fork] the design's field label (was a bold Label)
                kind: "label"
                font.weight: Font.DemiBold
                text: renamePcDialog.label
            }

            ForkTextField { // [fork] the redesign's field (was TextField)
                id: editText
                placeholderText: pcGrid.escapeMarkup(renamePcDialog.originalName) // [fork] was renamePcDialog.originalName
                Layout.fillWidth: true
                Layout.preferredWidth: 380 // [fork]
                focus: true

                Keys.onReturnPressed: {
                    renamePcDialog.accept()
                }

                Keys.onEnterPressed: {
                    renamePcDialog.accept()
                }
            }
        }
    }

    NavigableMessageDialog {
        id: showPcDetailsDialog
        property string pcDetails : "";
        text: showPcDetailsDialog.pcDetails
        imageSrc: "qrc:/res/baseline-help_outline-24px.svg"
        standardButtons: Dialog.Ok
    }

    ScrollBar.vertical: ScrollBar {}
}
