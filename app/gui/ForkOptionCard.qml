import QtQuick

import ForkTheme 1.0
import QtQuick.Layouts
import QtQuick.Templates as T

// [fork] One option among several shown as cards (aspect ratios, codecs, speaker layouts...):
// a picture on top (or on the left with horizontal: true), then a title and subtitle. Put the
// picture in as the card's children. selected outlines it in gold; the caller sets the setting
// in onClicked:
//
//   ForkOptionCard {
//       title: qsTr("Stereo")
//       subtitle: qsTr("2 channels")
//       selected: StreamingPreferences.audioConfig === StreamingPreferences.AC_STEREO
//       onClicked: StreamingPreferences.audioConfig = StreamingPreferences.AC_STEREO
//       Rectangle { width: 60; height: 40 }   // the picture
//   }
//
// compact makes a one-line row with a radio dot and no picture (the resolution list).
T.AbstractButton {
    id: card

    property bool selected: false
    property string title: ""
    property string subtitle: ""
    property bool horizontal: false
    property bool compact: false
    // Mono titles, for sizes like 3024×1890
    property bool monoTitle: false
    // A radio ring before the title, for cards without a picture (the codecs)
    property bool radio: false
    default property alias content: picture.data
    // Items pinned to the bottom of the card, like a codec's hardware line
    property alias below: belowSlot.data

    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    padding: 14
    leftPadding: compact ? 12 : 14
    rightPadding: leftPadding
    topPadding: compact ? 8 : 14
    bottomPadding: topPadding
    opacity: enabled ? 1 : 0.45
    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    // A compact row is at least 52 high, so one-line and two-line rows line up
    implicitHeight: Math.max(compact ? 52 : 0, implicitContentHeight + topPadding + bottomPadding)

    Accessible.role: Accessible.RadioButton
    Accessible.checkable: true
    Accessible.checked: selected
    Accessible.name: title
    Accessible.description: subtitle

    background: Rectangle {
        radius: card.compact ? ForkTheme.radiusControl : ForkTheme.radiusTile
        color: card.selected ? ForkTheme.sel : (card.compact ? "transparent" : ForkTheme.surface)
        border.width: card.visualFocus ? 2 : 1.5
        border.color: card.selected || card.visualFocus ? ForkTheme.selEdge
                    : (card.hovered ? ForkTheme.lineStrong : ForkTheme.line)
    }

    contentItem: GridLayout {
        columns: card.horizontal || card.compact ? 2 : 1
        columnSpacing: card.compact ? 12 : 16
        rowSpacing: 10

        // The radio dot of a compact card
        Rectangle {
            visible: card.compact
            Layout.alignment: Qt.AlignVCenter
            width: 16
            height: 16
            radius: 8
            color: "transparent"
            border.width: 1.5
            border.color: card.selected ? ForkTheme.selEdge : ForkTheme.trackEdge

            Rectangle {
                anchors.centerIn: parent
                visible: card.selected
                width: 8
                height: 8
                radius: 4
                color: ForkTheme.selEdge
            }
        }

        Item {
            id: picture
            visible: !card.compact && children.length > 0
            Layout.alignment: card.horizontal ? Qt.AlignVCenter : Qt.AlignLeft | Qt.AlignTop
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }

        Column {
            Layout.fillWidth: true
            Layout.alignment: card.horizontal || card.compact ? Qt.AlignVCenter : Qt.AlignTop
            spacing: 3

            Row {
                width: parent.width
                spacing: 10

                Rectangle {
                    visible: card.radio
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    radius: 8
                    color: "transparent"
                    border.width: 1.5
                    border.color: card.selected ? ForkTheme.selEdge : ForkTheme.trackEdge

                    Rectangle {
                        anchors.centerIn: parent
                        visible: card.selected
                        width: 8
                        height: 8
                        radius: 4
                        color: ForkTheme.selEdge
                    }
                }

                ForkText {
                    width: parent.width - (card.radio ? 26 : 0)
                    kind: card.monoTitle ? "mono" : "heading"
                    font.pixelSize: card.monoTitle ? 14 : (card.compact ? 14 : 15)
                    text: card.title
                    elide: Text.ElideRight
                }
            }

            ForkText {
                width: parent.width
                visible: card.subtitle !== ""
                kind: "help"
                text: card.subtitle
            }
        }

        // A card stretched to its row's height keeps its picture and text at the top
        Item {
            visible: !card.horizontal && !card.compact
            Layout.fillHeight: true
        }

        Item {
            id: belowSlot
            visible: !card.compact && children.length > 0
            Layout.fillWidth: true
            implicitHeight: childrenRect.height
        }
    }
}
