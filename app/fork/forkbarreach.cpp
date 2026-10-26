#include "forkbarreach.h"

#include <mutex>
#include <optional>

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QReadLocker>
#include <QThreadPool>

#include "apolloclient.h"
#include "backend/nvcomputer.h"
#include "forkevents.h"

struct ForkBarReach::Shared
{
    ApolloClient::Target target;
    QString hostName;

    std::mutex mutex;
    bool alive = true;
    bool gaveUp = false;        // the PC can't say (an older Apollo, no permission): no more questions
    bool getOnly = false;       // an Apollo before the pulse: GET, and the pulses drawn over the picture
    bool saidNoPulse = false;
    bool canPulse = true;       // as the PC's last answer said
    std::optional<BarReach::Cursor> answer;
};

namespace
{
    // An answer is only worth having while the push lasts
    const int k_TimeoutMs = 1000;
    // While the pulses run, a push that stops is seen this often
    const Uint32 k_TickMs = 50;

    const int k_AnswerCode = 0;
    const int k_TickCode = 1;

    Uint32 eventType()
    {
        static Uint32 type = ForkEvents::registerType();
        return type;
    }

    QThreadPool* workerPool()
    {
        // The pool belongs to the app, so a stream can end without waiting for a question in flight
        static QThreadPool* pool = [] {
            QThreadPool* newPool = new QThreadPool(QCoreApplication::instance());
            newPool->setMaxThreadCount(1);
            return newPool;
        }();
        return pool;
    }

    bool alive(const std::shared_ptr<ForkBarReach::Shared>& shared)
    {
        std::lock_guard<std::mutex> lock(shared->mutex);
        return shared->alive;
    }

    Uint32 tick(Uint32 interval, void*)
    {
        SDL_Event event = {};
        event.type = eventType();
        event.user.code = k_TickCode;
        SDL_PushEvent(&event);
        return interval;
    }

    std::optional<BarReach::Cursor> parse(const ApolloClient::Response& response, bool* canPulse)
    {
        if (response.httpStatus != 200) {
            return std::nullopt;
        }
        QJsonObject json = QJsonDocument::fromJson(response.body).object();
        for (const char* key : { "x", "y", "width", "height" }) {
            if (!json.value(QLatin1String(key)).isDouble()) {
                return std::nullopt;
            }
        }
        BarReach::Cursor cursor;
        cursor.x = json.value(QStringLiteral("x")).toInt();
        cursor.y = json.value(QStringLiteral("y")).toInt();
        cursor.width = json.value(QStringLiteral("width")).toInt();
        cursor.height = json.value(QStringLiteral("height")).toInt();
        cursor.shown = json.value(QStringLiteral("shown")).toBool();
        cursor.pulsing = json.value(QStringLiteral("pulsing")).toBool();
        *canPulse = json.value(QStringLiteral("canPulse")).toBool();
        return cursor;
    }

    // On the worker: POST /actions/cursor, or GET from an Apollo before the pulse; an answer that's
    // wanted goes to the main thread
    void ask(const std::shared_ptr<ForkBarReach::Shared>& shared, int pulses, bool ifAtTop, bool reduceMotion, bool wanted)
    {
        bool getOnly;
        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            getOnly = shared->getOnly;
        }
        if (getOnly && !wanted) {
            return;
        }

        ApolloClient::RequestOptions options;
        options.contentType = "application/json";
        options.timeoutMs = k_TimeoutMs;
        options.maxResponseBytes = 4096;
        options.cancelled = [shared] { return !alive(shared); };
        ApolloClient client(shared->target);

        QByteArray body = QJsonDocument(QJsonObject {
            { QStringLiteral("pulse"), pulses },
            { QStringLiteral("ifAtTop"), ifAtTop },
            { QStringLiteral("reduceMotion"), reduceMotion },
        }).toJson(QJsonDocument::Compact);
        ApolloClient::Response response = client.request(QStringLiteral("actions/cursor"), QString(), getOnly ? nullptr : &body, options);
        bool refused = response.httpStatus != 200 && response.httpStatus != 401 && response.httpStatus != 403 && response.httpStatus != 503;
        if (!getOnly && refused && alive(shared)) {
            // An Apollo that says where its pointer is but doesn't pulse it yet has no POST here: it
            // answers 404 or closes the connection. GET asks it this time, and from then on once it
            // said 404, so a lost answer doesn't end the PC's pulses for the stream.
            ApolloClient::Response get = client.request(QStringLiteral("actions/cursor"), QString(), nullptr, options);
            if (get.httpStatus == 200) {
                std::lock_guard<std::mutex> lock(shared->mutex);
                if (!shared->saidNoPulse) {
                    shared->saidNoPulse = true;
                    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: %s's Apollo doesn't pulse its pointer; it's pulsed over the picture",
                                qPrintable(shared->hostName));
                }
                shared->getOnly = response.httpStatus == 404 || response.httpStatus == 405;
                shared->canPulse = false;
            }
            response = get;
            if (!wanted) {
                return;
            }
        }

        bool canPulse = false;
        std::optional<BarReach::Cursor> cursor = parse(response, &canPulse);
        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            if (!shared->alive) {
                return;
            }
            if (cursor) {
                shared->canPulse = canPulse && !shared->getOnly;
            }
            // 403 is a stream the PC doesn't see yet or any more, 503 a secure desktop: worth asking again
            bool cant = response.httpStatus == 400 || response.httpStatus == 401 || response.httpStatus == 404;
            if (cant && !shared->gaveUp) {
                shared->gaveUp = true;
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                            "[fork] Notch bar: %s can't say where its pointer is (HTTP %d), so the pointer reaches the bar with Control-Option-Shift-N only",
                            qPrintable(shared->hostName), response.httpStatus);
            }
            if (!wanted) {
                return;
            }
            shared->answer = cursor;
        }
        SDL_Event event = {};
        event.type = eventType();
        event.user.code = k_AnswerCode;
        SDL_PushEvent(&event);
    }
}

