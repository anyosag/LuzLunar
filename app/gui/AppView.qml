import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Effects // [fork] MultiEffect, for the rounded box art and the running app's glow
import QtQml // [fork] Instantiator, to count the hidden apps
// [fork] No explicit Material import: it would override the native macOS style set in main.cpp

import AppModel 1.0
import ComputerManager 1.0
import SdlGamepadKeyNavigation 1.0
import AspectRatios 1.0 // [fork]
import ForkHostUpdates 1.0 // [fork] Apollo's version, for the header
import ForkTheme 1.0 // [fork]
import StreamProfiles 1.0 // [fork]
import StreamingPreferences 1.0 // [fork]
import SfSymbols 1.0 // [fork]
import SystemProperties 1.0 // [fork]

CenteredGridView {
    property int computerIndex
    // [fork] Two models of the PC's apps for the grid: one without the hidden apps, one with every
    // app. The grid shows one of them (forkShowHidden), so hidden apps can be shown and hidden
    // again in place; both follow the search (forkQuery). A third, with every app and no search,
    // counts the apps and the hidden ones. Was one model made by createModel().
    property bool forkShowHidden: showHiddenGames
    // [fork] Sample apps for the screenshot harness: a ListModel with AppModel's roles (and
    // sampleProfile, "office", "gaming" or "custom") shown instead of a PC's, which asks nothing
    // of a host; forkSampleHost stands in for forkHostInfo
    property var forkSampleModel: null
    property var forkSampleHost: ({})
    readonly property bool forkSample: forkSampleModel !== null
    property AppModel forkVisibleModel : forkSample ? null : createModel(false)
    property AppModel forkFullModel : forkSample ? null : createModel(true)
    property AppModel forkCountModel : forkSample ? null : createModel(true)
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

    // [fork] The running app, for the header's band, read from the model by its ID
    // (AppModel.forkRunningApp()), since the grid only makes tiles for the rows in view and the
    // search and hidden apps move rows: {id, name, boxart}, or empty with nothing running
    property var forkRunning: ({})
    // Bumped when the stream settings dialog closes, so the tiles' profile chips are read again
    property int forkProfileRevision: 0
    readonly property string forkHostUuid: forkSample ? "" : StreamProfiles.hostUuid(ComputerManager, computerIndex)

    // [fork] The PC for the header's band: its address, whether that's on this Mac's network or
    // from outside, and its host software (AppModel.forkHostInfo()), with Apollo's version
    property var forkHostInfo: ({})
    readonly property string forkApolloVersion: {
        if (forkSample) {
            return forkSampleHost.version || ""
        }
        var info = ForkHostUpdates.revision >= 0 ? ForkHostUpdates.status(forkHostUuid) : ({})
        return info.known && info.version ? info.version : ""
    }
    // Like "Apollo 0.4.8 · Home network": which of the PC's addresses LuzLunar uses, the one on
    // its own network (from home, or over a VPN into it) or the one from outside
    readonly property string forkHostLine: {
        var parts = []
        var software = forkHostInfo.software || ""
        if (software !== "") {
            parts.push(software === "Apollo" && forkApolloVersion !== "" ? "Apollo " + forkApolloVersion : software)
        }
        if (forkHostInfo.local) {
            parts.push(qsTr("Home network"))
        }
        else if (forkHostInfo.remote) {
            parts.push(qsTr("Over the internet"))
        }
        return parts.join(" · ")
    }

    // [fork] The search's text, and how many apps match it (counted like the header's numbers)
    property string forkQuery: ""
    property int forkMatchCount: 0

    // The user has scrolled the grid by hand (see the header's onHeightChanged)
    property bool forkUserScrolled: false

    // [fork] How many apps there are and how many of them are hidden, read off the counting model's rows
    readonly property int forkAppTotal: forkCounter.count
    property int forkHiddenCount: 0

    function forkReadRunning() {
        if (forkSample) {
            var found = {}
            for (var i = 0; i < forkSampleModel.count; i++) {
                var row = forkSampleModel.get(i)
                if (row.running) {
                    found = { "id": row.appid, "name": row.name, "boxart": row.boxart }
                    break
                }
            }
            forkRunning = found
        }
        else {
            forkRunning = appModel ? appModel.forkRunningApp() : ({})
        }
    }
    onAppModelChanged: forkReadRunning()

    function forkCountHidden() {
        var hidden = 0
        var matches = 0
        var query = forkQuery.trim().toLowerCase()
        for (var i = 0; i < forkCounter.count; i++) {
            var row = forkCounter.objectAt(i)
            if (!row) {
                continue
            }
            if (row.hidden) {
                hidden++
            }
            if (query !== "" && (forkShowHidden || !row.hidden) && row.name.toLowerCase().indexOf(query) >= 0) {
                matches++
            }
        }
        forkHiddenCount = hidden
        forkMatchCount = matches
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
        currentIndex = -1
        if (!show && !forkSample) {
            // A model keeps the apps that were visible when it was made (so a slip can be undone),
            // so apps hidden since then need a new one to leave the grid
            if (activated) {
                forkVisibleModel.computerLost.disconnect(computerLost)
            }
            forkVisibleModel = createModel(false)
            forkVisibleModel.forkSetNameFilter(forkQuery)
            if (activated) {
                forkVisibleModel.computerLost.connect(computerLost)
            }
        }
        forkShowHidden = show
        forkRecount()
    }

    // [fork] The search: both models keep only the apps whose names contain the text (and the
    // running app, so the band's Resume and Quit still reach it). No tile is picked meanwhile:
    // when rows change the grid would give a picked tile the keyboard, away from the search.
    function forkSetQuery(text) {
        if (text === forkQuery) {
            return
        }
        currentIndex = -1
        forkQuery = text
        if (forkVisibleModel) {
            forkVisibleModel.forkSetNameFilter(text)
        }
        if (forkFullModel) {
            forkFullModel.forkSetNameFilter(text)
        }
        forkRecount()
    }

    function forkReadHost() {
        forkHostInfo = forkSample ? forkSampleHost : (forkVisibleModel ? forkVisibleModel.forkHostInfo() : ({}))
    }

    // [fork] The band's Resume and Quit, for the app that runs, wherever its tile is (or isn't).
    // A hidden app that runs isn't in the grid's model while hidden apps are hidden, so Resume
    // takes its row from the model with every app.
    function forkResumeRunning() {
        var id = forkRunning.id || 0
        if (!appModel || id === 0) {
            return
        }
        var model = appModel
        var row = model.forkIndexOfApp(id)
        if (row < 0 && forkFullModel) {
            model = forkFullModel
            row = model.forkIndexOfApp(id)
        }
        if (row < 0) {
            return
        }
        var component = Qt.createComponent("StreamSegue.qml")
        var segue = component.createObject(stackView, {
                                               "appName": forkRunning.name,
                                               "session": model.createSessionForApp(row),
                                               "isResume": true,
                                               "hostName": appGrid.objectName,
                                               "summary": appGrid.forkStreamSummary(forkRunning.name)
                                           })
        stackView.push(segue)
    }

    function forkQuitRunning() {
        if (!appModel || !forkRunning.id) {
            return
        }
        quitAppDialog.appName = forkRunning.name
        quitAppDialog.segueToStream = false
        quitAppDialog.open()
    }

    // [fork] The band's copy button. QML has no clipboard of its own, so a hidden text editor copies it.
    function forkCopyAddress() {
        var address = forkHostInfo.address || ""
        if (address === "") {
            return
        }
        forkClipboard.text = address
        forkClipboard.selectAll()
        forkClipboard.copy()
        window.forkToast(qsTr("Copied %1").arg(address))
    }

    TextEdit {
        id: forkClipboard
        visible: false
        textFormat: TextEdit.PlainText
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

    // The same name for a preset ("office", "gaming" or "custom"), for the screenshot harness's samples
    function forkPresetName(preset) {
        return preset === "office" ? qsTr("Office profile") : preset === "gaming" ? qsTr("Gaming profile") : qsTr("Custom profile")
    }

    // [fork] A chip's fill and text: a profile in its own color (Office blue, Gaming orange, Custom
    // purple), Direct launch in gold, the rest plain
    function forkChipColors(tone) {
        var dark = ForkTheme.dark
        return tone === "office" ? (dark ? [Qt.rgba(64 / 255, 156 / 255, 1, 0.15), "#7FB8FF"] : [Qt.rgba(0, 98 / 255, 204 / 255, 0.09), "#0058B8"])
             : tone === "gaming" ? (dark ? [Qt.rgba(1, 159 / 255, 10 / 255, 0.15), "#FFB547"] : [Qt.rgba(168 / 255, 90 / 255, 0, 0.09), "#8F4C00"])
             : tone === "custom" ? (dark ? [Qt.rgba(193 / 255, 125 / 255, 245 / 255, 0.16), "#D3A3FA"] : [Qt.rgba(142 / 255, 59 / 255, 184 / 255, 0.09), "#7A2FA0"])
             : tone === "gold" ? (dark ? [Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.15), "#F5C878"] : [Qt.rgba(138 / 255, 90 / 255, 0, 0.09), "#7A5000"])
             : [ForkTheme.raised, ForkTheme.text2]
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

    // The band's one line for the running app, like "3024×1890 · 120 fps · HEVC 10-bit · Office profile"
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
        pcName: appGrid.objectName
        apollo: appGrid.forkHostInfo.software === "Apollo"
        hostLine: appGrid.forkHostLine
        address: appGrid.forkHostInfo.address || ""
        hasRunning: !!appGrid.forkRunning.id
        runningName: appGrid.forkRunning.name || ""
        runningBoxart: appGrid.forkRunning.boxart || ""
        runningSummary: {
            appGrid.forkProfileRevision
            return appGrid.forkRunning.id ? appGrid.forkBannerSummary(appGrid.forkRunning.name) : ""
        }
        showingHidden: appGrid.forkShowHidden
        appCount: appGrid.forkAppTotal - appGrid.forkHiddenCount
        hiddenCount: appGrid.forkHiddenCount
        matchCount: appGrid.forkQuery.trim() !== "" ? appGrid.forkMatchCount : -1

        onResume: appGrid.forkResumeRunning()
        onQuit: appGrid.forkQuitRunning()
        onToggleHidden: appGrid.forkSetShowHidden(!appGrid.forkShowHidden)
        onCopyAddress: appGrid.forkCopyAddress()
        onSearchTextChanged: appGrid.forkSetQuery(searchText)
        // In the search no tile stays picked; Up goes on to the toolbar (where Up from the top
        // row used to go), and Down or Return to the first app
        onSearchFocused: appGrid.currentIndex = -1
        onSearchUp: {
            var previous = appGrid.nextItemInFocusChain(false)
            if (previous) {
                previous.forceActiveFocus(Qt.TabFocusReason)
            }
        }
        onSearchDown: {
            if (appGrid.count > 0) {
                appGrid.currentIndex = 0
                if (appGrid.currentItem) {
                    appGrid.currentItem.forceActiveFocus(Qt.TabFocusReason)
                }
            }
        }

        // Unless the user has scrolled, keep the top in view when the header changes height
        onHeightChanged: {
            if (!appGrid.forkUserScrolled) {
                Qt.callLater(appGrid.positionViewAtBeginning)
            }
        }
    }
    onMovementStarted: forkUserScrolled = true // [fork]

    // [fork] A search that matches nothing (the running app stays in the grid, so that can be
    // next to a tile), or no apps to show
    readonly property bool forkShowEmpty: count === 0 || (forkQuery.trim() !== "" && forkMatchCount === 0)

    // [fork] Under the tiles: what's missing when nothing matches or shows, then how to start an
    // app and, for Apollo, where its apps come from. In the footer, it always sits under the
    // header and any tiles.
    footer: Item {
        width: appGrid.forkContentWidth
        height: footerColumn.implicitHeight + 36

        Column {
            id: footerColumn
            y: 6
            width: parent.width
            spacing: 14

            Column {
                visible: appGrid.forkShowEmpty
                width: parent.width
                topPadding: appGrid.count === 0 ? 40 : 0
                bottomPadding: 16
                spacing: 14

                ForkText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    kind: "body"
                    font.pixelSize: 15
                    color: ForkTheme.text2
                    // [fork] Every app hidden, and a search that matches nothing, have their own words
                    text: appGrid.forkQuery.trim() !== ""
                          ? qsTr("No apps on %1 match “%2”").arg(appGrid.objectName).arg(appGrid.forkQuery.trim())
                          : appGrid.forkHiddenCount > 0 && !appGrid.forkShowHidden
                          ? qsTr("Every app on this PC is hidden. Show hidden apps to see them.")
                          : qsTr("This computer doesn't seem to have any applications or some applications are hidden")
                }

                ForkButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: appGrid.forkQuery.trim() !== ""
                    text: qsTr("Clear Search")
                    onClicked: {
                        if (appGrid.headerItem) {
                            appGrid.headerItem.searchText = ""
                        }
                    }
                }
            }

            ForkText {
                width: Math.min(parent.width, 760)
                kind: "help"
                color: ForkTheme.faint
                text: appGrid.forkHostInfo.software === "Apollo"
                      ? qsTr("Click an app to start it, or right-click it for its options. To add an app, open Apollo’s web page on %1 and go to Applications.").arg(appGrid.objectName)
                      : qsTr("Click an app to start it, or right-click it for its options.")
            }
        }
    }

    // [fork] The tiles come in one after another when the page opens (and when hidden apps are
    // shown or hidden), as in the design; search results fade in and the rest slide into place.
    // All at once with Reduce Motion.
    populate: Transition {
        id: forkPopulate
        enabled: !ForkTheme.reduceMotion

        SequentialAnimation {
            PropertyAction { property: "opacity"; value: 0 }
            PauseAnimation { duration: Math.min(forkPopulate.ViewTransition.index, 18) * 28 }
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { property: "y"; from: forkPopulate.ViewTransition.destination.y + 14; to: forkPopulate.ViewTransition.destination.y; duration: 460; easing.type: Easing.OutCubic }
            }
        }
    }
    add: Transition {
        enabled: !ForkTheme.reduceMotion
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
    }
    displaced: Transition {
        enabled: !ForkTheme.reduceMotion
        NumberAnimation { properties: "x,y"; duration: 220; easing.type: Easing.OutCubic }
        // A tile whose populate or add transition this cuts short still ends opaque, as Qt's
        // ViewTransition docs advise (else typing fast, or the host's list changing while the
        // tiles come in, leaves some invisible)
        NumberAnimation { property: "opacity"; to: 1; duration: 220 }
    }

    // [fork] ⌘F goes to the search, scrolling up to it
    Shortcut {
        // Every key the platform binds to Find (a single sequence takes only the first, and warns)
        sequences: [StandardKey.Find]
        enabled: appGrid.activated
        onActivated: {
            if (appGrid.headerItem) {
                appGrid.positionViewAtBeginning()
                appGrid.headerItem.focusSearch()
            }
        }
    }

    // [fork] Counts the apps and the hidden ones: one row per app of the counting model
    Instantiator {
        id: forkCounter
        model: appGrid.forkSample ? appGrid.forkSampleModel : appGrid.forkCountModel

        delegate: QtObject {
            required property bool hidden
            required property string name
            onHiddenChanged: appGrid.forkRecount()
        }

        onObjectAdded: appGrid.forkRecount()
        onObjectRemoved: appGrid.forkRecount()
    }

    // [fork] The band reads the running app again when the model changes. Later, since the model
    // signals a change of running app before it has noted the new one.
    Connections {
        target: appGrid.appModel
        function onDataChanged() {
            Qt.callLater(appGrid.forkReadRunning)
        }
        function onModelReset() {
            Qt.callLater(appGrid.forkReadRunning)
        }
        function onRowsInserted() {
            Qt.callLater(appGrid.forkReadRunning)
        }
        function onRowsRemoved() {
            Qt.callLater(appGrid.forkReadRunning)
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
        forkReadHost() // [fork]
        forkReadRunning() // [fork]
    }

    StackView.onActivated: {
        if (forkVisibleModel) {
            forkVisibleModel.computerLost.connect(computerLost) // [fork] was appModel, which can be swapped now
        }
        activated = true
        forkReadHost() // [fork]
        forkReadRunning() // [fork]
        forkCountHidden() // [fork]

        // Highlight the first item if a gamepad is connected
        if (currentIndex === -1 && SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            currentIndex = 0
        }

        if (!showGames && !showHiddenGames && !forkSample) { // [fork] samples don't start
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
        if (forkVisibleModel) {
            forkVisibleModel.computerLost.disconnect(computerLost) // [fork] was appModel
        }
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

    model: forkSample ? forkSampleModel : appModel // [fork] was appModel

    delegate: NavigableItemDelegate {
        id: tile
        width: appGrid.forkItemWidth; height: appGrid.forkTileHeight; // [fork] the design's tile: box art, name and chips fill the grid's column (was 220x287)
        grid: appGrid
        // [fork] No card behind the tile: the art's overlay shows hover and focus, as in the design
        background: Item {}

        // [fork] VoiceOver says what a click does
        Accessible.role: Accessible.Button
        Accessible.name: model.running ? qsTr("Resume %1").arg(model.name) : qsTr("Start %1").arg(model.name)
        Accessible.description: forkChips.map(function(chip) { return chip.text }).join(", ")

        // [fork] Pointed at with the mouse, or picked with the keyboard or a gamepad
        readonly property bool forkPointed: tile.hovered || tile.highlighted

        // [fork] This app's chips: its stream profile (Office, Gaming or Custom, in its own color,
        // with Stretch, Mac trackpad or Touchpad, and the aspect ratio when the profile sets them),
        // direct launch and hidden
        readonly property var forkChips: {
            appGrid.forkProfileRevision
            var chips = []
            if (appGrid.forkSample) {
                if (model.sampleProfile) {
                    chips.push({ "text": appGrid.forkPresetName(model.sampleProfile), "tone": model.sampleProfile })
                }
            }
            else {
                var profile = StreamProfiles.profile(appGrid.forkHostUuid, model.name)
                if (Object.keys(profile).length > 0) {
                    chips.push({ "text": appGrid.forkProfileName(profile), "tone": streamProfileDialog.presetOf(profile) })
                    if (profile.fullscreenStretch === true) {
                        chips.push({ "text": qsTr("Stretch"), "tone": "plain" })
                    }
                    if (profile.trackpadMode !== undefined && appGrid.forkTrackpadChip(profile.trackpadMode) !== "") {
                        chips.push({ "text": appGrid.forkTrackpadChip(profile.trackpadMode), "tone": "plain" })
                    }
                    if (profile.width !== undefined && profile.height !== undefined) {
                        chips.push({ "text": AspectRatios.ratioLabel(profile.width, profile.height), "tone": "plain" })
                    }
                }
            }
            if (model.directLaunch) {
                chips.push({ "text": qsTr("Direct launch"), "tone": "gold", "symbol": "bolt.fill" })
            }
            if (model.hidden) {
                chips.push({ "text": qsTr("Hidden"), "tone": "plain", "symbol": "eye.slash" })
            }
            return chips
        }

        property alias appContextMenu: appContextMenuLoader.item

        // [fork] Everything on the tile, lifted a little while it's pointed at, as in the design
        Item {
            id: lift
            width: parent.width
            height: parent.height
            y: tile.forkPointed && !ForkTheme.reduceMotion ? -4 : 0

            Behavior on y {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            // [fork] The box art and what's drawn on it. A hidden app dims only this (not its name
            // and chips, or the buttons on it).
            Item {
                id: art
                width: parent.width
                height: appGrid.forkArtHeight
                opacity: model.hidden ? 0.45 : 1.0

                // [fork] The running app's glow, breathing (still with Reduce Motion); none where
                // effects can't draw (the software renderer of offscreen screenshots)
                Rectangle {
                    id: runGlow
                    visible: model.running && GraphicsInfo.api !== GraphicsInfo.Software
                    anchors.fill: parent
                    anchors.margins: -3
                    radius: appIconMask.radius + 3
                    color: ForkTheme.running
                    opacity: 0.4
                    layer.enabled: visible
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 1.0
                        blurMax: 24
                    }

                    SequentialAnimation on opacity {
                        running: runGlow.visible && !ForkTheme.reduceMotion
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.6; duration: 1100; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.25; duration: 1100; easing.type: Easing.InOutSine }
                    }
                }

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

                    // [fork] The drawn cover below stands in for the host's grey placeholder art
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

                // [fork] A cover drawn from the app's name, in the style of Apollo's, for the host's
                // placeholder art (or while art loads); was a plain tile with the name
                ForkAppCover {
                    anchors.fill: parent
                    visible: appIcon.isPlaceholder || appIcon.status !== Image.Ready
                    name: model.name
                    radius: appIconMask.radius
                }

                // [fork] A thin edge around real art so dark art doesn't melt into the page
                Rectangle {
                    anchors.fill: parent
                    visible: !appIcon.isPlaceholder && appIcon.status === Image.Ready
                    radius: appIconMask.radius
                    color: "transparent"
                    border.color: Qt.rgba(1, 1, 1, 0.07)
                }

                // [fork] Pointed at: the art darkens under a play disc in the PC's color (on the
                // running app too: a click resumes it)
                Rectangle {
                    anchors.fill: parent
                    radius: appIconMask.radius
                    color: Qt.rgba(10 / 255, 14 / 255, 28 / 255, 0.4)
                    opacity: tile.forkPointed ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 56
                        height: 56
                        radius: 28
                        color: ForkTheme.pcFill
                        scale: tile.forkPointed || ForkTheme.reduceMotion ? 1 : 0.7

                        Behavior on scale {
                            NumberAnimation { duration: 220; easing.type: Easing.OutBack }
                        }

                        ForkSymbol {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: 2
                            symbol: "play.fill"
                            fallback: "qrc:/res/play_arrow_FILL1_wght700_GRAD200_opsz48.svg"
                            size: 22
                            color: "#FFFFFF"
                        }
                    }
                }

                // [fork] The edge: the running app's blue while it runs, else the PC's color while
                // pointed at
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -2
                    visible: model.running || tile.forkPointed
                    radius: appIconMask.radius + 2
                    color: "transparent"
                    border.width: 2
                    border.color: model.running ? ForkTheme.running : ForkTheme.pcFill
                }
            }

            // [fork] The running app's badge, its dot blinking (still with Reduce Motion)
            Rectangle {
                x: 10
                y: 10
                visible: model.running
                width: runningBadge.implicitWidth + 16
                height: 20
                radius: 10
                color: ForkTheme.runningBadge

                Row {
                    id: runningBadge
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        id: runDot
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: 3
                        color: "#FFFFFF"

                        SequentialAnimation on opacity {
                            running: runDot.visible && !ForkTheme.reduceMotion
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 1100; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 1100; easing.type: Easing.InOutSine }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Running")
                        font.family: ForkTheme.uiFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: "#FFFFFF"
                    }
                }
            }

            // [fork] The menu button, always there: a 44 point target with a 30 point disc on the art
            ForkButton {
                id: moreButton
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.top: parent.top
                anchors.topMargin: 2
                kind: "quiet"
                symbol: "ellipsis"
                symbolSize: 16
                focusPolicy: Qt.NoFocus
                Accessible.name: qsTr("More for %1").arg(model.name)
                background: Item {
                    Rectangle {
                        anchors.centerIn: parent
                        width: 30
                        height: 30
                        radius: 15
                        color: Qt.rgba(10 / 255, 14 / 255, 28 / 255, moreButton.hovered || tile.forkPointed ? 0.8 : 0.55)
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
                    font.weight: Font.DemiBold
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    color: model.hidden ? ForkTheme.muted : ForkTheme.text
                    text: model.name
                }

                // Room for two rows of chips (the gap to the next row of tiles holds the second)
                Flow {
                    width: parent.width
                    height: Math.min(childrenRect.height, 46)
                    spacing: 6
                    clip: true

                    Repeater {
                        model: tile.forkChips

                        delegate: Rectangle {
                            required property var modelData
                            readonly property var colors: appGrid.forkChipColors(modelData.tone)

                            width: chipRow.implicitWidth + 14
                            height: 20
                            radius: 6
                            color: colors[0]

                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 4

                                ForkSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !!modelData.symbol
                                    symbol: modelData.symbol || ""
                                    size: 10
                                    color: parent.parent.colors[1]
                                }

                                ForkText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    kind: "body"
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    color: parent.parent.colors[1]
                                    wrapMode: Text.NoWrap
                                    text: modelData.text
                                }
                            }
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
                    quitAppDialog.forkNextAppId = model.appid // [fork] rows can shift meanwhile
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
            // [fork] A click resumes the running app too (the band above the grid has Resume and
            // Quit); upstream ignored clicks on it. Samples don't start.
            if (!appGrid.forkSample) {
                launchOrResumeSelectedApp(true)
            }
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
            // [fork] The design's order and wording: start or resume, the app's stream settings,
            // then Direct Launch and Hide App, and Quit for the running app
            sourceComponent: NavigableMenu {
                id: appContextMenu
                initiator: appContextMenuLoader.parent
                NavigableMenuItem {
                    symbol: "play.fill" // [fork]
                    text: model.running ? qsTr("Resume %1").arg(model.name) : qsTr("Start %1").arg(model.name) // [fork] was "Resume Game" or "Launch Game"
                    onTriggered: {
                        if (!appGrid.forkSample) {
                            launchOrResumeSelectedApp(true)
                        }
                    }
                }
                // [fork] per-app stream settings
                NavigableMenuItem {
                    symbol: "slider.horizontal.3" // [fork]
                    text: qsTr("Stream Settings…")
                    onTriggered: streamProfileDialog.openFor(computerIndex, model.name)
                    enabled: !appGrid.forkSample
                }
                ForkMenuSeparator {} // [fork]
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
                    enabled: !model.hidden && !appGrid.forkSample

                    ToolTip.text: qsTr("Starts this app as soon as you click the PC, without showing its apps.") // [fork]
                    ToolTip.delay: 1000
                    ToolTip.timeout: 3000
                    ToolTip.visible: hovered
                }
                NavigableMenuItem {
                    symbol: "eye.slash" // [fork]
                    checkable: true
                    checked: model.hidden
                    text: qsTr("Hide App") // [fork] was "Hide Game"
                    onTriggered: {
                        // [fork] The design confirms where the app went
                        var wasHidden = model.hidden
                        var appName = model.name
                        appModel.setAppHidden(model.index, !wasHidden)
                        window.forkToast(wasHidden ? qsTr("%1 is back in the grid").arg(appName)
                                                   : appGrid.forkShowHidden ? qsTr("%1 is hidden").arg(appName)
                                                                            : qsTr("%1 is hidden. Turn on Show hidden apps to find it.").arg(appName))
                    }
                    enabled: (model.hidden || (!model.running && !model.directLaunch)) && !appGrid.forkSample

                    ToolTip.text: qsTr("Hides this app from the grid. Show hidden apps, at the top of this page, brings it back.") // [fork]
                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                }
                ForkMenuSeparator { // [fork]
                    visible: model.running
                }
                NavigableMenuItem {
                    symbol: "stop.fill" // [fork]
                    destructive: true // [fork]
                    text: qsTr("Quit %1").arg(model.name) // [fork] was "Quit Game"
                    onTriggered: doQuitGame()
                    visible: model.running
                    enabled: !appGrid.forkSample
                }
            }
        }
    }

    // [fork] The words for an empty page (no apps, every app hidden, or no match for the search)
    // are in the footer, under the header (was a Label centered in the view)

    NavigableMessageDialog {
        id: quitAppDialog
        property string appName : ""
        property bool segueToStream : false
        property string nextAppName: ""
        property int nextAppIndex: 0
        property int forkNextAppId: 0 // [fork]
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
            // [fork] The chosen app's row now: the multi-display app can come or go with the displays
            var forkNextIndex = segueToStream ? appModel.forkIndexOfApp(forkNextAppId) : -1
            if (segueToStream && forkNextIndex >= 0) {
                // Store the session and app name if we're going to stream after
                // successfully quitting the old app.
                params.nextAppName = nextAppName
                params.nextSession = appModel.createSessionForApp(forkNextIndex)
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
