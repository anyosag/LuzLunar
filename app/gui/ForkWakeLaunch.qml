import QtQuick

import ForkPcPrefs

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
// off, it doesn't wake: it toasts and stops. After 3 minutes it gives up with "<PC> didn't wake up".
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
        var model = forkModel
        var appId = forkAppId
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
