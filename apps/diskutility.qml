//@ pragma AppId org.goldengate.DiskUtility
// CitronOS Disk Utility, as on the Mac: every disk and its volumes in the
// sidebar (Internal, External), and for the one chosen how full it is, what
// it is and where it's mounted, what's using the space, and First Aid, Erase,
// Mount / Unmount and Eject.
//
// apps/lib/disks/disks.py does the work (shared with Files): it reads the
// disks, and changes them only through udisks, which asks for a password
// when one is needed. Nothing that holds the running system can be erased,
// checked, unmounted or ejected; those buttons stay off for it.
// GG_DISKS_FIXTURE=<file.json> shows the disks in a file instead (tests).
import Quickshell
import Quickshell.Io
import QtQuick
import "lib"
import "lib/theme"

ShellRoot {
    AppWindow {
        id: win
        title: "Disk Utility"
        implicitWidth: Math.min(980, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(640, (Quickshell.screens[0]?.height ?? 900) - 130)
        minimumSize: Qt.size(760, 480)
        sidebarWidth: 230
        background: Theme.contentBg

        toolbarItems: [
            Column {
                x: win.contentX + 14
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: "Disk Utility"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Bold }
                }
                Text {
                    text: du.subject ? du.subject.name : ""
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(10) }
                }
            },
            Row {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 6
                component Action: Item {
                    id: action
                    property string symbol
                    property string label
                    property bool on: true
                    signal triggered()
                    width: Math.max(54, caption.implicitWidth + 12); height: 44
                    opacity: on ? 1 : 0.38
                    Accessible.role: Accessible.Button
                    Accessible.name: label
                    ToolbarButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 0
                        round: true
                        symbol: action.symbol
                        enabled: action.on && !du.busy
                        onClicked: action.triggered()
                    }
                    Text {
                        id: caption
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                        text: action.label
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(10) }
                    }
                }
                Action {
                    objectName: "duFirstAid"
                    symbol: "heart"; label: "First Aid"
                    on: !!du.volume && !du.volume.system && !!du.volume.fstype && !du.volume.swap
                    onTriggered: du.ask("firstaid")
                }
                Action {
                    objectName: "duErase"
                    symbol: "xmark-circle"; label: "Erase"
                    on: !!du.subject && !du.subject.system && (!!du.volume || du.subject.removable)
                    onTriggered: du.ask("erase")
                }
                Action {
                    objectName: "duMount"
                    symbol: "eject"; label: du.volume && du.volume.mounted ? "Unmount" : "Mount"
                    on: !!du.volume && !du.volume.system && !du.volume.swap && !!du.volume.fstype
                    onTriggered: du.run(du.volume.mounted ? "unmount" : "mount", [du.volume.device],
                                        (du.volume.mounted ? "Unmounting “" : "Mounting “") + du.volume.name + "”…")
                }
                Action {
                    objectName: "duEject"
                    symbol: "eject"; label: "Eject"
                    on: !!du.disk && du.disk.removable && !du.disk.system
                    onTriggered: du.run("eject", [du.disk.device], "Ejecting “" + du.disk.name + "”…")
                }
                Action {
                    symbol: "folder"; label: "Show in Files"
                    on: !!du.volume && du.volume.mounted && !!du.volume.mountpoint
                    onTriggered: Quickshell.execDetached(["gg-files", du.volume.mountpoint])
                }
            }
        ]

        // Internal and External, each disk with its volumes under it.
        sidebar: [
            Column {
                width: parent.width
                spacing: 2
                Repeater {
                    model: [{ title: "Internal", external: false }, { title: "External", external: true }]
                    delegate: Column {
                        id: section
                        required property var modelData
                        readonly property var disks: du.disks.filter((d) => d.removable === section.modelData.external)
                        width: parent.width
                        visible: disks.length > 0
                        spacing: 2
                        SidebarSection { text: section.modelData.title; topSpacing: section.modelData.external ? 14 : 4 }
                        Repeater {
                            model: section.disks
                            delegate: Column {
                                id: diskItem
                                required property var modelData
                                width: parent.width
                                spacing: 2
                                SidebarRow {
                                    objectName: "duDisk:" + diskItem.modelData.name
                                    width: parent.width
                                    text: diskItem.modelData.name
                                    symbol: "drive"
                                    selected: du.selected === du.diskKey(diskItem.modelData)
                                    onClicked: du.selected = du.diskKey(diskItem.modelData)
                                }
                                Repeater {
                                    model: diskItem.modelData.volumes
                                    delegate: SidebarRow {
                                        required property var modelData
                                        objectName: "duVolume:" + modelData.name
                                        width: parent.width
                                        indent: 16
                                        text: modelData.name
                                        symbol: "drive"
                                        symbolTone: "gray"
                                        opacity: modelData.mounted ? 1 : 0.6
                                        selected: du.selected === du.volumeKey(modelData)
                                        onClicked: du.selected = du.volumeKey(modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        ]

        Item {
            id: du
            anchors.fill: parent

            readonly property string helper: Qt.resolvedUrl("lib/disks/disks.py").toString().replace("file://", "")
            property var disks: []
            property string selected: ""            // diskKey() or volumeKey()
            // By device, which stays put when a volume is mounted or unmounted
            // (the live system's / has none: by its mount point).
            function diskKey(d) { return "disk:" + (d.device || d.name) }
            function volumeKey(v) { return "volume:" + (v.device || v.mountpoint) }
            property bool busy: false
            property string busyText: ""
            property string message: ""             // the last action's outcome
            property bool messageBad: false
            property var largest: null              // what's using the space, for the chosen volume
            property string sheet: ""               // "" | "erase" | "firstaid"

            // What's chosen: a volume (and its disk), or a disk alone.
            readonly property var choice: {
                for (const d of disks) {
                    if (selected === diskKey(d)) return { disk: d, volume: null }
                    for (const v of d.volumes)
                        if (selected === volumeKey(v)) return { disk: d, volume: v }
                }
                return { disk: null, volume: null }
            }
            readonly property var disk: choice.disk
            readonly property var volume: choice.volume
            readonly property var subject: volume || disk
            onSelectedChanged: { largest = null; message = "" }

            // First the system's volume, as Disk Utility opens on Macintosh HD.
            onDisksChanged: {
                if (choice?.disk) return
                for (const d of disks) for (const v of d.volumes)
                    if (v.mountpoint === "/") { selected = volumeKey(v); return }
                if (disks.length) selected = diskKey(disks[0])
            }

            function formatSize(bytes) {
                const units = ["bytes", "KB", "MB", "GB", "TB", "PB"]
                let n = Math.max(0, bytes || 0), i = 0
                while (n >= 1000 && i < units.length - 1) { n /= 1000; i++ }
                return i === 0 ? n + " bytes" : (i === 1 || n >= 100 ? Math.round(n) : n.toFixed(1).replace(/\.0$/, "")) + " " + units[i]
            }
            function kindOf(v, d) {
                if (!d) return ""
                const where = d.removable ? "External" : "Internal"
                const conn = { usb: "USB", nvme: "PCI-Express", sata: "SATA", mmc: "SD Card", virtio: "Virtual" }[d.transport] ?? ""
                return (conn ? conn + " " : "") + where + (v ? " Volume" : " Physical Disk") + (v && v.format ? " • " + v.format : "")
            }

            function refresh() { if (!snap.running) snap.running = true }
            function run(action, args, text) {
                if (busy) return
                busy = true
                busyText = text
                message = ""
                op.action = action
                op.command = ["python3", helper, action].concat(args)
                op.running = true
            }
            function ask(kind) {
                sheet = kind
                if (kind === "erase") {
                    eraseName.text = (volume ? volume.label || volume.name : "Untitled").slice(0, 15)
                    eraseFormat.current = Math.max(0, formats.indexOf(volume && formats.includes(volume.fstype) ? volume.fstype
                                                   : subject && subject.removable ? "exfat" : "ext4"))
                    Qt.callLater(() => eraseName.input.forceActiveFocus())
                }
            }
            readonly property var formats: ["exfat", "vfat", "ext4", "btrfs", "ntfs"]
            readonly property var formatNames: ["ExFAT", "MS-DOS (FAT)", "Linux (ext4)", "Btrfs", "Windows NT (NTFS)"]
            readonly property var formatNotes: [
                "Works with Mac, Windows and Linux, and files over 4 GB. For USB drives and memory cards.",
                "Works almost everywhere, but no file can be over 4 GB. Names are capitals, up to 11 letters.",
                "Linux's own: fast and dependable, but Mac and Windows can't read it.",
                "Linux, with snapshots and checksums.",
                "Windows' own; Mac can read it but not write to it."]

            Process {
                id: snap
                running: true
                command: ["python3", du.helper, "snapshot"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) du.disks = r.disks
                            else { du.message = r.error; du.messageBad = true }
                        } catch (e) {}
                    }
                }
            }
            // Drives plugged in or out, volumes mounted or unmounted elsewhere.
            Process {
                id: watch
                running: true
                command: ["sh", "-c", "command -v udevadm >/dev/null || command -v findmnt >/dev/null || exit 3; "
                    + "{ command -v udevadm >/dev/null && stdbuf -oL udevadm monitor --udev --subsystem-match=block & } ; "
                    + "{ command -v findmnt >/dev/null && stdbuf -oL findmnt --poll -o ACTION,TARGET & } ; wait"]
                stdout: SplitParser { onRead: settle.restart() }
                onExited: fallback.start()
            }
            Timer { id: settle; interval: 600; onTriggered: du.refresh() }
            Timer { id: fallback; interval: 15000; onTriggered: { du.refresh(); watch.running = true } }

            Process {
                id: op
                property string action: ""
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) {}
                        du.messageBad = !r || !r.ok
                        if (!r || !r.ok) du.message = r?.error ?? "Disk Utility couldn't finish that."
                        else if (op.action === "check")
                            du.message = r.healthy ? "First Aid found no problems." : "First Aid found problems. Choose Run First Aid again to repair them."
                        else if (op.action === "repair") du.message = "First Aid repaired the volume."
                        else if (op.action === "erase") du.message = "Erased."
                        else if (op.action === "eject") du.message = "It can be unplugged now."
                        else if (op.action === "mount") du.message = "Mounted at " + (r.mountpoint || "its folder") + "."
                        else if (op.action === "unmount") du.message = "Unmounted."
                        else if (op.action === "largest") du.largest = r
                    }
                }
                onExited: { du.busy = false; du.refresh() }
            }

            // ------------------------------------------------------- the pane
            Flickable {
                anchors.fill: parent
                contentHeight: pane.implicitHeight + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: !!du.subject

                Column {
                    id: pane
                    x: 24; y: 18
                    width: parent.width - 48
                    spacing: 16

                    // Its icon, name and what it is.
                    Row {
                        spacing: 14
                        Image {
                            width: 56; height: 56
                            source: Quickshell.iconPath("drive-harddisk", "drive-harddisk")
                            sourceSize: Qt.size(112, 112)
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Text {
                                objectName: "duTitle"
                                text: du.subject ? du.subject.name : ""
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: Theme.fs(20); weight: Font.DemiBold }
                            }
                            Text {
                                text: du.subject ? du.kindOf(du.volume, du.disk) : ""
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            }
                        }
                    }

                    // How full it is, as Disk Utility's bar.
                    Column {
                        visible: !!du.volume && du.volume.mounted && du.volume.size > 0
                        width: parent.width
                        spacing: 8
                        readonly property real usedShare: du.volume && du.volume.size > 0 ? Math.min(1, du.volume.used / du.volume.size) : 0
                        Rectangle {
                            objectName: "duUsage"
                            width: parent.width; height: 22; radius: 6
                            color: Theme.dark ? "#26ffffff" : "#12000000"
                            clip: true
                            Rectangle {
                                width: parent.width * parent.parent.usedShare
                                height: parent.height
                                radius: 6
                                color: Theme.accent
                                Behavior on width { enabled: !Theme.reduceMotion; Spring { spring: Theme.smooth } }
                            }
                        }
                        Row {
                            spacing: 22
                            component Legend: Row {
                                property color swatch
                                property string title
                                property string amount
                                spacing: 6
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 3; color: parent.swatch }
                                Text { text: parent.title; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Medium } }
                                Text { text: parent.amount; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(12) } }
                            }
                            Legend { swatch: Theme.accent; title: "Used"; amount: du.volume ? du.formatSize(du.volume.used) : "" }
                            Legend { swatch: Theme.dark ? "#40ffffff" : "#26000000"; title: "Free"; amount: du.volume ? du.formatSize(du.volume.free) : "" }
                        }
                    }

                    // The facts, in two columns.
                    Rectangle {
                        width: parent.width
                        height: facts.implicitHeight + 16
                        radius: 10
                        color: Theme.dark ? "#0dffffff" : "#08000000"
                        border { width: 0.5; color: Theme.separator }
                        Grid {
                            id: facts
                            objectName: "duFacts"
                            x: 14; y: 8
                            width: parent.width - 28
                            columns: 2
                            columnSpacing: 24
                            rowSpacing: 2
                            readonly property var rows: {
                                const v = du.volume, d = du.disk
                                if (!d) return []
                                if (!v) return [
                                    ["Capacity", du.formatSize(d.size)], ["Connection", ({ usb: "USB", nvme: "PCI-Express (NVMe)", sata: "SATA", mmc: "SD Card", virtio: "Virtual" })[d.transport] ?? "—"],
                                    ["Volumes", String(d.volumes.length)], ["Device", d.device || "—"],
                                    ["Model", d.model || "—"], ["Removable", d.removable ? "Yes" : "No"]]
                                return [
                                    ["Mount Point", v.mounted ? (v.mountpoint || "—") : "Not Mounted"], ["Capacity", du.formatSize(v.capacity || v.size)],
                                    ["Type", v.format || "—"], ["Available", v.mounted ? du.formatSize(v.free) : "—"],
                                    ["Device", v.device || "—"], ["Used", v.mounted ? du.formatSize(v.used) : "—"],
                                    ["Disk", d.name], ["Name", v.label || "—"]]
                            }
                            Repeater {
                                model: facts.rows
                                delegate: Row {
                                    required property var modelData
                                    width: (facts.width - facts.columnSpacing) / 2
                                    height: 26
                                    Text {
                                        width: parent.width * 0.42
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData[0] + ":"
                                        color: Theme.secondaryLabel
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                                    }
                                    Text {
                                        width: parent.width * 0.58
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData[1]
                                        elide: Text.ElideMiddle
                                        color: Theme.label
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                                    }
                                }
                            }
                        }
                    }

                    // Where things stand: the last action, or one in progress.
                    Row {
                        visible: du.busy || !!du.message
                        spacing: 10
                        ProgressBar { visible: du.busy; indeterminate: true; width: 120; anchors.verticalCenter: parent.verticalCenter }
                        Symbol {
                            visible: !du.busy
                            anchors.verticalCenter: parent.verticalCenter
                            name: du.messageBad ? "warning" : "checkmark"; size: 14
                            tone: du.messageBad ? "red" : "accent"
                        }
                        Text {
                            objectName: "duMessage"
                            anchors.verticalCenter: parent.verticalCenter
                            text: du.busy ? du.busyText : du.message
                            color: Theme.label
                            wrapMode: Text.Wrap
                            width: Math.min(560, pane.width - 160)
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                        }
                    }

                    // What's using the space: the biggest folders at the top of the volume.
                    Column {
                        visible: !!du.volume && du.volume.mounted && !!du.volume.mountpoint
                        width: parent.width
                        spacing: 8
                        Row {
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "What’s Using Space"
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: Theme.fs(14); weight: Font.DemiBold }
                            }
                            Button {
                                objectName: "duMeasure"
                                text: du.largest ? "Measure Again" : "Measure"
                                enabled: !du.busy
                                onClicked: du.run("largest", [du.volume.mountpoint], "Measuring the folders on “" + du.volume.name + "”…")
                            }
                        }
                        Text {
                            visible: !du.largest
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: "See which folders at the top of this volume take the most room. Folders you can't open aren't counted."
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                        }
                        Repeater {
                            model: du.largest ? du.largest.items : []
                            delegate: Item {
                                id: big
                                required property var modelData
                                width: pane.width
                                height: 30
                                readonly property real share: du.largest && du.largest.items.length ? modelData.size / du.largest.items[0].size : 0
                                Rectangle {
                                    anchors.fill: parent; radius: 7
                                    color: bigArea.containsMouse ? (Theme.dark ? "#0fffffff" : "#08000000") : "transparent"
                                }
                                Symbol { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "folder"; size: 15; tone: "accent" }
                                Text {
                                    x: 32; width: parent.width * 0.38
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: big.modelData.name
                                    elide: Text.ElideRight
                                    color: Theme.label
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                                }
                                Rectangle {
                                    x: parent.width * 0.42
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(3, parent.width * 0.42 * big.share); height: 6; radius: 3
                                    color: Theme.accent
                                    opacity: 0.75
                                }
                                Text {
                                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                    text: du.formatSize(big.modelData.size)
                                    color: Theme.secondaryLabel
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                                }
                                MouseArea {
                                    id: bigArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: Quickshell.execDetached(["gg-files", big.modelData.path])
                                }
                            }
                        }
                    }
                }
            }

            EmptyState {
                visible: !du.subject
                anchors.centerIn: parent
                width: Math.min(420, parent.width - 40)
                height: 220
                symbol: "drive"
                title: du.disks.length ? "Choose a Disk" : "Looking for Disks…"
                text: du.disks.length ? "Pick a disk or a volume in the sidebar." : ""
            }

            // ------------------------------------------------------- sheets
            Rectangle {
                parent: win.overlay
                anchors.fill: parent
                visible: du.sheet !== ""
                color: "#26000000"
                MouseArea { anchors.fill: parent }
            }

            // Erase: a name and a format, and what it means.
            Glass {
                objectName: "duEraseSheet"
                parent: win.overlay
                visible: du.sheet === "erase"
                anchors.centerIn: parent
                width: 440
                height: eraseColumn.implicitHeight + 40
                role: "regular"
                radius: 22
                z: 110
                Keys.onEscapePressed: du.sheet = ""
                Column {
                    id: eraseColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                    spacing: 12
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: "Erase “" + (du.subject ? du.subject.name : "") + "”?"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.Bold }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: du.volume ? "Erasing deletes everything on this volume. Enter a name, choose a format, and click Erase."
                              : "Erasing deletes everything on this disk and makes it one volume. Enter a name, choose a format, and click Erase."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    Grid {
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 10
                        verticalItemAlignment: Grid.AlignVCenter
                        Text { text: "Name:"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(12) } }
                        TextField { id: eraseName; objectName: "duEraseName"; width: 260; placeholder: "Untitled" }
                        Text { text: "Format:"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(12) } }
                        PopUpButton {
                            id: eraseFormat
                            objectName: "duEraseFormat"
                            width: 260
                            menuParent: win.overlay
                            options: du.formatNames
                        }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: du.formatNotes[eraseFormat.current] ?? ""
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Button { text: "Cancel"; onClicked: du.sheet = "" }
                        Button {
                            objectName: "duEraseConfirm"
                            text: "Erase"
                            prominent: true
                            destructive: true
                            enabled: eraseName.text.trim().length > 0
                            onClicked: {
                                const target = du.subject
                                du.sheet = ""
                                du.run("erase", [target.device, du.formats[eraseFormat.current], eraseName.text.trim()],
                                       "Erasing “" + target.name + "”…")
                            }
                        }
                    }
                }
            }

            // First Aid: check, and repair what the check finds.
            Glass {
                objectName: "duFirstAidSheet"
                parent: win.overlay
                visible: du.sheet === "firstaid"
                anchors.centerIn: parent
                width: 400
                height: aidColumn.implicitHeight + 40
                role: "regular"
                radius: 22
                z: 110
                Column {
                    id: aidColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                    spacing: 12
                    Symbol { anchors.horizontalCenter: parent.horizontalCenter; name: "heart"; size: 32; tone: "accent" }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: "Run First Aid on “" + (du.volume ? du.volume.name : "") + "”?"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(14); weight: Font.Bold }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: du.volume && du.volume.mounted
                            ? "First Aid checks a volume that isn't in use. It will be unmounted while it's checked."
                            : "First Aid checks the volume for errors. Repair fixes what it finds."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Button { text: "Cancel"; onClicked: du.sheet = "" }
                        Button {
                            text: "Repair"
                            onClicked: { du.sheet = ""; du.firstAid("repair") }
                        }
                        Button {
                            objectName: "duFirstAidRun"
                            text: "Run"
                            prominent: true
                            onClicked: { du.sheet = ""; du.firstAid("check") }
                        }
                    }
                }
            }
            // A mounted volume is unmounted first, then checked.
            function firstAid(kind) {
                const v = volume
                if (!v) return
                if (v.mounted) {
                    pendingAid = kind
                    run("unmount", [v.device], "Unmounting “" + v.name + "” to check it…")
                } else run(kind, [v.device], (kind === "repair" ? "Repairing “" : "Checking “") + v.name + "”…")
            }
            property string pendingAid: ""
            Connections {
                target: op
                function onExited() {
                    if (!du.pendingAid || du.messageBad) { du.pendingAid = ""; return }
                    const kind = du.pendingAid
                    du.pendingAid = ""
                    Qt.callLater(() => { if (du.volume) du.run(kind, [du.volume.device], (kind === "repair" ? "Repairing “" : "Checking “") + du.volume.name + "”…") })
                }
            }
        }
    }
}
