#include "forkpreferences.h"

#include <QSettings>

#define SER_KEYTARGETS "fork/keyTargets"

namespace
{
    // QSettings keys, indexed by ForkKeymap::Physical
    const char* const k_KeyTargetNames[] = { "control", "option", "command" };

    ForkKeymap::Map defaultKeyMap()
    {
#ifdef Q_OS_DARWIN
        // Make a Mac keyboard behave like a Windows one: Command does what Ctrl does on Windows,
        // and Control (the key in the Windows key's position) acts as the Windows key.
        return ForkKeymap::Map { { ForkKeymap::TargetWin, ForkKeymap::TargetAlt, ForkKeymap::TargetCtrl } };
#else
        return ForkKeymap::identity();
#endif
    }

    bool isValidTarget(int target)
    {
        return target >= ForkKeymap::TargetNone && target <= ForkKeymap::TargetWin;
    }
}

ForkPreferences* ForkPreferences::get()
{
    static ForkPreferences* s_Instance = new ForkPreferences();
    return s_Instance;
}

ForkPreferences::ForkPreferences(QObject* parent)
    : QObject(parent),
      m_KeyMap(defaultKeyMap())
{
    QSettings settings;

    settings.beginGroup(SER_KEYTARGETS);
    for (int key = ForkKeymap::PhysicalCtrl; key <= ForkKeymap::PhysicalGui; key++) {
        int target = settings.value(k_KeyTargetNames[key], m_KeyMap.target[key]).toInt();
        if (isValidTarget(target)) {
            m_KeyMap.target[key] = static_cast<ForkKeymap::Target>(target);
        }
    }
    settings.endGroup();
}

void ForkPreferences::setKeyTarget(ForkKeymap::Physical key, int target)
{
    if (!isValidTarget(target) || m_KeyMap.target[key] == target) {
        return;
    }

    m_KeyMap.target[key] = static_cast<ForkKeymap::Target>(target);

    QSettings settings;
    settings.beginGroup(SER_KEYTARGETS);
    settings.setValue(k_KeyTargetNames[key], target);
    settings.endGroup();

    emit keyTargetsChanged();
}
