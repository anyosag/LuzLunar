import QtQuick

import ForkPreferences 1.0
import ForkTheme 1.0

// [fork] Settings › This Mac › "This Mac's camera on the PC": during a stream, the PC's "Mac Camera"
// (Apollo, Windows 11) gets this Mac's camera while an app there uses it (camera.*). The switch, the
// camera to use, and what macOS allows. macOS's answer can change in System Settings, so the card
// looks again every 2 seconds while it's shown.
ForkCard {
    id: card

    title: qsTr("This Mac's camera on the PC")
    spacing: 8

    property var devices: ForkPreferences.cameraDevices()
    property string access: ForkPreferences.cameraAccess()

    function refresh() {
        devices = ForkPreferences.cameraDevices()
        access = ForkPreferences.cameraAccess()
    }

    // The picker's entries: macOS's choice first, then each camera
    readonly property var options: {
        var list = [{ "id": "", "label": qsTr("The one macOS prefers") }]
        for (var i = 0; i < devices.length; i++) {
            list.push({ "id": devices[i].id, "label": devices[i].name })
        }
        return list
    }

    function currentIndex() {
        for (var i = 0; i < options.length; i++) {
            if (options[i].id === ForkPreferences.cameraDevice) {
                return i
            }
        }
        return 0
    }

    Timer {
        interval: 2000
        repeat: true
        running: card.visible && ForkPreferences.camera
        onTriggered: card.refresh()
    }

    Column {
        width: parent.width
        spacing: 0

        ForkSwitchRow {
            showDivider: false
            label: qsTr("Use this Mac's camera on the PC")
            help: qsTr("Apollo lists Mac Camera on the PC. While an app there uses it during a stream, it gets this Mac's camera, at the size the app asks for; the camera's green light shows when. Without a stream, Mac Camera shows a placeholder.")
            checked: ForkPreferences.camera
            onToggled: (on) => {
                ForkPreferences.camera = on
                card.refresh()
            }
        }
    }

    Column {
        visible: ForkPreferences.camera
        width: parent.width
        spacing: 14

        ForkWarnBox {
            warnings: card.access === "denied" ? [qsTr("macOS doesn't let LuzLunar use the camera. Allow it in System Settings › Privacy & Security › Camera.")] :
                      card.devices.length === 0 ? [qsTr("This Mac has no camera connected.")] : []
            okText: card.access === "allowed" ? qsTr("Ready: an app on the PC can use this Mac's camera during a stream.")
                                              : qsTr("macOS asks the first time an app on the PC opens Mac Camera.")
        }

        ForkButton {
            visible: card.access === "denied"
            symbol: "camera"
            text: qsTr("Open Camera Settings")
            onClicked: ForkPreferences.openCameraSettings()
        }

        Column {
            visible: card.devices.length > 1
            // The drop-down is at most 320 wide
            width: Math.min(320, parent.width)
            spacing: 10

            ForkText {
                kind: "label"
                font.weight: Font.DemiBold
                text: qsTr("Camera")
            }

            AutoResizingComboBox {
                width: parent.width
                model: card.options
                textRole: "label"
                currentIndex: card.currentIndex()
                Accessible.name: qsTr("Camera")
                onActivated: (index) => ForkPreferences.cameraDevice = card.options[index].id
            }
        }

        ForkTip {
            width: parent.width
            symbol: "lock.fill"
            symbolColor: ForkTheme.ok
            text: qsTr("The picture goes only to the PC you stream from, over the paired, encrypted connection, and only while an app there has Mac Camera open.")
        }
    }
}
