import QtQuick 2.0
import QtQuick.Controls 2.2
import QtQuick.Window 2.2

import ForkGroupLaunch 1.0
import SdlGamepadKeyNavigation 1.0
import Session 1.0
import SystemProperties 1.0

Item {
    property Session session
    property string appName
    property string stageText : forkReconnect ? qsTr("Reconnecting to %1...").arg(appName) : // [fork]
                                isResume ? qsTr("Resuming %1...").arg(appName) :
                                           qsTr("Starting %1...").arg(appName)
    property bool isResume : false
    property bool quitAfter : false
    property string hostName: "" // [fork] for the launch screen; AppView sets it
    property var summary: [] // [fork] the launch screen's chips (AppView.forkStreamSummary)
    property bool forkStreamed: false // [fork] the stream began, so ending it earns a toast
    property bool forkQuitting: false // [fork] the host app is being quit after the stream
    property bool forkReconnect: false // [fork] this stream follows a reconnect from the notch bar
    property bool forkReconnecting: false // [fork] the stream ends to reconnect (Session.forkReconnectStarting)

    function stageStarting(stage)
    {
        // Update the spinner text
        stageText = qsTr("Starting %1...").arg(stage)
        launchPanel.stagesDone++ // [fork]
    }

    function stageFailed(stage, errorCode, failingPorts)
    {
        // Display the error dialog after Session::exec() returns
        streamSegueErrorDialog.text = qsTr("Starting %1 failed: Error %2").arg(stage).arg(errorCode)

        if (failingPorts) {
            streamSegueErrorDialog.text += "\n\n" + qsTr("Check your firewall and port forwarding rules for port(s): %1").arg(failingPorts)
        }
    }

    function connectionStarted()
    {
        // Hide the UI contents so the user doesn't
        // see them briefly when we pop off the StackView
        launchPanel.connected = true // [fork] the last of the launch screen's steps
        forkStreamed = true // [fork]
        launchPanel.visible = false // [fork] was the spinner, stage label and hint

        // Hide the window now that streaming has begun
        window.visible = false
    }

    function displayLaunchError(text)
    {
        // Display the error dialog after Session::exec() returns
        streamSegueErrorDialog.text = text
        console.error(text)
    }

    function quitStarting()
    {
        forkQuitting = true // [fork]

        // Avoid the push transition animation
        var component = Qt.createComponent("QuitSegue.qml")
        stackView.replace(stackView.currentItem, component.createObject(stackView, {"appName": appName}), StackView.Immediate)

        // Show the Qt window again to show quit segue
        window.visible = true
    }

    function sessionFinished(portTestResult)
    {
        if (portTestResult !== 0 && portTestResult !== -1 && streamSegueErrorDialog.text) {
            streamSegueErrorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking Moonlight. Streaming over the Internet may not work while connected to this network.")
        }

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()

        // Pop the StreamSegue off the stack if this is a GUI-based app launch
        if (!quitAfter) {
            stackView.pop()
        }

        if (quitAfter && !streamSegueErrorDialog.text) {
            // If this was a CLI launch without errors, exit now
            Qt.quit()
        }
        else {
            // Show the Qt window again after streaming
            window.visible = true

            // Display any launch errors. We do this after
            // the Qt UI is visible again to prevent losing
            // focus on the dialog which would impact gamepad
            // users.
            if (streamSegueErrorDialog.text) {
                streamSegueErrorDialog.quitAfter = quitAfter
                streamSegueErrorDialog.open()
            }
        }

        // [fork] The design says what became of the app when a stream ends cleanly
        if (forkStreamed && !quitAfter && !streamSegueErrorDialog.text) {
            var pc = hostName !== "" ? hostName : qsTr("your PC")
            window.forkToast(forkQuitting ? qsTr("Stream ended. %1 quit on %2.").arg(appName).arg(pc)
                                          : qsTr("Stream ended. %1 is still running on %2.").arg(appName).arg(pc))
        }
    }

    // [fork] The stream ends to reconnect from the notch bar: "Reconnecting" until the next one starts
    function forkReconnectStarting()
    {
        forkReconnecting = true
        stageText = qsTr("Reconnecting to %1...").arg(appName)
        summary = [] // the old settings', which the next stream may not have
        launchPanel.reconnect = true
        launchPanel.connected = false
        launchPanel.stagesDone = 0
        launchPanel.visible = true

        // Show the Qt window again while the old stream goes and the next one connects
        window.visible = true
    }

    function sessionReadyForDeletion()
    {
        // [fork] Reconnecting: the next stream, with what changed, takes this one's place, as
        // QuitSegue starts the next app once the old one quit
        var forkNext = forkReconnecting ? session.forkCreateReconnectSession() : null

        // Garbage collect the Session object since it's pretty heavyweight
        // and keeps other libraries (like SDL_TTF) around until it is deleted.
        session = null
        gc()

        if (forkReconnecting) { // [fork]
            if (forkNext !== null) {
                var component = Qt.createComponent("StreamSegue.qml")
                var segue = component.createObject(stackView, {"appName": appName, "session": forkNext, "hostName": hostName,
                                                               "quitAfter": quitAfter, "forkReconnect": true})
                stackView.replace(stackView.currentItem, segue, StackView.Immediate)
            }
            else {
                // Nothing to reconnect with: as if the stream had ended
                sessionFinished(0)
            }
        }
    }

    StackView.onDeactivating: {
        // Show the toolbar again when popped off the stack
        toolBar.visible = true

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()
    }

    StackView.onActivated: {
        // Hide the toolbar before we start loading
        toolBar.visible = false

        // Hook up our signals
        session.stageStarting.connect(stageStarting)
        session.stageFailed.connect(stageFailed)
        session.connectionStarted.connect(connectionStarted)
        session.displayLaunchError.connect(displayLaunchError)
        session.quitStarting.connect(quitStarting)
        session.sessionFinished.connect(sessionFinished)
        session.forkReconnectStarting.connect(forkReconnectStarting) // [fork]
        session.readyForDeletion.connect(sessionReadyForDeletion)

        // [fork] A multi-display stream's displays, for the launch screen
        ForkGroupLaunch.refresh()

        // Ensure the SystemProperties async thread is finished,
        // since it may currently be using the SDL video subsystem
        SystemProperties.waitForAsyncLoad()

        // Kick off the stream
        streamLoader.active = true
    }

    // [fork] A multi-display stream with DisplayExtend's display times the iMac's two routes first
    // (ForkGroupLaunch); the stream starts once the launch screen shows which one it takes
    function forkStartSession() {
        if (ForkGroupLaunch.active && ForkGroupLaunch.checkNeeded && !ForkGroupLaunch.decided) {
            ForkGroupLaunch.startCheck()
        }
        else {
            startSessionTimer.start()
        }
    }

    Connections {
        target: ForkGroupLaunch
        function onCheckFinished() {
            startSessionTimer.start()
        }
    }

    Timer {
        id: startSessionTimer
        onTriggered: {
            // Garbage collect QML stuff before we start streaming,
            // since we'll probably be streaming for a while and we
            // won't be able to GC during the stream.
            gc()

            // Run the streaming session to completion
            session.start()
        }
    }

    Loader {
        id: streamLoader
        active: false
        asynchronous: true

        onLoaded: {
            // Set the hint text. We do this here rather than
            // in the hintText control itself to synchronize
            // with Session.exec() which requires no concurrent
            // gamepad usage.
            launchPanel.gamepad = SdlGamepadKeyNavigation.getConnectedGamepads() > 0 // [fork] was hintText's tip

            // Stop GUI gamepad usage now
            SdlGamepadKeyNavigation.disable()

            // Initialize the session and probe for host/client capabilities
            if (!session.initialize(window)) {
                sessionFinished(0);
                sessionReadyForDeletion();
                return;
            }

            // This spinner is shown only after session.initialize() has completed
            // to prevent active animations from running during decoder probing,
            // which causes re-entrant event loop livelocks with libdecor-gtk.
            launchPanel.started = true // [fork] was stageSpinner.visible = true

            // Don't wait unless we have toasts to display
            startSessionTimer.interval = 0

            // Display the toasts together in a vertical centered arrangement
            var yOffset = 0
            for (var i = 0; i < session.launchWarnings.length; i++) {
                var text = session.launchWarnings[i]
                console.warn(text)

                // Show the tooltip for 3 seconds
                var toast = Qt.createQmlObject('import QtQuick.Controls 2.2; ToolTip {}', parent, '')
                toast.timeout = 3000
                toast.text = text
                toast.y += yOffset
                toast.visible = true

                // Offset the next toast below the previous one
                yOffset = toast.y + toast.padding + toast.height

                // Allow an extra 500 ms for the tooltip's fade-out animation to finish
                startSessionTimer.interval = toast.timeout + 500;
            }

            // Start the timer to wait for toasts (or start the session immediately)
            forkStartSession() // [fork] was startSessionTimer.start()
        }

        sourceComponent: Item {}
    }

    // [fork] The redesign's launch screen, in place of upstream's spinner, stage label and hint
    ForkLaunchPanel {
        id: launchPanel
        appName: parent.appName
        hostName: parent.hostName
        isResume: parent.isResume
        reconnect: parent.forkReconnect
        stageText: parent.stageText
        summary: parent.summary
    }
}
