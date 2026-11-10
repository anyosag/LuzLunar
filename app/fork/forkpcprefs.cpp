#include "forkpcprefs.h"
#include "pccardrules.h"
#include "pcorderrules.h"

#include <QTimer>

#include <QDateTime>
#include <QMutex>
#include <QMutexLocker>
#include <QSettings>

#ifdef Q_OS_UNIX
#include <pwd.h>
#include <unistd.h>
#endif

// [fork] Moonlight's own settings (same organization and application as StreamingPreferences)
namespace
{
    const QString k_FirstPcKey = QStringLiteral("fork/firstPc");

    // firstPcUuid() is read from any thread (ComputerManager::getComputers()), so the value lives
    // here under a mutex and QSettings is only touched on the main thread
    QMutex s_FirstMutex;
    QString s_FirstPc;
    bool s_FirstLoaded = false;

    QString loadFirstPc()
    {
        QMutexLocker locker(&s_FirstMutex);
        if (!s_FirstLoaded) {
            QSettings settings;
            s_FirstPc = settings.value(k_FirstPcKey).toString();
            s_FirstLoaded = true;
        }
        return s_FirstPc;
    }

    void storeFirstPc(const QString& uuid)
    {
        QMutexLocker locker(&s_FirstMutex);
        s_FirstPc = uuid;
        s_FirstLoaded = true;
        QSettings settings;
        if (uuid.isEmpty()) {
            settings.remove(k_FirstPcKey);
        } else {
            settings.setValue(k_FirstPcKey, uuid);
        }
    }

    // The order the person dragged the PCs into: uuids, read from any thread like the one above
    const QString k_OrderKey = QStringLiteral("fork/pcOrder");
    QMutex s_OrderMutex;
    QStringList s_Order;
    bool s_OrderLoaded = false;

    QStringList loadOrder()
    {
        QMutexLocker locker(&s_OrderMutex);
        if (!s_OrderLoaded) {
            QSettings settings;
            s_Order = settings.value(k_OrderKey).toStringList();
            s_OrderLoaded = true;
        }
        return s_Order;
    }

    void storeOrder(const QStringList& order)
    {
        QMutexLocker locker(&s_OrderMutex);
        s_Order = order;
        s_OrderLoaded = true;
        QSettings settings;
        if (order.isEmpty()) {
            settings.remove(k_OrderKey);
        } else {
            settings.setValue(k_OrderKey, order);
        }
    }

    std::vector<std::string> toStd(const QStringList& list)
    {
        std::vector<std::string> out;
        for (const QString& s : list) {
            out.push_back(s.toStdString());
        }
        return out;
    }

    QSettings& settings()
    {
        static QSettings* s_Settings = new QSettings();
        return *s_Settings;
    }
}

ForkPcPrefs::ForkPcPrefs() {}

ForkPcPrefs* ForkPcPrefs::get()
{
    static ForkPcPrefs* s_Instance = new ForkPcPrefs();
    return s_Instance;
}

QStringList ForkPcPrefs::colorIds() const
{
    QStringList ids;
    // Customize's swatch order
    for (const char* id : { "indigo", "blue", "purple", "pink", "red", "orange", "gold", "green", "teal", "graphite" }) {
        ids.append(QString::fromLatin1(id));
    }
    return ids;
}

bool ForkPcPrefs::screenshotMode() const
{
    return qEnvironmentVariableIsSet("LUZLUNAR_SCREENSHOTS");
}

QString ForkPcPrefs::pcsView() const
{
    if (m_PcsView.isEmpty()) {
        QString view = QStringLiteral("carousel");
        if (!screenshotMode()) {
            const QString stored = settings().value(QStringLiteral("fork/pcsView")).toString();
            if (stored == QLatin1String("grid")) {
                view = stored;
            }
        }
        const_cast<ForkPcPrefs*>(this)->m_PcsView = view;
    }
    return m_PcsView;
}

void ForkPcPrefs::setPcsView(const QString& view)
{
    if (view != QLatin1String("carousel") && view != QLatin1String("grid")) {
        return;
    }
    if (view == pcsView()) {
        return;
    }
    m_PcsView = view;
    if (!screenshotMode()) {
        settings().setValue(QStringLiteral("fork/pcsView"), view);
    }
    emit pcsViewChanged();
}

bool ForkPcPrefs::demoMode() const
{
    return qgetenv("LUZLUNAR_DEMO") == "1";
}

