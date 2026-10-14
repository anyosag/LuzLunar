#include "forkaspectratios.h"

#include <cmath>

#include "clienthardware.h"
#include "forkaspect.h"
#include "forkhwrules.h"
#include "forkpolicy.h"
#include "forkpreferences.h"
#include "settings/streamingpreferences.h"

namespace
{
    struct StandardRatio {
        const char* key;    // also the label
        double ratio;
    };

    // 21:9 is really 64:27 (2560x1080, 5120x2160), which 3440x1440 is within 1% of
    const StandardRatio k_Standard[] = {
        { "16:10", 16.0 / 10 },
        { "16:9", 16.0 / 9 },
        { "21:9", 64.0 / 27 },
        { "32:9", 32.0 / 9 },
        { "4:3", 4.0 / 3 },
        { "3:2", 3.0 / 2 },
        { "5:4", 5.0 / 4 },
        { "1:1", 1.0 },
    };

    // Two ratios this close are the same one
    const double k_Tolerance = 0.01;

    // One display's two shapes: the full panel and the area below the notch
    struct Shapes {
        bool valid = false;
        bool hasNotch = false;
        ForkAspect::Size full;
        ForkAspect::Size below;

        double fullRatio() const { return static_cast<double>(full.width) / full.height; }
        double belowRatio() const { return static_cast<double>(below.width) / below.height; }
    };

    Shapes shapesOf(int displayIndex)
    {
        Shapes shapes;
        QVariantList displays = ClientHardware::get()->displays();
        if (displayIndex < 0 || displayIndex >= displays.size()) {
            return shapes;
        }

        QVariantMap display = displays.at(displayIndex).toMap();
        shapes.full = { display.value("nativeWidth").toInt(), display.value("nativeHeight").toInt() };
        shapes.below = { display.value("safeWidth").toInt(), display.value("safeHeight").toInt() };
        if (shapes.below.width <= 0 || shapes.below.height <= 0) {
            shapes.below = shapes.full;
        }

        shapes.valid = shapes.full.width > 0 && shapes.full.height > 0;
        shapes.hasNotch = shapes.valid && display.value("hasNotch").toBool() &&
                          (shapes.below.width != shapes.full.width || shapes.below.height != shapes.full.height);
        return shapes;
    }

    bool sameRatio(double ratio, double other)
    {
        return std::fabs(ratio / other - 1) <= k_Tolerance;
    }

    double standardRatio(const QString& key)
    {
        for (const StandardRatio& standard : k_Standard) {
            if (key == QLatin1String(standard.key)) {
                return standard.ratio;
            }
        }
        return 0;
    }

    QString labelFor(const ForkAspect::Size& size)
    {
        return QString::fromStdString(ForkHwRules::ratioLabel(size.width, size.height));
    }

    QVariantMap entry(const QString& key, const QString& label, double ratio)
    {
        return QVariantMap { { "key", key }, { "label", label }, { "ratio", ratio } };
    }

    // Whether a stream whose ratio is neither of the display's shapes goes below the notch, in a
    // fullscreen Space, rather than under it. The same decision as ForkVideoScaling makes when
    // the stream starts.
    bool otherRatiosGoBelowNotch()
    {
        StreamingPreferences* prefs = StreamingPreferences::get();
        bool upstream = prefs->windowMode != StreamingPreferences::WM_FULLSCREEN;
        bool keepBelowNotch = ForkPreferences::get()->notchBar() || prefs->fullscreenStretch;
        return ForkPolicy::useSpacesFullscreen(upstream, true, keepBelowNotch, ForkPolicy::NotchFit::Other);
    }
}

AspectRatios* AspectRatios::get()
{
    static AspectRatios* s_Instance = new AspectRatios();
    return s_Instance;
}

AspectRatios::AspectRatios(QObject* parent)
    : QObject(parent)
{
}

int AspectRatios::defaultDisplay() const
{
    QVariantList displays = ClientHardware::get()->displays();
    for (int i = 0; i < displays.size(); i++) {
        if (displays.at(i).toMap().value("isBuiltin").toBool()) {
            return i;
        }
    }
    return 0;
}

