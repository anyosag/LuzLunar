// [fork] The words, icons and per-state looks of a PC card (the canvas's "Card states" and "Main"
// boards), shared by ForkPcCard, ForkPcCardSmall, the page and the screenshot harness. Plain data
// in, plain data out: colors are given as hex strings (the state colors the canvas calls S, plus
// the status discs), or as keys ("green", "blue", "purple", "gold", "orange", "red", "amber",
// "gray", "text2") that the QML maps through ForkTheme.
.pragma library

var ICONS = {
    play: "M8 5.8v12.4L18.2 12z",
    power: "M12 3.5v8M7.05 6.55a7 7 0 1 0 9.9 0",
    lock: "M6.5 10.5h11a1.5 1.5 0 0 1 1.5 1.5v6.5a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 18.5V12a1.5 1.5 0 0 1 1.5-1.5zM8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5",
    moon: "M15 4.2a7.8 7.8 0 1 0 4.8 13.1A6.6 6.6 0 0 1 15 4.2z",
    stop: "M8 6.5h8A1.5 1.5 0 0 1 17.5 8v8a1.5 1.5 0 0 1-1.5 1.5H8A1.5 1.5 0 0 1 6.5 16V8A1.5 1.5 0 0 1 8 6.5z",
    wifi: "M4.5 9.5a11 11 0 0 1 15 0M7.5 12.8a6.5 6.5 0 0 1 9 0M12 16.6h.01",
    noWifi: "M4.5 9.5a11 11 0 0 1 15 0M7.5 12.8a6.5 6.5 0 0 1 9 0M12 16.6h.01M4 4l16 16",
    check: "M12 3a9 9 0 1 1 0 18 9 9 0 0 1 0-18zM8.3 12.3l2.5 2.5 5-5.2",
    tick: "M6.5 12.5l3.5 3.5 7.5-8",
    update: "M12 3a9 9 0 1 1 0 18 9 9 0 0 1 0-18zM12 7.5v8M8.5 12.5 12 16l3.5-3.5",
    cable: "M7.5 4h9v9h-9zM10 13v4M14 13v4M12 17v3M10 7.5h4",
    pin: "M12 3.5a5.5 5.5 0 0 1 5.5 5.5c0 4.2-5.5 11.5-5.5 11.5S6.5 13.2 6.5 9A5.5 5.5 0 0 1 12 3.5zM12 7.2a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6z",
    spinner: "M12 4a8 8 0 1 0 8 8",
    copy: "M9.5 9h9a1.5 1.5 0 0 1 1.5 1.5v9a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 8 19.5v-9A1.5 1.5 0 0 1 9.5 9zM5 15.5V5.5A1.5 1.5 0 0 1 6.5 4h9",
    more: "M6 12h.01M12 12h.01M18 12h.01",
    plus: "M12 4.5v15M4.5 12h15"
}

// The state ids: ready streaming waking asleep offCanWake offNoWake notPaired unreachable
var STATES = ["ready", "streaming", "waking", "asleep", "offCanWake", "offNoWake", "notPaired", "unreachable"]

// The model's short state names (contract-data) to the card's
var ALIASES = { off: "offCanWake", offNoWake: "offNoWake", pair: "notPaired", lost: "unreachable" }

function normalizeState(s) {
    if (STATES.indexOf(s) >= 0) return s
    if (ALIASES[s]) return ALIASES[s]
    return "ready"
}

// State colors by key (the canvas's S, plus the two only the States board has)
function stateColor(key, dark) {
    var t = {
        green: ["#30D158", "#1A7F37"], blue: ["#409CFF", "#0062CC"], purple: ["#C17DF5", "#8E3BB8"],
        gold: ["#F5C878", "#8A5A00"], orange: ["#FF9F0A", "#A85A00"], red: ["#FF6961", "#C1272D"],
        amber: ["#FFB340", "#9A5B00"], gray: ["#9EA3B5", "#5F616E"]
    }[key]
    return t ? t[dark ? 0 : 1] : ""
}

function rgba(r, g, b, a) { return { r: r / 255, g: g / 255, b: b / 255, a: a } }

