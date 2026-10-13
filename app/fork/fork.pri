# Fork-only sources and resources (anyosag/moonlight-qt), included from app.pro. See FORK.md.

SOURCES += \
    $$PWD/apolloclient.cpp \
    $$PWD/clipbundle.cpp \
    $$PWD/clipboardsync.cpp \
    $$PWD/forkinput.cpp \
    $$PWD/forkkeymap.cpp \
    $$PWD/forkpreferences.cpp \
    $$PWD/forkqml.cpp \
    $$PWD/forkstreamextensions.cpp \
    $$PWD/screenshotharness.cpp \
    $$PWD/sfsymbols.cpp \
    $$PWD/streamprofiles.cpp \
    $$PWD/streamstats.cpp \
    $$PWD/windowchrome.cpp

HEADERS += \
    $$PWD/apolloclient.h \
    $$PWD/clipbundle.h \
    $$PWD/clipboardsync.h \
    $$PWD/forkinput.h \
    $$PWD/forkkeymap.h \
    $$PWD/forkpreferences.h \
    $$PWD/forkstreamextensions.h \
    $$PWD/sfsymbols.h \
    $$PWD/streamprofiles.h \
    $$PWD/streamstats.h \
    $$PWD/windowchrome.h \
    $$PWD/mac/macintegration.h \
    $$PWD/mac/notchbar.h \
    $$PWD/mac/pasteboard.h

macx {
    SOURCES += \
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
