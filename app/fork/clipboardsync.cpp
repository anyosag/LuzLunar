#include "clipboardsync.h"

#include <algorithm>
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
#include <QStandardPaths>
#include <QStringList>
#include <QThreadPool>

#include "clipbundle.h"
#include "clipfiles.h"
#include "forkpreferences.h"
#include "mac/macintegration.h"
#include "mac/pasteboard.h"
#include "streaming/session.h"

#define CS_TR(text) QCoreApplication::translate("ClipboardSync", text)

namespace
{
    // Apollo's per-client permission bits (src/crypto.h). Clipboard access also needs view or launch.
    const qint64 k_PermClipboardSet = 0x00010000;
    const qint64 k_PermClipboardRead = 0x00020000;
    const qint64 k_PermFileUpload = 0x00040000;
    const qint64 k_PermFileDownload = 0x00080000;
    const qint64 k_PermViewOrLaunch = 0x06000000;

    const int k_RequestTimeoutMs = 3000;
    const int k_UploadStallTimeoutMs = 20000;
    const int k_DownloadStallTimeoutMs = 30000;   // the PC may be waiting for Office to render
    const int k_QuitDownloadWaitMs = 1000;
    const Uint32 k_ToastDurationMs = 1500;
    const int k_MaxClipboardBytes = 1024 * 1024;  // for text sync
    const size_t k_ProgressBytes = 1024 * 1024;   // larger transfers say so
    const char* const k_BundleContentType = "application/x-luzlunar-clipboard";
    const char* const k_FileContentType = "application/octet-stream";

    // File copies: progress about once a second, and the PC's copies kept in the cache for pasting
    const int k_ProgressIntervalMs = 1000;
    const size_t k_CopiesKept = 3;
    const long k_CopyMaxAgeSeconds = 24 * 60 * 60;
    const uint64_t k_FreeSpaceMargin = uint64_t(512) << 20;   // left free on the Mac's disk

    enum EventCode {
        ResultsReady = 1,
        HideToast = 2,
    };

    // Shown once per app run so automatic sync doesn't repeat it every stream
    bool s_PermissionToastShown = false;
    std::atomic<bool> s_FilePermissionToastShown { false };   // the worker's

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

