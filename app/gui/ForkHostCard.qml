import QtQuick

import ForkTheme 1.0

// [fork] A PC in Your PCs (PcView's tile): a screen showing its state, its name and status, and
// the action that fits (show its apps, pair, or wake it). The delegate around it keeps upstream's
// click, context menu and keyboard handling; the card only draws and forwards its buttons.
// Laid out top to bottom as in the design (padding 14 14 18, 16 between the blocks); the screen is
// a moon scene for the PC's state (the "PC status moons" design).
Rectangle {
    id: card

    property string name: ""
    property bool online: false
    property bool paired: false
    property bool busy: false          // the host is running an app
    property bool wakeable: false
    property bool waking: false        // a wake-up was sent and the PC isn't online yet
    property bool statusUnknown: false
    property bool serverSupported: true
    property string hostSoftware: ""   // "Apollo", "Sunshine"… for a paired PC (ComputerModel)
    property bool hostUpdate: false    // a newer Apollo build is out and this Mac may install it (ForkHostUpdates)
    property bool highlighted: false   // keyboard or gamepad focus
    property bool hovered: false

    // Upstream's onClicked: shows the apps, starts pairing, or opens the menu of an offline PC
    signal activate()
    signal wake()
    signal details()
    signal menu()

    readonly property bool asleep: !online && !statusUnknown

    radius: ForkTheme.radiusCard
    color: ForkTheme.surface
    border.width: highlighted ? 2 : 1
    border.color: highlighted ? ForkTheme.selEdge : (hovered ? ForkTheme.lineStrong : ForkTheme.line)

    Behavior on border.color {
        enabled: !ForkTheme.reduceMotion
        ColorAnimation { duration: 120 }
    }

    // The screen: a moon scene for the PC's state (ForkStatusScene)
    ForkStatusScene {
        id: screen
        x: 14
        y: 14
        width: parent.width - 28
        height: 150
        Accessible.ignored: true
        status: card.statusUnknown ? "checking"
              : !card.online ? (card.waking ? "waking" : (card.wakeable ? "asleep" : "offline"))
              : !card.serverSupported ? "unsupported"
              : !card.paired ? "unpaired"
              : card.busy ? "streaming"
              : "ready"
    }

    // Name, status and the menu, then the host software and pairing
    Column {
        id: info
        x: 18
        anchors.top: screen.bottom
        anchors.topMargin: 12
        width: parent.width - 36
        spacing: 0

        Item {
            width: parent.width
            height: 44

            ForkText {
                id: nameText
                anchors.left: parent.left
                anchors.right: statusRow.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                kind: "heading"
                font.pixelSize: 18
                elide: Text.ElideRight
                text: card.name
            }

            Row {
                id: statusRow
                anchors.right: moreButton.left
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 3.5
                    color: card.online ? ForkTheme.ok : "transparent"
                    border.width: card.online ? 0 : 1.5
                    border.color: ForkTheme.muted
                }

                ForkText {
                    kind: "body"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    wrapMode: Text.NoWrap
                    color: card.online ? ForkTheme.ok : ForkTheme.muted
                    text: card.statusUnknown ? qsTr("Checking")
                        : card.online ? qsTr("Online")
                        : card.waking ? qsTr("Waking") : qsTr("Offline")
                }
            }

            ForkButton {
                id: moreButton
                anchors.right: parent.right
                anchors.rightMargin: -10
                anchors.verticalCenter: parent.verticalCenter
                kind: "quiet"
                symbol: "ellipsis"
                symbolSize: 17
                focusPolicy: Qt.NoFocus
                Accessible.name: qsTr("More for %1").arg(card.name)
                onClicked: card.menu()
            }
        }

        ForkText {
            width: parent.width
            kind: "body"
            color: ForkTheme.muted
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            text: !card.serverSupported ? qsTr("Update the host to stream from it")
                : !card.paired ? qsTr("Found on your network · not paired")
                : card.hostSoftware !== "" && card.hostUpdate ? qsTr("%1 · update available").arg(card.hostSoftware)
                : card.hostSoftware !== "" ? qsTr("%1 · paired").arg(card.hostSoftware)
                : qsTr("Paired")
        }
    }

    // The action that fits; buttons don't take focus, so the grid keeps arrow-key navigation
    Row {
        x: 18
        anchors.top: info.bottom
        anchors.topMargin: 16
        width: parent.width - 36
        spacing: 8

        ForkButton {
            visible: card.online && card.paired
            width: parent.width
            kind: "primary"
            focusPolicy: Qt.NoFocus
            text: qsTr("Show apps")
            Accessible.description: card.name
            onClicked: card.activate()
        }

        ForkButton {
            visible: card.online && !card.paired
            width: parent.width
            kind: "strong"
            focusPolicy: Qt.NoFocus
            text: qsTr("Pair with this PC")
            Accessible.description: card.name
            onClicked: card.activate()
        }

        ForkButton {
            visible: !card.online
            width: parent.width - detailsButton.width - parent.spacing
            kind: "accent"
            symbol: "power"
            focusPolicy: Qt.NoFocus
            enabled: card.wakeable && !card.statusUnknown && !card.waking
            text: card.waking ? qsTr("Waking…") : qsTr("Wake PC")
            Accessible.description: card.name
            onClicked: card.wake()
        }

        ForkButton {
            id: detailsButton
            visible: !card.online
            focusPolicy: Qt.NoFocus
            text: qsTr("Details")
            Accessible.description: card.name
            onClicked: card.details()
        }
    }
}
