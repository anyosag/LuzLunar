import QtQuick

import ForkPreferences 1.0
import ForkTheme 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0

// [fork] Settings › Keyboard & Clipboard: what the Mac's Command, Control and Option keys send to
// the host PC, whether system shortcuts like ⌘Tab go to the PC (and on a Mac, which ones), and how
// the clipboard is shared with Apollo hosts. It holds the settings of upstream's "Capture system
// keyboard shortcuts" (as a three-way choice), of ForkMacShortcutsOption under it, and of
// ForkSettingsGroupBox's Mac keys and clipboard sync.
Column {
    id: keyboardSection

    spacing: ForkTheme.gap

    // ---- Mac keys -------------------------------------------------------------------------

    // What a Mac key can send, in the order of ForkPreferences.ModifierTarget
    readonly property var targetOptions: [
        { "value": ForkPreferences.MT_NONE, "label": qsTr("Nothing") },
        { "value": ForkPreferences.MT_CTRL, "label": qsTr("Ctrl") },
        { "value": ForkPreferences.MT_ALT, "label": qsTr("Alt") },
        { "value": ForkPreferences.MT_WIN, "label": qsTr("Windows key") }
    ]

    // Whether Command goes to the PC as a key, so ⌘Q and ⌘H do too
    readonly property bool commandToPc: ForkPreferences.commandKeyTarget !== ForkPreferences.MT_WIN

    // What the Command setting does, with an example
    readonly property string commandExample: {
        switch (ForkPreferences.commandKeyTarget) {
        case ForkPreferences.MT_CTRL:
            return qsTr("⌘C copies and ⌘V pastes on the PC, as Ctrl+C and Ctrl+V.")
        case ForkPreferences.MT_ALT:
            return qsTr("⌘Tab switches windows on the PC, as Alt+Tab.")
        case ForkPreferences.MT_WIN:
            return qsTr("⌘ opens the Start menu on the PC, as the Windows key.")
        default:
            return qsTr("Command does nothing on the PC.")
        }
    }

    // ---- Mac shortcuts --------------------------------------------------------------------

    // Whether system shortcuts go to the PC at all; the Mac shortcut choices need it
    readonly property bool captureOn: StreamingPreferences.captureSysKeysMode !== StreamingPreferences.CSK_OFF

    // macShortcutToHost() is a call, not a property, so the switches re-read it when this counts up
    property int macShortcutsRevision: 0

    Connections {
        target: ForkPreferences

        function onMacShortcutsChanged() {
            keyboardSection.macShortcutsRevision++
        }
    }

    // What the Mac shortcut choices do now
    readonly property string macShortcutsNote: {
        if (!ForkPreferences.macShortcutsSelectable) {
            return qsTr("This macOS doesn't let LuzLunar pick shortcuts, so while capturing, the Mac keeps them all unless every shortcut goes to the PC.")
        }
        if (keyboardSection.captureOn) {
            return qsTr("The shortcuts turned on here go to the PC while capturing; the rest stay with the Mac. Keys arrive after the Mac key remapping above, so ⌘Space arrives as Ctrl+Space and ⌃← as Win+←. Force Quit (⌥⌘Esc) always stays with the Mac.")
        }
        return qsTr("Choose In fullscreen or Always above to send these Mac shortcuts to the PC.")
    }

    ForkCard {
        // The Mac-only parts hide elsewhere; the system shortcuts choice below stays

        // The card's title with its explanation right under it, 6 apart as in the design
        Column {
            visible: SystemProperties.isDarwin
            width: parent.width
            spacing: 6

            ForkText {
                kind: "eyebrow"
                text: qsTr("Mac keys on the PC")
                Accessible.role: Accessible.Heading
            }

            ForkText {
                width: parent.width
                kind: "help"
                font.pixelSize: 13
                text: qsTr("Choose what each Mac modifier key sends to the host PC. LuzLunar's own shortcuts (Control-Option-Shift plus a key) always use the physical keys.")
            }
        }

        Column {
            id: keyRows
            visible: SystemProperties.isDarwin
            width: parent.width
            spacing: 0

            Repeater {
                model: [
                    { "glyph": "⌘", "word": qsTr("command"), "name": qsTr("Command") },
                    { "glyph": "⌃", "word": qsTr("control"), "name": qsTr("Control") },
                    { "glyph": "⌥", "word": qsTr("option"), "name": qsTr("Option") }
                ]

                delegate: Item {
                    id: keyRow
                    required property var modelData
                    required property int index

                    // The three settings change together, so one read covers them
                    readonly property int target: index === 0 ? ForkPreferences.commandKeyTarget
                                                : index === 1 ? ForkPreferences.controlKeyTarget
                                                : ForkPreferences.optionKeyTarget

                    function choose(value) {
                        if (index === 0) {
                            ForkPreferences.commandKeyTarget = value
                        }
                        else if (index === 1) {
                            ForkPreferences.controlKeyTarget = value
                        }
                        else {
                            ForkPreferences.optionKeyTarget = value
                        }
                    }

                    width: keyRows.width
                    height: rowFlow.y + rowFlow.implicitHeight + 12

                    // The first row has no line above it
                    Rectangle {
                        visible: keyRow.index > 0
                        width: parent.width
                        height: 1
                        color: ForkTheme.lineSoft
                    }

                    // Wraps below the key's name when the page is narrow
                    Flow {
                        id: rowFlow
                        y: keyRow.index > 0 ? 13 : 12
                        width: parent.width
                        spacing: 20

                        Row {
                            width: Math.min(210, rowFlow.width)
                            height: 56
                            spacing: 14

                            // The key: its edge shows below it
                            Rectangle {
                                width: 64
                                height: 56
                                radius: 10
                                color: ForkTheme.lineStrong
                                Accessible.ignored: true

                                Rectangle {
                                    width: parent.width
                                    height: parent.height - 3
                                    radius: 10
                                    color: ForkTheme.tile

                                    ForkText {
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.topMargin: 6
                                        anchors.rightMargin: 8
                                        font.pixelSize: 15
                                        font.weight: Font.Medium
                                        text: keyRow.modelData.glyph
                                    }

                                    ForkText {
                                        anchors.left: parent.left
                                        anchors.bottom: parent.bottom
                                        anchors.leftMargin: 8
                                        anchors.bottomMargin: 6
                                        font.pixelSize: 10
                                        color: ForkTheme.text2
                                        text: keyRow.modelData.word
                                    }
                                }
                            }

                            ForkText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 64 - parent.spacing
                                kind: "label"
                                elide: Text.ElideRight
                                text: keyRow.modelData.name
                            }
                        }

                        Row {
                            height: 56
                            spacing: 14

                            ForkSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                symbol: "arrow.right"
                                size: 18
                                color: ForkTheme.faint
                            }

                            ForkSegmented {
                                anchors.verticalCenter: parent.verticalCenter
                                accessibleName: qsTr("%1 sends").arg(keyRow.modelData.name)
                                options: keyboardSection.targetOptions
                                value: keyRow.target
                                onActivated: (value) => keyRow.choose(value)
                            }
                        }
                    }
                }
            }
        }

        Flow {
            id: modifierTips
            visible: SystemProperties.isDarwin
            width: parent.width
            spacing: 10

            readonly property int columns: Math.max(1, Math.min(keyboardSection.commandToPc ? 2 : 1, Math.floor((width + spacing) / (260 + spacing))))
            readonly property real tipWidth: (width - (columns - 1) * spacing) / columns
            // Tips side by side share the taller one's height
            readonly property real tipHeight: Math.max(exampleTip.implicitHeight, commandTip.visible ? commandTip.implicitHeight : 0)

            ForkTip {
                id: exampleTip
                height: modifierTips.columns > 1 ? modifierTips.tipHeight : implicitHeight
                width: modifierTips.tipWidth
                lead: qsTr("e.g.")
                text: keyboardSection.commandExample
            }

            ForkTip {
                id: commandTip
                height: modifierTips.columns > 1 ? modifierTips.tipHeight : implicitHeight
                visible: keyboardSection.commandToPc
                width: modifierTips.tipWidth
                symbol: "info.circle"
                text: qsTr("While streaming, ⌘Q and ⌘H go to the PC. End a stream with ⌃⌥⇧Q.")
            }
        }

        // The system shortcuts choice, set off by a line when the Mac keys are above it
        Item {
            width: parent.width
            height: systemColumn.y + systemColumn.implicitHeight

            Rectangle {
                visible: SystemProperties.isDarwin
                width: parent.width
                height: 1
                color: ForkTheme.lineSoft
            }

            Column {
                id: systemColumn
                y: SystemProperties.isDarwin ? 17 : 0
                width: parent.width
                spacing: 10

                ForkText {
                    kind: "label"
                    font.weight: Font.DemiBold
                    text: qsTr("Send system shortcuts to the PC")
                }

                ForkSegmented {
                    enabled: SystemProperties.hasDesktopEnvironment
                    accessibleName: qsTr("Send system shortcuts to the PC")
                    options: [
                        { "value": StreamingPreferences.CSK_OFF, "label": qsTr("Off") },
                        { "value": StreamingPreferences.CSK_FULLSCREEN, "label": qsTr("In fullscreen") },
                        { "value": StreamingPreferences.CSK_ALWAYS, "label": qsTr("Always") }
                    ]
                    value: StreamingPreferences.captureSysKeysMode
                    onActivated: (value) => StreamingPreferences.captureSysKeysMode = value
                }

                ForkText {
                    width: parent.width
                    kind: "help"
                    text: qsTr("This captures system-wide shortcuts like ⌘Tab that would normally go to this Mac. Some, like Ctrl+Alt+Del on Windows, can't be captured by any app.")
                }
            }
        }

        // Which Mac shortcuts capture takes (forksystemshortcuts.cpp applies them while streaming),
        // set off by a line
        Item {
            visible: SystemProperties.isDarwin
            width: parent.width
            height: macShortcutsColumn.y + macShortcutsColumn.implicitHeight

            Rectangle {
                width: parent.width
                height: 1
                color: ForkTheme.lineSoft
            }

            Column {
                id: macShortcutsColumn
                y: 17
                width: parent.width
                spacing: 10

                ForkText {
                    kind: "label"
                    font.weight: Font.DemiBold
                    text: qsTr("Mac shortcuts that go to the PC")
                }

                ForkText {
                    width: parent.width
                    kind: "help"
                    text: keyboardSection.macShortcutsNote
                }

                Column {
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: SystemProperties.isDarwin ? ForkPreferences.macShortcutGroups() : []

                        delegate: ForkSwitchRow {
                            required property var modelData
                            required property int index

                            // "Spotlight (⌘Space, ⌥⌘Space)" shows as the name over its keys
                            readonly property var labelParts: /^(.*) \((.*)\)$/.exec(modelData.label)

                            showDivider: index > 0
                            label: labelParts ? labelParts[1] : modelData.label
                            help: labelParts ? labelParts[2] : ""
                            enabled: keyboardSection.captureOn && ForkPreferences.macShortcutsSelectable && !ForkPreferences.macShortcutsAll
                            checked: {
                                keyboardSection.macShortcutsRevision
                                return ForkPreferences.macShortcutToHost(modelData.key)
                            }
                            onToggled: (on) => ForkPreferences.setMacShortcutToHost(modelData.key, on)
                        }
                    }

                    ForkSwitchRow {
                        label: qsTr("Send every Mac shortcut to the PC")
                        help: qsTr("Moonlight's behavior: while capturing, every system shortcut goes to the PC, including screenshots (⇧⌘4) and other apps' global shortcuts.")
                        enabled: keyboardSection.captureOn
                        checked: ForkPreferences.macShortcutsAll
                        onToggled: (on) => ForkPreferences.macShortcutsAll = on
                    }
                }

                ForkTip {
                    width: parent.width
                    key: "K"
                    text: qsTr("Control-Option-Shift-K gives the Mac its shortcuts back for the rest of a stream")
                }
            }
        }
    }

    // ---- Clipboard ------------------------------------------------------------------------

    // What the sync mode does
    readonly property string syncNote: {
        switch (ForkPreferences.clipboardSyncMode) {
        case ForkPreferences.CSM_AUTOMATIC:
            return qsTr("Sends this Mac's clipboard when you switch to the stream and fetches the PC's when you switch away, transferring only what changed.")
        case ForkPreferences.CSM_MANUAL:
            return qsTr("Nothing moves until you press a shortcut.")
        default:
            return qsTr("Each computer keeps its own clipboard.")
        }
    }

    ForkCard {
        title: qsTr("Clipboard")

        Column {
            width: parent.width
            spacing: 10

            ForkText {
                kind: "label"
                font.weight: Font.DemiBold
                text: qsTr("Clipboard sync")
            }

            ForkSegmented {
                accessibleName: qsTr("Clipboard sync")
                options: [
                    { "value": ForkPreferences.CSM_OFF, "label": qsTr("Off") },
                    { "value": ForkPreferences.CSM_MANUAL, "label": qsTr("Shortcuts only") },
                    { "value": ForkPreferences.CSM_AUTOMATIC, "label": qsTr("Automatic") }
                ]
                value: ForkPreferences.clipboardSyncMode
                onActivated: (value) => ForkPreferences.clipboardSyncMode = value
            }

            ForkText {
                width: parent.width
                kind: "body"
                color: ForkTheme.text2
                text: keyboardSection.syncNote
            }
        }

        Flow {
            id: clipboardTips
            visible: ForkPreferences.clipboardSyncMode !== ForkPreferences.CSM_OFF
            width: parent.width
            spacing: 10

            readonly property int columns: Math.max(1, Math.min(2, Math.floor((width + spacing) / (240 + spacing))))
            readonly property real tipWidth: (width - (columns - 1) * spacing) / columns
            // Tips side by side share the taller one's height
            readonly property real tipHeight: Math.max(sendTip.implicitHeight, getTip.visible ? getTip.implicitHeight : 0)

            ForkTip {
                id: sendTip
                height: clipboardTips.columns > 1 ? clipboardTips.tipHeight : implicitHeight
                width: clipboardTips.tipWidth
                key: "U"
                text: qsTr("Control-Option-Shift-U sends this Mac's clipboard")
            }

            ForkTip {
                id: getTip
                height: clipboardTips.columns > 1 ? clipboardTips.tipHeight : implicitHeight
                width: clipboardTips.tipWidth
                key: "G"
                text: qsTr("Control-Option-Shift-G gets the PC's clipboard")
            }
        }

        // What travels, set off by a line
        Item {
            width: parent.width
            height: travelColumn.y + travelColumn.implicitHeight

            Rectangle {
                width: parent.width
                height: 1
                color: ForkTheme.lineSoft
            }

            Column {
                id: travelColumn
                y: 17
                width: parent.width
                spacing: 10

                ForkText {
                    kind: "label"
                    font.weight: Font.DemiBold
                    text: qsTr("What travels")
                }

                Flow {
                    id: chipFlow
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: [
                            { "symbol": "textformat", "label": qsTr("Text") },
                            { "symbol": "tablecells", "label": qsTr("Formatting from Word, Excel and PowerPoint") },
                            { "symbol": "photo", "label": qsTr("Images") }
                        ]

                        delegate: Rectangle {
                            id: chip
                            required property var modelData

                            width: chipRow.width + 24
                            height: 30
                            radius: height / 2
                            color: ForkTheme.raised

                            Accessible.role: Accessible.StaticText
                            Accessible.name: modelData.label

                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 8

                                ForkSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    symbol: chip.modelData.symbol
                                    size: 14
                                    color: ForkTheme.text2
                                }

                                ForkText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, chipFlow.width - 24 - 14 - chipRow.spacing)
                                    kind: "body"
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
                                    text: chip.modelData.label
                                }
                            }
                        }
                    }
                }

                ForkText {
                    width: parent.width
                    kind: "help"
                    text: qsTr("Formatting and images need LuzLunar's Apollo build; other Apollo versions share text only. Apollo must give this device its Clipboard permissions.")
                }
            }
        }

        ForkTip {
            width: parent.width
            symbol: "lock.fill"
            symbolColor: ForkTheme.ok
            text: qsTr("Passwords copied from a password manager are never synced automatically.")
        }
    }
}