    QString sizeText(uint64_t bytes)
    {
        if (bytes >= (uint64_t(1) << 30)) {
            return QString("%1 GB").arg(bytes / (1024.0 * 1024.0 * 1024.0), 0, 'f', 1);
        }
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
    bool files = false;             // file copies: rich sync, and "Copy files too" is on
    std::string filesBase;          // where copies from the PC go
    std::atomic<bool> hostTakesFiles { false };     // from the Permissions job
    std::atomic<bool> mayUploadFiles { false };
    std::atomic<bool> mayDownloadFiles { false };
    std::atomic<bool> ended { false };      // the stream ended: uploads and file copies in flight stop
    std::atomic<bool> quitting { false };   // the stream is ending: its last fetch leaves files out
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

    bool stopped(const ClipboardSync::Shared& shared)
    {
        return shared.ended.load() || s_AppQuitting.load();
    }

    // "3 files", for file copy messages
    QString filesText(const clipbundle::file_manifest& manifest)
    {
        size_t files = std::count_if(manifest.entries.begin(), manifest.entries.end(), [](const clipbundle::file_entry& entry) {
            return !entry.directory;
        });
        if (files == 0) {
            size_t folders = manifest.entries.size();
            return folders == 1 ? CS_TR("1 folder") : CS_TR("%1 folders").arg(qulonglong(folders));
        }
        return files == 1 ? CS_TR("1 file") : CS_TR("%1 files").arg(qulonglong(files));
    }

    // Why a file copy stopped. Not ClipboardSync::reportFailure(), whose 404 means a host without
    // clipboard sync.
    QString fileFailure(const ApolloClient::Response& response, bool sending)
    {
        switch (response.httpStatus) {
        case 401:
            return sending ? CS_TR("Apollo doesn't allow this device to upload files (File Upload permission)")
                           : CS_TR("Apollo doesn't allow this device to download files (File Download permission)");
        case 403:
            return CS_TR("The PC doesn't see an active stream from this device");
        case 404:
        case 409:
            return sending ? CS_TR("The PC stopped taking the files; send them again")
                           : CS_TR("The copied files changed on the PC, or it stopped offering them; copy them again");
        case 500:
            return sending ? CS_TR("The PC couldn't save the files") : CS_TR("The PC couldn't read one of the copied files");
        case 0:
            return CS_TR("Copying the files failed: %1").arg(response.networkError);
        default:
            return CS_TR("Copying the files failed (HTTP %1)").arg(response.httpStatus);
        }
    }

    // A file copy's progress, from the worker: a notice about once a second, and the percentage on
    // the Dock icon, which shows while the stream is in the background
    class Progress
    {
    public:
        // format's last placeholder takes the percentage
        Progress(ClipboardSync::Shared& shared, QString format, uint64_t total)
            : m_Shared(shared),
              m_Format(std::move(format)),
              m_Total(total),
              m_Visible(total > k_ProgressBytes)
        {
            add(0);
        }

        ~Progress()
        {
            if (m_Visible) {
                ClipboardSync::Result result;
                result.kind = ClipboardSync::Kind::Notice;
                result.setBadge = true;
                post(m_Shared, result);
            }
        }

        Progress(const Progress&) = delete;
        Progress& operator=(const Progress&) = delete;

        void add(uint64_t bytes)
        {
            m_Done += bytes;
            auto now = std::chrono::steady_clock::now();
            if (!m_Visible || (m_Shown && now - m_LastShown < std::chrono::milliseconds(k_ProgressIntervalMs))) {
                return;
            }
            m_Shown = true;
            m_LastShown = now;

            // 100% only once it's done, when the badge goes
            int percent = static_cast<int>(std::min<uint64_t>(m_Done * 100 / m_Total, 99));
            ClipboardSync::Result result;
            result.kind = ClipboardSync::Kind::Notice;
            result.toast = m_Format.arg(percent);
            result.setBadge = true;
            result.badge = QString("%1%").arg(percent);
            post(m_Shared, result);
        }

    private:
        ClipboardSync::Shared& m_Shared;
        QString m_Format;
        uint64_t m_Total;
        uint64_t m_Done = 0;
        bool m_Visible;
        bool m_Shown = false;
        std::chrono::steady_clock::time_point m_LastShown;
    };

    QString chunkArguments(const char* type, const std::string& transfer, size_t index, uint64_t offset)
    {
        return QString("type=%1&transfer=%2&index=%3&offset=%4")
                .arg(QString::fromLatin1(type), QString::fromStdString(transfer))
                .arg(qulonglong(index))
                .arg(qulonglong(offset));
    }

    // Why the PC's copied files didn't come with its clipboard; empty when there's nothing to say
    QString skippedFilesNote(const ClipboardSync::Shared& shared, bool manual, bool askedForFiles)
    {
        if (askedForFiles) {
            return CS_TR("The PC's copied files are too many or too large to copy (over 10,000 files or 20 GB), or couldn't be read");
        }
        if (shared.quitting) {
            return QString();
        }
        if (!shared.files) {
            // Turned off on purpose, so only said when asked
            return manual ? CS_TR("Files aren't copied: \"Copy files too\" is off in Settings") : QString();
        }
        if (!shared.hostTakesFiles) {
            return manual ? CS_TR("File copies are off on the PC (Apollo's fork_clipboard_files setting)") : QString();
        }
        if (!shared.mayDownloadFiles && (manual || !s_FilePermissionToastShown.exchange(true))) {
            return CS_TR("Apollo doesn't allow this device to download files (File Download permission)");
        }
        return QString();
    }

    // The PC's copied files, on the worker thread: fetched a chunk at a time into LuzLunar's cache,
    // then put on the Mac's clipboard as Finder's copy lists them, once they're all here. A copy
    // that's in the cache already isn't fetched again.
    void downloadFiles(ClipboardSync::Shared& shared, ApolloClient& client, const clipbundle::bundle& bundle,
                       const clipbundle::file_manifest& manifest, bool manual, long startCount, ClipboardSync::Result& result)
    {
        HostState& state = hostState(shared.target.hostUuid);
        uint64_t bytes = clipbundle::manifest_bytes(manifest);
        QString what = filesText(manifest);

        // Automatic fetches start as the stream goes to the background, so what they say waits for it
        result.whenBack = !manual;

        std::vector<std::string> topLevel;
        if (ClipFiles::existing(shared.filesBase, manifest, topLevel)) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] The host's copied files are in the cache already");
        }
        else {
            if (!manual && bytes > clipbundle::k_max_auto_file_bytes) {
                result.toast = CS_TR("The PC's copied files are over 1 GB (%1): press ⌃⌥⇧G to copy them").arg(sizeText(bytes));
                return;
            }

            // Room for this one: the oldest copy goes
            ClipFiles::tidy(shared.filesBase, k_CopiesKept - 1, k_CopyMaxAgeSeconds);
            if (ClipFiles::freeBytes(shared.filesBase) < bytes + k_FreeSpaceMargin) {
                result.toast = CS_TR("The Mac doesn't have room for the PC's copied files (%1)").arg(sizeText(bytes));
                return;
            }

            ClipFiles::Incoming in;
            if (!ClipFiles::prepare(shared.filesBase, manifest, in)) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Couldn't make a folder for the host's copied files in %s", shared.filesBase.c_str());
                result.toast = CS_TR("Couldn't save the PC's copied files on the Mac");
                return;
            }

