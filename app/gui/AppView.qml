import QtQuick
import QtQuick.Controls
import QtQuick.Effects // [fork] MultiEffect and RectangularShadow, for the panel's corners and shadows
import QtQml // [fork] Instantiator, to count the hidden apps
// [fork] No explicit Material import: it would override the native macOS style set in main.cpp

import AppModel
import ComputerManager
import SdlGamepadKeyNavigation
import AspectRatios // [fork]
import ForkHostUpdates // [fork] Apollo's version, for the header
import ForkHostPower // [fork] Wake PC, for the apps of a sleeping PC
import ForkTheme // [fork]
import StreamProfiles // [fork]
import StreamingPreferences // [fork]
import SystemProperties // [fork]
import "ForkLibraryLaunch.js" as Launch // [fork] the launch summaries

// [fork] A PC's All apps page, as in the design's Library and LibraryAsleep boards: a big rounded
// panel inset in the window (the window's sky shows around it, so the page is transparent there),
// the PC's band fixed at its top, and under it the scrolling "All apps" title row, the grid of
// covers and a footnote. The search field lives in the window's header (see forkSearchPlaceholder
// and forkSetQuery). Was a GridView with the band as its header.
FocusScope {
    id: appGrid

    property int computerIndex
    // [fork] What the window's header asks of the page that's showing (see contract-library.md)
    readonly property string forkHeaderVariant: "apps"
    property string forkSkyVariant: "main"
    property string forkBackTitle: qsTr("Your PCs")
    readonly property string forkSearchPlaceholder: qsTr("Search %1’s apps").arg(objectName)

    // [fork] Two models of the PC's apps for the grid: one without the hidden apps, one with every
    // app. The grid shows one of them (forkShowHidden), so hidden apps can be shown and hidden
    // again in place; both follow the search (forkQuery). A third, with every app and no search,
    // counts the apps and the hidden ones. Was one model made by createModel().
    property bool forkShowHidden: true // the design's switch starts on
    // [fork] Sample apps for the screenshot harness: a ListModel with AppModel's roles (and
    // sampleProfile, "office", "gaming" or "custom"; sampleColor, a cover color; sampleExtras, chips
    // like "Mac trackpad, 16:10") shown instead of a PC's, which asks nothing of a host;
    // forkSampleHost stands in for forkHostInfo (software, version, address, local, remote, asleep,
    // latencyMs, ipNote, colorKey, wakeReady)
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

    // [fork] The PC, from PcView (ForkPcPrefs and the PC model have these; see contract-library.md)
    property string forkColorKey: forkSample && forkSampleHost.colorKey ? forkSampleHost.colorKey : "indigo"
    property bool forkAsleep: false // the PC is off or asleep: the apps are the last visit's, and picking one wakes it
    property bool forkWakeReady: true // wake from off works for this PC
    property int forkLatencyMs: -1 // the last network round trip, -1 when unknown
    property var forkComputerModel: null // PcView's ComputerModel, which wakes the PC (wakeComputer(index))
    // Where the panel grows from, in this page's coordinates (-1: its middle)
    property real forkOriginX: -1
    property real forkOriginY: -1
    property bool forkAnimateOpen: true

    readonly property bool forkIsAsleep: forkSample ? !!forkSampleHost.asleep : forkAsleep
    readonly property var forkHue: ForkTheme.hue(forkColorKey)
    readonly property color forkFill: forkHue.fill
    readonly property color forkOnFill: forkHue.onFill
    readonly property color forkSky: forkHue.sky

    activeFocusOnTab: true

    // [fork] The grid's columns: 6 at the design's width; the panel's content width is the page's
    // less 78 (margins) and 62 (padding and border)
    readonly property real forkSheetWidth: width - 78
    readonly property real forkContentWidth: forkSheetWidth - 62
    readonly property int forkColumns: Math.max(2, Math.floor((forkContentWidth + 20) / 170))
    readonly property real forkTileWidth: (forkContentWidth - 20 * (forkColumns - 1)) / forkColumns

    // [fork] The running app, for the header's band, read from the model by its ID
    // (AppModel.forkRunningApp()), since the search and hidden apps move rows: {id, name, boxart},
    // or empty with nothing running
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
    readonly property int forkLatency: forkSample && forkSampleHost.latencyMs !== undefined ? forkSampleHost.latencyMs : forkLatencyMs
    // Like "Apollo 0.4.8 · Home network · 2 ms": which of the PC's addresses LuzLunar uses, the one
    // on its own network (from home, or over a VPN into it) or the one from outside, and how fast
    // it answers; for a sleeping PC "Apollo 0.4.8 · last seen at home"
    readonly property string forkHostLine: {
        var parts = []
        var software = forkHostInfo.software || ""
        if (software !== "") {
            parts.push(software === "Apollo" && forkApolloVersion !== "" ? "Apollo " + forkApolloVersion : software)
        }
        if (forkIsAsleep) {
            parts.push(forkHostInfo.remote ? qsTr("last seen away") : qsTr("last seen at home"))
        }
        else {
            if (forkHostInfo.local) {
                parts.push(qsTr("Home network"))
            }
            else if (forkHostInfo.remote) {
                parts.push(qsTr("Over the internet"))
            }
            if (forkLatency >= 0) {
                parts.push(qsTr("%1 ms").arg(forkLatency))
            }
        }
        return parts.join(" · ")
    }
    // The line beside the address
    readonly property string forkIpNote: forkHostInfo.ipNote !== undefined ? forkHostInfo.ipNote
                                       : forkIsAsleep ? qsTr("Its last address")
                                       : forkHostInfo.reachableRemote ? qsTr("Reachable from outside too") : ""

    // [fork] The search's text, and how many apps match it (counted like the header's numbers)
    property string forkQuery: ""
    property int forkMatchCount: 0

    // [fork] How many apps there are and how many of them are hidden, read off the counting model's
    // rows; and, for samples, how many of them the grid shows
    readonly property int forkAppTotal: forkCounter.count
    property int forkHiddenCount: 0
    property int forkSampleListCount: 0
    readonly property int forkListCount: forkSample ? forkSampleListCount : tiles.count

    // [fork] The page's beat (1100 ms) and entrance
    property int forkTick: 0
    property bool forkOpen: false
    property bool forkSettled: false

    // [fork] The picked tile (keyboard and gamepad) and the app whose menu is open
    property int currentIndex: -1
    property int forkMenuId: -1
    property int forkMenuCurrent: 0

    function forkSay(text) {
        if (typeof window !== "undefined" && window && window.forkToast) {
            window.forkToast(text)
        }
    }

    function forkReadRunning() {
        if (forkSample) {
            var found = {}
            for (var i = 0; i < forkSampleModel.count; i++) {
                var row = forkSampleModel.get(i)
                if (row.running) {
                    found = { "id": row.appid, "name": row.name, "boxart": row.boxart, "colorKey": row.sampleColor || "" }
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

    // Whether a sample app shows: hidden ones only with the switch on, and the ones the search matches
    function forkSampleMatches(name, hidden) {
        var query = forkQuery.trim().toLowerCase()
        return (forkShowHidden || !hidden) && (query === "" || name.toLowerCase().indexOf(query) >= 0)
    }

    function forkCountHidden() {
        var hidden = 0
        var matches = 0
        var listed = 0
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
            if ((forkShowHidden || !row.hidden) && (query === "" || row.name.toLowerCase().indexOf(query) >= 0)) {
                listed++
            }
        }
        forkHiddenCount = hidden
        forkMatchCount = matches
        forkSampleListCount = listed
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
        forkMenuId = -1
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

    // [fork] The search (the window header's field calls this): both models keep only the apps whose
    // names contain the text. No tile is picked meanwhile, and no menu stays open.
    function forkSetQuery(text) {
        if (text === forkQuery) {
            return
        }
        currentIndex = -1
        forkMenuId = -1
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
        if (forkSample) {
            if (id !== 0) {
                forkSay(qsTr("Resuming %1…").arg(forkRunning.name))
            }
            return
        }
        if (!appModel || id === 0) {
            return
        }
        forkLaunchById(id, forkRunning.name, true)
    }

    // Starts or resumes the app with this ID, from the model that has it
    function forkLaunchById(id, name, resume) {
        var model = appModel
        var row = model ? model.forkIndexOfApp(id) : -1
        if (row < 0 && forkFullModel) {
            model = forkFullModel
            row = model.forkIndexOfApp(id)
        }
        if (row < 0) {
            return
        }
        var component = Qt.createComponent("StreamSegue.qml")
        var segue = component.createObject(stackView, {
                                               "appName": name,
                                               "session": model.createSessionForApp(row),
                                               "isResume": resume,
                                               "hostName": appGrid.objectName,
                                               "summary": appGrid.forkStreamSummary(name)
                                           })
        stackView.push(segue)
    }

    function forkQuitRunning() {
        if (!forkRunning.id) {
            return
        }
        forkAskQuit(forkRunning.name, forkRunning.id, forkRunning.boxart || "", forkRunning.colorKey || "")
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
        forkSay(qsTr("Copied %1").arg(address))
    }

    TextEdit {
        id: forkClipboard
        visible: false
        textFormat: TextEdit.PlainText
    }

    // What a stream of this app would use, and the lines that say so: ForkLibraryLaunch.js (PcView
    // uses it too); the profile's name comes from the stream settings dialog
    function forkProfileName(profile) {
        return Object.keys(profile).length > 0 ? streamProfileDialog.profileName(profile) : ""
    }
    function forkTrackpadChip(mode) { return Launch.trackpadChip(mode) }
    function forkPresetName(preset) { return Launch.presetName(preset) }
    function forkStreamSummary(appName) {
        return Launch.streamSummary(forkHostUuid, appName, streamProfileDialog.profileName)
    }
    // The band's one line for the running app
    function forkBannerSummary(appName) {
        return Launch.bannerSummary(forkHostUuid, appName, streamProfileDialog.profileName)
    }

    // [fork] A chip's fill and text: a profile in its own color (Office blue, Gaming orange, Custom
    // purple), Direct launch in gold, the rest plain (the page's own plain tones)
    function forkChipColors(tone) {
        var dark = ForkTheme.dark
        return tone === "office" ? (dark ? [Qt.rgba(64 / 255, 156 / 255, 1, 0.15), "#7FB8FF"] : [Qt.rgba(0, 98 / 255, 204 / 255, 0.09), "#0058B8"])
             : tone === "gaming" ? (dark ? [Qt.rgba(1, 159 / 255, 10 / 255, 0.15), "#FFB547"] : [Qt.rgba(168 / 255, 90 / 255, 0, 0.09), "#8F4C00"])
             : tone === "custom" ? (dark ? [Qt.rgba(193 / 255, 125 / 255, 245 / 255, 0.16), "#D3A3FA"] : [Qt.rgba(142 / 255, 59 / 255, 184 / 255, 0.09), "#7A2FA0"])
             : tone === "gold" ? (dark ? [Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.15), "#F5C878"] : [Qt.rgba(138 / 255, 90 / 255, 0, 0.09), "#7A5000"])
             : [dark ? "#262A3A" : "#EEEEF3", ForkTheme.cv.text2]
    }

    // [fork] An app's chips: its stream profile (Office, Gaming or Custom, in its own color, with
    // Stretch, Mac trackpad or Touchpad, and the aspect ratio when the profile sets them), direct
    // launch and hidden. For samples: sampleProfile and sampleExtras.
    function forkChipsFor(name, direct, hidden, sampleProfile, sampleExtras) {
        forkProfileRevision
        var chips = []
        if (forkSample) {
            if (sampleProfile) {
                chips.push({ "text": forkPresetName(sampleProfile), "tone": sampleProfile })
            }
            var extras = sampleExtras ? String(sampleExtras).split(",") : []
            for (var e = 0; e < extras.length; e++) {
                chips.push({ "text": extras[e].trim(), "tone": "plain" })
            }
        }
        else {
            var profile = StreamProfiles.profile(forkHostUuid, name)
            if (Object.keys(profile).length > 0) {
                chips.push({ "text": forkProfileName(profile), "tone": streamProfileDialog.presetOf(profile) })
                if (profile.fullscreenStretch === true) {
                    chips.push({ "text": qsTr("Stretch"), "tone": "plain" })
                }
                if (profile.trackpadMode !== undefined && forkTrackpadChip(profile.trackpadMode) !== "") {
                    chips.push({ "text": forkTrackpadChip(profile.trackpadMode), "tone": "plain" })
                }
                if (profile.width !== undefined && profile.height !== undefined) {
                    chips.push({ "text": AspectRatios.ratioLabel(profile.width, profile.height), "tone": "plain" })
                }
            }
        }
        if (direct) {
            chips.push({ "text": qsTr("Direct launch"), "tone": "gold", "icon": "bolt" })
        }
        if (hidden) {
            chips.push({ "text": qsTr("Hidden"), "tone": "plain", "icon": "eyeSlash" })
        }
        return chips
    }

    // The words under the title: "10 apps · 2 hidden", or what the search matched
    readonly property string forkCountText: {
        var q = forkQuery.trim()
        if (q !== "") {
            return qsTr("%1 of %2 apps match").arg(forkListCount).arg(forkAppTotal)
        }
        var shown = forkAppTotal - forkHiddenCount
        var text = shown === 1 ? qsTr("1 app") : qsTr("%1 apps").arg(shown)
        return forkHiddenCount > 0 ? text + " · " + qsTr("%1 hidden").arg(forkHiddenCount) : text
    }

    // ---- What a pick does ------------------------------------------------------------------

    // Wake PC: sends the wake-up (the card shows it waking, and ForkHostPower toasts once it's up)
    function forkWakeButton() {
        forkSay(qsTr("Waking %1…").arg(objectName))
        if (forkSample) {
            return
        }
        ForkHostPower.noteWakeSent(forkHostUuid)
        if (forkComputerModel) {
            forkComputerModel.wakeComputer(forkComputerModel.forkIndexOf(forkHostUuid))
        }
    }

    // Picking an app on a sleeping PC wakes it first, then starts the app (ForkWakeLaunch)
    function forkPickAsleep(id, name) {
        if (forkSample) {
            forkSay(qsTr("Waking %1, then starting %2…").arg(objectName).arg(name))
        }
        else if (forkComputerModel) {
            wakeLaunch.start(forkComputerModel, forkComputerModel.forkIndexOf(forkHostUuid), id, name)
        }
    }

    ForkWakeLaunch {
        id: wakeLaunch
        summaryFor: function(appName) { return appGrid.forkStreamSummary(appName) }
    }

    // Click, Return or the menu's first row
    function forkPick(index, name, appid, running, boxart, colorKey) {
        if (forkIsAsleep) {
            forkPickAsleep(appid, name)
            return
        }
        var runningId = forkRunning.id || 0
        if (forkSample) {
            if (running) {
                forkSay(qsTr("Resuming %1…").arg(name))
            }
            else if (runningId !== 0) {
                forkAskSwitch(name, appid, index, boxart, colorKey)
            }
            else {
                forkSampleModel.setProperty(index, "running", true)
                forkSay(qsTr("Starting %1 on %2…").arg(name).arg(objectName))
            }
            return
        }
        forkLaunchOrResume(index, name, appid, true, boxart, colorKey)
    }

    function forkLaunchOrResume(index, name, appid, quitExistingApp, boxart, colorKey) {
        var runningId = appModel.getRunningAppId()
        if (runningId !== 0 && runningId !== appid) {
            if (quitExistingApp) {
                forkAskSwitch(name, appid, index, boxart, colorKey)
            }
            return
        }

        var component = Qt.createComponent("StreamSegue.qml")
        var segue = component.createObject(stackView, {
                                               "appName": name,
                                               "session": appModel.createSessionForApp(index),
                                               "isResume": runningId === appid,
                                               "hostName": appGrid.objectName, // [fork] for the launch screen
                                               "summary": appGrid.forkStreamSummary(name) // [fork]
                                           })
        stackView.push(segue)
    }

    // ---- The alert (quit the running app, or quit it to start another) -----------------------

    property string dlgKind: "quit" // "quit" or "switch"
    property string dlgApp: "" // the app the alert is about
    property int dlgAppId: 0
    property string dlgArt: ""
    property string dlgColor: ""
    property string dlgNextName: ""
    property int dlgNextId: 0
    property int dlgNextIndex: 0

    function forkAskQuit(name, id, boxart, colorKey) {
        dlgKind = "quit"
        dlgApp = name
        dlgAppId = id
        dlgArt = boxart
        dlgColor = colorKey
        forkMenuId = -1
        quitAppDialog.open()
    }

    function forkAskSwitch(nextName, nextId, nextIndex, boxart, colorKey) {
        dlgKind = "switch"
        dlgApp = forkRunning.name || ""
        dlgAppId = forkRunning.id || 0
        dlgNextName = nextName
        dlgNextId = nextId
        dlgNextIndex = nextIndex
        dlgArt = boxart
        dlgColor = colorKey
        forkMenuId = -1
        quitAppDialog.open()
    }

    function forkDialogConfirmed() {
        var segueToStream = dlgKind === "switch"
        if (forkSample) {
            var was = dlgApp
            for (var i = 0; i < forkSampleModel.count; i++) {
                var row = forkSampleModel.get(i)
                if (row.running) {
                    forkSampleModel.setProperty(i, "running", false)
                }
                if (segueToStream && row.appid === dlgNextId) {
                    forkSampleModel.setProperty(i, "running", true)
                }
            }
            forkSay(segueToStream ? qsTr("Quitting %1, then starting %2…").arg(was).arg(dlgNextName)
                                  : qsTr("Quit %1 on %2").arg(was).arg(objectName))
            return
        }
        var appName = dlgApp
        var component = Qt.createComponent("QuitSegue.qml")
        var params = {"appName": appName, "quitRunningAppFn": function() { appModel.quitRunningApp() }}
        // [fork] The chosen app's row now: the multi-display app can come or go with the displays
        var forkNextIndex = segueToStream ? appModel.forkIndexOfApp(dlgNextId) : -1
        if (segueToStream && forkNextIndex >= 0) {
            // Store the session and app name if we're going to stream after
            // successfully quitting the old app.
            params.nextAppName = dlgNextName
            params.nextSession = appModel.createSessionForApp(forkNextIndex)
            params.nextHostName = appGrid.objectName // [fork] for the next app's launch screen
            params.nextSummary = appGrid.forkStreamSummary(dlgNextName) // [fork]
        }
        else {
            params.nextAppName = null
            params.nextSession = null

            // [fork] The design confirms the quit, once the host has done it
            var quitName = appName
            var quitDone = function(error) {
                ComputerManager.quitAppCompleted.disconnect(quitDone)
                if (error === undefined) {
                    appGrid.forkSay(qsTr("Quit %1 on %2").arg(quitName).arg(appGrid.objectName))
                }
            }
            ComputerManager.quitAppCompleted.connect(quitDone)
        }

        stackView.push(component.createObject(stackView, params))
    }

    // ---- An app's menu ----------------------------------------------------------------------

    // The design's rows: start or resume (or wake first), the app's stream settings, Direct Launch,
    // Hide App, and Quit for the running app
    function forkMenuItemsFor(name, running, hidden, direct) {
        var asleep = forkIsAsleep
        var runs = running && !asleep
        var items = [
            { "id": "start", "label": runs ? qsTr("Resume %1").arg(name) : asleep ? qsTr("Wake PC and Start %1").arg(name) : qsTr("Start %1").arg(name),
              "icon": asleep ? "power" : "play", "filled": !asleep, "key": "↩" },
            { "id": "settings", "label": qsTr("Stream Settings…"), "icon": "sliders" },
            { "sep": true },
            { "id": "direct", "label": qsTr("Direct Launch"), "icon": "bolt", "check": true, "checked": direct, "disabled": hidden },
            { "id": "hide", "label": qsTr("Hide App"), "icon": "eyeSlash", "check": true, "checked": hidden, "disabled": !hidden && (runs || direct) }
        ]
        if (runs) {
            items.push({ "sep": true })
            items.push({ "id": "quit", "label": qsTr("Quit %1").arg(name), "icon": "stop", "danger": true })
        }
        return items
    }

    function forkMenuAction(actionId, index, name, appid, running, hidden, direct, boxart, colorKey) {
        forkMenuId = -1
        appGrid.forceActiveFocus()
        if (actionId === "start") {
            forkPick(index, name, appid, running, boxart, colorKey)
        }
        else if (actionId === "settings") {
            if (forkSample) {
                forkSay(qsTr("Opens “Stream settings for %1”: Office, Gaming or Custom").arg(name))
            }
            else {
                streamProfileDialog.openFor(computerIndex, name)
            }
        }
        else if (actionId === "direct") {
            // [fork] The design confirms what a click on the PC does now
            if (forkSample) {
                for (var i = 0; i < forkSampleModel.count; i++) {
                    forkSampleModel.setProperty(i, "directLaunch", !direct && i === index)
                }
            }
            else {
                appModel.setAppDirectLaunch(index, !direct)
            }
            forkSay(direct ? qsTr("Direct launch is off") : qsTr("Clicking %1 now starts %2").arg(objectName).arg(name))
        }
        else if (actionId === "hide") {
            if (forkSample) {
                forkSampleModel.setProperty(index, "hidden", !hidden)
            }
            else {
                appModel.setAppHidden(index, !hidden)
            }
            forkSay(hidden ? qsTr("%1 is back in the grid").arg(name)
                           : forkShowHidden ? qsTr("%1 is hidden").arg(name)
                                            : qsTr("%1 is hidden. Turn on Show hidden apps to find it.").arg(name))
        }
        else if (actionId === "quit") {
            forkAskQuit(name, appid, boxart, colorKey)
        }
    }

    // ---- Keyboard and gamepad ---------------------------------------------------------------

    // The grid: tiles in rows of forkColumns, 20 apart across and 26 down; a row is as tall as its
    // tallest tile (a manual layout, since Layouts round to whole points)
    function forkQueueLayout() {
        Qt.callLater(forkRelayout)
    }

    function forkRelayout() {
        var list = forkTileItems()
        var cols = forkColumns
        var y = 0
        for (var r = 0; r * cols < list.length; r++) {
            var h = 0
            for (var c = 0; c < cols && r * cols + c < list.length; c++) {
                var item = list[r * cols + c]
                item.gx = c * (forkTileWidth + 20)
                item.gy = y
                item.column = c
                h = Math.max(h, item.implicitHeight)
            }
            y += h + 26
        }
        grid.height = Math.max(0, y - 26)
    }

    onForkColumnsChanged: forkQueueLayout()
    onForkTileWidthChanged: forkQueueLayout()

    function forkTileItems() {
        var list = []
        for (var i = 0; i < tiles.count; i++) {
            var item = tiles.itemAt(i)
            if (item && item.visible) {
                list.push(item)
            }
        }
        return list
    }

    function forkSelect(item) {
        currentIndex = item.tileIndex
        var y = item.mapToItem(scroller.contentItem, 0, 0).y
        if (y < scroller.contentY + 8) {
            scroller.contentY = Math.max(0, y - 22)
        }
        else if (y + item.height > scroller.contentY + scroller.height - 8) {
            scroller.contentY = Math.min(scroller.contentHeight - scroller.height, y + item.height - scroller.height + 26)
        }
    }

    function forkMove(dx, dy) {
        var list = forkTileItems()
        if (list.length === 0) {
            return false
        }
        var pos = -1
        for (var i = 0; i < list.length; i++) {
            if (list[i].tileIndex === currentIndex) {
                pos = i
            }
        }
        if (pos < 0) {
            forkSelect(list[0])
            return true
        }
        var here = list[pos]
        var target = null
        if (dx !== 0) {
            target = list[pos + dx] || null
        }
        else {
            var cx = here.x
            var best = 1e9
            for (var j = 0; j < list.length; j++) {
                var other = list[j]
                var dist = (other.y - here.y) * dy
                if (dist > 1 && (dist < best - 1 || (Math.abs(dist - best) <= 1 && target && Math.abs(other.x - cx) < Math.abs(target.x - cx)))) {
                    best = dist
                    target = other
                }
            }
        }
        if (target) {
            forkSelect(target)
            return true
        }
        return false
    }

    Keys.onLeftPressed: forkMove(-1, 0)
    Keys.onRightPressed: forkMove(1, 0)
    Keys.onDownPressed: forkMove(0, 1)
    Keys.onUpPressed: {
        if (!forkMove(0, -1)) {
            // At the top of the grid: on to the window's header, where Up used to go
            currentIndex = -1
            var previous = appGrid.nextItemInFocusChain(false)
            if (previous) {
                previous.forceActiveFocus(Qt.TabFocusReason)
            }
        }
    }
    Keys.onReturnPressed: forkActivateCurrent()
    Keys.onEnterPressed: forkActivateCurrent()
    Keys.onMenuPressed: {
        var item = forkCurrentTile()
        if (item) {
            forkMenuId = item.appId
            forkMenuCurrent = 0
        }
    }
    Keys.onEscapePressed: {
        if (forkMenuId >= 0) {
            forkMenuId = -1
        }
    }

    function forkCurrentTile() {
        return currentIndex >= 0 ? tiles.itemAt(currentIndex) : null
    }

    function forkActivateCurrent() {
        var item = forkCurrentTile()
        if (!item) {
            return
        }
        // Return opens the menu of the running app (as before); any other app starts
        if (item.isRunning && !forkIsAsleep) {
            forkMenuId = item.appId
            forkMenuCurrent = 0
        }
        else {
            item.activated()
        }
    }

    onActiveFocusChanged: {
        if (!activeFocus && forkMenuId < 0) {
            // keeps the pick for when the focus comes back
        }
    }

    // ---- The page ----------------------------------------------------------------------------

    Timer {
        interval: 40
        running: true
        onTriggered: appGrid.forkOpen = true
    }

    Timer {
        interval: 1500
        running: appGrid.forkOpen
        onTriggered: appGrid.forkSettled = true
    }

    // The beat: only while the page is up, and still with Reduce Motion
    Timer {
        interval: 1100
        repeat: true
        running: appGrid.forkOpen && appGrid.visible && !ForkTheme.reduceMotion
        onTriggered: appGrid.forkTick++
    }

    // The panel, inset in the window: the window's sky shows around it (and, faintly, through it)
    Item {
        id: sheet
        x: 40
        y: 12
        width: appGrid.forkSheetWidth
        height: appGrid.height - 22
        opacity: appGrid.forkOpen || !appGrid.forkAnimateOpen ? 1 : 0
        scale: 1
        transform: Scale {
            id: sheetScale
            origin.x: (appGrid.forkOriginX >= 0 ? appGrid.forkOriginX : appGrid.width / 2) - sheet.x
            origin.y: (appGrid.forkOriginY >= 0 ? appGrid.forkOriginY : appGrid.height / 2) - sheet.y
            xScale: appGrid.forkOpen || !appGrid.forkAnimateOpen || ForkTheme.reduceMotion ? 1 : 0.58
            yScale: xScale

            Behavior on xScale {
                enabled: appGrid.forkAnimateOpen && !ForkTheme.reduceMotion
                NumberAnimation { duration: 580; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.22, 1.12, 0.36, 1, 1, 1] }
            }
        }

        Behavior on opacity {
            enabled: appGrid.forkAnimateOpen
            NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] }
        }

        RectangularShadow {
            anchors.fill: parent
            radius: 24
            offset: Qt.vector2d(0, ForkTheme.dark ? 40 : 30)
            blur: ForkTheme.dark ? 100 : 80
            color: ForkTheme.dark ? Qt.rgba(0, 0, 0, 0.6) : Qt.rgba(24 / 255, 26 / 255, 46 / 255, 0.22)
        }

        Rectangle {
            anchors.fill: parent
            radius: 24
            color: ForkTheme.dark ? Qt.rgba(19 / 255, 22 / 255, 34 / 255, 0.86) : Qt.rgba(1, 1, 1, 0.88)
            border.width: 1
            border.color: ForkTheme.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.16)
        }

        Accessible.role: Accessible.Grouping
        Accessible.name: qsTr("All apps on %1").arg(appGrid.objectName)

        // Band and scroll area, cut to the panel's inner corners
        Item {
            id: inner
            anchors.fill: parent
            anchors.margins: 1
            layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: innerMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            ForkAppsHeader {
                id: band
                width: parent.width
                pcName: appGrid.objectName
                apollo: appGrid.forkHostInfo.software === "Apollo"
                hostLine: appGrid.forkHostLine
                address: appGrid.forkHostInfo.address || ""
                ipNote: appGrid.forkIpNote
                asleep: appGrid.forkIsAsleep
                wakeReady: forkSample && appGrid.forkSampleHost.wakeReady !== undefined ? appGrid.forkSampleHost.wakeReady : appGrid.forkWakeReady
                hasRunning: !!appGrid.forkRunning.id
                runningName: appGrid.forkRunning.name || ""
                runningBoxart: appGrid.forkRunning.boxart || ""
                runningColorKey: appGrid.forkRunning.colorKey || ""
                runningSummary: {
                    appGrid.forkProfileRevision
                    return appGrid.forkRunning.id ? appGrid.forkBannerSummary(appGrid.forkRunning.name) : ""
                }
                pcSky: appGrid.forkSky
                pcFill: appGrid.forkFill
                pcOnFill: appGrid.forkOnFill
                tick: appGrid.forkTick
                entered: appGrid.forkOpen
                settled: appGrid.forkSettled || ForkTheme.reduceMotion

                onResume: appGrid.forkResumeRunning()
                onQuit: appGrid.forkQuitRunning()
                onWake: appGrid.forkWakeButton()
                onCopyAddress: appGrid.forkCopyAddress()
            }

            // With a menu open, a click anywhere on the band only closes the menu
            MouseArea {
                anchors.fill: band
                z: 5
                enabled: appGrid.forkMenuId >= 0
                onClicked: appGrid.forkMenuId = -1
            }

            // The title row, the grid and the footnote scroll; the band stays
            Flickable {
                id: scroller
                y: band.height
                width: parent.width
                height: parent.height - band.height
                contentWidth: width
                contentHeight: column.y + column.height + 26
                clip: true
                boundsBehavior: Flickable.OvershootBounds
                ScrollBar.vertical: ScrollBar {}

                // With a menu open, a click away from its tile closes it (the other tiles are off meanwhile)
                MouseArea {
                    width: scroller.contentWidth
                    height: scroller.contentHeight
                    enabled: appGrid.forkMenuId >= 0
                    onClicked: appGrid.forkMenuId = -1
                }

                Column {
                    id: column
                    x: 30
                    y: 22
                    width: scroller.width - 60

                    // "All apps", how many, and the switch for the hidden ones
                    ForkLibraryEnter {
                        width: parent.width
                        height: 32
                        entered: appGrid.forkOpen
                        settled: appGrid.forkSettled || ForkTheme.reduceMotion
                        delay: 240

                        ForkCanvasText {
                            id: pageTitle
                            height: 32
                            verticalAlignment: Text.AlignVCenter
                            text: qsTr("All apps")
                            color: ForkTheme.cv.text
                            px: 26
                            weight: 750
                            tracking: -0.52
                        }

                        ForkCanvasText {
                            x: pageTitle.implicitWidth + 14
                            y: 8
                            height: 20
                            verticalAlignment: Text.AlignVCenter
                            text: appGrid.forkCountText
                            color: ForkTheme.cv.muted
                            px: 14
                        }

                        Item {
                            id: hiddenSwitch
                            visible: appGrid.forkHiddenCount > 0
                            x: parent.width - width
                            y: 5
                            width: 38 + 14 + switchLabel.implicitWidth
                            height: 22

                            ForkCanvasText {
                                id: switchLabel
                                height: 22
                                verticalAlignment: Text.AlignVCenter
                                text: qsTr("Show hidden apps")
                                color: ForkTheme.cv.text2
                                px: 13
                            }

                            Rectangle {
                                id: track
                                x: parent.width - 38
                                width: 38
                                height: 22
                                radius: 11
                                color: appGrid.forkShowHidden ? appGrid.forkFill : (ForkTheme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.16))
                                Behavior on color { ColorAnimation { duration: 200 } }

                                Accessible.role: Accessible.CheckBox
                                Accessible.name: qsTr("Show hidden apps")
                                Accessible.checked: appGrid.forkShowHidden
                                Accessible.onToggleAction: appGrid.forkSetShowHidden(!appGrid.forkShowHidden)

                                RectangularShadow {
                                    anchors.fill: knob
                                    radius: 9
                                    offset: Qt.vector2d(0, 1)
                                    blur: 3
                                    color: Qt.rgba(0, 0, 0, 0.3)
                                }
                                Rectangle {
                                    id: knob
                                    y: 2
                                    x: appGrid.forkShowHidden ? 18 : 2
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: "#FFFFFF"
                                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] } }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    appGrid.forkMenuId = -1
                                    appGrid.forkSetShowHidden(!appGrid.forkShowHidden)
                                }
                            }
                        }
                    }

                    Item { width: 1; height: 18 }

                    // The grid: rows are as tall as their tallest tile
                    Item {
                        id: grid
                        width: parent.width
                        visible: appGrid.forkListCount > 0

                        Repeater {
                            id: tiles
                            model: appGrid.forkSample ? appGrid.forkSampleModel : appGrid.appModel

                            delegate: ForkLibraryTile {
                                id: tile
                                required property var model
                                required property int index
                                readonly property int tileIndex: index
                                readonly property int appId: model.appid
                                readonly property bool isRunning: !!model.running
                                readonly property string sampleColor: appGrid.forkSample ? (model.sampleColor || "") : ""
                                readonly property bool isMenu: appGrid.forkMenuId === model.appid

                                visible: !appGrid.forkSample || appGrid.forkSampleMatches(model.name, !!model.hidden)
                                enabled: appGrid.forkMenuId < 0 || isMenu
                                property real gx: 0
                                property real gy: 0
                                x: gx
                                y: gy
                                width: appGrid.forkTileWidth
                                column: index % appGrid.forkColumns
                                onImplicitHeightChanged: appGrid.forkQueueLayout()
                                onVisibleChanged: appGrid.forkQueueLayout()
                                Component.onCompleted: appGrid.forkQueueLayout()

                                pcFill: appGrid.forkFill
                                pcOnFill: appGrid.forkOnFill
                                pcSky: appGrid.forkSky
                                asleep: appGrid.forkIsAsleep
                                ph: appGrid.forkTick % 2
                                settled: appGrid.forkSettled || ForkTheme.reduceMotion
                                entered: appGrid.forkOpen
                                enterDelay: 280 + 30 * index
                                chipColors: appGrid.forkChipColors
                                highlighted: appGrid.activeFocus && appGrid.currentIndex === index

                                appName: model.name
                                boxart: model.boxart || ""
                                appCollector: !!model.isAppCollectorGame
                                colorKey: sampleColor
                                running: isRunning && !appGrid.forkIsAsleep
                                hidden: !!model.hidden
                                chips: appGrid.forkChipsFor(model.name, !!model.directLaunch, !!model.hidden,
                                                            appGrid.forkSample ? model.sampleProfile : "",
                                                            appGrid.forkSample ? model.sampleExtras : "")
                                clickLabel: appGrid.forkIsAsleep ? qsTr("Wake %1 and start %2").arg(appGrid.objectName).arg(model.name)
                                          : isRunning ? qsTr("Resume %1").arg(model.name) : qsTr("Start %1").arg(model.name)

                                menuOpen: isMenu
                                menuCurrent: appGrid.forkMenuCurrent
                                menuItems: isMenu ? appGrid.forkMenuItemsFor(model.name, isRunning, !!model.hidden, !!model.directLaunch) : []

                                onActivated: {
                                    appGrid.currentIndex = -1
                                    appGrid.forkPick(index, model.name, model.appid, isRunning, model.boxart || "", sampleColor)
                                }
                                onMenuToggled: {
                                    appGrid.forkMenuCurrent = 0
                                    appGrid.forkMenuId = isMenu ? -1 : model.appid
                                }
                                onMenuRequested: {
                                    appGrid.forkMenuCurrent = 0
                                    appGrid.forkMenuId = model.appid
                                }
                                onMenuClosed: {
                                    appGrid.forkMenuId = -1
                                    appGrid.forceActiveFocus()
                                }
                                onMenuTriggered: function(i) {
                                    var action = menuItems.filter(function(item) { return !item.sep })[i]
                                    appGrid.forkMenuAction(action.id, index, model.name, model.appid, isRunning, !!model.hidden,
                                                           !!model.directLaunch, model.boxart || "", sampleColor)
                                }
                            }
                        }
                    }

                    // Nothing to show: every app hidden, or a search that matches nothing
                    Column {
                        visible: appGrid.forkListCount === 0
                        width: parent.width
                        topPadding: 72
                        bottomPadding: 40
                        spacing: 12

                        ForkPathIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "search"
                            size: 30
                            strokeWidth: 1.8
                            color: ForkTheme.cv.faint
                        }

                        ForkCanvasText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(440, parent.width)
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            px: 15
                            lineHeightPx: 21
                            color: ForkTheme.cv.text2
                            // [fork] Every app hidden, and a search that matches nothing, have their own words
                            text: appGrid.forkQuery.trim() !== ""
                                  ? qsTr("No apps on %1 match “%2”").arg(appGrid.objectName).arg(appGrid.forkQuery.trim())
                                  : appGrid.forkAppTotal > 0 ? qsTr("Every app on %1 is hidden. Show hidden apps to see them.").arg(appGrid.objectName)
                                                             : qsTr("This computer doesn't seem to have any applications or some applications are hidden")
                        }

                        ForkLibraryButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: appGrid.forkQuery.trim() !== ""
                            height: 32
                            radius: 9
                            padLeft: 14
                            padRight: 14
                            fontSize: 13
                            fontWeight: 550
                            text: qsTr("Clear Search")
                            fill: ForkTheme.cv.chip
                            ink: ForkTheme.cv.text
                            borderColor: ForkTheme.cv.line
                            borderWidth: 1
                            onClicked: appGrid.forkClearSearch()
                        }
                    }

                    Item { width: 1; height: 26 }

                    ForkCanvasText {
                        width: Math.min(parent.width, 760)
                        wrapMode: Text.Wrap
                        px: 12.5
                        lineHeightPx: 18
                        color: ForkTheme.cv.faint
                        text: appGrid.forkIsAsleep
                              ? qsTr("%1 is asleep, so these are the apps LuzLunar saw on its last visit. Picking one wakes %1 first.").arg(appGrid.objectName)
                              : appGrid.forkHostInfo.software === "Apollo"
                                ? qsTr("Click an app to start it, or right-click it for its options. To add an app, open Apollo’s web page on %1 and go to Applications.").arg(appGrid.objectName)
                                : qsTr("Click an app to start it, or right-click it for its options.")
                    }
                }
            }
        }

        Rectangle {
            id: innerMask
            anchors.fill: inner
            radius: 23
            visible: false
            layer.enabled: true
        }
    }

    // The search lives in the window's header; Clear Search asks it to empty (it calls forkSetQuery)
    signal forkSearchCleared()
    function forkClearSearch() {
        forkSetQuery("")
        forkSearchCleared()
    }

    // [fork] The alert: quit the running app, or quit it to start another
    ForkLibraryDialog {
        id: quitAppDialog
        title: appGrid.dlgKind === "switch" ? qsTr("%1 is running").arg(appGrid.dlgApp) : qsTr("Quit %1?").arg(appGrid.dlgApp)
        body: appGrid.dlgKind === "switch"
              ? qsTr("%1 runs one app at a time. Quitting %2 loses anything you haven’t saved in it.").arg(appGrid.objectName).arg(appGrid.dlgApp)
              : qsTr("It closes on %1. Anything you haven’t saved is lost.").arg(appGrid.objectName)
        confirmText: appGrid.dlgKind === "switch" ? qsTr("Quit it and start %1").arg(appGrid.dlgNextName) : qsTr("Quit")
        confirmFill: appGrid.dlgKind === "switch" ? "#0A6CDB" : "#D93A33"
        appName: appGrid.dlgKind === "switch" ? appGrid.dlgNextName : appGrid.dlgApp
        boxart: appGrid.dlgArt
        colorKey: appGrid.dlgColor
        skyColor: appGrid.forkSky
        onConfirmed: appGrid.forkDialogConfirmed()
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
        target: appGrid.forkSample ? appGrid.forkSampleModel : appGrid.appModel
        function onDataChanged() {
            Qt.callLater(appGrid.forkReadRunning)
            Qt.callLater(appGrid.forkCountHidden)
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
        currentIndex = -1
        forkReadHost() // [fork]
        forkReadRunning() // [fork]
        forkCountHidden() // [fork]
        if (ForkTheme.reduceMotion) {
            forkSettled = true
        }
    }

    StackView.onActivated: {
        if (forkVisibleModel) {
            forkVisibleModel.computerLost.connect(computerLost) // [fork] was appModel, which can be swapped now
        }
        activated = true
        forkReadHost() // [fork]
        forkReadRunning() // [fork]
        forkCountHidden() // [fork]
        appGrid.forceActiveFocus()

        // Highlight the first item if a gamepad is connected
        if (currentIndex === -1 && SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            Qt.callLater(function() { appGrid.forkMove(0, 1) })
        }

        if (!showGames && !showHiddenGames && !forkSample && !forkIsAsleep) { // [fork] samples don't start
            // Check if there's a direct launch app
            var directLaunchAppIndex = appModel.getDirectLaunchAppIndex();
            if (directLaunchAppIndex >= 0) {
                // Start the direct launch app if nothing else is running
                var item = tiles.itemAt(directLaunchAppIndex)
                if (item) {
                    forkLaunchOrResume(directLaunchAppIndex, item.appName, item.appId, false, "", "")
                }

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

    function createModel(showHidden) // [fork] was without the argument, showing showHiddenGames
    {
        var model = Qt.createQmlObject('import AppModel; AppModel {}', parent, '')
        model.initialize(ComputerManager, computerIndex, showHidden)
        // [fork] The page stays while its PC sleeps: the apps of its last visit (see contract-library.md)
        if (model.forkKeepWhenOffline) {
            model.forkKeepWhenOffline(true)
        }
        return model
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
}
