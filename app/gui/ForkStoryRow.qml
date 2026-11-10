// [fork] The left of Your PCs' heading: the time-of-day greeting with its crescent, the 42 px title
// whose letters rise in one by one, and one sentence per PC saying what it's doing, each name a
// link to its card and a running PC's sentence carrying a Resume pill (carousel.md §2.1-2.4).
import QtQuick
import QtQuick.Effects
import ForkTheme

Column {
    id: story

    // "Good night, Gonzalo" before upper-casing
    property string greeting: ""
    // [{ name, before, after, dot (color), action (label or ""), }]
    property var lines: []
    property bool intro: false
    signal pick(int index)
    signal act(int index)

    spacing: 6

    readonly property bool _dark: ForkTheme.dark
    readonly property color shadowColor: Qt.rgba(5 / 255, 7 / 255, 15 / 255, 0.75)

    // Greeting
    ForkStoryRise {
        active: story.intro
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
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: story.greeting
                font.family: ForkTheme.uiFamily
                font.pixelSize: 11.5
                font.weight: 700
                font.letterSpacing: 1.38
                font.capitalization: Font.AllUppercase
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
                    delay: 80 + index * 40
                    dy: 16
                    height: 48
                    Text {
                        text: modelData
                        height: 48
                        verticalAlignment: Text.AlignVCenter
                        font.family: ForkTheme.uiFamily
                        font.pixelSize: 42
                        font.weight: 750
                        font.letterSpacing: -1.26
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

    // Sentences
    ForkStoryRise {
        id: sentences
        active: story.intro
        delay: 420
        dy: 8
        width: story.width
        height: flow.height + 2
        Flow {
            id: flow
            y: 2
            width: parent.width
            spacing: 16
            Repeater {
                model: story.lines
                delegate: Item {
                    id: item
                    required property var modelData
                    required property int index
                    readonly property bool hasAction: modelData.action !== ""
                    width: itemRow.width
                    height: hasAction ? 24 : 22
                    Row {
                        id: itemRow
                        spacing: 7
                        height: parent.height
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7; height: 7; radius: 3.5
                            color: item.modelData.dot
                            Accessible.ignored: true
                        }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                visible: item.modelData.before !== ""
                                text: item.modelData.before
                                font.family: ForkTheme.uiFamily
                                font.pixelSize: 14
                                lineHeight: 22; lineHeightMode: Text.FixedHeight
                                color: ForkTheme.cv.text2
                            }
                            Item {
                                width: nameText.width
                                height: 22
                                Text {
                                    id: nameText
                                    text: item.modelData.name
                                    font.family: ForkTheme.uiFamily
                                    font.pixelSize: 14
                                    font.weight: 650
                                    lineHeight: 22; lineHeightMode: Text.FixedHeight
                                    color: ForkTheme.cv.text
                                }
                                Rectangle {
                                    x: 0
                                    y: nameText.baselineOffset + 4
                                    width: nameText.width; height: 1
                                    color: ForkTheme.cv.lineStrong
                                }
                                Accessible.role: Accessible.Link
                                Accessible.name: qsTr("Show %1").arg(item.modelData.name)
                                Accessible.onPressAction: story.pick(item.index)
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: story.pick(item.index)
                                }
                            }
                            Text {
                                visible: item.modelData.after !== ""
                                text: item.modelData.after
                                font.family: ForkTheme.uiFamily
                                font.pixelSize: 14
                                lineHeight: 22; lineHeightMode: Text.FixedHeight
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
                            Accessible.onPressAction: story.act(item.index)
                            Row {
                                id: pillRow
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5
                                ForkStoryGlyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    path: "M8 5.8v12.4L18.2 12z"
                                    size: 11; strokeWidth: 1.6; filled: true
                                    color: "#FFFFFF"
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: item.modelData.action
                                    font.family: ForkTheme.uiFamily
                                    font.pixelSize: 12
                                    font.weight: 600
                                    color: "#FFFFFF"
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: story.act(item.index)
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
