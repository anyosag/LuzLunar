#include "forknetworklink.h"

#include <chrono>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <QCryptographicHash>
#include <QReadLocker>
#include <QSettings>
#include <QStringList>

#include "SDL_compat.h"
#include "backend/nvcomputer.h"
#include "forklinkrules.h"
#include "mac/networklink.h"

// A group with a list per PC (by uuid) of the networks it was streamed over the LAN on, newest first
#define SER_LANNETWORKS "fork/lanNetworks"

namespace ForkNetworkLink
{
namespace
{
    const auto k_RefreshInterval = std::chrono::seconds(5);

    // One stream's probing. Its thread holds it until it sees stopped.
    struct Monitor {
        std::mutex mutex;
        std::condition_variable wake;
        bool stopped = false;
    };

    struct State {
        std::mutex mutex;
        QString hostUuid;
        std::string address;    // the PC's address as Moonlight has it, maybe a name
        ForkLinkRules::Reachability reachability = ForkLinkRules::Reachability::NotChecked;
        std::shared_ptr<Monitor> monitor;
        Current current;
    };

    // Never destroyed: a probing thread may still be finishing as the app exits
    State& state()
    {
        static State* s = new State();
        return *s;
    }

    ForkLinkRules::Reachability fromMoonlight(int reachability)
    {
        switch (reachability) {
        case NvComputer::RI_LAN:
            return ForkLinkRules::Reachability::Lan;
        case NvComputer::RI_VPN:
            return ForkLinkRules::Reachability::Vpn;
        case NvComputer::RI_UNKNOWN:
            return ForkLinkRules::Reachability::Unknown;
        default:
            return ForkLinkRules::Reachability::NotChecked;
        }
    }

    // A network as stored: a hash, so the router's addresses aren't kept
    std::string hashed(const std::string& networkId)
    {
        if (networkId.empty()) {
            return std::string();
        }
        QByteArray hash = QCryptographicHash::hash(QByteArray::fromStdString(networkId), QCryptographicHash::Sha256);
        return hash.toHex().left(32).toStdString();
    }

    QString settingsKey(const QString& hostUuid)
    {
        return QStringLiteral(SER_LANNETWORKS "/") + hostUuid;
    }

    std::vector<std::string> loadRemembered(const QString& hostUuid)
    {
        std::vector<std::string> ids;
        for (const QString& id : QSettings().value(settingsKey(hostUuid)).toStringList()) {
            ids.push_back(id.toStdString());
        }
        return ids;
    }

    void saveRemembered(const QString& hostUuid, const std::vector<std::string>& ids)
    {
        QStringList list;
        for (const std::string& id : ids) {
            list.append(QString::fromStdString(id));
        }
        QSettings().setValue(settingsKey(hostUuid), list);
    }

    void stopMonitor(const std::shared_ptr<Monitor>& monitor)
    {
        if (monitor) {
            {
                std::lock_guard<std::mutex> lock(monitor->mutex);
                monitor->stopped = true;
            }
            monitor->wake.notify_all();
        }
    }

