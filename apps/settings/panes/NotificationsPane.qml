// Notifications, as in macOS: previews and sounds for all, and each app's
// choices. The apps listed are the ones that have notified (the shell keeps
// them in ~/.local/state/golden-gate/notifiers.json) and CitronOS's own that
// do. The shell reads desktop.json's "notifications" at once.
import Quickshell
import Quickshell.Io
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."
import "../../lib/FocusPolicy.js" as FocusPolicy

Pane {
    id: pane
    headerSymbol: "bell"; headerTint: "#ff3b30"; headerTitle: "Notifications"
    headerText: "Choose which apps can notify you, and how. Focus silences interruptions except the apps and critical alerts you allow."
    readonly property var prefs: sys.prefs.notifications ?? {}
    readonly property var appPrefs: prefs.apps ?? {}
    property var seen: ({})
    property string selected: ""

    // CitronOS's own apps that notify, listed before they first have.
    readonly property var builtIn: ({
        "org.goldengate.messages": { name: "Messages", icon: "org.goldengate.Messages" },
        "org.goldengate.mail": { name: "Mail", icon: "org.goldengate.Mail" },
        "org.goldengate.calendar": { name: "Calendar", icon: "org.goldengate.Calendar" },
        "org.goldengate.clock": { name: "Clock", icon: "org.goldengate.Clock" },
        "org.goldengate.software": { name: "App Store", icon: "org.goldengate.Software" },
        "org.goldengate.airdrop": { name: "AirDrop", icon: "org.goldengate.AirDrop" }
    })
    readonly property var apps: {
        const all = Object.assign({}, builtIn, seen)
        const canonical = {}
        for (const key in all) canonical[FocusPolicy.canonicalApp(key)] = all[key]
        return Object.keys(canonical).map((k) => ({ key: k, name: canonical[k].name || k, icon: canonical[k].icon || "" }))
            .sort((a, b) => a.name.localeCompare(b.name))
    }
    function choice(key) {
        return Object.assign({ allow: true, banners: true, sound: true, badges: true }, FocusPolicy.appChoice(appPrefs, key))
    }
    function setApp(key, field, value) {
        const all = JSON.parse(JSON.stringify(appPrefs))
        all[key] = Object.assign(choice(key), { [field]: value })
        sys.setPref(["notifications", "apps"], all)
    }
    function summary(key) {
        const c = choice(key)
        if (!c.allow) return "Off"
        const parts = [c.banners ? "Banners" : "", c.sound ? "Sounds" : "", c.badges ? "Badges" : ""].filter((s) => s)
        return parts.length ? parts.join(", ") : "In Notification Center only"
    }

    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/golden-gate/notifiers.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { pane.seen = JSON.parse(text()) } catch (e) { pane.seen = ({}) } }
    }

    Group {
        title: "Notification Center"
        SetRow {
            title: "Show previews"
            subtitle: "Off, a notification shows its app's name only."
            PopUpButton {
                menuParent: pane.nav.overlay
                options: ["Always", "Never"]
                current: (pane.prefs.previews ?? "always") === "never" ? 1 : 0
                onPicked: (i) => pane.sys.setPref(["notifications", "previews"], i === 1 ? "never" : "always")
            }
        }
        SetRow {
            title: "Play sound for notifications"
            Switch { checked: pane.prefs.sounds ?? true; onToggled: (on) => pane.sys.setPref(["notifications", "sounds"], on) }
        }
    }
    Group {
        title: "Application Notifications"
        Repeater {
            model: pane.apps
            delegate: SetRow {
                required property var modelData
                title: modelData.name
                subtitle: pane.summary(modelData.key)
                image: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""
                symbol: "bell"; symbolTint: "#ff3b30"
                chevron: true
                onClicked: pane.selected = pane.selected === modelData.key ? "" : modelData.key
            }
        }
    }
    Group {
        id: detail
        visible: !!pane.selected
        readonly property var app: pane.apps.find((a) => a.key === pane.selected) ?? { key: "", name: "" }
        readonly property var c: pane.choice(pane.selected)
        title: app.name
        SetRow {
            title: "Allow notifications"
            Switch { checked: detail.c.allow; onToggled: (on) => pane.setApp(pane.selected, "allow", on) }
        }
        SetRow {
            title: "Show banners"
            subtitle: "Off, they go straight to Notification Center."
            Switch { enabled: detail.c.allow; checked: detail.c.banners; onToggled: (on) => pane.setApp(pane.selected, "banners", on) }
        }
        SetRow {
            title: "Play sound for notifications"
            Switch { enabled: detail.c.allow; checked: detail.c.sound; onToggled: (on) => pane.setApp(pane.selected, "sound", on) }
        }
        SetRow {
            title: "Badge application icon"
            Switch { enabled: detail.c.allow; checked: detail.c.badges; onToggled: (on) => pane.setApp(pane.selected, "badges", on) }
        }
    }
}
