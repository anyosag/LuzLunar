#include "camerarules.h"

#include <algorithm>
#include <cstdlib>

namespace CameraRules
{

Offer offer(bool answered, bool camera, long long permissions)
{
    if (!answered) {
        // Unknown: the connection's own answer says
        return Offer::Connect;
    }
    if (!camera) {
        return Offer::NoCamera;
    }
    if (permissions >= 0 && (static_cast<std::uint64_t>(permissions) & k_CameraPermission) == 0) {
        return Offer::NoPermission;
    }
    return Offer::Connect;
}

std::int64_t queuedMs(std::size_t queuedBytes, std::uint32_t kbps)
{
    if (kbps == 0) {
        return 0;
    }
    // kbps is kilobits per second, which is bits per millisecond
    return static_cast<std::int64_t>(queuedBytes) * 8 / kbps;
}

void Bitrate::start(std::uint32_t kbps, std::int64_t nowMs)
{
    m_Ceiling = kbps;
    m_Current = kbps;
    m_LastChangeMs = nowMs;
    m_FastSinceMs = -1;
}

void Bitrate::limit(std::uint32_t kbps)
{
    if (kbps == 0) {
        return;
    }
    m_Ceiling = kbps;
    m_Current = std::min(m_Current, kbps);
    m_Current = std::max(m_Current, floor());
}

std::uint32_t Bitrate::floor() const
{
    return std::min(m_Ceiling, std::max(k_FloorKbps, m_Ceiling / 4));
}

bool Bitrate::update(std::size_t queuedBytes, std::int64_t nowMs)
{
    if (m_Ceiling == 0) {
        return false;
    }
    std::int64_t ms = queuedMs(queuedBytes, m_Current);
    if (ms > k_SlowMs) {
        m_FastSinceMs = -1;
        if (nowMs - m_LastChangeMs >= k_StepMs && m_Current > floor()) {
            m_Current = std::max(floor(), m_Current * 2 / 3);
            m_LastChangeMs = nowMs;
            return true;
        }
        return false;
    }
    if (ms >= k_FastMs) {
        m_FastSinceMs = -1;
        return false;
    }
    if (m_FastSinceMs < 0) {
        m_FastSinceMs = nowMs;
        return false;
    }
    if (nowMs - m_FastSinceMs >= k_RecoverMs && m_Current < m_Ceiling) {
        m_Current = std::min(m_Ceiling, m_Current + std::max<std::uint32_t>(m_Current / 4, 1));
        m_LastChangeMs = nowMs;
        m_FastSinceMs = nowMs;
        return true;
    }
    return false;
}

Queue::Verdict Queue::frame(bool keyframe, std::size_t queuedBytes, std::uint32_t kbps)
{
    std::int64_t ms = queuedMs(queuedBytes, kbps);
    if (!m_Dropping && ms > k_DropMs) {
        m_Dropping = true;
    }
    if (m_Dropping) {
        if (ms >= k_ResumeMs) {
            return Verdict::Drop;
        }
        m_Dropping = false;
        m_NeedKeyframe = true;
        m_Asked = false;
    }
    if (m_NeedKeyframe) {
        if (keyframe) {
            m_NeedKeyframe = false;
            return Verdict::Send;
        }
        if (!m_Asked) {
            m_Asked = true;
            return Verdict::DropAndAskKeyframe;
        }
        return Verdict::Drop;
    }
    return Verdict::Send;
}

void Queue::reset()
{
    m_Dropping = false;
    m_NeedKeyframe = false;
    m_Asked = false;
}

Answer answer(const std::string& statusLine, const std::string& body)
{
    // "HTTP/1.1 <code> <reason>"
    std::size_t space = statusLine.find(' ');
    int code = space == std::string::npos ? 0 : std::atoi(statusLine.c_str() + space + 1);
    switch (code) {
    case 101:
        return Answer::Upgraded;
    case 401:
        return Answer::NoPermission;
    case 403:
        return body == "not_streaming" ? Answer::RetrySoon : Answer::NoPermission;
    case 404:
        return Answer::Unsupported;
    default:
        return Answer::RetryLater;
    }
}

int retryDelayMs(Answer answer, int attempt)
{
    attempt = std::max(attempt, 1);
    switch (answer) {
    case Answer::RetrySoon:
        // The stream's session comes up within seconds of the stream starting
        return std::min(1000 * attempt, 5000);
    case Answer::RetryLater:
        // 5, 10, 20, then every 30 s
        return std::min(5000 << std::min(attempt - 1, 3), 30000);
    case Answer::Upgraded:
    case Answer::NoPermission:
    case Answer::Unsupported:
        break;
    }
    return -1;
}

}
