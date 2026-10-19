import QtQuick
import QtQuick.Controls
import QtQuick.Window

import ForkPreferences 1.0
import ForkTheme 1.0
import SdlGamepadKeyNavigation 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0

// [fork] LuzLunar's Settings: a sidebar of sections, and the chosen section's cards. It takes
// the place of upstream's SettingsView, which stays in the repository unused (see FORK.md).
// Each section is its own file, ForkSettings<Name>.qml, loaded when it's picked; the sections
// can reach this page as settingsPage (its languageChanged signal and its section property).
FocusScope {
    id: settingsPage
    objectName: qsTr("Settings")

    // The section shown, one of the ids below
    property string section: "display"

    // Sent after the language changed and the texts were translated again, like upstream's
    // SettingsView. Lists that hold translated text rebuild themselves on it.
    signal languageChanged()

    readonly property var sections: [
        { "id": "display", "label": qsTr("Display"), "symbol": "display", "file": "ForkSettingsDisplay.qml" },
        { "id": "video", "label": qsTr("Video"), "symbol": "play.rectangle", "file": "ForkSettingsVideo.qml" },
        { "id": "audio", "label": qsTr("Audio"), "symbol": "speaker.wave.2", "file": "ForkSettingsAudio.qml" },
        { "id": "mouse", "label": qsTr("Mouse & trackpad"), "symbol": "computermouse", "file": "ForkSettingsMouse.qml" },
        { "id": "keyboard", "label": qsTr("Keyboard & Clipboard"), "symbol": "keyboard", "file": "ForkSettingsKeyboard.qml" },
        { "id": "gamepads", "label": qsTr("Gamepads"), "symbol": "gamecontroller", "file": "ForkSettingsGamepads.qml" },
        { "id": "host", "label": qsTr("Host & network"), "symbol": "server.rack", "file": "ForkSettingsHost.qml" },
        { "id": "app", "label": qsTr("App"), "symbol": "square.grid.2x2", "file": "ForkSettingsApp.qml" },
        { "id": "updates", "label": qsTr("Updates"), "symbol": "arrow.down.circle", "file": "ForkSettingsUpdates.qml" },
        { "id": "mac", "label": qsTr("This Mac"), "symbol": "laptopcomputer", "file": "ForkSettingsMac.qml", "darwinOnly": true }
    ]

    readonly property var visibleSections: sections.filter(function(entry) {
        return !entry.darwinOnly || SystemProperties.isDarwin
    })

    readonly property var current: {
        for (var i = 0; i < visibleSections.length; i++) {
            if (visibleSections[i].id === section) {
                return visibleSections[i]
            }
        }
        return visibleSections[0]
    }

    // The page's scroll position and how far it scrolls, for the screenshot harness
    property alias scrollY: content.contentY
    readonly property real scrollMax: Math.max(0, content.contentHeight - content.height)

    function showSection(id) {
        section = id
        content.contentY = 0
    }

    // Moves keyboard focus into the section's first control
    function focusContent() {
        if (sectionLoader.item) {
            var first = sectionLoader.item.nextItemInFocusChain(true)
            if (first) {
                first.forceActiveFocus(Qt.TabFocus)
            }
        }
    }

    StackView.onActivated: {
        // Gamepads move focus between the controls on this page
        SdlGamepadKeyNavigation.setUiNavMode(true)

        // Highlight the first section if a gamepad is connected
        if (SdlGamepadKeyNavigation.getConnectedGamepads() > 0 && navRepeater.count > 0) {
            navRepeater.itemAt(0).forceActiveFocus(Qt.TabFocus)
        }
    }

    StackView.onDeactivating: {
        SdlGamepadKeyNavigation.setUiNavMode(false)

        // Save the prefs so the Session can observe the changes
        StreamingPreferences.save()
    }

    Component.onDestruction: {
        // Also save on destruction: there's no deactivating callback when LuzLunar is just closed
        StreamingPreferences.save()
    }

    // Keeps the focused control in view, as upstream's SettingsView does
    NumberAnimation {
        id: autoScrollAnimation
        target: content
        property: "contentY"
        duration: 100
    }

    Window.onActiveFocusItemChanged: {
        var item = Window.activeFocusItem
        if (!item || !content.contentItem) {
            return
        }

        var inside = false
        for (var parentItem = item; parentItem; parentItem = parentItem.parent) {
            if (parentItem === content.contentItem) {
                inside = true
                break
            }
        }
        if (!inside) {
            return
        }

        var pos = item.mapToItem(content.contentItem, 0, 0)
        var margin = content.height > 100 ? 50 : 0
        if (pos.y - margin < content.contentY) {
            autoScrollAnimation.from = content.contentY
            autoScrollAnimation.to = Math.max(pos.y - margin, 0)
            autoScrollAnimation.start()
        }
        else if (pos.y + item.height + margin > content.contentY + content.height) {
            autoScrollAnimation.from = content.contentY
            autoScrollAnimation.to = Math.min(pos.y + item.height + margin - content.height,
                                              Math.max(0, content.contentHeight - content.height))
            autoScrollAnimation.start()
        }
    }

    // The sidebar and content are one block, centered in the window with equal margins: at most
    // ForkTheme.contentMaxWidth wide, and 24 from the window's edges when the window is narrower.
    // The page's scroll bar sits at the window's edge, so it never takes room from the block.
    readonly property real navWidth: 220
    readonly property real navGap: 28
    readonly property real blockWidth: Math.min(ForkTheme.contentMaxWidth, Math.max(0, width - 48))
    readonly property real blockX: (width - blockWidth) / 2
    readonly property real mainWidth: Math.max(0, blockWidth - navWidth - navGap)
    readonly property real topMargin: 28

    Item {
        id: sidebar
        x: settingsPage.blockX
        y: settingsPage.topMargin
        width: settingsPage.navWidth
        height: parent.height - 2 * settingsPage.topMargin

        Column {
            id: navColumn
            width: parent.width
            spacing: 4

            Repeater {
                id: navRepeater
                model: settingsPage.visibleSections

                delegate: ForkNavButton {
                    required property var modelData
                    required property int index

                    width: navColumn.width
                    text: modelData.label
                    symbol: modelData.symbol
                    current: modelData.id === settingsPage.current.id
                    focus: index === 0

                    onClicked: settingsPage.showSection(modelData.id)

                    Keys.onUpPressed: {
                        if (index > 0) {
                            navRepeater.itemAt(index - 1).forceActiveFocus(Qt.TabFocus)
                        }
                        else {
                            nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocus)
                        }
                    }
                    Keys.onDownPressed: {
                        if (index < navRepeater.count - 1) {
                            navRepeater.itemAt(index + 1).forceActiveFocus(Qt.TabFocus)
                        }
                    }
                    Keys.onRightPressed: {
                        settingsPage.showSection(modelData.id)
                        settingsPage.focusContent()
                    }
                    Keys.onReturnPressed: clicked()
                    Keys.onEnterPressed: clicked()
                }
            }
        }

        ForkText {
            anchors.top: navColumn.bottom
            anchors.topMargin: 16
            leftPadding: 12
            width: parent.width
            kind: "mono"
            font.pixelSize: 11
            color: ForkTheme.faint
            elide: Text.ElideRight
            text: qsTr("LuzLunar %1").arg(ForkPreferences.buildId)
        }
    }

    // The scrolling content runs from the block's content column to the window's right edge, so the
    // scroll bar is at the edge of the window; the column itself ends where the block does.
    Flickable {
        id: content
        x: settingsPage.blockX + settingsPage.navWidth + settingsPage.navGap
        width: parent.width - x
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        contentHeight: pageColumn.y + pageColumn.height + settingsPage.topMargin
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {}

        Column {
            id: pageColumn
            y: settingsPage.topMargin
            width: settingsPage.mainWidth
            spacing: ForkTheme.gap

            // The page title, and the action a section offers beside it (its headerAction)
            Item {
                width: parent.width
                height: Math.max(pageTitle.implicitHeight, actionLoader.height)

                ForkText {
                    id: pageTitle
                    anchors.left: parent.left
                    anchors.right: actionLoader.left
                    anchors.rightMargin: actionLoader.item ? 16 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "title"
                    elide: Text.ElideRight
                    text: settingsPage.current.label
                    Accessible.role: Accessible.Heading
                }

                // A section can offer one action for the title row, as "Check again" on This Mac:
                //   property Component headerAction: Component { ForkButton { ... } }
                Loader {
                    id: actionLoader
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: sectionLoader.item && sectionLoader.item.headerAction ? sectionLoader.item.headerAction : null
                }
            }

            Loader {
                id: sectionLoader
                width: parent.width
                source: settingsPage.current.file
            }
        }
    }
}
