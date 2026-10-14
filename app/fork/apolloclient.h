#pragma once

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
    };

    struct Response {
        int httpStatus = 0;      // 0 if the request didn't get an HTTP response
        QByteArray body;
        QString networkError;    // set when httpStatus is 0
    };

    static Target targetFor(NvComputer* computer);

    explicit ApolloClient(const Target& target);

    // The <Permission> bits Apollo reports for this client, or -1 if the host isn't Apollo or didn't answer
    qint64 permissions();

    // GET command?arguments, or POST postBody to it when postBody isn't null
    Response request(const QString& command, const QString& arguments, const QByteArray* postBody, int timeoutMs);

private:
    Target m_Target;
};
