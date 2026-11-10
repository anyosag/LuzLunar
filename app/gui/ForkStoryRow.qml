// [fork] The left of Your PCs' heading: the time-of-day greeting with its crescent, the 42 px title
// whose letters rise in one by one, and one sentence per state (a few PCs by name, many as "N PCs"), each
// a link to its card(s) and a running PC's sentence carrying a Resume pill (carousel.md §2.1-2.4).
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import ForkTheme

Column {
    id: story

    // "Good night, Gonzalo" before upper-casing
    property string greeting: ""
    // ForkStoryLines.build(): [{ names: [{ name, index }], count, label, tip, before, sep, after,
    // dot (color), action (label or ""), indexes }]
    property var lines: []
    property bool intro: false
    property bool instant: false
    signal pick(int index)
    signal act(int index)
    // An "N PCs" link: every slot of its sentence
    signal pickGroup(var indexes)

    spacing: 6

    // The sentences' line is as tall as its tallest item (the Resume pill), the others centered in it
    readonly property bool anyAction: {
        for (var i = 0; i < lines.length; i++) if (lines[i].action !== "") return true
        return false
    }

    readonly property bool _dark: ForkTheme.dark
    readonly property color shadowColor: Qt.rgba(5 / 255, 7 / 255, 15 / 255, 0.75)

    // Greeting
    ForkStoryRise {
        active: story.intro
        instant: story.instant
        delay: 0
        dy: 8
        height: 16
        Row {
            spacing: 8
            height: 16
            Canvas {
                id: crescent
                anchors.verticalCenter: parent.verticalCenter
                width: 12; height: 12
                property color ink: ForkTheme.st.gold
                onInkChanged: requestPaint()
                onPaint: {
                    var c = getContext("2d")
                    c.reset()
                    c.fillStyle = ink
                    c.beginPath(); c.arc(6, 6, 6, 0, Math.PI * 2); c.fill()
                    c.globalCompositeOperation = "destination-out"
                    c.beginPath(); c.arc(9, 4, 6, 0, Math.PI * 2); c.fill()
                }
                Accessible.ignored: true
            }
            ForkCanvasText {
                anchors.verticalCenter: parent.verticalCenter
                text: story.greeting
                px: 11.5
                weight: 700
                tracking: 1.38
                upper: true
                color: ForkTheme.st.gold
            }
        }
    }

    // Title, a letter at a time
    Item {
        id: title
        width: titleRow.width
        height: 48
        Accessible.role: Accessible.Heading
        Accessible.name: qsTr("Your PCs")

        Row {
            id: titleRow
            Repeater {
                model: ["Y", "o", "u", "r", " ", "P", "C", "s"]
                delegate: ForkStoryRise {
                    required property string modelData
                    required property int index
                    active: story.intro
        instant: story.instant
                    delay: 80 + index * 40
                    dy: 16
                    height: 48
                    ForkCanvasText {
                        text: modelData
                        height: 48
                        verticalAlignment: Text.AlignVCenter
                        px: 42
                        weight: 750
                        tracking: -1.26
                        color: ForkTheme.cv.text
                    }
                    Accessible.ignored: true
                }
            }
            layer.enabled: story._dark
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: story.shadowColor
                shadowBlur: 0.5
                shadowVerticalOffset: 2
                shadowOpacity: 1
                autoPaddingEnabled: true
            }
        }
    }

    // Sentences: one per state (ForkStoryLines.js). Flow has one spacing for both axes, so the 20 px
    // between sentences is 8 px of spacing plus 12 px of padding at the end of each item, and the
    // wrapped lines are 8 px apart.
    ForkStoryRise {
        id: sentences
        active: story.intro
        instant: story.instant
        delay: 420
        dy: 8
        width: story.width
        height: flow.height + 2
        Flow {
            id: flow
            y: 2
            width: parent.width + 12
            spacing: 8
            Repeater {
                model: story.lines
                delegate: Item {
                    id: item
                    required property var modelData
                    required property int index
                    readonly property bool hasAction: modelData.action !== ""
                    // A sentence's names, or the one "N PCs" link
                    readonly property var links: modelData.count > 0
                        ? [{ name: modelData.label, index: -1 }] : modelData.names
                    width: itemRow.width + 12
                    height: story.anyAction ? 24 : 22
                    Row {
                        id: itemRow
                        spacing: 7
                        height: item.height
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7; height: 7; radius: 3.5
                            color: item.modelData.dot
                            Accessible.ignored: true
                        }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            ForkCanvasText {
                                visible: item.modelData.before !== ""
                                text: item.modelData.before
                                px: 14
                                lineHeightPx: 22
                                color: ForkTheme.cv.text2
                            }
                            Repeater {
                                model: item.links
                                delegate: Row {
                                    id: linkRow
                                    required property var modelData
                                    required property int index
                                    readonly property bool isGroup: item.modelData.count > 0
                                    function go() {
                                        if (isGroup) story.pickGroup(item.modelData.indexes)
                                        else story.pick(modelData.index)
                                    }
                                    ForkCanvasText {
                                        visible: linkRow.index > 0
                                        text: item.modelData.sep
                                        px: 14
                                        lineHeightPx: 22
                                        color: ForkTheme.cv.text2
                                    }
                                    Item {
                                        id: link
                                        width: Math.ceil(nameText.contentWidth)
                                        height: 22
                                        ForkCanvasText {
                                            id: nameText
                                            width: Math.min(implicitWidth, 200)
                                            text: linkRow.modelData.name
                                            elide: Text.ElideRight
                                            px: 14
                                            weight: 650
                                            lineHeightPx: 22
                                            color: ForkTheme.cv.text
                                        }
                                        Rectangle {
                                            x: 0
                                            y: nameText.baselineOffset + 4
                                            width: link.width; height: 1
                                            color: ForkTheme.cv.lineStrong
                                        }
                                        Accessible.role: Accessible.Link
                                        Accessible.name: qsTr("Show %1").arg(linkRow.modelData.name)
                                        Accessible.onPressAction: linkRow.go()
                                        MouseArea {
                                            id: linkMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: linkRow.go()
                                        }
                                        ToolTip {
                                            visible: linkMouse.containsMouse && text !== ""
                                            delay: 500
                                            text: linkRow.isGroup ? item.modelData.tip
                                                : (nameText.truncated ? linkRow.modelData.name : "")
                                        }
                                    }
                                }
                            }
                            ForkCanvasText {
                                visible: item.modelData.after !== ""
                                text: item.modelData.after
                                px: 14
                                lineHeightPx: 22
                                color: ForkTheme.cv.text2
                            }
                        }
                        Rectangle {
                            visible: item.hasAction
                            anchors.verticalCenter: parent.verticalCenter
                            height: 24
                            width: pillRow.width + 18
                            radius: 12
                            color: ForkTheme.cv.menuHi
                            Accessible.role: Accessible.Button
                            Accessible.name: item.modelData.action
                            Accessible.onPressAction: story.act(item.modelData.indexes[0])
                            Row {
                                id: pillRow
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5
                                ForkPathIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "play"
                                    size: 11; strokeWidth: 1.6; filled: true
                                    color: "#FFFFFF"
                                }
                                ForkCanvasText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: item.modelData.action
                                    px: 12
                                    weight: 600
                                    color: "#FFFFFF"
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: story.act(item.modelData.indexes[0])
                            }
                        }
                    }
                }
            }
            layer.enabled: story._dark
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: story.shadowColor
                shadowBlur: 0.5
                shadowVerticalOffset: 2
                shadowOpacity: 1
                autoPaddingEnabled: true
            }
        }
    }
}
