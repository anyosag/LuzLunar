#include "forkgrouplaunch.h"

#include <QCoreApplication>
#include <QDateTime>

#include <algorithm>
#include <cmath>
#include <limits>
#include <thread>

#include "SDL_compat.h"

namespace
{
    // The arrangement figure's box on the launch screen, in points
    constexpr double k_FigureMaxWidth = 260;
    constexpr double k_FigureMaxHeight = 84;

    QString ms(double value)
    {
        return QCoreApplication::translate("ForkGroupLaunch", "%1 ms").arg(std::lround(std::max(0.0, value)));
    }

    QString about(double value)
    {
        return QCoreApplication::translate("ForkGroupLaunch", "about %1").arg(ms(value));
    }

    // The probe to the PC address that answered fastest so far; null for none
    const ForkDisplayRoute::Probe* fastest(const std::vector<ForkDisplayRoute::Probe>& probes)
    {
        const ForkDisplayRoute::Probe* best = nullptr;
        for (const ForkDisplayRoute::Probe& probe : probes) {
            if (probe.medianMs >= 0 && (best == nullptr || probe.medianMs < best->medianMs)) {
                best = &probe;
            }
        }
        return best;
    }

    // "the iMac isn't paired with this PC" as a sentence
    QString sentence(const std::string& reason)
    {
        QString text = QString::fromStdString(reason);
        if (!text.isEmpty()) {
            text[0] = text[0].toUpper();
            text += QLatin1Char('.');
        }
        return text;
    }
}

ForkGroupLaunch* ForkGroupLaunch::get()
{
    static ForkGroupLaunch* s_Instance = new ForkGroupLaunch();
    return s_Instance;
}

ForkGroupLaunch::ForkGroupLaunch(QObject* parent)
    : QObject(parent)
{
}

void ForkGroupLaunch::refresh()
{
    m_Generation++;
    m_Group = ForkMultiDisplay::group();
    m_MacDisplays = m_Group ? ForkMultiDisplay::macDisplays() : std::vector<ForkDisplayGroup::MacDisplay>();
    m_Checking = false;
    m_Decided = false;
    m_Progress = 0;
    m_Facts = ForkDisplayRoute::Facts();
    m_Decision = ForkDisplayRoute::Decision();

    m_ShowRoute = false;
    if (m_Group) {
        for (const ForkDisplayGroup::Slot& slot : m_Group->plan.slotList) {
            m_ShowRoute = m_ShowRoute || slot.external;
        }
    }
    m_CheckNeeded = m_ShowRoute && ForkMultiDisplay::routeCheckNeeded();

    // A reconnect keeps its launch's group and route (only a new launch clears them,
    // ForkMultiDisplay::prepareSession()), so it isn't measured again
    if (m_ShowRoute && ForkMultiDisplay::routeDecision(&m_Decision, &m_Facts)) {
        m_Decided = true;
    }
    // Set to go through this Mac: decided already, nothing to measure
    else if (m_ShowRoute && !m_CheckNeeded) {
        m_Decision = ForkDisplayRoute::decide(ForkDisplayRoute::Setting::ViaMac, m_Facts);
        m_Decided = true;
        ForkMultiDisplay::setRouteDecision(m_Decision, m_Facts);
    }

    rebuild();
    emit changed();
}

