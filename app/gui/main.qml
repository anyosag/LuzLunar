import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Window 2.2
// [fork] No explicit Material import: it would override the native macOS style set in main.cpp

import ComputerManager 1.0
import AutoUpdateChecker 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0
import ForkTheme 1.0 // [fork]

ApplicationWindow {
    property bool pollingActive: false

    // Set by SettingsView to force the back operation to pop all
    // pages except the initial view. This is required when doing
    // a retranslate() because AppView breaks for some reason.
    property bool clearOnBack: false

    id: window
    width: 1280
    height: 600

    // [fork] The design's opaque Night or Day ground (the native title bar and toolbar sit on
    // ForkTheme.bar, set in windowchrome_mac.mm)
    color: ForkTheme.bg // [fork] was palette.window

    // [fork] Stock controls (dialogs, menus, drop-downs, text fields, tooltips) in LuzLunar's colors
    palette.window: ForkTheme.surface
    palette.windowText: ForkTheme.text
    palette.base: ForkTheme.bar
    palette.alternateBase: ForkTheme.raised
    palette.text: ForkTheme.text
    palette.button: ForkTheme.raised
    palette.buttonText: ForkTheme.text
    palette.brightText: ForkTheme.text
    palette.highlight: ForkTheme.accent
    palette.highlightedText: ForkTheme.textOnAccent
    palette.placeholderText: ForkTheme.faint
    palette.light: ForkTheme.lineStrong
    palette.midlight: ForkTheme.line
    palette.mid: ForkTheme.line
    palette.dark: ForkTheme.lineSoft
    palette.shadow: "#000000"
    palette.toolTipBase: ForkTheme.surface
    palette.toolTipText: ForkTheme.text
    palette.link: ForkTheme.accentInk
    palette.linkVisited: ForkTheme.accentInk

    // This function runs prior to creation of the initial StackView item
    function doEarlyInit() {
        // [fork] The Material 2 background override is gone with the native macOS style
        SdlGamepadKeyNavigation.enable()
    }

    Component.onCompleted: {
        // Show the window according to the user's preferences
        if (SystemProperties.hasDesktopEnvironment) {
            if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_MAXIMIZED) {
                window.showMaximized()
            }
            else if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_FULLSCREEN) {
                window.showFullScreen()
            }
            else {
                window.show()
            }
        } else {
            window.showFullScreen()
        }

        // Display any modal dialogs for configuration warnings
        if (runConfigChecks) {
            if (SystemProperties.isWow64) {
                wow64Dialog.open()
            }

            // Hardware acceleration and unmapped gamepads are checked asynchronously
            SystemProperties.hasHardwareAccelerationChanged.connect(hasHardwareAccelerationChanged)
            SystemProperties.unmappedGamepadsChanged.connect(hasUnmappedGamepadsChanged)
            SystemProperties.startAsyncLoad()
        }
    }

    function hasHardwareAccelerationChanged() {
        if (!SystemProperties.hasHardwareAcceleration && StreamingPreferences.videoDecoderSelection !== StreamingPreferences.VDS_FORCE_SOFTWARE) {
            if (SystemProperties.isRunningXWayland) {
                xWaylandDialog.open()
            }
            else {
                noHwDecoderDialog.open()
            }
        }
    }

    function hasUnmappedGamepadsChanged() {
        if (SystemProperties.unmappedGamepads) {
            unmappedGamepadDialog.unmappedGamepads = SystemProperties.unmappedGamepads
            unmappedGamepadDialog.open()
        }
    }

    // It would be better to use TextMetrics here, but it always lays out
    // the text slightly more compactly than real Text does in ToolTip,
    // causing unexpected line breaks to be inserted
    Text {
        id: tooltipTextLayoutHelper
        visible: false
        font: ToolTip.toolTip.font
        text: ToolTip.toolTip.text
    }

    // This configures the maximum width of the singleton attached QML ToolTip. If left unconstrained,
    // it will never insert a line break and just extend on forever.
    ToolTip.toolTip.contentWidth: Math.min(tooltipTextLayoutHelper.width, 400)

    function goBack() {
        if (clearOnBack) {
            // Pop all items except the first one
            stackView.pop(null)
            clearOnBack = false
        }
        else {
            stackView.pop()
        }
    }

    StackView {
        id: stackView
        anchors.fill: parent
        focus: true

        Component.onCompleted: {
            // Perform our early initialization before constructing
            // the initial view and pushing it to the StackView
            doEarlyInit()
            push(initialView)
        }

        onCurrentItemChanged: {
            // Ensure focus travels to the next view when going back
            if (currentItem) {
                currentItem.forceActiveFocus()
            }
        }

        Keys.onEscapePressed: {
            if (depth > 1) {
                goBack()
            }
            else {
                quitConfirmationDialog.open()
            }
        }

        Keys.onBackPressed: {
            if (depth > 1) {
                goBack()
            }
            else {
                quitConfirmationDialog.open()
            }
        }

        Keys.onMenuPressed: {
            settingsButton.clicked()
        }

        // This is a keypress we've reserved for letting the
        // SdlGamepadKeyNavigation object tell us to show settings
        // when Menu is consumed by a focused control.
        Keys.onHangupPressed: {
            settingsButton.clicked()
        }
    }

    // This timer keeps us polling for 5 minutes of inactivity
    // to allow the user to work with Moonlight on a second display
    // while dealing with configuration issues. This will ensure
    // machines come online even if the input focus isn't on Moonlight.
    Timer {
        id: inactivityTimer
        interval: 5 * 60000
        onTriggered: {
            if (!active && pollingActive) {
                ComputerManager.stopPollingAsync()
                pollingActive = false
            }
        }
    }

    onVisibleChanged: {
        // When we become invisible while streaming is going on,
        // stop polling immediately.
        if (!visible) {
            inactivityTimer.stop()

            if (pollingActive) {
                ComputerManager.stopPollingAsync()
                pollingActive = false
            }
        }
        else if (active) {
            // When we become visible and active again, start polling
            inactivityTimer.stop()

            // Restart polling if it was stopped
            if (!pollingActive) {
                ComputerManager.startPolling()
                pollingActive = true
            }
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    onActiveChanged: {
        if (active) {
            // Stop the inactivity timer
            inactivityTimer.stop()

            // Restart polling if it was stopped
            if (!pollingActive) {
                ComputerManager.startPolling()
                pollingActive = true
            }
        }
        else {
            // Start the inactivity timer to stop polling
            // if focus does not return within a few minutes.
            inactivityTimer.restart()
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    // [fork] The second line under the toolbar's title: LuzLunar's version in Settings, and the
    // host software and state of the PC whose apps are showing ("Apollo · online")
    readonly property string forkToolbarSubtitle: stackView.currentItem instanceof ForkSettingsView ? qsTr("Version %1").arg(SystemProperties.versionString)
                                                : (stackView.currentItem && stackView.currentItem.forkHostStatus !== undefined ? stackView.currentItem.forkHostStatus : "")

    // [fork] The redesign's toasts: a short confirmation at the bottom of the window, above dialogs
    // ("Renamed to Office PC"). Any page can call window.forkToast(text).
    function forkToast(text) {
        forkToasts.show(text)
    }

    ForkToast {
        id: forkToasts
        parent: Overlay.overlay
        z: 1000
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
    }

    function navigateTo(url, objectType)
    {
        var existingItem = stackView.find(function(item, index) {
            return item instanceof objectType
        })

        if (existingItem !== null) {
            // Pop to the existing item
            stackView.pop(existingItem)
        }
        else {
            // Create a new item
            stackView.push(url)
        }
    }

    // [fork] On macOS 15+ the buttons below show in a native toolbar (Liquid Glass on macOS 26).
    // The QML toolbar is then clipped to nothing but stays in the focus chain, so keyboard and
    // gamepad navigation still reach its buttons; the native item of the focused one is highlighted.
    // Clicks on native items go to the QML buttons.
    ForkNativeToolbar {
        id: nativeToolbar
        targetWindow: window
        shown: toolBar.visible
        title: stackView.currentItem ? stackView.currentItem.objectName : ""
        subtitle: window.forkToolbarSubtitle // [fork]
        items: [
            { "id": "back", "button": backButton, "symbol": "chevron.left", "label": qsTr("Back"),
              "navigational": true, "visible": stackView.depth > 1, "focused": backButton.activeFocus },
            { "id": "update", "button": updateButton, "symbol": "arrow.down.circle", "label": qsTr("Update"),
              "toolTip": updateButton.ToolTip.text, "visible": updateButton.browserUrl !== "", "focused": updateButton.activeFocus },
            { "id": "discord", "button": discordButton, "symbol": "bubble.left.and.bubble.right", "label": qsTr("Discord"),
              "toolTip": discordButton.ToolTip.text, "visible": SystemProperties.hasBrowser && stackView.currentItem instanceof ForkSettingsView,
              "focused": discordButton.activeFocus },
            { "id": "addPc", "button": addPcButton, "symbol": "plus", "label": qsTr("Add PC"), "labeled": true,
              "toolTip": addPcButton.ToolTip.text, "visible": stackView.currentItem instanceof PcView, "focused": addPcButton.activeFocus },
            { "id": "help", "button": helpButton, "symbol": "questionmark.circle", "label": qsTr("Help"),
              "toolTip": helpButton.ToolTip.text, "visible": helpButton.visible, "focused": helpButton.activeFocus },
            { "id": "settings", "button": settingsButton, "symbol": "gearshape", "label": qsTr("Settings"),
              "toolTip": settingsButton.ToolTip.text, "visible": !(stackView.currentItem instanceof ForkSettingsView),
              "focused": settingsButton.activeFocus }
        ]
    }

    header: ToolBar {
        id: toolBar
        height: nativeToolbar.active ? 0 : 60 // [fork] the design's toolbar height, or none with the native toolbar
        clip: nativeToolbar.active // [fork] draws nothing and takes no clicks, but its buttons keep keyboard focus
        anchors.topMargin: 5
        anchors.bottomMargin: 5

        // [fork] Where the native toolbar isn't shown (macOS before 15, offscreen screenshots), this one
        // takes the theme's toolbar ground, like the native one's tinted glass
        background: Rectangle {
            color: ForkTheme.bar

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: ForkTheme.lineSoft
            }
        }

        Label {
            id: titleLabel
            visible: false // [fork] the title sits at the left with its subtitle, as in the design (was toolBar.width > 700)
            anchors.fill: parent
            text: stackView.currentItem.objectName
            textFormat: Text.PlainText // [fork] an app grid's title is its host's name, never markup
            font.pointSize: 15 // [fork] macOS title size (was 20)
            font.bold: true
            elide: Label.ElideRight
            horizontalAlignment: Qt.AlignHCenter
            verticalAlignment: Qt.AlignVCenter
        }

        RowLayout {
            spacing: 10

            // [fork] Back (Escape, or B on a gamepad) leaves the toolbar for the page below,
            // which matters while the toolbar is clipped and its focus only shows natively
            Keys.onEscapePressed: {
                stackView.currentItem.forceActiveFocus(Qt.TabFocus)
            }
            Keys.onBackPressed: {
                stackView.currentItem.forceActiveFocus(Qt.TabFocus)
            }
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.fill: parent

            NavigableToolButton {
                id: backButton // [fork] for the native toolbar

                // Only make the button visible if the user has navigated somewhere.
                visible: stackView.depth > 1

                iconSource: "qrc:/res/arrow_left.svg"
                symbolName: "chevron.left" // [fork]

                onClicked: goBack()

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            // [fork] The design's title: LuzLunar's mark and name on Your PCs, otherwise the page's
            // title over its subtitle, at the left. It fills the row's free space, so the buttons
            // after it sit at the right. (Was a centered label shown when the window got narrow.)
            Item {
                id: titleRowLabel
                Layout.fillWidth: true
                Layout.fillHeight: true

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    spacing: 10

                    ForkMoonMark {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: stackView.currentItem instanceof PcView
                        size: 24
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 34
                        spacing: 2

                        ForkText {
                            width: parent.width
                            kind: "label"
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            text: stackView.currentItem ? stackView.currentItem.objectName : ""
                        }

                        ForkText {
                            width: parent.width
                            visible: text !== ""
                            kind: "help"
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                            text: window.forkToolbarSubtitle
                        }
                    }
                }
            }

            Label {
                id: versionLabel
                visible: false // [fork] the version is the title's subtitle (was stackView.currentItem instanceof ForkSettingsView)
                text: qsTr("Version %1").arg(SystemProperties.versionString)
                font.pointSize: 12
                horizontalAlignment: Qt.AlignRight
                verticalAlignment: Qt.AlignVCenter
            }

            NavigableToolButton {
                id: discordButton
                visible: SystemProperties.hasBrowser &&
                         stackView.currentItem instanceof ForkSettingsView

                iconSource: "qrc:/res/discord.svg"

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Join our community on Discord")

                // TODO need to make sure browser is brought to foreground.
                onClicked: Qt.openUrlExternally("https://moonlight-stream.org/discord");

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            NavigableToolButton {
                id: addPcButton
                visible: stackView.currentItem instanceof PcView

                iconSource:  "qrc:/res/ic_add_to_queue_white_48px.svg"
                symbolName: "plus" // [fork]

                // [fork] Labelled, as in the design (the native toolbar's item is labelled too)
                text: qsTr("Add PC")
                display: AbstractButton.TextBesideIcon
                Layout.preferredWidth: implicitWidth

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Add PC manually") + (newPcShortcut.nativeText ? (" ("+newPcShortcut.nativeText+")") : "")

                Shortcut {
                    id: newPcShortcut
                    sequence: StandardKey.New
                    onActivated: addPcButton.clicked()
                }

                onClicked: {
                    addPcDialog.open()
                }

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            NavigableToolButton {
                property string browserUrl: ""

                id: updateButton

                iconSource: "qrc:/res/update.svg"
                symbolName: "arrow.down.circle" // [fork]

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered || (visible && !nativeToolbar.active) // [fork] the native item has the tooltip

                // Invisible until we get a callback notifying us that
                // an update is available
                visible: false

                onClicked: {
                    if (SystemProperties.hasBrowser) {
                        Qt.openUrlExternally(browserUrl);
                    }
                }

                function updateAvailable(version, url)
                {
                    ToolTip.text = qsTr("Update available for Moonlight: Version %1").arg(version)
                    updateButton.browserUrl = url
                    updateButton.visible = true
                }

                Component.onCompleted: {
                    AutoUpdateChecker.onUpdateAvailable.connect(updateAvailable)
                    AutoUpdateChecker.start()
                }

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            NavigableToolButton {
                id: helpButton
                visible: true // [fork] the shortcuts dialog needs no browser (was SystemProperties.hasBrowser)

                iconSource: "qrc:/res/question_mark.svg"
                symbolName: "questionmark.circle" // [fork]

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Help") + (helpShortcut.nativeText ? (" ("+helpShortcut.nativeText+")") : "")

                Shortcut {
                    id: helpShortcut
                    sequence: StandardKey.HelpContents
                    onActivated: helpButton.clicked()
                }

                // [fork] The redesign's shortcuts dialog, which links to the setup guide (was the guide itself)
                onClicked: forkShortcutsDialog.open()

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            NavigableToolButton {
                // TODO: Implement gamepad mapping then unhide this button
                visible: false

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Gamepad Mapper")

                iconSource: "qrc:/res/ic_videogame_asset_white_48px.svg"
                symbolName: "gamecontroller" // [fork]

                onClicked: navigateTo("qrc:/gui/GamepadMapper.qml", GamepadMapper)

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            NavigableToolButton {
                id: settingsButton

                // [fork] The native toolbar has no Settings item on the Settings page, so focus shouldn't land here
                visible: !nativeToolbar.active || !(stackView.currentItem instanceof ForkSettingsView)

                iconSource:  "qrc:/res/settings.svg"
                symbolName: "gearshape" // [fork]

                onClicked: navigateTo("qrc:/gui/ForkSettingsView.qml", ForkSettingsView) // [fork] the redesign's Settings (was SettingsView)

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }

                Shortcut {
                    id: settingsShortcut
                    sequence: StandardKey.Preferences
                    onActivated: settingsButton.clicked()
                }

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Settings") + (settingsShortcut.nativeText ? (" ("+settingsShortcut.nativeText+")") : "")
            }
        }
    }

    ErrorMessageDialog {
        id: noHwDecoderDialog
        text: qsTr("No functioning hardware accelerated video decoder was detected by Moonlight. " +
                   "Your streaming performance may be severely degraded in this configuration.")
        helpText: qsTr("Click the Help button for more information on solving this problem.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Fixing-Hardware-Decoding-Problems"
    }

    ErrorMessageDialog {
        id: xWaylandDialog
        text: qsTr("Hardware acceleration doesn't work on XWayland. Continuing on XWayland may result in poor streaming performance. " +
                   "Try running with QT_QPA_PLATFORM=wayland or switch to X11.")
        helpText: qsTr("Click the Help button for more information.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Fixing-Hardware-Decoding-Problems"
    }

    NavigableMessageDialog {
        id: wow64Dialog
        standardButtons: Dialog.Ok | Dialog.Cancel
        text: qsTr("This version of Moonlight isn't optimized for your PC. Please download the '%1' version of Moonlight for the best streaming performance.").arg(SystemProperties.friendlyNativeArchName)
        onAccepted: {
            Qt.openUrlExternally("https://github.com/moonlight-stream/moonlight-qt/releases");
        }
    }

    ErrorMessageDialog {
        id: unmappedGamepadDialog
        property string unmappedGamepads : ""
        text: qsTr("Moonlight detected gamepads without a mapping:") + "\n" + unmappedGamepads
        helpTextSeparator: "\n\n"
        helpText: qsTr("Click the Help button for information on how to map your gamepads.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Gamepad-Mapping"
    }

    // This dialog appears when quitting via keyboard or gamepad button
    NavigableMessageDialog {
        id: quitConfirmationDialog
        standardButtons: Dialog.Yes | Dialog.No
        text: qsTr("Are you sure you want to quit?")
        // For keyboard/gamepad navigation
        onAccepted: Qt.quit()
    }

    // HACK: This belongs in StreamSegue but keeping a dialog around after the parent
    // dies can trigger bugs in Qt 5.12 that cause the app to crash. For now, we will
    // host this dialog in a QML component that is never destroyed.
    //
    // To repro: Start a stream, cut the network connection to trigger the "Connection
    // terminated" dialog, wait until the app grid times out back to the PC grid, then
    // try to dismiss the dialog.
    ErrorMessageDialog {
        id: streamSegueErrorDialog

        property bool quitAfter: false

        onClosed: {
            if (quitAfter) {
                Qt.quit()
            }

            // StreamSegue assumes its dialog will be re-created each time we
            // start streaming, so fake it by wiping out the text each time.
            text = ""
        }
    }

    // [fork] Help: the shortcuts while streaming
    ForkShortcutsDialog {
        id: forkShortcutsDialog
    }

    NavigableDialog {
        id: addPcDialog
        property string label: qsTr("IP address or hostname") // [fork] the design's label (was "Enter the IP address of your host PC:")
        // [fork] What was last added, for PcView's "Found" toast
        property string lastAddress: ""
        // [fork] An address is letters, digits and . - _ : % [ ] (IPv6 and ports included)
        readonly property string trimmed: editText.text.trim()
        readonly property bool addressValid: /^[A-Za-z0-9.\-_:%\[\]]+$/.test(trimmed)

        title: qsTr("Add a PC") // [fork]
        standardButtons: Dialog.Ok | Dialog.Cancel

        // [fork] The design's "Add PC" button, enabled once the address could be one
        function updateOkButton() {
            var add = standardButton(Dialog.Ok)
            if (add) {
                add.text = qsTr("Add PC")
                add.enabled = addressValid
            }
        }
        onAboutToShow: updateOkButton()
        onAddressValidChanged: updateOkButton()

        onOpened: {
            // Force keyboard focus on the textbox so keyboard navigation works
            editText.forceActiveFocus()
        }

        onClosed: {
            editText.clear()
        }

        onAccepted: {
            if (editText.text && addressValid) { // [fork] was editText.text
                lastAddress = trimmed // [fork]
                ComputerManager.addNewHostManually(editText.text.trim())
            }
        }

        ColumnLayout {
            spacing: 8 // [fork]

            ForkText { // [fork] the design's field label (was a bold Label)
                kind: "label"
                font.weight: Font.DemiBold
                text: addPcDialog.label
            }

            ForkTextField { // [fork] the redesign's field (was TextField)
                id: editText
                Layout.fillWidth: true
                Layout.preferredWidth: 420 // [fork]
                mono: true // [fork]
                placeholderText: "192.168.1.20" // [fork]
                invalid: addPcDialog.trimmed !== "" && !addPcDialog.addressValid // [fork]
                focus: true

                Keys.onReturnPressed: {
                    if (addPcDialog.addressValid) { // [fork]
                        addPcDialog.accept()
                    }
                }

                Keys.onEnterPressed: {
                    if (addPcDialog.addressValid) { // [fork]
                        addPcDialog.accept()
                    }
                }
            }

            // [fork] The design's help, or what's wrong with the address
            ForkText {
                Layout.fillWidth: true
                kind: "help"
                font.pixelSize: 13
                color: editText.invalid ? ForkTheme.danger : ForkTheme.muted
                text: editText.invalid ? qsTr("Use the PC's IP address or hostname: letters, digits, dots, colons and dashes.")
                                       : qsTr("Find it in Apollo or Sunshine on the PC, or in its network settings.")
            }
        }
    }
}
