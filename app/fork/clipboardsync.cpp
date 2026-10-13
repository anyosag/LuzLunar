#include "clipboardsync.h"

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <mutex>

#include <QCoreApplication>
#include <QThreadPool>

#include "mac/macintegration.h"
#include "streaming/session.h"

#define CS_TR(text) QCoreApplication::translate("ClipboardSync", text)

namespace
{
    // Apollo's per-client permission bits (src/crypto.h). Clipboard access also needs view or launch.
    const qint64 k_PermClipboardSet = 0x00010000;
    const qint64 k_PermClipboardRead = 0x00020000;
    const qint64 k_PermViewOrLaunch = 0x06000000;

    const int k_RequestTimeoutMs = 3000;
    const int k_QuitDownloadWaitMs = 1000;
    const Uint32 k_ToastDurationMs = 1500;
    const int k_MaxClipboardBytes = 1024 * 1024;

    enum EventCode {
        ResultsReady = 1,
        HideToast = 2,
    };

    // Shown once per app run so automatic sync doesn't repeat it every stream
    bool s_PermissionToastShown = false;

    Uint32 eventType()
    {
        static Uint32 type = SDL_RegisterEvents(1);
        return type;
    }

    QThreadPool* workerPool()
    {
        // A single thread keeps requests in order. The pool belongs to the app, so a stream
        // can end without waiting for a request in flight.
        static QThreadPool* pool = [] {
            QThreadPool* newPool = new QThreadPool(QCoreApplication::instance());
            newPool->setMaxThreadCount(1);
            return newPool;
        }();
        return pool;
    }

    void pushEvent(EventCode code, void* data = nullptr)
    {
        SDL_Event event = {};
        event.type = eventType();
        event.user.code = code;
        event.user.data1 = data;
        SDL_PushEvent(&event);
    }

    QString withLfLineEndings(QString text)
    {
        text.replace("\r\n", "\n");
        return text;
    }

    QString localClipboardText()
    {
        if (!SDL_HasClipboardText()) {
            return QString();
        }

        char* text = SDL_GetClipboardText();
        QString result = text != nullptr ? QString::fromUtf8(text) : QString();
        SDL_free(text);
        return withLfLineEndings(result);
    }
}

struct ClipboardSync::Shared
{
    ApolloClient::Target target;
    std::mutex mutex;
    std::condition_variable resultReady;
    std::deque<Result> results;
    bool alive = true;
};

ClipboardSync::ClipboardSync(NvComputer* computer, bool automatic)
    : m_Shared(std::make_shared<Shared>()),
      m_Automatic(automatic),
      m_HostSupportsSync(true),
      m_PermissionsKnown(false),
      m_CanSend(false),
      m_CanReceive(false),
      m_ToastGeneration(0),
      m_ToastShowing(false)
{
    // Register the event type on this thread before any worker uses it
    eventType();

    m_Shared->target = ApolloClient::targetFor(computer);

    // Requests run in order, so the permission check finishes before the first upload
    submit(Kind::Permissions, false);
    if (m_Automatic) {
        upload(false);
    }
}

ClipboardSync::~ClipboardSync()
{
    // Requests still queued or in flight drop their results
    std::lock_guard<std::mutex> lock(m_Shared->mutex);
    m_Shared->alive = false;
}

void ClipboardSync::handleEvent(const SDL_Event& event)
{
    if (event.type == eventType()) {
        if (event.user.code == ResultsReady) {
            processResults();
        }
        else if (event.user.code == HideToast) {
            hideToast(static_cast<unsigned>(reinterpret_cast<uintptr_t>(event.user.data1)));
        }
        return;
    }

    if (!m_Automatic) {
        return;
    }

    switch (event.type) {
    case SDL_WINDOWEVENT:
        if (event.window.event == SDL_WINDOWEVENT_FOCUS_GAINED) {
            upload(false);
        }
        else if (event.window.event == SDL_WINDOWEVENT_FOCUS_LOST) {
            download(false);
        }
        break;

    case SDL_QUIT:
        downloadBeforeQuit();
        break;

    default:
        break;
    }
}

void ClipboardSync::sendToHost()
{
    upload(true);
}

void ClipboardSync::receiveFromHost()
{
    download(true);
}

