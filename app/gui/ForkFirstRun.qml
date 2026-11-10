pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Shapes
import ForkPcPrefs // [fork] screenshot runs use the geometry renderer (a hidden grab drops curve shapes)

import ForkTheme 1.0
import ComputerManager

// [fork] The first-run page (canvas board "First run: no PCs yet"): what Your PCs shows while no PC
// is known. The page content only, for the area between the header (52 px) and the footer (36 px);
// the window behind it is the plain ForkTheme.cv.bg (the shared sky is "none"). Rings with the moon
// and two dots, "Let's find your PC", the discovery pill, and two cards: add a PC by address, and
// the three steps to set one up.
Item {
    id: page

    // The address the last Add sent, for the page's "Found %1" toast (empty: "Found the PC")
    property string lastAddress: ""
    // The Apollo guide the second card links to
    property url setupUrl: "https://github.com/ClassicOldSong/Apollo"
    // Automatic discovery is running (the pill shows)
    property bool discovering: true

    // An address is letters, digits and . - _ : % [ ] (IPv6 and ports included), like Add PC's
    readonly property string trimmed: addressField.text.trim()
    readonly property bool addressValid: /^[A-Za-z0-9.\-_:%\[\]]+$/.test(trimmed)

    // Emitted after the address was handed to ComputerManager
    signal added(string address)

    // Header "Add PC" while this page shows
    function focusAddress() {
        addressField.forceActiveFocus()
    }

    function addAddress() {
        if (!addressValid) {
            addressField.forceActiveFocus()
            return
        }
        lastAddress = trimmed
        ComputerManager.addNewHostManually(trimmed)
        added(trimmed)
        addressField.clear()
    }

    readonly property bool dk: ForkTheme.dark
    readonly property var cv: ForkTheme.cv
    readonly property color greenRing: cv.discRing

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Find your PC")

    Item {
        id: column
        x: 64
        y: 44
        width: parent.width - 128
        height: parent.height - 44

        // Hero
        Item {
            id: hero
            width: 220; height: 220
            anchors.horizontalCenter: parent.horizontalCenter
            Accessible.ignored: true

            Rectangle {
                width: 220; height: 220; radius: 110; color: "transparent"
                border.width: 1; border.color: page.dk ? Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.08) : Qt.rgba(168 / 255, 114 / 255, 15 / 255, 0.10)
            }
            Rectangle {
                x: 30; y: 30; width: 160; height: 160; radius: 80; color: "transparent"
                border.width: 1; border.color: page.dk ? Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.16) : Qt.rgba(168 / 255, 114 / 255, 15 / 255, 0.18)
            }
            Rectangle {
                x: 58; y: 58; width: 104; height: 104; radius: 52
                color: page.dk ? Qt.rgba(94 / 255, 92 / 255, 230 / 255, 0.10) : Qt.rgba(88 / 255, 86 / 255, 214 / 255, 0.06)
            }
            ForkFirstRunGlow {
                anchors.centerIn: heroMoon
                radius: 27
                color: page.dk ? Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.22) : Qt.rgba(168 / 255, 114 / 255, 15 / 255, 0.12)
            }
            Rectangle {
                x: 58; y: 58; width: 104; height: 104; radius: 52; color: "transparent"
                border.width: 1; border.color: page.dk ? Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.30) : Qt.rgba(168 / 255, 114 / 255, 15 / 255, 0.30)
            }
            Item {
                id: heroMoon
                x: 84; y: 80; width: 54; height: 54
                Shape {
                    // the crescent: the 54 px circle minus itself moved (14, -7)
                    anchors.fill: parent
                    preferredRendererType: ForkPcPrefs.screenshotMode ? Shape.GeometryRenderer : Shape.CurveRenderer
                    ShapePath {
                        fillColor: page.cv.gold
                        strokeColor: "transparent"
                        PathSvg { path: "M45.556 46.613A27 27 0 1 1 22.444 0.387A27 27 0 0 0 45.556 46.613Z" }
                    }
                }
            }
            Rectangle { // the green dot with its halo
                x: 182.5; y: 62.5; width: 15; height: 15; radius: 7.5; color: page.greenRing
            }
            Rectangle { x: 186; y: 66; width: 7; height: 7; radius: 3.5; color: ForkTheme.st.green }
            Rectangle { x: 38; y: 168; width: 5; height: 5; radius: 2.5; color: page.cv.faint }
        }

        ForkCanvasText {
            id: heading
            y: 220 + 22
            width: parent.width; height: 40
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Let’s find your PC")
            color: page.cv.text
            px: 34
            weight: 700
            tracking: -0.748
            Accessible.role: Accessible.Heading
        }
        ForkCanvasText {
            id: blurb
            y: heading.y + 40 + 10
            width: Math.min(560, parent.width)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            lineHeightMode: Text.FixedHeight
            lineHeight: 22
            text: qsTr("LuzLunar looks for PCs running Apollo or Sunshine on your network. Yours shows up here as a card you can stream from.")
            color: page.cv.muted
            px: 15
        }

        Rectangle {
            id: pill
            visible: page.discovering
            y: blurb.y + blurb.height + 18
            anchors.horizontalCenter: parent.horizontalCenter
            height: 30; radius: 15
            width: 12 + 8 + 10 + pillText.implicitWidth + 14
            color: page.cv.chip
            Accessible.role: Accessible.StaticText
            Accessible.name: pillText.text
            Rectangle { x: 8; y: 7; width: 16; height: 16; radius: 8; color: page.greenRing }
            Rectangle { x: 12; y: 11; width: 8; height: 8; radius: 4; color: ForkTheme.st.green }
            ForkCanvasText {
                id: pillText
                x: 30; height: 30
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Looking on your network…")
                color: page.cv.muted
                px: 13
            }
        }

        // The two cards
        Item {
            id: cards
            y: (page.discovering ? pill.y + pill.height : blurb.y + blurb.height) + 34
            width: Math.min(900, parent.width)
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property real cardWidth: (width - 16) / 2
            readonly property real cardHeight: Math.max(addressColumn.implicitHeight, setupColumn.implicitHeight + 28) + 42
            height: cardHeight

            component Card: Item {
                width: cards.cardWidth
                height: cards.cardHeight
                Rectangle { anchors.fill: parent; radius: 18; color: page.cv.surface }
                Rectangle { anchors.fill: parent; radius: 18; color: "transparent"; border.width: 1; border.color: page.cv.line }
            }
            component CardTitle: Row {
                id: head
                property color tile
                property string iconPath
                property string title
                spacing: 10
                height: 32
                Rectangle {
                    width: 32; height: 32; radius: 9; color: head.tile
                    ForkPathIcon { anchors.centerIn: parent; size: 18; path: head.iconPath; color: "#FFFFFF"; strokeWidth: 1.8 }
                }
                ForkCanvasText {
                    height: 32
                    verticalAlignment: Text.AlignVCenter
                    text: head.title
                    color: page.cv.text
                    px: 16
                    weight: 650
                    Accessible.role: Accessible.Heading
                }
            }

            Card {
                x: 0
                Column {
                    id: addressColumn
                    x: 23; y: 21; width: parent.width - 46
                    spacing: 12
                    CardTitle {
                        tile: "#0A6CDB"
                        iconPath: "M12 3.5a5.5 5.5 0 0 1 5.5 5.5c0 4.2-5.5 11.5-5.5 11.5S6.5 13.2 6.5 9A5.5 5.5 0 0 1 12 3.5zM12 7.2a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6z"
                        title: qsTr("Know its address?")
                    }
                    ForkCanvasText {
                        height: 16
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("IP address or hostname")
                        color: page.cv.text2
                        px: 13
                        weight: 600
                    }
                    Row {
                        spacing: 8
                        height: 40
                        TextField {
                            id: addressField
                            width: addressColumn.width - 8 - addButton.width
                            height: 40
                            leftPadding: 12; rightPadding: 12; topPadding: 0; bottomPadding: 0
                            verticalAlignment: TextInput.AlignVCenter
                            placeholderText: qsTr("10.0.0.20 or gaming-pc.local")
                            placeholderTextColor: "#757575"
                            color: page.cv.text
                            selectionColor: page.cv.gold
                            selectedTextColor: "#1A1405"
                            font.family: ForkTheme.uiFamily
                            font.pointSize: 14 * 72 / (Screen.logicalPixelDensity > 0 ? Screen.logicalPixelDensity * 25.4 : 72)
                            selectByMouse: true
                            Accessible.name: qsTr("IP address or hostname")
                            Keys.onReturnPressed: page.addAddress()
                            Keys.onEnterPressed: page.addAddress()
                            background: Item {
                                Rectangle { anchors.fill: parent; radius: 10; color: page.cv.raised }
                                Rectangle {
                                    anchors.fill: parent; radius: 10; color: "transparent"; border.width: 1
                                    border.color: addressField.text !== "" && !page.addressValid ? ForkTheme.danger : page.cv.lineStrong
                                }
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: -2; radius: 12; color: "transparent"
                                    border.width: 2; border.color: ForkTheme.selEdge; visible: addressField.activeFocus
                                }
                            }
                        }
                        Rectangle {
                            id: addButton
                            width: addLabel.implicitWidth + 36; height: 40; radius: 10
                            color: page.dk ? "#F5C878" : "#F2BE5C"
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Add")
                            Accessible.onPressAction: page.addAddress()
                            Keys.onReturnPressed: page.addAddress()
                            Keys.onEnterPressed: page.addAddress()
                            Keys.onSpacePressed: page.addAddress()
                            ForkCanvasText {
                                id: addLabel
                                anchors.centerIn: parent
                                text: qsTr("Add")
                                color: "#1A1405"
                                px: 14
                                weight: 600
                            }
                            Rectangle { anchors.fill: parent; radius: 10; color: Qt.rgba(0, 0, 0, 0.12); visible: addTap.pressed }
                            Rectangle {
                                anchors.fill: parent; anchors.margins: -3; radius: 13; color: "transparent"
                                border.width: 2; border.color: ForkTheme.selEdge; visible: addButton.activeFocus
                            }
                            TapHandler { id: addTap; onTapped: page.addAddress() }
                        }
                    }
                    ForkCanvasText {
                        width: parent.width
                        height: 18
                        verticalAlignment: Text.AlignVCenter
                        text: addressField.text !== "" && !page.addressValid
                              ? qsTr("Use the PC's IP address or hostname: letters, digits, dots, colons and dashes.")
                              : qsTr("From outside your home, use its public address or a DDNS name.")
                        elide: addressField.text !== "" && !page.addressValid ? Text.ElideRight : Text.ElideNone
                        color: addressField.text !== "" && !page.addressValid ? ForkTheme.danger : page.cv.muted
                        px: 12.5
                    }
                }
            }

            Card {
                x: cards.cardWidth + 16
                Column {
                    id: setupColumn
                    x: 23; y: 21; width: parent.width - 46
                    spacing: 12
                    CardTitle {
                        tile: "#9B45D9"
                        iconPath: "M12 4v11M7.5 10.5 12 15l4.5-4.5M5 19.5h14"
                        title: qsTr("Setting up a new PC?")
                    }
                    Column {
                        spacing: 9
                        Repeater {
                            model: [qsTr("Install Apollo on the Windows PC."),
                                    qsTr("Connect it to the same network as this Mac."),
                                    qsTr("Pick its card here and pair with a PIN.")]
                            delegate: Row {
                                required property int index
                                required property string modelData
                                spacing: 10
                                height: 22
                                Rectangle {
                                    width: 22; height: 22; radius: 11; color: page.cv.chip
                                    ForkCanvasText {
                                        anchors.centerIn: parent
                                        text: index + 1
                                        color: page.cv.text
                                        px: 12
                                        weight: 700
                                    }
                                }
                                ForkCanvasText {
                                    height: 22
                                    verticalAlignment: Text.AlignVCenter
                                    text: modelData
                                    color: page.cv.text2
                                    px: 13
                                }
                            }
                        }
                    }
                }
                Row {
                    id: link
                    x: 23
                    y: parent.height - 21 - height
                    height: 16
                    spacing: 6
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Link
                    Accessible.name: qsTr("How to set up Apollo")
                    Accessible.onPressAction: Qt.openUrlExternally(page.setupUrl)
                    Keys.onReturnPressed: Qt.openUrlExternally(page.setupUrl)
                    Keys.onEnterPressed: Qt.openUrlExternally(page.setupUrl)
                    Keys.onSpacePressed: Qt.openUrlExternally(page.setupUrl)
                    ForkCanvasText {
                        height: 16
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("How to set up Apollo")
                        color: page.dk ? "#7DB7FF" : "#0062CC"
                        px: 13
                        weight: 600
                    }
                    ForkPathIcon {
                        y: 1
                        size: 14
                        path: "M9.5 5.5 16 12l-6.5 6.5"
                        strokeWidth: 2
                        color: page.dk ? "#7DB7FF" : "#0062CC"
                    }
                    Rectangle {
                        x: -4; y: -4; width: parent.width + 8; height: parent.height + 8; radius: 6
                        color: "transparent"; border.width: 2; border.color: ForkTheme.selEdge
                        visible: link.activeFocus
                    }
                    TapHandler { onTapped: Qt.openUrlExternally(page.setupUrl) }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
            }
        }
    }
}
