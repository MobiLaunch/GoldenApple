// Add desktop entries to Golden Gate's real Dock pinned list.
// Uses the same Quickshell registry as Launchpad and the Dock, not a hardcoded
// app list, so newly installed Flatpaks are discoverable after their scan.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "apps"
    headerTint: "#487bd9"
    headerTitle: "Add to Dock"
    headerText: "Choose installed applications to keep in the Dock."
    property string filter: ""
    readonly property var pinned: Array.isArray(sys.prefs.dock?.pinned) ? sys.prefs.dock.pinned :
        ["org.goldengate.Files", "org.goldengate.Web", "org.goldengate.Mail",
         "org.goldengate.Messages", "org.goldengate.Maps", "org.goldengate.Photos",
         "org.goldengate.Music", "org.goldengate.Calendar", "org.goldengate.Notes",
         "org.goldengate.Weather", "org.goldengate.Software", "org.goldengate.Settings",
         "org.goldengate.Terminal"]
    readonly property var available: {
        const sources = DesktopEntries.applications.values
        const seen = new Set()
        const text = filter.trim().toLowerCase()
        return sources.filter((e) => {
            if (!e?.id || !e.name || e.noDisplay || e.hidden || pinned.includes(e.id)) return false
            if (seen.has(e.id)) return false
            seen.add(e.id)
            return !text || e.name.toLowerCase().includes(text) || e.id.toLowerCase().includes(text)
        }).sort((a, b) => String(a.name).localeCompare(String(b.name))).slice(0, 150)
    }
    Group {
        SetRow {
            title: "Find an application"
            TextField {
                id: search
                objectName: "settingsDockAppSearch"
                width: Math.min(230, pane.width * 0.5)
                search: true
                placeholder: "Search installed apps"
                onTextChanged: pane.filter = text
            }
        }
    }
    Group {
        title: "Available Applications"
        Repeater {
            model: pane.available
            delegate: SetRow {
                id: entryRow
                required property var modelData
                title: modelData.name
                subtitle: modelData.id
                image: Quickshell.iconPath(modelData.icon, true)
                Button {
                    text: "Add"
                    onClicked: {
                        pane.sys.setPref(["dock", "pinned"], pane.pinned.concat([entryRow.modelData.id]))
                        pane.nav.open("dock")
                    }
                }
            }
        }
        SetRow {
            visible: pane.available.length === 0
            title: pane.filter ? "No matching applications" : "All available applications are already in the Dock"
        }
    }
}