void ClipboardSync::upload(bool manual)
{
    if (!m_HostSupportsSync) {
        if (manual) {
            showToast(CS_TR("This host doesn't support clipboard sync (it needs Apollo)"));
        }
        return;
    }
    if (m_PermissionsKnown && !m_CanSend) {
        if (manual) {
            showToast(CS_TR("Apollo doesn't allow this device to set the PC's clipboard"));
        }
        return;
    }

    QString text = localClipboardText();
    if (text.isEmpty()) {
        if (manual) {
            showToast(CS_TR("The clipboard has no text to send"));
        }
        return;
    }
    if (text.toUtf8().size() > k_MaxClipboardBytes) {
        if (manual) {
            showToast(CS_TR("The clipboard is too large to send (over 1 MB)"));
        }
        return;
    }

    if (!manual) {
        // Skip text the host already has or is about to get, and passwords from password managers
        if (text == m_LastKnownHost || text == m_PendingUpload || MacIntegration::clipboardHasConcealedContent()) {
            return;
        }
    }

    m_PendingUpload = text;
    submit(Kind::Upload, manual, text);
}

void ClipboardSync::download(bool manual)
{
    if (!m_HostSupportsSync) {
        if (manual) {
            showToast(CS_TR("This host doesn't support clipboard sync (it needs Apollo)"));
        }
        return;
    }
    if (m_PermissionsKnown && !m_CanReceive) {
        if (manual) {
            showToast(CS_TR("Apollo doesn't allow this device to read the PC's clipboard"));
        }
        return;
    }

    submit(Kind::Download, manual);
}

void ClipboardSync::submit(Kind kind, bool manual, const QString& text)
{
    std::shared_ptr<Shared> shared = m_Shared;

    workerPool()->start([shared, kind, manual, text]() {
        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            if (!shared->alive) {
                return;
            }
        }

        ApolloClient client(shared->target);
        Result result;
        result.kind = kind;
        result.manual = manual;
        result.permissions = -1;
        result.text = text;

        switch (kind) {
        case Kind::Permissions:
            result.permissions = client.permissions();
            break;
        case Kind::Upload: {
            QByteArray body = text.toUtf8();
            result.response = client.request("actions/clipboard", "type=text", &body, k_RequestTimeoutMs);
            break;
        }
        case Kind::Download:
            result.response = client.request("actions/clipboard", "type=text", nullptr, k_RequestTimeoutMs);
            break;
        }

        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            if (!shared->alive) {
                return;
            }
            shared->results.push_back(result);
        }
        shared->resultReady.notify_all();
        pushEvent(ResultsReady);
    });
}

void ClipboardSync::processResults()
{
    std::deque<Result> results;
    {
        std::lock_guard<std::mutex> lock(m_Shared->mutex);
        results.swap(m_Shared->results);
    }

    for (const Result& result : results) {
        apply(result);
    }
}

void ClipboardSync::apply(const Result& result)
{
    switch (result.kind) {
    case Kind::Permissions:
        m_PermissionsKnown = true;
        if (result.permissions < 0) {
            m_HostSupportsSync = false;
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                        "[fork] Clipboard sync is off: the host didn't report Apollo permissions");
            break;
        }

        m_CanSend = (result.permissions & k_PermClipboardSet) && (result.permissions & k_PermViewOrLaunch);
        m_CanReceive = (result.permissions & k_PermClipboardRead) && (result.permissions & k_PermViewOrLaunch);
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[fork] Apollo clipboard permissions: send %s, receive %s",
                    m_CanSend ? "yes" : "no", m_CanReceive ? "yes" : "no");

        if ((!m_CanSend || !m_CanReceive) && !s_PermissionToastShown) {
            s_PermissionToastShown = true;
            showToast(CS_TR("Clipboard sync needs the Clipboard permissions for this device in Apollo"));
        }
        break;

    case Kind::Upload:
        if (result.text == m_PendingUpload) {
            m_PendingUpload.clear();
        }
        if (result.response.httpStatus != 200) {
            reportFailure(result);
            break;
        }

        m_LastKnownHost = result.text;
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[fork] Sent %d characters of clipboard text to the host",
                    (int)result.text.length());
        if (result.manual) {
            showToast(CS_TR("Clipboard sent to the PC"));
        }
        break;

    case Kind::Download: {
        if (result.response.httpStatus != 200) {
            reportFailure(result);
            break;
        }

        QString text = withLfLineEndings(QString::fromUtf8(result.response.body));
        if (text.isEmpty()) {
            // Never wipe the local clipboard because the host has no text
            if (result.manual) {
                showToast(CS_TR("The PC's clipboard has no text"));
            }
            break;
        }

        // Unchanged on the host since we last synced: keep anything newer that was copied locally
        if (!result.manual && text == m_LastKnownHost) {
            break;
        }

        m_LastKnownHost = text;
        if (text != localClipboardText()) {
            SDL_SetClipboardText(text.toUtf8().constData());
        }
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[fork] Received %d characters of clipboard text from the host",
                    (int)text.length());
        if (result.manual) {
            showToast(CS_TR("Clipboard received from the PC"));
        }
        break;
    }
    }
}