ForkBarReach::ForkBarReach(NvComputer* computer, Callbacks callbacks)
    : m_Shared(std::make_shared<Shared>()),
      m_Callbacks(std::move(callbacks))
{
    // Both on this thread before a worker uses them
    eventType();
    workerPool();

    m_Shared->target = ApolloClient::targetFor(computer);
    QReadLocker lock(&computer->lock);
    m_Shared->hostName = computer->name;
}

ForkBarReach::~ForkBarReach()
{
    if (m_TickTimer != 0) {
        SDL_RemoveTimer(m_TickTimer);
    }
    // A question in flight gives up, and its answer is dropped
    std::lock_guard<std::mutex> lock(m_Shared->mutex);
    m_Shared->alive = false;
}

void ForkBarReach::moved(int dx, int dy, double dxPoints, double dyPoints)
{
    // A button held is a drag, as a window up to the top to fill the screen
    bool buttonDown = SDL_GetMouseState(nullptr, nullptr) != 0;
    apply(m_Tracker.moved(dx, dy, dxPoints, dyPoints, buttonDown, SDL_GetTicks()));
}

bool ForkBarReach::pulseOnce()
{
    {
        std::lock_guard<std::mutex> lock(m_Shared->mutex);
        if (m_Shared->gaveUp || m_Shared->getOnly || !m_Shared->canPulse) {
            return false;
        }
    }
    send(1, false, false);
    return true;
}

std::optional<std::pair<double, double>> ForkBarReach::pointer() const
{
    if (!m_Tracker.known() || m_Tracker.width() <= 0 || m_Tracker.height() <= 0) {
        return std::nullopt;
    }
    return std::make_pair((m_Tracker.x() + 0.5) / m_Tracker.width(), (m_Tracker.y() + 0.5) / m_Tracker.height());
}

int ForkBarReach::displayHeight() const
{
    return m_Tracker.known() ? m_Tracker.height() : 0;
}

void ForkBarReach::send(int pulses, bool ifAtTop, bool answer)
{
    std::shared_ptr<Shared> shared = m_Shared;
    bool reduce = m_Callbacks.reduceMotion && m_Callbacks.reduceMotion();
    workerPool()->start([shared, pulses, ifAtTop, reduce, answer] { ask(shared, pulses, ifAtTop, reduce, answer); });
}

void ForkBarReach::apply(const BarReach::Step& step)
{
    switch (step.action) {
    case BarReach::Action::None:
        break;
    case BarReach::Action::Ask: {
        bool gaveUp;
        {
            std::lock_guard<std::mutex> lock(m_Shared->mutex);
            gaveUp = m_Shared->gaveUp;
        }
        if (gaveUp) {
            m_Tracker.unanswered();
        }
        else {
            // Where it is, and pulse it twice if it's at the top
            send(BarReach::k_Pulses, true, true);
        }
        break;
    }
    case BarReach::Action::PulseHere:
        if (m_Callbacks.pulseHere) {
            m_Callbacks.pulseHere(BarReach::k_Pulses);
        }
        break;
    case BarReach::Action::Cancel:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: the push up stopped before the pointer went");
        if (step.pcPulses) {
            send(0, false, false);
        }
        else if (m_Callbacks.settleHere) {
            m_Callbacks.settleHere();
        }
        break;
    case BarReach::Action::HandOver:
        if (m_Callbacks.handOver) {
            m_Callbacks.handOver(step.fraction);
        }
        break;
    }
    updateTicks();
}

void ForkBarReach::updateTicks()
{
    if (m_Tracker.busy() && m_TickTimer == 0) {
        m_TickTimer = SDL_AddTimer(k_TickMs, tick, nullptr);
    }
    else if (!m_Tracker.busy() && m_TickTimer != 0) {
        SDL_RemoveTimer(m_TickTimer);
        m_TickTimer = 0;
    }
}

bool ForkBarReach::handleEvent(const SDL_Event& event)
{
    if (event.type != eventType()) {
        return false;
    }
    if (event.user.code == k_TickCode) {
        apply(m_Tracker.tick(SDL_GetTicks()));
        return true;
    }

    std::optional<BarReach::Cursor> answer;
    {
        std::lock_guard<std::mutex> lock(m_Shared->mutex);
        answer = m_Shared->answer;
        m_Shared->answer.reset();
    }
    if (!answer) {
        m_Tracker.unanswered();
        updateTicks();
        return true;
    }
    apply(m_Tracker.answered(*answer, SDL_GetTicks()));
    return true;
}