    void probeUntilStopped(std::shared_ptr<Monitor> monitor, QString hostUuid, std::string host,
                           ForkLinkRules::Reachability reachability, bool refresh,
                           std::function<void(bool)> onFirstProbe)
    {
        // Once: a name the PC is known by could take a DNS lookup
        std::string address = MacNetworkLink::numericAddress(host);
        std::vector<std::string> remembered = loadRemembered(hostUuid);

        for (bool first = true;; first = false) {
            MacNetworkLink::Probe probe = MacNetworkLink::probe(address);
            bool lan = ForkLinkRules::viaLan(reachability, probe.onLink, probe.link.kind);
            std::string network = hashed(probe.networkId);
            bool known = ForkLinkRules::remembered(remembered, network);

            {
                std::lock_guard<std::mutex> lock(monitor->mutex);
                if (monitor->stopped) {
                    return;
                }
            }
            bool rememberedNow = lan && !network.empty() && (remembered.empty() || remembered.front() != network);
            if (rememberedNow) {
                remembered = ForkLinkRules::remember(remembered, network);
                saveRemembered(hostUuid, remembered);
            }

            bool shown = ForkLinkRules::shouldShow(lan, known);

            if (first) {
                std::string link = ForkLinkRules::badge(probe.link, false);
                const char* about = network.empty() ? "no router to tell the network by"
                                    : known         ? "this PC was streamed over the LAN on this network before"
                                    : rememberedNow ? "the network is remembered from now on"
                                                    : "this PC wasn't streamed over the LAN on this network before";
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Stream link: %s%s%s%s, %s; %s; %s",
                            link.empty() ? "no route found" : link.c_str(),
                            probe.interfaceName.empty() ? "" : " (",
                            probe.interfaceName.c_str(),
                            probe.interfaceName.empty() ? "" : ")",
                            lan ? "over the LAN" : "not over the LAN",
                            about,
                            !refresh ? "no notch bar" : (shown ? "shown in the notch bar" : "not shown in the notch bar"));
                if (onFirstProbe) {
                    onFirstProbe(lan);
                }
            }

            {
                std::lock_guard<std::mutex> lock(state().mutex);
                // A later stream's monitor owns it otherwise
                if (state().monitor == monitor) {
                    state().current.known = true;
                    state().current.link = probe.link;
                    state().current.viaLan = lan;
                    state().current.shown = shown;
                }
            }

            if (!refresh) {
                return;
            }
            std::unique_lock<std::mutex> lock(monitor->mutex);
            if (monitor->wake.wait_for(lock, k_RefreshInterval, [&monitor] { return monitor->stopped; })) {
                return;
            }
        }
    }
}

void noteStreamStart(NvComputer* computer, int reachability)
{
    QString uuid;
    std::string address;
    {
        QReadLocker lock(&computer->lock);
        uuid = computer->uuid;
        address = computer->activeAddress.address().toStdString();
    }

    std::lock_guard<std::mutex> lock(state().mutex);
    state().hostUuid = uuid;
    state().address = address;
    state().reachability = fromMoonlight(reachability);
}

void start(bool refresh, std::function<void(bool viaLan)> onFirstProbe)
{
    auto monitor = std::make_shared<Monitor>();
    std::shared_ptr<Monitor> previous;
    QString hostUuid;
    std::string address;
    ForkLinkRules::Reachability reachability = ForkLinkRules::Reachability::NotChecked;
    {
        std::lock_guard<std::mutex> lock(state().mutex);
        previous.swap(state().monitor);
        state().current = Current();
        if (!state().hostUuid.isEmpty() && !state().address.empty()) {
            state().monitor = monitor;
            hostUuid = state().hostUuid;
            address = state().address;
            reachability = state().reachability;
        }
    }
    stopMonitor(previous);
    if (!hostUuid.isEmpty()) {
        std::thread(probeUntilStopped, monitor, hostUuid, address, reachability, refresh, std::move(onFirstProbe)).detach();
    }
}

void stop()
{
    std::shared_ptr<Monitor> monitor;
    {
        std::lock_guard<std::mutex> lock(state().mutex);
        monitor.swap(state().monitor);
        state().current = Current();
        // The next stream notes its own
        state().hostUuid.clear();
        state().address.clear();
        state().reachability = ForkLinkRules::Reachability::NotChecked;
    }
    stopMonitor(monitor);
}

Current current()
{
    std::lock_guard<std::mutex> lock(state().mutex);
    return state().current;
}

QVector<NvAddress> pollOrder(NvComputer* computer)
{
    QVector<NvAddress> addresses = computer->uniqueAddresses();
    NvAddress lanAddress;
    QString uuid;
    {
        QReadLocker lock(&computer->lock);
        lanAddress = computer->localAddress;
        uuid = computer->uuid;
    }
    int at = lanAddress.isNull() ? -1 : addresses.indexOf(lanAddress);
    if (at <= 0) {
        return addresses;
    }

    MacNetworkLink::Probe probe = MacNetworkLink::probe(MacNetworkLink::numericAddress(lanAddress.address().toStdString()));
    // The settings only when the address is local here: away, that's every poll
    bool known = probe.onLink && ForkLinkRules::remembered(loadRemembered(uuid), hashed(probe.networkId));
    if (ForkLinkRules::lanAddressFirst(probe.onLink, probe.link.kind, known)) {
        addresses.move(at, 0);
    }
    return addresses;
}
}
