// Finish Setting Up: what Setup Assistant put off (setup-deferred.json), each
// with a way to finish it now. An item goes from the list (and the list from
// the sidebar) only once it's actually done.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "gear"; headerTint: "#ff9f0a"; headerTitle: "Finish Setting Up"
    headerText: "These weren't finished when you set up this computer. Finish them here whenever you're ready."
    readonly property var items: sys.region.deferred ?? []
    property string working: ""            // the item being finished
    property var errors: ({})              // item → why it didn't finish

    Component.onCompleted: sys.refreshRegion()

    function failed(item, why) {
        const e = Object.assign({}, errors)
        e[item] = why
        errors = e
        working = ""
    }
    function succeeded(item) {
        const e = Object.assign({}, errors)
        delete e[item]
        errors = e
        working = ""
    }
    function finishItem(item) {
        if (working) return
        working = item
        const done = (ok, why) => ok ? succeeded(item) : failed(item, why || "It couldn't be finished.")
        if (item === "timezone") {
            const zone = sys.region.zone
            if (!zone) { working = ""; nav.open("datetime"); return }
            sys.setZone(zone, done)
        } else if (item === "formats") {
            const formats = sys.region.formats
            if (!formats) { working = ""; nav.open("language"); return }
            // The formats locale is generated (as an administrator), then used.
            sys.systemSetup({ formats: formats }, (ok, why) => {
                if (!ok) { failed(item, why || "Authorization was refused or isn't available."); return }
                sys.regionRun(["set-formats", formats], done)
            })
        } else if (item === "location") {
            const on = sys.privacy.location === true
            sys.run(["gsettings", "set", "org.gnome.system.location", "enabled", String(on)], (out, code) => {
                if (code !== 0) { failed(item, out.trim() || "Location Services couldn't be set."); return }
                sys.regionRun(["resolve", "location"], done)
            })
        } else {
            working = ""
        }
    }

    readonly property var about: ({
        timezone: { title: "Time zone", symbol: "clock", tint: "#0a84ff",
                    text: (zone) => zone ? "Set the time zone to " + zone.replace(/_/g, " ") + ". You'll be asked for an administrator's password."
                                         : "Choose your time zone in Date & Time." },
        formats: { title: "Region formats", symbol: "globe", tint: "#0a84ff",
                   text: () => "Prepare dates, numbers and currency for your region. You'll be asked for an administrator's password." },
        location: { title: "Location Services", symbol: "location", tint: "#0a84ff",
                    text: () => "Apply your Location Services choice (" + (sys.privacy.location === true ? "on" : "off") + ")." }
    })

    Group {
        visible: pane.items.length === 0
        SetRow {
            objectName: "finishSetupDone"
            title: "Everything is set up."
        }
    }

    Group {
        visible: pane.items.length > 0
        Repeater {
            model: pane.items
            delegate: SetRow {
                id: itemRow
                required property string modelData
                objectName: "finish-" + modelData
                readonly property var info: pane.about[modelData] ?? { title: modelData, symbol: "gear", tint: "#8e8e93", text: () => "" }
                title: info.title
                subtitle: pane.errors[modelData] ? pane.errors[modelData] : info.text(pane.sys.region.zone)
                symbol: info.symbol
                symbolTint: info.tint
                Button {
                    objectName: "finishButton-" + itemRow.modelData
                    text: pane.working === itemRow.modelData ? "Working…" : (pane.errors[itemRow.modelData] ? "Try Again" : "Finish")
                    enabled: !pane.working
                    prominent: true
                    onClicked: pane.finishItem(itemRow.modelData)
                }
            }
        }
    }
}
