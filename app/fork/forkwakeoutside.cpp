#include "forkwakeoutside.h"

#include <QCoreApplication>
#include <QDate>
#include <QDateTime>
#include <QHostAddress>
#include <QHostInfo>
#include <QLocale>
#include <QPointer>
#include <QReadLocker>
#include <QSslCertificate>
#include <QThread>
#include <QThreadPool>
#include <QTimer>
#include <QtDebug>

#include "forknetworklink.h"
#include "forkpcprefs.h"
#include "pccardrules.h"
#include "backend/computermanager.h"
#include "backend/nvcomputer.h"
#include "backend/nvhttp.h"

namespace
{
    // The PC came online at home: the check waits a little, for the polls of a launch to settle
    const int k_CheckDelayMs = 15 * 1000;
    const int k_CheckTimeoutMs = 4000;

    std::string text(const QString& s)
    {
        return s.toStdString();
    }

    QString text(const std::string& s)
    {
        return QString::fromStdString(s);
    }

    // What the rules need from a PC, read under its lock (the worker gets this, never the PC)
    struct Pc {
        QString uuid;
        QString name;
        QString lanAddress;
        QString mac;
        QString remote;
        quint16 remotePort = 0;
        QString manual;
        quint16 manualPort = 0;
        QString ipv6;
        bool online = false;
    };

    Pc pcOf(NvComputer* computer)
    {
        Pc pc;
        QReadLocker lock(&computer->lock);
        pc.uuid = computer->uuid;
        pc.name = computer->name;
        pc.lanAddress = computer->localAddress.isNull() ? QString() : computer->localAddress.address();
        pc.mac = computer->macAddress.isEmpty() ? QString() : QString::fromLatin1(computer->macAddress.toHex(':'));
        if (!computer->remoteAddress.isNull()) {
            pc.remote = computer->remoteAddress.address();
            pc.remotePort = computer->remoteAddress.port();
        }
        if (!computer->manualAddress.isNull()) {
            pc.manual = computer->manualAddress.address();
            pc.manualPort = computer->manualAddress.port();
        }
        pc.ipv6 = computer->ipv6Address.isNull() ? QString() : computer->ipv6Address.address();
        pc.online = computer->state == NvComputer::CS_ONLINE;
        return pc;
    }

    WakeOutsideRules::Where whereOf(const Pc& pc)
    {
        const ForkNetworkLink::Home home = ForkNetworkLink::homeFor(pc.uuid, pc.lanAddress);
        WakeOutsideRules::Where where;
        where.onLink = home.onLink;
        where.networkRemembered = home.networkRemembered;
        where.anyRemembered = home.anyRemembered;
        where.outsideAddress = WakeOutsideRules::outsideAddress(text(pc.remote), text(pc.manual));
        where.ipv6Address = WakeOutsideRules::isGlobalIPv6(text(pc.ipv6)) ? text(pc.ipv6) : std::string();
        return where;
    }

    // The HTTP port at the home's address: the one Moonlight has for that address
    quint16 outsidePort(const Pc& pc, const QString& outside)
    {
        const quint16 port = outside == pc.remote ? pc.remotePort : outside == pc.manual ? pc.manualPort : 0;
        return port != 0 ? port : 47989;
    }

    WakeOutsideRules::Check checkOf(const QVariantMap& stored)
    {
        WakeOutsideRules::Check check;
        check.atSecs = stored.value(QStringLiteral("at")).toLongLong();
        check.address = text(stored.value(QStringLiteral("address")).toString());
        check.reached = stored.value(QStringLiteral("reached")).toBool();
        check.forwardedTo = text(stored.value(QStringLiteral("forwardedTo")).toString());
        return check;
    }

    // "today at 21:52", "yesterday at 9:05", "on 11/14/26"
    QString whenText(qint64 secs)
    {
        const QDateTime at = QDateTime::fromSecsSinceEpoch(secs);
        const QDate today = QDate::currentDate();
        const QString time = QLocale::system().toString(at.time(), QLocale::ShortFormat);
        if (at.date() == today) {
            return QCoreApplication::translate("ForkWakeOutside", "today at %1").arg(time);
        }
        if (at.date() == today.addDays(-1)) {
            return QCoreApplication::translate("ForkWakeOutside", "yesterday at %1").arg(time);
        }
        return QCoreApplication::translate("ForkWakeOutside", "on %1").arg(QLocale::system().toString(at.date(), QLocale::ShortFormat));
    }

    QString logText(const QVariantMap& found, const QString& pcName)
    {
        const QString address = found.value(QStringLiteral("address")).toString();
        if (!found.value(QStringLiteral("reached")).toBool()) {
            return QStringLiteral("[fork] Wake from outside, checked from home: %1 doesn't reach %2").arg(address, pcName);
        }
        const QString forwardedTo = found.value(QStringLiteral("forwardedTo")).toString();
        const QString lan = found.value(QStringLiteral("lanAddress")).toString();
        QString line = QStringLiteral("[fork] Wake from outside, checked from home: %1 reaches %2 at %3").arg(address, pcName, forwardedTo);
        if (!lan.isEmpty() && !forwardedTo.isEmpty() && lan != forwardedTo) {
            line += QStringLiteral(" (LuzLunar finds it at home at %1)").arg(lan);
        }
        return line;
    }
}

