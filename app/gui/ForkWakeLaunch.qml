import QtQuick

import ForkPcPrefs
import ComputerManager

// [fork] "Picking an app wakes it first": wakes a sleeping or shut-down PC, waits until it is online
// and paired, then starts the app the way a normal launch does. Used by the All apps page of an
// asleep PC (AppView) and by the Your PCs cards (PcView). Make one where it's needed and call
// start(); only one wake-launch runs per object, and a new start() replaces the old one.
//
//   ForkWakeLaunch { id: wakeLaunch }
//   wakeLaunch.start(computerModel, row, appId, appName[, summaryFor])
//
// computerModel is the ComputerModel (wakeComputer(row), forkIndexOf(uuid), createSessionForApp(row,
// appId)). The helper reads the PC's name, uuid, online and paired through the model's role numbers
// (Qt::UserRole + 0, 1, 2, 9) or, for a ListModel stand-in, get(row). With Wake it when I pick an app
// off, it doesn't wake: it toasts and stops. Once the PC answers it waits for its app list to be read again
// (up to 2.5 s: it reports online before it re-reads the apps) and finds the app again by NAME in it
// (Apollo can change an app's id), falling back to the id it was given. After 3 minutes it gives up with "<PC> didn't wake up".
QtObject {
    id: launch

    // What the page knows of the app: the launch screen's chips for it (AppView.forkStreamSummary)
    property var summaryFor: function(appName) { return [] }

    readonly property bool active: forkWatching
    property bool forkWatching: false

    property var forkModel: null
    property string forkUuid: ""
    property string forkPcName: ""
    property int forkAppId: 0
    property string forkAppName: ""
    property var forkApps: null // the PC's apps, read again once it is online
    property var forkSummaryFn: null
    property bool forkOnline: false
    property bool forkListChanged: false

    function say(text) {
        if (typeof window !== "undefined" && window && window.forkToast) {
            window.forkToast(text)
        }
    }

    // One field of a row: by role number on the real model, by name on a ListModel
    function field(model, row, role, name) {
        if (row < 0) {
            return undefined
        }
        if (model.get) {
            var item = model.get(row)
            return item ? item[name] : undefined
        }
        return model.data(model.index(row, 0), role)
    }

    function rowOfPc() {
        if (!forkModel) {
            return -1
        }
        if (forkModel.forkIndexOf) {
            return forkModel.forkIndexOf(forkUuid)
        }
        for (var i = 0; i < forkModel.count; i++) {
            if (forkModel.get(i).uuid === forkUuid) {
                return i
            }
        }
        return -1
    }

    // The id this app has in `apps` (0 when its list doesn't have it, or can't be read)
    function idByName(apps, name) {
        var count = apps.get ? apps.count : apps.rowCount()
        for (var i = 0; i < count; i++) {
            var item = apps.get ? apps.get(i) : null
            var rowName = item ? item.name : apps.data(apps.index(i, 0), 256) // AppModel.NameRole
            if (rowName === name) {
                return item ? item.appid : apps.data(apps.index(i, 0), 260) // AppModel.AppIdRole
            }
        }
        return 0
    }

    function start(computerModel, row, appId, appName, summaryFn) {
        stop()
        forkSummaryFn = summaryFn || null
        if (!computerModel || row < 0) {
            return
        }
        var uuid = field(computerModel, row, 265, "uuid")
        var name = field(computerModel, row, 256, "name") || ""
        if (!uuid) {
            return
        }
        if (!ForkPcPrefs.wakeOnPick(uuid)) {
            say(qsTr("%1 is asleep. Wake it first, or turn on Wake it when I pick an app in Customize.").arg(name))
            return
        }
        forkModel = computerModel
        forkUuid = uuid
        forkPcName = name
        forkAppId = appId
        forkAppName = appName
        forkOnline = false
        forkListChanged = false
        forkWatching = true
        say(qsTr("Waking %1, then starting %2…").arg(name).arg(appName))
        computerModel.wakeComputer(row)
        giveUp.restart()
        poll.restart()
    }

    function stop() {
        forkWatching = false
        forkOnline = false
        giveUp.stop()
        poll.stop()
        grace.stop()
        if (forkApps) {
            forkApps.destroy()
            forkApps = null
        }
    }

    // Looks at the PC's row; once it is online and paired, starts the app
    function check() {
        if (!forkWatching) {
            return
        }
        var row = rowOfPc()
        if (row < 0) {
            return
        }
        if (!field(forkModel, row, 257, "online") || !field(forkModel, row, 258, "paired")) {
            return
        }
        if (!forkOnline) {
            // Online: its apps are read again now. Wait for that (rows coming or going, or the
            // grace time if nothing changed), then find the app by name.
            forkOnline = true
            poll.stop()
            forkApps = Qt.createQmlObject('import AppModel; AppModel {}', launch, "")
            forkApps.initialize(ComputerManager, row, true)
            watchApps.target = forkApps
            grace.restart()
        }
    }

    // The app list changed after the PC came online: look for the app by name
    function listChanged() {
        if (forkWatching && forkOnline) {
            forkListChanged = true
            if (idByName(forkApps, forkAppName) !== 0) {
                Qt.callLater(launchNow)
            }
        }
    }

    // Starts the app (the id it has by now, else the one it was given)
    function launchNow() {
        if (!forkWatching || !forkOnline) {
            return
        }
        var row = rowOfPc()
        var found = forkApps ? idByName(forkApps, forkAppName) : 0
        var model = forkModel
        var appId = found !== 0 ? found : forkAppId
        var appName = forkAppName
        var pcName = forkPcName
        var summaryFn = forkSummaryFn || summaryFor
        stop()
        var session = row >= 0 ? model.createSessionForApp(row, appId) : null
        if (!session) {
            say(qsTr("Couldn’t start %1 on %2").arg(appName).arg(pcName))
            return
        }
        var component = Qt.createComponent("StreamSegue.qml")
        var segue = component.createObject(stackView, {
                                               "appName": appName,
                                               "session": session,
                                               "isResume": false,
                                               "hostName": pcName,
                                               "summary": summaryFn(appName)
                                           })
        stackView.push(segue)
    }

    property Timer grace: Timer {
        interval: 2500
        onTriggered: launch.launchNow()
    }

    property Connections watchApps: Connections {
        ignoreUnknownSignals: true
        function onRowsInserted() { launch.listChanged() }
        function onRowsRemoved() { launch.listChanged() }
        function onModelReset() { launch.listChanged() }
    }

    property Timer giveUp: Timer {
        interval: 180000
        onTriggered: {
            var name = launch.forkPcName
            launch.stop()
            launch.say(qsTr("%1 didn’t wake up").arg(name))
        }
    }

    // The model signals on every change of a PC; a slow poll covers a row that moved without one
    property Timer poll: Timer {
        interval: 1000
        repeat: true
        onTriggered: launch.check()
    }

    property Connections watch: Connections {
        target: launch.forkModel
        ignoreUnknownSignals: true
        function onDataChanged() { launch.check() }
        function onModelReset() { launch.check() }
    }
}
