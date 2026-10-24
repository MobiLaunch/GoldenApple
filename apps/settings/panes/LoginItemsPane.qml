// XDG Autostart login items: app .desktop files, per-user override precedence.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "apps"
    headerTint: "#8e8e93"
    headerTitle: "Login Items"
    headerText: "Choose the applications that open automatically when you sign in."
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("../app-preferences.py").toString().replace("file://", ""))
    property var items: []
    property var installed: []
    property bool showAdd: false
    property string query: ""
    property bool busy: false
    property string error: ""
    readonly property var addable: {
        const known = new Set(items.filter((x) => x.enabled).map((x) => x.id))
        const q = query.trim().toLowerCase()
        return installed.filter((x) => !known.has(x.id) && (!q || x.name.toLowerCase().includes(q))).slice(0, 75)
    }
    function refresh() {
        sys.run(["python3", helper, "login-items"], (out, code) => {
            try {
                const r = JSON.parse(out)
                if (r.ok && code === 0) { items = r.rows ?? []; error = "" }
                else error = r.error || "Could not read login items."
            } catch (e) { error = "Could not read login items." }
        })
        sys.run(["python3", helper, "available"], (out, code) => {
            try { const r = JSON.parse(out); if (r.ok && code === 0) installed = r.rows ?? [] } catch (e) {}
        })
    }
    function setLogin(id, value) {
        if (busy) return
        busy = true
        sys.run(["python3", helper, "toggle-login", id, String(value)], (out, code) => {
            busy = false
            try {
                const r = JSON.parse(out)
                if (!r.ok || code !== 0) { error = r.error || "Login item could not be saved."; return }
                items = r.rows ?? []
                error = ""
            } catch (e) { error = "Login item could not be verified." }
        })
    }
    Component.onCompleted: refresh()
    Group {
        title: "Open at Login"
        Repeater {
            model: pane.items
            delegate: SetRow {
                id: loginRow
                required property var modelData
                title: modelData.name
                subtitle: modelData.source === "System" ? "Installed by the system" : "Your login item"
                Switch {
                    enabled: !pane.busy
                    checked: loginRow.modelData.enabled
                    onToggled: (on) => pane.setLogin(loginRow.modelData.id, on)
                }
            }
        }
        SetRow {
            title: "Add a Login Item"
            subtitle: "Apps added here open automatically on your next sign-in."
            Button { text: pane.showAdd ? "Done" : "Add…"; onClicked: pane.showAdd = !pane.showAdd }
        }
    }
    Group {
        visible: pane.showAdd
        title: "Installed Applications"
        SetRow {
            title: "Find an app"
            TextField {
                width: 210
                search: true
                placeholder: "Search installed apps"
                onTextChanged: pane.query = text
            }
        }
        Repeater {
            model: pane.addable
            delegate: SetRow {
                id: candidate
                required property var modelData
                title: modelData.name
                Button { text: "Add"; enabled: !pane.busy; onClicked: pane.setLogin(candidate.modelData.id, true) }
            }
        }
    }
    Group {
        visible: !!pane.error
        SetRow { title: "Unable to apply"; subtitle: pane.error; Button { text: "Try Again"; onClicked: pane.refresh() } }
    }
}