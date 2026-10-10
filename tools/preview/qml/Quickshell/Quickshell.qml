pragma Singleton
import QtQuick
// Quickshell's global object. Environment, shell directory and icon lookup
// come from the harness (context properties set by preview.py).
QtObject {
    readonly property var screens: [PreviewDesktop.screen]
    readonly property string shellDir: __preview.shellDir
    readonly property string configDir: __preview.shellDir
    property string clipboardText: ""
    property bool watchFiles: false
    function env(name) { const v = __preview.env[name]; return v === undefined ? "" : v }
    function execDetached(cmd) { __preview.log("exec " + JSON.stringify(cmd)) }
    function iconPath(name, check) {
        const p = __preview.iconPath(String(name ?? ""))
        return p ? p : (check === true ? "" : (typeof check === "string" ? __preview.iconPath(check) : ""))
    }
    function reload(hard) {}
    function inhibitReloadPopup() {}
}
