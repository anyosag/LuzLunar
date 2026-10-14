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

SOURCES += \
    $$PWD/apolloclient.cpp \
    $$PWD/clienthardware.cpp \
    $$PWD/clipbundle.cpp \
    $$PWD/clipboardsync.cpp \
    $$PWD/forkaspect.cpp \
    $$PWD/forkaspectratios.cpp \
    $$PWD/forkhwrules.cpp \
    $$PWD/forkinput.cpp \
    $$PWD/forkkeymap.cpp \
    $$PWD/forkpolicy.cpp \
    $$PWD/forkpreferences.cpp \
    $$PWD/forkqml.cpp \
    $$PWD/forkstreamextensions.cpp \
    $$PWD/forkvideoscaling.cpp \
    $$PWD/sfsymbols.cpp \
    $$PWD/streamprofiles.cpp \
    $$PWD/streamstats.cpp \
    $$PWD/windowchrome.cpp

HEADERS += \
    $$PWD/apolloclient.h \
    $$PWD/clienthardware.h \
    $$PWD/clipbundle.h \
    $$PWD/clipboardsync.h \
    $$PWD/forkaspect.h \
    $$PWD/forkaspectratios.h \
    $$PWD/forkhwrules.h \
    $$PWD/forkinput.h \
    $$PWD/forkkeymap.h \
    $$PWD/forkpolicy.h \
    $$PWD/forkpreferences.h \
    $$PWD/forkstreamextensions.h \
    $$PWD/forkvideoscaling.h \
    $$PWD/sfsymbols.h \
    $$PWD/streamprofiles.h \
    $$PWD/streamstats.h \
    $$PWD/windowchrome.h \
    $$PWD/mac/macintegration.h \
    $$PWD/mac/notchbar.h \
    $$PWD/mac/pasteboard.h

macx {
    SOURCES += \
        $$PWD/screenshotharness.cpp \
        $$PWD/mac/clienthardware_mac.mm \
        $$PWD/mac/macintegration.mm \
        $$PWD/mac/notchbar.mm \
        $$PWD/mac/pasteboard_mac.mm \
        $$PWD/mac/sfsymbolprovider.mm \
        $$PWD/mac/windowchrome_mac.mm

    # Rich clipboard sync: images through ImageIO, and zlib for the clipboard bundle (clipbundle.cpp)
    LIBS += -framework ImageIO -lz
    DEFINES += CLIPBUNDLE_WITH_ZLIB
}

RESOURCES += \
    $$PWD/fork.qrc
