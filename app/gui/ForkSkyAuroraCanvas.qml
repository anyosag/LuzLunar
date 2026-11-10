// [fork] The Canvas (Context2D) version of the night sky aurora, kept as the fallback for software
// rendering (GraphicsInfo.Software); ForkSkyAuroraGpu.qml is the default. A port of the design canvas's
// startAurora() (Main.dc.html 446-565). Two additive "lighter" curtains of 3 px columns are drawn into
// `curtains`, a small blurred copy in `glow`, and both are screened over the sky gradient into `out`
// (Qt Quick has no screen blend mode, so the compositing happens in Context2D "qt-screen"). Decorative.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window

Item {
    id: aurora

    // The sky's size. The aurora box is 520 px tall; its top is set by the owner (window height - 620).
    property real skyWidth: 1280
    property real skyHeight: 900
    // y of this item inside the sky, used to continue the sky's gradient behind the aurora
    property real bandTop: skyHeight - 620
    // Time in ms (the canvas's rAF timestamp). A pure function of this, so any start offset is fine.
    property real time: 12000
    // true: paint a frame at every change of `time` (the owner throttles it to 30 fps)
    property bool active: false
    // Fraction of the canvas's own resolution to draw at. 1 = the canvas's 1 px per logical px (D10)
    property real quality: 1
    // The sky gradient stops (bottom of the stack, behind the aurora): [[pos, "#rrggbb"], ...]
    property var gradientStops: [[0, "#05070F"], [0.4, "#0A0E20"], [0.78, "#111833"], [1, "#18204A"]]
    // smoothed milliseconds spent drawing the curtains (for tests and tuning)
    property real drawMs: 0
    // emitted when a frame has been fully composed
    signal frameReady()
    readonly property bool ready: out.available

    width: skyWidth
    height: 520
    y: bandTop
    clip: true

    // Context2D's drawImage of a Canvas copies from the source item's device-resolution image, and its
    // default source rectangle is the item's logical size: on a 2x screen that is the top-left quarter.
    // So every copy from a canvas names its source rectangle in device pixels (logical size x this)
    readonly property real dpr: Screen.devicePixelRatio
    readonly property int bw: Math.max(8, Math.round(skyWidth * quality))
    readonly property int bh: Math.max(8, Math.round(520 * quality))
    readonly property int gw: Math.max(8, Math.round(skyWidth / 4))
    readonly property int gh: 130

    // The curtains (additive), at quality x the canvas's pixels. Sits under `out`, which is opaque
    Canvas {
        id: curtains
        width: aurora.bw; height: aurora.bh
        canvasSize: Qt.size(aurora.bw, aurora.bh)
        tileSize: canvasSize
        canvasWindow: Qt.rect(0, 0, aurora.bw, aurora.bh)
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Threaded
        onPaint: {
            var t0 = Date.now()
            aurora.drawCurtains(curtains.getContext("2d"), aurora.bw, aurora.bh, 1)
            aurora.drawMs = aurora.drawMs * 0.9 + (Date.now() - t0) * 0.1
        }
        onPainted: glowA.requestPaint()
    }

    // The glow the curtains cast: the curtains again at 1/4 size (the canvas's glow bitmap is 320 x 130),
    // blurred there by a box blur made of eight 2-tap averages (Context2D has no blur, and it only
    // scales images up without smoothing), then blown up 4 times. Each stage is its own tiny canvas
    Canvas {
        id: glowA
        width: aurora.gw; height: aurora.gh
        canvasSize: Qt.size(aurora.gw, aurora.gh)
        tileSize: canvasSize
        canvasWindow: Qt.rect(0, 0, aurora.gw, aurora.gh)
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Threaded
        onPaint: aurora.drawCurtains(glowA.getContext("2d"), aurora.gw, aurora.gh, 0.75)
        onPainted: h1.requestPaint()
    }
    component Stage: Canvas {
        property Canvas src
        property int dx: 0
        property int dy: 0
        property Canvas next
        width: aurora.gw; height: aurora.gh
        canvasSize: Qt.size(aurora.gw, aurora.gh)
        tileSize: canvasSize
        canvasWindow: Qt.rect(0, 0, aurora.gw, aurora.gh)
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Threaded
        onPaint: aurora.average(getContext("2d"), src, dx, dy)
        onPainted: if (next) next.requestPaint()
    }
    Stage { id: h1; src: glowA; dx: 1; dy: 0; next: h2 }
    Stage { id: h2; src: h1; dx: 2; dy: 0; next: h3 }
    Stage { id: h3; src: h2; dx: 4; dy: 0; next: h4 }
    Stage { id: h4; src: h3; dx: 8; dy: 0; next: v1 }
    Stage { id: v1; src: h4; dx: 0; dy: 1; next: v2 }
    Stage { id: v2; src: v1; dx: 0; dy: 2; next: v3 }
    Stage { id: v3; src: v2; dx: 0; dy: 4; next: glow }
    Stage { id: glow; src: v3; dx: 0; dy: 8; next: out }

    Canvas {
        id: out
        anchors.fill: parent
        canvasSize: Qt.size(aurora.bw, aurora.bh)
        tileSize: canvasSize
        canvasWindow: Qt.rect(0, 0, aurora.bw, aurora.bh)
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Threaded
        onPaint: aurora.drawOut(out.getContext("2d"))
        onPainted: aurora.frameReady()
    }

    // for tests: save the three bitmaps
    function dump(prefix) {
        curtains.save(prefix + "-curtains.png")
        glow.save(prefix + "-glow.png")
        glowA.save(prefix + "-glowA.png")
        out.save(prefix + "-out.png")
    }

    function paintFrame() {
        curtains.requestPaint()
    }
    onTimeChanged: if (active) paintFrame()
    onActiveChanged: if (active) paintFrame()
    onGradientStopsChanged: if (active) paintFrame()
    onSkyWidthChanged: if (active) paintFrame()
    Component.onCompleted: if (active) paintFrame()

    // The column gradients (offset 0 = lower edge), as in the canvas's sprites
    readonly property var tealStops: [[0, "rgba(200,255,245,0)"], [0.02, "rgba(190,255,240,0.8)"], [0.08, "rgba(80,240,200,0.7)"],
        [0.28, "rgba(40,200,170,0.4)"], [0.55, "rgba(60,140,190,0.18)"], [0.8, "rgba(140,80,190,0.08)"], [1, "rgba(140,80,190,0)"]]
    readonly property var greenStops: [[0, "rgba(210,255,230,0)"], [0.015, "rgba(215,255,232,0.95)"], [0.06, "rgba(110,255,170,0.9)"],
        [0.2, "rgba(45,235,135,0.6)"], [0.42, "rgba(30,200,120,0.3)"], [0.65, "rgba(90,120,170,0.14)"], [0.82, "rgba(160,70,150,0.09)"], [1, "rgba(170,50,120,0)"]]

    readonly property var curtainDefs: [
        { y: 320, a: [26, 12, 5], f: [2.4, 7.1, 19], s: [-0.035, 0.08, 0.22], h: 160, hf: 3.1, g: [4.2, 1.7], strength: 0.5, fringe: false, p: 2.1 },
        { y: 410, a: [38, 16, 6], f: [3.1, 8.7, 23], s: [0.045, -0.11, 0.3], h: 235, hf: 4.3, g: [5.3, 2.2], strength: 1, fringe: true, p: 0 }
    ]

    // Copy a whole source canvas (logical size sw x sh) into the destination rectangle. At 1x the
    // 5-argument form is exact; on a 2x screen the source rectangle has to be named in device pixels
    function blit(ctx, src, sw, sh, dx, dy, dw, dh) {
        if (aurora.dpr === 1)
            ctx.drawImage(src, dx, dy, dw, dh)
        else
            ctx.drawImage(src, 0, 0, sw * aurora.dpr, sh * aurora.dpr, dx, dy, dw, dh)
    }

    function drawCurtains(ctx, pw, ph, gain) {
        var W = aurora.skyWidth
        ctx.reset()
        ctx.clearRect(0, 0, pw, ph)
        ctx.scale(pw / W, ph / 520)
        var t = aurora.time / 1000
        // unit-space gradients, made once per paint
        var grads = [tealStops, greenStops].map(function (stops) {
            var g = ctx.createLinearGradient(0, 0, 0, -1)
            for (var i = 0; i < stops.length; i++)
                g.addColorStop(stops[i][0], stops[i][1])
            return g
        })
        var fringeGrad = ctx.createLinearGradient(0, 0, 0, 1)
        fringeGrad.addColorStop(0, "rgba(255,110,190,0.75)")
        fringeGrad.addColorStop(1, "rgba(255,110,190,0)")
        ctx.globalCompositeOperation = "lighter"
        var step = 2
        for (var ci = 0; ci < 2; ci++) {
            var c = curtainDefs[ci]
            var PI = Math.PI
            for (var x = -10; x < W + 10; x += step) {
                var u = x / W
                var base = c.y
                    + c.a[0] * Math.sin(u * c.f[0] * PI + t * c.s[0] * 6 + c.p)
                    + c.a[1] * Math.sin(u * c.f[1] * PI + t * c.s[1] * 6)
                    + c.a[2] * Math.sin(u * c.f[2] * PI + t * c.s[2] * 6 + c.p)
                var patch = 0.5 + 0.5 * Math.sin(u * c.g[0] * PI + t * 0.22 + c.p) * Math.sin(u * c.g[1] * PI - t * 0.13)
                var rays = 0.5 + 0.5 * Math.sin(x * 0.19 + t * 1.6 + 3 * Math.sin(x * 0.011 + t * 0.35)) * Math.sin(x * 0.061 - t * 0.9)
                var pulse = 0.88 + 0.12 * Math.sin(t * 2.3 + x * 0.004 + c.p)
                var ends = Math.max(0, Math.min(1, (x + 60) / 300, (W + 60 - x) / 300))
                var light = patch * (0.3 + 0.7 * rays) * pulse * ends * c.strength
                if (light < 0.03)
                    continue
                var tall = c.h * (0.6 + 0.4 * (0.5 + 0.5 * Math.sin(u * c.hf * PI + t * 0.25 + c.p))) * (0.85 + 0.15 * rays)
                ctx.globalAlpha = Math.min(1, light) * gain
                // the column is the unit gradient (0,0)-(0,-1) moved to its lower edge and stretched
                ctx.save()
                ctx.translate(x, base)
                ctx.scale(1, tall)
                ctx.fillStyle = grads[ci]
                ctx.fillRect(0, -1, 3, 1)
                ctx.restore()
                if (c.fringe && light > 0.55) {
                    ctx.globalAlpha = Math.min(1, (light - 0.55) * 1.6) * gain
                    ctx.save()
                    ctx.translate(x, base - 2)
                    ctx.scale(1, 10)
                    ctx.fillStyle = fringeGrad
                    ctx.fillRect(0, 0, 3, 1)
                    ctx.restore()
                }
            }
        }
        ctx.globalAlpha = 1
        ctx.globalCompositeOperation = "source-over"
    }

    // The mean of a stage and itself shifted by (dx, dy): half of each, added
    function average(ctx, src, dx, dy) {
        ctx.reset()
        ctx.scale(aurora.dpr, aurora.dpr)
        ctx.globalCompositeOperation = "copy"
        ctx.globalAlpha = 0.5
        aurora.blit(ctx, src, aurora.gw, aurora.gh, 0, 0, aurora.gw, aurora.gh)
        ctx.globalCompositeOperation = "lighter"
        aurora.blit(ctx, src, aurora.gw, aurora.gh, dx, dy, aurora.gw, aurora.gh)
        ctx.globalAlpha = 1
        ctx.globalCompositeOperation = "source-over"
    }

    function drawOut(ctx) {
        var bw = aurora.bw, bh = aurora.bh
        ctx.reset()
        ctx.scale(aurora.dpr, aurora.dpr)
        // The sky's own gradient behind this band
        var grad = ctx.createLinearGradient(0, -aurora.bandTop * bh / 520, 0, (aurora.skyHeight - aurora.bandTop) * bh / 520)
        for (var i = 0; i < gradientStops.length; i++)
            grad.addColorStop(gradientStops[i][0], gradientStops[i][1])
        ctx.fillStyle = grad
        ctx.fillRect(0, 0, bw, bh)
        ctx.globalCompositeOperation = "qt-screen"
        ctx.globalAlpha = 0.85
        // the 15 px box shifts the glow by 7.5 stage px; put it back
        aurora.blit(ctx, glow, aurora.gw, aurora.gh, -30 * bw / aurora.skyWidth, -30 * bh / 520, bw, bh)
        ctx.globalAlpha = 0.92
        aurora.blit(ctx, curtains, bw, bh, 0, 0, bw, bh)
        ctx.globalAlpha = 1
        ctx.globalCompositeOperation = "source-over"
    }
}
