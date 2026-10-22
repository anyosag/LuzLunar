#pragma once

#include <memory>

#include "upscalerules.h"

struct AVFrame;

// [fork] Upscaling (Settings › Video › Upscaling) for the stream running now. The renderers ask
// it which mode the stream has and report what each frame went through, for the stats overlay
// and the log:
//   - Fast: plvk.cpp renders with libplacebo's Lanczos instead of its fastest preset, and
//     vt_metal.mm upscales with MetalFX's spatial scaler (mac/metalfxscaler.*)
//   - Quality: both first run VideoToolbox's low-latency super resolution on the decoded frame
//     (superResolve(), mac/superresolution_mac.mm), then Fast for whatever's left
namespace ForkUpscaling
{
    // Called by ForkStreamExtensions around a stream, with Settings' mode and whether the stream
    // is full color. Logs the mode the stream gets (see UpscaleRules::effectiveMode()).
    void activate(int requestedMode, bool yuv444);
    void deactivate();

    // The stream's mode; Off outside a stream. Cheap and thread safe.
    UpscaleRules::Mode mode();

    struct FrameFree
    {
        void operator()(AVFrame* frame) const;
    };
    using ScopedFrame = std::unique_ptr<AVFrame, FrameFree>;

    // Quality: a copy of a VideoToolbox frame, super-resolved to fit the video's area in a
    // drawable this size, or null to render the frame as it is (another mode, nothing to
    // upscale, not supported, or still starting: the first frames of a size go through as they
    // are while the processor loads its model on a worker thread). On the render thread; it
    // waits for the processor. The copy's buffers stay valid for two more frames after it's
    // freed, as Pacer keeps the decoder's. Reports what it did.
    AVFrame* superResolve(const AVFrame* frame, int drawableWidth, int drawableHeight);

    // Whether the frames being rendered now are super-resolved, so Fast leaves them alone
    bool superResolutionActive();

    // Whether this Mac has VideoToolbox's low-latency super resolution (macOS 26), for Settings
    bool superResolutionSupported();

    // A renderer's report for the frame it's drawing: frame size and the size it's shown at. ms
    // is how long it took, when known. When the mode is Quality and the engine isn't super
    // resolution, the overlay also says why. Logs each change of engine or size.
    void report(UpscaleRules::Engine engine, int frameWidth, int frameHeight, int outWidth, int outHeight,
                double ms = -1, const char* note = nullptr);

    // libplacebo's report: Lanczos when the video's area is larger than the frame, unless
    // superResolved (superResolve() reported that already)
    void reportPlacebo(bool superResolved, int frameWidth, int frameHeight, int rectWidth, int rectHeight);

    // Why Quality isn't super-resolving right now ("" when it is), set by superResolve()
    void setQualityNote(const char* note);

    // Appends the latest report's line to the stats overlay's text, with the average time over
    // the frames since the last line
    void appendOverlayLine(char* text, int maxLength);

    // Ends superResolve()'s session and frees its buffers; activate() and deactivate() call it
    void resetSuperResolution();
}
