#include "clipboardsync.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <map>
#include <mutex>
#include <string>
#include <string_view>

#include <QCoreApplication>
#include <QStringList>
#include <QThreadPool>

#include "clipbundle.h"
#include "mac/macintegration.h"
#include "mac/pasteboard.h"
#include "streaming/session.h"

#define CS_TR(text) QCoreApplication::translate("ClipboardSync", text)

namespace
{
    // Apollo's per-client permission bits (src/crypto.h). Clipboard access also needs view or launch.
    const qint64 k_PermClipboardSet = 0x00010000;
    const qint64 k_PermClipboardRead = 0x00020000;
    const qint64 k_PermViewOrLaunch = 0x06000000;

    const int k_RequestTimeoutMs = 3000;
    const int k_UploadStallTimeoutMs = 20000;
    const int k_DownloadStallTimeoutMs = 30000;   // the PC may be waiting for Office to render
    const int k_QuitDownloadWaitMs = 1000;
    const Uint32 k_ToastDurationMs = 1500;
    const int k_MaxClipboardBytes = 1024 * 1024;  // for text sync
    const size_t k_ProgressBytes = 1024 * 1024;   // larger transfers say so
    const char* const k_BundleContentType = "application/x-luzlunar-clipboard";

    enum EventCode {
        ResultsReady = 1,
        HideToast = 2,
    };

    // Shown once per app run so automatic sync doesn't repeat it every stream
    bool s_PermissionToastShown = false;

    // Lets a transfer in flight give up when the app quits, instead of delaying the quit
    std::atomic<bool> s_AppQuitting { false };

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
            QObject::connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, [] {
                s_AppQuitting = true;
            });
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

    // What rich sync knows about a host's clipboard. Kept for the life of the app, so a new stream
    // doesn't resend content the host already has. Only used on the worker thread.
    enum class Transport { Unknown, Bundle, Text };

    struct HostState {
        Transport transport = Transport::Unknown;
        std::string token;          // the host's clipboard state when we last synced
        uint64_t hostEtag = 0;      // hash of what the host holds
        long localChangeCount = -1; // the Mac pasteboard after our last upload or write
        uint64_t localEtag = 0;     // hash of that content
        std::string hostText;       // text sync: the host's text when we last synced
    };

    HostState& hostState(const QString& hostUuid)
    {
        static std::map<QString, HostState> states;
        return states[hostUuid];
    }

    std::string_view viewOf(const QByteArray& bytes)
    {
        return std::string_view(bytes.constData(), static_cast<size_t>(bytes.size()));
    }

    QString sizeText(size_t bytes)
    {
        return QString("%1 MB").arg(bytes / (1024.0 * 1024.0), 0, 'f', 1);
    }

    // Types and sizes for the log; never the content
    QString describe(const std::vector<clipbundle::item>& items)
    {
        QStringList parts;
        for (const clipbundle::item& it : items) {
            parts.append(QString("%1 %2 bytes").arg(QString::fromStdString(it.type)).arg(it.data.size()));
        }
        return parts.isEmpty() ? QString("nothing") : parts.join(", ");
    }

    bool hasImage(const std::vector<clipbundle::item>& items)
    {
        for (const clipbundle::item& it : items) {
            if (clipbundle::is_image_type(it.type)) {
                return true;
            }
        }
        return false;
    }

    QString successToast(const std::vector<clipbundle::item>& items, size_t wireBytes, bool manual, bool sent)
    {
        if (hasImage(items)) {
            return sent ? CS_TR("Image sent to the PC") : CS_TR("Image copied from the PC");
        }
        if (wireBytes > k_ProgressBytes) {
            return (sent ? CS_TR("Clipboard sent to the PC (%1)") : CS_TR("Clipboard copied from the PC (%1)")).arg(sizeText(wireBytes));
        }
        if (manual) {
            return sent ? CS_TR("Clipboard sent to the PC") : CS_TR("Clipboard received from the PC");
        }
        return QString();
    }
}

struct ClipboardSync::Shared
{
    ApolloClient::Target target;
    bool rich = false;
    std::atomic<bool> cancelUploads { false };
    std::mutex mutex;
    std::condition_variable resultReady;
    std::deque<Result> results;
    bool alive = true;
};

