#pragma once

#include <QObject>

#include "forkkeymap.h"

// Settings added by this fork. Stored next to Moonlight's own settings under "fork/".
class ForkPreferences : public QObject
{
    Q_OBJECT

public:
    enum ModifierTarget {
        MT_NONE = ForkKeymap::TargetNone,
        MT_CTRL = ForkKeymap::TargetCtrl,
        MT_ALT = ForkKeymap::TargetAlt,
        MT_WIN = ForkKeymap::TargetWin,
    };
    Q_ENUM(ModifierTarget)

    enum ClipboardSyncMode {
        CSM_OFF,
        CSM_MANUAL,     // only with Ctrl+Option+Shift+U / G
        CSM_AUTOMATIC,  // also when the stream starts, gains and loses focus, and ends
    };
    Q_ENUM(ClipboardSyncMode)

    // What the Command (GUI), Control and Option (Alt) keys send to the host
    Q_PROPERTY(int commandKeyTarget READ commandKeyTarget WRITE setCommandKeyTarget NOTIFY keyTargetsChanged)
    Q_PROPERTY(int controlKeyTarget READ controlKeyTarget WRITE setControlKeyTarget NOTIFY keyTargetsChanged)
    Q_PROPERTY(int optionKeyTarget READ optionKeyTarget WRITE setOptionKeyTarget NOTIFY keyTargetsChanged)

    // Clipboard sync with Apollo hosts
    Q_PROPERTY(int clipboardSyncMode READ clipboardSyncMode WRITE setClipboardSyncMode NOTIFY clipboardSyncModeChanged)

    // The app name and stream stats beside the camera notch in fullscreen (macOS)
    Q_PROPERTY(bool notchBar READ notchBar WRITE setNotchBar NOTIFY notchBarChanged)

    // This build, like "6.2.0-fork.ee5b3ba" (not a preference; shown in Settings)
    Q_PROPERTY(QString buildId READ buildId CONSTANT)

    static ForkPreferences* get();

    QString buildId() const;

    int clipboardSyncMode() const { return m_ClipboardSyncMode; }
    void setClipboardSyncMode(int mode);

    bool notchBar() const { return m_NotchBar; }
    void setNotchBar(bool enabled);

    int commandKeyTarget() const { return m_KeyMap.target[ForkKeymap::PhysicalGui]; }
    int controlKeyTarget() const { return m_KeyMap.target[ForkKeymap::PhysicalCtrl]; }
    int optionKeyTarget() const { return m_KeyMap.target[ForkKeymap::PhysicalAlt]; }

    void setCommandKeyTarget(int target) { setKeyTarget(ForkKeymap::PhysicalGui, target); }
    void setControlKeyTarget(int target) { setKeyTarget(ForkKeymap::PhysicalCtrl, target); }
    void setOptionKeyTarget(int target) { setKeyTarget(ForkKeymap::PhysicalAlt, target); }

    const ForkKeymap::Map& keyMap() const { return m_KeyMap; }

signals:
    void keyTargetsChanged();
    void clipboardSyncModeChanged();
    void notchBarChanged();

private:
    explicit ForkPreferences(QObject* parent = nullptr);

    void setKeyTarget(ForkKeymap::Physical key, int target);

    ForkKeymap::Map m_KeyMap;
    int m_ClipboardSyncMode;
    bool m_NotchBar;
};
