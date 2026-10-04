pragma Singleton
import QtQuick
// The installed apps: Golden Gate's desktop files (from preview.py).
QtObject {
    readonly property QtObject applications: QtObject {
        readonly property var values: __preview.desktopEntries.map((e) => entry.createObject(null, e))
    }
    property Component entry: Component {
        QtObject {
            property string id; property string name; property string genericName; property string comment
            property string icon; property string execString; property var categories: []; property bool noDisplay
            property bool runInTerminal; property var command: []; property var actions: []; property var keywords: []
            function execute() { __preview.log("launch " + id) }
        }
    }
    function byId(id) { return applications.values.find((e) => e.id === id || e.id === id + ".desktop") ?? null }
    function heuristicLookup(name) {
        const n = String(name ?? "").toLowerCase()
        return applications.values.find((e) => e.id.toLowerCase() === n || e.id.toLowerCase().endsWith("." + n) || e.name.toLowerCase() === n) ?? null
    }
}
