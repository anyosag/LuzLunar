import QtQuick

import ForkGroupLaunch 1.0
import ForkTheme 1.0

// [fork] The launch screen's card for a multi-display stream (ForkLaunchPanel): the displays as
// the Mac arranges them and what each one does, and, with DisplayExtend's display, where the
// iMac's picture comes from, measured before the stream connects (ForkGroupLaunch)
Rectangle {
    id: card

    implicitHeight: content.implicitHeight + 36
    radius: 16
    color: ForkTheme.surface
    border.color: ForkTheme.line

    // One of the two routes: chosen (gold), the reason it can't be used (warning colors), or
    // still being measured (a bar that fills with the check)
    component RouteCard: Rectangle {
        id: routeCard

        property var info: ({})
        readonly property bool chosen: info.chosen === true
        readonly property bool warn: info.warn === true
        readonly property string value: info.value || ""
        readonly property string detail: info.detail || ""
        readonly property string note: info.note || ""

        implicitHeight: routeColumn.implicitHeight + 24
        radius: 12
        color: warn ? ForkTheme.warnBg : chosen ? ForkTheme.raised : "transparent"
        border.width: chosen ? 1.5 : 1
        border.color: warn ? ForkTheme.warnLine : chosen ? ForkTheme.accentInk : ForkTheme.line

        Accessible.role: Accessible.StaticText
        Accessible.name: [info.title, chosen ? qsTr("chosen") : "", value, note, detail]
                         .filter(function(part) { return part }).join(", ")

        Column {
            id: routeColumn
            x: 14
            y: 12
            width: parent.width - 28
            spacing: 6

            Row {
                spacing: 8

                ForkSymbol {
                    visible: routeCard.chosen || routeCard.warn
                    anchors.verticalCenter: parent.verticalCenter
                    symbol: routeCard.warn ? "exclamationmark.triangle" : "checkmark.circle.fill"
                    size: 15
                    color: routeCard.warn ? ForkTheme.warnIcon : ForkTheme.accentInk
                }

                ForkText {
                    kind: "label"
                    pixelSize: 14
                    font.weight: Font.DemiBold
                    color: routeCard.warn ? ForkTheme.warnText
                         : routeCard.chosen || !ForkGroupLaunch.decided ? ForkTheme.text : ForkTheme.text2
                    text: routeCard.info.title || ""
                    Accessible.ignored: true
                }
            }

            ForkText {
                visible: routeCard.value !== ""
                kind: "titleSm"
                pixelSize: 20
                color: routeCard.chosen ? ForkTheme.accentInk : ForkTheme.text2
                text: routeCard.value
                Accessible.ignored: true
            }

            ForkText {
                visible: routeCard.note !== ""
                width: parent.width
                kind: "body"
                color: routeCard.warn ? ForkTheme.warnText : ForkTheme.text2
                text: routeCard.note
                Accessible.ignored: true
            }

            ForkText {
                visible: routeCard.detail !== ""
                width: parent.width
                kind: "mono"
                color: routeCard.warn ? ForkTheme.warnText : routeCard.chosen ? ForkTheme.text2 : ForkTheme.muted
                elide: Text.ElideRight
                text: routeCard.detail
                Accessible.ignored: true
            }

            Rectangle {
                visible: ForkGroupLaunch.checking
                width: parent.width
                height: 3
                radius: 2
                color: ForkTheme.line

                Rectangle {
                    width: parent.width * ForkGroupLaunch.progress
                    height: parent.height
                    radius: 2
                    color: ForkTheme.lineStrong

                    Behavior on width {
                        enabled: !ForkTheme.reduceMotion
                        NumberAnimation { duration: 250 }
                    }
                }
            }
        }
    }

    Column {
        id: content
        x: 20
        y: 18
        width: parent.width - 40
        spacing: 16

        // The arrangement, and what each display does
        Row {
            width: parent.width
            spacing: 24

            Item {
                id: figure
                anchors.verticalCenter: parent.verticalCenter
                width: ForkGroupLaunch.figureWidth
                height: ForkGroupLaunch.figureHeight
                Accessible.ignored: true

                Repeater {
                    model: ForkGroupLaunch.displays

                    delegate: Rectangle {
                        required property var modelData

                        x: modelData.x
                        y: modelData.y
                        width: modelData.w
                        height: modelData.h
                        radius: 5
                        color: ForkTheme.raised
                        border.width: 2
                        border.color: modelData.main ? ForkTheme.accentInk
                                    : modelData.external && !ForkGroupLaunch.decided ? ForkTheme.lineStrong : ForkTheme.text2

                        ForkText {
                            anchors.centerIn: parent
                            kind: "label"
                            pixelSize: 12
                            font.weight: Font.DemiBold
                            color: parent.modelData.main ? ForkTheme.accentInk : ForkTheme.text
                            text: parent.modelData.number
                        }
                    }
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - figure.width - parent.spacing
                spacing: 10

                Repeater {
                    model: ForkGroupLaunch.displays

                    delegate: Row {
                        required property var modelData

                        width: parent.width
                        spacing: 10

                        Accessible.role: Accessible.StaticText
                        Accessible.name: qsTr("Display %1: %2, %3").arg(modelData.number).arg(modelData.title).arg(modelData.subtitle)

                        ForkText {
                            width: 14
                            kind: "label"
                            pixelSize: 12
                            font.weight: Font.Bold
                            color: parent.modelData.main ? ForkTheme.accentInk : ForkTheme.text2
                            text: parent.modelData.number
                            Accessible.ignored: true
                        }

                        Column {
                            width: parent.width - 24
                            spacing: 2

                            ForkText {
                                width: parent.width
                                kind: "label"
                                pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                text: modelData.title
                                Accessible.ignored: true
                            }

                            ForkText {
                                width: parent.width
                                kind: "help"
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                                text: modelData.subtitle
                                Accessible.ignored: true
                            }
                        }
                    }
                }
            }
        }

        // Where the iMac's picture comes from
        Rectangle {
            visible: ForkGroupLaunch.showRoute
            width: parent.width
            height: 1
            color: ForkTheme.lineSoft
        }

        Column {
            visible: ForkGroupLaunch.showRoute
            width: parent.width
            spacing: 10

            ForkText {
                kind: "eyebrow"
                text: qsTr("The iMac's picture")
                Accessible.role: Accessible.Heading
            }

            Row {
                id: routes

                readonly property real cardHeight: Math.max(directCard.implicitHeight, viaCard.implicitHeight)

                width: parent.width
                spacing: 12

                RouteCard {
                    id: directCard
                    width: (routes.width - routes.spacing) / 2
                    height: routes.cardHeight
                    info: ForkGroupLaunch.directCard
                }

                RouteCard {
                    id: viaCard
                    width: (routes.width - routes.spacing) / 2
                    height: routes.cardHeight
                    info: ForkGroupLaunch.viaCard
                }
            }
        }
    }
}
