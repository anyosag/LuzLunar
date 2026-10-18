import QtQuick 2.9
import QtQuick.Controls 2.2

import AspectRatios 1.0
import ComputerManager 1.0
import StreamingPreferences 1.0
import StreamProfiles 1.0

// Per-app stream settings, opened from an app's "Stream Settings..." menu item.
// Every row starts with "Global", which follows the global settings.
NavigableDialog {
    id: streamProfileDialog

    property string hostUuid
    property string appName
    // The current choices by profile key; a missing key uses the global setting
    property var selection: ({})
    property var fields: []

    // The choices of the Aspect ratio and Resolution rows, which change with the ratio (the other
    // rows keep the options in their field). "aspectRatio" is only a helper for the resolution
    // list, like the synthetic "resolution" field: it isn't saved, since a profile has a width
    // and height. customRatio is the ratio of a size that isn't a standard one.
    property var ratioChoices: []
    property var resolutionChoices: []
    property real customRatio: 0

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

    // [fork] The name a saved profile goes by on the app tiles, the banner and the launch screen:
    // Office or Gaming where it has every setting of that preset, else Custom
    function profileName(profile) {
        function hasAll(preset) {
            for (var key in preset) {
                if (profile[key] !== preset[key]) {
                    return false
                }
            }
            return true
        }

        return hasAll(officePreset) ? qsTr("Office profile")
                                    : hasAll(gamingPreset) ? qsTr("Gaming profile") : qsTr("Custom profile")
    }

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
            loaded.aspectRatio = AspectRatios.keyFor(profile.width, profile.height, AspectRatios.defaultDisplay())
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

    // The aspect ratio the resolution list is for: the chosen one, else the ratio of the size the stream will use
    function effectiveRatioKey() {
        if (selection.aspectRatio !== undefined) {
            return selection.aspectRatio
        }
        return AspectRatios.keyFor(effectiveSize[0], effectiveSize[1], AspectRatios.defaultDisplay())
    }

    // The number of a ratio's key (width over height), 0 if it has none
    function ratioNumber(key) {
        if (key === "custom") {
            return customRatio
        }
        var ratios = AspectRatios.ratios(AspectRatios.defaultDisplay())
        for (var i = 0; i < ratios.length; i++) {
            if (ratios[i].key === key) {
                return ratios[i].ratio
            }
        }
        return 0
    }

    // The ratios of the aspect ratio row. Typing a ratio is left to the Custom... resolution
    // dialog, so "Custom ratio" is only there while the size has a ratio of its own.
    function ratioOptions() {
        var options = []
        var ratios = AspectRatios.ratios(AspectRatios.defaultDisplay())
        for (var i = 0; i < ratios.length; i++) {
            if (ratios[i].key !== "custom") {
                options.push({ "text": ratios[i].label, "value": ratios[i].key })
            }
        }
        if (effectiveRatioKey() === "custom") {
            options.push({ "text": qsTr("Custom (%1)").arg(AspectRatios.ratioLabel(effectiveSize[0], effectiveSize[1])), "value": "custom" })
        }
        return options
    }

    // The sizes of the chosen ratio, then a saved size that isn't one of them, then Custom...
    function resolutionOptions() {
        var options = []
        function add(text, width, height) {
            var value = width + "x" + height
            if (width > 0 && height > 0 && !options.some(function(option) { return option.value === value })) {
                options.push({ "text": text, "value": value })
            }
        }

        var key = effectiveRatioKey()
        var presets = AspectRatios.presets(key, key === "custom" ? customRatio : 0, AspectRatios.defaultDisplay())
        for (var i = 0; i < presets.length; i++) {
            add(presets[i].text, presets[i].width, presets[i].height)
        }

        // Keep a saved custom resolution selectable
        if (selection.resolution !== undefined) {
            var parts = selection.resolution.split("x")
            add(parts[0] + " × " + parts[1], parseInt(parts[0]), parseInt(parts[1]))
        }

        options.push({ "text": qsTr("Custom…"), "value": "custom", "custom": true })
        return options
    }

    // The size to pick for a ratio, as a "WxH" value: the one that fills the display, else the
    // one nearest the current size by pixel count. Empty if the ratio has no sizes.
    function fillingSize(key) {
        var presets = AspectRatios.presets(key, key === "custom" ? customRatio : 0, AspectRatios.defaultDisplay())
        var best = -1
        var bestDistance = 0
        for (var i = 0; i < presets.length; i++) {
            if (presets[i].fills) {
                best = i
                break
            }

            var distance = Math.abs(Math.log(presets[i].width * presets[i].height / (effectiveSize[0] * effectiveSize[1])))
            if (best < 0 || distance < bestDistance) {
                best = i
                bestDistance = distance
            }
        }
        return best >= 0 ? presets[best].width + "x" + presets[best].height : ""
    }

    // The options of a row; the aspect ratio and resolution rows change with the ratio
    function optionsFor(field) {
        return field.key === "aspectRatio" ? ratioChoices : field.key === "resolution" ? resolutionChoices : field.options
    }

    // A ratio was picked in the aspect ratio row: the resolution becomes the size that fills the
    // display, or follows the global one again for Global
    function ratioChosen() {
        var updated = Object.assign({}, selection)
        if (selection.aspectRatio === undefined) {
            delete updated.resolution
        }
        else if (selection.aspectRatio !== "custom") {
            var size = fillingSize(selection.aspectRatio)
            if (size !== "") {
                updated.resolution = size
            }
        }

        selection = updated
        resolutionChoices = resolutionOptions()
        refresh()
    }

    function openCustomResolution() {
        customResolutionDialog.openFor(effectiveSize[0], effectiveSize[1], ratioNumber(effectiveRatioKey()))
    }

    // A size typed in the Custom... dialog
    function useCustomResolution(width, height) {
        var key = AspectRatios.keyFor(width, height, AspectRatios.defaultDisplay())
        if (key === "custom") {
            customRatio = width / height
        }

        selection = Object.assign({}, selection, { "resolution": width + "x" + height, "aspectRatio": key })
        ratioChoices = ratioOptions()
        resolutionChoices = resolutionOptions()
        refresh()
    }

    function buildFields() {
        // The ratio and resolution rows list the sizes of the ratio the stream will use
        customRatio = effectiveSize[1] > 0 ? effectiveSize[0] / effectiveSize[1] : 0
        ratioChoices = ratioOptions()
        resolutionChoices = resolutionOptions()

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
            { "key": "aspectRatio", "label": qsTr("Aspect ratio"),
              "current": AspectRatios.ratioLabel(StreamingPreferences.width, StreamingPreferences.height), "options": [] },
            { "key": "resolution", "label": qsTr("Resolution"), "current": StreamingPreferences.width + "x" + StreamingPreferences.height,
              "options": [] },
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
        delete profile.aspectRatio
        StreamProfiles.saveProfile(hostUuid, appName, profile)

        // [fork] The design confirms what was saved
        if (Object.keys(profile).length > 0) {
            window.forkToast(qsTr("Saved %1 for %2").arg(profileName(profile).toLocaleLowerCase()).arg(appName))
        }
        else {
            window.forkToast(qsTr("%1 follows Settings again").arg(appName))
        }
    }

    // The Custom... resolution choice
    ForkCustomResolutionDialog {
        id: customResolutionDialog

        onAccepted: streamProfileDialog.useCustomResolution(chosenWidth, chosenHeight)

        // The row still shows Custom..., so show the selection again
        onClosed: Qt.callLater(function() {
            streamProfileDialog.refresh()
            streamProfileDialog.forceActiveFocus()
        })
    }

    Column {
        spacing: 8

        Row {
            spacing: 8

            ForkButton { // [fork] the redesign's buttons
                text: qsTr("Office")
                onClicked: applyPreset(officePreset)

                ToolTip.text: qsTr("HEVC with YUV 4:4:4 for sharp text, remote desktop mouse, V-Sync and frame pacing")
                ToolTip.delay: 1000
                ToolTip.visible: hovered
            }

            ForkButton {
                text: qsTr("Gaming")
                onClicked: applyPreset(gamingPreset)

                ToolTip.text: qsTr("AV1 with HDR, captured mouse, no frame pacing")
                ToolTip.delay: 1000
                ToolTip.visible: hovered
            }

            ForkButton {
                kind: "quiet"
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
                property var choices: [ { "text": qsTr("Global (%1)").arg(modelData.current), "value": null } ].concat(streamProfileDialog.optionsFor(modelData))

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
                        // Custom... asks for a size in its own dialog
                        if (choices[currentIndex].custom) {
                            streamProfileDialog.openCustomResolution()
                            return
                        }

                        var updated = Object.assign({}, streamProfileDialog.selection)
                        var value = choices[currentIndex].value
                        if (value === null) {
                            delete updated[modelData.key]
                        }
                        else {
                            updated[modelData.key] = value
                        }
                        streamProfileDialog.selection = updated

                        if (modelData.key === "aspectRatio") {
                            streamProfileDialog.ratioChosen()
                        }
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
