# Fork-only sources and resources (anyosag/moonlight-qt), included from app.pro. See FORK.md.

# LuzLunar is macOS-only and its QML uses Qt 6.8 APIs (Popup.popupType), which would otherwise
# only fail at runtime
!versionAtLeast(QT_VERSION, 6.8.0) {
    error("LuzLunar needs Qt 6.8 or later (found $$QT_VERSION)")
}

# The build ID from scripts/fork/build-mac.sh (qmake FORK_BUILD_ID=...), shown in Settings
!isEmpty(FORK_BUILD_ID) {
    DEFINES += FORK_BUILD_ID=\\\"$$FORK_BUILD_ID\\\"
}

# Which CI run built this, and whether from master, for over-the-air updates (forkupdater.cpp)
!isEmpty(FORK_BUILD_RUN) {
    DEFINES += FORK_BUILD_RUN=$$FORK_BUILD_RUN
}
!isEmpty(FORK_BUILD_CHANNEL) {
    DEFINES += FORK_BUILD_CHANNEL=\\\"$$FORK_BUILD_CHANNEL\\\"
}

SOURCES += \
    $$PWD/apolloclient.cpp \
    $$PWD/clientdisplay.cpp \
    $$PWD/clienthardware.cpp \
    $$PWD/clipbundle.cpp \
    $$PWD/clipboardsync.cpp \
    $$PWD/clipfiles.cpp \
    $$PWD/forkaspect.cpp \
    $$PWD/forkaspectratios.cpp \
    $$PWD/forkevents.cpp \
    $$PWD/forkhostpower.cpp \
    $$PWD/forkhostupdates.cpp \
    $$PWD/forkhwrules.cpp \
    $$PWD/forkinput.cpp \
    $$PWD/forkkeymap.cpp \
    $$PWD/forklaunchargs.cpp \
    $$PWD/forklinkrules.cpp \
    $$PWD/forkmacshortcuts.cpp \
    $$PWD/forkmultitouch.cpp \
    $$PWD/forknetworklink.cpp \
    $$PWD/forkpolicy.cpp \
    $$PWD/forkpreferences.cpp \
    $$PWD/forkqml.cpp \
    $$PWD/forkstreamextensions.cpp \
    $$PWD/forksystemshortcuts.cpp \
    $$PWD/forktrackpad.cpp \
    $$PWD/forktrackpadgestures.cpp \
    $$PWD/forktrackpadpassthrough.cpp \
    $$PWD/forkupdater.cpp \
    $$PWD/forkupdaterules.cpp \
    $$PWD/forkvideoscaling.cpp \
    $$PWD/adaptivebitrate.cpp \
    $$PWD/bitraterules.cpp \
    $$PWD/hostpacing.cpp \
    $$PWD/macdrive.cpp \
    $$PWD/macdriverules.cpp \
    $$PWD/powernotice.cpp \
    $$PWD/sfsymbols.cpp \
    $$PWD/streamprofiles.cpp \
    $$PWD/streamstats.cpp \
    $$PWD/windowchrome.cpp

HEADERS += \
    $$PWD/apolloclient.h \
    $$PWD/clientdisplay.h \
    $$PWD/clienthardware.h \
    $$PWD/clipbundle.h \
    $$PWD/clipboardsync.h \
    $$PWD/clipfiles.h \
    $$PWD/forkaspect.h \
    $$PWD/forkaspectratios.h \
    $$PWD/forkevents.h \
    $$PWD/forkhostpower.h \
    $$PWD/forkhostupdates.h \
    $$PWD/forkhwrules.h \
    $$PWD/forkinput.h \
    $$PWD/forkkeymap.h \
    $$PWD/forklaunchargs.h \
    $$PWD/forklinkrules.h \
    $$PWD/forkmacshortcuts.h \
    $$PWD/forkmultitouch.h \
    $$PWD/forknetworklink.h \
    $$PWD/forkpolicy.h \
    $$PWD/forkpreferences.h \
    $$PWD/forkstreamextensions.h \
    $$PWD/forksystemshortcuts.h \
    $$PWD/forktrackpad.h \
    $$PWD/forktrackpadgestures.h \
    $$PWD/forktrackpadpassthrough.h \
    $$PWD/forkupdater.h \
    $$PWD/forkupdaterules.h \
    $$PWD/forkvideoscaling.h \
    $$PWD/hostcadence.h \
    $$PWD/hostpacing.h \
    $$PWD/luztouchpad.h \
    $$PWD/adaptivebitrate.h \
    $$PWD/bitraterules.h \
    $$PWD/macdrive.h \
    $$PWD/macdriverules.h \
    $$PWD/notchmenus.h \
    $$PWD/powernotice.h \
    $$PWD/sfsymbols.h \
    $$PWD/streamprofiles.h \
    $$PWD/streamstats.h \
    $$PWD/windowchrome.h \
    $$PWD/mac/displaytiming.h \
    $$PWD/mac/gesturesuppressor_mac.h \
    $$PWD/mac/macdrivesetup.h \
    $$PWD/mac/macintegration.h \
    $$PWD/mac/networklink.h \
    $$PWD/mac/notchbar.h \
    $$PWD/mac/notchmenus_mac.h \
    $$PWD/mac/pasteboard.h \
    $$PWD/mac/selfupdate_mac.h \
    $$PWD/mac/trackpadcapture_mac.h \
    $$PWD/updatekey.h

macx {
    SOURCES += \
        $$PWD/screenshotharness.cpp \
        $$PWD/mac/clienthardware_mac.mm \
        $$PWD/mac/displaytiming_mac.mm \
        $$PWD/mac/gesturesuppressor_mac.mm \
        $$PWD/mac/macdrivesetup_mac.mm \
        $$PWD/mac/macintegration.mm \
        $$PWD/mac/networklink_mac.mm \
        $$PWD/mac/notchbar.mm \
        $$PWD/mac/notchmenus_mac.mm \
        $$PWD/mac/pasteboard_mac.mm \
        $$PWD/mac/selfupdate_mac.mm \
        $$PWD/mac/sfsymbolprovider.mm \
        $$PWD/mac/trackpadcapture_mac.mm \
        $$PWD/mac/windowchrome_mac.mm

    # Rich clipboard sync: images through ImageIO, and zlib for the clipboard bundle (clipbundle.cpp)
    LIBS += -framework ImageIO -lz

    # Trackpad passthrough's gesture blocker: the event tap and the Accessibility check
    LIBS += -framework ApplicationServices

    # Over-the-air updates: the new build's code signature against this one's (mac/selfupdate_mac.mm)
    LIBS += -framework Security

    # The notch bar's link badge: the interface's kind and network, and Wi-Fi's rate (mac/networklink_mac.mm)
    LIBS += -framework SystemConfiguration -framework CoreWLAN

    # The Mac drive: the account and File Sharing's shares from the local directory (mac/macdrivesetup_mac.mm)
    LIBS += -framework OpenDirectory
    DEFINES += CLIPBUNDLE_WITH_ZLIB
}

RESOURCES += \
    $$PWD/fork.qrc