void ForkGroupLaunch::startCheck()
{
    if (!m_Group || !m_CheckNeeded || m_Checking || m_Decided) {
        emit checkFinished();
        return;
    }

    m_Checking = true;
    rebuild();
    emit changed();

    int generation = m_Generation;
    std::shared_ptr<const ForkMultiDisplay::Group> group = m_Group;
    ForkGroupLaunch* self = this;   // the singleton outlives the thread

    // Resume uses the launch's measurements when they still hold, so only a launch waits for them
    auto remembered = std::make_shared<ForkRouteMemory::Memory>();
    if (!group->resume || !ForkMultiDisplay::rememberedRoute(group->hostUuid, remembered.get())) {
        remembered.reset();
    }

    std::thread([self, generation, group, remembered]() {
        ForkMultiDisplay::RouteCheck check = ForkMultiDisplay::checkRoute(*group, remembered.get(), [self, generation](const ForkDisplayRoute::Facts& partial, double progress) {
            QMetaObject::invokeMethod(self, [self, generation, partial, progress]() {
                if (self->m_Generation == generation && self->m_Checking) {
                    self->m_Facts = partial;
                    self->m_Progress = progress;
                    self->rebuild();
                    emit self->changed();
                }
            }, Qt::QueuedConnection);
        });
        ForkDisplayRoute::Decision decision = ForkDisplayRoute::decide(group->route, check.facts);

        QMetaObject::invokeMethod(self, [self, generation, group, check, decision]() {
            // A launch left during its check, and maybe a new one planned since
            if (self->m_Generation != generation || ForkMultiDisplay::group() != group) {
                return;
            }
            const ForkDisplayRoute::Facts& facts = check.facts;
            if (check.recalled) {
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] iMac route: %s, as measured at the launch at %s (Resume doesn't measure again)",
                            ForkDisplayRoute::describe(decision, facts).c_str(),
                            qPrintable(QDateTime::fromSecsSinceEpoch(check.measuredAt).toString(QStringLiteral("HH:mm"))));
            }
            else {
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] iMac route: %s",
                            ForkDisplayRoute::describe(decision, facts).c_str());
                ForkMultiDisplay::rememberRoute(check);
            }
            ForkMultiDisplay::setRouteDecision(decision, facts);
            self->m_Facts = facts;
            self->m_Decision = decision;
            self->m_Decided = true;
            self->m_Checking = false;
            self->m_Progress = 1;
            self->rebuild();
            emit self->changed();
            emit self->checkFinished();
        }, Qt::QueuedConnection);
    }).detach();
}

void ForkGroupLaunch::showSample(int stage)
{
    if (qEnvironmentVariableIsEmpty("LUZLUNAR_SCREENSHOTS")) {
        return;
    }

    auto group = std::make_shared<ForkMultiDisplay::Group>();
    group->hostName = QStringLiteral("GonzaloPC");
    group->plan.id = "0123456789abcdef";

    ForkDisplayGroup::Slot builtin;
    builtin.slot = 0;
    builtin.displayId = 1;
    builtin.name = "Built-in display";
    builtin.width = 3024;
    builtin.height = 1890;
    ForkDisplayGroup::Slot imac;
    imac.slot = 1;
    imac.displayId = 7;
    imac.name = "DisplayExtend (iMac)";
    imac.width = 1920;
    imac.height = 1080;
    imac.external = true;
    group->plan.slotList = { builtin, imac };

    ForkDisplayGroup::MacDisplay builtinDisplay;
    builtinDisplay.id = 1;
    builtinDisplay.pointWidth = 1512;
    builtinDisplay.pointHeight = 982;
    ForkDisplayGroup::MacDisplay imacDisplay;
    imacDisplay.id = 7;
    imacDisplay.x = 1512;
    imacDisplay.y = -98;
    imacDisplay.pointWidth = 1920;
    imacDisplay.pointHeight = 1080;

    ForkDisplayRoute::Probe imacProbe;
    imacProbe.address = "10.0.0.77";
    imacProbe.count = 30;
    imacProbe.medianMs = 3;
    imacProbe.maxMs = stage == 2 ? 140 : 9;
    imacProbe.failures = stage == 2 ? 2 : 0;
    ForkDisplayRoute::Probe macProbe;
    macProbe.address = "10.0.0.77";
    macProbe.count = 30;
    macProbe.medianMs = 2.2;
    macProbe.maxMs = 4.4;

    ForkDisplayRoute::Facts facts;
    facts.bridge = facts.imacConnected = facts.directSupported = facts.moonlightVerified = facts.paired = true;
    facts.imacToPc = { imacProbe };
    facts.macToPc = macProbe;
    facts.displayExtendP50Ms = 21;
    facts.displayExtendP95Ms = 76;
    facts.displayExtendFrames = 600;

    m_Generation++;
    m_Group = group;
    m_MacDisplays = { builtinDisplay, imacDisplay };
    m_ShowRoute = true;
    m_CheckNeeded = true;
    m_Facts = facts;
    m_Checking = stage == 0;
    m_Decided = stage != 0;
    m_Progress = stage == 0 ? 0.64 : 1;
    m_Decision = stage == 0 ? ForkDisplayRoute::Decision() : ForkDisplayRoute::decide(ForkDisplayRoute::Setting::Automatic, facts);
    rebuild();
    emit changed();
}

