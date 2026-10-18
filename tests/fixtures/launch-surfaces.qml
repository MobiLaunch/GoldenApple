import QtQuick
import "../../shell" as Native
import "../../shell/ui/theme"

// The real launcher, without Weather, Maps, notifications, location
// services, or app content. Python supplies fixture-only services.
Item {
    objectName: "launchSurfacesFixture"
    function motion(reduced) { Theme.reduceMotion = reduced }
    Native.Applications { id: applications }
}
