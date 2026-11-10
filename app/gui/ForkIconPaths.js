.pragma library

// [fork] Every icon path of the redesign canvas, verbatim, keyed by name. The names are the keys of
// the canvas's `I` dictionary (Main.dc.html 640-664, Library.dc.html, States.dc.html) plus the
// icons the boards draw inline (header, carousel arrows, menus, empty state, Customize).
//
// Each entry: d (SVG path data, viewBox 0 0 24 24 unless vb is set), sw (stroke width in viewBox
// units, the most common one the boards use), fill (true when the board draws it filled with
// currentColor), noStroke (true when the board draws it with stroke="none"), vb ([x, y, w, h]).
// ForkPathIcon draws them; get(name) returns the entry or null.

var icons = {
    // The canvas's `I` dictionary
    play:     { d: "M8 5.8v12.4L18.2 12z", sw: 1.9, fill: true },
    pause:    { d: "M9 6v12M15 6v12", sw: 2.2 },
    power:    { d: "M12 3.5v8M7.05 6.55a7 7 0 1 0 9.9 0", sw: 1.9 },
    lock:     { d: "M6.5 10.5h11a1.5 1.5 0 0 1 1.5 1.5v6.5a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 18.5V12a1.5 1.5 0 0 1 1.5-1.5zM8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5", sw: 1.9 },
    grid:     { d: "M4.5 4.5h5.5V10H4.5zM14 4.5h5.5V10H14zM4.5 14h5.5v5.5H4.5zM14 14h5.5v5.5H14z", sw: 1.8 },
    display:  { d: "M4.5 4.5h15a1.5 1.5 0 0 1 1.5 1.5v9a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 15V6a1.5 1.5 0 0 1 1.5-1.5zM9 20h6M12 16.5V20", sw: 1.8 },
    displays: { d: "M3 8h10v7H3zM11 5h10v7h-6M6 19h4M8 15v4", sw: 1.8 },
    gamepad:  { d: "M7.5 8.5h9a4 4 0 0 1 3.9 4.9l-.7 3.1a2.2 2.2 0 0 1-3.9.9L14.4 15H9.6l-1.4 2.4a2.2 2.2 0 0 1-3.9-.9l-.7-3.1A4 4 0 0 1 7.5 8.5zM8 10.8v3.2M6.4 12.4h3.2M15.6 11.6h.01M17.4 13.2h.01", sw: 1.8 },
    moon:     { d: "M15 4.2a7.8 7.8 0 1 0 4.8 13.1A6.6 6.6 0 0 1 15 4.2z", sw: 1.8 },
    restart:  { d: "M19 12a7 7 0 1 1-2.05-4.95M19 4.5V8h-3.5", sw: 1.8 },
    wifi:     { d: "M4.5 9.5a11 11 0 0 1 15 0M7.5 12.8a6.5 6.5 0 0 1 9 0M12 16.6h.01", sw: 1.8 },
    cable:    { d: "M7.5 4h9v9h-9zM10 13v4M14 13v4M12 17v3M10 7.5h4", sw: 1.8 },
    check:    { d: "M12 3a9 9 0 1 1 0 18 9 9 0 0 1 0-18zM8.3 12.3l2.5 2.5 5-5.2", sw: 1.9 },
    update:   { d: "M12 3a9 9 0 1 1 0 18 9 9 0 0 1 0-18zM12 7.5v8M8.5 12.5 12 16l3.5-3.5", sw: 1.9 },
    sliders:  { d: "M4 7h9M17 7h3M4 12h3M11 12h9M4 17h11M19 17h1M15 5v4M9 10v4M17 15v4", sw: 1.8 },
    palette:  { d: "M12 3.5a8.5 8.5 0 1 0 0 17c1.2 0 1.8-.9 1.5-1.9-.4-1.3.4-2.4 1.8-2.4h1.7a3.5 3.5 0 0 0 3.5-3.5C20.5 7.6 16.7 3.5 12 3.5zM8 11h.01M11 7.6h.01M15.2 8.4h.01", sw: 1.8 },
    info:     { d: "M12 3a9 9 0 1 1 0 18 9 9 0 0 1 0-18zM12 11v5.5M12 7.8h.01", sw: 1.8 },
    trash:    { d: "M5 7h14M10 4h4M7 7l.8 12a1.5 1.5 0 0 0 1.5 1.4h5.4a1.5 1.5 0 0 0 1.5-1.4L17 7M10.2 10.5v6M13.8 10.5v6", sw: 1.8 },
    stop:     { d: "M8 6.5h8A1.5 1.5 0 0 1 17.5 8v8a1.5 1.5 0 0 1-1.5 1.5H8A1.5 1.5 0 0 1 6.5 16V8A1.5 1.5 0 0 1 8 6.5z", sw: 1.8 },
    pin:      { d: "M12 3.5a5.5 5.5 0 0 1 5.5 5.5c0 4.2-5.5 11.5-5.5 11.5S6.5 13.2 6.5 9A5.5 5.5 0 0 1 12 3.5zM12 7.2a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6z", sw: 1.8 },
    tower:    { d: "M8 3.5h8A1.5 1.5 0 0 1 17.5 5v14a1.5 1.5 0 0 1-1.5 1.5H8A1.5 1.5 0 0 1 6.5 19V5A1.5 1.5 0 0 1 8 3.5zM9.5 7h5M9.5 10h5M12 16.5h.01", sw: 1.8 },
    tv:       { d: "M4.5 5.5h15a1.5 1.5 0 0 1 1.5 1.5v9a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 16V7a1.5 1.5 0 0 1 1.5-1.5zM8.5 20.5h7", sw: 1.8 },
    mini:     { d: "M5 9h14a1.5 1.5 0 0 1 1.5 1.5v4A1.5 1.5 0 0 1 19 16H5a1.5 1.5 0 0 1-1.5-1.5v-4A1.5 1.5 0 0 1 5 9zM7 12.5h.01M10 12.5h4", sw: 1.8 },

    // States.dc.html's `I` (the ones Main's does not have)
    tick:     { d: "M6.5 12.5l3.5 3.5 7.5-8", sw: 2 },
    spinner:  { d: "M12 4a8 8 0 1 0 8 8", sw: 2 },
    noWifi:   { d: "M4.5 9.5a11 11 0 0 1 15 0M7.5 12.8a6.5 6.5 0 0 1 9 0M12 16.6h.01M4 4l16 16", sw: 2 },
    laptop:   { d: "M5.5 6h13a1 1 0 0 1 1 1v8.5h-15V7a1 1 0 0 1 1-1zM3 18.5h18", sw: 1.8 },

    // Library.dc.html's `I` (menu items)
    bolt:     { d: "M13.2 3 5.8 13.2h5.6L10.6 21l7.6-10.4h-5.6z", sw: 1.8 },
    eyeSlash: { d: "M3 12s3.3-6 9-6c1.7 0 3.2.5 4.4 1.3M21 12s-3.3 6-9 6c-1.7 0-3.2-.5-4.4-1.3M9.9 9.9a3 3 0 0 0 4.2 4.2M4 4l16 16", sw: 1.8 },

    // Drawn inline in the boards
    carousel: { d: "M8.5 5h7A1.5 1.5 0 0 1 17 6.5v11a1.5 1.5 0 0 1-1.5 1.5h-7A1.5 1.5 0 0 1 7 17.5v-11A1.5 1.5 0 0 1 8.5 5zM3.5 8v8M20.5 8v8", sw: 1.8 },
    plus:     { d: "M12 5v14M5 12h14", sw: 2 },
    plusLg:   { d: "M12 4.5v15M4.5 12h15", sw: 2.2 },
    help:     { d: "M12 3a9 9 0 1 1 0 18 9 9 0 0 1 0-18zM9.6 9.4a2.5 2.5 0 0 1 4.8.9c0 1.7-2.4 2.2-2.4 3.7M12 17.1h.01", sw: 1.8 },
    settings: { d: "M12 8.8a3.2 3.2 0 1 1 0 6.4 3.2 3.2 0 0 1 0-6.4zM12 5.4a6.6 6.6 0 1 1 0 13.2 6.6 6.6 0 0 1 0-13.2zM12 2.8v2.6M12 18.6v2.6M21.2 12h-2.6M5.4 12H2.8M18.5 5.5l-1.8 1.8M7.3 16.7l-1.8 1.8M18.5 18.5l-1.8-1.8M7.3 7.3 5.5 5.5", sw: 1.8 },
    download: { d: "M12 4v11M7.5 10.5 12 15l4.5-4.5M5 19.5h14", sw: 1.8 },
    chevronLeft:  { d: "M14.5 5.5 8 12l6.5 6.5", sw: 2.2 },
    chevronRight: { d: "M9.5 5.5 16 12l-6.5 6.5", sw: 2.2 },
    search:   { d: "M10.5 4a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13zM15.3 15.3 20 20", sw: 2 },
    close:    { d: "M7 7l10 10M17 7 7 17", sw: 2.6 },
    copy:     { d: "M9.5 9h9a1.5 1.5 0 0 1 1.5 1.5v9a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 8 19.5v-9A1.5 1.5 0 0 1 9.5 9zM5 15.5V5.5A1.5 1.5 0 0 1 6.5 4h9", sw: 2.2 },
    more:     { d: "M6 12h.01M12 12h.01M18 12h.01", sw: 2.6 },
    menuCheck:{ d: "M5 12.5l4.2 4.2L19 7", sw: 2.4 },
    // The four-point star of the Add card (viewBox -7 -7 14 14, fill only)
    sparkle:  { d: "M0 -6.5 L1.6 -1.6 L6.5 0 L1.6 1.6 L0 6.5 L-1.6 1.6 L-6.5 0 L-1.6 -1.6 Z", sw: 0, fill: true, noStroke: true, vb: [-7, -7, 14, 14] }
}

// The entry for a name, or null
function get(name) {
    return Object.prototype.hasOwnProperty.call(icons, name) ? icons[name] : null
}

// All names
function names() {
    return Object.keys(icons)
}
