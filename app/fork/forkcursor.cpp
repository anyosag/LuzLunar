#include "forkcursor.h"

#include <atomic>
#include <cmath>
#include <mutex>
#include <string>

#include <QCoreApplication>
#include <QReadLocker>
#include <QThread>
#include <QThreadPool>

#include "apolloclient.h"
#include "backend/nvcomputer.h"
#include "forkbarreach.h"
#include "forkevents.h"
#include "forkhostmessages.h"
#include "forkpreferences.h"
#include "forksystemshortcuts.h"
#include "forktrackpadpassthrough.h"
#include "mac/forkcursor_mac.h"
#include "settings/streamingpreferences.h"
#include "streaming/input/input.h"
#include "streaming/session.h"
#include "streaming/streamutils.h"

struct ForkCursor::Shared
{
    ApolloClient::Target target;
    QString hostName;

    std::mutex mutex;
    bool alive = true;
    bool refused = false;   // Apollo said no (the option off, an older one): it draws the pointer
};

namespace
{
    const int k_StateCode = 0;      // a STATE arrived
    const int k_RefreshCode = 1;    // a move from another thread, or the ease's tick
    const int k_AnswerCode = 2;     // Apollo refused a draw request
    const Uint32 k_EaseTickMs = 8;
    // A draw request is tried again while Apollo doesn't answer
    const int k_TellAttempts = 3;
    const unsigned long k_TellRetryMs = 400;

    Uint32 eventType()
    {
        static Uint32 type = ForkEvents::registerType();
        return type;
    }

    void post(int code)
    {
        SDL_Event event = {};
        event.type = eventType();
        event.user.code = code;
        SDL_PushEvent(&event);
    }

    // What the launch asks for, "1", "host" or nothing: worked out on the main thread, read on the
    // stream's
    std::mutex s_LaunchMutex;
    std::string s_LaunchValue;
    SDL_threadID s_MainThread = 0;

    // Apollo's messages, read on moonlight-common-c's control receive thread
    struct Received {
        std::mutex mutex;
        bool listening = false;
        luzcursor::receiver_t receiver;
        bool stateKnown = false;
        luzcursor::state_t state;
        std::shared_ptr<const luzcursor::shape_t> shape;   // the state's; null for none, or one that couldn't be used
        bool eventPending = false;
    };
    Received s_Received;

    // Where the moves put the PC's pointer; they're sent from any thread
    std::mutex s_TrackerMutex;
    CursorRules::Tracker s_Tracker;

    std::atomic<ForkCursor*> s_Active { nullptr };

    void onShape(const std::uint8_t* payload, int length)
    {
        std::lock_guard<std::mutex> lock(s_Received.mutex);
        if (s_Received.listening) {
            s_Received.receiver.shape_message(payload, static_cast<std::size_t>(length));
        }
    }

    void onState(const std::uint8_t* payload, int length)
    {
        bool wake = false;
        {
            std::lock_guard<std::mutex> lock(s_Received.mutex);
            if (!s_Received.listening) {
                return;
            }
            std::optional<luzcursor::state_t> state = s_Received.receiver.state_message(payload, static_cast<std::size_t>(length));
            if (!state) {
                return;
            }
            s_Received.state = *state;
            s_Received.stateKnown = true;
            s_Received.shape = s_Received.receiver.shape(state->hash);
            // One event wakes the main thread for however many states arrive before it looks
            if (!s_Received.eventPending) {
                s_Received.eventPending = true;
                wake = true;
            }
        }
        if (wake) {
            post(k_StateCode);
        }
    }

    QThreadPool* workerPool()
    {
        // The pool belongs to the app, so a stream can end without waiting for a request in flight
        static QThreadPool* pool = [] {
            QThreadPool* newPool = new QThreadPool(QCoreApplication::instance());
            newPool->setMaxThreadCount(1);
            return newPool;
        }();
        return pool;
    }

    bool alive(const std::shared_ptr<ForkCursor::Shared>& shared)
    {
        std::lock_guard<std::mutex> lock(shared->mutex);
        return shared->alive;
    }

