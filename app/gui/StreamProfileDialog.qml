import QtQuick
import QtQuick.Controls
import QtQuick.Window

import AspectRatios 1.0
import ClientHardware 1.0
import ComputerManager 1.0
import ForkTheme 1.0
import StreamingPreferences 1.0
import StreamProfiles 1.0

// Per-app stream settings, opened from an app's "Stream Settings..." menu item: three preset
// cards (Office, Gaming, Custom), then the settings in sections like Settings' own. A row on
// Global follows the global setting; a row set for this app is marked in gold, with a button
// that puts it back on Global. The content scrolls between a pinned title and footer.
NavigableDialog {
    id: streamProfileDialog

    property string hostUuid
    property string appName
    // The current choices by profile key; a missing key uses the global setting
    property var selection: ({})
    property var fields: []
    // The choices the Custom card brings back: the last ones that weren't a preset
    property var customSelection: ({})

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

    // The sections and the rows in each, by profile key
    readonly property var sections: [
        { "title": qsTr("Picture"), "keys": ["aspectRatio", "resolution", "fps", "enableHdr"] },
        { "title": qsTr("Video"), "keys": ["videoCodecConfig", "enableYUV444", "bitrateKbps"] },
        { "title": qsTr("Window"), "keys": ["fullscreenStretch", "enableVsync", "framePacing"],
          "help": qsTr("Fullscreen fill only applies in fullscreen, and frame pacing only with V-Sync on.") },
        { "title": qsTr("Mouse & trackpad"), "keys": ["absoluteMouseMode", "trackpadPassthrough"] }
    ]

    // The card that's selected: "office" or "gaming" while the choices are exactly that preset,
    // else "custom", so changing any row picks Custom
    readonly property string preset: presetOf(selection)
    // The rows set for this app
    readonly property int overrideCount: Object.keys(selection).length

    // True when a profile has every setting of a preset and nothing else (the aspect ratio row
    // only picks sizes, and isn't saved)
    function matchesPreset(profile, preset) {
        var keys = Object.keys(profile).filter(function(key) { return key !== "aspectRatio" })
        if (keys.length !== Object.keys(preset).length) {
            return false
        }
        for (var key in preset) {
            if (profile[key] !== preset[key]) {
                return false
            }
        }
        return true
    }

    function presetOf(profile) {
        return matchesPreset(profile, officePreset) ? "office" : matchesPreset(profile, gamingPreset) ? "gaming" : "custom"
    }

    // [fork] The name a saved profile goes by on the app tiles, the banner and the launch screen:
    // Office or Gaming where it's exactly that preset, else Custom, like the dialog's cards
    function profileName(profile) {
        var name = presetOf(profile)
        return name === "office" ? qsTr("Office profile") : name === "gaming" ? qsTr("Gaming profile") : qsTr("Custom profile")
    }

    // The width and height the stream will use: the profile's where it sets a resolution, else the global one
    readonly property var effectiveSize: selection.resolution !== undefined ? selection.resolution.split("x").map(Number)
                                                                            : [StreamingPreferences.width, StreamingPreferences.height]

    title: qsTr("Stream settings for %1").arg(appName)

    // At most 620 wide, and never taller than the window: the content scrolls instead
    width: Math.min(620, (Overlay.overlay ? Overlay.overlay.width : 660) - 32)
    height: Math.min(implicitHeight, (Overlay.overlay ? Overlay.overlay.height : implicitHeight + 48) - 48)
    // The title and footer draw their own space above and below the content
    topPadding: 0
    bottomPadding: 0

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
        customSelection = presetOf(loaded) === "custom" ? loaded : {}
        fields = buildFields()
        scroller.contentY = 0
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

    // The field of a profile key
    function fieldFor(key) {
        for (var i = 0; i < fields.length; i++) {
            if (fields[i].key === key) {
                return fields[i]
            }
        }
        return null
    }

    // Every change of the choices goes through here, so the Custom card can bring back the last
    // choices that weren't a preset
    function choose(updated) {
        selection = updated
        if (presetOf(updated) === "custom") {
            customSelection = updated
        }
    }

    // A row's choice; null puts it back on Global
    function chooseValue(key, value) {
        var updated = Object.assign({}, selection)
        if (value === null) {
            delete updated[key]
            // The aspect ratio row only picks sizes, so it follows the resolution back to Global
            if (key === "resolution") {
                delete updated.aspectRatio
            }
        }
        else {
            updated[key] = value
        }
        choose(updated)

        if (key === "aspectRatio") {
            ratioChosen()
        }
        else {
            if (key === "resolution" && value === null) {
                updateSizeChoices()
            }
            refresh()
        }
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

        choose(updated)
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

        choose(Object.assign({}, selection, { "resolution": width + "x" + height, "aspectRatio": key }))
        ratioChoices = ratioOptions()
        resolutionChoices = resolutionOptions()
        refresh()
    }

    // The ratio and resolution rows list the sizes of the ratio the stream will use
    function updateSizeChoices() {
        customRatio = effectiveSize[1] > 0 ? effectiveSize[0] / effectiveSize[1] : 0
        ratioChoices = ratioOptions()
        resolutionChoices = resolutionOptions()
    }

    // The rows' fields. "current" is the global setting, shown on rows left on Global; an option's
    // "short" text is shown in the row when the list's text is longer.
    function buildFields() {
        updateSizeChoices()

        return [
            { "key": "aspectRatio", "label": qsTr("Aspect ratio"),
              "current": AspectRatios.ratioLabel(StreamingPreferences.width, StreamingPreferences.height), "options": [] },
            { "key": "resolution", "label": qsTr("Resolution"), "current": StreamingPreferences.width + " × " + StreamingPreferences.height,
              "options": [] },
            { "key": "fps", "label": qsTr("Frame rate"), "current": StreamingPreferences.fps + " FPS",
              "options": [30, 60, 90, 120].map(function(fps) { return { "text": fps + " FPS", "value": fps } }) },
            { "key": "enableHdr", "label": qsTr("HDR"), "current": onOff(StreamingPreferences.enableHdr), "options": onOffOptions() },
            { "key": "videoCodecConfig", "label": qsTr("Video codec"), "current": codecName(StreamingPreferences.videoCodecConfig),
              "options": [ { "text": qsTr("Automatic"), "value": StreamingPreferences.VCC_AUTO },
                           { "text": "H.264", "value": StreamingPreferences.VCC_FORCE_H264 },
                           { "text": "HEVC", "value": StreamingPreferences.VCC_FORCE_HEVC },
                           { "text": "AV1", "value": StreamingPreferences.VCC_FORCE_AV1 } ] },
            { "key": "enableYUV444", "label": qsTr("Full color (YUV 4:4:4)"), "current": onOff(StreamingPreferences.enableYUV444),
              "options": onOffOptions() },
            { "key": "bitrateKbps", "label": qsTr("Bitrate"), "current": (StreamingPreferences.bitrateKbps / 1000) + " Mbps",
              "options": [10, 20, 30, 40, 50, 60, 80, 100, 150].map(function(mbps) { return { "text": mbps + " Mbps", "value": mbps * 1000 } }) },
            { "key": "fullscreenStretch", "label": qsTr("Fullscreen fill"),
              "current": StreamingPreferences.fullscreenStretch ? qsTr("Stretch") : qsTr("Fit"),
              "options": [ { "text": qsTr("Fit (black bars)"), "short": qsTr("Fit"), "value": false },
                           { "text": qsTr("Stretch"), "value": true } ] },
            { "key": "enableVsync", "label": qsTr("V-Sync"), "current": onOff(StreamingPreferences.enableVsync), "options": onOffOptions() },
            { "key": "framePacing", "label": qsTr("Frame pacing"), "current": onOff(StreamingPreferences.framePacing), "options": onOffOptions() },
            { "key": "absoluteMouseMode", "label": qsTr("Mouse"),
              "current": StreamingPreferences.absoluteMouseMode ? qsTr("Remote desktop") : qsTr("Games"),
              "options": [ { "text": qsTr("Remote desktop (cursor not captured)"), "short": qsTr("Remote desktop"), "value": true },
                           { "text": qsTr("Games (cursor captured)"), "short": qsTr("Games"), "value": false } ] },
            { "key": "trackpadPassthrough", "label": qsTr("Trackpad"),
              "current": StreamingPreferences.trackpadPassthrough ? qsTr("Windows touchpad") : qsTr("Mac mouse"),
              "options": [ { "text": qsTr("Windows touchpad (gestures go to Windows)"), "short": qsTr("Windows touchpad"), "value": true },
                           { "text": qsTr("Mac mouse"), "value": false } ] }
        ]
    }

    // Shows the current selection in every row's list
    function refresh() {
        for (var s = 0; s < sectionRepeater.count; s++) {
            var section = sectionRepeater.itemAt(s)
            for (var r = 0; section && r < section.rows.count; r++) {
                var row = section.rows.itemAt(r)
                var key = row.field.key
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
    }

    // A preset card: exactly the preset's settings, and the rest on Global
    function applyPreset(preset) {
        selection = Object.assign({}, preset)
        updateSizeChoices()
        refresh()
    }

    // The Custom card: back to the last choices that weren't a preset
    function applyCustom() {
        if (preset !== "custom") {
            selection = Object.assign({}, customSelection)
            updateSizeChoices()
            refresh()
        }
    }

    function resetAll() {
        choose({})
        updateSizeChoices()
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

    // The title, and how many rows are set for this app. A line under it shows once the content
    // has scrolled under it.
    header: Item {
        implicitHeight: headerColumn.implicitHeight + 24 + 6

        Column {
            id: headerColumn
            x: 24
            y: 24
            width: parent.width - 48
            spacing: 4

            Text {
                width: parent.width
                text: streamProfileDialog.title
                textFormat: Text.PlainText // a title can hold an app name from the host
                font.family: ForkTheme.uiFamily
                font.pixelSize: 24
                font.bold: true
                font.letterSpacing: -0.24
                color: ForkTheme.text
                elide: Text.ElideRight
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            ForkText {
                width: parent.width
                kind: "help"
                font.pixelSize: 13
                text: streamProfileDialog.overrideCount === 0
                      ? qsTr("Every setting follows Settings. Change one below to set it for this app only.")
                      : streamProfileDialog.overrideCount === 1
                        ? qsTr("1 setting is set for this app. The rest follow Settings.")
                        : qsTr("%1 settings are set for this app. The rest follow Settings.").arg(streamProfileDialog.overrideCount)
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            visible: scroller.contentY > 1
            color: ForkTheme.lineSoft
        }
    }

    // Reset all on the left, away from the presets; Cancel and Save on the right
    footer: Item {
        implicitHeight: footerButtons.implicitHeight + 16 + 24

        Rectangle {
            width: parent.width
            height: 1
            color: ForkTheme.lineSoft
        }

        ForkButton {
            anchors.left: parent.left
            anchors.leftMargin: 22 // the link's own 2 of padding lines its text up with the content
            anchors.verticalCenter: footerButtons.verticalCenter
            visible: streamProfileDialog.overrideCount > 0
            kind: "link"
            text: qsTr("Reset all to Global")
            onClicked: streamProfileDialog.resetAll()
            Keys.onReturnPressed: clicked()
            Keys.onEnterPressed: clicked()

            ToolTip.text: qsTr("Clears this app's settings, so every row follows Settings")
            ToolTip.delay: 1000
            ToolTip.visible: hovered
        }

        Row {
            id: footerButtons
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            spacing: 8

            ForkButton {
                text: qsTr("Cancel")
                implicitWidth: Math.max(88, implicitContentWidth + leftPadding + rightPadding)
                onClicked: streamProfileDialog.reject()
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
            }

            ForkButton {
                kind: "primary"
                text: qsTr("Save")
                implicitWidth: Math.max(88, implicitContentWidth + leftPadding + rightPadding)
                onClicked: streamProfileDialog.accept()
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
            }
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

    Flickable {
        id: scroller
        // The screenshot harness finds the open dialog by this name
        objectName: "streamProfileScroller"
        readonly property var dialog: streamProfileDialog

        anchors.fill: parent
        // The dialog is as tall as all of the content, up to the window's height
        implicitHeight: contentHeight
        contentHeight: content.height + 14 + 22
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        // In the dialog's right padding, so it doesn't cover the rows' buttons
        ScrollBar.vertical: ScrollBar {
            parent: scroller.parent
            anchors.top: scroller.top
            anchors.bottom: scroller.bottom
            anchors.left: scroller.right
            anchors.leftMargin: 6
        }

        // Keeps the focused control in view for the keyboard and gamepads, like Settings
        NumberAnimation {
            id: autoScrollAnimation
            target: scroller
            property: "contentY"
            duration: 100
        }

        Window.onActiveFocusItemChanged: {
            var item = Window.activeFocusItem
            if (!item || !scroller.contentItem) {
                return
            }

            var inside = false
            for (var parentItem = item; parentItem; parentItem = parentItem.parent) {
                if (parentItem === scroller.contentItem) {
                    inside = true
                    break
                }
            }
            if (!inside) {
                return
            }

            var pos = item.mapToItem(scroller.contentItem, 0, 0)
            var margin = scroller.height > 200 ? 40 : 0
            if (pos.y - margin < scroller.contentY) {
                autoScrollAnimation.from = scroller.contentY
                autoScrollAnimation.to = Math.max(pos.y - margin, 0)
                autoScrollAnimation.start()
            }
            else if (pos.y + item.height + margin > scroller.contentY + scroller.height) {
                autoScrollAnimation.from = scroller.contentY
                autoScrollAnimation.to = Math.min(pos.y + item.height + margin - scroller.height,
                                                  Math.max(0, scroller.contentHeight - scroller.height))
                autoScrollAnimation.start()
            }
        }

        Column {
            id: content
            y: 14
            width: scroller.width
            spacing: 22

            // ---- Presets ------------------------------------------------------------------

            Column {
                width: parent.width
                spacing: 10

                ForkText {
                    kind: "eyebrow"
                    text: qsTr("Profile")
                    Accessible.role: Accessible.Heading
                }

                Row {
                    id: presetRow
                    width: parent.width
                    spacing: 10

                    readonly property real cardWidth: (width - 2 * spacing) / 3

                    // The tallest card, so the cards are all as tall as it
                    readonly property real tallest: Math.max(officeCard.implicitHeight, gamingCard.implicitHeight, customCard.implicitHeight)

                    ForkOptionCard {
                        id: officeCard
                        width: presetRow.cardWidth
                        height: presetRow.tallest
                        horizontal: true
                        title: qsTr("Office")
                        subtitle: qsTr("Sharp text, desktop mouse")
                        selected: streamProfileDialog.preset === "office"
                        onClicked: streamProfileDialog.applyPreset(streamProfileDialog.officePreset)
                        Keys.onReturnPressed: clicked()
                        Keys.onEnterPressed: clicked()
                        Accessible.description: ToolTip.text

                        ToolTip.text: qsTr("HEVC with YUV 4:4:4 for sharp text, remote desktop mouse, V-Sync and frame pacing. Everything else follows Settings.")
                        ToolTip.delay: 1000
                        ToolTip.visible: hovered

                        ForkSymbol {
                            symbol: "desktopcomputer"
                            size: 20
                            color: officeCard.selected ? ForkTheme.accentInk : ForkTheme.muted
                        }
                    }

                    ForkOptionCard {
                        id: gamingCard
                        width: presetRow.cardWidth
                        height: presetRow.tallest
                        horizontal: true
                        title: qsTr("Gaming")
                        subtitle: qsTr("AV1 HDR, captured mouse")
                        selected: streamProfileDialog.preset === "gaming"
                        onClicked: streamProfileDialog.applyPreset(streamProfileDialog.gamingPreset)
                        Keys.onReturnPressed: clicked()
                        Keys.onEnterPressed: clicked()
                        Accessible.description: ToolTip.text

                        ToolTip.text: qsTr("AV1 with HDR, captured mouse, no frame pacing. Everything else follows Settings.")
                        ToolTip.delay: 1000
                        ToolTip.visible: hovered

                        ForkSymbol {
                            symbol: "gamecontroller"
                            size: 20
                            color: gamingCard.selected ? ForkTheme.accentInk : ForkTheme.muted
                        }
                    }

                    ForkOptionCard {
                        id: customCard
                        width: presetRow.cardWidth
                        height: presetRow.tallest
                        horizontal: true
                        title: qsTr("Custom")
                        subtitle: qsTr("Your own choices below")
                        selected: streamProfileDialog.preset === "custom"
                        onClicked: streamProfileDialog.applyCustom()
                        Keys.onReturnPressed: clicked()
                        Keys.onEnterPressed: clicked()
                        Accessible.description: ToolTip.text

                        ToolTip.text: qsTr("Picked when you change any setting below. Choosing it again brings back your own choices from before a preset.")
                        ToolTip.delay: 1000
                        ToolTip.visible: hovered

                        ForkSymbol {
                            symbol: "slider.horizontal.3"
                            size: 20
                            color: customCard.selected ? ForkTheme.accentInk : ForkTheme.muted
                        }
                    }
                }

                // What this Mac can't handle in these settings: the profile's choices, and the global
                // setting for rows left on Global
                ForkWarnBox {
                    width: parent.width
                    warnings: {
                        // Read so the warnings are checked again when the displays change
                        ClientHardware.displays
                        var choices = streamProfileDialog.selection
                        return ClientHardware.warningsFor(streamProfileDialog.effectiveSize[0], streamProfileDialog.effectiveSize[1],
                                                          choices.fps !== undefined ? choices.fps : StreamingPreferences.fps,
                                                          choices.videoCodecConfig !== undefined ? choices.videoCodecConfig
                                                                                                 : StreamingPreferences.videoCodecConfig,
                                                          choices.enableHdr !== undefined ? choices.enableHdr : StreamingPreferences.enableHdr)
                    }
                }
            }

            // ---- Settings -----------------------------------------------------------------

            Repeater {
                id: sectionRepeater
                model: streamProfileDialog.sections

                delegate: Column {
                    id: sectionColumn
                    required property var modelData
                    required property int index

                    // The section's rows, for refresh()
                    property alias rows: rowRepeater

                    width: content.width
                    spacing: 10

                    ForkText {
                        kind: "eyebrow"
                        text: sectionColumn.modelData.title
                        Accessible.role: Accessible.Heading
                    }

                    Rectangle {
                        width: parent.width
                        height: rowColumn.height
                        radius: ForkTheme.radiusTile
                        color: ForkTheme.bar
                        border.color: ForkTheme.lineSoft

                        Column {
                            id: rowColumn
                            width: parent.width

                            Repeater {
                                id: rowRepeater
                                model: sectionColumn.modelData.keys.map(function(key) { return streamProfileDialog.fieldFor(key) })
                                                                   .filter(function(field) { return field !== null })

                                delegate: Item {
                                    id: fieldRow
                                    required property var modelData
                                    required property int index

                                    readonly property var field: modelData
                                    property alias comboBox: fieldComboBox
                                    readonly property var choices: [ { "text": qsTr("Global (%1)").arg(modelData.current), "value": null } ]
                                                                   .concat(streamProfileDialog.optionsFor(modelData))
                                    readonly property bool overridden: streamProfileDialog.selection[modelData.key] !== undefined

                                    // What the row shows: the chosen option's (short) text, or the global setting
                                    readonly property string shownText: {
                                        var value = streamProfileDialog.selection[modelData.key]
                                        if (value === undefined) {
                                            return modelData.current
                                        }
                                        for (var i = 1; i < choices.length; i++) {
                                            if (choices[i].value === value) {
                                                return choices[i].short !== undefined ? choices[i].short : choices[i].text
                                            }
                                        }
                                        return String(value)
                                    }

                                    width: rowColumn.width
                                    height: 52

                                    // The line between rows
                                    Rectangle {
                                        visible: fieldRow.index > 0
                                        x: 16
                                        width: parent.width - 16
                                        height: 1
                                        color: ForkTheme.lineSoft
                                    }

                                    // A row set for this app has a gold dot before its name
                                    Rectangle {
                                        visible: fieldRow.overridden
                                        x: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: ForkTheme.accentInk
                                    }

                                    ForkText {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 28
                                        anchors.right: fieldComboBox.left
                                        anchors.rightMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        kind: "label"
                                        font.pixelSize: 14
                                        elide: Text.ElideRight
                                        text: fieldRow.modelData.label
                                    }

                                    AutoResizingComboBox {
                                        id: fieldComboBox
                                        anchors.right: resetButton.left
                                        anchors.rightMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        // Every row's list is as wide, so they line up
                                        width: 232
                                        height: 38
                                        textRole: "text"
                                        model: fieldRow.choices
                                        // The open list is as wide as its longest item (refresh() measures
                                        // them), growing to the left over the row's name
                                        popup.width: Math.max(width, textWidth + 52)
                                        popup.x: width - popup.width
                                        Accessible.name: fieldRow.modelData.label
                                        Accessible.description: fieldRow.overridden ? qsTr("Set for this app") : qsTr("Follows Settings")

                                        // A row on Global shows the global setting in muted text with a
                                        // Global tag; a row set for this app shows its choice in a gold edge
                                        background: Rectangle {
                                            radius: 10
                                            color: fieldComboBox.down ? ForkTheme.lineSoft
                                                 : fieldComboBox.hovered ? ForkTheme.raised
                                                 : fieldRow.overridden ? ForkTheme.sel : ForkTheme.surface
                                            border.width: 1
                                            border.color: fieldRow.overridden ? ForkTheme.selEdge : ForkTheme.line

                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                visible: fieldComboBox.visualFocus
                                                radius: 14
                                                color: "transparent"
                                                border.width: 2
                                                border.color: ForkTheme.selEdge
                                            }
                                        }

                                        contentItem: Item {
                                            Text {
                                                anchors.left: parent.left
                                                anchors.right: globalTag.visible ? globalTag.left : parent.right
                                                anchors.rightMargin: globalTag.visible ? 8 : 0
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: fieldRow.shownText
                                                textFormat: Text.PlainText
                                                font: fieldComboBox.font
                                                color: fieldRow.overridden ? ForkTheme.text : ForkTheme.muted
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                id: globalTag
                                                visible: !fieldRow.overridden
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: globalText.implicitWidth + 12
                                                height: 20
                                                radius: 6
                                                color: "transparent"
                                                border.color: ForkTheme.line

                                                Text {
                                                    id: globalText
                                                    anchors.centerIn: parent
                                                    text: qsTr("Global")
                                                    font.family: ForkTheme.uiFamily
                                                    font.pixelSize: 11
                                                    font.weight: Font.Medium
                                                    color: ForkTheme.faint
                                                }
                                            }
                                        }

                                        // ::onActivated must be used, as it only listens for when the index is changed by a human
                                        onActivated: (index) => {
                                            // Custom... asks for a size in its own dialog
                                            if (fieldRow.choices[index].custom) {
                                                streamProfileDialog.openCustomResolution()
                                                return
                                            }
                                            streamProfileDialog.chooseValue(fieldRow.modelData.key, fieldRow.choices[index].value)
                                        }
                                    }

                                    // Puts a row set for this app back on Global
                                    ForkButton {
                                        id: resetButton
                                        anchors.right: parent.right
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 32
                                        height: 32
                                        visible: fieldRow.overridden
                                        kind: "quiet"
                                        symbol: "arrow.uturn.backward"
                                        symbolSize: 14
                                        Accessible.description: qsTr("Back to Global for %1").arg(fieldRow.modelData.label)
                                        onClicked: streamProfileDialog.chooseValue(fieldRow.modelData.key, null)
                                        Keys.onReturnPressed: clicked()
                                        Keys.onEnterPressed: clicked()

                                        ToolTip.text: qsTr("Back to Global (%1)").arg(fieldRow.modelData.current)
                                        ToolTip.delay: 500
                                        ToolTip.visible: hovered
                                    }
                                }
                            }
                        }
                    }

                    ForkText {
                        visible: sectionColumn.modelData.help !== undefined
                        width: parent.width
                        leftPadding: 4
                        rightPadding: 4
                        kind: "help"
                        text: sectionColumn.modelData.help !== undefined ? sectionColumn.modelData.help : ""
                    }
                }
            }
        }
    }
}