            uint64_t wanted = 0;    // the files not left out (names already taken)
            for (size_t i = 0; i < manifest.entries.size(); i++) {
                if (!in.local[i].empty()) {
                    wanted += manifest.entries[i].size;
                }
            }
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Copying %d files and folders (%llu bytes) from the host",
                        (int)manifest.entries.size(), (unsigned long long)wanted);

            ApolloClient::RequestOptions options;
            options.transferTimeoutMs = k_DownloadStallTimeoutMs;
            options.maxResponseBytes = static_cast<qint64>(clipbundle::k_file_chunk_bytes) + 64 * 1024;
            options.cancelled = [&shared] {
                return stopped(shared);
            };

            Progress progress(shared, CS_TR("Copying %1 from the PC (%2)... %3%").arg(what, sizeText(wanted)), wanted);
            for (size_t i = 0; i < manifest.entries.size(); i++) {
                const clipbundle::file_entry& entry = manifest.entries[i];
                if (in.local[i].empty() || entry.directory) {
                    continue;
                }
                for (uint64_t offset = 0; offset < entry.size;) {
                    if (stopped(shared)) {
                        ClipFiles::discard(in);
                        return;
                    }
                    uint64_t length = std::min<uint64_t>(entry.size - offset, clipbundle::k_file_chunk_bytes);
                    ApolloClient::Response response = client.request("actions/clipboard", chunkArguments("file", manifest.transfer, i, offset), nullptr, options);
                    if (response.httpStatus != 200 || static_cast<uint64_t>(response.body.size()) != length) {
                        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Copying a file from the host failed: HTTP %d, %d of %llu bytes %s",
                                    response.httpStatus, (int)response.body.size(), (unsigned long long)length, qPrintable(response.networkError));
                        ClipFiles::discard(in);
                        result.toast = response.httpStatus == 200 ? CS_TR("A file from the PC arrived incomplete; copy it again")
                                                                  : fileFailure(response, false);
                        return;
                    }
                    if (!ClipFiles::writeChunk(in, manifest, i, offset, viewOf(response.body))) {
                        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Couldn't write a file from the host in %s", in.folder.c_str());
                        ClipFiles::discard(in);
                        result.toast = CS_TR("Couldn't save the PC's copied files on the Mac");
                        return;
                    }
                    offset += length;
                    progress.add(length);
                }
            }
            if (!ClipFiles::complete(shared.filesBase, in, manifest, topLevel)) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Couldn't finish the host's copied files in %s", shared.filesBase.c_str());
                ClipFiles::discard(in);
                result.toast = CS_TR("Couldn't save the PC's copied files on the Mac");
                return;
            }
        }

        if (!manual && MacPasteboard::changeCount() != startCount) {
            // Something was copied on the Mac meanwhile; keep the newer copy. ⌃⌥⇧G puts these files
            // on the clipboard from the cache.
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] The Mac's clipboard changed while the host's files were copied; keeping it");
            return;
        }
        long count = MacPasteboard::writeFiles(topLevel);
        if (count == 0) {
            result.toast = CS_TR("Couldn't update the Mac's clipboard");
            return;
        }
        state.localChangeCount = count;
        state.localEtag = clipbundle::etag(bundle.items);
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Copied the host's copied files: %d files and folders, %llu bytes",
                    (int)manifest.entries.size(), (unsigned long long)bytes);

        // Shown now if the stream is in front; otherwise the Dock badge going says so
        result.whenBack = false;
        result.toast = CS_TR("Ready to paste: %1 from the PC (%2)").arg(what, sizeText(bytes));
    }

    // Sends a Finder copy's files once the PC has their list, on the worker thread: each file a
    // chunk at a time, then files-done, which puts them on the PC's clipboard. reply gets the PC's
    // clipboard state after that.
    bool uploadFiles(ClipboardSync::Shared& shared, ApolloClient& client, const ClipFiles::Outgoing& out,
                     clipbundle::bundle& reply, ClipboardSync::Result& result)
    {
        const clipbundle::file_manifest& manifest = out.manifest;

        // The PC leaves out the same entries (names already taken), so they aren't sent
        std::vector<std::string> local = clipbundle::local_paths(manifest);
        uint64_t total = 0;
        for (size_t i = 0; i < manifest.entries.size(); i++) {
            if (!local[i].empty()) {
                total += manifest.entries[i].size;
            }
        }

        ApolloClient::RequestOptions options;
        options.contentType = k_FileContentType;
        options.transferTimeoutMs = k_UploadStallTimeoutMs;
        options.cancelled = [&shared] {
            return stopped(shared);
        };

        Progress progress(shared, CS_TR("Sending %1 to the PC (%2)... %3%").arg(filesText(manifest), sizeText(total)), total);
        std::string data;
        for (size_t i = 0; i < manifest.entries.size(); i++) {
            const clipbundle::file_entry& entry = manifest.entries[i];
            if (local[i].empty() || entry.directory) {
                continue;
            }
            for (uint64_t offset = 0; offset < entry.size;) {
                if (stopped(shared)) {
                    return false;
                }
                ClipFiles::ReadResult read = ClipFiles::readChunk(out.paths[i], entry, offset, data);
                if (read != ClipFiles::ReadResult::Ok) {
                    bool changed = read == ClipFiles::ReadResult::Changed;
                    SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Couldn't read a copied file to send it%s",
                                changed ? " (it changed since it was copied)" : "");
                    result.toast = changed ? CS_TR("A copied file changed while it was being sent; copy it again")
                                           : CS_TR("Couldn't read one of the copied files");
                    return false;
                }

                QByteArray body(data.data(), static_cast<int>(data.size()));
                ApolloClient::Response response = client.request("actions/clipboard", chunkArguments("file", manifest.transfer, i, offset), &body, options);
                if (response.httpStatus != 200) {
                    SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Sending a file to the host failed: HTTP %d %s",
                                response.httpStatus, qPrintable(response.networkError));
                    result.toast = fileFailure(response, true);
                    return false;
                }
                offset += data.size();
                progress.add(data.size());
            }
        }

        QByteArray none;
        ApolloClient::Response response = client.request("actions/clipboard", "type=files-done&transfer=" + QString::fromStdString(manifest.transfer),
                                                         &none, options);
        if (response.httpStatus != 200) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] The host didn't finish the files: HTTP %d %s",
                        response.httpStatus, qPrintable(response.networkError));
            result.toast = fileFailure(response, true);
            return false;
        }
        if (!clipbundle::decode(viewOf(response.body), reply)) {
            reply = clipbundle::bundle();
        }
        return true;
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

        // Files copied in Finder: their list goes first in the bundle, and uploadFiles() sends them
        // once the PC has it
        ClipFiles::Outgoing outgoing;
        bool sendFiles = false;
        QString filesNote;      // why they aren't sent
        if (!snapshot.files.empty() && shared.files && shared.hostTakesFiles && state.transport != Transport::Text) {
            if (!shared.mayUploadFiles) {
                if (manual || !s_FilePermissionToastShown.exchange(true)) {
                    filesNote = CS_TR("Apollo doesn't allow this device to upload files (File Upload permission)");
                }
            }
            else if (!ClipFiles::share(snapshot.files, outgoing)) {
                filesNote = CS_TR("The copied files are too many or too large to send (over 10,000 files or 20 GB)");
            }
            else if (outgoing.manifest.entries.empty()) {
                filesNote = CS_TR("The copied files couldn't be read");
            }
            else if (!manual && clipbundle::manifest_bytes(outgoing.manifest) > clipbundle::k_max_auto_file_bytes) {
                // Only the shortcut moves this much, and not the rest of the copy on its own either
                result.toast = CS_TR("The copied files are over 1 GB (%1): press ⌃⌥⇧U to send them")
                                       .arg(sizeText(clipbundle::manifest_bytes(outgoing.manifest)));
                state.localChangeCount = snapshot.changeCount;
                return;
            }
            else {
                sendFiles = true;
                snapshot.items.insert(snapshot.items.begin(), clipbundle::item { clipbundle::k_files_type, clipbundle::encode_manifest(outgoing.manifest) });
                if (outgoing.unreadable > 0) {
                    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] %d of the copied files or folders couldn't be read, and aren't sent",
                                (int)outgoing.unreadable);
                }
            }
        }

        if (snapshot.items.empty()) {
            if (manual) {
                result.toast = filesNote.isEmpty() ? CS_TR("The clipboard has nothing to send") : filesNote;
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
                return shared.ended.load() || s_AppQuitting.load();
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
                bool decoded = clipbundle::decode(viewOf(response.body), reply);
                if (sendFiles && decoded && !(reply.flags & clipbundle::flag_files_skipped)) {
                    // The PC waits for the files, and its clipboard changes once they're all there
                    if (!uploadFiles(shared, client, outgoing, reply, result)) {
                        if (!stopped(shared)) {
                            // Not sent again on its own, which could mean another gigabyte; the shortcut tries again
                            state.localChangeCount = snapshot.changeCount;
                        }
                        return;
                    }
                    result.toast = CS_TR("Ready to paste on the PC: %1 (%2)")
                                       .arg(filesText(outgoing.manifest), sizeText(clipbundle::manifest_bytes(outgoing.manifest)));
                }
                else if (sendFiles) {
                    // Nobody is signed in to Windows, or its settings changed: it has the rest of the copy
                    filesNote = CS_TR("The PC didn't take the copied files");
                }
                if (decoded) {
                    state.token = reply.token;
                    state.hostEtag = reply.etag;
                }
                state.localChangeCount = snapshot.changeCount;
                state.localEtag = etag;
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Sent the clipboard to the host: %s (%d bytes on the wire)",
                            qPrintable(describe(bundle.items)), (int)encoded.size());
                if (result.toast.isEmpty()) {
                    result.toast = filesNote.isEmpty() ? successToast(bundle.items, encoded.size(), manual, true) : filesNote;
                }
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
            bool askForFiles = shared.files && shared.hostTakesFiles && shared.mayDownloadFiles && !shared.quitting;
            if (askForFiles) {
                arguments += "&files=1";
            }
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
                QString filesNote;      // why the PC's copied files didn't come
                if (bundle.flags & clipbundle::flag_files_skipped) {
                    filesNote = skippedFilesNote(shared, manual, askForFiles);
                }
                if (bundle.items.empty()) {
                    // Never wipe the local clipboard because the PC's is empty or private
                    if (!filesNote.isEmpty()) {
                        result.toast = filesNote;
                        result.whenBack = !manual;
                    }
                    else if (manual) {
                        result.toast = (bundle.flags & clipbundle::flag_concealed) ? CS_TR("The PC's clipboard holds private content")
                                                                                    : CS_TR("The PC's clipboard is empty");
                    }
                    return;
                }
                state.hostEtag = bundle.etag;

                // Files copied in Explorer
                auto files = std::find_if(bundle.items.begin(), bundle.items.end(), [](const clipbundle::item& it) {
                    return it.type == clipbundle::k_files_type;
                });
                if (files != bundle.items.end()) {
                    clipbundle::file_manifest manifest;
                    if (askForFiles && clipbundle::decode_manifest(files->data, manifest, &error)) {
                        downloadFiles(shared, client, bundle, manifest, manual, startCount, result);
                        return;
                    }
                    SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Couldn't read the host's list of copied files: %s", error.c_str());
                    bundle.items.erase(files);
                    if (bundle.items.empty()) {
                        if (manual) {
                            result.toast = CS_TR("The clipboard data wasn't understood (update Apollo and LuzLunar)");
                        }
                        return;
                    }
                }

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
                if (!filesNote.isEmpty()) {
                    result.toast = filesNote;
                    result.whenBack = !manual;
                }
                else {
                    result.toast = successToast(bundle.items, static_cast<size_t>(response.body.size()), manual, false);
                }
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
      m_HasFocus(true),
      m_BadgeShown(false),
      m_ToastGeneration(0),
      m_ToastShowing(false)
{
    // Register the event type on this thread before any worker uses it
    eventType();

    m_Shared->target = ApolloClient::targetFor(computer);
    m_Shared->rich = m_Rich;
    QString cache = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (m_Rich && ForkPreferences::get()->clipboardFiles() && !cache.isEmpty()) {
        m_Shared->files = true;
        m_Shared->filesBase = (cache + "/Clipboard Files").toStdString();
    }

    // Requests run in order, so the permission check finishes before the first upload
    submit(Kind::Permissions, false);
    if (m_Automatic) {
        upload(false);
    }
}

ClipboardSync::~ClipboardSync()
{
    // Uploads and file copies in flight stop (the PC won't take them after the stream), and
    // requests still queued or in flight drop their results. A download in flight still updates
    // the clipboard.
    m_Shared->ended = true;
    {
        std::lock_guard<std::mutex> lock(m_Shared->mutex);
        m_Shared->alive = false;
    }
    if (m_BadgeShown) {
        MacIntegration::setDockBadge(QString());
    }
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

    if (event.type == SDL_WINDOWEVENT) {
        if (event.window.event == SDL_WINDOWEVENT_FOCUS_GAINED) {
            m_HasFocus = true;
            if (!m_ToastWhenBack.isEmpty()) {
                showToast(m_ToastWhenBack);
                m_ToastWhenBack.clear();
            }
        }
        else if (event.window.event == SDL_WINDOWEVENT_FOCUS_LOST) {
            m_HasFocus = false;
        }
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
        case Kind::Permissions: {
            ApolloClient::HostInfo info = client.hostInfo();
            result.permissions = info.permissions;
            shared->hostTakesFiles = info.clipboardFiles;
            shared->mayUploadFiles = info.permissions >= 0 && (info.permissions & k_PermFileUpload) != 0;
            shared->mayDownloadFiles = info.permissions >= 0 && (info.permissions & k_PermFileDownload) != 0;
            if (info.clipboardFiles) {
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] The host takes file copies; Apollo permissions: upload %s, download %s",
                            shared->mayUploadFiles ? "yes" : "no", shared->mayDownloadFiles ? "yes" : "no");
            }
            if (shared->files) {
                // Copies from the PC past the newest few or older than a day, and any left unfinished
                ClipFiles::tidy(shared->filesBase, k_CopiesKept, k_CopyMaxAgeSeconds);
            }
            break;
        }
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
    if (result.setBadge) {
        MacIntegration::setDockBadge(result.badge);
        m_BadgeShown = !result.badge.isEmpty();
    }
    if (result.kind == Kind::Notice) {
        if (!result.toast.isEmpty()) {
            showToast(result.toast);
        }
        return;
    }
    if (result.rich) {
        if (result.failed) {
            reportFailure(result);
        }
        else if (!result.toast.isEmpty()) {
            if (result.whenBack && !m_HasFocus) {
                // Out of sight now, like the stream
                m_ToastWhenBack = result.toast;
            }
            else {
                showToast(result.toast);
            }
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
    // wait briefly for the host's clipboard to arrive. There's no time for files.
    m_Shared->quitting = true;
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
