.pragma library
.import StreamProfiles 1.0 as StreamProfilesModule
.import StreamingPreferences 1.0 as PrefsModule
.import SystemProperties 1.0 as SystemModule
.import AspectRatios 1.0 as RatiosModule

// [fork] What a stream of an app would use, and the lines that say so (the All apps band's one line
// for the running app, and the chips of the launch screen). Shared by AppView and PcView. All take
// the PC's uuid (StreamProfiles.hostUuid) and the app's name; `profileName` is an optional function
// (profile) -> "Office profile" | "Gaming profile" | "Custom profile" (StreamProfileDialog.profileName),
// which is only asked for an app that has a profile; without it a profile adds no line or chip.

function effectiveStream(hostUuid, appName) {
    var StreamProfiles = StreamProfilesModule.StreamProfiles
    var StreamingPreferences = PrefsModule.StreamingPreferences
    var SystemProperties = SystemModule.SystemProperties
    var p = StreamProfiles.profile(hostUuid, appName)
    function has(key) { return p[key] !== undefined }
    var w = has("width") ? p.width : StreamingPreferences.width
    var h = has("height") ? p.height : StreamingPreferences.height
    var fps = has("fps") ? p.fps : StreamingPreferences.fps
    var yuv = has("enableYUV444") ? p.enableYUV444 : StreamingPreferences.enableYUV444
    var codec = has("videoCodecConfig") ? p.videoCodecConfig : StreamingPreferences.videoCodecConfig
    // H.264 has no HDR, so an HDR setting leaves that stream in SDR
    var hdr = SystemProperties.supportsHdr && codec !== StreamingPreferences.VCC_FORCE_H264 &&
              (has("enableHdr") ? p.enableHdr : StreamingPreferences.enableHdr)
    var bitrate = has("bitrateKbps") ? p.bitrateKbps : StreamingPreferences.bitrateKbps
    if (!has("bitrateKbps") && (has("width") || has("height") || has("fps") || has("enableYUV444")) &&
            StreamingPreferences.bitrateKbps === StreamingPreferences.getDefaultBitrate(StreamingPreferences.width, StreamingPreferences.height,
                                                                                        StreamingPreferences.fps, StreamingPreferences.enableYUV444)) {
        bitrate = StreamingPreferences.getDefaultBitrate(w, h, fps, yuv)
    }
    var trackpad = has("trackpadMode") ? p.trackpadMode : StreamingPreferences.trackpadMode
    return { "profile": p, "width": w, "height": h, "fps": fps, "yuv": yuv, "hdr": hdr, "codec": codec, "bitrate": bitrate,
             "trackpad": trackpad }
}

// "Mac trackpad" or "Touchpad" (the Windows touchpad), or nothing for a trackpad that's a mouse
function trackpadChip(mode) {
    var StreamingPreferences = PrefsModule.StreamingPreferences
    return mode === StreamingPreferences.TM_MAC_TRACKPAD ? qsTr("Mac trackpad")
         : mode === StreamingPreferences.TM_WINDOWS_TOUCHPAD ? qsTr("Touchpad")
         : ""
}

function codecName(codec) {
    var StreamingPreferences = PrefsModule.StreamingPreferences
    return codec === StreamingPreferences.VCC_FORCE_H264 ? "H.264"
         : codec === StreamingPreferences.VCC_FORCE_AV1 ? "AV1"
         : codec === StreamingPreferences.VCC_FORCE_HEVC ? "HEVC"
         : qsTr("Automatic codec")
}

// The name a profile goes by everywhere; empty for an app with none (or without a naming function)
function profileLabel(profile, profileName) {
    return Object.keys(profile).length > 0 && profileName ? profileName(profile) : ""
}

// Chips for the launch screen. The profile's name is last, as an object so the panel shows it in
// the text font like the design.
function streamSummary(hostUuid, appName, profileName) {
    var e = effectiveStream(hostUuid, appName)
    var Ratios = RatiosModule.AspectRatios
    var chips = [e.width + "×" + e.height + " · " + Ratios.ratioLabel(e.width, e.height), qsTr("%1 fps").arg(e.fps),
                 qsTr("%1 Mb/s").arg(e.bitrate / 1000), codecName(e.codec) + (e.hdr ? " · HDR" : "")]
    if (e.yuv) {
        chips.push("4:4:4")
    }
    if (trackpadChip(e.trackpad) !== "") {
        chips.push(trackpadChip(e.trackpad))
    }
    var profile = profileLabel(e.profile, profileName)
    if (profile !== "") {
        chips.push({ "text": profile, "plain": true })
    }
    return chips
}

// The band's one line for the running app, like "3024×1890 · 120 fps · HEVC 10-bit · Office profile"
function bannerSummary(hostUuid, appName, profileName) {
    var StreamingPreferences = PrefsModule.StreamingPreferences
    var e = effectiveStream(hostUuid, appName)
    var codec = codecName(e.codec)
    if (e.hdr) {
        codec += e.codec === StreamingPreferences.VCC_AUTO ? " · HDR" : " 10-bit"
    }
    var parts = [e.width + "×" + e.height, qsTr("%1 fps").arg(e.fps), codec]
    var profile = profileLabel(e.profile, profileName)
    if (profile !== "") {
        parts.push(profile)
    }
    return parts.join(" · ")
}

// The same name for a preset ("office", "gaming" or "custom"), for the screenshot harness's samples
function presetName(preset) {
    return preset === "office" ? qsTr("Office profile") : preset === "gaming" ? qsTr("Gaming profile") : qsTr("Custom profile")
}
