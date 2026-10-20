#include "macdrive.h"

#include <algorithm>
#include <mutex>
#include <string>
#include <vector>

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QReadLocker>
#include <QSettings>
#include <QStringList>
#include <QThread>
#include <QThreadPool>

#include "apolloclient.h"
#include "backend/nvcomputer.h"
#include "mac/macdrivesetup.h"
#include "macdriverules.h"

#define MD_TR(text) QCoreApplication::translate("MacDrive", text)

// What the last LAN stream got, for Settings › This Mac
#define SER_MACDRIVELAST "fork/macDriveLast"

using MacDriveRules::Outcome;
using MacDriveRules::Skip;

struct MacDrive::Shared
{
    ApolloClient::Target target;
    QString hostName;
    std::mutex mutex;
    bool alive = true;
    bool asked = false;     // the stream's one request was queued
    bool ready = false;     // a message for the main thread
    QString message;
    bool show = false;
};

namespace
{
    // How long Apollo gets to map the drive before the stream stops asking how it went
    const int k_MapWaitMs = 15000;
    const int k_PollMs = 500;

    Uint32 eventType()
    {
        static Uint32 type = SDL_RegisterEvents(1);
        return type;
    }

    QThreadPool* workerPool()
    {
        // The pool belongs to the app, so a stream can end without waiting for a request in flight
        static QThreadPool* pool = [] {
            QThreadPool* newPool = new QThreadPool(QCoreApplication::instance());
            newPool->setMaxThreadCount(1);
            return newPool;
        }();
        return pool;
    }

    bool alive(const std::shared_ptr<MacDrive::Shared>& shared)
    {
        std::lock_guard<std::mutex> lock(shared->mutex);
        return shared->alive;
    }

    void wipe(std::string& secret)
    {
        std::fill(secret.begin(), secret.end(), '\0');
        secret.clear();
    }

    // Apollo takes the Mac's name in up to 100 bytes of UTF-8
    QString labelFor(QString name)
    {
        while (name.toUtf8().size() > 100) {
            name.chop(1);
        }
        return name;
    }

    QString skipMessage(Skip reason)
    {
        switch (reason) {
        case Skip::HostTooOld:
            return MD_TR("This PC's Apollo can't show this Mac as a drive yet; update Apollo");
        case Skip::HostOff:
            return MD_TR("Apollo on this PC has the Mac drive turned off");
        case Skip::NoPermission:
            return MD_TR("Apollo doesn't give this Mac the Network Drive permission");
        case Skip::NoPassword:
            return MD_TR("Save your Mac password in Settings › This Mac to see this Mac on the PC");
        case Skip::PasswordChanged:
            return MD_TR("Your Mac password changed: save it again in Settings › This Mac");
        case Skip::SharingOff:
            return MD_TR("Turn on File Sharing in System Settings to see this Mac on the PC");
        case Skip::NotApollo:
            return MD_TR("The PC didn't answer as an Apollo PC, so it wasn't asked for this Mac's disk");
        case Skip::NotLan:
        case Skip::Off:
        case Skip::None:
            break;
        }
        return QString();
    }

    QString outcomeMessage(Outcome outcome, const MacDriveRules::Reply& reply)
    {
        QString letter = QString::fromStdString(reply.letter);
        switch (outcome) {
        case Outcome::Added:
            return MD_TR("On the PC, this Mac is drive %1:").arg(letter);
        case Outcome::AddedHome:
            return MD_TR("On the PC, your home folder is drive %1:; share the whole disk in File Sharing to see all of it").arg(letter);
        case Outcome::Kept:
            return MD_TR("On the PC, this Mac is still drive %1:").arg(letter);
        case Outcome::WrongPassword:
            return MD_TR("The PC couldn't sign in to this Mac: turn on Windows File Sharing for your account");
        case Outcome::NtlmBlocked:
            return MD_TR("Windows on the PC blocks the sign-in this Mac needs (SMB NTLM blocking)");
        case Outcome::Denied:
            return MD_TR("This Mac doesn't let your account open its disk or home folder from the PC");
        case Outcome::NoShare:
            return MD_TR("This Mac shares neither its disk nor your home folder");
        case Outcome::Unreachable:
            return MD_TR("The PC couldn't reach this Mac's File Sharing");
        case Outcome::Conflict:
            return MD_TR("The PC is connected to this Mac under another account; disconnect that drive first");
        case Outcome::NoLetter:
            return MD_TR("The PC has no free drive letter for this Mac");
        case Outcome::NobodySignedIn:
            return MD_TR("Nobody is signed in to Windows on the PC");
        case Outcome::Refused:
            return MD_TR("Apollo didn't take this Mac as a drive");
        case Outcome::Pending:
            return MD_TR("The PC is still connecting to this Mac's File Sharing");
        case Outcome::Failed:
            break;
        }
        return MD_TR("The PC couldn't add this Mac as a drive");
    }

    MacDriveRules::Reply parseReply(const ApolloClient::Response& response)
    {
        MacDriveRules::Reply reply;
        reply.httpStatus = response.httpStatus;
        QJsonObject json = QJsonDocument::fromJson(response.body).object();
        reply.state = json.value(QStringLiteral("state")).toString().toStdString();
        reply.letter = json.value(QStringLiteral("letter")).toString().toStdString();
        reply.share = json.value(QStringLiteral("share")).toString().toStdString();
        reply.added = json.value(QStringLiteral("added")).toBool();
        reply.error = json.value(QStringLiteral("error")).toString().toStdString();
        reply.code = json.value(QStringLiteral("code")).toVariant().toLongLong();
        return reply;
    }

