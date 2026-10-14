import QtQuick
import QtQuick.Controls

import AspectRatios 1.0
import ClientHardware 1.0
import ForkPreferences 1.0
import StreamingPreferences 1.0

// "Aspect ratio" above Resolution and FPS in SettingsView. The chosen ratio decides which sizes
// the Resolution list offers, so it's refilled here: resolutionCombo is SettingsView's own combo
// box, and its ListModel keeps the same roles (text, video_width, video_height, is_custom), so
// its onActivated and bitrate update work as before. Apollo makes a virtual display at exactly
// the size asked for, so any ratio works.
Column {
    id: aspectRatioPicker

    // SettingsView's resolution combo box
    property var resolutionCombo

    // The chosen ratio's key (see AspectRatios), its number (width over height; the custom
    // resolution dialog holds it) and the display its sizes are measured against
    property string ratioKey: ""
    readonly property real ratio: ratioOf(ratioKey)
    property int displayIndex: 0

    // From AspectRatios.ratios(), and the ratio typed after "Custom ratio…"
    property var entries: []
    property real customRatio: 0

    // The displays to pick from, built-in first: maps of index (into ClientHardware.displays) and text
    readonly property var displayChoices: sortedDisplays(ClientHardware.displays)

    // Set once the first fill has run, so a preference change before that doesn't fill early
    property bool ready: false

    spacing: 5

    function ratioOf(key) {
        if (key === "custom") {
            return customRatio
        }
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].key === key) {
                return entries[i].ratio
            }
        }
        return 0
    }

    function indexOfKey(key) {
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].key === key) {
                return i
            }
        }
        return -1
    }

    function sortedDisplays(displays) {
        var list = []
        for (var i = 0; i < displays.length; i++) {
            list.push({ "index": i, "text": displays[i].name, "builtin": displays[i].isBuiltin })
        }
        list.sort(function(a, b) {
            return a.builtin !== b.builtin ? (a.builtin ? -1 : 1) : a.index - b.index
        })
        return list
    }

    function indexOfDisplay(index) {
        for (var i = 0; i < displayChoices.length; i++) {
            if (displayChoices[i].index === index) {
                return i
            }
        }
        return 0
    }

    // Lists the ratios for the display, with the chosen one selected
    function loadEntries() {
        entries = AspectRatios.ratios(displayIndex)
        ratioComboBox.currentIndex = indexOfKey(ratioKey)
        ratioComboBox.recalculateWidth()
        displayComboBox.currentIndex = indexOfDisplay(displayIndex)
        displayComboBox.recalculateWidth()
    }

    // Makes the model's rows these ones, in place. The list never goes empty, which would leave the
    // combo box's currentIndex at -1 for a moment and upset bindings that read the current row.
    function setRows(model, rows) {
        for (var i = 0; i < rows.length; i++) {
            if (i < model.count) {
                model.set(i, rows[i])
            }
            else {
                model.append(rows[i])
            }
        }

        if (model.count > rows.length) {
            resolutionCombo.currentIndex = Math.min(resolutionCombo.currentIndex, rows.length - 1)
            model.remove(rows.length, model.count - rows.length)
        }
    }

    // Fills the Resolution list with the sizes of the chosen ratio. With chooseDefault the size
    // that fills the display is selected, and applied as if it were picked from the list (so the
    // bitrate follows). Without it the size to keep stays selected (the saved one unless
    // keepWidth and keepHeight say otherwise), which is how the list starts.
    function refill(chooseDefault, keepWidth, keepHeight) {
        var presets = AspectRatios.presets(ratioKey, customRatio, displayIndex)
        if (presets.length === 0 || !resolutionCombo) {
            return
        }

        var savedWidth = keepWidth !== undefined ? keepWidth : StreamingPreferences.width
        var savedHeight = keepHeight !== undefined ? keepHeight : StreamingPreferences.height
        var rows = []
        var saved = -1
        var fill = -1
        var closest = -1
        var closestDistance = 0

        for (var i = 0; i < presets.length; i++) {
            var preset = presets[i]
            rows.push({
                          "text": preset.text,
                          "video_width": "" + preset.width,
                          "video_height": "" + preset.height,
                          "is_custom": false
                      })

            if (preset.width === savedWidth && preset.height === savedHeight) {
                saved = i
            }
            if (preset.fills && fill < 0) {
                fill = i
            }

            // Without a display to fill, the nearest size by pixel count is the next best
            var distance = Math.abs(Math.log(preset.width * preset.height / (savedWidth * savedHeight)))
            if (closest < 0 || distance < closestDistance) {
                closest = i
                closestDistance = distance
            }
        }

        var index = saved
        if (chooseDefault) {
            index = fill >= 0 ? fill : closest
        }
        else if (index < 0) {
            // A size that isn't in this list (a custom one) stays selectable
            rows.push({
                          "text": qsTr("Custom (%1×%2)").arg(savedWidth).arg(savedHeight),
                          "video_width": "" + savedWidth,
                          "video_height": "" + savedHeight,
                          "is_custom": true
                      })
            index = rows.length - 1
        }

        // The entry that opens the custom resolution dialog, as in upstream
        rows.push({
                      "text": qsTr("Custom"),
                      "video_width": "",
                      "video_height": "",
                      "is_custom": true
                  })

        setRows(resolutionCombo.model, rows)
        resolutionCombo.currentIndex = index
        resolutionCombo.recalculateWidth()
        resolutionCombo.lastIndexValue = index
        if (chooseDefault) {
            resolutionCombo.updateBitrateForSelection()
        }
    }

    // Shows the ratio of a size (the saved one by default), and fills the list to match it
    function syncToSize(width, height) {
        ratioKey = AspectRatios.keyFor(width, height, displayIndex)
        if (ratioKey === "custom") {
            customRatio = height > 0 ? width / height : 16 / 9
            customField.text = AspectRatios.ratioLabel(width, height)
            customField.invalid = false
        }
        loadEntries()
        refill(false, width, height)
    }

    function syncToSaved() {
        syncToSize(StreamingPreferences.width, StreamingPreferences.height)
    }

    // Selects a size typed in the custom resolution dialog, like picking it from the list: it
    // gets an entry unless the list has it, and the bitrate follows
    function useSize(width, height) {
        syncToSize(width, height)
        resolutionCombo.updateBitrateForSelection()
    }

    function initialize() {
        displayIndex = AspectRatios.defaultDisplay()
        syncToSaved()
        ready = true
    }

    function ratioChosen(key) {
        if (key === ratioKey) {
            return
        }

        ratioKey = key
        if (key === "custom") {
            // Start from the ratio of the current size. The field takes a new one.
            var width = StreamingPreferences.width
            var height = StreamingPreferences.height
            customRatio = height > 0 ? width / height : 16 / 9
            customField.text = AspectRatios.ratioLabel(width, height)
            customField.invalid = false
            refill(false)
            customField.forceActiveFocus()
            customField.selectAll()
        }
        else {
            refill(true)
        }
    }

    // Only what was typed counts, so leaving the field untouched doesn't change the size
    function customRatioTyped() {
        if (!customField.edited) {
            return
        }

        customField.edited = false
        var typed = AspectRatios.parseRatio(customField.text)
        customField.invalid = typed <= 0
        if (typed > 0 && Math.abs(typed - customRatio) > 1e-9) {
            customRatio = typed
            refill(true)
        }
    }

    function displayChosen(index) {
        displayIndex = index
        loadEntries()
        if (indexOfKey(ratioKey) < 0) {
            // This display has no such shape (the notch, say): its own shape instead
            ratioKey = "full"
            loadEntries()
        }
        refill(true)
    }

    // The window mode, Stretch and the notch bar decide whether a stream goes below the notch,
    // which changes the size that fills the display. The selected size stays.
    function preferencesChanged() {
        if (ready) {
            refill(false)
        }
    }

    Component.onCompleted: {
        // After the Resolution combo box has built its own list
        Qt.callLater(initialize)
    }

    Connections {
        target: StreamingPreferences

        function onFullscreenStretchChanged() { aspectRatioPicker.preferencesChanged() }
        function onWindowModeChanged() { aspectRatioPicker.preferencesChanged() }
    }

    Connections {
        target: ForkPreferences

        function onNotchBarChanged() { aspectRatioPicker.preferencesChanged() }
    }

    // Displays that come or go
    Connections {
        target: ClientHardware

        function onChanged() {
            if (aspectRatioPicker.ready) {
                aspectRatioPicker.displayIndex = Math.min(aspectRatioPicker.displayIndex, Math.max(0, ClientHardware.displays.length - 1))
                aspectRatioPicker.syncToSaved()
            }
        }
    }

    Label {
        text: qsTr("Aspect ratio")
        font.pointSize: 12
    }

    Row {
        spacing: 5
        width: parent.width

        AutoResizingComboBox {
            id: ratioComboBox
            maximumWidth: parent.width - (customField.visible ? customField.width + parent.spacing : 0)
            textRole: "label"
            model: aspectRatioPicker.entries

            // ::onActivated must be used, as it only listens for when the index is changed by a human
            onActivated: aspectRatioPicker.ratioChosen(aspectRatioPicker.entries[currentIndex].key)
        }

        TextField {
            id: customField
            property bool invalid: false
            property bool edited: false

            visible: aspectRatioPicker.ratioKey === "custom"
            width: 110
            anchors.verticalCenter: ratioComboBox.verticalCenter
            placeholderText: qsTr("W:H")
            color: invalid ? "#FF453A" : palette.text
            inputMethodHints: Qt.ImhPreferNumbers

            ToolTip.delay: 1000
            ToolTip.timeout: 8000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Width to height, like 21:9, 12:5 or 2.39:1")

            onTextEdited: edited = true
            onAccepted: aspectRatioPicker.customRatioTyped()
            onEditingFinished: aspectRatioPicker.customRatioTyped()
        }
    }

    Row {
        spacing: 5
        width: parent.width
        visible: aspectRatioPicker.displayChoices.length > 1

        Label {
            anchors.verticalCenter: displayComboBox.verticalCenter
            text: qsTr("For display")
            font.pointSize: 9
        }

        AutoResizingComboBox {
            id: displayComboBox
            maximumWidth: parent.width - 80
            textRole: "text"
            model: aspectRatioPicker.displayChoices

            // ::onActivated must be used, as it only listens for when the index is changed by a human
            onActivated: aspectRatioPicker.displayChosen(aspectRatioPicker.displayChoices[currentIndex].index)
        }
    }

    Label {
        width: parent.width
        visible: customField.visible && customField.invalid
        text: qsTr("Enter a ratio like 21:9, 12:5 or 2.39:1.")
        font.pointSize: 9
        color: "#FF453A"
        wrapMode: Text.Wrap
    }
}
