# Fork-only sources and resources (anyosag/moonlight-qt), included from app.pro. See FORK.md.

SOURCES += \
    $$PWD/forkinput.cpp \
    $$PWD/forkkeymap.cpp \
    $$PWD/forkpreferences.cpp \
    $$PWD/forkqml.cpp \
    $$PWD/forkstreamextensions.cpp

HEADERS += \
    $$PWD/forkinput.h \
    $$PWD/forkkeymap.h \
    $$PWD/forkpreferences.h \
    $$PWD/forkstreamextensions.h \
    $$PWD/mac/macintegration.h

macx {
    SOURCES += \
        $$PWD/mac/macintegration.mm
}

RESOURCES += \
    $$PWD/fork.qrc