namespace
{
    // Hands a result to the main thread; dropped once the stream has ended
    void post(ClipboardSync::Shared& shared, const ClipboardSync::Result& result)
    {
        {
            std::lock_guard<std::mutex> lock(shared.mutex);
            if (!shared.alive) {
                return;
            }
            shared.results.push_back(result);
        }
        shared.resultReady.notify_all();
        pushEvent(ResultsReady);
    }

    void notice(ClipboardSync::Shared& shared, const QString& text)
    {
        ClipboardSync::Result result;
        result.kind = ClipboardSync::Kind::Notice;
        result.toast = text;
        post(shared, result);
    }

    void fail(ClipboardSync::Result& result, const ApolloClient::Response& response)
    {
        result.failed = true;
        result.response = response;
    }

    void failWith(ClipboardSync::Result& result, int status)
    {
        result.failed = true;
        result.response.httpStatus = status;
    }

    // Rich sync, on the worker thread: reads the Mac pasteboard and sends what changed
    void richUpload(ClipboardSync::Shared& shared, bool manual, ClipboardSync::Result& result)
    {
        HostState& state = hostState(shared.target.hostUuid);
        if (!manual && MacPasteboard::changeCount() == state.localChangeCount) {
            return;     // nothing new since the last sync
        }

        MacPasteboard::Snapshot snapshot = MacPasteboard::read();
        SDL_LogDebug(SDL_LOG_CATEGORY_APPLICATION, "[fork] Pasteboard types: %s",
                     QString::fromStdString([&] {
                         std::string all;
                         for (const std::string& type : snapshot.types) {
                             all += (all.empty() ? "" : ", ") + type;
                         }
                         return all;
                     }()).toUtf8().constData());

        if (snapshot.concealed && !manual) {
            // A password from a password manager: never sent automatically
            state.localChangeCount = snapshot.changeCount;
            return;
        }
        if (snapshot.items.empty()) {
            if (manual) {
                result.toast = CS_TR("The clipboard has nothing to send");
            }
            return;
        }

        uint64_t etag = clipbundle::etag(snapshot.items);
        if (!manual && etag == state.localEtag) {
            // Copied again, but the same content
            state.localChangeCount = snapshot.changeCount;
            return;
        }

        ApolloClient client(shared.target);
        if (state.transport != Transport::Text) {
            clipbundle::bundle bundle;
            bundle.flags = snapshot.concealed ? clipbundle::flag_concealed : 0;
            bundle.etag = etag;
            bundle.items = snapshot.items;
            std::string encoded;
            if (!clipbundle::encode_within_limit(bundle, encoded)) {
                failWith(result, 413);
                return;
            }
            if (encoded.size() > k_ProgressBytes) {
                notice(shared, CS_TR("Sending the clipboard to the PC (%1)...").arg(sizeText(encoded.size())));
            }

            QByteArray body(encoded.data(), static_cast<int>(encoded.size()));
            ApolloClient::RequestOptions options;
            options.contentType = k_BundleContentType;
            options.transferTimeoutMs = k_UploadStallTimeoutMs;
            options.cancelled = [&shared] {
                return shared.cancelUploads.load() || s_AppQuitting.load();
            };
            ApolloClient::Response response = client.request("actions/clipboard", "type=bundle&v=1", &body, options);

            if (response.httpStatus == 400) {
                // Stock Apollo: plain text from now on
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] The host syncs text only (it doesn't have LuzLunar's Apollo build)");
                state.transport = Transport::Text;
            }
            else if (response.httpStatus != 200) {
                fail(result, response);
                return;
            }
            else {
                state.transport = Transport::Bundle;
                clipbundle::bundle reply;
                if (clipbundle::decode(viewOf(response.body), reply)) {
                    state.token = reply.token;
                    state.hostEtag = reply.etag;
                }
                state.localChangeCount = snapshot.changeCount;
                state.localEtag = etag;
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Sent the clipboard to the host: %s (%d bytes on the wire)",
                            qPrintable(describe(bundle.items)), (int)encoded.size());
                result.toast = successToast(bundle.items, encoded.size(), manual, true);
                return;
            }
        }

        // Text sync
        const clipbundle::item* text = nullptr;
        for (const clipbundle::item& it : snapshot.items) {
            if (it.type == "text/plain") {
                text = &it;
            }
        }
        if (text == nullptr) {
            if (manual) {
                result.toast = CS_TR("This PC only syncs text (images and formatting need LuzLunar's Apollo build)");
            }
            state.localChangeCount = snapshot.changeCount;
            return;
        }
        if (text->data.size() > static_cast<size_t>(k_MaxClipboardBytes)) {
            if (manual) {
                result.toast = CS_TR("The clipboard is too large to send (over 1 MB)");
            }
            return;
        }
        if (!manual && text->data == state.hostText) {
            state.localChangeCount = snapshot.changeCount;
            return;
        }

        QByteArray body = QByteArray::fromStdString(text->data);
        ApolloClient::Response response = client.request("actions/clipboard", "type=text", &body, k_RequestTimeoutMs);
        if (response.httpStatus != 200) {
            fail(result, response);
            return;
        }
        state.hostText = text->data;
        state.localChangeCount = snapshot.changeCount;
        state.localEtag = etag;
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Sent %d bytes of clipboard text to the host", (int)text->data.size());
        if (manual) {
            result.toast = CS_TR("Clipboard sent to the PC");
        }
    }

    // Rich sync, on the worker thread: fetches what changed on the host and writes the Mac pasteboard
    void richDownload(ClipboardSync::Shared& shared, bool manual, ClipboardSync::Result& result)
    {
        HostState& state = hostState(shared.target.hostUuid);
        long startCount = MacPasteboard::changeCount();
        ApolloClient client(shared.target);

        if (state.transport != Transport::Text) {
            // A manual fetch always gets the content; automatic ones skip what we already have
            QString arguments = QString("type=bundle&v=1&auto=%1").arg(manual ? 0 : 1);
            if (!manual) {
                if (!state.token.empty()) {
                    arguments += "&since=" + QString::fromStdString(state.token);
                }
                if (state.hostEtag != 0) {
                    arguments += "&have=" + QString::fromStdString(clipbundle::etag_hex(state.hostEtag));
                }
            }

            ApolloClient::RequestOptions options;
            options.transferTimeoutMs = k_DownloadStallTimeoutMs;
            options.maxResponseBytes = static_cast<qint64>(clipbundle::k_max_bundle_bytes) + 1024 * 1024;
            options.cancelled = [] {
                return s_AppQuitting.load();
            };
            ApolloClient::Response response = client.request("actions/clipboard", arguments, nullptr, options);

            if (response.httpStatus == 400) {
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] The host syncs text only (it doesn't have LuzLunar's Apollo build)");
                state.transport = Transport::Text;
            }
            else if (response.httpStatus != 200) {
                fail(result, response);
                return;
            }
            else {
                state.transport = Transport::Bundle;
                clipbundle::bundle bundle;
                std::string error;
                if (!clipbundle::decode(viewOf(response.body), bundle, &error)) {
                    SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Couldn't read the host's clipboard: %s", error.c_str());
                    failWith(result, 422);
                    return;
                }
                state.token = bundle.token;

                if (bundle.flags & clipbundle::flag_unchanged) {
                    if (bundle.etag != 0) {
                        state.hostEtag = bundle.etag;
                    }
                    if (manual) {
                        result.toast = CS_TR("The clipboard is already up to date");
                    }
                    return;
                }
                if (bundle.items.empty()) {
                    // Never wipe the local clipboard because the PC's is empty or private
                    if (manual) {
                        result.toast = (bundle.flags & clipbundle::flag_concealed) ? CS_TR("The PC's clipboard holds private content")
                                                                                    : CS_TR("The PC's clipboard is empty");
                    }
                    return;
                }
                state.hostEtag = bundle.etag;

                if (!manual && MacPasteboard::changeCount() != startCount) {
                    // Something was copied on the Mac meanwhile; keep the newer copy
                    return;
                }
                long count = MacPasteboard::write(bundle.items, (bundle.flags & clipbundle::flag_concealed) != 0);
                if (count == 0) {
                    result.toast = CS_TR("Couldn't update the Mac's clipboard");
                    return;
                }
                state.localChangeCount = count;
                state.localEtag = clipbundle::etag(bundle.items);
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Copied the host's clipboard: %s (%d bytes on the wire)",
                            qPrintable(describe(bundle.items)), (int)response.body.size());
                result.toast = successToast(bundle.items, static_cast<size_t>(response.body.size()), manual, false);
                return;
            }
        }

        // Text sync
        ApolloClient::Response response = client.request("actions/clipboard", "type=text", nullptr, k_RequestTimeoutMs);
        if (response.httpStatus != 200) {
            fail(result, response);
            return;
        }
        std::string text = clipbundle::to_lf(viewOf(response.body));
        if (text.empty()) {
            if (manual) {
                result.toast = CS_TR("The PC's clipboard has no text");
            }
            return;
        }
        if (!manual && text == state.hostText) {
            return;
        }
        state.hostText = text;
        if (!manual && MacPasteboard::changeCount() != startCount) {
            return;
        }

        std::vector<clipbundle::item> items { { "text/plain", text } };
        long count = MacPasteboard::write(items, false);
        if (count != 0) {
            state.localChangeCount = count;
            state.localEtag = clipbundle::etag(items);
        }
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Received %d bytes of clipboard text from the host", (int)text.size());
        if (manual) {
            result.toast = CS_TR("Clipboard received from the PC");
        }
    }
}