QString ForkPcPrefs::firstName() const
{
    // The screenshots never show the account's name (FORK.md, privacy)
    if (screenshotMode()) {
        return QStringLiteral("Gonzalo");
    }

#ifdef Q_OS_UNIX
    const struct passwd* entry = getpwuid(getuid());
    if (entry != nullptr) {
        // The GECOS field is "Full Name,room,phone,..."
        QString full = QString::fromLocal8Bit(entry->pw_gecos ? entry->pw_gecos : "");
        full = full.section(QLatin1Char(','), 0, 0).trimmed();
        const QString first = full.section(QLatin1Char(' '), 0, 0, QString::SectionSkipEmpty).trimmed();
        if (!first.isEmpty()) {
            return first;
        }
        return QString::fromLocal8Bit(entry->pw_name ? entry->pw_name : "");
    }
#endif
    return QString();
}

bool ForkPcPrefs::validUuid(const QString& uuid)
{
    // The characters NvComputer accepts for a uuid (nvcomputer.cpp), so a key can't climb out of its group
    if (uuid.isEmpty() || uuid.size() > 64) {
        return false;
    }
    for (QChar c : uuid) {
        const ushort u = c.unicode();
        if (!((u >= '0' && u <= '9') || (u >= 'A' && u <= 'Z') || (u >= 'a' && u <= 'z') || u == '_' || u == '-')) {
            return false;
        }
    }
    return true;
}

QString ForkPcPrefs::key(const QString& uuid, const QString& name)
{
    return QStringLiteral("fork/pcs/") + uuid + QLatin1Char('/') + name;
}

QVariantMap& ForkPcPrefs::group(const QString& uuid) const
{
    auto it = m_Cache.find(uuid);
    if (it == m_Cache.end()) {
        QVariantMap values;
        QSettings& s = settings();
        s.beginGroup(QStringLiteral("fork/pcs/") + uuid);
        for (const QString& name : s.allKeys()) {
            values.insert(name, s.value(name));
        }
        s.endGroup();
        it = m_Cache.insert(uuid, values);
    }
    return it.value();
}

QVariant ForkPcPrefs::read(const QString& uuid, const QString& name) const
{
    if (!validUuid(uuid)) {
        return QVariant();
    }
    return group(uuid).value(name);
}

void ForkPcPrefs::write(const QString& uuid, const QString& name, const QVariant& value, bool notify)
{
    if (!validUuid(uuid)) {
        return;
    }
    QVariantMap& values = group(uuid);
    if (value.isNull() || (value.typeId() == QMetaType::QString && value.toString().isEmpty())) {
        values.remove(name);
        settings().remove(key(uuid, name));
    } else {
        values.insert(name, value);
        settings().setValue(key(uuid, name), value);
    }
    if (notify) {
        bump(uuid);
    }
}

void ForkPcPrefs::bump(const QString& uuid)
{
    m_Revision++;
    emit changed(uuid);
}

QString ForkPcPrefs::colorKey(const QString& uuid)
{
    if (!validUuid(uuid)) {
        return QStringLiteral("indigo");
    }

    const QString stored = read(uuid, QStringLiteral("color")).toString();
    if (PcCardRules::isColor(stored.toStdString())) {
        return stored;
    }

    // Hand out the next color nobody has, and keep it
    std::vector<std::string> used;
    QSettings& s = settings();
    s.beginGroup(QStringLiteral("fork/pcs"));
    for (const QString& other : s.childGroups()) {
        const QString color = s.value(other + QStringLiteral("/color")).toString();
        if (PcCardRules::isColor(color.toStdString())) {
            used.push_back(color.toStdString());
        }
    }
    s.endGroup();
    const QString next = QString::fromStdString(PcCardRules::nextColor(used));
    if (!m_Forgotten.contains(uuid)) {
        write(uuid, QStringLiteral("color"), next, false);   // silent: reading a PC's color changes nothing for others
    }
    return next;
}

void ForkPcPrefs::setColorKey(const QString& uuid, const QString& color)
{
    if (!PcCardRules::isColor(color.toStdString())) {
        return;
    }
    m_Forgotten.remove(uuid);
    write(uuid, QStringLiteral("color"), color);
}

bool ForkPcPrefs::keepFirst(const QString& uuid) const
{
    return validUuid(uuid) && loadFirstPc() == uuid;
}

void ForkPcPrefs::setKeepFirst(const QString& uuid, bool on)
{
    if (!validUuid(uuid)) {
        return;
    }
    const QString previous = loadFirstPc();
    if (on) {
        if (previous == uuid) {
            return;
        }
        storeFirstPc(uuid);
        emit orderChanged();
        if (!previous.isEmpty()) {
            bump(previous);
        }
        bump(uuid);
    } else if (previous == uuid) {
        storeFirstPc(QString());
        emit orderChanged();
        bump(uuid);
    }
}

