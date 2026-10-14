#pragma once

#include <QObject>
#include <QPointer>
#include <QVariantList>
#include <QWindow>

// Native window chrome for the main window. On macOS 15 and later it gives the window a real
// NSToolbar, whose buttons are Liquid Glass on macOS 26, in place of the QML toolbar. QML
// describes the buttons (ForkNativeToolbar.qml) and gets a signal when one is clicked.
// Inactive everywhere else, so the QML toolbar stays.
class ForkWindowChrome : public QObject
{
    Q_OBJECT

    // True once the native toolbar is in place; the QML toolbar collapses while it is
    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)

public:
    static ForkWindowChrome* get();
    ~ForkWindowChrome();

    bool isActive() const;

    // Takes over the window's title bar. Call once, after the window is created.
    Q_INVOKABLE void attach(QWindow* window);

    // Each item is a map with id, symbol (SF Symbol name), label, toolTip, visible, focused (its
    // QML button has keyboard focus; highlighted natively) and, for back buttons, navigational.
    // Items keep the order of the first call.
    Q_INVOKABLE void setToolbarItems(const QVariantList& items);

    // Hides the toolbar while a stream starts or ends, like the QML toolbar
    Q_INVOKABLE void setToolbarVisible(bool visible);

    // Smaller second line under the window title
    Q_INVOKABLE void setSubtitle(const QString& subtitle);

    // Called by the platform code
    void notifyTriggered(const QString& id);

signals:
    void activeChanged();
    void triggered(const QString& id);

private:
    ForkWindowChrome() = default;

    void apply();

    QPointer<QWindow> m_Window;
    QVariantList m_Items;
    bool m_ToolbarVisible = true;
    QString m_Subtitle;
    bool m_Active = false;
    void* m_Platform = nullptr;   // ForkToolbarController on macOS
};
