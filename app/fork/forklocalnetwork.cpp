#include "forklocalnetwork.h"

#include <vector>

#include <QCoreApplication>
#include <QDebug>
#include <QDesktopServices>
#include <QGuiApplication>
#include <QReadLocker>
#include <QThreadPool>
#include <QUrl>

#include "backend/computermanager.h"
#include "mac/networklink.h"

using LocalNetworkRules::Access;

namespace
{
    // Bonjour's IPv4 group: local on any network, so it's checked even with no PC at home
    const char k_BonjourGroup[] = "224.0.0.251";
}

ForkLocalNetwork::ForkLocalNetwork()
{
    m_Timer.setSingleShot(true);
    connect(&m_Timer, &QTimer::timeout, this, &ForkLocalNetwork::checkNow);
}

ForkLocalNetwork* ForkLocalNetwork::get()
{
    static ForkLocalNetwork* s_Instance = new ForkLocalNetwork();
    return s_Instance;
}

void ForkLocalNetwork::attach(ComputerManager* manager)
{
    // A screenshot run has no real PCs and checks nothing
    if (!m_Manager.isNull() || manager == nullptr || qEnvironmentVariableIsSet("LUZLUNAR_SCREENSHOTS")) {
        return;
    }
    m_Manager = manager;
    connect(qGuiApp, &QGuiApplication::applicationStateChanged, this, &ForkLocalNetwork::handleApplicationState);
    // Soon after the window is up, so after an update macOS's own alert, if it asks, comes while
    // you're there
    QTimer::singleShot(1500, this, &ForkLocalNetwork::checkNow);
}

void ForkLocalNetwork::noteJustUpdated()
{
    m_JustUpdated = true;
}

// Back in front, as from System Settings: check at once
void ForkLocalNetwork::handleApplicationState(Qt::ApplicationState state)
{
    if (state == Qt::ApplicationActive) {
        checkNow();
    }
    else {
        m_Timer.stop();
    }
}

void ForkLocalNetwork::scheduleNext()
{
    if (QGuiApplication::applicationState() == Qt::ApplicationActive) {
        m_Timer.start(LocalNetworkRules::recheckSeconds(m_Access) * 1000);
    }
}

void ForkLocalNetwork::checkNow()
{
    if (m_Manager.isNull() || m_Checking || QGuiApplication::applicationState() != Qt::ApplicationActive) {
        return;
    }
    m_Timer.stop();

    QStringList targets{QString::fromLatin1(k_BonjourGroup)};
    for (NvComputer* computer : m_Manager->getComputers()) {
        QReadLocker lock(&computer->lock);
        if (!computer->localAddress.isNull()) {
            targets.append(computer->localAddress.address());
        }
    }
    targets.removeDuplicates();

    m_Checking = true;
    QPointer<ForkLocalNetwork> self(this);
    QThreadPool::globalInstance()->start([self, targets]() {
        std::vector<LocalNetworkRules::Check> checks;
        QString refused;
        int error = 0;
        QStringList reachable;
        for (const QString& target : targets) {
            // A PC's LAN address is numeric (serverinfo's LocalIP, or Bonjour's answer)
            const std::string address = MacNetworkLink::numericAddress(target.toStdString());
            MacNetworkLink::LocalCheck result = MacNetworkLink::checkLocal(address);
            LocalNetworkRules::Check check;
            check.local = result.local;
            check.connected = result.connected;
            checks.push_back(check);
            if (result.local && !result.connected && refused.isEmpty()) {
                refused = QString::fromStdString(address);
                error = result.error;
            }
            if (result.local && result.connected) {
                reachable.append(target);
            }
        }
        const Access access = LocalNetworkRules::combine(checks);
        QMetaObject::invokeMethod(qApp, [self, access, refused, error, reachable]() {
            if (!self.isNull()) {
                self->finished(access, refused, error, reachable);
            }
        }, Qt::QueuedConnection);
    });
}

void ForkLocalNetwork::finished(Access access, const QString& refused, int error, const QStringList& reachable)
{
    m_Checking = false;
    const Access before = m_Access;
    m_Access = access;
    if (access != before) {
        qInfo().noquote() << QString::fromStdString(LocalNetworkRules::logLine(access, refused.toStdString(), error));
        emit changed();
    }

    switch (LocalNetworkRules::notice(before, access, m_BlockedTold, m_JustUpdated)) {
    case LocalNetworkRules::Notice::Blocked:
        m_BlockedTold = true;
        emit notice(tr("macOS blocks LuzLunar's Local Network access, so streams go through your router"));
        break;
    case LocalNetworkRules::Notice::BlockedAfterUpdate:
        m_BlockedTold = true;
        emit notice(tr("After the update, turn LuzLunar on again in Privacy & Security › Local Network"));
        break;
    case LocalNetworkRules::Notice::Restored:
        emit notice(tr("LuzLunar can use your local network again"));
        break;
    case LocalNetworkRules::Notice::None:
        break;
    }
    // The first check that could tell is the update's
    if (access != Access::Unknown) {
        m_JustUpdated = false;
    }

    moveToLan(before, reachable);
    scheduleNext();
}

// As when Bonjour finds a PC: its serverinfo from its LAN address, which then becomes the address
// it's polled at (ComputerManager's mDNS path)
void ForkLocalNetwork::moveToLan(Access before, const QStringList& reachable)
{
    if (m_Manager.isNull()) {
        return;
    }
    for (NvComputer* computer : m_Manager->getComputers()) {
        NvAddress lanAddress;
        QString name;
        bool online, activeIsLan;
        {
            QReadLocker lock(&computer->lock);
            lanAddress = computer->localAddress;
            name = computer->name;
            online = computer->state == NvComputer::CS_ONLINE;
            activeIsLan = !computer->activeAddress.isNull() && computer->activeAddress == computer->localAddress;
        }
        const bool lanLocal = !lanAddress.isNull() && reachable.contains(lanAddress.address());
        if (LocalNetworkRules::moveToLan(before, m_Access, lanLocal, online, activeIsLan)) {
            qInfo() << "[fork] Local Network is back: asking" << name << "at its LAN address" << lanAddress.toString();
            m_Manager->addNewHost(lanAddress, true, name);
        }
    }
}

void ForkLocalNetwork::openSettings()
{
    QDesktopServices::openUrl(QUrl(QStringLiteral("x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")));
}
