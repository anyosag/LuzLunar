import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Effects // [fork] MultiEffect, for the rounded box art
import QtQml // [fork] Instantiator, to count the hidden apps
// [fork] No explicit Material import: it would override the native macOS style set in main.cpp

import AppModel 1.0
import ComputerManager 1.0
import SdlGamepadKeyNavigation 1.0
import AspectRatios 1.0 // [fork]
import ForkTheme 1.0 // [fork]
import StreamProfiles 1.0 // [fork]
import StreamingPreferences 1.0 // [fork]
import SfSymbols 1.0 // [fork]
import SystemProperties 1.0 // [fork]

CenteredGridView {
    property int computerIndex
    // [fork] Two models of the PC's apps: one without the hidden apps, one with every app. The grid
    // shows one of them (forkShowHidden), so hidden apps can be shown and hidden again in place;
    // the full one also tells how many apps are hidden. Was one model made by createModel().
    property bool forkShowHidden: showHiddenGames
    property AppModel forkVisibleModel : createModel(false)
    property AppModel forkFullModel : createModel(true)
    property AppModel appModel : forkShowHidden ? forkFullModel : forkVisibleModel
    property bool activated
    property bool showHiddenGames
    property bool showGames
    property string forkHostStatus: "" // [fork] e.g. "Apollo · online", set by PcView; shown under the toolbar title

    id: appGrid
    focus: true
    activeFocusOnTab: true
    topMargin: 0 // [fork] the header holds the page's top space (was 20)
    bottomMargin: 24 // [fork] was 5

    // [fork] The design's grid: tiles at least 156 wide, 20 apart and 28 between rows, stretched to
    // fill a centered block at most 1152 wide (CenteredGridView). A tile is the box art (3:4), 10,
    // the name, 6 and a row of chips; the grid's cell adds the gap to the next row.
    forkStretch: true
    forkMinItemWidth: 156
    forkGap: 20
    readonly property real forkRowGap: 28
    readonly property real forkArtHeight: Math.round(forkItemWidth * 4 / 3)
    readonly property real forkTileHeight: forkArtHeight + 10 + 18 + 6 + 22
    cellWidth: forkItemWidth + forkGap
    cellHeight: forkTileHeight + forkRowGap

    // [fork] The running app, for the header's banner. Tiles report it as they're created; a
    // model change with nothing running clears it.
    property int forkRunningIndex: -1
    property string forkRunningName: ""
    property url forkRunningBoxart
    // Bumped when the stream settings dialog closes, so the tiles' profile chips are read again
    property int forkProfileRevision: 0
    readonly property string forkHostUuid: StreamProfiles.hostUuid(ComputerManager, computerIndex)

    // The user has scrolled the grid by hand (see the header's onHeightChanged)
    property bool forkUserScrolled: false

    // [fork] How many apps there are and how many of them are hidden, read off the full model's rows
    readonly property int forkAppTotal: forkCounter.count
    property int forkHiddenCount: 0

    function forkNoteRunning(index, running, name, boxart) {
        if (running) {
            forkRunningIndex = index
            forkRunningName = name
            forkRunningBoxart = boxart
        }
        else if (forkRunningIndex === index) {
            forkRunningIndex = -1
        }
    }

    function forkCountHidden() {
        var hidden = 0
        for (var i = 0; i < forkCounter.count; i++) {
            var row = forkCounter.objectAt(i)
            if (row && row.hidden) {
                hidden++
            }
        }
        forkHiddenCount = hidden
    }

    function forkRecount() {
        forkCountHidden()
        // Again once the model has settled
        Qt.callLater(forkCountHidden)
    }

    // [fork] Shows or hides the hidden apps in the grid, in place. The tiles are made again, so
    // each one tells whether it's the running app.
    function forkSetShowHidden(show) {
        if (show === forkShowHidden) {
            return
        }
        forkRunningIndex = -1
        currentIndex = -1
        if (!show) {
            // A model keeps the apps that were visible when it was made (so a slip can be undone),
            // so apps hidden since then need a new one to leave the grid
            if (activated) {
                forkVisibleModel.computerLost.disconnect(computerLost)
            }
            forkVisibleModel = createModel(false)
            if (activated) {
                forkVisibleModel.computerLost.connect(computerLost)
            }
        }
        forkShowHidden = show
    }

    // What a stream of this app would use: the global settings with its profile applied, as
    // StreamProfiles::createSession does.
    function forkEffectiveStream(appName) {
        var p = StreamProfiles.profile(forkHostUuid, appName)
        function has(key) { return p[key] !== undefined }
        var w = has("width") ? p.width : StreamingPreferences.width
        var h = has("height") ? p.height : StreamingPreferences.height
        var fps = has("fps") ? p.fps : StreamingPreferences.fps
        var yuv = has("enableYUV444") ? p.enableYUV444 : StreamingPreferences.enableYUV444
        var codec = has("videoCodecConfig") ? p.videoCodecConfig : StreamingPreferences.videoCodecConfig
        // H.264 has no HDR, so an HDR setting leaves that stream in SDR
        var hdr = SystemProperties.supportsHdr && codec !== StreamingPreferences.VCC_FORCE_H264 &&
                  (has("enableHdr") ? p.enableHdr : StreamingPreferences.enableHdr)
        var bitrate = has("bitrateKbps") ? p.bitrateKbps : StreamingPreferences.bitrateKbps
        if (!has("bitrateKbps") && (has("width") || has("height") || has("fps") || has("enableYUV444")) &&
                StreamingPreferences.bitrateKbps === StreamingPreferences.getDefaultBitrate(StreamingPreferences.width, StreamingPreferences.height,
                                                                                            StreamingPreferences.fps, StreamingPreferences.enableYUV444)) {
            bitrate = StreamingPreferences.getDefaultBitrate(w, h, fps, yuv)
        }
        var trackpad = has("trackpadMode") ? p.trackpadMode : StreamingPreferences.trackpadMode
        return { "profile": p, "width": w, "height": h, "fps": fps, "yuv": yuv, "hdr": hdr, "codec": codec, "bitrate": bitrate,
                 "trackpad": trackpad }
    }

    // "Mac trackpad" or "Touchpad" (the Windows touchpad), or nothing for a trackpad that's a mouse
    function forkTrackpadChip(mode) {
        return mode === StreamingPreferences.TM_MAC_TRACKPAD ? qsTr("Mac trackpad")
             : mode === StreamingPreferences.TM_WINDOWS_TOUCHPAD ? qsTr("Touchpad")
             : ""
    }

    function forkCodecName(codec) {
        return codec === StreamingPreferences.VCC_FORCE_H264 ? "H.264"
             : codec === StreamingPreferences.VCC_FORCE_AV1 ? "AV1"
             : codec === StreamingPreferences.VCC_FORCE_HEVC ? "HEVC"
             : qsTr("Automatic codec")
    }

    // The name a profile goes by everywhere: "Office profile", "Gaming profile" or "Custom profile";
    // empty for an app with none
    function forkProfileName(profile) {
        return Object.keys(profile).length > 0 ? streamProfileDialog.profileName(profile) : ""
    }

    // Chips for the launch screen. The profile's name is last, as an object so the panel shows it
    // in the text font like the design.
    function forkStreamSummary(appName) {
        var e = forkEffectiveStream(appName)
        var chips = [e.width + "×" + e.height + " · " + AspectRatios.ratioLabel(e.width, e.height), qsTr("%1 fps").arg(e.fps),
                     qsTr("%1 Mb/s").arg(e.bitrate / 1000), forkCodecName(e.codec) + (e.hdr ? " · HDR" : "")]
        if (e.yuv) {
            chips.push("4:4:4")
        }
        if (forkTrackpadChip(e.trackpad) !== "") {
            chips.push(forkTrackpadChip(e.trackpad))
        }
        var profile = forkProfileName(e.profile)
        if (profile !== "") {
            chips.push({ "text": profile, "plain": true })
        }
        return chips
    }

    // The banner's one line for the running app, like "3024×1890 · 120 fps · HEVC 10-bit · Office profile"
    function forkBannerSummary(appName) {
        var e = forkEffectiveStream(appName)
        var codec = forkCodecName(e.codec)
        if (e.hdr) {
            codec += e.codec === StreamingPreferences.VCC_AUTO ? " · HDR" : " 10-bit"
        }
        var parts = [e.width + "×" + e.height, qsTr("%1 fps").arg(e.fps), codec]
        var profile = forkProfileName(e.profile)
        if (profile !== "") {
            parts.push(profile)
        }
        return parts.join(" · ")
    }

    header: ForkAppsHeader {
        width: appGrid.forkContentWidth
        hasRunning: appGrid.forkRunningIndex >= 0
        runningName: appGrid.forkRunningName
        runningBoxart: appGrid.forkRunningBoxart
        runningSummary: {
            appGrid.forkProfileRevision
            return appGrid.forkRunningIndex >= 0 ? appGrid.forkBannerSummary(appGrid.forkRunningName) : ""
        }
        showingHidden: appGrid.forkShowHidden
        appCount: appGrid.forkAppTotal - appGrid.forkHiddenCount
        hiddenCount: appGrid.forkHiddenCount

        onResume: {
            var tile = appGrid.itemAtIndex(appGrid.forkRunningIndex)
            if (tile) {
                tile.launchOrResumeSelectedApp(true)
            }
        }
        onQuit: {
            var tile = appGrid.itemAtIndex(appGrid.forkRunningIndex)
            if (tile) {
                tile.doQuitGame()
            }
        }
        onToggleHidden: appGrid.forkSetShowHidden(!appGrid.forkShowHidden)

        // The banner shows once the tiles say which app runs, which makes the header taller after
        // the view has been placed; unless the user has scrolled, keep the top in view
        onHeightChanged: {
            if (!appGrid.forkUserScrolled) {
                Qt.callLater(appGrid.positionViewAtBeginning)
            }
        }
    }
    onMovementStarted: forkUserScrolled = true // [fork]

    // [fork] Counts the hidden apps: one row per app of the full model
    Instantiator {
        id: forkCounter
        model: appGrid.forkFullModel

        delegate: QtObject {
            required property bool hidden
            onHiddenChanged: appGrid.forkRecount()
        }

        onObjectAdded: appGrid.forkRecount()
        onObjectRemoved: appGrid.forkRecount()
    }

    Connections {
        target: appGrid.appModel
        function onDataChanged() {
            if (appGrid.appModel.getRunningAppId() === 0) {
                appGrid.forkRunningIndex = -1
            }
        }
        function onModelReset() {
            if (appGrid.appModel.getRunningAppId() === 0) {
                appGrid.forkRunningIndex = -1
            }
        }
    }

    function computerLost()
    {
        // Go back to the PC view on PC loss
        stackView.pop()
    }

    Component.onCompleted: {
        // Don't show any highlighted item until interacting with them.
        // We do this here instead of onActivated to avoid losing the user's
        // selection when backing out of a different page of the app.
        currentIndex = -1
    }

    StackView.onActivated: {
        forkVisibleModel.computerLost.connect(computerLost) // [fork] was appModel, which can be swapped now
        activated = true
        forkCountHidden() // [fork]

        // Highlight the first item if a gamepad is connected
        if (currentIndex === -1 && SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            currentIndex = 0
        }

        if (!showGames && !showHiddenGames) {
            // Check if there's a direct launch app
            var directLaunchAppIndex = model.getDirectLaunchAppIndex();
            if (directLaunchAppIndex >= 0) {
                // Start the direct launch app if nothing else is running
                currentIndex = directLaunchAppIndex
                currentItem.launchOrResumeSelectedApp(false)

                // Set showGames so we will not loop when the stream ends
                showGames = true
            }
        }
    }

    StackView.onDeactivating: {
        forkVisibleModel.computerLost.disconnect(computerLost) // [fork] was appModel
        activated = false
    }

    // [fork] A tooltip's text can't be set to plain, and the host picks app names, so markup in
    // one is escaped to show as it's spelled. Text without "<" holds no markup and is left alone.
    function escapeMarkup(text)
    {
        if (!text || text.indexOf("<") < 0) {
            return text
        }
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function createModel(showHidden) // [fork] was without the argument, showing showHiddenGames
    {
        var model = Qt.createQmlObject('import AppModel 1.0; AppModel {}', parent, '')
        model.initialize(ComputerManager, computerIndex, showHidden)
        return model
    }

    model: appModel

    delegate: NavigableItemDelegate {
        id: tile
        width: appGrid.forkItemWidth; height: appGrid.forkTileHeight; // [fork] the design's tile: box art, name and chips fill the grid's column (was 220x287)
        grid: appGrid
        // [fork] No card behind the tile: the art's overlay shows hover and focus, as in the design
        background: Item {}

        // [fork] VoiceOver says what a click does
        Accessible.role: Accessible.Button
        Accessible.name: model.running ? qsTr("Resume %1").arg(model.name) : qsTr("Start %1").arg(model.name)
        Accessible.description: forkChips.join(", ")

        // [fork] Tells the header whether this is the running app
        readonly property bool forkRunning: model.running
        onForkRunningChanged: appGrid.forkNoteRunning(index, forkRunning, model.name, appIcon.isPlaceholder ? "" : model.boxart)
        Component.onCompleted: appGrid.forkNoteRunning(index, model.running, model.name, appIcon.isPlaceholder ? "" : model.boxart)

        // [fork] This app's chips: its stream profile (Office, Gaming or Custom, with Stretch, Mac
        // trackpad or Touchpad, and the aspect ratio when the profile sets them), direct launch, hidden
        readonly property var forkChips: {
            appGrid.forkProfileRevision
            var chips = []
            var profile = StreamProfiles.profile(appGrid.forkHostUuid, model.name)
            if (Object.keys(profile).length > 0) {
                chips.push(appGrid.forkProfileName(profile))
                if (profile.fullscreenStretch === true) {
                    chips.push(qsTr("Stretch"))
                }
                if (profile.trackpadMode !== undefined && appGrid.forkTrackpadChip(profile.trackpadMode) !== "") {
                    chips.push(appGrid.forkTrackpadChip(profile.trackpadMode))
                }
                if (profile.width !== undefined && profile.height !== undefined) {
                    chips.push(AspectRatios.ratioLabel(profile.width, profile.height))
                }
            }
            if (model.directLaunch) {
                chips.push(qsTr("Direct launch"))
            }
            if (model.hidden) {
                chips.push(qsTr("Hidden"))
            }
            return chips
        }

        property alias appContextMenu: appContextMenuLoader.item

        // [fork] The box art and what's drawn on it. A hidden app dims only this (not its name
        // and chips, or the buttons on it).
        Item {
            id: art
            width: parent.width
            height: appGrid.forkArtHeight
            opacity: model.hidden ? 0.45 : 1.0

            Image {
                property bool isPlaceholder: false

                id: appIcon
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop // [fork]
                source: model.boxart

                onSourceSizeChanged: {
                    // Nearly all of Nvidia's official box art does not match the dimensions of placeholder
                    // images, however the one known exception is Overcooked. Therefore, we only execute
                    // the image size checks if this is not an app collector game. We know the officially
                    // supported games all have box art, so this check is not required.
                    if (!model.isAppCollectorGame &&
                        ((sourceSize.width === 130 && sourceSize.height === 180) || // GFE 2.0 placeholder image
                         (sourceSize.width === 628 && sourceSize.height === 888) || // GFE 3.0 placeholder image
                         (sourceSize.width === 200 && sourceSize.height === 266)))  // Our no_app_image.png
                    {
                        isPlaceholder = true
                    }
                    else
                    {
                        isPlaceholder = false
                    }
                }

                // Display a tooltip with the full name if it's truncated
                ToolTip.text: appGrid.escapeMarkup(model.name) // [fork] was model.name
                ToolTip.delay: 1000
                ToolTip.timeout: 5000
                ToolTip.visible: (tile.hovered || tile.highlighted) && nameLabel.truncated // [fork] the name sits under the art now

                // [fork] The themed tile below stands in for the host's grey placeholder art
                opacity: isPlaceholder ? 0 : 1

                // [fork] Rounded corners, like artwork in macOS apps (square where effects can't draw:
                // the software renderer of offscreen screenshots)
                layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                layer.smooth: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: appIconMask
                    // Antialiased edges
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
            }

            // [fork] The shape the box art is cut to (only used as a mask, never drawn)
            Rectangle {
                id: appIconMask
                anchors.fill: parent
                radius: ForkTheme.radiusTile
                visible: false
                layer.enabled: true
                layer.smooth: true
            }

            // [fork] A themed tile under the host's placeholder art (or while art loads), with the
            // app's name, or a display for the Desktop
            Rectangle {
                anchors.fill: parent
                visible: appIcon.isPlaceholder || appIcon.status !== Image.Ready
                radius: appIconMask.radius
                color: ForkTheme.tile
                border.color: ForkTheme.line
            }

            Loader {
                id: appNameTextLoader
                active: appIcon.isPlaceholder

                // This loader is not asynchronous to avoid noticeable differences
                // in the time in which the text loads for each game.

                anchors.fill: parent

                sourceComponent: Item {
                    readonly property bool desktop: model.name === "Desktop" && SfSymbols.available

                    ForkSymbol {
                        anchors.centerIn: parent
                        visible: parent.desktop
                        symbol: "display"
                        size: 46
                        color: ForkTheme.text2
                    }

                    Label {
                        id: appNameText
                        anchors.fill: parent
                        visible: !parent.desktop
                        text: model.name
                        textFormat: Text.PlainText // [fork] the host picks app names, never markup
                        font.pixelSize: 22 // [fork] the themed tile's wordmark (was pointSize 22)
                        font.weight: Font.Bold // [fork]
                        font.letterSpacing: -0.22 // [fork]
                        color: ForkTheme.text // [fork]
                        leftPadding: 14
                        rightPadding: 14
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                    }
                }
            }

            // [fork] A thin edge around real art so dark art doesn't melt into the page
            Rectangle {
                anchors.fill: parent
                visible: !appIcon.isPlaceholder && appIcon.status === Image.Ready
                radius: appIconMask.radius
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.07)
            }

            // [fork] The redesign's overlay on the box art (on the running app too): a gold edge and a
            // play disc on hover or focus. Resume and Quit are in the header's banner.
            Rectangle {
                anchors.fill: parent
                radius: appIconMask.radius
                color: Qt.rgba(10 / 255, 14 / 255, 28 / 255, 0.5)
                border.width: 2
                border.color: "#F5C878"
                opacity: tile.hovered || tile.highlighted ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 56
                    height: 56
                    radius: 28
                    color: "#F5C878"

                    ForkSymbol {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 2
                        symbol: "play.fill"
                        fallback: "qrc:/res/play_arrow_FILL1_wght700_GRAD200_opsz48.svg"
                        size: 22
                        color: "#1A1405"
                    }
                }
            }
        }

        // [fork] The running app's badge
        Rectangle {
            x: 10
            y: 10
            visible: model.running
            width: runningBadge.implicitWidth + 18
            height: 22
            radius: 11
            color: Qt.rgba(10 / 255, 14 / 255, 28 / 255, 0.84)

            Row {
                id: runningBadge
                anchors.centerIn: parent
                spacing: 6

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 3.5
                    color: "#79D6B5"
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Running")
                    font.family: ForkTheme.uiFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: "#79D6B5"
                }
            }
        }

        // [fork] The menu button, always there: a 44 point target with a 32 point disc on the art
        ForkButton {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.top: parent.top
            anchors.topMargin: 4
            kind: "quiet"
            symbol: "ellipsis"
            symbolSize: 18
            focusPolicy: Qt.NoFocus
            Accessible.name: qsTr("More for %1").arg(model.name)
            background: Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: 32
                    height: 32
                    radius: 16
                    color: Qt.rgba(10 / 255, 14 / 255, 28 / 255, 0.62)
                }
            }
            // On box art in either appearance, so the symbol stays light
            foreground: "#ECEEF6"
            onClicked: appContextMenu.open()
        }

        // [fork] The name and chips under the box art
        Column {
            anchors.top: art.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.right: parent.right
            anchors.rightMargin: 2
            spacing: 6

            ForkText {
                id: nameLabel
                width: parent.width
                height: 18
                kind: "label"
                font.pixelSize: 14
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: model.name
            }

            // Room for two rows of chips (the gap to the next row of tiles holds the second)
            Flow {
                width: parent.width
                height: Math.min(childrenRect.height, 46)
                spacing: 6
                clip: true

                Repeater {
                    model: forkChips

                    delegate: Rectangle {
                        required property string modelData

                        width: chipText.implicitWidth + 16
                        height: 20
                        radius: 6
                        color: ForkTheme.raised

                        ForkText {
                            id: chipText
                            anchors.centerIn: parent
                            kind: "body"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: ForkTheme.text2
                            wrapMode: Text.NoWrap
                            text: parent.modelData
                        }
                    }
                }
            }
        }

        function launchOrResumeSelectedApp(quitExistingApp)
        {
            var runningId = appModel.getRunningAppId()
            if (runningId !== 0 && runningId !== model.appid) {
                if (quitExistingApp) {
                    quitAppDialog.appName = appModel.getRunningAppName()
                    quitAppDialog.segueToStream = true
                    quitAppDialog.nextAppName = model.name
                    quitAppDialog.nextAppIndex = index
                    quitAppDialog.open()
                }

                return
            }

            var component = Qt.createComponent("StreamSegue.qml")
            var segue = component.createObject(stackView, {
                                                   "appName": model.name,
                                                   "session": appModel.createSessionForApp(index),
                                                   "isResume": runningId === model.appid,
                                                   "hostName": appGrid.objectName, // [fork] for the launch screen
                                                   "summary": appGrid.forkStreamSummary(model.name) // [fork]
                                               })
            stackView.push(segue)
        }

        onClicked: {
            // [fork] A click resumes the running app too (the banner above the grid has Resume and
            // Quit); upstream ignored clicks on it
            launchOrResumeSelectedApp(true)
        }

        onPressAndHold: {
            // popup() ensures the menu appears under the mouse cursor
            if (appContextMenu.popup) {
                appContextMenu.popup()
            }
            else {
                // Qt 5.9 doesn't have popup()
                appContextMenu.open()
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton;
            onClicked: {
                parent.pressAndHold()
            }
        }

        Keys.onReturnPressed: {
            // Open the app context menu if activated via the gamepad or keyboard
            // for running games. If the game isn't running, the above onClicked
            // method will handle the launch.
            if (model.running) {
                // This will be keyboard/gamepad driven so use
                // open() instead of popup()
                appContextMenu.open()
            }
        }

        Keys.onEnterPressed: {
            // Open the app context menu if activated via the gamepad or keyboard
            // for running games. If the game isn't running, the above onClicked
            // method will handle the launch.
            if (model.running) {
                // This will be keyboard/gamepad driven so use
                // open() instead of popup()
                appContextMenu.open()
            }
        }

        Keys.onMenuPressed: {
            // This will be keyboard/gamepad driven so use open() instead of popup()
            appContextMenu.open()
        }

        function doQuitGame() {
            quitAppDialog.appName = appModel.getRunningAppName()
            quitAppDialog.segueToStream = false
            quitAppDialog.open()
        }

        Loader {
            id: appContextMenuLoader
            asynchronous: true
            sourceComponent: NavigableMenu {
                id: appContextMenu
                initiator: appContextMenuLoader.parent
                NavigableMenuItem {
                    symbol: "play.fill" // [fork]
                    text: model.running ? qsTr("Resume Game") : qsTr("Launch Game")
                    onTriggered: launchOrResumeSelectedApp(true)
                }
                NavigableMenuItem {
                    symbol: "bolt.fill" // [fork]
                    checkable: true
                    checked: model.directLaunch
                    text: qsTr("Direct Launch")
                    onTriggered: {
                        // [fork] The design confirms what a click on the PC does now
                        var wasOn = model.directLaunch
                        var appName = model.name
                        appModel.setAppDirectLaunch(model.index, !wasOn)
                        window.forkToast(wasOn ? qsTr("Direct launch is off")
                                               : qsTr("Clicking %1 now starts %2").arg(appGrid.objectName).arg(appName))
                    }
                    enabled: !model.hidden

                    ToolTip.text: qsTr("Launch this app immediately when the host is selected, bypassing the app selection grid.")
                    ToolTip.delay: 1000
                    ToolTip.timeout: 3000
                    ToolTip.visible: hovered
                }
                NavigableMenuItem {
                    symbol: "eye.slash" // [fork]
                    checkable: true
                    checked: model.hidden
                    text: qsTr("Hide Game")
                    onTriggered: {
                        // [fork] The design confirms where the app went
                        var wasHidden = model.hidden
                        var appName = model.name
                        appModel.setAppHidden(model.index, !wasHidden)
                        window.forkToast(wasHidden ? qsTr("%1 is back in the grid").arg(appName)
                                                   : qsTr("%1 is hidden. Show hidden apps to find it.").arg(appName))
                    }
                    enabled: model.hidden || (!model.running && !model.directLaunch)

                    ToolTip.text: qsTr("Hide this game from the app grid. To access hidden games, right-click on the host and choose %1.").arg(qsTr("View All Apps"))
                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                }
                ForkMenuSeparator {} // [fork]
                // [fork] per-app stream settings
                NavigableMenuItem {
                    symbol: "slider.horizontal.3" // [fork]
                    text: qsTr("Stream Settings...")
                    onTriggered: streamProfileDialog.openFor(computerIndex, model.name)
                }
                ForkMenuSeparator { // [fork]
                    visible: model.running
                }
                NavigableMenuItem {
                    symbol: "stop.fill" // [fork]
                    destructive: true // [fork]
                    text: qsTr("Quit Game")
                    onTriggered: doQuitGame()
                    visible: model.running
                }
            }
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 5
        visible: appGrid.count === 0

        Label {
            // [fork] Every app hidden has its own words (the header's link shows them)
            text: appGrid.forkHiddenCount > 0 && !appGrid.forkShowHidden
                  ? qsTr("Every app on this PC is hidden. Show hidden apps to see them.")
                  : qsTr("This computer doesn't seem to have any applications or some applications are hidden")
            font.pointSize: 15 // [fork] was 20
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }
    }

    NavigableMessageDialog {
        id: quitAppDialog
        property string appName : ""
        property bool segueToStream : false
        property string nextAppName: ""
        property int nextAppIndex: 0
        // [fork] The design's wording: quitting asks "Quit X?" with a red Quit; starting another app
        // says why it has to quit this one (was "Are you sure you want to quit %1? Any unsaved
        // progress will be lost." for both)
        title: segueToStream ? qsTr("%1 is running").arg(appName) : qsTr("Quit %1?").arg(appName)
        text: segueToStream ? qsTr("%1 runs one app at a time. Quitting %2 loses anything you haven't saved in it.").arg(appGrid.objectName).arg(appName)
                            : qsTr("It closes on %1. Anything you haven't saved is lost.").arg(appGrid.objectName)
        destructive: !segueToStream
        standardButtons: Dialog.Yes | Dialog.No

        onAboutToShow: {
            var yes = footer.standardButton(Dialog.Yes)
            var no = footer.standardButton(Dialog.No)
            if (yes) {
                yes.text = segueToStream ? qsTr("Quit it and start %1").arg(nextAppName) : qsTr("Quit")
            }
            if (no) {
                no.text = qsTr("Cancel")
            }
        }

        function quitApp() {
            var component = Qt.createComponent("QuitSegue.qml")
            var params = {"appName": appName, "quitRunningAppFn": function() { appModel.quitRunningApp() }}
            if (segueToStream) {
                // Store the session and app name if we're going to stream after
                // successfully quitting the old app.
                params.nextAppName = nextAppName
                params.nextSession = appModel.createSessionForApp(nextAppIndex)
                params.nextHostName = appGrid.objectName // [fork] for the next app's launch screen
                params.nextSummary = appGrid.forkStreamSummary(nextAppName) // [fork]
            }
            else {
                params.nextAppName = null
                params.nextSession = null

                // [fork] The design confirms the quit, once the host has done it
                var quitName = appName
                var quitDone = function(error) {
                    ComputerManager.quitAppCompleted.disconnect(quitDone)
                    if (error === undefined) {
                        window.forkToast(qsTr("Quit %1 on %2").arg(quitName).arg(appGrid.objectName))
                    }
                }
                ComputerManager.quitAppCompleted.connect(quitDone)
            }

            stackView.push(component.createObject(stackView, params))
        }

        onAccepted: quitApp()
    }

    // [fork] per-app stream settings
    StreamProfileDialog {
        id: streamProfileDialog
        onClosed: appGrid.forkProfileRevision++ // [fork] the tiles' chips
    }

    // [fork] The notch bar's Stream Settings saved a profile during a stream: the tiles' chips
    Connections {
        target: StreamProfiles
        function onProfileSaved() {
            appGrid.forkProfileRevision++
        }
    }

    ScrollBar.vertical: ScrollBar {}
}
