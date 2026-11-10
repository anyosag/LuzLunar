// [fork] Versionless imports: the window's padding (set to 0 below, so the content starts under the
// transparent title bar) and Overlay need Qt Quick Controls newer than the 2.2 these were pinned to
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Templates as T // [fork] for Overlay.overlay
// [fork] No explicit Material import: it would override the native macOS style set in main.cpp

import ComputerManager 1.0
import AutoUpdateChecker 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0
import ForkTheme 1.0 // [fork]
import ForkUpdater 1.0 // [fork]
import ForkHostUpdates 1.0 // [fork]
import ForkHostPower 1.0 // [fork]
import ForkPcPrefs 1.0 // [fork]
import WindowChrome 1.0 // [fork]

ApplicationWindow {
    property bool pollingActive: false

    // Set by SettingsView to force the back operation to pop all
    // pages except the initial view. This is required when doing
    // a retranslate() because AppView breaks for some reason.
    property bool clearOnBack: false

    id: window
    // [fork] The canvas's window: 1280 x 900 (clamped to the screen's free area in Component.onCompleted),
    // 1024 x 700 at least. The content draws under a transparent title bar: the real traffic lights
    // stay and the header (ForkWindowHeader) is the bar. See contract-chrome.md.
    width: 1280
    height: 900
    minimumWidth: 1024
    minimumHeight: Math.min(700, Screen.desktopAvailableHeight)
    title: qsTr("LuzLunar")
    flags: Qt.platform.os === "osx" ? (Qt.Window | Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint) : Qt.Window
    topPadding: 0
    leftPadding: 0
    rightPadding: 0
    bottomPadding: 0

    // [fork] The canvas's ground, seen on the pages without a sky (the sky covers it on the others)
    color: ForkTheme.cv.bg // [fork] was palette.window

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
        // [fork] Fit the default size to the screen's free area (below the menu bar, beside the Dock)
        width = Math.min(1280, Screen.desktopAvailableWidth)
        height = Math.min(900, Screen.desktopAvailableHeight)

        // Show the window according to the user's preferences
        if (forkHiddenScreenshots) {
            // [fork] CI's screenshot run on a self-hosted runner leaves it hidden: the harness grabs
            // it rendered offscreen (main.cpp, screenshotharness.cpp)
        }
        else if (SystemProperties.hasDesktopEnvironment) {
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
        if (isGuiLaunch) {
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

    // [fork] ---- The window's chrome (sky-chrome.md §2, §5, §6; decision D1) ----

    readonly property Item forkPage: stackView.currentItem
    // A page's chrome properties are optional: contract-chrome.md
    function pageValue(name, fallback) {
        var page = forkPage
        return page && page[name] !== undefined ? page[name] : fallback
    }
    readonly property bool isSettingsPage: forkPage instanceof ForkSettingsView

    // The one sky, behind the header, the page and the footer; the page picks its variant
    ForkSky {
        id: sky
        anchors.fill: parent
        z: 0
        variant: toolBar.visible ? pageValue("forkSkyVariant", "none") : "none"
        still: ForkPcPrefs.screenshotMode
    }

    ForkWindowHeader {
        id: toolBar // [fork] stream pages hide it with toolBar.visible = false, as they did the toolbar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        z: 3

        skySource: sky.shown ? sky : null
        opaque: pageValue("forkChromeOpaque", !sky.shown)
        fakeLights: forkHiddenScreenshots || ForkPcPrefs.screenshotMode
        lightsVisible: window.visibility !== Window.FullScreen

        variant: window.isSettingsPage ? "back" : pageValue("forkHeaderVariant", "pcs")
        viewMode: pageValue("forkViewMode", "carousel")
        hasPcs: pageValue("forkHasPcs", true)
        backTitle: {
            if (window.isSettingsPage) {
                var below = stackView.get(stackView.depth - 2)
                return below instanceof PcView ? qsTr("Your PCs") : qsTr("Back")
            }
            return pageValue("forkBackTitle", qsTr("Your PCs"))
        }
        pageTitle: window.isSettingsPage ? qsTr("Settings") : ""
        searchPlaceholder: pageValue("forkSearchPlaceholder", qsTr("Search apps"))
        searchAccessibleName: pageValue("forkSearchAccessibleName",
                                        window.forkPage && window.forkPage.objectName !== ""
                                        ? qsTr("Search the apps on %1").arg(window.forkPage.objectName) : searchPlaceholder)
        updateReady: ForkUpdater.updateReady && updateButton.browserUrl !== ""
        updateTip: updateButton.tip
        discordVisible: SystemProperties.hasBrowser && window.isSettingsPage
        addPcTip: qsTr("Add PC manually") + (newPcShortcut.nativeText ? (" (" + newPcShortcut.nativeText + ")") : "")
        helpTip: qsTr("Help") + (helpShortcut.nativeText ? (" (" + helpShortcut.nativeText + ")") : "")
        settingsTip: qsTr("Settings") + (settingsShortcut.nativeText ? (" (" + settingsShortcut.nativeText + ")") : "")

        onViewModeRequested: function(mode) {
            if (window.forkPage && window.forkPage.forkSetViewMode) {
                window.forkPage.forkSetViewMode(mode)
            }
        }
        onAddPcRequested: window.addPc()
        onHelpRequested: forkShortcutsDialog.open()
        onSettingsRequested: settingsButton.clicked()
        onUpdateRequested: updateButton.clicked()
        onDiscordRequested: Qt.openUrlExternally("https://moonlight-stream.org/discord")
        onBackRequested: goBack()
        onSearchEdited: function(text) {
            if (window.forkPage && window.forkPage.forkSetQuery) {
                window.forkPage.forkSetQuery(text)
            }
        }
        onPageFocusRequested: {
            if (window.forkPage) {
                window.forkPage.forceActiveFocus(Qt.TabFocus)
            }
        }
        onZoomRequested: WindowChrome.zoomWindow(window)

        // A new page starts with an empty search
        Connections {
            target: stackView
            function onCurrentItemChanged() {
                toolBar.searchText = ""
            }
        }

        // D9: the page's own Clear Search, and a page that sets its query itself, empty or follow the
        // header's field (the field to the page goes through forkSetQuery)
        Connections {
            target: window.forkPage
            ignoreUnknownSignals: true
            function onForkSearchCleared() {
                toolBar.searchText = ""
            }
            function onForkQueryChanged() {
                var query = window.forkPage ? window.forkPage.forkQuery : undefined
                if (typeof query === "string" && query !== toolBar.searchText) {
                    toolBar.searchText = query
                }
            }
        }
    }

    ForkWindowFooter {
        id: pageFooter
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        z: 3
        visible: toolBar.visible
        skySource: sky.shown ? sky : null
        opaque: toolBar.opaque
    }

    // Header actions that other code calls or that have shortcuts. Add PC, Help and Settings are
    // the header's buttons; their shortcuts work on every page.
    QtObject {
        id: settingsButton
        signal clicked()
        // [fork] The redesign's Settings (was SettingsView)
        onClicked: navigateTo("qrc:/gui/ForkSettingsView.qml", ForkSettingsView)
    }

    // D4: a page can take Add PC itself (PcView on the first run); otherwise it's the dialog
    function addPc() {
        if (forkPage && typeof forkPage.forkAddPc === "function") {
            forkPage.forkAddPc()
        }
        else {
            addPcDialog.open()
        }
    }

    Shortcut {
        id: newPcShortcut
        sequence: StandardKey.New
        onActivated: window.addPc()
    }

    Shortcut {
        id: helpShortcut
        sequence: StandardKey.HelpContents
        onActivated: forkShortcutsDialog.open()
    }

    Shortcut {
        id: settingsShortcut
        sequence: StandardKey.Preferences
        onActivated: settingsButton.clicked()
    }

    // ⌘F on All apps goes to the header's search
    Shortcut {
        sequence: StandardKey.Find
        enabled: toolBar.visible && toolBar.variant === "apps"
        onActivated: toolBar.focusSearch()
    }

    // The "update ready" state of the header's Update pill, and the app wiring that used to live in
    // the Update button's Component.onCompleted (LuzLunar's own over-the-air updates, ForkUpdater,
    // and the toasts of Apollo PCs' updates and power actions)
    QtObject {
        id: updateButton
        property string browserUrl: ""
        property string tip: ""

        // LuzLunar's own update, in Settings › Updates (was upstream's download page)
        function clicked() {
            navigateTo("qrc:/gui/ForkSettingsView.qml", ForkSettingsView)
            if (window.forkPage instanceof ForkSettingsView) {
                window.forkPage.showSection("updates")
            }
        }

        function updateAvailable(version, url) {
            tip = qsTr("LuzLunar %1 is ready to install").arg(version) // [fork]
            browserUrl = url
        }

        Component.onCompleted: {
            ForkUpdater.changed.connect(function() {
                if (ForkUpdater.updateReady && ForkUpdater.supported) {
                    updateAvailable(ForkUpdater.latestVersion, "luzlunar:update")
                }
                else {
                    updateButton.browserUrl = ""
                }
            })
            ForkUpdater.start()
            if (ForkUpdater.lastResult !== "") {
                window.forkToast(ForkUpdater.lastResult)
            }
            ForkHostUpdates.setComputerManager(ComputerManager)
            ForkHostUpdates.finished.connect(function(uuid, text) {
                window.forkToast(text)
            })
            ForkHostPower.setComputerManager(ComputerManager)
            ForkHostPower.finished.connect(function(uuid, ok, text) {
                window.forkToast(text)
            })
            // [fork] Set Up Wake from Off's outcome, and whether a PC Wake PC was sent to woke or was turned on
            ForkHostPower.wakeFinished.connect(function(uuid, ok, text) {
                window.forkToast(text)
            })
            ForkHostPower.poweredOn.connect(function(uuid, text) {
                window.forkToast(text)
            })
        }
    }

    StackView {
        id: stackView
        // [fork] The pages sit between the header and the footer (the sky fills the window behind all three)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: toolBar.visible ? toolBar.bottom : parent.top
        anchors.bottom: pageFooter.visible ? pageFooter.top : parent.bottom
        focus: true

        // [fork] Hold transitions: pages don't slide. Your PCs steps back and All apps grows from its
        // tile on their own (sky-chrome.md §7.3), so the page leaving only stays for as long as that
        // takes (its forkHoldMs: PcView 480, AppView 440), when the page coming in animates too.
        // Pages without forkHoldMs (Settings) change at once.
        function holdFor(item) {
            var entering = stackView.currentItem
            if (!item || !entering || item.forkHoldMs === undefined || entering.forkHoldMs === undefined) {
                return 0
            }
            return item.forkHoldMs
        }
        pushEnter: Transition { }
        popEnter: Transition { }
        pushExit: Transition {
            PauseAnimation { duration: ForkTheme.reduceMotion ? 0 : stackView.holdFor(ViewTransition.item) }
        }
        popExit: Transition {
            PauseAnimation { duration: ForkTheme.reduceMotion ? 0 : stackView.holdFor(ViewTransition.item) }
        }

        Component.onCompleted: {
            // [fork] CI's hidden screenshot run only renders when the harness grabs the window, and
            // the style's XAnimator transitions start at a render and stop at the grab's teardown,
            // so a page would never finish coming in: change pages at once there
            if (forkHiddenScreenshots) {
                pushEnter = null
                pushExit = null
                popEnter = null
                popExit = null
                replaceEnter = null
                replaceExit = null
            }

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
        // Polling is only managed from the window for a normal GUI launch;
        // CLI commands (stream/quit/pair) manage it via the ComputerSeeker.
        if (isGuiLaunch) {
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
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    onActiveChanged: {
        // Polling is only managed from the window for a normal GUI launch;
        // CLI commands (stream/quit/pair) manage it via the ComputerSeeker.
        if (isGuiLaunch) {
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
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    // [fork] The redesign's toasts: a short confirmation at the bottom of the window, above dialogs
    // ("Renamed to Office PC"). Any page can call window.forkToast(text).
    function forkToast(text, ms) {
        forkToasts.show(text, ms)
    }
    function forkToastHide() {
        forkToasts.hide()
    }

    // In the window's overlay, where dialogs and menus go, above them all. The Overlay type has to
    // come from the T import: with this file's QtQuick.Controls 2.2 it's undefined, and the toasts
    // stayed in the window's content, under any open dialog and its dim.
    ForkToast {
        id: forkToasts
        parent: T.Overlay.overlay
        z: 1000
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18 + (pageFooter.visible ? pageFooter.height : 0) // [fork] the canvas's 54 above the bottom, clear of the footer
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
