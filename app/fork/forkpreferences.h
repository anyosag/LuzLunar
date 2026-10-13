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

    // What the Command (GUI), Control and Option (Alt) keys send to the host
    Q_PROPERTY(int commandKeyTarget READ commandKeyTarget WRITE setCommandKeyTarget NOTIFY keyTargetsChanged)
    Q_PROPERTY(int controlKeyTarget READ controlKeyTarget WRITE setControlKeyTarget NOTIFY keyTargetsChanged)
    Q_PROPERTY(int optionKeyTarget READ optionKeyTarget WRITE setOptionKeyTarget NOTIFY keyTargetsChanged)

    static ForkPreferences* get();

    int commandKeyTarget() const { return m_KeyMap.target[ForkKeymap::PhysicalGui]; }
    int controlKeyTarget() const { return m_KeyMap.target[ForkKeymap::PhysicalCtrl]; }
    int optionKeyTarget() const { return m_KeyMap.target[ForkKeymap::PhysicalAlt]; }

    void setCommandKeyTarget(int target) { setKeyTarget(ForkKeymap::PhysicalGui, target); }
    void setControlKeyTarget(int target) { setKeyTarget(ForkKeymap::PhysicalCtrl, target); }
    void setOptionKeyTarget(int target) { setKeyTarget(ForkKeymap::PhysicalAlt, target); }

    const ForkKeymap::Map& keyMap() const { return m_KeyMap; }

signals:
    void keyTargetsChanged();

private:
    explicit ForkPreferences(QObject* parent = nullptr);

    void setKeyTarget(ForkKeymap::Physical key, int target);

    ForkKeymap::Map m_KeyMap;
};