    SdlInputHandler* inputHandler()
    {
        Session* session = Session::get();
        return session != nullptr ? session->forkInputHandler() : nullptr;
    }

    // On SDL's timer thread, while a correction eases in
    Uint32 easeTick(Uint32 interval, void*)
    {
        post(k_RefreshCode);
        return interval;
    }

    // On the worker: POST /actions/cursor {"draw"}, tried again while Apollo doesn't answer
    void ask(const std::shared_ptr<ForkCursor::Shared>& shared, bool macDraws)
    {
        ApolloClient::RequestOptions options;
        options.contentType = "application/json";
        options.timeoutMs = 3000;
        options.maxResponseBytes = 4096;
        options.cancelled = [shared] { return !alive(shared); };
        ApolloClient apollo(shared->target);
        QByteArray body = macDraws ? QByteArrayLiteral("{\"draw\":\"client\"}") : QByteArrayLiteral("{\"draw\":\"host\"}");

        for (int attempt = 0; attempt < k_TellAttempts && alive(shared); attempt++) {
            if (attempt > 0) {
                QThread::msleep(k_TellRetryMs);
            }
            ApolloClient::Response response = apollo.request(QStringLiteral("actions/cursor"), QString(), &body, options);
            if (response.httpStatus == 200) {
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] The PC's pointer: %s", macDraws ? "this Mac draws it" : "the PC draws it");
                return;
            }
            if (response.httpStatus == 400 || response.httpStatus == 401 || response.httpStatus == 404 || response.httpStatus == 409) {
                // It won't: the PC draws the pointer for the rest of the stream
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] The PC's pointer: %s won't let this Mac draw it (HTTP %d %s); the PC draws it",
                            qPrintable(shared->hostName), response.httpStatus, response.body.constData());
                {
                    std::lock_guard<std::mutex> lock(shared->mutex);
                    shared->refused = true;
                }
                post(k_AnswerCode);
                return;
            }
        }
        if (alive(shared)) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] The PC's pointer: %s didn't answer when asked that %s draw it",
                        qPrintable(shared->hostName), macDraws ? "this Mac" : "the PC");
        }
    }
}

void ForkCursor::prepare(NvComputer* computer, const StreamingPreferences& prefs, bool helperWindow)
{
    s_MainThread = SDL_ThreadID();
    // Both on this thread before another uses them
    eventType();
    workerPool();

    bool apolloCanDraw;
    {
        QReadLocker lock(&computer->lock);
        apolloCanDraw = computer->apolloCursorDraw;
    }
    // The stream's mouse as it starts, which Mac trackpad mode can still lose to an Apollo without it
    bool macTrackpad = prefs.trackpadMode == StreamingPreferences::TM_MAC_TRACKPAD;
    bool absolute = prefs.absoluteMouseMode && prefs.trackpadMode == StreamingPreferences::TM_MAC_MOUSE;
    bool setting = ForkPreferences::get()->drawPcPointer();
    std::string value = CursorRules::launchValue(setting, apolloCanDraw, helperWindow, CursorRules::modeFor(absolute, macTrackpad));
    {
        std::lock_guard<std::mutex> lock(s_LaunchMutex);
        s_LaunchValue = value;
    }
    if (setting && !apolloCanDraw && !helperWindow) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] The PC's pointer: the PC draws it (its Apollo can't let this Mac)");
    }
}

QString ForkCursor::launchArgument()
{
    std::lock_guard<std::mutex> lock(s_LaunchMutex);
    if (s_LaunchValue.empty()) {
        return QString();
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] The PC's pointer: asking to draw it on this Mac (luzCursor=%s)", s_LaunchValue.c_str());
    return QStringLiteral("&luzCursor=") + QString::fromStdString(s_LaunchValue);
}

