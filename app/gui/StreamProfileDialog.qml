import QtQuick 2.9
import QtQuick.Controls 2.2

import ComputerManager 1.0
import StreamingPreferences 1.0
import StreamProfiles 1.0
import SystemProperties 1.0

// Per-app stream settings, opened from an app's "Stream Settings..." menu item.
// Every row starts with "Global", which follows the global settings.
NavigableDialog {
    id: streamProfileDialog

    property string hostUuid
    property string appName
    // The current choices by profile key; a missing key uses the global setting
    property var selection: ({})
    property var fields: []

    readonly property var officePreset: ({
        "videoCodecConfig": StreamingPreferences.VCC_FORCE_HEVC,
        "enableYUV444": true,
        "enableHdr": false,
        "absoluteMouseMode": true,
        "enableVsync": true,
        "framePacing": true
    })
    readonly property var gamingPreset: ({
        "videoCodecConfig": StreamingPreferences.VCC_FORCE_AV1,
        "enableHdr": true,
        "enableYUV444": false,
        "absoluteMouseMode": false,
        "framePacing": false
    })

    // The width and height the stream will use: the profile's where it sets a resolution, else the global one
    readonly property var effectiveSize: selection.resolution !== undefined ? selection.resolution.split("x").map(Number)
                                                                            : [StreamingPreferences.width, StreamingPreferences.height]

    title: qsTr("Stream settings for %1").arg(appName)
    standardButtons: Dialog.Save | Dialog.Cancel

    function openFor(computerIndex, name) {
        hostUuid = StreamProfiles.hostUuid(ComputerManager, computerIndex)
        appName = name

        var profile = StreamProfiles.profile(hostUuid, appName)
        var loaded = {}
        for (var key in profile) {
            if (key !== "width" && key !== "height") {
                loaded[key] = profile[key]
            }
        }
        if (profile.width !== undefined && profile.height !== undefined) {
            loaded.resolution = profile.width + "x" + profile.height
        }

        selection = loaded
        fields = buildFields()
        open()
        refresh()
    }

    function onOff(value) {
        return value ? qsTr("On") : qsTr("Off")
    }

    function codecName(value) {
        switch (value) {
        case StreamingPreferences.VCC_FORCE_H264:
            return "H.264"
        case StreamingPreferences.VCC_FORCE_HEVC:
            return "HEVC"
        case StreamingPreferences.VCC_FORCE_AV1:
            return "AV1"
        default:
            return qsTr("Automatic")
        }
    }

    function onOffOptions() {
        return [ { "text": qsTr("On"), "value": true }, { "text": qsTr("Off"), "value": false } ]
    }

    function resolutionOptions() {
        var options = []
        function add(text, width, height) {
            var value = width + "x" + height
            if (width > 0 && height > 0 && !options.some(function(option) { return option.value === value })) {
                options.push({ "text": text ? text + " (" + value + ")" : value, "value": value })
            }
        }

        SystemProperties.refreshDisplays()
        var native = SystemProperties.getNativeResolution(0)
        var safeArea = SystemProperties.getSafeAreaResolution(0)
        add("", 1280, 720)
        add("", 1920, 1080)
        add("", 2560, 1440)
        add("", 3840, 2160)
        add(qsTr("Native"), native.width, native.height)
        add(qsTr("Native (Excluding Notch)"), safeArea.width, safeArea.height)

        // Keep a saved custom resolution selectable
        if (selection.resolution !== undefined) {
            var parts = selection.resolution.split("x")
            add("", parseInt(parts[0]), parseInt(parts[1]))
        }
        return options
    }

    function buildFields() {
        return [
            { "key": "videoCodecConfig", "label": qsTr("Video codec"), "current": codecName(StreamingPreferences.videoCodecConfig),
              "options": [ { "text": qsTr("Automatic"), "value": StreamingPreferences.VCC_AUTO },
                           { "text": "H.264", "value": StreamingPreferences.VCC_FORCE_H264 },
                           { "text": "HEVC", "value": StreamingPreferences.VCC_FORCE_HEVC },
                           { "text": "AV1", "value": StreamingPreferences.VCC_FORCE_AV1 } ] },
            { "key": "enableHdr", "label": qsTr("HDR"), "current": onOff(StreamingPreferences.enableHdr), "options": onOffOptions() },
            { "key": "enableYUV444", "label": qsTr("YUV 4:4:4"), "current": onOff(StreamingPreferences.enableYUV444), "options": onOffOptions() },
            { "key": "absoluteMouseMode", "label": qsTr("Mouse"),
              "current": StreamingPreferences.absoluteMouseMode ? qsTr("Remote desktop") : qsTr("Games"),
              "options": [ { "text": qsTr("Remote desktop (cursor not captured)"), "value": true },
                           { "text": qsTr("Games (cursor captured)"), "value": false } ] },
            { "key": "enableVsync", "label": qsTr("V-Sync"), "current": onOff(StreamingPreferences.enableVsync), "options": onOffOptions() },
            { "key": "framePacing", "label": qsTr("Frame pacing"), "current": onOff(StreamingPreferences.framePacing), "options": onOffOptions() },
            { "key": "fullscreenStretch", "label": qsTr("Fullscreen fill"),
              "current": StreamingPreferences.fullscreenStretch ? qsTr("Stretch") : qsTr("Fit"),
              "options": [ { "text": qsTr("Fit (black bars)"), "value": false },
                           { "text": qsTr("Stretch"), "value": true } ] },
            { "key": "resolution", "label": qsTr("Resolution"), "current": StreamingPreferences.width + "x" + StreamingPreferences.height,
              "options": resolutionOptions() },
            { "key": "fps", "label": qsTr("Frame rate"), "current": StreamingPreferences.fps + " FPS",
              "options": [30, 60, 90, 120].map(function(fps) { return { "text": fps + " FPS", "value": fps } }) },
            { "key": "bitrateKbps", "label": qsTr("Bitrate"), "current": (StreamingPreferences.bitrateKbps / 1000) + " Mbps",
              "options": [10, 20, 30, 40, 50, 60, 80, 100, 150].map(function(mbps) { return { "text": mbps + " Mbps", "value": mbps * 1000 } }) }
        ]
    }

    // Shows the current selection in every row
    function refresh() {
        for (var i = 0; i < fieldRepeater.count; i++) {
            var row = fieldRepeater.itemAt(i)
            var key = fields[i].key
            var index = 0
            if (selection[key] !== undefined) {
                for (var j = 1; j < row.choices.length; j++) {
                    if (row.choices[j].value === selection[key]) {
                        index = j
                        break
                    }
                }
            }
            row.comboBox.currentIndex = index
            row.comboBox.recalculateWidth()
        }
    }

    function applyPreset(preset) {
        selection = Object.assign({}, selection, preset)
        refresh()
    }

    onAccepted: {
        var profile = Object.assign({}, selection)
        if (profile.resolution !== undefined) {
            var parts = profile.resolution.split("x")
            profile.width = parseInt(parts[0])
            profile.height = parseInt(parts[1])
        }
        delete profile.resolution
        StreamProfiles.saveProfile(hostUuid, appName, profile)
    }

    Column {
        spacing: 8

        Row {
            spacing: 8

            Button {
                text: qsTr("Office")
                onClicked: applyPreset(officePreset)

                ToolTip.text: qsTr("HEVC with YUV 4:4:4 for sharp text, remote desktop mouse, V-Sync and frame pacing")
                ToolTip.delay: 1000
                ToolTip.visible: hovered
            }

            Button {
                text: qsTr("Gaming")
                onClicked: applyPreset(gamingPreset)

                ToolTip.text: qsTr("AV1 with HDR, captured mouse, no frame pacing")
                ToolTip.delay: 1000
                ToolTip.visible: hovered
            }

            Button {
                text: qsTr("Reset to Global")
                onClicked: {
                    selection = {}
                    refresh()
                }
            }
        }

        Repeater {
            id: fieldRepeater
            model: fields

            delegate: Row {
                property alias comboBox: fieldComboBox
                property var choices: [ { "text": qsTr("Global (%1)").arg(modelData.current), "value": null } ].concat(modelData.options)

                // AutoResizingComboBox limits itself to its parent's width, so the row needs a fixed one
                width: 460
                spacing: 10

                Label {
                    width: 120
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    font.pointSize: 12
                }

                AutoResizingComboBox {
                    id: fieldComboBox
                    font.pointSize: 12
                    textRole: "text"
                    model: choices

                    // ::onActivated must be used, as it only listens for when the index is changed by a human
                    onActivated: {
                        var updated = Object.assign({}, streamProfileDialog.selection)
                        var value = choices[currentIndex].value
                        if (value === null) {
                            delete updated[modelData.key]
                        }
                        else {
                            updated[modelData.key] = value
                        }
                        streamProfileDialog.selection = updated
                    }
                }
            }
        }

        Label {
            width: 420
            text: qsTr("Frame pacing only applies when V-Sync is on, and Fullscreen fill only in fullscreen. Settings left on Global follow LuzLunar's settings.")
            font.pointSize: 9
            wrapMode: Text.Wrap
        }

        // What this Mac can't handle in these settings: the profile's choices, and the global setting for rows left on Global
        ForkHardwareWarnings {
            width: 420
            streamWidth: streamProfileDialog.effectiveSize[0]
            streamHeight: streamProfileDialog.effectiveSize[1]
            streamFps: streamProfileDialog.selection.fps !== undefined ? streamProfileDialog.selection.fps : StreamingPreferences.fps
            codecConfig: streamProfileDialog.selection.videoCodecConfig !== undefined ? streamProfileDialog.selection.videoCodecConfig
                                                                                      : StreamingPreferences.videoCodecConfig
            hdr: streamProfileDialog.selection.enableHdr !== undefined ? streamProfileDialog.selection.enableHdr : StreamingPreferences.enableHdr
        }
    }
}
