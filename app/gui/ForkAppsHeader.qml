import QtQuick
import QtQuick.Effects

import ForkTheme 1.0
import SfSymbols 1.0

// [fork] The top of a PC's app grid (AppView's header): the app that's running, with Resume and
// Quit, then the title, the count and a way to show the hidden apps. As wide as the grid's block
// (AppView sets the width), so its edges line up with the tiles.
Column {
    id: header

    property bool hasRunning: false
    property string runningName: ""
    property url runningBoxart
    // The running app's stream in one line, like "3024×1890 · 120 fps · HEVC 10-bit · Office profile"
    property string runningSummary: ""
    // Hidden apps are showing in the grid too
    property bool showingHidden: false
    // Apps that aren't hidden, and apps that are
    property int appCount: 0
    property int hiddenCount: 0

    signal resume()
    signal quit()
    signal toggleHidden()

    // The page rhythm: 36 above, 28 between the banner and the title, 20 to the grid
    spacing: 28
    topPadding: 36
    bottomPadding: 20

    Rectangle {
        id: banner
        visible: header.hasRunning
        width: header.width
        height: 106
        radius: ForkTheme.radiusCard
        color: ForkTheme.surface
        border.color: ForkTheme.line

        Accessible.role: Accessible.Grouping
        Accessible.name: qsTr("Now running: %1").arg(header.runningName)

        Item {
            id: thumb
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 112
            height: 76

            // The host's placeholder art has one of these sizes (as AppView checks)
            readonly property bool hasArt: {
                if (thumbImage.status !== Image.Ready) {
                    return false
                }
                var w = thumbImage.sourceSize.width
                var h = thumbImage.sourceSize.height
                return !((w === 130 && h === 180) || (w === 628 && h === 888) || (w === 200 && h === 266))
            }

            // Without real art (the host's placeholder, or none yet), a tile: a display for the
            // Desktop, otherwise the app's name
            Rectangle {
                anchors.fill: parent
                visible: !thumb.hasArt
                radius: 12
                color: ForkTheme.tile

                ForkSymbol {
                    anchors.centerIn: parent
                    visible: header.runningName === "Desktop" && SfSymbols.available
                    symbol: "display"
                    size: 30
                    color: ForkTheme.text2
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    visible: !(header.runningName === "Desktop" && SfSymbols.available)
                    text: header.runningName
                    textFormat: Text.PlainText
                    font.family: ForkTheme.uiFamily
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    color: ForkTheme.text2
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }

            // Real art, cropped to fill the landscape tile
            Image {
                id: thumbImage
                anchors.fill: parent
                source: header.runningBoxart
                fillMode: Image.PreserveAspectCrop
                // Drawn through the rounded mask below, or plainly where effects can't draw
                visible: thumb.hasArt && GraphicsInfo.api === GraphicsInfo.Software
                asynchronous: true
            }

            Rectangle {
                id: thumbMask
                anchors.fill: parent
                radius: 12
                visible: false
                layer.enabled: true
            }

            MultiEffect {
                visible: thumb.hasArt && GraphicsInfo.api !== GraphicsInfo.Software
                anchors.fill: parent
                source: thumbImage
                maskEnabled: true
                maskSource: thumbMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }

        Column {
            anchors.left: thumb.right
            anchors.leftMargin: 20
            anchors.right: buttons.left
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            ForkText {
                kind: "eyebrow"
                color: ForkTheme.ok
                text: qsTr("Now running")
            }

            ForkText {
                width: parent.width
                kind: "titleSm"
                elide: Text.ElideRight
                text: header.runningName
            }

            ForkText {
                width: parent.width
                kind: "mono"
                color: ForkTheme.muted
                elide: Text.ElideRight
                text: header.runningSummary
            }
        }

        Row {
            id: buttons
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            ForkButton {
                kind: "primary"
                symbol: "play.fill"
                symbolSize: 14
                focusPolicy: Qt.NoFocus
                text: qsTr("Resume")
                onClicked: header.resume()
            }

            ForkButton {
                symbol: "stop.fill"
                symbolSize: 12
                focusPolicy: Qt.NoFocus
                text: qsTr("Quit")
                onClicked: header.quit()
            }
        }
    }

    // "Apps", how many, and the link that shows or hides the hidden ones
    Item {
        width: header.width
        height: 44

        ForkText {
            id: heading
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            kind: "titleSm"
            pixelSize: 32
            text: qsTr("Apps")
            Accessible.role: Accessible.Heading
        }

        ForkText {
            id: countText
            anchors.left: heading.right
            anchors.leftMargin: 12
            anchors.baseline: heading.baseline
            kind: "body"
            pixelSize: 14
            color: ForkTheme.muted
            wrapMode: Text.NoWrap
            text: {
                var apps = header.appCount === 1 ? qsTr("1 app") : qsTr("%1 apps").arg(header.appCount)
                return header.hiddenCount > 0 ? apps + " · " + qsTr("%1 hidden").arg(header.hiddenCount) : apps
            }
        }

        ForkButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: header.hiddenCount > 0
            kind: "link"
            implicitHeight: 44
            font.pixelSize: 14
            focusPolicy: Qt.NoFocus
            text: header.showingHidden ? qsTr("Hide hidden apps") : qsTr("Show hidden apps")
            Accessible.checkable: true
            Accessible.checked: header.showingHidden
            onClicked: header.toggleHidden()
        }
    }
}