// The status box tint of a state. big: the Main board's (its light tints differ a little)
function tint(state, dark, big) {
    var a = dark ? 0.13 : 0.08
    switch (state) {
    case "ready": return rgba(48, 209, 88, a)
    case "streaming": return rgba(64, 156, 255, big ? a : a)
    case "waking": return rgba(255, 179, 64, a)
    case "asleep": return rgba(193, 125, 245, a)
    case "offCanWake":
    case "offNoWake": return dark ? rgba(255, 255, 255, 0.06) : rgba(0, 0, 0, 0.05)
    case "notPaired":
        if (big) return dark ? rgba(245, 200, 120, 0.12) : rgba(168, 114, 15, 0.09)
        return rgba(245, 200, 120, a)
    case "unreachable": return rgba(255, 105, 97, a)
    }
    return rgba(255, 255, 255, 0.06)
}

// The light tint of streaming / asleep / pair on the big card is a different color than the dark
// one's rgb: Main's own values
function tintBig(state, dark) {
    if (!dark) {
        if (state === "streaming") return rgba(0, 98, 204, 0.08)
        if (state === "asleep") return rgba(142, 59, 184, 0.08)
    }
    return tint(state, dark, true)
}

var DISCS = {
    ready: { disc: "#248A3D", ink: "#FFFFFF", glyph: "tick", fill: false },
    streaming: { disc: "#0A6CDB", ink: "#FFFFFF", glyph: "play", fill: true },
    waking: { disc: "#B85800", ink: "#FFFFFF", glyph: "spinner", fill: false },
    asleep: { disc: "#9B45D9", ink: "#FFFFFF", glyph: "moon", fill: false },
    offCanWake: { disc: "#636366", ink: "#FFFFFF", glyph: "power", fill: false },
    offNoWake: { disc: "#636366", ink: "#FFFFFF", glyph: "power", fill: false },
    notPaired: { disc: "#F5C878", ink: "#1A1405", glyph: "lock", fill: false },
    unreachable: { disc: "#C62828", ink: "#FFFFFF", glyph: "noWifi", fill: false }
}

// Which moon the header draws: live (the lit crescent), waking, asleep, off (plain ring), pair, lost
var MOONS = {
    ready: "live", streaming: "live", waking: "waking", asleep: "asleep", offCanWake: "off",
    offNoWake: "off", notPaired: "pair", unreachable: "lost"
}

function join(parts) {
    var out = []
    for (var i = 0; i < parts.length; i++) if (parts[i]) out.push(parts[i])
    return out.join(" · ")
}

function latencyText(ms) { return (ms !== undefined && ms !== null && ms >= 0) ? ms + " ms" : "" }

