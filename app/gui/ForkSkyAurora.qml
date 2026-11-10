// [fork] The night sky's aurora: a QML Canvas port of the design canvas's startAurora() (Main.dc.html
// 446-565). Two additive "lighter" curtains of 2.7 px columns are drawn into `curtains`, a small blurred
// copy of them is made in `glow`, and both are screened over the sky gradient into `out`, which is what
// shows. Plain Qt Quick has no screen blend mode, so the compositing happens in Context2D ("qt-screen").
// Decorative: no input, no accessibility.
import QtQuick

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
    // Fraction of the canvas's own resolution to draw at. 1 = the canvas's 1 px per logical px
    property real quality: 1
    // The sky gradient stops (bottom of the stack, behind the aurora): [[pos, "#rrggbb"], ...]
    property var gradientStops: [[0, "#05070F"], [0.4, "#0A0E20"], [0.78, "#111833"], [1, "#18204A"]]
    // The Milky Way is part of this composite so the aurora can sit over it, as on the canvas
    property real milkyAngle: 0
    property real fieldScale: 1
    // emitted when a frame has been fully composed
    signal frameReady()
    readonly property bool ready: out.available

    width: skyWidth
    height: 520
    y: bandTop
    clip: true

    readonly property int bw: Math.max(8, Math.round(skyWidth * quality))
    readonly property int bh: Math.max(8, Math.round(520 * quality))
    readonly property int gw: Math.max(32, Math.round(skyWidth / 8))
    readonly property int gh: 64

    function paintSprite(cv, stops, h) {
        var g = cv.getContext("2d")
        g.reset()
        var grad = g.createLinearGradient(0, h, 0, 0)
        for (var i = 0; i < stops.length; i++)
            grad.addColorStop(stops[i][0], stops[i][1])
        g.fillStyle = grad
        g.fillRect(0, 0, 4, h)
    }

    // One column of a curtain, bottom to top: 4 x 256 sprites, as in the canvas
    Canvas {
        id: spriteGreen
        width: 4; height: 256
        opacity: 0
        onPaint: aurora.paintSprite(spriteGreen, [
            [0, "rgba(210,255,230,0)"], [0.015, "rgba(215,255,232,0.95)"], [0.06, "rgba(110,255,170,0.9)"],
            [0.2, "rgba(45,235,135,0.6)"], [0.42, "rgba(30,200,120,0.3)"], [0.65, "rgba(90,120,170,0.14)"],
            [0.82, "rgba(160,70,150,0.09)"], [1, "rgba(170,50,120,0)"]], 256)
        onPainted: aurora.spritesReady()
    }
    Canvas {
        id: spriteTeal
        width: 4; height: 256
        opacity: 0
        onPaint: aurora.paintSprite(spriteTeal, [
            [0, "rgba(200,255,245,0)"], [0.02, "rgba(190,255,240,0.8)"], [0.08, "rgba(80,240,200,0.7)"],
            [0.28, "rgba(40,200,170,0.4)"], [0.55, "rgba(60,140,190,0.18)"], [0.8, "rgba(140,80,190,0.08)"],
            [1, "rgba(140,80,190,0)"]], 256)
        onPainted: aurora.spritesReady()
    }
    Canvas {
        id: spriteFringe
        width: 4; height: 32
        opacity: 0
        onPaint: {
            var g = getContext("2d")
            g.reset()
            var grad = g.createLinearGradient(0, 0, 0, 32)
            grad.addColorStop(0, "rgba(255,110,190,0.75)")
            grad.addColorStop(1, "rgba(255,110,190,0)")
            g.fillStyle = grad
            g.fillRect(0, 0, 4, 32)
        }
        onPainted: aurora.spritesReady()
    }

    property int spriteCount: 0
    property bool spritesOk: false
    function spritesReady() {
        spriteCount++
        if (spriteCount >= 3 && !spritesOk) {
            spritesOk = true
            if (active) aurora.paintFrame()
        }
    }

    // The curtains (additive), at quality x the canvas's pixels. Sits under `out`, which is opaque
    Canvas {
        id: curtains
        width: aurora.bw; height: aurora.bh
        canvasSize: Qt.size(aurora.bw, aurora.bh)
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Cooperative
        onPaint: aurora.drawCurtains(curtains.getContext("2d"))
        onPainted: glowMid.requestPaint()
    }

    // A small copy, blurred: the glow the curtains cast
    Canvas {
        id: glowMid
        width: aurora.gw; height: aurora.gh
        canvasSize: Qt.size(aurora.gw, aurora.gh)
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Cooperative
        onPaint: aurora.drawGlowMid(glowMid.getContext("2d"))
        onPainted: glow.requestPaint()
    }
    Canvas {
        id: glow
        width: aurora.gw / 4; height: aurora.gh / 4
        canvasSize: Qt.size(aurora.gw / 4, aurora.gh / 4)
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Cooperative
        onPaint: aurora.drawGlow(glow.getContext("2d"))
        onPainted: out.requestPaint()
    }

    Canvas {
        id: out
        anchors.fill: parent
        canvasSize: Qt.size(aurora.bw, aurora.bh)
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Cooperative
        onPaint: aurora.drawOut(out.getContext("2d"))
        onPainted: aurora.frameReady()
    }

    // for tests: save the three bitmaps
    function dump(prefix) {
        curtains.save(prefix + "-curtains.png")
        glow.save(prefix + "-glow.png")
        out.save(prefix + "-out.png")
    }

    function paintFrame() {
        if (!spritesOk) {
            spriteGreen.requestPaint(); spriteTeal.requestPaint(); spriteFringe.requestPaint()
            return
        }
        curtains.requestPaint()
    }
    onTimeChanged: if (active) paintFrame()
    onActiveChanged: if (active) paintFrame()
    onGradientStopsChanged: if (spritesOk) paintFrame()
    onSkyWidthChanged: if (spritesOk) paintFrame()
    onMilkyAngleChanged: if (spritesOk && active) paintFrame()
    Component.onCompleted: {
        spriteGreen.requestPaint(); spriteTeal.requestPaint(); spriteFringe.requestPaint()
    }

    readonly property var curtainDefs: [
        { sprite: 0, y: 320, a: [26, 12, 5], f: [2.4, 7.1, 19], s: [-0.035, 0.08, 0.22], h: 160, hf: 3.1, g: [4.2, 1.7], strength: 0.5, fringe: false, p: 2.1 },
        { sprite: 1, y: 410, a: [38, 16, 6], f: [3.1, 8.7, 23], s: [0.045, -0.11, 0.3], h: 235, hf: 4.3, g: [5.3, 2.2], strength: 1, fringe: true, p: 0 }
    ]

    function drawCurtains(ctx) {
        var W = aurora.skyWidth
        var q = aurora.quality
        ctx.reset()
        ctx.clearRect(0, 0, aurora.bw, aurora.bh)
        ctx.scale(aurora.bw / W, aurora.bh / 520)
        var t = aurora.time / 1000
        ctx.globalCompositeOperation = "lighter"
        var step = 2
        for (var ci = 0; ci < 2; ci++) {
            var c = curtainDefs[ci]
            var sprite = ci === 0 ? spriteTeal : spriteGreen
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
                ctx.globalAlpha = Math.min(1, light)
                ctx.drawImage(sprite, x, base - tall, 3, tall)
                if (c.fringe && light > 0.55) {
                    ctx.globalAlpha = Math.min(1, (light - 0.55) * 1.6)
                    ctx.drawImage(spriteFringe, x, base - 2, 3, 10)
                }
            }
        }
        ctx.globalAlpha = 1
        ctx.globalCompositeOperation = "source-over"
    }

    // The glow: a 1/8 size copy, then a 1/32 size copy of that (area averaging), blown up again with
    // linear filtering: together about the canvas's 16 px Gaussian, with no per-pixel work in JS
    function drawGlowMid(ctx) {
        ctx.reset()
        ctx.globalCompositeOperation = "copy"
        ctx.drawImage(curtains, 0, 0, aurora.bw, aurora.bh, 0, 0, aurora.gw, aurora.gh)
    }
    function drawGlow(ctx) {
        ctx.reset()
        ctx.globalCompositeOperation = "copy"
        ctx.drawImage(glowMid, 0, 0, aurora.gw, aurora.gh, 0, 0, aurora.gw / 4, aurora.gh / 4)
    }

    function drawOut(ctx) {
        var bw = aurora.bw, bh = aurora.bh
        ctx.reset()
        // The sky's own gradient behind this band
        var grad = ctx.createLinearGradient(0, -aurora.bandTop * bh / 520, 0, (aurora.skyHeight - aurora.bandTop) * bh / 520)
        for (var i = 0; i < gradientStops.length; i++)
            grad.addColorStop(gradientStops[i][0], gradientStops[i][1])
        ctx.fillStyle = grad
        ctx.fillRect(0, 0, bw, bh)
        ctx.globalCompositeOperation = "qt-screen"
        ctx.globalAlpha = 0.85
        ctx.drawImage(glow, 0, 0, aurora.gw / 4, aurora.gh / 4, 0, 0, bw, bh)
        ctx.globalAlpha = 0.92
        ctx.drawImage(curtains, 0, 0, bw, bh, 0, 0, bw, bh)
        ctx.globalAlpha = 1
        ctx.globalCompositeOperation = "source-over"
    }
}
