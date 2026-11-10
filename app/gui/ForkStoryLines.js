// [fork] The sentences under "Your PCs": one per state, not per PC, so six PCs read "GonzaloPC is
// ready" and "Can’t reach 5 PCs" instead of six crowded lines (contract-reorder.md §1). Plain data
// in, plain data out; ForkStoryRow draws what build() returns. The strings are qsTr'd here.
.pragma library

// Good news first, problems last. streaming is never grouped (each PC has its own Resume).
var ORDER = ["streaming", "waking", "ready", "asleep", "pair", "off", "checking", "lost"]

function kindOf(state) {
    switch (state) {
    case "streaming": case "waking": case "asleep": case "pair": case "checking": case "lost": return state
    case "off": case "offNoWake": return "off"
    }
    return "ready"
}

function dotOf(kind, st) {
    switch (kind) {
    case "streaming": return st.blue
    case "waking": return st.amber
    case "asleep": return st.purple
    case "pair": return st.gold
    case "off": case "checking": return st.gray
    case "lost": return st.red
    }
    return st.green
}

// [before, separator, after] around the names for 1, 2 and 3+ PCs of a kind
function words(kind, n) {
    var one = n === 1
    switch (kind) {
    case "waking": return ["", one ? qsTr(" is waking up…") : qsTr(" are waking up…")]
    case "asleep": return ["", one ? qsTr(" is asleep") : qsTr(" are asleep")]
    case "pair": return ["", one ? qsTr(" is waiting to pair") : qsTr(" are waiting to pair")]
    case "off": return ["", one ? qsTr(" is shut down") : qsTr(" are shut down")]
    case "checking": return [qsTr("Looking for "), qsTr("…")]
    case "lost": return [qsTr("Can’t reach "), ""]
    }
    return ["", one ? qsTr(" is ready") : qsTr(" are ready")]
}

// Names for a tooltip: each once, then "+n more" past 6
function tipOf(members) {
    var seen = {}, list = []
    for (var i = 0; i < members.length; i++) {
        if (seen[members[i].name] === true) continue
        seen[members[i].name] = true
        list.push(members[i].name)
    }
    if (list.length <= 6) return list.join("\n")
    return list.slice(0, 6).join("\n") + "\n" + qsTr("+%1 more").arg(list.length - 6)
}

// pcs: [{ index, name, state, app }] in the stage's order; st: ForkTheme.st
// -> [{ names: [{ name, index }], count, label, tip, before, sep, after, dot, action, indexes }]
function build(pcs, st) {
    var groups = {}
    var i, k
    for (i = 0; i < pcs.length; i++) {
        k = kindOf(pcs[i].state)
        if (groups[k] === undefined) groups[k] = []
        groups[k].push(pcs[i])
    }
    var out = []
    for (var g = 0; g < ORDER.length; g++) {
        var kind = ORDER[g]
        var list = groups[kind]
        if (list === undefined) continue
        var dot = dotOf(kind, st)
        if (kind === "streaming") {
            for (i = 0; i < list.length; i++) {
                var app = list[i].app !== undefined && list[i].app !== "" ? list[i].app : qsTr("Desktop")
                out.push({ names: [{ name: list[i].name, index: list[i].index }], count: 0, label: "", tip: "",
                           before: qsTr("%1 is running on ").arg(app), sep: "", after: "", dot: dot,
                           action: qsTr("Resume"), indexes: [list[i].index] })
            }
            continue
        }
        var w = words(kind, list.length)
        var line = { names: [], count: 0, label: "", tip: "", before: w[0], sep: qsTr(" and "), after: w[1],
                     dot: dot, action: "", indexes: [] }
        for (i = 0; i < list.length; i++) line.indexes.push(list[i].index)
        if (list.length >= 3) {
            line.count = list.length
            line.label = qsTr("%1 PCs").arg(list.length)
            line.tip = tipOf(list)
        } else {
            for (i = 0; i < list.length; i++) line.names.push({ name: list[i].name, index: list[i].index })
        }
        out.push(line)
    }
    return out
}
