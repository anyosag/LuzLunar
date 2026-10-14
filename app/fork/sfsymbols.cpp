#include "sfsymbols.h"

#include <QQmlEngine>
#include <QQuickImageProvider>

namespace
{
    const char* k_ProviderId = "sfsymbol";
}

ForkSfSymbols* ForkSfSymbols::get(QQmlEngine* engine)
{
    static ForkSfSymbols* instance = new ForkSfSymbols();

#ifdef Q_OS_DARWIN
    if (engine != nullptr && engine->imageProvider(k_ProviderId) == nullptr) {
        // The engine takes ownership
        engine->addImageProvider(k_ProviderId, createSfSymbolProvider());
    }
#else
    Q_UNUSED(engine);
#endif

    return instance;
}

bool ForkSfSymbols::isAvailable() const
{
#ifdef Q_OS_DARWIN
    return true;
#else
    return false;
#endif
}

QString ForkSfSymbols::url(const QString& symbolName) const
{
    return isAvailable() ? QStringLiteral("image://%1/%2").arg(k_ProviderId, symbolName) : QString();
}
