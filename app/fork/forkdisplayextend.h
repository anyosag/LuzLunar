#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QList>
#include <QString>
#include <QStringList>

#include <atomic>
#include <vector>

#include "forkdisplayroute.h"

// The DisplayExtend Host's socket for LuzLunar. DisplayExtend makes the Mac's virtual display that it
// streams to an iMac; through this socket LuzLunar asks the Host (on this Mac) about the iMac, has
// the iMac time its connects to the PC, pairs the iMac's Moonlight with Apollo, and hands the iMac
// over to that Moonlight for a direct stream from the PC (forkdisplayroute.*). The iMac never runs
// LuzLunar: the Host relays every request to its own client there.
//
// JSON lines over a Unix socket, at ~/Library/Application Support/DisplayExtend/luzlunar.sock:
// requests {"id":n,"op":...}, replies {"id":n,"ok":bool,"error"?:...}, events {"event":...}.
// Closing the socket ends a direct stream the connection started. Blocking: use from worker threads.
class ForkDisplayExtend
{
public:
    // What "status" reports
    struct Status {
        bool ok = false;                  // the Host answered
        bool imacConnected = false;
        QString imacAddress;
        uint32_t displayId = 0;           // the virtual display on this Mac
        int width = 0, height = 0, hz = 0;
        double p50Ms = 0, p95Ms = 0;      // DisplayExtend's live delay, capture to the iMac's refresh
        int frames = 0;
        bool moonlightVerified = false;
        QString moonlightVersion;
        QStringList pairedHostIds;        // the PCs the iMac's Moonlight is paired with (their uniqueid)
        bool directSupported = false;
        // direct.codecs and imac.hardwareDecoders (DisplayExtend 1.6.5); H.264 alone before
        ForkDisplayRoute::ImacCodecs codecs;
        QString error;
    };

    // The parameters of a direct stream from the PC to the iMac
    struct Direct {
        QString address;                  // the PC address the iMac connects to (with :port if not the default)
        QString app;                      // the app's name on the host
        QString hostUniqueId;             // the PC's uniqueid, checked before streaming
        int width = 0, height = 0, fps = 0, bitrateKbps = 0;
        ForkDisplayRoute::Codec codec = ForkDisplayRoute::Codec::H264;   // sent only when it isn't H.264
    };

    static QString socketPath();

    // Whether the Host's socket is there (it may still not answer)
    static bool available();

    ForkDisplayExtend();
    ~ForkDisplayExtend();

    ForkDisplayExtend(const ForkDisplayExtend&) = delete;
    ForkDisplayExtend& operator=(const ForkDisplayExtend&) = delete;

    bool open(int timeoutMs);
    bool isOpen() const { return m_Fd >= 0; }
    void close();

    // From another thread: makes a request or wait in progress give up at once (the connection
    // is then useless, and closing it is up to the thread that owns it)
    void interrupt();

    // Sends a request and waits for its reply; events that arrive meanwhile are kept for
    // nextEvent(). An empty object with *error set on failure.
    QJsonObject request(const QString& op, const QJsonObject& arguments, int timeoutMs, QString* error = nullptr);

    // The next event, waiting up to timeoutMs; empty on timeout or a closed socket
    QJsonObject nextEvent(int timeoutMs);

    Status status(int timeoutMs);
    std::vector<ForkDisplayRoute::Probe> probe(const QStringList& addresses, int port, int count, int timeoutMs);
    bool pairMoonlight(const QString& address, const QString& pin, int timeoutMs, QString* error);

    // Starts the direct stream, then waits until the iMac's Moonlight streams (true) or fails
    bool startDirect(const Direct& direct, int timeoutMs, QString* error);
    void stopDirect(int timeoutMs);

private:
    bool writeLine(const QByteArray& line);
    bool readLine(QByteArray& line, int timeoutMs);

    std::atomic<int> m_Fd { -1 };   // read by interrupt() on another thread
    int m_NextId = 1;
    QByteArray m_Buffer;
    QList<QJsonObject> m_Events;
};

namespace ForkRouteProbe
{
    // count timed TCP connects to address:port, after one that isn't counted (it warms up ARP,
    // routes and the Wi-Fi radio); each gives up after timeoutMs
    ForkDisplayRoute::Probe tcpConnects(const QString& address, uint16_t port, int count, int timeoutMs);
}