void ClipboardSync::reportFailure(const Result& result)
{
    const ApolloClient::Response& response = result.response;

    QString message;
    switch (response.httpStatus) {
    case 401:
        message = CS_TR("Apollo doesn't give this device clipboard permission");
        break;
    case 403:
        message = CS_TR("The PC doesn't see an active stream from this device");
        break;
    case 404:
        message = CS_TR("This host doesn't support clipboard sync (it needs Apollo)");
        m_HostSupportsSync = false;
        break;
    case 500:
        message = CS_TR("The PC couldn't update its clipboard");
        break;
    case 0:
        message = CS_TR("Clipboard sync failed: %1").arg(response.networkError);
        break;
    default:
        message = CS_TR("Clipboard sync failed (HTTP %1)").arg(response.httpStatus);
        break;
    }

    SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                "[fork] Clipboard %s failed: %s",
                result.kind == Kind::Upload ? "upload" : "download",
                qPrintable(message));

    if (result.manual) {
        showToast(message);
    }
    else if (response.httpStatus == 401 && !s_PermissionToastShown) {
        s_PermissionToastShown = true;
        showToast(message);
    }
}

void ClipboardSync::downloadBeforeQuit()
{
    if (!m_HostSupportsSync || (m_PermissionsKnown && !m_CanReceive)) {
        return;
    }

    // The host still sees the stream until the connection is stopped after this event, so
    // wait briefly for the host's clipboard to arrive.
    submit(Kind::Download, false);

    {
        std::unique_lock<std::mutex> lock(m_Shared->mutex);
        m_Shared->resultReady.wait_for(lock, std::chrono::milliseconds(k_QuitDownloadWaitMs), [this] {
            for (const Result& result : m_Shared->results) {
                if (result.kind == Kind::Download) {
                    return true;
                }
            }
            return false;
        });
    }

    processResults();
}

void ClipboardSync::showToast(const QString& text)
{
    Session* session = Session::get();
    if (session == nullptr) {
        return;
    }

    // Don't cover one of Moonlight's own status messages, like a poor connection warning
    Overlay::OverlayManager& overlays = session->getOverlayManager();
    if (overlays.isOverlayEnabled(Overlay::OverlayStatusUpdate) && !m_ToastShowing) {
        return;
    }

    overlays.updateOverlayText(Overlay::OverlayStatusUpdate, text.toUtf8().constData());
    overlays.setOverlayState(Overlay::OverlayStatusUpdate, true);
    m_ToastText = text;
    m_ToastShowing = true;

    unsigned generation = ++m_ToastGeneration;
    SDL_AddTimer(k_ToastDurationMs,
                 [](Uint32, void* param) -> Uint32 {
                     pushEvent(HideToast, param);
                     return 0;
                 },
                 reinterpret_cast<void*>(static_cast<uintptr_t>(generation)));
}

void ClipboardSync::hideToast(unsigned generation)
{
    if (!m_ToastShowing || generation != m_ToastGeneration) {
        return;
    }
    m_ToastShowing = false;

    Session* session = Session::get();
    if (session == nullptr) {
        return;
    }

    // Only hide it if Moonlight hasn't replaced it with its own message in the meantime
    Overlay::OverlayManager& overlays = session->getOverlayManager();
    const char* current = overlays.getOverlayText(Overlay::OverlayStatusUpdate);
    if (current != nullptr && m_ToastText == QString::fromUtf8(current)) {
        overlays.setOverlayState(Overlay::OverlayStatusUpdate, false);
    }
}
