import QtQuick
import QtQuick.Controls
import QtQuick.Effects // [fork] the All apps hand-off's blur
import QtQuick.Layouts

import ForkTheme // [fork]
import ForkHostUpdates // [fork]
import ForkHostPower // [fork]
import ForkPcPrefs // [fork]

import "ForkLibraryLaunch.js" as Launch // [fork] the launch screen's summary chips

import ComputerManager
import StreamingPreferences
import SdlGamepadKeyNavigation

// [fork] Your PCs, the canvas's Main board: the greeting and story row, tonight's moon and the
// discovery pill, and below them the PC cards, one in front with its neighbours turned toward it
// (or all of them in a grid), a "Pick a PC" row and a key hint. The ... menu, the pairing, wake,
// sleep, update, rename, remove and details dialogs of the old page are kept. Spec: carousel.md;
// the contract for the harness and the header is spec/contract-pcview.md.
Item {
    id: pcPage

    property var computerModel: null
    // [fork] Sample PCs for the screenshot harness: a ListModel with ComputerModel's roles, shown
    // instead of the real PCs, which asks nothing of the network or of ComputerManager
    property var forkSampleModel: null
    readonly property bool forkSample: forkSampleModel !== null
    readonly property var pcModel: forkSample ? forkSampleModel : computerModel

    focus: true
    activeFocusOnTab: true
    objectName: "LuzLunar" // the window title

    // ---- what the header and main.qml read
    // "carousel" | "grid"; the header's View as control shows it and calls forkSetViewMode
    property string forkViewMode: "carousel"
    readonly property bool forkHasPcs: pcCount > 0
    // The shared sky behind the page (main.qml): none while the first run shows
    readonly property string forkSkyVariant: showFirstRun ? "none" : "main"
    // The first run's bars are opaque (the Empty board has no sky behind them)
    readonly property bool forkChromeOpaque: showFirstRun
    // The header's Add PC and the new-PC key: the dialog, or on the first run the address field
    function forkAddPc() {
        if (showFirstRun && firstRun.item) firstRun.item.focusAddress()
        else addPcDialog.open()
    }
    function forkSetViewMode(mode) {
        if (mode !== "carousel" && mode !== "grid") return
        if (mode === "grid") demo = false
        menuOpen = false
        forkViewMode = mode
        // Remembered per Mac (ForkPcPrefs.pcsView, "carousel" | "grid"), once DATA has it
        if (ForkPcPrefs.pcsView !== undefined && !forkSample) ForkPcPrefs.pcsView = mode
    }

    // ---- the harness's hooks (contract-pcview.md)
    property bool forkEntrance: !ForkPcPrefs.screenshotMode
    // 0 = the real clock; else the instant the greeting and the moon use (UTC ms)
    property double forkNowMs: ForkPcPrefs.screenshotMode ? Date.UTC(2026, 10, 9, 23, 10) : 0
    // -1 = the local hour of the clock; else the hour the greeting uses
    property int forkHour: ForkPcPrefs.screenshotMode ? 23 : -1
    property string forkFirstName: ForkPcPrefs.firstName
    property string forkLastToast: ""
    function forkFocus(i) { go(i, undefined, false) }
    function forkOpenMenu(i) { if (i !== undefined) go(i, undefined, false); toggleMenu() }
    function forkCloseMenu() { menuOpen = false }
    // Shows the Pause demo pill without LUZLUNAR_DEMO (the harness; ForkPcPrefs.demoMode is constant)
    property bool forkDemoPill: false
    function forkStartDemo() { forkDemoPill = true; demo = true }
    function forkOpenCustomize(i) { runAction(i !== undefined ? i : idx, "customize") }
    function forkStopDemo() { demo = false }
    function forkSkipEntrance() {
        introTimer.stop(); revealTimer.stop(); settleTimer.stop()
        noEntrance = true
        intro = true; revealed = true; settled = true
    }
    property bool noEntrance: false
    function forkTickDemo() { if (demo) go(idx + 1, 1, true) }
    function forkShowToast(text) { forkToast(text) }
    readonly property alias forkStage: stage
    readonly property bool forkMenuOpen: menuOpen
    readonly property bool forkDemoOn: demo
    readonly property int forkIndex: idx

    // ---- page state (carousel.md §3.1)
    property int idx: 0
    property int prevIdx: -1
    property int moveDir: 0
    property int prevDir: 0
    property bool intro: false
    property bool revealed: false
    property bool settled: false
    property bool demo: ForkPcPrefs.demoMode && !ForkTheme.reduceMotion
    property bool menuOpen: false
    property bool appsOpen: false
    property int tick: 0
    property int clockHour: new Date().getHours()
    property double clockMs: Date.now()
    // uuid -> true while a Wake PC was sent and the PC hasn't come online yet
    property var wakingUuids: ({})
    property string toastText: ""
    readonly property bool motionOn: visible && !ForkTheme.reduceMotion

    readonly property int pcCount: stage.pcCount
    readonly property int slotCount: pcCount + 1
    readonly property bool showFirstRun: pcCount === 0 && firstRunSettled
    // The model is empty for a moment at startup, before the first poll: the first-run page waits
    // a beat so a PC that is already known doesn't flash it
    property bool firstRunSettled: forkSample
    property bool dark: ForkTheme.dark

    Timer {
        id: introTimer
        interval: 150
        onTriggered: pcPage.intro = true
    }
    Timer {
        id: revealTimer
        interval: 1600
        onTriggered: pcPage.revealed = true
    }
    Timer {
        id: settleTimer
        interval: 120
        onTriggered: pcPage.settled = true
    }
    Timer {
        id: demoTimer
        interval: 3400
        repeat: true
        running: pcPage.demo && pcPage.visible && !pcPage.showFirstRun
        onTriggered: {
            if (pcPage.demo && !pcPage.menuOpen && pcPage.hoverIdx === -1) {
                pcPage.go(pcPage.idx + 1, 1, true)
            }
        }
    }
    // The shared animation clock the cards' ambient motion runs on (card.md §1.6)
    Timer {
        interval: 1100
        repeat: true
        running: pcPage.motionOn && !ForkPcPrefs.screenshotMode
        onTriggered: pcPage.tick++
    }
    // The greeting and the moon follow the clock
    Timer {
        interval: 30000
        repeat: true
        running: pcPage.visible
        onTriggered: { pcPage.clockHour = new Date().getHours(); pcPage.clockMs = Date.now() }
    }
    Timer {
        id: firstRunTimer
        interval: 1200
        running: !pcPage.forkSample
        onTriggered: pcPage.firstRunSettled = true
    }
    Timer {
        id: toastTimer
        interval: 2200
        onTriggered: pcPage.toastText = ""
    }

    Component.onCompleted: {
        if (!forkSample) {
            computerModel = createModel()
        }
        if (ForkTheme.reduceMotion || !forkEntrance) {
            noEntrance = true
            intro = true; revealed = true; settled = true
        } else {
            introTimer.start(); revealTimer.start(); settleTimer.start()
        }
        if (!forkSample && ForkPcPrefs.pcsView === "grid") forkViewMode = "grid"
        forceActiveFocus()
    }

    // The greeting's words and moon read the pinned clock when the harness set one
    readonly property int greetHour: forkHour >= 0 ? forkHour : clockHour
    readonly property double moonMs: forkNowMs > 0 ? forkNowMs : clockMs
    readonly property string greetingText: {
        var h = greetHour
        var word = h < 5 ? qsTr("Up late") : h < 12 ? qsTr("Good morning") : h < 17 ? qsTr("Good afternoon") : h < 22 ? qsTr("Good evening") : qsTr("Good night")
        return forkFirstName !== "" ? qsTr("%1, %2").arg(word).arg(forkFirstName) : word
    }

    // ---- moving (carousel.md §3.4)
    property int hoverIdx: stage.hoverIndex
    function offsetOf(i, at, d) { return stage.offsetOf(i, at, d) }
    function go(i, d, auto) {
        var n = slotCount
        var loop = n > 2
        var target = loop ? ((i % n) + n) % n : Math.max(0, Math.min(n - 1, i))
        if (target === idx) {
            menuOpen = false
            if (!auto) demo = false
            return
        }
        var dir = d !== undefined ? d : (target > idx ? 1 : -1)
        prevIdx = idx
        prevDir = moveDir
        idx = target
        moveDir = dir
        menuOpen = false
        if (!auto) demo = false
        if (!ForkTheme.reduceMotion) {
            settled = false
            settleTimer.interval = 60
            settleTimer.restart()
        }
    }
    function pick(i) { go(i, slotCount > 2 ? (offsetOf(i, idx, 0) > 0 ? 1 : -1) : undefined, false) }
    function step(delta) { go(idx + delta, delta, false) }

    // ---- rows of the model, by slot
    function rowOf(i) {
        var s = stage.slotAt(i)
        return s && !s.isAdd ? s.rowModel : null
    }
    function isAddSlot(i) { return i === pcCount }

    function normState(s) {
        switch (s) {
        case "offCanWake": return "off"
        case "notPaired": return "pair"
        case "unreachable": return "lost"
        }
        return s
    }
    // The card state: the model's, or (an older model) worked out from its first roles
    function stateOf(m) {
        if (!m) return "ready"
        var w = wakingUuids[m.uuid] === true && !m.online
        if (w) return "waking"
        // An online, paired host whose software Moonlight refuses: the "can't reach" look, and its
        // main action says why (today's errorDialog)
        if (m.online === true && m.paired === true && m.serverSupported === false) return "lost"
        var s = m.state
        if (s !== undefined && s !== "") return normState(s)
        if (m.statusUnknown) return "waking"
        if (!m.online) return m.wakeable ? "asleep" : "lost"
        if (!m.paired) return "pair"
        return m.busy ? "streaming" : "ready"
    }
    function hueOf(m) {
        if (!m) return "indigo"
        if (stateOf(m) === "pair") return "gray"
        var k = m.colorKey !== undefined ? m.colorKey : (m.hue !== undefined ? m.hue : "")
        if (k === "" || k === undefined) {
            var rev = ForkPcPrefs.revision
            k = ForkPcPrefs.colorKey(m.uuid)
        }
        return k
    }
    function appsOf(m) {
        var list = m ? m.previewApps : null
        var out = []
        if (!list) return out
        if (list.get !== undefined) {
            for (var i = 0; i < list.count; i++) out.push(list.get(i))
        } else {
            for (var j = 0; j < list.length; j++) out.push(list[j])
        }
        return out
    }
    function networkText(m) {
        return m.network === "home" ? qsTr("Home network") : m.network === "internet" ? qsTr("Over the internet") : ""
    }
    function noteText(id) {
        return id === "reachableOutside" ? qsTr("Reachable from outside too")
             : id === "lastAddress" ? qsTr("Its last address")
             : id === "foundAutomatically" ? qsTr("Found automatically")
             : id === "outsideAddress" ? qsTr("Its address from outside")
             : id === "addedByAddress" ? qsTr("Added by its address") : ""
    }
    function runningAppOf(m) { return m && m.runningApp ? m.runningApp : "" }
    function appName(m) { return runningAppOf(m) !== "" ? runningAppOf(m) : (m && m.mainApp ? m.mainApp : "Desktop") }

    // ---- the story under the title (carousel.md §2.3)
    readonly property var storyLines: {
        var rev = stage.itemsRevision
        var out = []
        for (var i = 0; i < pcCount; i++) {
            var m = rowOf(i)
            if (!m) continue
            var st = stateOf(m)
            var line = { name: m.name, before: "", after: "", dot: ForkTheme.st.green, action: "" }
            switch (st) {
            case "streaming":
                line.before = qsTr("%1 is running on ").arg(appName(m)); line.dot = ForkTheme.st.blue; line.action = qsTr("Resume"); break
            case "asleep": line.after = qsTr(" is asleep"); line.dot = ForkTheme.st.purple; break
            case "pair": line.after = qsTr(" is waiting to pair"); line.dot = ForkTheme.st.gold; break
            case "waking": line.after = qsTr(" is waking up…"); line.dot = ForkTheme.st.amber; break
            case "off": case "offNoWake": line.after = qsTr(" is shut down"); line.dot = ForkTheme.st.gray; break
            case "lost": line.before = qsTr("Can’t reach "); line.dot = ForkTheme.st.red; break
            case "checking": line.before = qsTr("Looking for "); line.after = qsTr("…"); line.dot = ForkTheme.st.gray; break
            default: line.after = qsTr(" is ready"); break
            }
            out.push(line)
        }
        return out
    }
    readonly property var navChips: {
        var rev = stage.itemsRevision
        var out = []
        for (var i = 0; i < pcCount; i++) {
            var m = rowOf(i)
            if (m) out.push({ name: m.name, dot: ForkTheme.hue(hueOf(m)).fill })
        }
        out.push({ name: qsTr("Add a PC"), dot: ForkTheme.cv.muted })
        return out
    }

    // Keep the focus on the same PC when PCs come and go (carousel.md §11.9)
    property string focusUuid: ""
    function noteFocus() {
        var m = rowOf(idx)
        focusUuid = m ? m.uuid : ""
    }
    Connections {
        target: stage
        function onItemsRevisionChanged() {
            if (pcPage.focusUuid !== "") {
                for (var i = 0; i < pcPage.pcCount; i++) {
                    var m = pcPage.rowOf(i)
                    if (m && m.uuid === pcPage.focusUuid) {
                        if (i !== pcPage.idx) { pcPage.idx = i; pcPage.prevIdx = -1 }
                        return
                    }
                }
            }
            if (pcPage.idx > pcPage.pcCount) pcPage.idx = pcPage.pcCount
        }
    }
    onIdxChanged: Qt.callLater(noteFocus)

    // ---- the headline texts above the stage
    readonly property real sectionTop: 22
    readonly property real stageBlockHeight: 556 + 6 + 28 + 10 + 15
    readonly property real stageTop: sectionTop + section.height + 14
    // Smaller windows scale the stage down together (sky-chrome.md §4.14)
    readonly property real stageScale: Math.max(0.6, Math.min(1, (height - stageTop - 10) / stageBlockHeight, width / 1280))

    function escapeMarkup(text) {
        if (!text || text.indexOf("<") < 0) {
            return text
        }
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    // ---- actions (every one the old card and menu had, parity map app-qml.md §2.12)
    function forkToast(text) {
        forkLastToast = text
        if (typeof window !== "undefined" && window && typeof window.forkToast === "function") {
            window.forkToast(text)
        }
    }
    readonly property bool canLaunch: !forkSample && computerModel !== null && typeof computerModel.createSessionForApp === "function"
    readonly property bool canQuit: !forkSample && computerModel !== null && typeof computerModel.quitRunningApp === "function"
    readonly property bool canWakeThenStream: !forkSample && computerModel !== null
    // Fallback for a harness without main.qml's shared instance
    ForkWakeLaunch {
        id: wakeLaunch
        summaryFor: function (appName) { return Launch.streamSummary(pcPage.wakeUuid, appName) }
    }
    property string wakeUuid: ""

    function forkWake(i) {
        var m = rowOf(i)
        if (!m) return
        var w = Object.assign({}, wakingUuids)
        w[m.uuid] = true
        wakingUuids = w
        wakeTimeouts.restart()
        ForkHostPower.noteWakeSent(m.uuid)
        if (computerModel) computerModel.wakeComputer(i)
    }
    // Waking ends when the PC answers (its poweredOn() toasts) or after 3 minutes
    Timer {
        id: wakeTimeouts
        interval: 180000
        onTriggered: pcPage.wakingUuids = ({})
    }
    function noteOnlineState() {
        var w = wakingUuids
        var changed = false
        var next = {}
        for (var i = 0; i < pcCount; i++) {
            var m = rowOf(i)
            if (m && w[m.uuid] === true) {
                if (m.online) { ForkHostPower.noteOnline(m.uuid); changed = true }
                else next[m.uuid] = true
            }
        }
        if (changed) wakingUuids = next
    }
    Connections {
        target: stage
        function onItemsRevisionChanged() { pcPage.noteOnlineState() }
    }
    Repeater {
        model: pcPage.forkSample ? 0 : pcPage.pcCount
        delegate: Item {
            required property int index
            readonly property var m: pcPage.rowOf(index)
            readonly property bool online: m ? m.online === true : false
            onOnlineChanged: pcPage.noteOnlineState()
        }
    }

    function pairPc(i) {
        var m = rowOf(i)
        if (!m || !computerModel) { forkToast(qsTr("Pairing with %1…").arg(m ? m.name : "")); return }
        if (!m.serverSupported && m.serverSupported !== undefined) {
            errorDialog.text = qsTr("The version of GeForce Experience on %1 is not supported by this build of Moonlight. You must update Moonlight to stream from %1.").arg(m.name)
            errorDialog.helpText = ""
            errorDialog.open()
            return
        }
        var pin = computerModel.generatePinString()
        computerModel.pairComputer(i, pin)
        pairDialog.pin = pin
        pairDialog.pcIndex = i
        pairDialog.pcName = m.name
        pairDialog.paired = false
        pairDialog.open()
    }

    // All apps: the PC's page grows out of `origin` (page coordinates)
    function openApps(i, origin) {
        var m = rowOf(i)
        if (!m || (forkSample && forkSampleApps === null) || (!forkSample && !computerModel)) { forkToast(qsTr("Opens all of %1's apps").arg(m ? m.name : "")); return }
        var component = Qt.createComponent("AppView.qml")
        var online = m.online === true
        var props = {"computerIndex": i, "objectName": m.name, "showHiddenGames": true,
                     "forkHostStatus": online ? (m.hostSoftware !== "" && m.hostSoftware !== undefined ? qsTr("%1 · online").arg(m.hostSoftware) : qsTr("Online")) : qsTr("Asleep"),
                     "forkAsleep": !online, "forkColorKey": hueOf(m), "forkComputerModel": computerModel,
                     "forkLatencyMs": m.latencyMs !== undefined ? m.latencyMs : -1, "forkWakeReady": m.wakeFromOff === "ready"}
        if (forkSample) {
            props["forkSampleModel"] = forkSampleApps
            var host = forkSampleHostInfo ? Object.assign({}, forkSampleHostInfo) : {}
            host.software = m.hostSoftware
            host.version = m.apolloVersion
            host.address = m.address
            host.latencyMs = m.latencyMs
            host.colorKey = hueOf(m)
            host.wakeReady = m.wakeFromOff === "ready"
            host.asleep = !online
            props["forkSampleHost"] = host
            delete props["forkComputerModel"]
        }
        if (origin) {
            props["forkOriginX"] = origin.x
            props["forkOriginY"] = origin.y
        }
        var appView = component.createObject(stackView, props)
        if (appView === null) { forkToast(component.errorString()); return }
        appsOpen = true
        stackView.push(appView)
    }
    // Sample apps for the harness: a ListModel with AppModel's roles and the host's facts; forkOpenApps(i)
    // pushes AppView with them (the model's own apps when the page isn't in sample mode)
    property var forkSampleApps: null
    property var forkSampleHostInfo: null
    function forkOpenApps(i) { openApps(i, geoOrigin(i)) }
    function geoOrigin(i, local) {
        // `local` is a point in the card's own 560 x 540 box, or undefined for the card's center
        var g = stage.geoOf(i)
        var p = local !== undefined ? Qt.point((local.x - 280) * g.s + g.cx, (local.y - 270) * g.s + g.cy) : Qt.point(g.cx, g.cy)
        return stage.mapToItem(pcPage, p.x, p.y)
    }

    // Starts a stream of one of the PC's apps (or resumes the running one); without the model's
    // launch support the PC's apps page opens instead
    function launchApp(i, appId, appLabel, resume) {
        var m = rowOf(i)
        if (!m) return
        if (!canLaunch || !appId) { openApps(i, geoOrigin(i)); return }
        var session = computerModel.createSessionForApp(i, appId)
        if (!session) { openApps(i, geoOrigin(i)); return }
        var component = Qt.createComponent("StreamSegue.qml")
        var segue = component.createObject(stackView, {
                                               "appName": appLabel,
                                               "session": session,
                                               "isResume": resume,
                                               "hostName": m.name,
                                               "summary": Launch.streamSummary(m.uuid, appLabel)
                                           })
        stackView.push(segue)
    }
    // An app picked on a sleeping or shut-down PC: wake it, wait, then start the app (ForkWakeLaunch,
    // which respects "Wake it when I pick an app"); without that helper it just wakes the PC
    function wakeThenLaunch(i, appId, label) {
        var m = rowOf(i)
        if (m) wakeUuid = m.uuid
        // One wake-launch app-wide: main.qml's (window.forkWakeLaunch) when it has one, else this page's own
        var shared = (typeof window !== "undefined" && window && window.forkWakeLaunch) ? window.forkWakeLaunch : wakeLaunch
        shared.summaryFor = function (appName) { return Launch.streamSummary(pcPage.wakeUuid, appName) }
        if (canWakeThenStream && appId) shared.start(computerModel, i, appId, label)
        else forkWake(i)
    }
    function quitRunning(i) {
        var m = rowOf(i)
        if (!m) return
        if (!canQuit) { openApps(i, geoOrigin(i)); return }
        quitDialog.pcIndex = i
        quitDialog.appName = runningAppOf(m)
        quitDialog.pcName = m.name
        quitDialog.pcUuid = m.uuid
        quitDialog.open()
    }
    function copyAddress(text) {
        copier.text = text
        copier.selectAll()
        copier.copy()
        forkToast(qsTr("Copied %1").arg(text))
    }
    TextEdit { id: copier; visible: false; Accessible.ignored: true }

    // The card's main action, what Return and the menu's highlighted row do
    function primaryAction(i) {
        if (isAddSlot(i)) { addPcDialog.open(); return }
        var m = rowOf(i)
        if (!m) return
        switch (stateOf(m)) {
        case "streaming": runAction(i, "resume"); break
        case "ready": runAction(i, "stream"); break
        case "asleep": case "off": runAction(i, "wakeAndStream"); break
        case "offNoWake": runAction(i, "setupWake"); break
        case "pair": runAction(i, "pair"); break
        case "lost": runAction(i, "testNetwork"); break
        }
    }

    function runAction(i, id) {
        var m = rowOf(i)
        if (!m) return
        menuOpen = false
        demo = false
        switch (id) {
        case "resume": launchApp(i, m.runningAppId, appName(m), true); break
        case "stream": launchApp(i, m.mainAppId, appName(m), false); break
        case "wake": case "turnOn": forkWake(i); break
        case "wakeAndStream":
            // Wakes it, then starts the app once it answers (ForkHostPower, when the backend has it)
            wakeThenLaunch(i, m.mainAppId, appName(m))
            break
        case "setupWake": wakeSetupDialog.openFor(m.uuid, m.name); break
        case "pair": pairPc(i); break
        case "testNetwork":
            if (m.online === true && m.paired === true && m.serverSupported === false) {
                errorDialog.text = qsTr("The version of GeForce Experience on %1 is not supported by this build of Moonlight. You must update Moonlight to stream from %1.").arg(m.name)
                errorDialog.helpText = ""
                errorDialog.open()
            } else if (computerModel) { computerModel.testConnectionForComputer(i); testConnectionDialog.open() }
            else forkToast(qsTr("Testing the network to %1…").arg(m.name))
            break
        case "sleep": case "shutDown":
            sleepPcDialog.mode = id === "shutDown" ? "off" : "sleep"
            sleepPcDialog.pcUuid = m.uuid
            sleepPcDialog.pcName = m.name
            sleepPcDialog.open()
            break
        case "quit": quitRunning(i); break
        case "update":
            ForkHostUpdates.install(m.uuid)
            forkToast(qsTr("Updating Apollo on %1").arg(m.name))
            break
        case "allApps": openApps(i, geoOrigin(i)); break
        case "multiDisplay": launchApp(i, multiDisplayId(m), qsTr("Desktop (multiple displays)"), false); break
        case "customize": customizeDialog.openFor(m.uuid, m.name, i); break
        case "details":
            showPcDetailsDialog.pcDetails = m.details
            showPcDetailsDialog.open()
            break
        case "remove":
            deletePcDialog.pcIndex = i
            deletePcDialog.pcName = m.name
            deletePcDialog.open()
            break
        }
    }
    function multiDisplayId(m) {
        var apps = appsOf(m)
        for (var i = 0; i < apps.length; i++) {
            if (apps[i].name.indexOf("multiple displays") >= 0) return apps[i].appid
        }
        return 0
    }

    // ---- the ... menu's rows per state (carousel.md §6.3); rows with no backend are left out
    function menuSections(i) {
        var m = rowOf(i)
        if (!m) return []
        var st = stateOf(m)
        var app = appName(m)
        var flag = function (v) { return v === true }
        var item = function (id, label, icon, extra) {
            var o = { id: id, label: label, icon: icon }
            if (extra) for (var k in extra) o[k] = extra[k]
            return o
        }
        var sec = []
        var online = m.online === true
        var main = []
        switch (st) {
        case "streaming":
            main.push(item("resume", qsTr("Resume %1").arg(app), "play", { fill: true, key: "↩", hi: true }))
            if (canQuit || forkSample) main.push(item("quit", qsTr("Quit %1").arg(app), "stop"))
            main.push(item("allApps", qsTr("Show All Apps"), "grid"))
            break
        case "ready":
            main.push(item("stream", qsTr("Stream %1").arg(app), "play", { fill: true, key: "↩", hi: true }))
            main.push(item("allApps", qsTr("Show All Apps"), "grid"))
            break
        case "asleep":
            main.push(item("wake", qsTr("Wake PC"), "power", { key: "↩", hi: true }))
            if (canWakeThenStream || forkSample) main.push(item("wakeAndStream", qsTr("Wake and Stream %1").arg(app), "play", { fill: true, badge: qsTr("New") }))
            break
        case "off":
            main.push(item("turnOn", qsTr("Turn On"), "power", { key: "↩", hi: true }))
            break
        case "offNoWake":
            main.push(item("setupWake", qsTr("Set Up Wake from Off…"), "check", { key: "↩", hi: true }))
            break
        case "pair":
            main.push(item("pair", qsTr("Pair with This PC…"), "lock", { key: "↩", hi: true }))
            break
        case "lost":
            main.push(item("testNetwork", qsTr("Test Network"), "wifi", { key: "↩", hi: true }))
            break
        }
        if (main.length) sec.push(main)

        var net = []
        if (st === "streaming" && (canLaunch || forkSample) && multiDisplayId(m) !== 0) net.push(item("multiDisplay", qsTr("Desktop (multiple displays)"), "displays"))
        if (st !== "lost") net.push(item("testNetwork", qsTr("Test Network"), "wifi"))
        else net = []
        var power = []
        if (flag(m.canSleep) && st !== "waking") power.push(item("sleep", qsTr("Sleep PC"), "moon"))
        if (flag(m.canShutDown)) power.push(item("shutDown", qsTr("Shut Down PC…"), "power"))

        var upd = []
        if (online && flag(m.hostUpdate)) upd.push(item("update", qsTr("Update Apollo"), "update", { badge: qsTr("Update"), warm: true }))
        if ((flag(m.canSetUpWake) || st === "asleep") && st !== "offNoWake") upd.push(item("setupWake", qsTr("Set Up Wake from Off…"), "check"))

        var tail = [item("customize", qsTr("Customize…"), "palette", { badge: qsTr("New") }),
                    item("details", qsTr("View Details"), "info")]

        if (st === "streaming" || st === "ready") {
            sec.push(net)
            if (power.length) sec.push(power)
            sec.push(upd.concat(tail))
        } else if (st === "asleep" || st === "off") {
            sec.push(net.concat(upd))
            sec.push(tail)
        } else {
            sec.push(net.concat(tail))
        }
        sec.push([item("remove", qsTr("Remove PC…"), "trash", { key: "⌫", danger: true })])
        return sec.filter(function (s) { return s.length > 0 })
    }

    function toggleMenu() {
        if (isAddSlot(idx) || rowOf(idx) === null) { menuOpen = false; return }
        demo = false
        menuOpen = !menuOpen
    }

    // A pointer press hides the keyboard focus ring
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.AllButtons
        propagateComposedEvents: true
        onPressed: function (mouse) { pcPage.keyFocus = false; mouse.accepted = false }
    }

    // The first run gives way to the cards with a 400 ms cross-fade (instant under Reduce Motion)
    property real arrive: showFirstRun ? 0 : 1
    Behavior on arrive { enabled: !ForkTheme.reduceMotion && !pcPage.forkSample; NumberAnimation { duration: 400; easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] } }

    // ---- the board (everything but the sky, the menu and the toast), which steps back when All
    // apps opens over it (carousel.md §8)
    Item {
        id: board
        anchors.fill: parent
        visible: opacity > 0.001 && !pcPage.showFirstRun
        enabled: !pcPage.appsOpen
        property real fxBlur: 0
        transformOrigin: Item.Center
        layer.enabled: fxBlur > 0.01
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            blur: board.fxBlur / 32
        }
        states: State {
            name: "away"
            when: pcPage.appsOpen
            PropertyChanges { board.opacity: 0; board.scale: 0.95; board.fxBlur: 6 }
        }
        transitions: [
            Transition {
                to: "away"
                enabled: !ForkTheme.reduceMotion
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: 260; easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] }
                    NumberAnimation { property: "scale"; duration: 480; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
                    NumberAnimation { property: "fxBlur"; duration: 480; easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] }
                }
            },
            Transition {
                from: "away"
                enabled: !ForkTheme.reduceMotion
                ParallelAnimation {
                    SequentialAnimation {
                        PauseAnimation { duration: 160 }
                        NumberAnimation { target: board; property: "opacity"; duration: 380; easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] }
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: 100 }
                        NumberAnimation { target: board; property: "scale"; duration: 560; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: 100 }
                        NumberAnimation { target: board; property: "fxBlur"; duration: 460; easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] }
                    }
                }
            }
        ]

        // Greeting row: the story at the left, the moon and the discovery pill at the right
        Item {
            id: section
            opacity: pcPage.arrive
            y: pcPage.sectionTop
            width: parent.width
            height: Math.max(story.height, rightCol.height)

            ForkStoryRow {
                id: story
                x: 64
                width: Math.max(300, pcPage.width - 128 - rightCol.width - 24)
                greeting: pcPage.greetingText
                lines: pcPage.storyLines
                intro: pcPage.intro
                instant: pcPage.noEntrance
                onPick: function (i) { pcPage.pick(i) }
                onAct: function (i) { pcPage.runAction(i, "resume") }
            }

            ForkStoryRise {
                id: rightCol
                anchors.right: parent.right
                anchors.rightMargin: 64
                anchors.bottom: parent.bottom
                active: pcPage.intro
                instant: pcPage.noEntrance
                delay: 420
                dy: 8
                width: Math.max(moon.width, pill.width)
                height: moon.height + 10 + pill.height
                ForkMoonWidget {
                    id: moon
                    anchors.right: parent.right
                    nowMs: pcPage.moonMs
                }
                ForkDiscoveryPill {
                    id: pill
                    anchors.right: parent.right
                    y: moon.height + 10
                    active: !!StreamingPreferences.enableMdns
                    text: !!StreamingPreferences.enableMdns ? qsTr("Looking for PCs on your network") : qsTr("Automatic PC discovery is off")
                }
            }
        }

        // The stage block, scaled down in small windows
        Item {
            id: stageBlock
            opacity: pcPage.arrive
            y: pcPage.stageTop
            width: parent.width
            height: pcPage.stageBlockHeight * pcPage.stageScale

            Item {
                id: scaled
                width: pcPage.width / pcPage.stageScale
                height: pcPage.stageBlockHeight
                scale: pcPage.stageScale
                transformOrigin: Item.TopLeft

                ForkPcStage {
                    id: stage
                    width: parent.width
                    pcModel: pcPage.pcModel
                    index: pcPage.idx
                    prevIndex: pcPage.prevIdx
                    dir: pcPage.moveDir
                    prevDir: pcPage.prevDir
                    view: pcPage.forkViewMode
                    settled: pcPage.settled
                    revealed: pcPage.revealed
                    keyFocusRing: pcPage.keyFocus && pcPage.activeFocus
                    // A pointer resting on a card would lift it (-6 px) in a screenshot
                    hoverEnabled: !ForkPcPrefs.screenshotMode
                    pcCard: pcCardComp
                    addCard: addCardComp
                    onPick: function (i) { pcPage.pick(i) }
                    onStep: function (d) { pcPage.step(d) }
                }

                ForkDotsNav {
                    id: dots
                    y: 556 + 6
                    width: parent.width
                    visible: pcPage.forkViewMode === "carousel"
                    chips: pcPage.navChips
                    current: pcPage.idx
                    showDemo: ForkPcPrefs.demoMode || pcPage.forkDemoPill
                    demoOn: pcPage.demo
                    onPicked: function (i) { pcPage.pick(i) }
                    onToggleDemo: pcPage.demo = !pcPage.demo
                }

                ForkCanvasText {
                    y: pcPage.forkViewMode === "carousel" ? 556 + 6 + 28 + 10 : 556 + 10
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("← → move between PCs · Return does the main action · ⌘N adds a PC")
                    px: 12
                    color: ForkTheme.cv.faint
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }
        }
    }

    // ---- the cards, as the stage makes them: `m` is the PC's row, `slot` its place on the stage
    Component {
        id: pcCardComp
        ForkPcCard {
            id: pc
            property var m: null
            property var slot: null
            readonly property string st: pcPage.stateOf(m)
            pcName: m ? m.name : ""
            hueKey: pcPage.hueOf(m)
            cardState: st
            version: m && m.apolloVersion !== undefined ? m.apolloVersion : ""
            network: m ? pcPage.networkText(m) : ""
            latencyMs: m && m.latencyMs !== undefined ? m.latencyMs : -1
            address: m && m.address !== undefined ? m.address : ""
            ipNote: m ? pcPage.noteText(m.addressNote) : ""
            reachableOutside: m ? (m.hasRemoteAddress === true || m.remoteWorked === true) : false
            onLanNow: m ? m.network === "home" : true
            runningApp: m && m.runningApp !== undefined ? m.runningApp : ""
            defaultApp: m && m.mainApp ? m.mainApp : "Desktop"
            streamWidth: m && m.streamWidth !== undefined ? m.streamWidth : 0
            streamHeight: m && m.streamHeight !== undefined ? m.streamHeight : 0
            streamFps: m && m.streamFps !== undefined ? m.streamFps : 0
            streamHdr: m ? m.streamHdr === true : false
            wakeFromOff: m ? (m.wakeFromOff === "ready" ? "ready" : (m.wakeFromOff === "" || m.wakeFromOff === undefined ? "unknown" : "notSetUp")) : "unknown"
            updateAvailable: m ? m.hostUpdate === true : false
            apps: m ? pcPage.appsOf(m).map(function (a) { return { name: a.name, cover: a.boxart, running: a.running === true } }) : []

            focused: slot ? slot.focused : false
            arriving: focused && pcPage.revealed && !pcPage.settled
            settled: pcPage.settled
            revealed: pcPage.revealed
            sharedTick: pcPage.tick
            motion: pcPage.motionOn

            // Inputs the card gets later (D11): bound when it has them
            Component.onCompleted: {
                var bind = function (name, fn) { if (pc.hasOwnProperty(name)) pc[name] = Qt.binding(fn) }
                bind("canSleep", function () { return m ? m.canSleep !== false : true })
                bind("apolloUpToDate", function () { return m ? m.apolloUpToDate === true : false })
                bind("appsCached", function () { return m ? m.appsCached === true : false })
                bind("hiddenAppCount", function () { return m && m.hiddenAppCount !== undefined ? m.hiddenAppCount : 0 })
                bind("online", function () { return m ? m.online === true : false })
                bind("lastSeenVia", function () { return m && m.lastSeenVia !== undefined ? (m.lastSeenVia === "internet" ? "outside" : m.lastSeenVia) : "" })
                bind("unsupported", function () { return m ? (m.online === true && m.paired === true && m.serverSupported === false) : false })
            }

            onPrimaryClicked: function (action) { if (slot) pcPage.runAction(slot.slotIndex, action) }
            onQuietClicked: function (action) { if (slot) pcPage.runAction(slot.slotIndex, action) }
            onMoreClicked: { if (slot) { pcPage.demo = false; pcPage.toggleMenu() } }
            onCopyAddressClicked: function (text) { pcPage.copyAddress(text) }
            onUpdateApolloClicked: { if (slot) pcPage.runAction(slot.slotIndex, "update") }
            onTileClicked: function (index, app) {
                if (!slot) return
                var apps = pcPage.appsOf(m)
                var a = apps[index]
                pcPage.demo = false
                if (!a) return
                var asleep = pc.st === "asleep" || pc.st === "off"
                if (asleep) pcPage.wakeThenLaunch(slot.slotIndex, a.appid, a.name)
                else pcPage.launchApp(slot.slotIndex, a.appid, a.name, a.running === true)
            }
            onAllAppsClicked: function (origin) {
                if (!slot) return
                pcPage.demo = false
                pcPage.openApps(slot.slotIndex, pc.mapToItem(pcPage, origin.x, origin.y))
            }
        }
    }
    Component {
        id: addCardComp
        ForkAddPcCard {
            id: add
            property var m: null
            property var slot: null
            focused: slot ? slot.focused : false
            settled: pcPage.settled
            revealed: pcPage.revealed
            sharedTick: pcPage.tick
            motion: pcPage.motionOn
            onAddClicked: { pcPage.demo = false; pcPage.forkAddPc() }
            onGuideClicked: Qt.openUrlExternally("https://github.com/ClassicOldSong/Apollo")
        }
    }

    // ---- the first run: no PCs known yet
    Loader {
        id: firstRun
        anchors.fill: parent
        active: pcPage.showFirstRun
        sourceComponent: ForkFirstRun {
            discovering: !!StreamingPreferences.enableMdns
        }
    }

    // ---- the ... menu: placed against the focused card, with a catcher that only closes it
    Item {
        id: menuLayer
        anchors.fill: parent
        visible: pcPage.menuOpen && !pcPage.showFirstRun
        z: 40
        onVisibleChanged: if (visible) { menu.forceActiveFocus() } else { pcPage.forceActiveFocus() }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: pcPage.menuOpen = false
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close menu")
            Accessible.onPressAction: pcPage.menuOpen = false
        }

        readonly property var geo: stage.geoOf(pcPage.idx)
        readonly property point cardTopRight: stage.mapToItem(pcPage, geo.cx + 280 * geo.s, geo.cy - 270 * geo.s)
        ForkPcMenu {
            id: menu
            z: 50
            x: Math.min(menuLayer.cardTopRight.x + 14 * pcPage.stageScale, pcPage.width - 300)
            y: menuLayer.cardTopRight.y + 36 * pcPage.stageScale
            title: { var m = pcPage.rowOf(pcPage.idx); return m ? m.name : "" }
            sections: pcPage.menuOpen ? pcPage.menuSections(pcPage.idx) : []
            onActivated: function (id) { pcPage.runAction(pcPage.idx, id) }
            onDismissed: pcPage.menuOpen = false
            scale: pcPage.stageScale
            transformOrigin: Item.TopLeft
        }
    }

    // ---- keys (carousel.md §3.11)
    property bool keyFocus: false
    Keys.onPressed: function (event) {
        if (showFirstRun || appsOpen) return
        keyFocus = true
        var grid = forkViewMode === "grid"
        if (event.matches(StandardKey.New)) {
            forkAddPc()
            event.accepted = true
        } else if (event.key === Qt.Key_Left && event.modifiers === Qt.NoModifier) {
            step(-1); event.accepted = true
        } else if (event.key === Qt.Key_Right && event.modifiers === Qt.NoModifier) {
            step(1); event.accepted = true
        } else if (event.key === Qt.Key_Up && event.modifiers === Qt.NoModifier) {
            // Up inside the grid moves a row; from the carousel or the grid's top row it goes on to the
            // window's header (before the page in the focus chain), as AppView does. Down or Escape
            // there give the page focus back.
            if (grid && idx - stage.gridCols >= 0) {
                go(idx - stage.gridCols, -1, false)
            } else {
                menuOpen = false
                keyFocus = false
                var previous = pcPage.nextItemInFocusChain(false)
                if (previous && previous !== pcPage) previous.forceActiveFocus(Qt.TabFocusReason)
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Down && grid) {
            if (idx + stage.gridCols < slotCount) go(idx + stage.gridCols, 1, false)
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            demo = false
            primaryAction(idx)
            event.accepted = true
        } else if (event.key === Qt.Key_Menu) {
            toggleMenu()
            event.accepted = true
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            if (!isAddSlot(idx)) runAction(idx, "remove")
            event.accepted = true
        } else if (event.key === Qt.Key_Escape && menuOpen) {
            menuOpen = false
            event.accepted = true
        }
    }

    // ---- the page's lifecycle
    StackView.onActivated: {
        appsOpen = false
        if (!forkSample) {
            ComputerManager.computerAddCompleted.connect(addComplete)
        }
        if (SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            forceActiveFocus()
        }
    }
    StackView.onDeactivating: {
        if (!forkSample) {
            ComputerManager.computerAddCompleted.disconnect(addComplete)
        }
    }

    function pairingComplete(error)
    {
        // On success the PIN dialog says so and offers the PC's apps
        if (error === undefined) {
            if (pairDialog.visible) {
                pairDialog.paired = true
            }
            else {
                forkToast(qsTr("Paired with %1").arg(pairDialog.pcName))
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
        // The design confirms a PC that was found
        if (success) {
            var last = showFirstRun && firstRun.item ? firstRun.item.lastAddress : addPcDialog.lastAddress
            forkToast(last !== "" ? qsTr("Found %1").arg(last) : qsTr("Found the PC"))
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

    function createModel()
    {
        var model = Qt.createQmlObject('import ComputerModel 1.0; ComputerModel {}', pcPage, '')
        model.initialize(ComputerManager)
        model.pairingCompleted.connect(pairingComplete)
        model.connectionTestCompleted.connect(testConnectionDialog.connectionTestComplete)
        return model
    }

    // Something changed a PC's color, "keep first" or name: the cards read the model again
    Connections {
        target: ForkPcPrefs
        function onChanged(uuid) { stage.itemsRevision++ }
    }

    // [fork] Customize (name, color, wake on pick, keep first)
    ForkCustomizeDialog {
        id: customizeDialog
        computerModel: pcPage.computerModel
        onSaved: stage.itemsRevision++
    }

    // [fork] Quit the running app (the card's Quit button and the menu's), in the All apps alert
    ForkLibraryDialog {
        id: quitDialog
        property int pcIndex: -1
        property string pcName: ""
        property string pcUuid: ""
        title: qsTr("Quit %1?").arg(appName)
        body: qsTr("It closes on %1. Anything you haven’t saved is lost.").arg(pcName)
        confirmText: qsTr("Quit")
        confirmFill: "#D93A33"
        colorKey: pcPage.hueOf(pcPage.rowOf(pcIndex))
        onConfirmed: {
            var component = Qt.createComponent("QuitSegue.qml")
            var index = pcIndex
            var name = appName
            var host = pcName
            var quitDone = function (error) {
                ComputerManager.quitAppCompleted.disconnect(quitDone)
                if (error === undefined) {
                    pcPage.forkToast(qsTr("Quit %1 on %2").arg(name).arg(host))
                }
            }
            ComputerManager.quitAppCompleted.connect(quitDone)
            stackView.push(component.createObject(stackView, {
                                                      "appName": name,
                                                      "quitRunningAppFn": function () { pcPage.computerModel.quitRunningApp(index) },
                                                      "nextAppName": "",
                                                      "nextSession": null
                                                  }))
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

                ForkCanvasText {
                    id: pinText
                    anchors.centerIn: parent
                    text: pairDialog.pin
                    textFormat: Text.PlainText
                    font.family: ForkTheme.monoFamily
                    font.pixelSize: 44
                    font.weight: Font.DemiBold
                    tracking: 8.8
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

    // [fork] Sleep PC's and Shut Down PC's confirmation; it warns when an app is still running on
    // the PC, which sleeping or shutting down quits first, and, for Shut Down PC, when Wake PC may
    // not turn the PC on again (ForkHostPower)
    NavigableMessageDialog {
        id: sleepPcDialog
        property string pcUuid : ""
        property string pcName : ""
        property string mode: "sleep" // or "off": Shut Down PC
        readonly property bool off: mode === "off"
        readonly property var info: ForkHostPower.revision >= 0 && pcUuid !== "" ? ForkHostPower.status(pcUuid) : ({})
        readonly property var wake: ForkHostPower.revision >= 0 && pcUuid !== "" ? ForkHostPower.wakeStatus(pcUuid) : ({})
        readonly property string runningApp: info.reason === "app_running" ? info.app : ""
        title: off ? qsTr("Shut down %1?").arg(pcName) : qsTr("Put %1 to sleep?").arg(pcName)
        text: {
            if (!off) {
                return runningApp !== "" ? qsTr("%1 is still running on %2. Sleep quits it first; anything unsaved in it is lost.").arg(runningApp).arg(pcName)
                                         : qsTr("Wake PC wakes it again.")
            }
            var text = runningApp !== "" ? qsTr("%1 is still running on %2. Shutting down quits it first; anything unsaved in it is lost.").arg(runningApp).arg(pcName)
                                         : qsTr("Open apps on %1 are closed, and anything unsaved in them is lost. Wake PC turns it back on.").arg(pcName)
            if (wake.shutDownWarning) {
                text += "\n\n" + wake.shutDownWarning
            }
            return text
        }
        destructive: off || runningApp !== ""
        forkShowIcon: false
        standardButtons: Dialog.Yes | Dialog.No

        onAboutToShow: {
            ForkHostPower.refresh(pcUuid)
            if (standardButton(Dialog.Yes)) {
                standardButton(Dialog.Yes).text = off ? qsTr("Shut Down") : qsTr("Sleep")
            }
            if (standardButton(Dialog.No)) {
                standardButton(Dialog.No).text = qsTr("Cancel")
            }
        }

        onAccepted: {
            if (off) {
                ForkHostPower.shutDown(pcUuid, runningApp)
            }
            else {
                ForkHostPower.sleep(pcUuid, runningApp)
            }
        }
    }

    // [fork] Set Up Wake from Off
    ForkWakeSetupDialog {
        id: wakeSetupDialog
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
                placeholderText: pcPage.escapeMarkup(renamePcDialog.originalName) // [fork] was renamePcDialog.originalName
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

}
