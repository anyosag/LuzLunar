import QtQuick

import ForkPcPrefs
import ComputerManager

// [fork] "Picking an app wakes it first": wakes a sleeping or shut-down PC, waits until it is online
// and paired, then starts the app the way a normal launch does. Used by the All apps page of an
// asleep PC (AppView) and by the Your PCs cards (PcView). Make one where it's needed and call
// start(); only one wake-launch runs per object, and a new start() replaces the old one.
//
//   ForkWakeLaunch { id: wakeLaunch }
//   wakeLaunch.start(computerModel, row, appId, appName)
//
// computerModel is the ComputerModel (wakeComputer(row), forkIndexOf(uuid), createSessionForApp(row,
// appId)). The helper reads the PC's name, uuid, online and paired through the model's role numbers
// (Qt::UserRole + 0, 1, 2, 9) or, for a ListModel stand-in, get(row). With Wake it when I pick an app
// off, it doesn't wake: it toasts and stops. Once the PC answers it finds the app again by NAME in the
// refreshed app list (Apollo can change an app's id), for up to 6 s, and falls back to the id it was
// given. After 3 minutes it gives up with "<PC> didn't wake up".
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
    property int forkTries: 0

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

    // The id the PC gives this app now (0 when its list doesn't have it, or can't be read)
    function idByName(row, name) {
        var id = 0
        var apps = null
        try {
            apps = Qt.createQmlObject('import AppModel; AppModel {}', launch, "")
            apps.initialize(ComputerManager, row, true)
            var count = apps.rowCount()
            for (var i = 0; i < count && id === 0; i++) {
                var item = apps.get ? apps.get(i) : null
                var rowName = item ? item.name : apps.data(apps.index(i, 0), 256) // AppModel.NameRole
                if (rowName === name) {
                    id = item ? item.appid : apps.data(apps.index(i, 0), 260) // AppModel.AppIdRole
                }
            }
        }
        catch (e) {
            id = 0
        }
        if (apps) {
            apps.destroy()
        }
        return id
    }

    function start(computerModel, row, appId, appName) {
        stop()
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
        forkTries = 0
        forkWatching = true
        say(qsTr("Waking %1, then starting %2…").arg(name).arg(appName))
        computerModel.wakeComputer(row)
        giveUp.restart()
        poll.restart()
    }

    function stop() {
        forkWatching = false
        giveUp.stop()
        poll.stop()
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
        // Its apps are read again as it wakes: find this one by name, for a few polls, else use the old id
        var found = idByName(row, forkAppName)
        if (found === 0 && forkTries < 6) {
            forkTries++
            return
        }
        var model = forkModel
        var appId = found !== 0 ? found : forkAppId
        var appName = forkAppName
        var pcName = forkPcName
        stop()
        var session = model.createSessionForApp(row, appId)
        if (!session) {
            return
        }
        var component = Qt.createComponent("StreamSegue.qml")
        var segue = component.createObject(stackView, {
                                               "appName": appName,
                                               "session": session,
                                               "isResume": false,
                                               "hostName": pcName,
                                               "summary": launch.summaryFor(appName)
                                           })
        stackView.push(segue)
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
