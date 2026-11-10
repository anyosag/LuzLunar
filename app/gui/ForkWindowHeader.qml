// [fork] The window's 52 px header bar, drawn in the window content under the transparent macOS
// title bar (sky-chrome.md §5). It sits on glass over the sky and has three variants:
//   "pcs"   LuzLunar's moon and name, the View-as control, Add PC, and the Help / Settings capsule
//   "apps"  the "‹ Your PCs" back pill and the apps search field (All apps)
//   "back"  the back pill and the page's title, Help (Settings, which the canvas doesn't cover)
// The real traffic lights are macOS's own, at x 20 / 40 / 60 with their centres on y 25.5; this bar
// only leaves their place free (three discs are drawn there when `fakeLights` is set, for
// screenshots). Empty areas drag the window; a double click zooms it (zoomRequested).
// main.qml feeds it from the current page (contract-chrome.md).
import QtQuick
import QtQuick.Controls

import ForkTheme 1.0

Item {
    id: root

    property string variant: "pcs"
    // "carousel" or "grid"
    property string viewMode: "carousel"
    // View-as shows only when there are PCs
    property bool hasPcs: true
    // The first-run page's bar: opaque, as on the Empty board
    property bool opaque: false
    // The label of the back pill (the page's forkBackTitle)
    property string backTitle: qsTr("Your PCs")
    // The title beside the back pill in the "back" variant
    property string pageTitle: ""
    property string searchPlaceholder: qsTr("Search apps")
    property string searchAccessibleName: qsTr("Search apps")
    property alias searchText: searchField.text
    // An update is ready to install (the "Update" pill)
    property bool updateReady: false
    property bool discordVisible: false
    // Tooltips, with their shortcuts
    property string addPcTip: qsTr("Add PC manually")
    property string helpTip: qsTr("Help")
    property string settingsTip: qsTr("Settings")
    property string updateTip: ""
    // The sky to blur behind the bar; null paints the flat glass
    property Item skySource: null
    // Draws the three traffic-light discs (offscreen screenshots have no native ones)
    property bool fakeLights: false
    // The native lights are there (not in full screen), so the content starts at x 96
    property bool lightsVisible: true

    signal viewModeRequested(string mode)
    signal addPcRequested()
    signal helpRequested()
    signal settingsRequested()
    signal updateRequested()
    signal discordRequested()
    signal backRequested()
    signal searchEdited(string text)
    // The header gives up the keyboard focus (Down, Escape, B on a gamepad)
    signal pageFocusRequested()
    signal zoomRequested()

    function focusSearch() {
        if (variant === "apps") {
            searchField.forceActiveFocus(Qt.ShortcutFocusReason)
            searchField.selectAll()
        }
    }

    readonly property real contentLeft: lightsVisible || fakeLights ? 96 : 20
    readonly property bool pcsOn: variant === "pcs"
    readonly property bool mainOn: variant !== "apps"
    readonly property bool backOn: variant !== "pcs"
    readonly property bool appsOn: variant === "apps"

    height: 52
    implicitHeight: 52

    Accessible.role: Accessible.ToolBar
    Accessible.name: qsTr("LuzLunar")

    // The bar's controls fade as the page changes (sky-chrome.md §5.8, §5.10, §7.3)
    component FxItem: Item {
        property bool shown: true
        property int inDelay: 180
        property int inMs: 280
        property int outMs: 160

        anchors.fill: parent
        opacity: shown ? 1 : 0
        visible: opacity > 0
        enabled: shown

        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation { duration: ForkTheme.reduceMotion || !parent.shown ? 0 : parent.inDelay }
                NumberAnimation {
                    duration: ForkTheme.reduceMotion ? 0 : (parent.shown ? parent.inMs : parent.outMs)
                    easing.type: Easing.Bezier
                    easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1]
                }
            }
        }
    }

    ForkWindowGlass {
        anchors.fill: parent
        skySource: root.skySource
        sourceY: 0
        edge: "top"
        opaque: root.opaque
    }

    // The bar's bottom line
    Rectangle {
        x: 0
        y: parent.height - 1
        width: parent.width
        height: 1
        color: ForkTheme.cv.line
    }

    // Drag the window by the empty bar; double click zooms it
    Item {
        anchors.fill: parent

        DragHandler {
            target: null
            acceptedButtons: Qt.LeftButton
            onActiveChanged: {
                if (active && root.Window.window) {
                    root.Window.window.startSystemMove()
                }
            }
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onDoubleTapped: root.zoomRequested()
        }
    }

    // Offscreen screenshots only
    Row {
        visible: root.fakeLights
        x: 20
        y: 19.5
        spacing: 8

        Repeater {
            model: ["#FF5F57", "#FEBC2E", "#28C840"]

            Rectangle {
                required property string modelData
                width: 12
                height: 12
                radius: 6
                color: modelData
            }
        }
    }

    // Your PCs: the moon and the name
    FxItem {
        shown: root.pcsOn
        inDelay: 180
        inMs: 280
        outMs: 160

        Item {
            x: root.contentLeft
            y: 17.5
            width: 80
            height: 16

            ForkPathIcon {
                // The crescent of the canvas's box-shadow moon, in its own 16 unit box
                size: 24
                path: "M13.435 13.87A8 8 0 1 1 6.565 0.13A8 8 0 0 0 13.435 13.87Z"
                color: ForkTheme.cv.gold
                filled: true
                stroked: false
            }

            Text {
                x: 24
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("LuzLunar")
                color: ForkTheme.cv.text
                font.family: ForkTheme.uiFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
                font.letterSpacing: -0.14
                textFormat: Text.PlainText
            }
        }
    }

    // The back pill (All apps, Settings)
    FxItem {
        shown: root.backOn
        inDelay: 140
        inMs: 280
        outMs: 160

        ForkWindowHeaderButton {
            id: backPill
            x: root.contentLeft
            y: 11
            text: root.backTitle
            iconName: "chevronLeft"
            iconSize: 17
            gap: 3
            leftPad: 8
            rightPad: 14
            radius: 15
            fillColor: ForkTheme.cv.glass
            borderColor: ForkTheme.cv.line
            Accessible.name: text
            ToolTip.visible: hovered
            ToolTip.delay: 1000
            ToolTip.timeout: 3000
            ToolTip.text: qsTr("Back")
            onClicked: root.backRequested()
        }

        Text {
            visible: root.variant === "back" && root.pageTitle !== ""
            x: backPill.x + backPill.width + 14
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -0.5
            text: root.pageTitle
            color: ForkTheme.cv.text
            font.family: ForkTheme.uiFamily
            font.pixelSize: 14
            font.weight: Font.DemiBold
            font.letterSpacing: -0.14
            textFormat: Text.PlainText
        }
    }

    // The apps search field (All apps)
    FxItem {
        shown: root.appsOn
        inDelay: 140
        inMs: 280
        outMs: 160

        Item {
            x: parent.width - 14 - width
            y: 11
            width: 260
            height: 30

            TextField {
                id: searchField
                anchors.fill: parent
                leftPadding: 31
                rightPadding: 30
                topPadding: 0
                bottomPadding: 0
                verticalAlignment: TextInput.AlignVCenter
                font.family: ForkTheme.uiFamily
                font.pixelSize: 13
                color: ForkTheme.cv.text
                placeholderText: root.searchPlaceholder
                placeholderTextColor: "#757575"
                selectionColor: ForkTheme.cv.menuHi
                selectedTextColor: "#FFFFFF"
                selectByMouse: true
                activeFocusOnTab: true
                Accessible.name: root.searchAccessibleName

                background: Rectangle {
                    radius: 8
                    color: ForkTheme.cv.glass
                    border.width: 1
                    border.color: ForkTheme.cv.line

                    Rectangle {
                        visible: searchField.visualFocus
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: 10
                        color: "transparent"
                        border.width: 2
                        border.color: ForkTheme.cv.gold
                    }
                }

                onTextEdited: root.searchEdited(text)

                Keys.onDownPressed: root.pageFocusRequested()
                Keys.onReturnPressed: root.pageFocusRequested()
                Keys.onEnterPressed: root.pageFocusRequested()
                Keys.onEscapePressed: function(event) {
                    if (text !== "") {
                        clear()
                        root.searchEdited("")
                    } else {
                        root.pageFocusRequested()
                    }
                }
            }

            ForkPathIcon {
                x: 10
                y: 8
                name: "search"
                size: 15
                color: ForkTheme.cv.muted
                // Ignores clicks: the field below takes them
                enabled: false
            }

            ForkWindowHeaderButton {
                visible: searchField.text !== ""
                x: parent.width - 5 - width
                y: 5
                contentWidth: 20
                contentHeight: 20
                radius: 10
                borderWidth: 0
                iconName: "close"
                iconSize: 11
                iconColor: ForkTheme.cv.text2
                fillColor: ForkTheme.cv.chip
                Accessible.name: qsTr("Clear the search")
                onClicked: {
                    searchField.clear()
                    root.searchEdited("")
                    searchField.forceActiveFocus()
                }
            }
        }
    }

    // The right side: Update, View as, Add PC, Help / Settings
    FxItem {
        shown: root.mainOn
        inDelay: 180
        inMs: 280
        outMs: 160

        Row {
            id: rightRow
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: (parent.height - 1 - height) / 2
            height: 30
            spacing: 12

            // An update is ready: LuzLunar's own, installed from Settings › Updates
            ForkWindowHeaderButton {
                visible: root.updateReady
                text: qsTr("Update")
                iconName: "update"
                iconSize: 15
                iconColor: ForkTheme.cv.gold
                leftPad: 11
                rightPad: 13
                gap: 6
                fillColor: ForkTheme.cv.glass
                borderColor: ForkTheme.cv.line
                Accessible.name: root.updateTip !== "" ? root.updateTip : text
                ToolTip.visible: hovered && root.updateTip !== ""
                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.text: root.updateTip
                onClicked: root.updateRequested()
            }

            ForkWindowHeaderButton {
                visible: root.variant === "back" && root.discordVisible
                text: qsTr("Discord")
                leftPad: 14
                rightPad: 14
                fillColor: ForkTheme.cv.glass
                borderColor: ForkTheme.cv.line
                ToolTip.visible: hovered
                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.text: qsTr("Join our community on Discord")
                onClicked: root.discordRequested()
            }

            // View as
            Rectangle {
                id: viewAs
                visible: root.pcsOn && root.hasPcs
                width: 68
                height: 30
                radius: 9
                color: ForkTheme.cv.chip
                border.width: 1
                border.color: ForkTheme.cv.line
                Accessible.role: Accessible.Grouping
                Accessible.name: qsTr("View as")

                Row {
                    x: 3
                    y: 3
                    spacing: 2

                    Repeater {
                        model: [
                            { mode: "carousel", label: qsTr("Carousel") },
                            { mode: "grid", label: qsTr("Grid") }
                        ]

                        ForkWindowHeaderButton {
                            required property var modelData
                            readonly property bool on: root.viewMode === modelData.mode

                            contentWidth: 30
                            contentHeight: 24
                            radius: 7
                            borderWidth: 0
                            checkable: true
                            checked: on
                            iconName: modelData.mode
                            iconSize: 16
                            iconColor: on ? ForkTheme.cv.text : ForkTheme.cv.muted
                            fillColor: on ? (ForkTheme.dark ? Qt.rgba(1, 1, 1, 0.16) : "#FFFFFF") : "transparent"
                            lift: on && !ForkTheme.dark
                            Accessible.name: modelData.label
                            ToolTip.visible: hovered
                            ToolTip.delay: 1000
                            ToolTip.timeout: 3000
                            ToolTip.text: modelData.label
                            onClicked: root.viewModeRequested(modelData.mode)
                        }
                    }
                }
            }

            ForkWindowHeaderButton {
                visible: root.pcsOn
                text: qsTr("Add PC")
                iconName: "plus"
                iconSize: 15
                leftPad: 11
                rightPad: 13
                gap: 6
                fillColor: ForkTheme.cv.glass
                borderColor: ForkTheme.cv.line
                Accessible.name: text
                ToolTip.visible: hovered
                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.text: root.addPcTip
                onClicked: root.addPcRequested()
            }

            // Help and Settings
            Rectangle {
                width: tools.width + 8
                height: 30
                radius: 15
                color: ForkTheme.cv.glass
                border.width: 1
                border.color: ForkTheme.cv.line

                Row {
                    id: tools
                    x: 4
                    y: 3
                    spacing: 2

                    ForkWindowHeaderButton {
                        contentWidth: 26
                        contentHeight: 24
                        radius: 12
                        borderWidth: 0
                        iconName: "help"
                        iconSize: 17
                        iconColor: ForkTheme.cv.text2
                        Accessible.name: qsTr("Help")
                        ToolTip.visible: hovered
                        ToolTip.delay: 1000
                        ToolTip.timeout: 3000
                        ToolTip.text: root.helpTip
                        onClicked: root.helpRequested()
                    }

                    ForkWindowHeaderButton {
                        visible: root.pcsOn
                        contentWidth: 26
                        contentHeight: 24
                        radius: 12
                        borderWidth: 0
                        iconName: "settings"
                        iconSize: 17
                        iconColor: ForkTheme.cv.text2
                        Accessible.name: qsTr("Settings")
                        ToolTip.visible: hovered
                        ToolTip.delay: 1000
                        ToolTip.timeout: 3000
                        ToolTip.text: root.settingsTip
                        onClicked: root.settingsRequested()
                    }
                }
            }
        }
    }

    // Keyboard and gamepad: B and Escape and Down leave the bar for the page; Y (Menu or Hangup)
    // opens Settings
    Keys.onDownPressed: root.pageFocusRequested()
    Keys.onEscapePressed: root.pageFocusRequested()
    Keys.onBackPressed: root.pageFocusRequested()
    Keys.onMenuPressed: root.settingsRequested()
    Keys.onHangupPressed: root.settingsRequested()
}
