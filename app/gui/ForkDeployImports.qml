// [fork] Never loaded. macdeployqt bundles only the QML modules imported by files in app/gui,
// and the macOS style is chosen at runtime (main.cpp) rather than imported, so this import
// makes sure the native macOS style plugin ships in LuzLunar.app.
import QtQuick
import QtQuick.Controls.macOS

Item {
}