QString ForkPcPrefs::firstPcUuid()
{
    return loadFirstPc();
}

QStringList ForkPcPrefs::pcOrder()
{
    return loadOrder();
}

QString ForkPcPrefs::setPcOrder(const QStringList& uuids)
{
    QStringList order;
    for (const QString& uuid : uuids) {
        if (validUuid(uuid) && !order.contains(uuid)) {
            order.append(uuid);
        }
    }

    // Dragging another PC to the front ends "keep it first"
    QString dropped;
    const QString first = loadFirstPc();
    if (PcOrderRules::dropsKeepFirst(toStd(order), first.toStdString())) {
        dropped = first;
    }

    const bool orderChanged_ = order != loadOrder();
    if (!orderChanged_ && dropped.isEmpty()) {
        return QString();
    }
    if (orderChanged_) {
        storeOrder(order);
    }
    if (!dropped.isEmpty()) {
        storeFirstPc(QString());
    }
    emit orderChanged();
    if (!dropped.isEmpty()) {
        bump(dropped);
    }
    return dropped;
}

bool ForkPcPrefs::wakeOnPick(const QString& uuid) const
{
    // On unless set otherwise: Customize's toggle starts on
    const QVariant stored = read(uuid, QStringLiteral("wakeOnPick"));
    return stored.isValid() ? stored.toBool() : true;
}

void ForkPcPrefs::setWakeOnPick(const QString& uuid, bool on)
{
    write(uuid, QStringLiteral("wakeOnPick"), on);
}

void ForkPcPrefs::forget(const QString& uuid)
{
    if (!validUuid(uuid)) {
        return;
    }
    settings().remove(QStringLiteral("fork/pcs/") + uuid);
    m_Cache.remove(uuid);
    m_WakeSent.remove(uuid);
    m_WakeTimedOut.remove(uuid);
    m_Forgotten.insert(uuid);
    const bool wasFirst = loadFirstPc() == uuid;
    if (wasFirst) {
        storeFirstPc(QString());
    }
    QStringList order = loadOrder();
    const bool wasOrdered = order.removeAll(uuid) > 0;
    if (wasOrdered) {
        storeOrder(order);
    }
    bump(uuid);
    if (wasFirst || wasOrdered) {
        emit orderChanged();
    }
}

void ForkPcPrefs::adopt(const QString& uuid)
{
    m_Forgotten.remove(uuid);
}

qint64 ForkPcPrefs::lastSeenSecs(const QString& uuid) const
{
    return read(uuid, QStringLiteral("lastSeen")).toLongLong();
}

QString ForkPcPrefs::lastSeenVia(const QString& uuid) const
{
    return read(uuid, QStringLiteral("lastSeenVia")).toString();
}

void ForkPcPrefs::noteLastSeen(const QString& uuid, qint64 secs, const QString& via)
{
    write(uuid, QStringLiteral("lastSeen"), secs, false);
    write(uuid, QStringLiteral("lastSeenVia"), via, false);
}

qint64 ForkPcPrefs::remoteWorkedSecs(const QString& uuid) const
{
    return read(uuid, QStringLiteral("remoteWorked")).toLongLong();
}

void ForkPcPrefs::noteRemoteWorked(const QString& uuid, qint64 secs)
{
    write(uuid, QStringLiteral("remoteWorked"), secs, false);
}

QString ForkPcPrefs::powerAction(const QString& uuid) const
{
    return read(uuid, QStringLiteral("powerAction")).toString();
}

qint64 ForkPcPrefs::powerActionSecs(const QString& uuid) const
{
    return read(uuid, QStringLiteral("powerActionAt")).toLongLong();
}

void ForkPcPrefs::notePowerAction(const QString& uuid, const QString& action)
{
    if (action != QLatin1String("sleep") && action != QLatin1String("off")) {
        return;
    }
    write(uuid, QStringLiteral("powerAction"), action, false);
    write(uuid, QStringLiteral("powerActionAt"), QDateTime::currentSecsSinceEpoch(), false);
    bump(uuid);
}

void ForkPcPrefs::clearPowerAction(const QString& uuid)
{
    if (read(uuid, QStringLiteral("powerAction")).isValid()) {
        write(uuid, QStringLiteral("powerAction"), QString(), false);
        write(uuid, QStringLiteral("powerActionAt"), QVariant(), false);
        bump(uuid);
    }
}

QString ForkPcPrefs::apolloVersion(const QString& uuid) const
{
    return read(uuid, QStringLiteral("apolloVersion")).toString();
}

bool ForkPcPrefs::apolloUpdate(const QString& uuid) const
{
    return read(uuid, QStringLiteral("apolloUpdate")).toBool();
}

