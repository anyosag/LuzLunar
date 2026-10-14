#pragma once

#include <memory>

#include <QString>

#include "SDL_compat.h"
#include "apolloclient.h"

class NvComputer;

// Syncs the clipboard with an Apollo host during a stream through Apollo's /actions/clipboard
// endpoint. Lives on the SDL main thread. Requests run one at a time on a worker thread, and their
// results come back as SDL events, because the Qt event loop is paused while streaming.
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

private:
    enum class Kind { Permissions, Upload, Download };

    struct Result {
        Kind kind;
        bool manual;
        ApolloClient::Response response;
        qint64 permissions;
        QString text;   // the uploaded text
    };

    struct Shared;

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
    bool m_HostSupportsSync;    // false once the host turns out not to be Apollo
    bool m_PermissionsKnown;
    bool m_CanSend;
    bool m_CanReceive;
    QString m_LastKnownHost;    // what we believe the host's clipboard holds, with LF line endings
    QString m_PendingUpload;
    QString m_ToastText;
    unsigned m_ToastGeneration;
    bool m_ToastShowing;
};