void ForkCursor::connectionStarting()
{
    bool asking;
    {
        std::lock_guard<std::mutex> lock(s_LaunchMutex);
        asking = !s_LaunchValue.empty();
    }
    {
        // Each stream starts with an empty cache, as Apollo's copy of it does
        std::lock_guard<std::mutex> lock(s_Received.mutex);
        s_Received.receiver.reset();
        s_Received.stateKnown = false;
        s_Received.state = luzcursor::state_t();
        s_Received.shape.reset();
        s_Received.eventPending = false;
        s_Received.listening = asking;
    }
    {
        std::lock_guard<std::mutex> lock(s_TrackerMutex);
        s_Tracker = CursorRules::Tracker();
    }
    ForkHostMessages::setHandler(luzcursor::k_type_shape, onShape);
    ForkHostMessages::setHandler(luzcursor::k_type_state, onState);
}

void ForkCursor::connectionStopped()
{
    ForkHostMessages::setHandler(luzcursor::k_type_shape, nullptr);
    ForkHostMessages::setHandler(luzcursor::k_type_state, nullptr);
    std::lock_guard<std::mutex> lock(s_Received.mutex);
    s_Received.listening = false;
}

void ForkCursor::sentMove(int dx, int dy)
{
    {
        std::lock_guard<std::mutex> lock(s_TrackerMutex);
        s_Tracker.moved(dx, dy, SDL_GetTicks());
    }
    ForkCursor* cursor = s_Active.load();
    if (cursor == nullptr) {
        return;
    }
    // The sprite goes with the move at once; a move from another thread (a gamepad's mouse) wakes
    // the main thread for it
    if (SDL_ThreadID() == s_MainThread) {
        cursor->refresh();
    }
    else {
        post(k_RefreshCode);
    }
}

bool ForkCursor::asked()
{
    std::lock_guard<std::mutex> lock(s_LaunchMutex);
    return !s_LaunchValue.empty();
}

ForkCursor::ForkCursor(NvComputer* computer, SDL_Window* window, int streamWidth, int streamHeight)
    : m_Shared(std::make_shared<Shared>()),
      m_Window(window),
      m_StreamWidth(streamWidth),
      m_StreamHeight(streamHeight)
{
    eventType();
    workerPool();
    m_Shared->target = ApolloClient::targetFor(computer);
    {
        QReadLocker lock(&computer->lock);
        m_Shared->hostName = computer->name;
    }
    {
        std::lock_guard<std::mutex> lock(s_LaunchMutex);
        m_ToldMacDraws = s_LaunchValue == "1";
    }
    s_Active = this;
    // The stream's mouse as it is now, which the launch could only guess, and what Apollo said already
    checkMode();
    stateArrived();
}

ForkCursor::~ForkCursor()
{
    s_Active = nullptr;
    {
        std::lock_guard<std::mutex> lock(m_Shared->mutex);
        m_Shared->alive = false;
    }
    if (m_EaseTimer != 0) {
        SDL_RemoveTimer(m_EaseTimer);
        m_EaseTimer = 0;
    }
    m_Sprite.reset();
    dropCursor();
}

bool ForkCursor::handleEvent(const SDL_Event& event)
{
    if (event.type == eventType()) {
        switch (event.user.code) {
        case k_StateCode:
            checkMode();
            stateArrived();
            break;
        case k_RefreshCode:
            refresh();
            break;
        case k_AnswerCode:
            checkMode();
            refresh();
            break;
        default:
            break;
        }
        return true;
    }

    // The stream's mouse may have changed: Control-Option-Shift-M, the notch bar's Control Center
    checkMode();

    bool refreshNow = event.type == SDL_WINDOWEVENT && event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED;
    // macOS's screenshot tools: the sprite would be in the picture they take
    bool tools = ForkSystemShortcuts::screenshotToolsOpen();
    if (tools != m_ScreenshotTools) {
        m_ScreenshotTools = tools;
        refreshNow = true;
    }
    if (refreshNow) {
        refresh();
    }
    return false;
}

