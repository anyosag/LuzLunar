// [fork] The words, icons and per-state looks of a PC card (the canvas's "Card states" and "Main"
// boards), shared by ForkPcCard, ForkPcCardSmall, the page and the screenshot harness. Plain data
// in, plain data out. Colors, tints and the status disc come from ForkTheme.stateStyle; icons are
// names of ForkIconPaths.js; chip and button inks are keys ("green", "orange", "text2") that the QML
// maps through ForkTheme.
.pragma library

// The state ids: ready streaming waking asleep offCanWake offNoWake notPaired unreachable checking
// (checking is not on the canvas: a PC that has not answered since launch, drawn neutral)
var STATES = ["ready", "streaming", "waking", "asleep", "offCanWake", "offNoWake", "notPaired", "unreachable", "checking"]

// The model's short state names (contract-data) to the card's
var ALIASES = { off: "offCanWake", offNoWake: "offNoWake", pair: "notPaired", lost: "unreachable" }

function normalizeState(s) {
    if (STATES.indexOf(s) >= 0) return s
    if (ALIASES[s]) return ALIASES[s]
    return "ready"
}

// Which moon the header draws: live (the lit crescent), waking, asleep, off (plain ring), pair, lost
var MOONS = {
    ready: "live", streaming: "live", waking: "waking", asleep: "asleep", offCanWake: "off",
    offNoWake: "off", notPaired: "pair", unreachable: "lost", checking: "off"
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
    var app = p.runningApp || "Desktop"
    var defApp = p.defaultApp || "Desktop"
    var out = {
        state: state, moon: MOONS[state], subLine: "", ipNote: "", title: "", sub: "",
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
        out.showApps = true; out.sleepy = true; out.tilesTitle = "Wake and stream"; out.allNote = "From its last visit"
        out.chips.push({ label: "Sent from this Mac", icon: "wifi", colorKey: "text2" })
        out.quiet = [{ id: "testNetwork", label: "Test Network", icon: "wifi", colorKey: "text2" }]
        out.primary = { id: "", label: "Waking…", icon: "spinner", fill: false, disabled: true }
        break
    case "asleep":
        out.title = "Asleep"; out.sub = "Picking an app wakes it first"
        out.showApps = true; out.sleepy = true; out.tilesTitle = "Wake and stream"; out.allNote = "From its last visit"
        if (wakeChip) out.chips.push(wakeChip)
        if (!p.updateAvailable) out.chips.push(updateChip)
        out.quiet = [{ id: "testNetwork", label: "Test Network", icon: "wifi", colorKey: "text2" }]
        out.primary = { id: "wake", label: "Wake PC", icon: "power", fill: false }
        break
    case "offCanWake":
        out.title = "Shut down"; out.sub = "Turn On wakes it from off over the network"
        out.showApps = true; out.sleepy = true; out.badge = "power"
        out.tilesTitle = "Wake and stream"; out.allNote = "From its last visit"
        out.chips.push({ label: "Wake from off ready", icon: "check", colorKey: "green" })
        out.quiet = [{ id: "testNetwork", label: "Test Network", icon: "wifi", colorKey: "text2" }]
        out.primary = { id: "turnOn", label: "Turn On", icon: "power", fill: false }
        break
    case "offNoWake":
        out.title = "Shut down"; out.sub = "It can’t be turned on from here yet"
        out.chips.push({ label: "Wake from off not set up", icon: "check", colorKey: "orange" })
        out.quiet = [{ id: "testNetwork", label: "Test Network", icon: "wifi", colorKey: "text2" }]
        out.primary = { id: "setupWake", label: "Set Up Wake…", icon: "check", fill: false, quietLook: true }
        break
    case "notPaired":
        out.title = "Not paired yet"; out.sub = "Pair once to stream; it takes about a minute"
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
        out.chips.push({ label: "Last seen at home", icon: "cable", colorKey: "text2" })
        out.primary = { id: "testNetwork", label: "Test Network", icon: "wifi", fill: false, quietLook: true }
        break
    case "checking":
        out.title = "Looking for " + p.name + "\u2026"; out.sub = "LuzLunar is checking where it is on your network."
        out.primary = { id: "", label: "Checking\u2026", icon: "spinner", fill: false, disabled: true }
        break
    }
    return out
}

// The small card's (States board) words and looks. Same p as describe().
function describeSmall(p) {
    var state = normalizeState(p.state)
    var dark = p.dark !== false
    var o = {
        state: state, moon: MOONS[state], host: "", headline: "", sub: "", chip: null,
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
    case "checking":
        o.headline = "Looking for " + p.name + "\u2026"; o.sub = "LuzLunar is checking where it is on your network."
        o.chip = null
        o.action = { id: "", label: "Checking\u2026", icon: "spinner", fill: false, disabled: true }
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