ForkWakeOutside* ForkWakeOutside::get()
{
    static ForkWakeOutside* s_Instance = new ForkWakeOutside();
    return s_Instance;
}

ForkWakeOutside::ForkWakeOutside()
    : QObject(QCoreApplication::instance())
{
    connect(ForkPcPrefs::get(), &ForkPcPrefs::wakeTimedOut, this, &ForkWakeOutside::onWakeTimedOut);
}

void ForkWakeOutside::setComputerManager(ComputerManager* manager)
{
    if (m_Manager.isNull() && manager != nullptr) {
        m_Manager = manager;
    }
}

NvComputer* ForkWakeOutside::find(const QString& uuid) const
{
    if (m_Manager.isNull() || uuid.isEmpty()) {
        return nullptr;
    }
    for (NvComputer* computer : m_Manager->getComputers()) {
        QReadLocker lock(&computer->lock);
        if (computer->uuid == uuid) {
            return computer;
        }
    }
    return nullptr;
}

void ForkWakeOutside::bump()
{
    m_Revision++;
    emit changed();
}

ForkWakeOutside::Route ForkWakeOutside::routeFor(NvComputer* computer) const
{
    Route r;
    r.where = whereOf(pcOf(computer));
    r.route = text(WakeOutsideRules::route(r.where));
    r.address = text(WakeOutsideRules::shownAddress(r.where));
    return r;
}

void ForkWakeOutside::noteWake(NvComputer* computer)
{
    const Pc pc = pcOf(computer);
    const Route r = routeFor(computer);
    ForkPcPrefs* prefs = ForkPcPrefs::get();
    prefs->noteWakeRoute(pc.uuid, r.route, r.address, prefs->powerAction(pc.uuid) == QLatin1String("off"));
    qInfo().noquote() << "[fork]" << text(WakeOutsideRules::logLine(text(r.route), r.where, text(pc.name)));
}

void ForkWakeOutside::onWakeTimedOut(const QString& uuid)
{
    NvComputer* computer = find(uuid);
    const QString name = computer != nullptr ? pcOf(computer).name : QString();
    const QString route = ForkPcPrefs::get()->wakeRoute(uuid);
    qInfo().noquote() << QStringLiteral("[fork] Wake PC to %1: no answer in %2 s (%3)")
                             .arg(name).arg(PcCardRules::k_WakeWaitSecs).arg(route.isEmpty() ? QStringLiteral("route unknown") : route);
    const QString toast = text(WakeOutsideRules::missedToast(text(route), text(name)));
    if (!toast.isEmpty()) {
        emit missed(uuid, toast);
    }
}

QVariantMap ForkWakeOutside::status(const QString& uuid) const
{
    QVariantMap map;
    NvComputer* computer = find(uuid);
    if (computer == nullptr) {
        return map;
    }
    const Pc pc = pcOf(computer);
    const WakeOutsideRules::Where where = whereOf(pc);
    ForkPcPrefs* prefs = ForkPcPrefs::get();

    WakeOutsideRules::Facts facts;
    facts.pcName = text(pc.name);
    facts.lanAddress = text(pc.lanAddress);
    facts.mac = text(pc.mac);
    facts.adapter = text(prefs->wakeAdapter(uuid));
    facts.link = text(prefs->wakeLink(uuid));
    facts.outsideAddress = where.outsideAddress;
    facts.atHome = WakeOutsideRules::route(where) == "home";
    facts.online = pc.online;
    facts.check = checkOf(prefs->outsideCheck(uuid));
    if (facts.check.atSecs > 0) {
        facts.checkedWhen = text(whenText(facts.check.atSecs));
    }

    QVariantList rows;
    for (const WakeOutsideRules::Row& row : WakeOutsideRules::rows(facts)) {
        QVariantMap r;
        r.insert(QStringLiteral("id"), text(row.id));
        r.insert(QStringLiteral("kind"), text(row.kind));
        r.insert(QStringLiteral("title"), text(row.title));
        r.insert(QStringLiteral("detail"), text(row.detail));
        rows.append(r);
    }
    map.insert(QStringLiteral("intro"), text(WakeOutsideRules::intro(facts)));
    map.insert(QStringLiteral("rows"), rows);
    map.insert(QStringLiteral("atHome"), facts.atHome);
    map.insert(QStringLiteral("online"), facts.online);
    map.insert(QStringLiteral("checking"), m_Checking.contains(uuid));
    map.insert(QStringLiteral("blocker"), text(WakeOutsideRules::checkBlocker(facts)));
    map.insert(QStringLiteral("checked"), facts.check.atSecs > 0);
    return map;
}

QString ForkWakeOutside::shutDownWarning(const QString& uuid) const
{
    NvComputer* computer = find(uuid);
    if (computer == nullptr) {
        return QString();
    }
    const Pc pc = pcOf(computer);
    return text(WakeOutsideRules::shutDownWarning(WakeOutsideRules::route(whereOf(pc)), text(pc.name)));
}