CursorRules::Mode ForkCursor::currentMode() const
{
    {
        std::lock_guard<std::mutex> lock(m_Shared->mutex);
        if (m_Shared->refused) {
            return CursorRules::Mode::None;
        }
    }
    if (m_CantDraw) {
        return CursorRules::Mode::None;
    }
    SdlInputHandler* input = inputHandler();
    return CursorRules::modeFor(input != nullptr && input->forkAbsoluteMouseMode(), ForkTrackpadPassthrough::macPointerMode());
}

void ForkCursor::checkMode()
{
    CursorRules::Mode mode = currentMode();
    bool changed = mode != m_Mode;
    m_Mode = mode;

    bool refused;
    {
        std::lock_guard<std::mutex> lock(m_Shared->mutex);
        refused = m_Shared->refused;
    }
    if (!refused && CursorRules::macDraws(mode) != m_ToldMacDraws) {
        tell(CursorRules::macDraws(mode));
    }
    if (changed) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] The PC's pointer: %s",
                    mode == CursorRules::Mode::Cursor ? "the Mac's cursor in its shape (remote desktop mode)" :
                    mode == CursorRules::Mode::Sprite ? "drawn where the moves put it (Mac trackpad mode)" : "drawn by the PC in this mouse mode");
        refresh();
    }
}

void ForkCursor::tell(bool macDraws)
{
    m_ToldMacDraws = macDraws;
    std::shared_ptr<Shared> shared = m_Shared;
    workerPool()->start([shared, macDraws] { ask(shared, macDraws); });
}

void ForkCursor::stateArrived()
{
    bool known;
    luzcursor::state_t state;
    std::shared_ptr<const luzcursor::shape_t> shape;
    {
        std::lock_guard<std::mutex> lock(s_Received.mutex);
        s_Received.eventPending = false;
        known = s_Received.stateKnown;
        state = s_Received.state;
        shape = s_Received.shape;
    }
    if (!known) {
        return;
    }
    m_StateKnown = true;
    m_State = state;
    m_Shape = shape;
    m_ShapeUsable = shape != nullptr;

    CursorRules::Correction correction;
    bool trackerKnown;
    int x;
    int y;
    {
        std::lock_guard<std::mutex> lock(s_TrackerMutex);
        correction = s_Tracker.state(state, SDL_GetTicks());
        trackerKnown = s_Tracker.known();
        x = s_Tracker.predictedX();
        y = s_Tracker.predictedY();
    }
    if (correction == CursorRules::Correction::Ease && m_EaseTimer == 0) {
        m_EaseTimer = SDL_AddTimer(k_EaseTickMs, easeTick, nullptr);
    }
    // The notch bar's reach follows the same pointer
    if (m_BarReach != nullptr && trackerKnown && m_Mode == CursorRules::Mode::Sprite) {
        m_BarReach->follow(x, y, state.width, state.height);
    }

    bool drawing = state.client_draws() && m_ShapeUsable;
    if (drawing != m_WasDrawing) {
        m_WasDrawing = drawing;
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] The PC's pointer: %s",
                    drawing ? "this Mac draws it" :
                    state.host_draws() ? "the PC draws it (a secure desktop, Windows Graphics Capture, or another stream of its display)" :
                    state.hash != 0 && !m_ShapeUsable ? "its shape didn't arrive whole; nothing draws it until the next one" :
                    "hidden, or off this display");
    }
    refresh();
}

CursorRules::Rect ForkCursor::displayRect() const
{
    // The picture as the renderers and the absolute mouse fit it, and the PC's display in that
    SDL_Rect src = { 0, 0, m_StreamWidth, m_StreamHeight };
    SDL_Rect dst = { 0, 0, 0, 0 };
    SDL_GetWindowSize(m_Window, &dst.w, &dst.h);
    StreamUtils::scaleSourceToDestinationSurface(&src, &dst);
    CursorRules::Rect picture;
    picture.x = dst.x;
    picture.y = dst.y;
    picture.w = dst.w;
    picture.h = dst.h;
    return CursorRules::displayInPicture(picture, m_State.width, m_State.height);
}

