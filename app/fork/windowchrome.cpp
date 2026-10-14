#include "windowchrome.h"

// The platform parts (attach, apply and the destructor) are in mac/windowchrome_mac.mm on macOS (a different name, so qmake doesn't give both files the same object file)

ForkWindowChrome* ForkWindowChrome::get()
{
    static ForkWindowChrome* instance = new ForkWindowChrome();
    return instance;
}

bool ForkWindowChrome::isActive() const
{
    return m_Active;
}

void ForkWindowChrome::setToolbarItems(const QVariantList& items)
{
    m_Items = items;
    apply();
}

void ForkWindowChrome::setToolbarVisible(bool visible)
{
    m_ToolbarVisible = visible;
    apply();
}

void ForkWindowChrome::setSubtitle(const QString& subtitle)
{
    m_Subtitle = subtitle;
    apply();
}

void ForkWindowChrome::notifyTriggered(const QString& id)
{
    emit triggered(id);
}

#ifndef Q_OS_DARWIN

ForkWindowChrome::~ForkWindowChrome()
{
}

void ForkWindowChrome::attach(QWindow* window)
{
    m_Window = window;
}

void ForkWindowChrome::apply()
{
}

#endif
