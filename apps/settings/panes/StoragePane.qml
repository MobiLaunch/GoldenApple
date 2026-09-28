// Storage: how full each disk is, with the Mac's coloured bar.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    property var disks: []        // {mount, size, used, avail, pct}
    Component.onCompleted: sys.sh("df -B1 --output=target,size,used,avail -x tmpfs -x devtmpfs -x overlay -x squashfs -x efivarfs 2>/dev/null | tail -n +2", (o) => {
        disks = o.split("\n").filter((l) => l.trim()).map((l) => { const f = l.trim().split(/\s+/); return { mount: f[0], size: +f[1], used: +f[2], avail: +f[3] } })
            .filter((d) => d.size > 1e9)
    })
    function gb(b) { return b >= 1e12 ? (b / 1e12).toFixed(2) + " TB" : (b / 1e9).toFixed(1) + " GB" }
    Repeater {
        model: pane.disks
        delegate: Group {
            required property var modelData
            title: modelData.mount === "/" ? "Golden Gate HD" : modelData.mount
            SetRow {
                title: pane.gb(modelData.used) + " of " + pane.gb(modelData.size) + " used"
                subtitle: pane.gb(modelData.avail) + " available"
                Rectangle {
                    width: 260; height: 14; radius: 4
                    color: Theme.dark ? "#26ffffff" : "#14000000"
                    Rectangle {
                        width: parent.width * modelData.used / Math.max(1, modelData.size); height: parent.height; radius: 4
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#ff9f0a" }
                            GradientStop { position: 0.5; color: "#ff375f" }
                            GradientStop { position: 1; color: "#bf5af2" }
                        }
                    }
                }
            }
        }
    }
}