ClipboardSync::ClipboardSync(NvComputer* computer, bool automatic)
    : m_Shared(std::make_shared<Shared>()),
      m_Automatic(automatic),
      m_Rich(MacPasteboard::supported()),
      m_HostSupportsSync(true),
      m_PermissionsKnown(false),
      m_CanSend(false),
      m_CanReceive(false),
      m_AutoFailureShown(false),
      m_ToastGeneration(0),
      m_ToastShowing(false)
{
    // Register the event type on this thread before any worker uses it
    eventType();

    m_Shared->target = ApolloClient::targetFor(computer);
    m_Shared->rich = m_Rich;

    // Requests run in order, so the permission check finishes before the first upload
    submit(Kind::Permissions, false);
    if (m_Automatic) {
        upload(false);
    }
}

ClipboardSync::~ClipboardSync()
{
    // Uploads in flight stop (the PC won't accept them after the stream), and requests still
    // queued or in flight drop their results. A download in flight still updates the clipboard.
    m_Shared->cancelUploads = true;
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

    if (m_Rich) {
        // The worker reads the pasteboard, so the stream never waits on it
        submit(Kind::Upload, manual);
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
        result.text = text;

        switch (kind) {
        case Kind::Permissions:
            result.permissions = client.permissions();
            break;
        case Kind::Upload:
            if (shared->rich) {
                result.rich = true;
                richUpload(*shared, manual, result);
            }
            else {
                QByteArray body = text.toUtf8();
                result.response = client.request("actions/clipboard", "type=text", &body, k_RequestTimeoutMs);
            }
            break;
        case Kind::Download:
            if (shared->rich) {
                result.rich = true;
                richDownload(*shared, manual, result);
            }
            else {
                result.response = client.request("actions/clipboard", "type=text", nullptr, k_RequestTimeoutMs);
            }
            break;
        case Kind::Notice:
            break;
        }

        post(*shared, result);
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
    if (result.kind == Kind::Notice) {
        showToast(result.toast);
        return;
    }
    if (result.rich) {
        if (result.failed) {
            reportFailure(result);
        }
        else if (!result.toast.isEmpty()) {
            showToast(result.toast);
        }
        return;
    }

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

    case Kind::Notice:
        break;
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
    case 413:
        message = CS_TR("The clipboard is too large to sync (over 64 MB)");
        break;
    case 422:
        message = CS_TR("The clipboard data wasn't understood (update Apollo and LuzLunar)");
        break;
    case 500:
        message = CS_TR("The PC couldn't update its clipboard");
        break;
    case 503:
        message = CS_TR("The PC's clipboard is busy; try again");
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

    if (result.manual || response.httpStatus == 413) {
        showToast(message);
    }
    else if (response.httpStatus == 401) {
        if (!s_PermissionToastShown) {
            s_PermissionToastShown = true;
            showToast(message);
        }
    }
    else if (!m_AutoFailureShown) {
        // Otherwise an automatic sync that failed just leaves the old clipboard, with no explanation
        m_AutoFailureShown = true;
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

void ClipboardSync::setMessageSink(std::function<bool(const QString&)> sink)
{
    m_MessageSink = std::move(sink);
}

void ClipboardSync::showToast(const QString& text)
{
    // Shown beside the notch instead while LuzLunar's notch bar is on screen
    if (m_MessageSink && m_MessageSink(text)) {
        return;
    }

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