void ForkCursor::refresh()
{
    std::uint32_t now = SDL_GetTicks();
    CursorRules::Situation situation;
    situation.mode = m_Mode;
    situation.stateKnown = m_StateKnown;
    situation.state = m_State;
    situation.shapeUsable = m_ShapeUsable;
    situation.screenshotTools = m_ScreenshotTools;
    double drawX;
    double drawY;
    bool easing;
    {
        std::lock_guard<std::mutex> lock(s_TrackerMutex);
        situation.trackerKnown = s_Tracker.known();
        situation.x = s_Tracker.predictedX();
        situation.y = s_Tracker.predictedY();
        drawX = s_Tracker.x(now);
        drawY = s_Tracker.y(now);
        easing = s_Tracker.easing(now);
    }
    if (!easing && m_EaseTimer != 0) {
        SDL_RemoveTimer(m_EaseTimer);
        m_EaseTimer = 0;
    }

    CursorRules::Rect display = displayRect();
    double scale = CursorRules::pointsPerPixel(display.w, m_State.width);

    // Remote desktop mode: the Mac's own cursor, in the PC's shape
    if (CursorRules::cursorShows(situation) && scale > 0) {
        if (m_Cursor == nullptr || m_CursorHash != m_Shape->hash || std::fabs(m_CursorScale - scale) > 0.001) {
            SDL_Cursor* made = ForkCursorMac::createCursor(*m_Shape, scale);
            if (made == nullptr) {
                // The PC draws it instead, for the rest of the stream
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] The PC's pointer: couldn't make its shape the Mac's cursor; the PC draws it");
                m_CantDraw = true;
                dropCursor();
                checkMode();
                return;
            }
            // In before the old one goes, so the stream never shows SDL's own meanwhile
            applyCursor(made);
            if (m_Cursor != nullptr) {
                SDL_FreeCursor(m_Cursor);
            }
            m_Cursor = made;
            m_CursorHash = m_Shape->hash;
            m_CursorScale = scale;
        }
        applyCursor(m_Cursor);
    }
    else {
        applyCursor(nullptr);
    }

    // Mac trackpad mode: the sprite where the moves put the PC's pointer
    if (CursorRules::spriteShows(situation) && scale > 0) {
        if (!m_Sprite) {
            m_Sprite = std::make_unique<ForkCursorMac::Sprite>(m_Window);
        }
        m_Sprite->setShape(m_Shape, scale);
        CursorRules::Point at = CursorRules::inWindow(drawX, drawY, display.x, display.y, display.w, display.h, m_State.width, m_State.height);
        m_Sprite->show(at.x, at.y);
        m_SpriteAt = std::make_pair(at.x, at.y);
    }
    else {
        if (m_Sprite) {
            m_Sprite->hide();
        }
        m_SpriteAt.reset();
    }
}

void ForkCursor::applyCursor(SDL_Cursor* cursor)
{
    if (cursor == m_CursorApplied) {
        return;
    }
    SdlInputHandler* input = inputHandler();
    if (input != nullptr) {
        input->forkSetPcCursor(cursor);
    }
    m_CursorApplied = cursor;
}

void ForkCursor::dropCursor()
{
    applyCursor(nullptr);
    if (m_Cursor != nullptr) {
        // SDL frees every cursor itself as its video quits
        if (SDL_WasInit(SDL_INIT_VIDEO) != 0) {
            SDL_FreeCursor(m_Cursor);
        }
        m_Cursor = nullptr;
        m_CursorHash = 0;
        m_CursorScale = 0;
    }
}

bool ForkCursor::pulse(int count, bool reduceMotion)
{
    if (!m_Sprite || !m_SpriteAt) {
        return false;
    }
    m_Sprite->pulse(count, reduceMotion);
    return true;
}

void ForkCursor::settlePulse()
{
    if (m_Sprite) {
        m_Sprite->settle();
    }
}

std::optional<std::pair<double, double>> ForkCursor::pointerInWindow() const
{
    return m_SpriteAt;
}
