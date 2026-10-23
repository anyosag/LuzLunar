import QtQuick

import ForkPreferences 1.0
import ForkTheme 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0

// [fork] Settings › App: the language, how the app opens, what it shows while streaming, and its
// warnings and Discord status. The language list and what happens when it changes are upstream's
// SettingsView (UI Settings), and the notch bar is ForkSettingsGroupBox's.
Column {
    id: appSection

    spacing: ForkTheme.gap

    // Set when changing the language needs a restart (upstream shows a tooltip)
    property bool languageNeedsRestart: false

    // ---- General --------------------------------------------------------------------------

    ForkCard {
        title: qsTr("General")

        Flow {
            id: generalFlow
            width: parent.width
            spacing: 32

            Column {
                id: languageColumn
                width: Math.min(320, generalFlow.width)
                spacing: 10

                ForkText {
                    kind: "label"
                    font.weight: Font.DemiBold
                    text: qsTr("Language")
                }

                AutoResizingComboBox {
                    // ignore setting the index at first, and actually set it when the component is loaded
                    Component.onCompleted: {
                        var saved_language = StreamingPreferences.language
                        currentIndex = 0
                        for (var i = 0; i < languageListModel.count; i++) {
                            var el_language = languageListModel.get(i).val;
                            if (saved_language === el_language) {
                                currentIndex = i
                                break
                            }
                        }

                        activated(currentIndex)
                    }

                    id: languageComboBox
                    // At least 280 wide, as wide as the column allows
                    width: Math.min(parent.width, Math.max(280, implicitWidth))
                    textRole: "text"
                    Accessible.description: qsTr("Language")
                    model: ListModel {
                        id: languageListModel
                        ListElement {
                            text: qsTr("Automatic")
                            val: StreamingPreferences.LANG_AUTO
                        }
                        ListElement {
                            text: "Deutsch" // German
                            val: StreamingPreferences.LANG_DE
                        }
                        ListElement {
                            text: "English"
                            val: StreamingPreferences.LANG_EN
                        }
                        ListElement {
                            text: "Français" // French
                            val: StreamingPreferences.LANG_FR
                        }
                        ListElement {
                            text: "简体中文" // Simplified Chinese
                            val: StreamingPreferences.LANG_ZH_CN
                        }
                        ListElement {
                            text: "Norwegian Bokmål"
                            val: StreamingPreferences.LANG_NB_NO
                        }
                        ListElement {
                            text: "русский" // Russian
                            val: StreamingPreferences.LANG_RU
                        }
                        ListElement {
                            text: "Español" // Spanish
                            val: StreamingPreferences.LANG_ES
                        }
                        ListElement {
                            text: "日本語" // Japanese
                            val: StreamingPreferences.LANG_JA
                        }
                        ListElement {
                            text: "Tiếng Việt" // Vietnamese
                            val: StreamingPreferences.LANG_VI
                        }
                        ListElement {
                            text: "ภาษาไทย" // Thai
                            val: StreamingPreferences.LANG_TH
                        }
                        ListElement {
                            text: "한국어" // Korean
                            val: StreamingPreferences.LANG_KO
                        }
                        ListElement {
                            text: "Magyar" // Hungarian
                            val: StreamingPreferences.LANG_HU
                        }
                        ListElement {
                            text: "Nederlands" // Dutch
                            val: StreamingPreferences.LANG_NL
                        }
                        ListElement {
                            text: "Svenska" // Swedish
                            val: StreamingPreferences.LANG_SV
                        }
                        ListElement {
                            text: "Türkçe" // Turkish
                            val: StreamingPreferences.LANG_TR
                        }
                        /* ListElement {
                            text: "Українська" // Ukrainian
                            val: StreamingPreferences.LANG_UK
                        } */
                        ListElement {
                            text: "繁體中文" // Traditional Chinese
                            val: StreamingPreferences.LANG_ZH_TW
                        }
                        ListElement {
                            text: "Português" // Portuguese
                            val: StreamingPreferences.LANG_PT
                        }
                        ListElement {
                            text: "Português do Brasil" // Brazilian Portuguese
                            val: StreamingPreferences.LANG_PT_BR
                        }
                        ListElement {
                            text: "Ελληνικά" // Greek
                            val: StreamingPreferences.LANG_EL
                        }
                        ListElement {
                            text: "Italiano" // Italian
                            val: StreamingPreferences.LANG_IT
                        }
                        /* ListElement {
                            text: "हिन्दी, हिंदी" // Hindi
                            val: StreamingPreferences.LANG_HI
                        } */
                        ListElement {
                            text: "Język polski" // Polish
                            val: StreamingPreferences.LANG_PL
                        }
                        ListElement {
                            text: "Čeština" // Czech
                            val: StreamingPreferences.LANG_CS
                        }
                        /* ListElement {
                            text: "עִבְרִית" // Hebrew
                            val: StreamingPreferences.LANG_HE
                        } */
                        /* ListElement {
                            text: "کرمانجیی خواروو" // Central Kurdish
                            val: StreamingPreferences.LANG_CKB
                        } */
                        /* ListElement {
                            text: "Lietuvių kalba" // Lithuanian
                            val: StreamingPreferences.LANG_LT
                        } */
                        /* ListElement {
                            text: "Eesti" // Estonian
                            val: StreamingPreferences.LANG_ET
                        } */
                        ListElement {
                            text: "Български" // Bulgarian
                            val: StreamingPreferences.LANG_BG
                        }
                        /* ListElement {
                            text: "Esperanto"
                            val: StreamingPreferences.LANG_EO
                        } */
                        ListElement {
                            text: "தமிழ்" // Tamil
                            val: StreamingPreferences.LANG_TA
                        }
                    }
                    // ::onActivated must be used, as it only listens for when the index is changed by a human
                    onActivated : {
                        // Retranslating is expensive, so only do it if the language actually changed
                        var new_language = languageListModel.get(currentIndex).val
                        if (StreamingPreferences.language !== new_language) {
                            StreamingPreferences.language = languageListModel.get(currentIndex).val
                            if (!StreamingPreferences.retranslate()) {
                                appSection.languageNeedsRestart = true
                            }
                            else {
                                appSection.languageNeedsRestart = false

                                // Force the back operation to pop any AppView pages that exist.
                                // The AppView stops working after retranslate() for some reason.
                                window.clearOnBack = true

                                // Signal other controls to adjust their text
                                settingsPage.languageChanged()
                            }
                        }
                    }
                }

                ForkText {
                    visible: appSection.languageNeedsRestart
                    width: parent.width
                    kind: "help"
                    text: qsTr("You must restart LuzLunar for this change to take effect")
                }
            }

            Column {
                visible: SystemProperties.hasDesktopEnvironment
                spacing: 10

                ForkText {
                    kind: "label"
                    font.weight: Font.DemiBold
                    text: qsTr("When LuzLunar opens")
                }

                ForkSegmented {
                    accessibleName: qsTr("When LuzLunar opens")
                    options: [
                        { "value": StreamingPreferences.UI_WINDOWED, "label": qsTr("Windowed") },
                        { "value": StreamingPreferences.UI_MAXIMIZED, "label": qsTr("Maximized") },
                        { "value": StreamingPreferences.UI_FULLSCREEN, "label": qsTr("Fullscreen") }
                    ]
                    value: StreamingPreferences.uiDisplayMode
                    onActivated: (value) => StreamingPreferences.uiDisplayMode = value
                }
            }
        }
    }

    // ---- While streaming ------------------------------------------------------------------

    ForkCard {
        title: qsTr("While streaming")
        // The title sits close above the rows, which draw their own padding, and the card is 8
        // shorter below them (the design's rows cards)
        spacing: 8
        height: implicitHeight - 8

        Column {
            width: parent.width
            spacing: 0

            ForkSwitchRow {
                visible: SystemProperties.isDarwin
                showDivider: false
                label: qsTr("Notch bar")
                help: qsTr("On a MacBook with a camera notch, fullscreen streams show the app's name, stream stats, the bitrate and the battery in the strip beside the notch, each opening a menu. With the Mac trackpad, keep moving up past the top to reach them; while a game has the mouse, press ⌃⌥⇧N.")
                checked: ForkPreferences.notchBar
                onToggled: (on) => ForkPreferences.notchBar = on
            }

            // A picture of the strip: the app on the left of the notch, the stats on the right.
            // It depicts the screen, so it's black in both appearances.
            Item {
                visible: SystemProperties.isDarwin
                width: parent.width
                height: 30 + 14

                Rectangle {
                    width: parent.width
                    height: 30
                    radius: 8
                    color: "#000000"
                    border.color: ForkTheme.lineSoft
                    clip: true
                    opacity: ForkPreferences.notchBar ? 1 : 0.35
                    Accessible.ignored: true

                    Rectangle {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: appPill.implicitWidth + 16
                        height: 18
                        radius: 9
                        color: Qt.rgba(1, 1, 1, 0.1)

                        Row {
                            id: appPill
                            anchors.centerIn: parent
                            spacing: 5

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: ForkTheme.accent
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Desktop · Gaming PC")
                                textFormat: Text.PlainText
                                font.family: ForkTheme.uiFamily
                                font.pixelSize: 10
                                color: "#ECEEF6"
                            }
                        }
                    }

                    // The notch hangs from the top edge
                    Rectangle {
                        x: (parent.width - width) / 2
                        y: -1
                        width: 92
                        height: 30
                        topLeftRadius: 0
                        topRightRadius: 0
                        bottomLeftRadius: 8
                        bottomRightRadius: 8
                        color: "#000000"
                        border.color: "#2A2A2A"
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: statsText.implicitWidth + 16
                        height: 18
                        radius: 9
                        color: Qt.rgba(1, 1, 1, 0.1)

                        Text {
                            id: statsText
                            anchors.centerIn: parent
                            text: qsTr("120 fps · 4 ms · 80 Mb/s")
                            textFormat: Text.PlainText
                            font.family: ForkTheme.monoFamily
                            font.pixelSize: 10
                            color: "#ECEEF6"
                        }
                    }
                }
            }

            ForkSwitchRow {
                showDivider: SystemProperties.isDarwin
                label: qsTr("Show performance stats while streaming")
                help: qsTr("Control-Option-Shift-S shows or hides them at any time while streaming.")
                checked: StreamingPreferences.showPerformanceOverlay
                onToggled: (on) => StreamingPreferences.showPerformanceOverlay = on
            }

            ForkSwitchRow {
                label: qsTr("Keep the display awake while streaming")
                help: qsTr("Prevents the screensaver from starting or the display from going to sleep while streaming.")
                checked: StreamingPreferences.keepAwake
                onToggled: (on) => StreamingPreferences.keepAwake = on
            }
        }
    }

    // ---- Warnings and sharing -------------------------------------------------------------

    ForkCard {
        title: qsTr("Warnings & sharing")
        // The title sits close above the rows, which draw their own padding, and the card is 8
        // shorter below them (the design's rows cards)
        spacing: 8
        height: implicitHeight - 8

        Column {
            width: parent.width
            spacing: 0

            ForkSwitchRow {
                showDivider: false
                label: qsTr("Show connection quality warnings")
                checked: StreamingPreferences.connectionWarnings
                onToggled: (on) => StreamingPreferences.connectionWarnings = on
            }

            ForkSwitchRow {
                label: qsTr("Show configuration warnings")
                checked: StreamingPreferences.configurationWarnings
                onToggled: (on) => StreamingPreferences.configurationWarnings = on
            }

            ForkSwitchRow {
                visible: SystemProperties.hasDiscordIntegration
                label: qsTr("Discord Rich Presence integration")
                help: qsTr("Updates your Discord status to display the name of the game you're streaming.")
                checked: StreamingPreferences.richPresence
                onToggled: (on) => StreamingPreferences.richPresence = on
            }
        }
    }
}