    // Hands the stream its message, and keeps it for Settings even once the stream has ended
    void finish(const std::shared_ptr<MacDrive::Shared>& shared, const QString& message, bool show)
    {
        QSettings().setValue(SER_MACDRIVELAST, message);
        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            if (!shared->alive) {
                return;
            }
            shared->message = message;
            shared->show = show;
            shared->ready = true;
        }
        SDL_Event event = {};
        event.type = eventType();
        SDL_PushEvent(&event);
    }

    // On the worker: whether the PC can be asked, then asking and waiting for the drive
    void ask(std::shared_ptr<MacDrive::Shared> shared)
    {
        ApolloClient client(shared->target);
        ApolloClient::HostInfo info = client.hostInfo();

        MacDriveRules::Facts facts;
        facts.enabled = true;
        facts.viaLan = true;
        facts.host = MacDriveRules::hostSupport(info.macDrive.toStdString());
        facts.permissions = info.permissions;
        // The keychain is only read for a host that takes the drive; these are checked next
        facts.passwordSaved = facts.passwordValid = facts.sharingOn = true;
        Skip reason = MacDriveRules::skip(facts);
        std::string password;
        if (reason == Skip::None) {
            password = MacDriveSetup::loadPassword();
            facts.passwordSaved = !password.empty();
            facts.passwordValid = facts.passwordSaved && MacDriveSetup::verifyPassword(password);
            facts.sharingOn = MacDriveSetup::fileSharingOn();
            reason = MacDriveRules::skip(facts);
        }
        if (reason != Skip::None) {
            wipe(password);
            QString message = skipMessage(reason);
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Mac drive: %s didn't get asked: %s",
                        qPrintable(shared->hostName), qPrintable(message));
            finish(shared, message, !MacDriveRules::silent(reason));
            return;
        }

        std::string user = MacDriveSetup::userName();
        std::vector<std::string> shares = MacDriveRules::shares(MacDriveSetup::diskShareName(), MacDriveSetup::isAdmin(),
                                                                MacDriveSetup::startupVolumeName(), user);
        QJsonArray shareList;
        QStringList shareNames;
        for (const std::string& share : shares) {
            shareList.append(QString::fromStdString(share));
            shareNames.append(QString::fromStdString(share));
        }
        QJsonObject request;
        request.insert(QStringLiteral("action"), QStringLiteral("map"));
        request.insert(QStringLiteral("shares"), shareList);
        request.insert(QStringLiteral("user"), QString::fromStdString(user));
        request.insert(QStringLiteral("password"), QString::fromStdString(password));
        request.insert(QStringLiteral("name"), labelFor(QString::fromStdString(MacDriveSetup::computerName())));
        QByteArray body = QJsonDocument(request).toJson(QJsonDocument::Compact);
        request.remove(QStringLiteral("password"));
        wipe(password);

        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Mac drive: asking %s for this Mac's disk (%s)",
                    qPrintable(shared->hostName), qPrintable(shareNames.join(QStringLiteral(", "))));
        ApolloClient::RequestOptions options;
        options.contentType = "application/json";
        options.timeoutMs = 10 * 1000;
        options.maxResponseBytes = 64 * 1024;
        options.cancelled = [shared] { return !alive(shared); };
        ApolloClient::Response response = client.request(QStringLiteral("actions/drive"), QString(), &body, options);
        body.fill('\0');

        MacDriveRules::Reply reply = parseReply(response);
        Outcome outcome = MacDriveRules::outcome(reply, shares);
        QElapsedTimer waited;
        waited.start();
        while (outcome == Outcome::Pending && waited.elapsed() < k_MapWaitMs && alive(shared)) {
            QThread::msleep(k_PollMs);
            response = client.request(QStringLiteral("actions/drive"), QString(), nullptr, options);
            reply = parseReply(response);
            outcome = MacDriveRules::outcome(reply, shares);
        }

        QString message = outcomeMessage(outcome, reply);
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Mac drive: %s (HTTP %d, %s%s%s)", qPrintable(message), reply.httpStatus,
                    reply.state.empty() ? "no state" : reply.state.c_str(), reply.error.empty() ? "" : ", ", reply.error.c_str());
        finish(shared, message, MacDriveRules::worthTelling(outcome));
    }
}

MacDrive::MacDrive(NvComputer* computer)
    : m_Shared(std::make_shared<Shared>())
{
    // Both on this thread before a worker or the probe's thread uses them
    eventType();
    workerPool();

    m_Shared->target = ApolloClient::targetFor(computer);
    QReadLocker lock(&computer->lock);
    m_Shared->hostName = computer->name;
}

MacDrive::~MacDrive()
{
    // A request in flight gives up, and its result is dropped
    std::lock_guard<std::mutex> lock(m_Shared->mutex);
    m_Shared->alive = false;
}

std::function<void(bool viaLan)> MacDrive::linkListener() const
{
    std::shared_ptr<Shared> shared = m_Shared;
    return [shared](bool viaLan) {
        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            if (!shared->alive || shared->asked) {
                return;
            }
            shared->asked = true;
        }
        if (!viaLan) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Mac drive: the stream doesn't go over the LAN, so %s isn't asked",
                        qPrintable(shared->hostName));
            return;
        }
        workerPool()->start([shared] { ask(shared); });
    };
}

void MacDrive::handleEvent(const SDL_Event& event)
{
    if (event.type != eventType()) {
        return;
    }
    QString message;
    bool show;
    {
        std::lock_guard<std::mutex> lock(m_Shared->mutex);
        if (!m_Shared->ready) {
            return;
        }
        m_Shared->ready = false;
        message = m_Shared->message;
        show = m_Shared->show;
    }
    if (show && !message.isEmpty() && m_MessageSink) {
        m_MessageSink(message);
    }
}

void MacDrive::setMessageSink(std::function<bool(const QString&)> sink)
{
    m_MessageSink = std::move(sink);
}
