import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../shell" as Native
import "../../shell/components" as Components

// Only Dock/AppLaunch are loaded; there is no full shell, Maps, network access,
// real compositor, or external application execution in this fixture.
Item {
    objectName: "dockLifecycleFixture"
    property alias dock: dock
    property alias launcher: launcher
    property int launches: 0
    Native.Dock { id: dock; objectName: "testDock"; launcher: launcher }
    Native.AppLaunch { id: launcher; objectName: "testLauncher"; dock: dock }
    function windows(ids) {
        ToplevelManager.toplevels.values = ids.map(id => ({
            appId: id, title: id, activate: () => {}, close: () => {}
        }))
    }
    function motion(reduced) { Components.Prefs.data = Object.assign({}, Components.Prefs.data, { reduceMotion: reduced }) }
    function pin(ids) { dock.pinned = ids }
    function launch() {
        launcher.launch({ id: "test.app", name: "Test", icon: "application-x-executable",
                            execute: () => { launches++ } }, Qt.rect(300, 700, 56, 56))
    }
    function fold() {
        launcher.fold({ id: "test.app", icon: "application-x-executable" },
                      Qt.rect(200, 100, 700, 500), Qt.rect(300, 700, 56, 56))
    }
    function closeDuringLaunch() {
        launcher.pendingAddress = "0x123"
        Hyprland.rawEvent({ name: "closewindow", parse: n => ["123"] })
    }
}
