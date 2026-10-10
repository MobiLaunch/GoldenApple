import QtQuick
import "../../shell" as Native
import "../../shell/ui/theme"

// The real launcher and live chrome, without Weather, Maps, notifications,
// location services, or app content. Python supplies fixture-only services.
Item {
    objectName: "launchSurfacesFixture"
    function motion(reduced) { Theme.reduceMotion = reduced }
    QtObject { id: controls; property bool open: false; function toggle() { open = !open } }
    Native.Applications { id: applications; dock: dock }
    Native.Dock { id: dock; objectName: "launchpadDock"; applications: applications; launcher: launcher }
    Native.AppLaunch { id: launcher; dock: dock }
    Native.MenuBar { applications: applications; controlCenter: controls }
}