void ForkWakeOutside::checkIfDue(const QString& uuid)
{
    QTimer::singleShot(k_CheckDelayMs, this, [this, uuid]() {
        NvComputer* computer = find(uuid);
        if (computer == nullptr) {
            return;
        }
        const Pc pc = pcOf(computer);
        // Only from home, and only for a PC with an address from outside (else nothing to check)
        if (!pc.online || WakeOutsideRules::outsideAddress(text(pc.remote), text(pc.manual)).empty() ||
                WakeOutsideRules::route(whereOf(pc)) != "home") {
            return;
        }
        const QVariantMap last = ForkPcPrefs::get()->outsideCheck(uuid);
        if (WakeOutsideRules::checkDue(checkOf(last), QDateTime::currentSecsSinceEpoch(), text(pc.lanAddress),
                                       text(last.value(QStringLiteral("lanAddress")).toString()))) {
            check(uuid);
        }
    });
}

void ForkWakeOutside::check(const QString& uuid)
{
    NvComputer* computer = find(uuid);
    if (computer == nullptr || m_Checking.contains(uuid)) {
        return;
    }
    const Pc pc = pcOf(computer);
    const QString outside = text(WakeOutsideRules::outsideAddress(text(pc.remote), text(pc.manual)));
    if (outside.isEmpty() || !pc.online) {
        return;
    }
    const quint16 port = outsidePort(pc, outside);
    m_Checking.insert(uuid);
    bump();

    QPointer<ForkWakeOutside> self(this);
    QThreadPool::globalInstance()->start([self, pc, outside, port]() {
        QVariantMap found;
        QString skipped;
        // The IPv4 address to ask through: the home's address, or the public IPv4 one of a name the
        // PC was added by (a dual-stack name may list its IPv6 address first, which goes around the
        // router's forward)
        QString target = WakeOutsideRules::isIPv4(text(outside)) ? outside : QString();
        if (target.isEmpty()) {
            const QHostInfo info = QHostInfo::fromName(outside);
            for (const QHostAddress& address : info.addresses()) {
                if (address.protocol() == QAbstractSocket::IPv4Protocol && WakeOutsideRules::isPublicIPv4(text(address.toString()))) {
                    target = address.toString();
                    break;
                }
            }
        }
        if (WakeOutsideRules::route(whereOf(pc)) != "home") {
            skipped = QStringLiteral("this Mac isn't on its home network");
        }
        else if (!WakeOutsideRules::isPublicIPv4(text(target))) {
            skipped = QStringLiteral("its address isn't one from outside");
        }
        else {
            auto ask = [&]() {
                QString xml;
                try {
                    NvHTTP http(NvAddress(target, port), 47984, QSslCertificate(), false);
                    xml = http.openConnectionToString(http.m_BaseUrlHttp, QStringLiteral("serverinfo"), QString(),
                                                      k_CheckTimeoutMs, NvHTTP::NVLL_NONE);
                }
                catch (...) {
                    xml.clear();
                }
                return text(xml);
            };
            std::string body = ask();
            bool reached = WakeOutsideRules::samePc(body, text(pc.uuid));
            if (!reached) {
                // Once more, for a packet lost on the way
                QThread::msleep(1000);
                body = ask();
                reached = WakeOutsideRules::samePc(body, text(pc.uuid));
            }
            if (WakeOutsideRules::route(whereOf(pc)) != "home") {
                // This Mac left the PC's home network meanwhile: the answer says nothing
                skipped = QStringLiteral("this Mac left its home network during the check");
            }
            else {
                found.insert(QStringLiteral("at"), QDateTime::currentSecsSinceEpoch());
                found.insert(QStringLiteral("address"), outside);
                found.insert(QStringLiteral("reached"), reached);
                found.insert(QStringLiteral("forwardedTo"), reached ? text(WakeOutsideRules::xmlValue(body, "LocalIP")) : QString());
                found.insert(QStringLiteral("lanAddress"), pc.lanAddress);
            }
        }

        QMetaObject::invokeMethod(qApp, [self, pc, found, skipped]() {
            if (self.isNull()) {
                return;
            }
            self->m_Checking.remove(pc.uuid);
            QString why = skipped;
            if (!found.isEmpty() && !found.value(QStringLiteral("reached")).toBool()) {
                // No answer from a PC that has since gone to sleep says nothing about the router
                NvComputer* computer = self->find(pc.uuid);
                if (computer == nullptr || !pcOf(computer).online) {
                    why = QStringLiteral("it stopped answering during the check");
                }
            }
            if (why.isEmpty()) {
                ForkPcPrefs::get()->noteOutsideCheck(pc.uuid, found);
                qInfo().noquote() << logText(found, pc.name);
            }
            else {
                qInfo().noquote() << QStringLiteral("[fork] Wake from outside: not checked for %1 (%2)").arg(pc.name, why);
            }
            self->bump();
        }, Qt::QueuedConnection);
    });
}
