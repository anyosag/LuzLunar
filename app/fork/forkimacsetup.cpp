#include "forkimacsetup.h"

#include <QElapsedTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QReadLocker>
#include <QThread>

#include <algorithm>
#include <thread>

#include "apolloclient.h"
#include "backend/computermanager.h"
#include "backend/nvcomputer.h"
#include "forkdisplayextend.h"
#include "forkdisplaygroup.h"
#include "forkmultidisplay.h"
#include "forkpreferences.h"

namespace
{
    // How long the iMac's Moonlight waits for Apollo to take the PIN, and how long this Mac keeps
    // offering it to Apollo (Moonlight has to reach the PC and ask first)
    constexpr int k_PairTimeoutMs = 60000;
    constexpr int k_OfferPinMs = 45000;

    // Moonlight's default HTTP port; any other goes with the address
    constexpr uint16_t k_DefaultHttpPort = 47989;

    // A PC this Mac could pair the iMac with, captured on the main thread
    struct Candidate {
        QString uuid, name;
        ApolloClient::Target target;
        QStringList addresses;
        uint16_t httpPort = 0, httpsPort = 0;
    };

    QString describeStatus(const ForkDisplayExtend::Status& status, const QStringList& pairedNames)
    {
        if (!status.ok) {
            return QObject::tr("DisplayExtend's Host didn't answer.");
        }
        if (!status.imacConnected) {
            return QObject::tr("The iMac isn't connected to DisplayExtend.");
        }
        if (!status.directSupported) {
            return QObject::tr("The iMac's DisplayExtend can only show this Mac. To let it stream straight from the PC, update it from DisplayExtend's Host.");
        }
        if (!status.moonlightVerified) {
            return QObject::tr("Moonlight on the iMac is missing or failed its signature check; its picture goes through this Mac.");
        }
        if (pairedNames.isEmpty()) {
            return QObject::tr("The iMac can stream straight from a PC once it's set up.");
        }
        return QObject::tr("The iMac can stream straight from %1.").arg(pairedNames.join(QStringLiteral(", ")));
    }

    // The "iMac codec" help line; *warns when the iMac's DisplayExtend can't be asked for a codec
    QString describeCodecs(bool available, bool directReady, const ForkDisplayRoute::ImacCodecs& codecs, bool* warns)
    {
        using namespace ForkDisplayRoute;
        *warns = false;
        if (!available) {
            return QObject::tr("Automatic: straight from the PC, a codec the iMac decodes in hardware; through this Mac, the main stream's codec.");
        }
        if (directReady && codecs.direct.size() < 2) {
            *warns = true;
            return QObject::tr("Straight from the PC, the iMac streams H.264 until both Macs have DisplayExtend 1.6.5.");
        }

        Codec automatic = imacStream(Route::Direct, CodecSetting::Automatic, 0, k_ImacMinBitrateKbps, k_VccAutomatic, codecs).codec;
        QStringList software;
        for (Codec codec : { Codec::Hevc, Codec::Av1 }) {
            if (std::find(codecs.hardware.begin(), codecs.hardware.end(), codec) == codecs.hardware.end()) {
                software.append(QString::fromLatin1(codecName(codec)));
            }
        }
        QString text = QObject::tr("Automatic: %1 straight from the PC, which this iMac decodes in hardware, and the main stream's codec through this Mac.")
                           .arg(QString::fromLatin1(codecName(automatic)));
        if (!software.isEmpty()) {
            text += QLatin1Char(' ') + QObject::tr("Straight from the PC, this iMac decodes %1 on its processor, which costs it time and power.")
                                           .arg(software.join(QObject::tr(" and ")));
        }
        return text;
    }
}

ForkImacSetup* ForkImacSetup::get()
{
    static ForkImacSetup* s_Instance = new ForkImacSetup();
    return s_Instance;
}

ForkImacSetup::ForkImacSetup(QObject* parent)
    : QObject(parent)
{
    m_Pool.setMaxThreadCount(1);
}

void ForkImacSetup::setComputerManager(QObject* manager)
{
    auto* computerManager = qobject_cast<ComputerManager*>(manager);
    if (computerManager == nullptr || computerManager == m_Manager) {
        return;
    }
    m_Manager = computerManager;

    // Which PCs are online changes who the iMac can be paired with
    connect(computerManager, &ComputerManager::computerStateChanged, this, &ForkImacSetup::updateCanSetUp);
    refresh();
}

