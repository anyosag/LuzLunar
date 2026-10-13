# Fork-only sources and resources (anyosag/moonlight-qt), included from app.pro. See FORK.md.

SOURCES += \
    $$PWD/apolloclient.cpp \
    $$PWD/clipboardsync.cpp \
    $$PWD/forkinput.cpp \
    $$PWD/forkkeymap.cpp \
    $$PWD/forkpreferences.cpp \
    $$PWD/forkqml.cpp \
    $$PWD/forkstreamextensions.cpp \
    $$PWD/streamprofiles.cpp \
    $$PWD/streamstats.cpp

HEADERS += \
    $$PWD/apolloclient.h \
    $$PWD/clipboardsync.h \
    $$PWD/forkinput.h \
    $$PWD/forkkeymap.h \
    $$PWD/forkpreferences.h \
    $$PWD/forkstreamextensions.h \
    $$PWD/streamprofiles.h \
    $$PWD/streamstats.h \
    $$PWD/mac/macintegration.h \
    $$PWD/mac/notchbar.h

macx {
    SOURCES += \
        $$PWD/mac/macintegration.mm \
        $$PWD/mac/notchbar.mm
}

RESOURCES += \
    $$PWD/fork.qrc
