pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Shapes
import QtQuick.Effects

import ForkTheme 1.0
import ForkPcPrefs 1.0

// [fork] The "Customize <PC>" sheet (canvas board "Customize a PC"): a 600 x 590 modal over the
// app's scrim with a live preview band, the PC's name, its color and two options kept on this Mac
// (ForkPcPrefs). Open it with openFor(); Save stores the options, renames the PC through
// computerModel and emits saved(). Escape or Cancel closes it without storing anything.
NavigableDialog {
    id: sheet

    // The PCs' model (ComputerModel) for the rename, set once by the page that owns the sheet
    property var computerModel: null
    // The host software the preview names ("Apollo" or "Sunshine") and its logo
    property string hostSoftware: "Apollo"
    property url logoSource: "qrc:/res/apollo.png"

    // The PC being edited
    property string pcUuid: ""
    property string savedName: ""
    property int pcIndex: -1

    // The sheet's state (the preview follows it live)
    property string colorKey: "indigo"
    property bool wakeOnPick: true
    property bool keepFirst: false

    readonly property var current: {
        var list = ForkTheme.pcPalette
        for (var i = 0; i < list.length; i++) {
            if (list[i].key === colorKey) {
                return { key: list[i].key, name: list[i].name, fill: list[i].fill, sky: list[i].sky,
                         on: list[i].key === "gold" ? "#1A1405" : "#FFFFFF" }
            }
        }
        return { key: list[0].key, name: list[0].name, fill: list[0].fill, sky: list[0].sky, on: "#FFFFFF" }
    }

    // The sheet's tokens: the canvas's, from ForkTheme.cv where they match; the surface, raised fill
    // and divider line are the sheet's own (a little different from the pages')
    readonly property bool dk: ForkTheme.dark
    readonly property color cSurface: dk ? "#1A1D29" : "#FFFFFF"
    readonly property color cRaised: dk ? "#232736" : "#F6F6F9"
    readonly property color cChip: ForkTheme.cv.chip
    readonly property color cLine: dk ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color cLineStrong: ForkTheme.cv.lineStrong
    readonly property color cText: ForkTheme.cv.text
    readonly property color cText2: ForkTheme.cv.text2
    readonly property color cMuted: ForkTheme.cv.muted
    readonly property color cFaint: ForkTheme.cv.faint
    readonly property color cTrackOff: dk ? "#3E414B" : "#D6D6D6" // the translucent track over the surface
    readonly property int fadeMs: ForkTheme.reduceMotion ? 0 : 240
    readonly property int flipMs: ForkTheme.reduceMotion ? 0 : 200

    signal saved(string uuid, string name, string colorKey, bool wakeOnPick, bool keepFirst)

    // Opens the sheet for a PC: its saved name, color and options (from ForkPcPrefs) fill it in.
    // index is the PC's row in computerModel, for the rename.
    function openFor(uuid, name, index) {
        pcUuid = uuid
        savedName = name
        pcIndex = index === undefined ? -1 : index
        colorKey = ForkPcPrefs.colorKey(uuid)
        wakeOnPick = ForkPcPrefs.wakeOnPick(uuid)
        keepFirst = ForkPcPrefs.keepFirst(uuid)
        nameField.text = name
        open()
    }

    function save() {
        var name = nameField.text.trim()
        var renamed = name !== "" && name !== savedName
        if (renamed && computerModel && pcIndex >= 0) {
            computerModel.renameComputer(pcIndex, name)
        }
        if (colorKey !== ForkPcPrefs.colorKey(pcUuid)) {
            ForkPcPrefs.setColorKey(pcUuid, colorKey)
        }
        if (wakeOnPick !== ForkPcPrefs.wakeOnPick(pcUuid)) {
            ForkPcPrefs.setWakeOnPick(pcUuid, wakeOnPick)
        }
        if (keepFirst !== ForkPcPrefs.keepFirst(pcUuid)) {
            ForkPcPrefs.setKeepFirst(pcUuid, keepFirst)
        }
        var shown = renamed ? name : savedName
        var w = sheet.parent ? sheet.parent.Window.window : null
        if (renamed && w && typeof w["forkToast"] === "function") {
            w["forkToast"](qsTr("Renamed to %1").arg(name))
        }
        saved(pcUuid, shown, colorKey, wakeOnPick, keepFirst)
        close()
    }

    title: ""
    padding: 0
    topPadding: 0
    bottomPadding: 0
    closePolicy: Popup.CloseOnEscape
    header: Item { visible: false; height: 0 }
    footer: Item { visible: false; height: 0 }
    background: ForkDialogBackground {
        dialog: sheet
        radius: 14
    }

    onOpened: nameField.forceActiveFocus()

    contentItem: FocusScope {
        implicitWidth: 600
        implicitHeight: 590

        Accessible.role: Accessible.Dialog
        Accessible.name: qsTr("Customize %1").arg(sheet.savedName)

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: sheet.cSurface
        }

        Keys.onReturnPressed: sheet.save()
        Keys.onEnterPressed: sheet.save()

        // Title row
        ForkCanvasText {
            x: 24; y: 24; height: 24
            width: 552 - faintLabel.width - 8
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            
            text: qsTr("Customize %1").arg(sheet.savedName)
            color: sheet.cText
            px: 19
            weight: 700
            tracking: -0.19
        }
        ForkCanvasText {
            id: faintLabel
            x: 576 - width; y: 28.5; height: 15
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Only on this Mac")
            color: sheet.cFaint
            px: 12
        }

        // Preview band
        Rectangle {
            id: band
            x: 24; y: 66; width: 552; height: 118
            radius: 14
            clip: true
            color: sheet.current.sky
            Behavior on color { ColorAnimation { duration: sheet.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] } }
            Accessible.ignored: true

            Repeater {
                model: [[40, 24, 0.55], [150, 46, 0.4], [260, 18, 0.5], [500, 30, 0.45]]
                delegate: Rectangle {
                    required property var modelData
                    x: modelData[0]; y: modelData[1]; width: 2; height: 2; radius: 1
                    color: Qt.rgba(1, 1, 1, modelData[2])
                }
            }
            Rectangle { x: 16; y: 86; width: 520; height: 1; color: Qt.rgba(1, 1, 1, 0.14) }

            ForkFirstRunGlow {
                anchors.centerIn: moon
                radius: 23
                color: Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.25)
            }
            Shape {
                id: moon
                x: 408; y: 22; width: 46; height: 46
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "#F5C878"
                    strokeColor: "transparent"
                    PathSvg { path: "M38.839 39.677A23 23 0 1 1 19.161 0.323A23 23 0 0 0 38.839 39.677Z" }
                }
            }
            Rectangle { x: 410; y: 92; width: 42; height: 3; radius: 1.5; color: "#F5C878"; opacity: 0.9 }
            Rectangle { x: 416; y: 99; width: 30; height: 3; radius: 1.5; color: "#F5C878"; opacity: 0.6 }
            Rectangle { x: 423; y: 106; width: 16; height: 3; radius: 1.5; color: "#F5C878"; opacity: 0.4 }

            Image {
                x: 13; y: 16; width: 44; height: 44
                source: sheet.logoSource
                sourceSize: Qt.size(176, 176)
                smooth: true
                mipmap: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.35)
                    shadowVerticalOffset: 4
                    shadowBlur: 0.5
                    blurMax: 16
                }
            }
            ForkCanvasText {
                x: 64; y: 20.5; height: 19; width: 400
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                
                text: nameField.text.trim() !== "" ? nameField.text.trim() : sheet.savedName
                color: "#FFFFFF"
                px: 15
                weight: 650
            }
            ForkCanvasText {
                x: 64; y: 40.5; height: 15
                verticalAlignment: Text.AlignVCenter
                text: sheet.hostSoftware + " · " + sheet.current.name
                color: "#FFFFFF"
                opacity: 0.75
                px: 12
            }
        }

        // Name
        ForkCanvasText {
            x: 24; y: 202; height: 16
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Name")
            color: sheet.cText2
            px: 13
            weight: 600
        }
        TextField {
            id: nameField
            x: 24; y: 224; width: 552; height: 38
            leftPadding: 12; rightPadding: 12; topPadding: 0; bottomPadding: 0
            verticalAlignment: TextInput.AlignVCenter
            color: sheet.cText
            selectedTextColor: "#FFFFFF"
            selectionColor: sheet.current.fill
            font.family: ForkTheme.uiFamily
            font.pointSize: 14 * 72 / (Screen.logicalPixelDensity * 25.4)
            selectByMouse: true
            maximumLength: 64
            Accessible.name: qsTr("Name")
            background: Item {
                Rectangle { anchors.fill: parent; radius: 9; color: sheet.cRaised }
                Rectangle { anchors.fill: parent; radius: 9; color: "transparent"; border.width: 1; border.color: sheet.cLineStrong }
                Rectangle {
                    anchors.fill: parent; anchors.margins: -2; radius: 11; color: "transparent"
                    border.width: 2; border.color: ForkTheme.selEdge
                    visible: nameField.activeFocus
                }
            }
        }

        // Color
        ForkCanvasText {
            x: 24; y: 280; height: 16
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Color")
            color: sheet.cText2
            px: 13
            weight: 600
        }
        Repeater {
            id: swatches
            model: ForkTheme.pcPalette
            delegate: Item {
                id: sw
                required property int index
                required property var modelData
                readonly property bool picked: sheet.colorKey === modelData.key
                x: 24 + 42 * index; y: 304; width: 32; height: 32
                activeFocusOnTab: true
                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.name
                Accessible.checkable: true
                Accessible.checked: picked
                Accessible.onPressAction: sheet.colorKey = modelData.key
                Keys.onSpacePressed: sheet.colorKey = modelData.key
                Keys.onLeftPressed: if (index > 0) { swatches.itemAt(index - 1).forceActiveFocus(); sheet.colorKey = ForkTheme.pcPalette[index - 1].key }
                Keys.onRightPressed: if (index < 9) { swatches.itemAt(index + 1).forceActiveFocus(); sheet.colorKey = ForkTheme.pcPalette[index + 1].key }

                Rectangle { // selected: the swatch's fill, the sheet color, then the disc
                    anchors.centerIn: parent; width: 40; height: 40; radius: 20
                    color: sw.modelData.fill; visible: sw.picked
                }
                Rectangle {
                    anchors.centerIn: parent; width: 36; height: 36; radius: 18
                    color: sheet.cSurface; visible: sw.picked
                }
                Rectangle { anchors.fill: parent; radius: 16; color: sw.modelData.fill }
                Rectangle {
                    anchors.fill: parent; radius: 16; color: "transparent"
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12); visible: !sw.picked
                }
                Rectangle { // keyboard focus
                    anchors.centerIn: parent; width: 46; height: 46; radius: 23; color: "transparent"
                    border.width: 2; border.color: ForkTheme.selEdge
                    visible: sw.activeFocus && !sw.byMouse
                }
                property bool byMouse: false
                onActiveFocusChanged: if (!activeFocus) byMouse = false
                TapHandler {
                    onTapped: { sheet.colorKey = sw.modelData.key; sw.forceActiveFocus(); sw.byMouse = true }
                }
            }
        }

        // Toggle group
        Rectangle {
            x: 24; y: 354; width: 552; height: 113
            radius: 12; color: "transparent"
            border.width: 1; border.color: sheet.cLine
            Accessible.ignored: true
        }
        Rectangle { x: 25; y: 410; width: 550; height: 1; color: sheet.cLine }

        component ToggleRow: Item {
            id: row
            property string label
            property string help
            property bool on
            property alias switchItem: tsw
            signal flipped()
            Accessible.ignored: true

            Column {
                x: 14; y: 11; spacing: 2
                ForkCanvasText {
                    height: 16; verticalAlignment: Text.AlignVCenter
                    text: row.label; color: sheet.cText
                    px: 13.5; weight: 500
                }
                ForkCanvasText {
                    height: 15; verticalAlignment: Text.AlignVCenter
                    text: row.help; color: sheet.cMuted
                    px: 12
                }
            }
            Item {
                id: tsw
                x: 498; y: (row.height - 22) / 2 + 0.5; width: 38; height: 22
                activeFocusOnTab: true
                Accessible.role: Accessible.CheckBox
                Accessible.name: row.label
                Accessible.checkable: true
                Accessible.checked: row.on
                Accessible.onToggleAction: row.flipped()
                Accessible.onPressAction: row.flipped()
                Keys.onSpacePressed: row.flipped()

                Rectangle {
                    anchors.fill: parent; radius: 11
                    color: row.on ? sheet.current.fill : sheet.cTrackOff
                    Behavior on color { ColorAnimation { duration: sheet.flipMs; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] } }
                }
                Rectangle { // the knob's shadow
                    x: knob.x; y: knob.y + 1; width: 18; height: 18; radius: 9
                    color: Qt.rgba(0, 0, 0, 0.18)
                }
                Rectangle {
                    id: knob
                    x: row.on ? 18 : 2; y: 2; width: 18; height: 18; radius: 9; color: "#FFFFFF"
                    Behavior on x { NumberAnimation { duration: sheet.flipMs; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] } }
                }
                Rectangle {
                    anchors.centerIn: parent; width: 46; height: 30; radius: 15; color: "transparent"
                    border.width: 2; border.color: ForkTheme.selEdge
                    visible: tsw.activeFocus && !tsw.byMouse
                }
                property bool byMouse: false
                onActiveFocusChanged: if (!activeFocus) byMouse = false
                TapHandler { onTapped: { row.flipped(); tsw.forceActiveFocus(); tsw.byMouse = true } }
            }
        }

        ToggleRow {
            x: 25; y: 355; width: 550; height: 55
            label: qsTr("Wake it when I pick an app")
            help: qsTr("Choosing an app on a sleeping or shut-down PC wakes it first.")
            on: sheet.wakeOnPick
            onFlipped: sheet.wakeOnPick = !sheet.wakeOnPick
        }
        ToggleRow {
            x: 25; y: 411; width: 550; height: 55
            label: qsTr("Keep it first in the carousel")
            help: qsTr("Your PCs opens on this one.")
            on: sheet.keepFirst
            onFlipped: sheet.keepFirst = !sheet.keepFirst
        }

        // Buttons
        Rectangle {
            id: saveButton
            x: 576 - width; y: 530; height: 36; width: saveLabel.implicitWidth + 44
            radius: 9
            color: sheet.current.fill
            Behavior on color { ColorAnimation { duration: sheet.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] } }
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Save")
            Accessible.onPressAction: sheet.save()
            Keys.onReturnPressed: sheet.save()
            Keys.onEnterPressed: sheet.save()
            Keys.onSpacePressed: sheet.save()
            ForkCanvasText {
                id: saveLabel
                anchors.centerIn: parent
                text: qsTr("Save")
                color: sheet.current.on
                px: 13.5; weight: 600
            }
            Rectangle {
                anchors.fill: parent; anchors.margins: -3; radius: 12; color: "transparent"
                border.width: 2; border.color: ForkTheme.selEdge; visible: saveButton.activeFocus
            }
            Rectangle { anchors.fill: parent; radius: 9; color: Qt.rgba(1, 1, 1, 0.08); visible: saveTap.pressed }
            TapHandler { id: saveTap; onTapped: sheet.save() }
        }
        Rectangle {
            id: cancelButton
            x: saveButton.x - 10 - width; y: 530; height: 36; width: cancelLabel.implicitWidth + 38
            radius: 9
            color: sheet.cChip
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Cancel")
            Accessible.onPressAction: sheet.close()
            Keys.onReturnPressed: sheet.close()
            Keys.onEnterPressed: sheet.close()
            Keys.onSpacePressed: sheet.close()
            Rectangle { anchors.fill: parent; radius: 9; color: "transparent"; border.width: 1; border.color: sheet.cLine }
            ForkCanvasText {
                id: cancelLabel
                anchors.centerIn: parent
                text: qsTr("Cancel")
                color: sheet.cText
                px: 13.5; weight: 500
            }
            Rectangle {
                anchors.fill: parent; anchors.margins: -3; radius: 12; color: "transparent"
                border.width: 2; border.color: ForkTheme.selEdge; visible: cancelButton.activeFocus
            }
            TapHandler { onTapped: sheet.close() }
        }
    }
}
