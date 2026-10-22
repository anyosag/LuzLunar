import QtQuick
import QtQuick.Shapes

import AspectRatios 1.0
import ClientHardware 1.0
import ForkPreferences 1.0
import ForkTheme 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0

// [fork] Settings › Display: the stream's shape, size, frame rate and bitrate, HDR, and how a
// fullscreen stream fills the screen. The aspect ratio works as ForkAspectRatioPicker does for
// upstream's page: the chosen ratio decides which sizes are offered, and choosing one selects the
// size that fills the display. Apollo makes a virtual display at exactly the size asked for, so
// any ratio works.
Column {
    id: displaySection

    spacing: ForkTheme.gap

    // ---- Aspect ratio and size --------------------------------------------------------------

    // The display the sizes are measured against (an index into ClientHardware.displays)
    property int displayIndex: AspectRatios.defaultDisplay()

    // The ratio's key (see AspectRatios), and the number typed after "Custom ratio…"
    property string ratioKey: ""
    property real customRatio: 0

    readonly property var ratioEntries: {
        // Read so the list follows displays that come or go
        ClientHardware.displays
        return AspectRatios.ratios(displayIndex)
    }

    // The sizes of the chosen ratio. The window mode, Stretch and the notch bar decide whether a
    // stream goes below the notch, which changes the size that fills the display.
    readonly property var presets: {
        StreamingPreferences.windowMode
        StreamingPreferences.fullscreenStretch
        ForkPreferences.notchBar
        ClientHardware.displays
        return AspectRatios.presets(ratioKey, customRatio, displayIndex)
    }

    readonly property bool sizeListed: {
        for (var i = 0; i < presets.length; i++) {
            if (presets[i].width === StreamingPreferences.width && presets[i].height === StreamingPreferences.height) {
                return true
            }
        }
        return false
    }

    // The displays to pick from, built-in first
    readonly property var displayChoices: {
        var list = []
        var displays = ClientHardware.displays
        for (var i = 0; i < displays.length; i++) {
            list.push({ "value": i, "label": displays[i].name, "builtin": displays[i].isBuiltin })
        }
        list.sort(function(a, b) {
            return a.builtin !== b.builtin ? (a.builtin ? -1 : 1) : a.value - b.value
        })
        return list
    }

    // "Full display, with the notch area (1.54:1)" as a title and the part in parentheses
    // and "Full display" over "1.54:1 · with the notch area", so long names fit the card
    function splitLabel(label) {
        var title = label
        var detail = ""
        var open = label.lastIndexOf(" (")
        if (open > 0 && label.charAt(label.length - 1) === ")") {
            title = label.substring(0, open)
            detail = label.substring(open + 2, label.length - 1)
        }
        var comma = title.indexOf(", ")
        if (comma > 0) {
            detail = detail !== "" ? detail + " · " + title.substring(comma + 2) : title.substring(comma + 2)
            title = title.substring(0, comma)
        }
        return { "title": title, "detail": detail }
    }

    // What a standard ratio is for, under its name
    function ratioNote(key) {
        switch (key) {
        case "16:9": return qsTr("TVs and most games")
        case "16:10": return qsTr("Most Mac and PC laptops")
        case "21:9": return qsTr("Ultrawide")
        case "32:9": return qsTr("Super ultrawide")
        case "4:3": return qsTr("Classic")
        case "3:2": return qsTr("Surface and some laptops")
        case "5:4": return qsTr("Older monitors")
        case "1:1": return qsTr("Square")
        case "custom": return qsTr("Any width to height")
        }
        return ""
    }

    // Selects a size as if it were picked from upstream's list: the bitrate follows unless it was set by hand
    function applySize(width, height) {
        if (StreamingPreferences.width === width && StreamingPreferences.height === height) {
            return
        }
        StreamingPreferences.width = width
        StreamingPreferences.height = height
        if (StreamingPreferences.autoAdjustBitrate) {
            StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(width, height, StreamingPreferences.fps,
                                                                                      StreamingPreferences.enableYUV444)
        }
    }

    function applyFps(fps) {
        if (StreamingPreferences.fps === fps) {
            return
        }
        StreamingPreferences.fps = fps
        if (StreamingPreferences.autoAdjustBitrate) {
            StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(StreamingPreferences.width, StreamingPreferences.height,
                                                                                      fps, StreamingPreferences.enableYUV444)
        }
    }

    // Selects the size that fills the display, or the nearest by pixel count without one
    function pickFillingSize() {
        var list = presets
        if (list.length === 0) {
            return
        }
        var index = -1
        var closest = 0
        var closestDistance = -1
        for (var i = 0; i < list.length; i++) {
            if (list[i].fills && index < 0) {
                index = i
            }
            var distance = Math.abs(Math.log(list[i].width * list[i].height / (StreamingPreferences.width * StreamingPreferences.height)))
            if (closestDistance < 0 || distance < closestDistance) {
                closest = i
                closestDistance = distance
            }
        }
        if (index < 0) {
            index = closest
        }
        applySize(list[index].width, list[index].height)
    }

    function chooseRatio(key) {
        if (key === ratioKey) {
            return
        }
        ratioKey = key
        if (key === "custom") {
            // Start from the ratio of the current size; the field takes a new one
            customRatio = StreamingPreferences.width / Math.max(1, StreamingPreferences.height)
            customField.text = AspectRatios.ratioLabel(StreamingPreferences.width, StreamingPreferences.height)
            customField.invalid = false
            customField.forceActiveFocus()
            customField.selectAll()
        }
        else {
            pickFillingSize()
        }
    }

    function customRatioTyped() {
        var typed = AspectRatios.parseRatio(customField.text)
        customField.invalid = typed <= 0
        if (typed > 0 && Math.abs(typed - customRatio) > 1e-9) {
            customRatio = typed
            pickFillingSize()
        }
    }

    function syncToSaved() {
        ratioKey = AspectRatios.keyFor(StreamingPreferences.width, StreamingPreferences.height, displayIndex)
        if (ratioKey === "custom") {
            customRatio = StreamingPreferences.width / Math.max(1, StreamingPreferences.height)
            customField.text = AspectRatios.ratioLabel(StreamingPreferences.width, StreamingPreferences.height)
        }
    }

    function chooseDisplay(index) {
        displayIndex = index
        var keys = ratioEntries.map(function(entry) { return entry.key })
        if (keys.indexOf(ratioKey) < 0) {
            // This display has no such shape (the notch, say): its own shape instead
            ratioKey = "full"
        }
        pickFillingSize()
    }

    // ---- Frame rate -----------------------------------------------------------------------

    // 30 and 60, each display's refresh rate, the saved rate if it's none of those, then Custom.
    // SDL can read a ProMotion screen as 0 Hz, so macOS's highest rate for each screen counts too.
    readonly property var fpsOptions: {
        displaysLoaded
        var rates = [30, 60]
        for (var i = 0; i < 16; i++) {
            var rate = SystemProperties.getRefreshRate(i)
            if (rate > 0 && rates.indexOf(rate) < 0) {
                rates.push(rate)
            }
        }
        var displays = ClientHardware.displays
        for (var j = 0; j < displays.length; j++) {
            var maxRate = displays[j].maxRefresh
            if (maxRate > 0 && rates.indexOf(maxRate) < 0) {
                rates.push(maxRate)
            }
        }
        if (rates.indexOf(StreamingPreferences.fps) < 0) {
            rates.push(StreamingPreferences.fps)
        }
        rates.sort(function(a, b) { return a - b })
        var options = rates.map(function(rate) { return { "value": rate, "label": "" + rate } })
        options.push({ "value": "custom", "label": qsTr("Custom…") })
        return options
    }

    readonly property int maxRefresh: {
        var displays = ClientHardware.displays
        return displayIndex < displays.length ? displays[displayIndex].maxRefresh : 0
    }

    // ---- Bitrate --------------------------------------------------------------------------

    readonly property int defaultBitrate: StreamingPreferences.getDefaultBitrate(StreamingPreferences.width, StreamingPreferences.height,
                                                                               StreamingPreferences.fps, StreamingPreferences.enableYUV444)

    // ---- Fullscreen fill ------------------------------------------------------------------

    readonly property bool windowed: StreamingPreferences.windowMode === StreamingPreferences.WM_WINDOWED

    // The area a fullscreen stream fills on the first display (below the notch where there is
    // one), and the whole panel
    property size screenSize: Qt.size(0, 0)
    property size panelSize: Qt.size(0, 0)

    function refreshScreen() {
        var rect = SystemProperties.getSafeAreaResolution(0)
        if (rect.width <= 0) {
            // The display list isn't loaded yet
            SystemProperties.refreshDisplays()
            rect = SystemProperties.getSafeAreaResolution(0)
        }
        var panel = SystemProperties.getNativeResolution(0)
        if (rect.width <= 0) {
            rect = panel
        }
        screenSize = Qt.size(rect.width, rect.height)
        panelSize = Qt.size(panel.width, panel.height)
    }

    readonly property real streamRatio: StreamingPreferences.width / Math.max(1, StreamingPreferences.height)
    readonly property real screenRatio: screenSize.height > 0 ? screenSize.width / screenSize.height : 1.6

    // How a stream of this shape looks in fullscreen, as ForkStretchOption says it
    readonly property string fillNote: {
        if (windowed) {
            return qsTr("Only used in fullscreen. A windowed stream always fits.")
        }
        var name = AspectRatios.ratioLabel(StreamingPreferences.width, StreamingPreferences.height)
        var panelRatio = panelSize.height > 0 ? panelSize.width / panelSize.height : 0
        var percent = Math.round((Math.max(streamRatio / screenRatio, screenRatio / streamRatio) - 1) * 100)
        // A stream with the whole panel's ratio fills the panel, under the notch, so nothing is distorted
        if (percent < 1 || (panelRatio > 0 && Math.abs(streamRatio / panelRatio - 1) <= 0.01)) {
            return qsTr("%1 matches this screen: no distortion.").arg(name)
        }
        if (!StreamingPreferences.fullscreenStretch) {
            return streamRatio > screenRatio ? qsTr("%1 on this screen: black bars above and below.").arg(name)
                                             : qsTr("%1 on this screen: black bars at the sides.").arg(name)
        }
        // A stream that's wider than the screen gets squeezed sideways, so it looks taller
        return streamRatio > screenRatio ? qsTr("%1 on this screen: %2% taller.").arg(name).arg(percent)
                                         : qsTr("%1 on this screen: %2% wider.").arg(name).arg(percent)
    }

    // ---- Picture --------------------------------------------------------------------------

    ForkCard {
        title: qsTr("Picture")

        Column {
            width: parent.width
            spacing: 10

            ForkText {
                kind: "label"
                font.weight: Font.DemiBold
                text: qsTr("Aspect ratio")
            }

            ForkSegmented {
                visible: displaySection.displayChoices.length > 1
                accessibleName: qsTr("For display")
                options: displaySection.displayChoices
                value: displaySection.displayIndex
                onActivated: (value) => displaySection.chooseDisplay(value)
            }

            Flow {
                id: ratioFlow
                width: parent.width
                spacing: 10

                readonly property int columns: Math.max(2, Math.floor((width + spacing) / (150 + spacing)))
                readonly property real cardWidth: (width - (columns - 1) * spacing) / columns

                Repeater {
                    model: displaySection.ratioEntries

                    delegate: ForkOptionCard {
                        id: ratioCard
                        required property var modelData

                        readonly property var parts: displaySection.splitLabel(modelData.label)

                        width: ratioFlow.cardWidth
                        // Room for a two-line detail, like "1.54:1 · with the notch area"
                        height: 130
                        title: parts.title
                        subtitle: parts.detail !== "" ? parts.detail : displaySection.ratioNote(modelData.key)
                        selected: displaySection.ratioKey === modelData.key
                        onClicked: displaySection.chooseRatio(modelData.key)

                        // The ratio's shape, in a 64x40 box
                        Item {
                            width: 64
                            height: 40

                            Rectangle {
                                visible: ratioCard.modelData.ratio > 0
                                anchors.centerIn: parent
                                width: ratioCard.modelData.ratio >= 1.6 ? 64 : 40 * ratioCard.modelData.ratio
                                height: ratioCard.modelData.ratio >= 1.6 ? 64 / ratioCard.modelData.ratio : 40
                                radius: 4
                                color: ratioCard.selected ? ForkTheme.accent : ForkTheme.lineStrong
                            }

                            Shape {
                                visible: ratioCard.modelData.ratio <= 0
                                anchors.centerIn: parent
                                width: 44
                                height: 30
                                preferredRendererType: Shape.CurveRenderer

                                ShapePath {
                                    strokeColor: ForkTheme.faint
                                    strokeWidth: 1.5
                                    strokeStyle: ShapePath.DashLine
                                    dashPattern: [3, 2.5]
                                    fillColor: "transparent"
                                    startX: 4; startY: 0.75
                                    PathLine { x: 40; y: 0.75 }
                                    PathArc { x: 43.25; y: 4; radiusX: 3.25; radiusY: 3.25 }
                                    PathLine { x: 43.25; y: 26 }
                                    PathArc { x: 40; y: 29.25; radiusX: 3.25; radiusY: 3.25 }
                                    PathLine { x: 4; y: 29.25 }
                                    PathArc { x: 0.75; y: 26; radiusX: 3.25; radiusY: 3.25 }
                                    PathLine { x: 0.75; y: 4 }
                                    PathArc { x: 4; y: 0.75; radiusX: 3.25; radiusY: 3.25 }
                                }
                            }
                        }
                    }
                }
            }
        }

        Column {
            visible: displaySection.ratioKey === "custom"
            width: parent.width
            spacing: 6

            ForkText {
                kind: "label"
                font.weight: Font.DemiBold
                text: qsTr("Custom ratio")
            }

            ForkTextField {
                id: customField
                width: 200
                font.family: ForkTheme.monoFamily
                placeholderText: qsTr("W:H")
                inputMethodHints: Qt.ImhPreferNumbers
                Accessible.name: qsTr("Custom ratio")
                onAccepted: displaySection.customRatioTyped()
                onEditingFinished: displaySection.customRatioTyped()
            }

            ForkText {
                width: parent.width
                kind: "help"
                color: customField.invalid ? ForkTheme.danger : ForkTheme.muted
                text: customField.invalid ? qsTr("Enter a ratio like 21:9, 12:5 or 2.39:1.")
                                          : qsTr("Width to height, like 21:9, 12:5 or 2.39:1")
            }
        }

        Column {
            width: parent.width
            spacing: 10

            ForkText {
                kind: "label"
                font.weight: Font.DemiBold
                text: qsTr("Resolution")
            }

            Flow {
                id: sizeFlow
                width: parent.width
                spacing: 8

                readonly property int columns: Math.max(1, Math.floor((width + spacing) / (190 + spacing)))
                readonly property real cardWidth: (width - (columns - 1) * spacing) / columns

                // A row with a note under the size is a little taller than one without: every
                // row is as tall as the tallest, so they line up
                readonly property real rowHeight: 54

                Repeater {
                    model: displaySection.presets

                    delegate: ForkOptionCard {
                        required property var modelData

                        readonly property string note: {
                            var text = modelData.text
                            var open = text.lastIndexOf("(")
                            return open > 0 ? text.substring(open + 1, text.length - 1) : ""
                        }

                        width: sizeFlow.cardWidth
                        height: Math.max(sizeFlow.rowHeight, implicitHeight)
                        compact: true
                        monoTitle: true
                        title: modelData.width + "×" + modelData.height
                        subtitle: note
                        selected: modelData.width === StreamingPreferences.width && modelData.height === StreamingPreferences.height
                        onClicked: displaySection.applySize(modelData.width, modelData.height)
                    }
                }

                // A size that isn't in the list stays selected, as "Custom (W×H)"
                ForkOptionCard {
                    visible: !displaySection.sizeListed
                    width: sizeFlow.cardWidth
                    height: Math.max(sizeFlow.rowHeight, implicitHeight)
                    compact: true
                    monoTitle: true
                    title: StreamingPreferences.width + "×" + StreamingPreferences.height
                    subtitle: qsTr("custom size")
                    selected: true
                    onClicked: customResolutionDialog.openFor(StreamingPreferences.width, StreamingPreferences.height,
                                                              displaySection.ratioKey === "custom" ? displaySection.customRatio : 0)
                }

                ForkOptionCard {
                    width: sizeFlow.cardWidth
                    height: Math.max(sizeFlow.rowHeight, implicitHeight)
                    compact: true
                    title: qsTr("Custom size…")
                    subtitle: qsTr("any width and height")
                    onClicked: customResolutionDialog.openFor(StreamingPreferences.width, StreamingPreferences.height,
                                                              displaySection.ratioKey === "custom" ? displaySection.customRatio : 0)
                }
            }
        }

        ForkWarnBox {
            warnings: {
                // Read so the warnings are checked again when the displays change
                ClientHardware.displays
                return ClientHardware.warningsFor(StreamingPreferences.width, StreamingPreferences.height, StreamingPreferences.fps,
                                                  StreamingPreferences.videoCodecConfig, StreamingPreferences.enableHdr)
            }
        }

        Flow {
            width: parent.width
            spacing: 32

            Column {
                id: fpsColumn
                spacing: 10

                ForkText {
                    kind: "label"
                    font.weight: Font.DemiBold
                    text: qsTr("Frame rate")
                }

                ForkSegmented {
                    mono: true
                    accessibleName: qsTr("Frame rate")
                    options: displaySection.fpsOptions
                    value: StreamingPreferences.fps
                    onActivated: (value) => {
                        if (value === "custom") {
                            fpsDialog.openFor(StreamingPreferences.fps)
                        }
                        else {
                            displaySection.applyFps(value)
                        }
                    }
                }

                ForkText {
                    visible: displaySection.maxRefresh > 0
                    kind: "help"
                    text: qsTr("This display refreshes at up to %1 Hz").arg(displaySection.maxRefresh)
                }
            }

            Column {
                // The rest of the row, or the whole row when it's too narrow to share
                width: parent.width - fpsColumn.width - parent.spacing >= 260 ? parent.width - fpsColumn.width - parent.spacing : parent.width
                spacing: 8

                Item {
                    width: parent.width
                    height: bitrateLabel.implicitHeight

                    ForkText {
                        id: bitrateLabel
                        kind: "label"
                        font.weight: Font.DemiBold
                        text: qsTr("Bitrate")
                    }

                    ForkText {
                        anchors.right: parent.right
                        kind: "mono"
                        font.pixelSize: 14
                        color: ForkTheme.accentInk
                        text: qsTr("%1 Mb/s").arg(StreamingPreferences.bitrateKbps / 1000)
                    }
                }

                ForkSlider {
                    id: bitrateSlider
                    width: parent.width
                    from: 500
                    to: StreamingPreferences.unlockBitrate ? 500000 : 150000
                    stepSize: 500
                    Accessible.name: qsTr("Bitrate")

                    onMoved: {
                        StreamingPreferences.autoAdjustBitrate = false
                        StreamingPreferences.bitrateKbps = value
                    }

                    // Follows the setting (a new size changes it) except while it's dragged
                    Binding on value {
                        value: StreamingPreferences.bitrateKbps
                        when: !bitrateSlider.pressed
                    }
                }

                Item {
                    width: parent.width
                    height: Math.max(bitrateHelp.implicitHeight, defaultButton.implicitHeight)

                    ForkText {
                        id: bitrateHelp
                        anchors.left: parent.left
                        anchors.right: defaultButton.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "help"
                        text: qsTr("Lower it on slow networks, raise it for a sharper picture")
                    }

                    ForkButton {
                        id: defaultButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "link"
                        visible: StreamingPreferences.bitrateKbps !== displaySection.defaultBitrate
                        text: qsTr("Use default (%1 Mb/s)").arg(displaySection.defaultBitrate / 1000)
                        onClicked: {
                            StreamingPreferences.bitrateKbps = displaySection.defaultBitrate
                            StreamingPreferences.autoAdjustBitrate = true
                        }
                    }
                }
            }
        }

        ForkSwitchRow {
            label: qsTr("HDR")
            help: SystemProperties.supportsHdr ? qsTr("Brighter highlights on an HDR display. Some games need an HDR monitor on the host PC to turn it on.")
                                               : qsTr("HDR streaming isn't supported on this Mac.")
            enabled: SystemProperties.supportsHdr
            checked: SystemProperties.supportsHdr && StreamingPreferences.enableHdr
            onToggled: (on) => StreamingPreferences.enableHdr = on
        }
    }

    // ---- Window ---------------------------------------------------------------------------

    ForkCard {
        title: qsTr("Window")

        Column {
            visible: SystemProperties.hasDesktopEnvironment
            width: parent.width
            spacing: 10

            ForkText {
                kind: "label"
                font.weight: Font.DemiBold
                text: qsTr("Display mode")
            }

            ForkSegmented {
                enabled: !SystemProperties.rendererAlwaysFullScreen
                accessibleName: qsTr("Display mode")
                options: [
                    { "value": StreamingPreferences.WM_FULLSCREEN, "label": qsTr("Fullscreen") },
                    { "value": StreamingPreferences.WM_FULLSCREEN_DESKTOP, "label": qsTr("Borderless windowed") },
                    { "value": StreamingPreferences.WM_WINDOWED, "label": qsTr("Windowed") }
                ]
                value: StreamingPreferences.windowMode
                onActivated: (value) => StreamingPreferences.windowMode = value
            }

            ForkText {
                width: parent.width
                kind: "help"
                text: qsTr("Fullscreen generally provides the best performance, but borderless windowed may work better with features like macOS Spaces, Alt+Tab, screenshot tools, on-screen overlays, etc.")
            }
        }

        Column {
            width: parent.width
            spacing: 10

            ForkText {
                kind: "label"
                font.weight: Font.DemiBold
                text: qsTr("Fullscreen fill")
            }

            Flow {
                id: fillFlow
                width: parent.width
                spacing: 10

                readonly property int columns: Math.max(1, Math.floor((width + spacing) / (220 + spacing)))
                readonly property real cardWidth: (width - (columns - 1) * spacing) / columns

                Repeater {
                    model: [
                        { "stretch": false, "title": qsTr("Fit"), "subtitle": qsTr("Keeps the shape, adds black bars") },
                        { "stretch": true, "title": qsTr("Stretch"), "subtitle": qsTr("Fills the screen, distorts the picture") }
                    ]

                    delegate: ForkOptionCard {
                        id: fillCard
                        required property var modelData

                        // The picture's box in a 112x70 screen, and the ball drawn in it: round when fitted
                        readonly property real boxW: displaySection.streamRatio >= 1.6 ? 112 : 70 * displaySection.streamRatio
                        readonly property real boxH: displaySection.streamRatio >= 1.6 ? 112 / displaySection.streamRatio : 70
                        readonly property real ball: Math.round(boxH * 0.5)

                        width: fillFlow.cardWidth
                        horizontal: true
                        enabled: !displaySection.windowed
                        title: modelData.title
                        subtitle: modelData.subtitle
                        selected: StreamingPreferences.fullscreenStretch === modelData.stretch
                        onClicked: StreamingPreferences.fullscreenStretch = modelData.stretch

                        // The screen: 112x70 inside a 1 pt border
                        Rectangle {
                            width: 114
                            height: 72
                            radius: 8
                            color: "#05070F"
                            border.color: ForkTheme.line
                            Accessible.ignored: true

                            Rectangle {
                                anchors.centerIn: parent
                                width: fillCard.modelData.stretch ? 112 : fillCard.boxW
                                height: fillCard.modelData.stretch ? 70 : fillCard.boxH
                                // A picture that fills the screen follows its rounded corners
                                radius: fillCard.modelData.stretch ? 7 : 0
                                color: "#1E2650"

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: fillCard.modelData.stretch ? fillCard.ball * 112 / fillCard.boxW : fillCard.ball
                                    height: fillCard.modelData.stretch ? fillCard.ball * 70 / fillCard.boxH : fillCard.ball
                                    radius: Math.min(width, height) / 2
                                    color: "#F5C878"
                                }
                            }
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 8

                ForkSymbol {
                    y: 1
                    symbol: "info.circle"
                    size: 15
                    color: ForkTheme.muted
                }

                ForkText {
                    width: parent.width - 23
                    kind: "body"
                    color: ForkTheme.text2
                    text: displaySection.fillNote
                }
            }
        }

        Column {
            width: parent.width
            spacing: 0

            ForkSwitchRow {
                label: qsTr("V-Sync")
                help: qsTr("Disabling V-Sync allows sub-frame rendering latency, but it can display visible tearing")
                checked: StreamingPreferences.enableVsync
                onToggled: (on) => StreamingPreferences.enableVsync = on
            }

            ForkSwitchRow {
                label: qsTr("Frame pacing")
                help: qsTr("Frame pacing reduces micro-stutter by delaying frames that come in too early")
                enabled: StreamingPreferences.enableVsync
                checked: StreamingPreferences.enableVsync && StreamingPreferences.framePacing
                onToggled: (on) => StreamingPreferences.framePacing = on
            }
        }
    }

    // ---- Dialogs --------------------------------------------------------------------------

    ForkCustomResolutionDialog {
        id: customResolutionDialog
        onAccepted: {
            displaySection.applySize(chosenWidth, chosenHeight)
            displaySection.syncToSaved()
        }
    }

    ForkFpsDialog {
        id: fpsDialog
        onAccepted: displaySection.applyFps(chosenFps)
    }

    // Set once the display list is loaded, so the frame rates are listed again
    property int displaysLoaded: 0

    Component.onCompleted: {
        refreshScreen()
        displaysLoaded++
        syncToSaved()
    }
}
