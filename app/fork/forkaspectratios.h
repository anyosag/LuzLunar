#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// The aspect ratio picker's data for QML (the AspectRatios singleton): the ratios to offer on a
// display, and the stream sizes of a ratio (forkaspect.*). Settings and the stream profile
// dialog use it to fill their resolution lists.
//
// A ratio is named by a key: "full" (the display's own shape; with a notch, the full panel
// including the strip beside the notch), "belowNotch" (the area below the notch), a standard
// ratio's own name like "16:9", or "custom". displayIndex is an index into
// ClientHardware.displays; one that doesn't exist leaves the display shapes out.
class AspectRatios : public QObject
{
    Q_OBJECT

public:
    static AspectRatios* get();

    // The display to start from: the built-in one if there is one, else the first
    Q_INVOKABLE int defaultDisplay() const;

    // Maps of key, label and ratio (width over height, 0 for "custom"), in the order to show:
    // the display's shapes ("Full display, with the notch area (1.54:1)" and "Below the notch
    // (16:10)" on a notched display, else "Native (16:9)"), then 16:10, 16:9, 21:9, 32:9, 4:3,
    // 3:2, 5:4 and 1:1 (leaving out one that a display shape already is), then "Custom ratio…"
    Q_INVOKABLE QVariantList ratios(int displayIndex = 0) const;

    // Maps of width, height, text and fills (the size that fills the display's box) for a ratio,
    // smallest first. customRatio is only used for the key "custom"; an empty list for a ratio
    // that makes no sense. The box a size is measured against: the display's own shape for
    // "full" and "belowNotch". For any other ratio, the area below the notch while the stream
    // would go there on a notched display (the notch bar or Stretch is on, or upstream's choice
    // for the window mode is a Space; see ForkPolicy::useSpacesFullscreen()), else the whole
    // panel.
    Q_INVOKABLE QVariantList presets(const QString& key, double customRatio, int displayIndex = 0) const;

    // The key of the ratio a saved size belongs to: a display shape first (ForkPolicy::notchFit,
    // at any scale), then a standard ratio within 1%, else "custom"
    Q_INVOKABLE QString keyFor(int width, int height, int displayIndex = 0) const;

    // Maps of width, height and rounded (true if either changed) for a size made even and
    // brought to 256..8192
    Q_INVOKABLE QVariantMap normalize(int width, int height) const;

    // The other side of a size with the ratio kept, even; 0 if the ratio makes no sense
    Q_INVOKABLE int linkedHeight(int width, double ratio) const;
    Q_INVOKABLE int linkedWidth(int height, double ratio) const;

    // "21:9" or "2.39:1" as a number; 0 if it isn't a ratio
    Q_INVOKABLE double parseRatio(const QString& text) const;

    // "16:9", "16:10", "21:9", "1.54:1": the name of a size's ratio (ForkHwRules::ratioLabel)
    Q_INVOKABLE QString ratioLabel(int width, int height) const;

private:
    explicit AspectRatios(QObject* parent = nullptr);
};
