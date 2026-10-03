// Settings ▸ Key Bindings: every command and its keys. Click a shortcut and
// type a new one; Delete removes it, Escape cancels. A shortcut another
// command was using moves to this one.
import QtQuick
import "../../lib"
import "../../lib/theme"
import "../commands.js" as Commands

Item {
    id: page
    property var app
    property var backend
    property Item overlay: null
    property string recording: ""          // the command waiting for keys
    property string note: ""
    readonly property var overrides: app.settings.keyBindings || ({})
    readonly property string query: search.text.trim().toLowerCase()
    readonly property var rows: {
        const out = []
        for (const m of Commands.MENUS) {
            const cmds = Commands.COMMANDS.filter((c) => c.menu === m && (!query || c.title.toLowerCase().includes(query)
                || Commands.keysFor(c.id, overrides).some((k) => Commands.display(k).toLowerCase().includes(query))))
            if (cmds.length) out.push({ header: m })
            for (const c of cmds) out.push(c)
        }
        return out
    }

    function record(id) { recording = id; note = ""; catcher.forceActiveFocus() }
    function finish(seq) {
        const id = recording
        recording = ""
        if (seq === null) return
        const taken = seq ? Commands.conflicts(seq, id, overrides) : []
        note = taken.length ? Commands.display(seq) + " was used by “" + taken.map((c) => c.title).join("”, “") + "”; it's now “" + Commands.byId(id).title + "”." : ""
        app.saveSettings({ keyBindings: Commands.bind(id, seq, overrides) })
    }

    // Takes the keys while recording.
    Item {
        id: catcher
        focus: page.recording !== ""
        Keys.onPressed: (event) => {
            event.accepted = true
            if (!event.modifiers && event.key === Qt.Key_Escape) { page.finish(null); return }
            if (!event.modifiers && (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete)) { page.finish(""); return }
            const seq = Commands.sequenceFor(event.key, event.modifiers, event.text)
            if (seq) page.finish(seq)
        }
        onActiveFocusChanged: if (!activeFocus && page.recording) page.recording = ""
    }

    TextField {
        id: search
        x: 24; y: 20
        width: 260
        height: 28
        search: true
        placeholder: "Search commands or keys"
    }
    Button {
        anchors { right: parent.right; rightMargin: 24 }
        y: 21
        text: "Restore Defaults"
        enabled: Object.keys(page.overrides).length > 0
        onClicked: { page.note = ""; page.app.saveSettings({ keyBindings: {} }) }
    }
    Text {
        id: noteText
        x: 24
        y: search.y + search.height + 8
        width: parent.width - 48
        visible: !!page.note
        wrapMode: Text.Wrap
        text: page.note
        color: "#ff9f0a"
        font { family: Theme.fontUi; pixelSize: 12 }
    }
    Rectangle {
        x: 24
        y: noteText.y + (page.note ? noteText.implicitHeight + 8 : 0)
        width: parent.width - 48
        height: parent.height - y - 20
        radius: 10
        color: Theme.dark ? "#10ffffff" : "#06000000"
        border { width: 1; color: Theme.separator }
        ListView {
            id: list
            anchors { fill: parent; margins: 6 }
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: page.rows
            delegate: Item {
                id: cmdRow
                required property var modelData
                required property int index
                readonly property bool isHeader: !!modelData.header
                readonly property var keys: isHeader ? [] : Commands.keysFor(modelData.id, page.overrides)
                readonly property bool customized: !isHeader && Commands.isCustomized(modelData.id, page.overrides)
                width: list.width
                height: isHeader ? 30 : 30
                SidebarSection {
                    visible: cmdRow.isHeader
                    text: cmdRow.modelData.header || ""
                    topSpacing: 10
                }
                Rectangle {
                    visible: !cmdRow.isHeader
                    anchors.fill: parent
                    radius: 6
                    color: cmdRow.index % 2 ? (Theme.dark ? "#08ffffff" : "#05000000") : "transparent"
                }
                Text {
                    visible: !cmdRow.isHeader
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: cmdRow.modelData.title || ""
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 13; weight: cmdRow.customized ? Font.DemiBold : Font.Normal }
                }
                Row {
                    visible: !cmdRow.isHeader
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    ToolbarButton {
                        visible: cmdRow.customized
                        symbol: "arrow-clockwise"
                        symbolSize: 12
                        Accessible.name: "Restore the default"
                        onClicked: page.app.saveSettings({ keyBindings: Commands.reset(cmdRow.modelData.id, page.overrides) })
                    }
                    Rectangle {
                        id: chip
                        readonly property bool active: page.recording === cmdRow.modelData.id
                        width: Math.max(120, chipText.implicitWidth + 20)
                        height: 22
                        radius: 6
                        color: active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : chipHover.hovered ? (Theme.dark ? "#22ffffff" : "#12000000") : (Theme.dark ? "#14ffffff" : "#0a000000")
                        border { width: active ? 1.5 : 0.5; color: active ? Theme.accent : Theme.separator }
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.active ? "Type a shortcut…" : cmdRow.keys.length ? cmdRow.keys.map(Commands.display).join("  ") : "—"
                            color: chip.active ? Theme.accent : cmdRow.keys.length ? Theme.label : Theme.tertiaryLabel
                            font { family: Theme.fontUi; pixelSize: 12 }
                        }
                        HoverHandler { id: chipHover }
                        TapHandler { onTapped: page.record(cmdRow.modelData.id) }
                    }
                }
            }
        }
    }
}
