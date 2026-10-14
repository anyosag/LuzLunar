#pragma once

#include <functional>
#include <memory>

#include <QString>

#include "SDL_compat.h"
#include "apolloclient.h"

class NvComputer;

// Syncs the clipboard with an Apollo host during a stream through Apollo's /actions/clipboard
// endpoint. Lives on the SDL main thread. Requests run one at a time on a worker thread, and their
// results come back as SDL events, because the Qt event loop is paused while streaming.
//
// On macOS with LuzLunar's Apollo build, text, formatting (RTF and HTML), images and Office content
// travel together as a clipbundle (type=bundle, see clipbundle.h), and only clipboard content that
// changed is transferred. Other hosts, and other platforms, sync plain text (type=text).
//
// Automatic mode sends the local clipboard when the stream starts or regains focus, and fetches
// the host's clipboard when the stream loses focus or ends. Ctrl+Option+Shift+U / G send and
// fetch manually in either mode.
class ClipboardSync
{
public:
    ClipboardSync(NvComputer* computer, bool automatic);
    ~ClipboardSync();

    ClipboardSync(const ClipboardSync&) = delete;
    ClipboardSync& operator=(const ClipboardSync&) = delete;

    void handleEvent(const SDL_Event& event);

    void sendToHost();
    void receiveFromHost();

    // Messages go to the sink first, like LuzLunar's notch bar. When it returns false, they show
    // in Moonlight's status overlay.
    void setMessageSink(std::function<bool(const QString&)> sink);

    enum class Kind { Permissions, Upload, Download, Notice };

    struct Result {
        Kind kind;
        bool manual = false;
        ApolloClient::Response response;
        qint64 permissions = -1;
        QString text;           // text sync: the uploaded text
        bool rich = false;      // rich sync: the worker already applied the result
        bool failed = false;    // rich sync: response holds the failure to report
        QString toast;          // rich sync and notices: a message to show
    };

    struct Shared;

private:
    void upload(bool manual);
    void download(bool manual);
    void submit(Kind kind, bool manual, const QString& text = QString());
    void processResults();
    void apply(const Result& result);
    void reportFailure(const Result& result);
    void downloadBeforeQuit();
    void showToast(const QString& text);
    void hideToast(unsigned generation);

    std::shared_ptr<Shared> m_Shared;
    bool m_Automatic;
    bool m_Rich;                // rich sync through the Mac pasteboard
    bool m_HostSupportsSync;    // false once the host turns out not to be Apollo
    bool m_PermissionsKnown;
    bool m_CanSend;
    bool m_CanReceive;
    QString m_LastKnownHost;    // text sync: what we believe the host's clipboard holds, with LF line endings
    QString m_PendingUpload;    // text sync
    QString m_ToastText;
    unsigned m_ToastGeneration;
    bool m_ToastShowing;
    std::function<bool(const QString&)> m_MessageSink;
};