// p: { state, name, version, network, latencyMs, address, runningApp, defaultApp, streamWidth,
//      streamHeight, streamFps, streamHdr, wakeFromOff ("ready"|"notSetUp"|"unknown"),
//      updateAvailable, reachableOutside, onLanNow, dark, ipNote }
// The big card's words and looks.
function describe(p) {
    var state = normalizeState(p.state)
    var dark = p.dark !== false
    var d = DISCS[state]
    var app = p.runningApp || "Desktop"
    var defApp = p.defaultApp || "Desktop"
    var out = {
        state: state, moon: MOONS[state], disc: d.disc, discInk: d.ink, glyph: d.glyph, glyphFill: d.fill,
        tint: tintBig(state, dark), subLine: "", ipNote: "", title: "", sub: "", label: "", labelKey: "",
        tilesTitle: "", tilesNote: "", allNote: "", showApps: false, showSteps: false, sleepy: false,
        badge: "moon", chips: [], quiet: [], primary: {}, steps: []
    }
    var net = p.network || "Home network"
    switch (state) {
    case "ready":
    case "streaming":
        out.subLine = join([p.version ? "Apollo " + p.version : "", net, latencyText(p.latencyMs)])
        out.ipNote = p.ipNote !== undefined ? p.ipNote : (p.reachableOutside ? "Reachable from outside too" : "")
        break
    case "notPaired":
        out.subLine = join(["Found on your network", latencyText(p.latencyMs)])
        out.ipNote = p.ipNote !== undefined ? p.ipNote : "Found automatically"
        break
    default:
        out.subLine = join([p.version ? "Apollo " + p.version : "", "last seen at home"])
        out.ipNote = p.ipNote !== undefined ? p.ipNote : "Its last address"
    }

    var wakeChip = p.wakeFromOff === "ready" ? { label: "Wake from off ready", icon: "check", colorKey: "green" } : null
    var updateChip = p.updateAvailable
        ? { label: "Update Apollo", icon: "update", colorKey: "orange", button: true, id: "updateApollo" }
        : { label: "Apollo up to date", icon: "update", colorKey: "text2" }

    switch (state) {
    case "ready":
        out.title = "Ready to stream"; out.sub = "Pick an app, or press Return for Desktop"
        out.label = "Ready"; out.labelKey = "green"
        out.showApps = true; out.tilesTitle = "Apps"; out.tilesNote = "Return starts " + defApp
        out.allNote = "Hidden ones too"
        if (wakeChip) out.chips.push(wakeChip)
        out.chips.push(updateChip)
        out.quiet = [{ id: "sleep", label: "Sleep", icon: "moon", colorKey: "purple" }]
        out.primary = { id: "stream", label: "Stream " + defApp, icon: "play", fill: true }
        break
    case "streaming":
        var info = ["On this Mac"]
        if (p.streamWidth > 0) info.push(p.streamWidth + "×" + p.streamHeight)
        if (p.streamFps > 0) info.push(p.streamFps + " fps")
        if (p.streamHdr) info.push("HDR")
        out.title = app + " is running"; out.sub = info.join(" · ")
        out.label = "Streaming"; out.labelKey = "blue"
        out.showApps = true; out.tilesTitle = "Apps"; out.tilesNote = "Return resumes " + app
        out.allNote = "Hidden ones too"
        if (wakeChip) out.chips.push(wakeChip)
        out.chips.push(updateChip)
        out.quiet = [{ id: "quit", label: "Quit " + app, icon: "stop", colorKey: "text2" },
                     { id: "sleep", label: "Sleep", icon: "moon", colorKey: "purple" }]
        out.primary = { id: "resume", label: "Resume " + app, icon: "play", fill: true }
        break
    case "waking":
        out.title = "Waking up…"; out.sub = "Wake PC was sent. The card turns ready when it answers"
        out.label = "Waking"; out.labelKey = "amber"
        out.showApps = true; out.sleepy = true; out.tilesTitle = "Wake and stream"; out.allNote = "From its last visit"
        out.chips.push({ label: "Sent from this Mac", icon: "wifi", colorKey: "text2" })
        out.quiet = [{ id: "testNetwork", label: "Test Network", icon: "wifi", colorKey: "text2" }]
        out.primary = { id: "", label: "Waking…", icon: "spinner", fill: false, disabled: true }
        break
    case "asleep":
        out.title = "Asleep"; out.sub = "Picking an app wakes it first"
        out.label = "Asleep"; out.labelKey = "purple"
        out.showApps = true; out.sleepy = true; out.tilesTitle = "Wake and stream"; out.allNote = "From its last visit"
        if (wakeChip) out.chips.push(wakeChip)
        if (!p.updateAvailable) out.chips.push(updateChip)
        out.quiet = [{ id: "testNetwork", label: "Test Network", icon: "wifi", colorKey: "text2" }]
        out.primary = { id: "wake", label: "Wake PC", icon: "power", fill: false }
        break
    case "offCanWake":
        out.title = "Shut down"; out.sub = "Turn On wakes it from off over the network"
        out.label = "Off"; out.labelKey = "gray"
        out.showApps = true; out.sleepy = true; out.badge = "power"
        out.tilesTitle = "Wake and stream"; out.allNote = "From its last visit"
        out.chips.push({ label: "Wake from off ready", icon: "check", colorKey: "green" })
        out.quiet = [{ id: "testNetwork", label: "Test Network", icon: "wifi", colorKey: "text2" }]
        out.primary = { id: "turnOn", label: "Turn On", icon: "power", fill: false }
        break
    case "offNoWake":
        out.title = "Shut down"; out.sub = "It can’t be turned on from here yet"
        out.label = "Off"; out.labelKey = "gray"
        out.chips.push({ label: "Wake from off not set up", icon: "check", colorKey: "orange" })
        out.quiet = [{ id: "testNetwork", label: "Test Network", icon: "wifi", colorKey: "text2" }]
        out.primary = { id: "setupWake", label: "Set Up Wake…", icon: "check", fill: false, quietLook: true }
        break
    case "notPaired":
        out.title = "Not paired yet"; out.sub = "Pair once to stream; it takes about a minute"
        out.label = "Not paired"; out.labelKey = "gold"
        out.showSteps = true
        out.steps = ["Choose Pair with this PC. LuzLunar shows a 4-digit PIN.",
                     "On " + p.name + ", open Apollo’s web page and go to PIN.",
                     "Type the PIN there. This card then shows its apps."]
        if (p.onLanNow !== false) out.chips.push({ label: "Same network as this Mac", icon: "cable", colorKey: "green" })
        out.quiet = [{ id: "testNetwork", label: "Test Network", icon: "wifi", colorKey: "text2" }]
        out.primary = { id: "pair", label: "Pair with this PC", icon: "lock", fill: false }
        break
    case "unreachable":
        out.title = "Can’t reach it"; out.sub = "Not on this network, or Apollo isn’t running"
        out.label = "Can’t reach"; out.labelKey = "red"
        out.chips.push({ label: "Last seen at home", icon: "cable", colorKey: "text2" })
        out.primary = { id: "testNetwork", label: "Test Network", icon: "wifi", fill: false, quietLook: true }
        break
    }
    return out
}

