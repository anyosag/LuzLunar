// [fork] Tonight's moon from where the Moon and the Sun actually are, not from the mean length of a
// lunar month: real new and full moons drift from the mean by up to about 17 hours, which put the
// phase, the % lit and "full in N days" a day off around them. The Moon's elongation from the Sun
// uses the main periodic terms of Meeus, Astronomical Algorithms (2nd ed.), chapter 48: the lit
// fraction comes within about 1% of an ephemeris and new and full moons within about an hour
// (checked against PyEphem for 2026-2030). Plain JavaScript, so ForkMoonWidget's text stays in QML.
.pragma library

var SYNODIC = 29.530588853  // mean days from one new moon to the next
var RATE = 360 / SYNODIC    // mean degrees a day the Moon gains on the Sun

function rad(deg) { return deg * Math.PI / 180 }

// Wraps an angle into [0, 360)
function wrap360(deg) { return ((deg % 360) + 360) % 360 }

// Wraps an angle into [-180, 180)
function wrap180(deg) { return wrap360(deg + 180) - 180 }

// The Moon's elongation from the Sun at `ms` (Unix ms, UTC), in degrees: 0 at new moon, 90 at first
// quarter, 180 at full, 270 at last quarter. 180 minus the phase angle of Meeus (48.4).
function elongation(ms) {
    var T = (ms / 86400000 + 2440587.5 - 2451545.0) / 36525
    var D = 297.8501921 + 445267.1114034 * T - 0.0018819 * T * T + T * T * T / 545868 - T * T * T * T / 113065000
    var M = 357.5291092 + 35999.0502909 * T - 0.0001536 * T * T + T * T * T / 24490000
    var Mp = 134.9633964 + 477198.8675055 * T + 0.0087414 * T * T + T * T * T / 69699 - T * T * T * T / 14712000
    var i = 180 - D
            - 6.289 * Math.sin(rad(Mp))
            + 2.100 * Math.sin(rad(M))
            - 1.274 * Math.sin(rad(2 * D - Mp))
            - 0.658 * Math.sin(rad(2 * D))
            - 0.214 * Math.sin(rad(2 * Mp))
            - 0.110 * Math.sin(rad(D))
    return wrap360(180 - i)
}

// Days from `ms` until the elongation next reaches `target` degrees (forward > 0), or since it last
// did (forward < 0): a guess from the mean rate, then Newton steps on the true elongation
function daysTo(ms, target, forward) {
    var e = elongation(ms)
    var days = forward > 0 ? wrap360(target - e) / RATE : -wrap360(e - target) / RATE
    for (var n = 0; n < 5; n++) {
        days += wrap180(target - elongation(ms + days * 86400000)) / RATE
    }
    return days
}

// Everything ForkMoonWidget shows, at `ms`:
//   phase      0..1 through the month (0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter)
//   lit        the lit fraction of the disc, 0..1
//   waxing     true from new moon to full
//   toFull     days to the next full moon
//   toNew      days to the next new moon
//   sinceFull  days since the last full moon
function at(ms) {
    var e = elongation(ms)
    return {
        phase: e / 360,
        lit: (1 - Math.cos(rad(e))) / 2,
        waxing: e < 180,
        toFull: daysTo(ms, 180, 1),
        toNew: daysTo(ms, 0, 1),
        sinceFull: -daysTo(ms, 180, -1)
    }
}