int ForkImacSetup::automaticBitrateKbps(int route, int codec, int mainKbps, int mainWidth, int mainHeight,
                                        int mainFps, int mainCodecConfig) const
{
    ForkDisplayGroup::Stream stream;
    stream.width = mainWidth;
    stream.height = mainHeight;
    stream.fps = mainFps;
    stream.bitrateKbps = mainKbps;

    // The plan a launch would make now, for the slot of DisplayExtend's display
    std::vector<ForkDisplayGroup::MacDisplay> displays = ForkMultiDisplay::macDisplays();
    ForkDisplayGroup::Plan plan = ForkDisplayGroup::plan(displays, stream, static_cast<int>(displays.size()), "settings");
    for (const ForkDisplayGroup::Slot& slot : plan.slotList) {
        if (slot.external) {
            ForkDisplayRoute::Route imacRoute = route == ForkPreferences::IR_VIA_MAC ? ForkDisplayRoute::Route::ViaMac
                                                                                      : ForkDisplayRoute::Route::Direct;
            return ForkDisplayRoute::imacStream(imacRoute, static_cast<ForkDisplayRoute::CodecSetting>(codec), 0,
                                                slot.bitrateKbps, mainCodecConfig, m_Codecs).kbps;
        }
    }
    return 0;
}

void ForkImacSetup::refresh()
{
    if (!ForkDisplayExtend::available()) {
        applyStatus(tr("DisplayExtend's Host isn't running on this Mac, or is older than 1.6."), false, false, QStringList(),
                    ForkDisplayRoute::ImacCodecs());
        return;
    }

    QPointer<ForkImacSetup> self(this);
    m_Pool.start([self]() {
        ForkDisplayExtend bridge;
        ForkDisplayExtend::Status status;
        if (bridge.open(1000)) {
            status = bridge.status(3000);
        }

        QMetaObject::invokeMethod(self, [self, status]() {
            if (self == nullptr) {
                return;
            }

            QStringList pairedNames;
            if (self->m_Manager != nullptr) {
                for (NvComputer* computer : self->m_Manager->getComputers()) {
                    QReadLocker lock(&computer->lock);
                    if (status.pairedHostIds.contains(computer->uuid, Qt::CaseInsensitive)) {
                        pairedNames.append(computer->name);
                    }
                }
            }
            self->applyStatus(describeStatus(status, pairedNames), status.ok && status.imacConnected,
                              status.directSupported && status.moonlightVerified, status.pairedHostIds, status.codecs);
        }, Qt::QueuedConnection);
    });
}

void ForkImacSetup::applyStatus(const QString& status, bool available, bool directReady, const QStringList& pairedHostIds,
                                const ForkDisplayRoute::ImacCodecs& codecs)
{
    m_Status = status;
    m_Available = available;
    m_DirectReady = directReady;
    m_PairedHostIds = pairedHostIds;
    m_Codecs = codecs;
    m_CodecHelp = describeCodecs(available, directReady, codecs, &m_CodecHelpWarns);
    updateCanSetUp();
    emit changed();
}

void ForkImacSetup::updateCanSetUp()
{
    bool can = false;
    if (m_DirectReady && m_Manager != nullptr) {
        for (NvComputer* computer : m_Manager->getComputers()) {
            QReadLocker lock(&computer->lock);
            if (computer->state == NvComputer::CS_ONLINE && computer->pairState == NvComputer::PS_PAIRED &&
                    computer->forkPairDevice && !m_PairedHostIds.contains(computer->uuid, Qt::CaseInsensitive)) {
                can = true;
            }
        }
    }
    if (can != m_CanSetUp) {
        m_CanSetUp = can;
        emit changed();
    }
}