QVariantList AspectRatios::ratios(int displayIndex) const
{
    QVariantList list;
    QList<double> shapeRatios;

    Shapes shapes = shapesOf(displayIndex);
    if (shapes.valid) {
        if (shapes.hasNotch) {
            list << entry("full", tr("Full display, with the notch area (%1)").arg(labelFor(shapes.full)), shapes.fullRatio());
            list << entry("belowNotch", tr("Below the notch (%1)").arg(labelFor(shapes.below)), shapes.belowRatio());
            shapeRatios << shapes.fullRatio() << shapes.belowRatio();
        }
        else {
            list << entry("full", tr("Native (%1)").arg(labelFor(shapes.full)), shapes.fullRatio());
            shapeRatios << shapes.fullRatio();
        }
    }

    // A standard ratio that a display shape already is stays out, so it isn't listed twice. The
    // shape's label names it, like "Below the notch (16:10)".
    for (const StandardRatio& standard : k_Standard) {
        bool isShape = false;
        for (double shapeRatio : shapeRatios) {
            isShape = isShape || sameRatio(standard.ratio, shapeRatio);
        }
        if (!isShape) {
            list << entry(QLatin1String(standard.key), QLatin1String(standard.key), standard.ratio);
        }
    }

    list << entry("custom", tr("Custom ratio…"), 0.0);
    return list;
}

QVariantList AspectRatios::presets(const QString& key, double customRatio, int displayIndex) const
{
    Shapes shapes = shapesOf(displayIndex);
    double ratio = 0;
    ForkAspect::Size box;

    if (key == QLatin1String("full") || key == QLatin1String("belowNotch")) {
        if (!shapes.valid) {
            return QVariantList();
        }
        box = key == QLatin1String("full") ? shapes.full : shapes.below;
        ratio = static_cast<double>(box.width) / box.height;
    }
    else {
        ratio = key == QLatin1String("custom") ? customRatio : standardRatio(key);
        if (shapes.valid) {
            // A typed ratio can still be one of the display's shapes, which fills that shape
            bool isFull = sameRatio(ratio, shapes.fullRatio());
            bool isBelow = shapes.hasNotch && sameRatio(ratio, shapes.belowRatio());
            bool below = isBelow || (shapes.hasNotch && !isFull && otherRatiosGoBelowNotch());
            box = below ? shapes.below : shapes.full;
        }
    }

    QVariantList list;
    for (const ForkAspect::Preset& preset : ForkAspect::presetsFor(ratio, box)) {
        QString text = preset.fillsDisplay ? tr("%1 × %2 (fills this display)") :
                       preset.largerThanDisplay ? tr("%1 × %2 (larger than this display)") :
                                                  tr("%1 × %2");
        list << QVariantMap {
            { "width", preset.width },
            { "height", preset.height },
            { "text", text.arg(preset.width).arg(preset.height) },
            { "fills", preset.fillsDisplay },
        };
    }
    return list;
}

QString AspectRatios::keyFor(int width, int height, int displayIndex) const
{
    if (width <= 0 || height <= 0) {
        return QStringLiteral("custom");
    }

    Shapes shapes = shapesOf(displayIndex);
    if (shapes.valid) {
        switch (ForkPolicy::notchFit(width, height, shapes.full.width, shapes.full.height,
                                     shapes.below.width, shapes.below.height, k_Tolerance)) {
        case ForkPolicy::NotchFit::FullDisplay:
            return QStringLiteral("full");
        case ForkPolicy::NotchFit::BelowNotch:
            return shapes.hasNotch ? QStringLiteral("belowNotch") : QStringLiteral("full");
        case ForkPolicy::NotchFit::Other:
            break;
        }
    }

    double ratio = static_cast<double>(width) / height;
    for (const StandardRatio& standard : k_Standard) {
        if (sameRatio(ratio, standard.ratio)) {
            return QLatin1String(standard.key);
        }
    }
    return QStringLiteral("custom");
}

QVariantMap AspectRatios::normalize(int width, int height) const
{
    ForkAspect::Size size = ForkAspect::normalize(width, height);
    return QVariantMap {
        { "width", size.width },
        { "height", size.height },
        { "rounded", size.width != width || size.height != height },
    };
}

int AspectRatios::linkedHeight(int width, double ratio) const
{
    return ForkAspect::linkedHeight(width, ratio);
}

int AspectRatios::linkedWidth(int height, double ratio) const
{
    return ForkAspect::linkedWidth(height, ratio);
}

double AspectRatios::parseRatio(const QString& text) const
{
    return ForkAspect::parseRatio(text.toStdString());
}

QString AspectRatios::ratioLabel(int width, int height) const
{
    return QString::fromStdString(ForkHwRules::ratioLabel(width, height));
}
