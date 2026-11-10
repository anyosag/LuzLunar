#pragma once

#include <QObject>
#include <QPointer>
#include <QSize>
#include <QVariantList>
#include <QWindow>

// Native window chrome for the main window. The window draws its own 52 px header bar in QML
// (ForkWindowHeader.qml) under a transparent title bar, in a full-size content view, so on macOS this
// keeps the real traffic lights, puts them where the design has them (x 20, centred on y 25.5), hides
// the native title and separator, and zooms the window on a double click of the header like the
// title bar would. Also reports Reduce Motion. Off macOS it does nothing.
class ForkWindowChrome : public QObject
{
    Q_OBJECT

    // True once the native window is set up for the drawn header (macOS only). It no longer
    // stands for a native toolbar showing the buttons, so nothing in QML hides under it
    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)

    // The system's Reduce Motion accessibility setting (always false off macOS)
    Q_PROPERTY(bool reduceMotion READ reduceMotion NOTIFY reduceMotionChanged)

public:
    static ForkWindowChrome* get();
    ~ForkWindowChrome();

    bool isActive() const;
    bool reduceMotion();

    // Sets the window up for the drawn header. Call once, after the window is created.
    Q_INVOKABLE void attach(QWindow* window);

    // What a double click on the window's title bar does, per the user's setting (System Settings >
    // Desktop & Dock): zoom, minimize or nothing. Off macOS it toggles maximized.
    Q_INVOKABLE void zoomWindow(QWindow* window);

    // The free area (below the menu bar, beside the Dock) of the screen the window is on, in points;
    // the primary screen's if it has none yet. QML's Screen.desktopAvailable* is the union of all screens.
    Q_INVOKABLE QSize availableSize(QWindow* window) const;

    // The native toolbar is gone (the header is QML). These stay only for ForkNativeToolbar.qml,
    // which nothing loads any more, and do nothing.
    Q_INVOKABLE void setToolbarItems(const QVariantList& items);
    Q_INVOKABLE void setToolbarVisible(bool visible);
    Q_INVOKABLE void setSubtitle(const QString& subtitle);

signals:
    void activeChanged();
    void reduceMotionChanged();
    void triggered(const QString& id);

private:
    ForkWindowChrome() = default;

    void apply();

    QPointer<QWindow> m_Window;
    bool m_Active = false;
    void* m_Platform = nullptr;   // ForkChromeController on macOS
    void* m_MotionObserver = nullptr;
};