void ForkImacSetup::setUp()
{
    if (m_Busy || m_Manager == nullptr) {
        return;
    }

    QList<Candidate> candidates;
    for (NvComputer* computer : m_Manager->getComputers()) {
        Candidate candidate;
        {
            QReadLocker lock(&computer->lock);
            if (computer->state != NvComputer::CS_ONLINE || computer->pairState != NvComputer::PS_PAIRED ||
                    !computer->forkPairDevice || m_PairedHostIds.contains(computer->uuid, Qt::CaseInsensitive)) {
                continue;
            }
            candidate.uuid = computer->uuid;
            candidate.name = computer->name;
            candidate.httpPort = computer->activeAddress.port();
            candidate.httpsPort = computer->activeHttpsPort;
        }
        candidate.target = ApolloClient::targetFor(computer);
        for (const NvAddress& address : computer->uniqueAddresses()) {
            candidate.addresses.append(address.address());
        }
        candidates.append(candidate);
    }
    if (candidates.isEmpty()) {
        emit finished(tr("No online Apollo PC can set up the iMac."));
        return;
    }

    m_Busy = true;
    emit changed();

    QPointer<ForkImacSetup> self(this);
    m_Pool.start([self, candidates]() {
        QStringList outcomes;
        for (const Candidate& candidate : candidates) {
            ForkDisplayExtend bridge;
            if (!bridge.open(1000)) {
                outcomes << tr("DisplayExtend's Host didn't answer.");
                break;
            }
            ForkDisplayExtend::Status status = bridge.status(3000);
            if (!status.ok || !status.imacConnected || status.imacAddress.isEmpty()) {
                outcomes << tr("The iMac isn't connected to DisplayExtend.");
                break;
            }

            // The PC address the iMac reaches best
            QString address = candidate.target.address.address();
            double best = -1;
            for (const ForkDisplayRoute::Probe& probe : bridge.probe(candidate.addresses, candidate.httpsPort, 3, 15000)) {
                if (probe.failures == 0 && probe.medianMs >= 0 && (best < 0 || probe.medianMs < best)) {
                    best = probe.medianMs;
                    address = QString::fromStdString(probe.address);
                }
            }
            if (candidate.httpPort != 0 && candidate.httpPort != k_DefaultHttpPort) {
                address += QStringLiteral(":%1").arg(candidate.httpPort);
            }

            QString pin = QStringLiteral("%1").arg(QRandomGenerator::system()->bounded(10000), 4, 10, QLatin1Char('0'));

            // The iMac's Moonlight asks the PC to pair and waits for the PIN, which this Mac gives
            // Apollo meanwhile
            bool imacPaired = false;
            QString imacError;
            std::thread pairing([&bridge, address, pin, &imacPaired, &imacError]() {
                imacPaired = bridge.pairMoonlight(address, pin, k_PairTimeoutMs, &imacError);
            });

            ApolloClient client(candidate.target);
            QByteArray body = QJsonDocument(QJsonObject {
                { "pin", pin },
                { "name", QStringLiteral("iMac (DisplayExtend)") },
                { "address", status.imacAddress },
            }).toJson(QJsonDocument::Compact);
            ApolloClient::RequestOptions options;
            options.contentType = "application/json";
            options.timeoutMs = 5000;

            QString apolloError;
            bool offered = false;
            QElapsedTimer offering;
            offering.start();
            while (offering.elapsed() < k_OfferPinMs) {
                ApolloClient::Response response = client.request(QStringLiteral("actions/pairdevice"), QString(), &body, options);
                if (response.httpStatus == 200) {
                    offered = true;
                    break;
                }
                if (response.httpStatus == 409 || response.httpStatus == 0) {
                    // Moonlight hasn't asked yet, or the PC didn't answer this time
                    QThread::msleep(1000);
                    continue;
                }
                apolloError = response.httpStatus == 403 ? tr("this Mac may not pair other devices with %1 (Apollo's \"Pair other devices\" permission)").arg(candidate.name)
                            : response.httpStatus == 404 ? tr("Apollo on %1 is too old to pair other devices").arg(candidate.name)
                                                         : tr("%1 refused (HTTP %2)").arg(candidate.name).arg(response.httpStatus);
                break;
            }
            if (!offered) {
                // The iMac's Moonlight is still waiting; this ends its request
                bridge.interrupt();
            }
            pairing.join();

            if (offered && imacPaired) {
                outcomes << tr("The iMac is paired with %1.").arg(candidate.name);
            }
            else {
                QString why = !apolloError.isEmpty() ? apolloError
                            : !offered ? tr("%1 never saw the iMac ask to pair").arg(candidate.name)
                                       : imacError;
                outcomes << tr("Couldn't pair the iMac with %1: %2").arg(candidate.name, why);
            }
        }

        QMetaObject::invokeMethod(self, [self, outcomes]() {
            if (self == nullptr) {
                return;
            }
            self->m_Busy = false;
            emit self->changed();
            emit self->finished(outcomes.join(QLatin1Char(' ')));
            self->refresh();
        }, Qt::QueuedConnection);
    });
}
