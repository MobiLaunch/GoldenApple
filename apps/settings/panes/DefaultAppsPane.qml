// Real default handlers from xdg-mime, not decorative switches.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "apps"
    headerTint: "#6a84d3"
    headerTitle: "Default Applications"
    headerText: "Choose the applications that open web links, mail, documents, media and archives."
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("../app-preferences.py").toString().replace("file://", ""))
    property var rows: []
    property string error: ""
    property bool busy: false
    function refresh() {
        sys.run(["python3", helper, "defaults"], (output, code) => {
            try {
                const r = JSON.parse(output)
                if (!r.ok || code !== 0) { error = r.error || "Could not read app defaults."; return }
                rows = r.rows ?? []
                error = ""
            } catch (e) { error = "Could not read app defaults." }
        })
    }
    function choose(mime, appId) {
        if (busy) return
        busy = true
        sys.run(["python3", helper, "set-default", mime, appId], (output, code) => {
            busy = false
            try {
                const r = JSON.parse(output)
                if (!r.ok || code !== 0) { error = r.error || "Could not change the default app."; return }
                rows = r.rows ?? []
                error = ""
            } catch (e) { error = "Could not verify the new default app." }
        })
    }
    Component.onCompleted: refresh()

    Group {
        title: "Open Files & Links With"
        Repeater {
            model: pane.rows
            delegate: SetRow {
                id: entry
                required property var modelData
                title: entry.modelData.title
                subtitle: entry.modelData.current ? "Default: " + entry.modelData.current.replace(".desktop", "") : "No default selected"
                PopUpButton {
                    menuParent: pane.nav.overlay
                    enabled: !pane.busy && entry.modelData.choices.length > 0
                    options: entry.modelData.choices.map((v) => v.name)
                    current: Math.max(0, entry.modelData.choices.findIndex((v) => v.id === entry.modelData.current))
                    onPicked: (i) => pane.choose(entry.modelData.mime, entry.modelData.choices[i].id)
                }
            }
        }
        SetRow {
            visible: !pane.rows.length && !pane.error
            title: "Loading installed applications…"
        }
    }
    Group {
        visible: !!pane.error
        SetRow {
            title: "Unable to apply"
            subtitle: pane.error
            Button { text: "Try Again"; onClicked: pane.refresh() }
        }
    }
}