// The small card's (States board) words and looks. Same p as describe().
function describeSmall(p) {
    var state = normalizeState(p.state)
    var dark = p.dark !== false
    var d = DISCS[state]
    var o = {
        state: state, moon: MOONS[state], disc: d.disc, discInk: d.ink, glyph: d.glyph, glyphFill: d.fill,
        tint: tint(state, dark, false), host: "", headline: "", sub: "", chip: null,
        action: { id: "", label: "", icon: "", fill: false, quietLook: false, disabled: false }
    }
    o.host = state === "notPaired" ? "Found · " + p.address : "Apollo · " + p.address
    switch (state) {
    case "ready":
        o.headline = "Ready to stream"; o.sub = "Pick an app, or press Return for Desktop."
        o.chip = p.updateAvailable ? { label: "Update Apollo", icon: "update", colorKey: "orange", warm: true }
                                   : { label: "Apollo up to date", icon: "update", colorKey: "text2" }
        o.action = { id: "stream", label: "Stream " + (p.defaultApp || "Desktop"), icon: "play", fill: true }
        break
    case "streaming":
        var info = ["On this Mac"]
        if (p.streamWidth > 0) info.push(p.streamWidth + "×" + p.streamHeight)
        if (p.streamFps > 0) info.push(p.streamFps + " fps")
        o.headline = (p.runningApp || "Desktop") + " is running"; o.sub = info.join(" · ")
        o.chip = { label: join([p.network || "Home network", latencyText(p.latencyMs)]), icon: "cable", colorKey: "green" }
        o.action = { id: "resume", label: "Resume " + (p.runningApp || "Desktop"), icon: "play", fill: true }
        break
    case "waking":
        o.headline = "Waking up…"; o.sub = "Wake PC was sent. The card turns ready when it answers."
        o.chip = { label: "Sent from this Mac", icon: "wifi", colorKey: "text2" }
        o.action = { id: "", label: "Waking…", icon: "spinner", fill: false, disabled: true }
        break
    case "asleep":
        o.headline = "Asleep"; o.sub = "Picking an app wakes it first."
        o.chip = { label: "Wake from off ready", icon: "check", colorKey: "green" }
        o.action = { id: "wake", label: "Wake PC", icon: "power", fill: false }
        break
    case "offCanWake":
        o.headline = "Shut down"; o.sub = "Turn On wakes it from off over the network."
        o.chip = { label: "Wake from off ready", icon: "check", colorKey: "green" }
        o.action = { id: "turnOn", label: "Turn On", icon: "power", fill: false }
        break
    case "offNoWake":
        o.headline = "Shut down"; o.sub = "It can’t be turned on from here yet."
        o.chip = { label: "Wake from off not set up", icon: "check", colorKey: "orange" }
        o.action = { id: "setupWake", label: "Set Up Wake…", icon: "check", fill: false, quietLook: true }
        break
    case "notPaired":
        o.headline = "Not paired yet"; o.sub = "Pair once with a 4-digit PIN."
        o.chip = { label: p.address, icon: "pin", colorKey: "text2" }
        o.action = { id: "pair", label: "Pair with this PC", icon: "lock", fill: false }
        break
    case "unreachable":
        o.headline = "Can’t reach it"; o.sub = "Not on this network, or Apollo isn’t running."
        o.chip = { label: "Last seen at home", icon: "cable", colorKey: "text2" }
        o.action = { id: "testNetwork", label: "Test Network", icon: "wifi", fill: false, quietLook: true }
        break
    }
    return o
}

// The States board's own titles, in order
var STATE_TITLES = {
    ready: "Ready", streaming: "Streaming", waking: "Waking", asleep: "Asleep", offCanWake: "Off, can turn on",
    offNoWake: "Off, not set up", notPaired: "Not paired", unreachable: "Can’t reach"
}

// The legend: label and color key
var LEGEND = [["Ready", "green"], ["Streaming", "blue"], ["Waking", "amber"], ["Asleep", "purple"],
              ["Off", "gray"], ["Not paired", "gold"], ["Can’t reach", "red"], ["Update", "orange"]]
