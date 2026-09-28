// Date & Time: automatic time (NTP), the time zone and the 24-hour clock.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    property bool ntp: true
    property string zone: ""
    property var zones: []
    property bool h24: false
    Component.onCompleted: {
        sys.sh("timedatectl show -p NTP --value 2>/dev/null || echo; timedatectl show -p Timezone --value 2>/dev/null || readlink /etc/localtime | sed 's|.*zoneinfo/||'", (o) => { const l = o.split("\n"); ntp = l[0] === "yes"; zone = l[1] ?? "" })
        sys.sh("timedatectl list-timezones 2>/dev/null || awk '!/^#/ {print $3}' /usr/share/zoneinfo/zone1970.tab 2>/dev/null | sort -u", (o) => zones = o.split("\n").filter((z) => z.includes("/")))
        sys.run(["gsettings", "get", "org.gnome.desktop.interface", "clock-format"], (o) => h24 = o.includes("24h"))
    }
    Group {
        SetRow {
            title: "Set time and date automatically"
            subtitle: "Uses network time servers."
            Switch { checked: pane.ntp; onToggled: (on) => { pane.ntp = on; pane.sys.run(["timedatectl", "set-ntp", on ? "true" : "false"]) } }
        }
        SetRow {
            title: "Time zone"
            subtitle: new Date().toLocaleString(Qt.locale(), Locale.ShortFormat)
            PopUpButton {
                width: 130
                menuParent: pane.nav.overlay
                options: [...new Set(pane.zones.map((z) => z.split("/")[0]).concat([pane.zone.split("/")[0]]).filter((r) => r))].sort()
                current: Math.max(0, options.indexOf(pane.zone.split("/")[0]))
                onPicked: (i) => {
                    const first = pane.zones.find((z) => z.startsWith(options[i] + "/"))
                    if (first) { pane.zone = first; pane.sys.run(["timedatectl", "set-timezone", first]) }
                }
            }
        }
        SetRow {
            title: "Closest city"
            PopUpButton {
                width: 220
                menuParent: pane.nav.overlay
                readonly property var zoneList: {
                    const near = pane.zones.filter((z) => z.startsWith(pane.zone.split("/")[0] + "/"))
                    return near.includes(pane.zone) || !pane.zone ? near : [pane.zone].concat(near)
                }
                options: zoneList.map((z) => z.split("/").slice(1).join(" / ").replace(/_/g, " ") || z)
                current: Math.max(0, zoneList.indexOf(pane.zone))
                onPicked: (i) => { pane.zone = zoneList[i]; pane.sys.run(["timedatectl", "set-timezone", pane.zone]) }
            }
        }
        SetRow {
            title: "24-hour time"
            Switch { checked: pane.h24; onToggled: (on) => { pane.h24 = on; pane.sys.run(["gsettings", "set", "org.gnome.desktop.interface", "clock-format", on ? "24h" : "12h"]) } }
        }
    }
}