void ForkGroupLaunch::rebuild()
{
    m_Displays.clear();
    m_FigureWidth = m_FigureHeight = 0;
    m_DirectCard.clear();
    m_ViaCard.clear();
    m_CheckText.clear();
    if (!m_Group) {
        return;
    }

    bool direct = m_Decided && m_Decision.route == ForkDisplayRoute::Route::Direct;
    QString externalSubtitle = !m_Decided ? tr("Picture: checking the route…")
                             : direct ? tr("Picture: straight from the PC")
                                      : tr("Picture: through this Mac");

    // The arrangement as the Mac has it, scaled into the figure's box
    const std::vector<ForkDisplayGroup::MacDisplay>& macDisplays = m_MacDisplays;
    struct Tile {
        const ForkDisplayGroup::Slot* slot;
        double x, y, w, h;
    };
    std::vector<Tile> tiles;
    double minX = std::numeric_limits<double>::max(), minY = minX, maxX = -minX, maxY = -minX;
    for (const ForkDisplayGroup::Slot& slot : m_Group->plan.slotList) {
        for (const ForkDisplayGroup::MacDisplay& display : macDisplays) {
            if (display.id == slot.displayId) {
                tiles.push_back({ &slot, double(display.x), double(display.y), double(display.pointWidth), double(display.pointHeight) });
                minX = std::min(minX, double(display.x));
                minY = std::min(minY, double(display.y));
                maxX = std::max(maxX, double(display.x + display.pointWidth));
                maxY = std::max(maxY, double(display.y + display.pointHeight));
            }
        }
    }
    double scale = tiles.empty() ? 0 : std::min(k_FigureMaxWidth / std::max(1.0, maxX - minX), k_FigureMaxHeight / std::max(1.0, maxY - minY));
    m_FigureWidth = tiles.empty() ? 0 : (maxX - minX) * scale;
    m_FigureHeight = tiles.empty() ? 0 : (maxY - minY) * scale;

    for (const ForkDisplayGroup::Slot& slot : m_Group->plan.slotList) {
        QVariantMap entry {
            { "number", slot.slot + 1 },
            { "title", tr("%1 · %2×%3").arg(QString::fromStdString(slot.name)).arg(slot.width).arg(slot.height) },
            { "subtitle", slot.slot == 0 ? tr("Main stream: keyboard, pointer and sound")
                        : slot.external ? externalSubtitle
                                        : tr("Video only") },
            { "main", slot.slot == 0 },
            { "external", slot.external },
            { "x", 0 }, { "y", 0 }, { "w", 0 }, { "h", 0 },
        };
        for (const Tile& tile : tiles) {
            if (tile.slot == &slot) {
                entry["x"] = (tile.x - minX) * scale;
                entry["y"] = (tile.y - minY) * scale;
                entry["w"] = tile.w * scale;
                entry["h"] = tile.h * scale;
            }
        }
        m_Displays.append(entry);
    }

    if (!m_ShowRoute) {
        return;
    }

    // The two routes, as measured so far
    const ForkDisplayRoute::Probe* imac = fastest(m_Facts.imacToPc);
    QString imacLine = imac != nullptr ? tr("iMac → PC %1 · worst %2").arg(ms(imac->medianMs), ms(imac->maxMs)) : QString();
    bool measured = m_Facts.displayExtendFrames >= ForkDisplayRoute::k_MinDisplayExtendFrames && m_Facts.displayExtendP50Ms > 0;
    QString displayExtendLine = m_Facts.bridge ? measured ? tr("DisplayExtend %1").arg(ms(m_Facts.displayExtendP50Ms))
                                                          : tr("DisplayExtend %1, assumed").arg(ms(ForkDisplayRoute::k_DefaultDisplayExtendMs))
                                               : QString();
    QString macLine = m_Facts.macToPc.medianMs >= 0 ? tr("Mac → PC %1").arg(ms(m_Facts.macToPc.medianMs)) : QString();

    m_DirectCard["title"] = tr("Straight from the PC");
    m_ViaCard["title"] = tr("Through this Mac");

    if (!m_Decided) {
        m_DirectCard["detail"] = imacLine.isEmpty() ? tr("Measuring…") : imacLine;
        QStringList via;
        if (!macLine.isEmpty()) {
            via << macLine;
        }
        if (!displayExtendLine.isEmpty()) {
            via << displayExtendLine;
        }
        m_ViaCard["detail"] = via.isEmpty() ? tr("Measuring…") : via.join(QStringLiteral(" · "));

        // In rounds, not seconds: a PC address the iMac can't reach makes the first round the long one
        long round = std::lround((m_Progress - 0.04) / 0.96 * ForkMultiDisplay::k_RouteRounds);
        m_CheckText = m_Progress < 0.04 ? tr("Asking DisplayExtend about the iMac…")
                                        : tr("Timing both routes to %1… %2 of %3")
                                              .arg(m_Group->hostName)
                                              .arg(std::max(1L, std::min(round, long(ForkMultiDisplay::k_RouteRounds))))
                                              .arg(ForkMultiDisplay::k_RouteRounds);
        return;
    }

    bool estimated = m_Decision.estDirectMs >= 0;
    m_DirectCard["chosen"] = direct;
    m_ViaCard["chosen"] = !direct;

    if (estimated) {
        m_DirectCard["value"] = about(m_Decision.estDirectMs);
        m_DirectCard["detail"] = imac != nullptr ? tr("worst %1 · iMac → PC %2").arg(ms(m_Decision.estDirectWorstMs), ms(imac->medianMs))
                                                 : tr("worst %1").arg(ms(m_Decision.estDirectWorstMs));
        m_ViaCard["value"] = about(m_Decision.estViaMs);
        m_ViaCard["detail"] = displayExtendLine.isEmpty() ? tr("worst %1").arg(ms(m_Decision.estViaWorstMs))
                                                          : tr("worst %1 · %2").arg(ms(m_Decision.estViaWorstMs), displayExtendLine);
        if (!direct && m_Decision.reason == "steadier at its worst") {
            m_ViaCard["note"] = tr("Steadier at its worst");
        }
        else if (direct && m_Decision.reason == "set to go straight from the PC") {
            m_DirectCard["note"] = tr("Set in Settings");
        }
    }
    else if (m_Group->route == ForkDisplayRoute::Setting::ViaMac) {
        m_DirectCard["note"] = tr("Off: Settings › Display sends the iMac's picture through this Mac");
        m_ViaCard["detail"] = tr("Set in Settings");
    }
    else {
        // It couldn't go straight from the PC: why
        m_DirectCard["warn"] = true;
        m_DirectCard["note"] = sentence(m_Decision.reason.rfind("can't go straight from the PC: ", 0) == 0
                                            ? m_Decision.reason.substr(31) : m_Decision.reason);
        m_DirectCard["detail"] = imacLine;
        if (m_Decision.estViaMs >= 0) {
            m_ViaCard["value"] = about(m_Decision.estViaMs);
            m_ViaCard["detail"] = displayExtendLine.isEmpty() ? tr("worst %1").arg(ms(m_Decision.estViaWorstMs))
                                                              : tr("worst %1 · %2").arg(ms(m_Decision.estViaWorstMs), displayExtendLine);
        }
        else {
            m_ViaCard["detail"] = displayExtendLine;
        }
    }
}
