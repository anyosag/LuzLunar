#pragma once

#include <functional>

#include <QByteArray>
#include <QSslCertificate>
#include <QString>

#include "backend/nvaddress.h"

class NvComputer;

// Blocking HTTPS requests to Apollo's protocol extensions (e.g. /actions/clipboard), authenticated
// with Moonlight's paired client certificate like NvHTTP. Use from a worker thread.
class ApolloClient
{
public:
    // A host's connection details, captured on the main thread
    struct Target {
        NvAddress address;
        uint16_t httpsPort = 0;
        QSslCertificate serverCert;
        bool useTrueUid = true;
        QString hostUuid;
    };

    struct Response {
        int httpStatus = 0;      // 0 if the request didn't get an HTTP response
        QByteArray body;
        QString networkError;    // set when httpStatus is 0
    };

    struct RequestOptions {
        QByteArray contentType = "text/plain; charset=utf-8";   // of the POST body
        int timeoutMs = 3000;           // for the whole request, unless transferTimeoutMs is set
        int transferTimeoutMs = 0;      // instead: give up only after this long without any progress
        qint64 maxResponseBytes = 32 * 1024 * 1024;   // give up on larger responses (the host decides what it sends); 0 for no limit
        std::function<bool()> cancelled;    // polled while waiting; true aborts the request
    };

    static Target targetFor(NvComputer* computer);

    explicit ApolloClient(const Target& target);

    // What /serverinfo says of this client and the host
    struct HostInfo {
        qint64 permissions = -1;     // the <Permission> bits Apollo reports, or -1 if the host isn't Apollo or didn't answer
        bool clipboardFiles = false; // <LuzClipboardFiles>: LuzLunar's Apollo takes file copies through the clipboard
    };

    HostInfo hostInfo();

    // GET command?arguments, or POST postBody to it when postBody isn't null
    Response request(const QString& command, const QString& arguments, const QByteArray* postBody, int timeoutMs);
    Response request(const QString& command, const QString& arguments, const QByteArray* postBody, const RequestOptions& options);

private:
    Target m_Target;
};
