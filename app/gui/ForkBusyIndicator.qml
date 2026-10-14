import QtQuick
import QtQuick.Controls

// [fork] The native macOS style's BusyIndicator takes its size from its animated WebP (needs the
// qtimageformats plugin) and is 0x0 without it. A fixed size keeps spinners and the labels sized
// from them visible either way; 28 stays close to the 20 pt artwork, so it doesn't blur.
BusyIndicator {
    implicitWidth: 28
    implicitHeight: 28
}
