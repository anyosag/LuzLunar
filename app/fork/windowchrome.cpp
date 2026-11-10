#include "windowchrome.h"

#include <QGuiApplication>
#include <QScreen>

// The platform parts (attach, apply, zoomWindow and the destructor) are in mac/windowchrome_mac.mm on macOS (a different name, so qmake doesn't give both files the same object file)

ForkWindowChrome* ForkWindowChrome::get()
{
    static ForkWindowChrome* instance = new ForkWindowChrome();
    return instance;
}

bool ForkWindowChrome::isActive() const
{
    return m_Active;
}

QSize ForkWindowChrome::availableSize(QWindow* window) const
{
    QScreen* screen = window != nullptr ? window->screen() : nullptr;
    if (screen == nullptr) {
        screen = QGuiApplication::primaryScreen();
    }
    return screen != nullptr ? screen->availableGeometry().size() : QSize(1280, 900);
}

void ForkWindowChrome::setToolbarItems(const QVariantList&)
{
}

void ForkWindowChrome::setToolbarVisible(bool)
{
}

void ForkWindowChrome::setSubtitle(const QString&)
{
}

#ifndef Q_OS_DARWIN

ForkWindowChrome::~ForkWindowChrome()
{
}

void ForkWindowChrome::attach(QWindow* window)
{
    m_Window = window;
}

void ForkWindowChrome::zoomWindow(QWindow* window)
{
    if (window == nullptr) {
        return;
    }
    if (window->visibility() == QWindow::Maximized) {
        window->showNormal();
    }
    else {
        window->showMaximized();
    }
}

void ForkWindowChrome::apply()
{
}

bool ForkWindowChrome::reduceMotion()
{
    return false;
}

#endif