void ForkPcPrefs::noteApollo(const QString& uuid, const QString& version, bool update)
{
    if (version == apolloVersion(uuid) && update == apolloUpdate(uuid)) {
        return;
    }
    write(uuid, QStringLiteral("apolloVersion"), version, false);
    write(uuid, QStringLiteral("apolloUpdate"), update, false);
    bump(uuid);
}

QString ForkPcPrefs::wakeFromOff(const QString& uuid) const
{
    return read(uuid, QStringLiteral("wakeFromOff")).toString();
}

void ForkPcPrefs::noteWakeFromOff(const QString& uuid, const QString& fromOff)
{
    if (fromOff == wakeFromOff(uuid)) {
        return;
    }
    write(uuid, QStringLiteral("wakeFromOff"), fromOff);
}

void ForkPcPrefs::noteStream(const QString& uuid, int appId, const QString& appName, int width, int height,
                             int fps, bool hdr, const QString& codec)
{
    if (!validUuid(uuid)) {
        return;
    }
    QVariantMap last;
    last.insert(QStringLiteral("appId"), appId);
    last.insert(QStringLiteral("appName"), appName);
    last.insert(QStringLiteral("width"), width);
    last.insert(QStringLiteral("height"), height);
    last.insert(QStringLiteral("fps"), fps);
    last.insert(QStringLiteral("hdr"), hdr);
    last.insert(QStringLiteral("codec"), codec);
    for (auto it = last.cbegin(); it != last.cend(); ++it) {
        write(uuid, QStringLiteral("lastStream/") + it.key(), it.value(), false);
    }

    QStringList recent = recentApps(uuid);
    recent.removeAll(appName);
    recent.prepend(appName);
    while (recent.size() > 8) {
        recent.removeLast();
    }
    write(uuid, QStringLiteral("recentApps"), recent, false);
    bump(uuid);
}

QVariantMap ForkPcPrefs::lastStream(const QString& uuid) const
{
    QVariantMap last;
    if (!read(uuid, QStringLiteral("lastStream/appId")).isValid()) {
        return last;
    }
    last.insert(QStringLiteral("appId"), read(uuid, QStringLiteral("lastStream/appId")).toInt());
    last.insert(QStringLiteral("appName"), read(uuid, QStringLiteral("lastStream/appName")).toString());
    last.insert(QStringLiteral("width"), read(uuid, QStringLiteral("lastStream/width")).toInt());
    last.insert(QStringLiteral("height"), read(uuid, QStringLiteral("lastStream/height")).toInt());
    last.insert(QStringLiteral("fps"), read(uuid, QStringLiteral("lastStream/fps")).toInt());
    last.insert(QStringLiteral("hdr"), read(uuid, QStringLiteral("lastStream/hdr")).toBool());
    last.insert(QStringLiteral("codec"), read(uuid, QStringLiteral("lastStream/codec")).toString());
    return last;
}

QStringList ForkPcPrefs::recentApps(const QString& uuid) const
{
    return read(uuid, QStringLiteral("recentApps")).toStringList();
}

void ForkPcPrefs::noteWakeSent(const QString& uuid)
{
    if (!validUuid(uuid)) {
        return;
    }
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    m_WakeSent.insert(uuid, now);
    m_WakeTimedOut.remove(uuid);
    QTimer::singleShot((PcCardRules::k_WakeWaitSecs + 1) * 1000, this, [this, uuid, now]() { onWakeDeadline(uuid, now); });
    bump(uuid);
}

// Wake PC got no answer: the mark ends, so the card goes back to what the poll says (Wake PC stays
// available), and whoever wants to tell the person hears it once
void ForkPcPrefs::onWakeDeadline(const QString& uuid, qint64 sentAt)
{
    if (m_WakeSent.value(uuid, 0) != sentAt) {
        return;     // answered, or sent again since
    }
    m_WakeSent.remove(uuid);
    m_WakeTimedOut.insert(uuid);
    bump(uuid);
    emit wakeTimedOut(uuid);
}

void ForkPcPrefs::clearWakeSent(const QString& uuid)
{
    const bool had = m_WakeSent.remove(uuid) > 0;
    const bool timedOut = m_WakeTimedOut.remove(uuid);
    if (had || timedOut) {
        bump(uuid);
    }
}

qint64 ForkPcPrefs::wakeSentSecs(const QString& uuid) const
{
    return m_WakeSent.value(uuid, 0);
}

bool ForkPcPrefs::isWakeTimedOut(const QString& uuid) const
{
    return m_WakeTimedOut.contains(uuid);
}
