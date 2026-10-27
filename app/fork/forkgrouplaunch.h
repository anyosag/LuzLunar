#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

#include <memory>

#include "forkdisplayroute.h"
#include "forkmultidisplay.h"

// The launch screen's part in a multi-display stream (ForkLaunchPanel, StreamSegue): the group's
// displays, and the check of the iMac's route before the stream connects. With DisplayExtend's
// display in the group and the route not set to go through this Mac, StreamSegue starts the check
// once the session is initialized and starts the stream when it finishes: DisplayExtend's status,
// then a few seconds of connects from the iMac and from this Mac to the PC
// (ForkMultiDisplay::checkRoute()). Only a launch measures: Resume reads DisplayExtend's status
// and reuses the launch's measurements when they were taken for the same iMac, display and
// network (forkroutememory.h), so it starts at once. The decision is kept for the coordinator,
// which hands the iMac over once the main stream is up.
class ForkGroupLaunch : public QObject
{
    Q_OBJECT

    // The session starting is a multi-display group
    Q_PROPERTY(bool active READ active NOTIFY changed)
    Q_PROPERTY(int displayCount READ displayCount NOTIFY changed)

    // One map per display, slot order: number, title ("Built-in display · 3024×1890"), subtitle,
    // main, external, and its tile in the arrangement figure (x, y, w, h), which is figureWidth ×
    // figureHeight
    Q_PROPERTY(QVariantList displays READ displays NOTIFY changed)
    Q_PROPERTY(double figureWidth READ figureWidth NOTIFY changed)
    Q_PROPERTY(double figureHeight READ figureHeight NOTIFY changed)

    // The group has DisplayExtend's display, so the launch screen shows the iMac's picture
    Q_PROPERTY(bool showRoute READ showRoute NOTIFY changed)
    // ... and checks its route before connecting
    Q_PROPERTY(bool checkNeeded READ checkNeeded NOTIFY changed)
    Q_PROPERTY(bool checking READ checking NOTIFY changed)
    Q_PROPERTY(bool decided READ decided NOTIFY changed)
    Q_PROPERTY(double progress READ progress NOTIFY changed)       // 0 to 1
    Q_PROPERTY(QString checkText READ checkText NOTIFY changed)    // the stage line while checking

    // The two routes' cards: chosen, warn, title, value ("about 16 ms"), detail, note
    Q_PROPERTY(QVariantMap directCard READ directCard NOTIFY changed)
    Q_PROPERTY(QVariantMap viaCard READ viaCard NOTIFY changed)

public:
    static ForkGroupLaunch* get();

    bool active() const { return m_Group != nullptr; }
    int displayCount() const { return m_Displays.size(); }
    QVariantList displays() const { return m_Displays; }
    double figureWidth() const { return m_FigureWidth; }
    double figureHeight() const { return m_FigureHeight; }
    bool showRoute() const { return m_ShowRoute; }
    bool checkNeeded() const { return m_CheckNeeded; }
    bool checking() const { return m_Checking; }
    bool decided() const { return m_Decided; }
    double progress() const { return m_Progress; }
    QString checkText() const { return m_CheckText; }
    QVariantMap directCard() const { return m_DirectCard; }
    QVariantMap viaCard() const { return m_ViaCard; }

    // Reads the session just created (StreamProfiles::createSession()); main thread
    Q_INVOKABLE void refresh();

    // Starts the check; checkFinished() follows, also when there's nothing to check
    Q_INVOKABLE void startCheck();

    // The screenshot harness's sample states (screenshotharness.cpp), a built-in display and the
    // iMac: 0 checking, 1 straight from the PC, 2 through this Mac. Only with LUZLUNAR_SCREENSHOTS.
    Q_INVOKABLE void showSample(int stage);

signals:
    void changed();
    void checkFinished();

private:
    explicit ForkGroupLaunch(QObject* parent = nullptr);

    void rebuild();

    std::shared_ptr<const ForkMultiDisplay::Group> m_Group;
    std::vector<ForkDisplayGroup::MacDisplay> m_MacDisplays;   // as they were at refresh(), for the figure
    int m_Generation = 0;            // ignores a check from an earlier launch

    QVariantList m_Displays;
    double m_FigureWidth = 0, m_FigureHeight = 0;
    bool m_ShowRoute = false;
    bool m_CheckNeeded = false;
    bool m_Checking = false;
    bool m_Decided = false;
    double m_Progress = 0;
    QString m_CheckText;
    QVariantMap m_DirectCard, m_ViaCard;

    ForkDisplayRoute::Facts m_Facts;
    ForkDisplayRoute::Decision m_Decision;
};
