#include "apolloclient.h"

#include <QEventLoop>
#include <QNetworkAccessManager>
#include <QNetworkProxy>
#include <QNetworkReply>
#include <QReadLocker>
#include <QTimer>
#include <QUuid>

#include "backend/identitymanager.h"
#include "backend/nvcomputer.h"
#include "backend/nvhttp.h"

ApolloClient::Target ApolloClient::targetFor(NvComputer* computer)
{
    QReadLocker lock(&computer->lock);

    Target target;
    target.address = computer->activeAddress;
    target.httpsPort = computer->activeHttpsPort;
    target.serverCert = computer->serverCert;
    target.useTrueUid = !computer->isNvidiaServerSoftware;
    target.hostUuid = computer->uuid;
    return target;
}

ApolloClient::ApolloClient(const Target& target)
    : m_Target(target)
{
}

qint64 ApolloClient::permissions()
{
    if (m_Target.address.isNull() || m_Target.serverCert.isNull()) {
        return -1;
    }

    try {
        NvHTTP http(m_Target.address, m_Target.httpsPort, m_Target.serverCert, m_Target.useTrueUid);
        QString permission = NvHTTP::getXmlString(http.getServerInfo(NvHTTP::NVLL_ERROR, true), "Permission");

        bool ok;
        qint64 bits = permission.toLongLong(&ok);
        return ok ? bits : -1;
    }
    catch (...) {
        return -1;
    }
}

ApolloClient::Response ApolloClient::request(const QString& command, const QString& arguments, const QByteArray* postBody, int timeoutMs)
{
    RequestOptions options;
    options.timeoutMs = timeoutMs;
    return request(command, arguments, postBody, options);
}

ApolloClient::Response ApolloClient::request(const QString& command, const QString& arguments, const QByteArray* postBody, const RequestOptions& options)
{
    Response response;
    if (m_Target.address.isNull() || m_Target.serverCert.isNull()) {
        response.networkError = "Host isn't paired over HTTPS";
        return response;
    }

    QNetworkAccessManager nam;
    nam.setProxy(QNetworkProxy(QNetworkProxy::NoProxy));

    // Reuse NvHTTP's HTTPS base URL so addresses and ports are formatted the same way
    NvHTTP http(m_Target.address, m_Target.httpsPort, m_Target.serverCert, m_Target.useTrueUid, &nam);
    QUrl url(http.m_BaseUrlHttps);
    url.setPath("/" + command);
    url.setQuery("uniqueid=" + (m_Target.useTrueUid ? IdentityManager::get()->getUniqueId() : "0123456789ABCDEF") +
                 "&uuid=" + QUuid::createUuid().toRfc4122().toHex() +
                 (arguments.isEmpty() ? "" : "&" + arguments));

    QNetworkRequest request(url);
    request.setSslConfiguration(IdentityManager::get()->getSslConfig());
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
#endif
#if QT_VERSION >= QT_VERSION_CHECK(6, 3, 0)
    request.setAttribute(QNetworkRequest::ConnectionCacheExpiryTimeoutSecondsAttribute, 0);
#endif
    if (options.transferTimeoutMs > 0) {
        // Large clipboard transfers can take a while on a slow connection, but shouldn't stall
        request.setTransferTimeout(options.transferTimeoutMs);
    }

    // Like NvHTTP::handleSslErrors(): the host's self-signed certificate is pinned at pairing time
    QSslCertificate serverCert = m_Target.serverCert;
    QObject::connect(&nam, &QNetworkAccessManager::sslErrors, [serverCert](QNetworkReply* reply, const QList<QSslError>& errors) {
        for (const QSslError& error : errors) {
            if (error.certificate() != serverCert) {
                return;
            }
        }
        reply->ignoreSslErrors(errors);
    });

    QNetworkReply* reply;
    if (postBody != nullptr) {
        request.setHeader(QNetworkRequest::ContentTypeHeader, options.contentType);
        reply = nam.post(request, *postBody);
    }
    else {
        reply = nam.get(request);
    }

    QEventLoop loop;
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    if (options.transferTimeoutMs <= 0) {
        QTimer::singleShot(options.timeoutMs, &loop, &QEventLoop::quit);
    }

    bool cancelled = false;
    QTimer cancelPoll;
    if (options.cancelled) {
        QObject::connect(&cancelPoll, &QTimer::timeout, &loop, [&]() {
            if (options.cancelled()) {
                cancelled = true;
                loop.quit();
            }
        });
        cancelPoll.start(100);
    }

    bool tooLarge = false;
    if (options.maxResponseBytes > 0) {
        QObject::connect(reply, &QNetworkReply::downloadProgress, &loop, [&](qint64 received, qint64 total) {
            if (received > options.maxResponseBytes || total > options.maxResponseBytes) {
                tooLarge = true;
                loop.quit();
            }
        });
    }

    loop.exec(QEventLoop::ExcludeUserInputEvents);

    if (!reply->isFinished()) {
        reply->abort();
        response.networkError = cancelled ? "Cancelled" : (tooLarge ? "Response too large" : "Request timed out");
    }
    else {
        response.httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        response.body = reply->readAll();
        if (response.httpStatus == 0) {
            // A transfer timeout aborts the reply itself
            response.networkError = reply->error() == QNetworkReply::OperationCanceledError ? QString("Request timed out") : reply->errorString();
        }
    }

    delete reply;
    return response;
}
