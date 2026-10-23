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
    bool gaveUp = false;    // the PC can't say (an older Apollo, no permission): no more questions
    std::optional<BarReach::Cursor> answer;
};

namespace
{
    // An answer is only worth having while the push lasts
    const int k_TimeoutMs = 1000;

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

    std::optional<BarReach::Cursor> parse(const ApolloClient::Response& response)
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
        return cursor;
    }

    // On the worker: GET /actions/cursor, then the answer to the main thread
    void ask(const std::shared_ptr<ForkBarReach::Shared>& shared)
    {
        ApolloClient::RequestOptions options;
        options.timeoutMs = k_TimeoutMs;
        options.maxResponseBytes = 4096;
        options.cancelled = [shared] { return !alive(shared); };
        ApolloClient client(shared->target);
        ApolloClient::Response response = client.request(QStringLiteral("actions/cursor"), QString(), nullptr, options);
        std::optional<BarReach::Cursor> cursor = parse(response);

        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            if (!shared->alive) {
                return;
            }
            // 403 is a stream the PC doesn't see yet or any more, 503 a secure desktop: worth asking again
            bool cant = response.httpStatus == 400 || response.httpStatus == 401 || response.httpStatus == 404;
            if (cant && !shared->gaveUp) {
                shared->gaveUp = true;
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                            "[fork] Notch bar: %s can't say where its pointer is (HTTP %d), so the pointer reaches the bar with Control-Option-Shift-N only",
                            qPrintable(shared->hostName), response.httpStatus);
            }
            shared->answer = cursor;
        }
        SDL_Event event = {};
        event.type = eventType();
        SDL_PushEvent(&event);
    }
}

ForkBarReach::ForkBarReach(NvComputer* computer, std::function<void(double)> handOver)
    : m_Shared(std::make_shared<Shared>()),
      m_HandOver(std::move(handOver))
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
    // A question in flight gives up, and its answer is dropped
    std::lock_guard<std::mutex> lock(m_Shared->mutex);
    m_Shared->alive = false;
}

void ForkBarReach::moved(int dx, int dy, double dxPoints, double dyPoints)
{
    // A button held is a drag, as a window up to the top to fill the screen
    bool buttonDown = SDL_GetMouseState(nullptr, nullptr) != 0;
    if (!m_Tracker.moved(dx, dy, dxPoints, dyPoints, buttonDown, SDL_GetTicks())) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(m_Shared->mutex);
        if (m_Shared->gaveUp) {
            m_Tracker.unanswered();
            return;
        }
    }
    std::shared_ptr<Shared> shared = m_Shared;
    workerPool()->start([shared] { ask(shared); });
}

void ForkBarReach::placed(double fx, double fy)
{
    m_Tracker.placed(fx, fy);
}

bool ForkBarReach::handleEvent(const SDL_Event& event)
{
    if (event.type != eventType()) {
        return false;
    }
    std::optional<BarReach::Cursor> answer;
    {
        std::lock_guard<std::mutex> lock(m_Shared->mutex);
        answer = m_Shared->answer;
        m_Shared->answer.reset();
    }
    if (!answer) {
        m_Tracker.unanswered();
        return true;
    }
    std::optional<double> fraction = m_Tracker.answered(*answer, SDL_GetTicks());
    if (fraction && m_HandOver) {
        m_HandOver(*fraction);
    }
    return true;
}
