// Open Quickly (⇧⌘O): type part of a file name, Return opens the best match.
import QtQuick
import "../lib"
import "../lib/theme"

Sheet {
    id: oq
    property var backend
    property var app
    property var files: []
    property int selectedIndex: 0
    signal chosen(string path)
    panelWidth: 600
    panelHeight: 380

    onShownChanged: if (shown) {
        field.text = ""
        field.input.forceActiveFocus()
        backend.call("files", {}, (r) => { if (r.ok) oq.files = r.files })
    }

    // Subsequence match; consecutive letters and word starts score higher, shorter names win ties.
    function score(query, name) {
        if (!query) return 0
        const q = query.toLowerCase().replace(/\s+/g, ""), c = name.toLowerCase()
        let s = 0, qi = 0, last = -2
        for (let i = 0; i < c.length && qi < q.length; i++) {
            if (c[i] !== q[qi]) continue
            s += 1 + (last === i - 1 ? 5 : 0) + (i === 0 || "/_-. ".includes(name[i - 1]) || (name[i] !== c[i] && name[i - 1] === c[i - 1]) ? 8 : 0)
            last = i
            qi++
        }
        return qi < q.length ? -1 : s * 10 - c.length
    }

    readonly property var results: {
        const root = app.project ? app.project.root + "/" : ""
        const out = []
        for (const p of files) {
            const name = p.split("/").pop()
            const rel = p.startsWith(root) ? p.slice(root.length) : p
            let s = score(field.text, name)
            s = s >= 0 ? s + 1000 : score(field.text, rel)
            if (s >= 0) out.push({ path: p, name: name, dir: rel.split("/").slice(0, -1).join("/"), score: s })
        }
        out.sort((a, b) => b.score - a.score || a.name.localeCompare(b.name))
        return out.slice(0, 60)
    }
    onResultsChanged: selectedIndex = 0

    function accept() {
        const r = results[selectedIndex]
        if (!r) return
        close()
        chosen(r.path)
    }

    TextField {
        id: field
        width: parent.width
        height: 38
        search: true
        placeholder: "Open Quickly"
        onAccepted: oq.accept()
        input.Keys.onDownPressed: oq.selectedIndex = Math.min(oq.results.length - 1, oq.selectedIndex + 1)
        input.Keys.onUpPressed: oq.selectedIndex = Math.max(0, oq.selectedIndex - 1)
        input.Keys.onEscapePressed: oq.close()
    }
    ListView {
        id: list
        y: field.height + 10
        width: parent.width
        height: oq.panelHeight - 40 - y
        clip: true
        model: oq.results
        currentIndex: oq.selectedIndex
        boundsBehavior: Flickable.StopAtBounds
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            width: list.width
            height: 40
            Rectangle {
                anchors.fill: parent
                radius: 8
                color: row.index === oq.selectedIndex ? Theme.accent : hover.hovered ? Theme.fill : "transparent"
            }
            Symbol {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                name: row.modelData.name.endsWith(".swift") ? "code" : "doc"
                size: 18
                tone: row.index === oq.selectedIndex ? "white" : "auto"
                color: row.index !== oq.selectedIndex && row.modelData.name.endsWith(".swift") ? "#f05138" : "transparent"
            }
            Column {
                x: 38
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: row.modelData.name
                    color: row.index === oq.selectedIndex ? "#ffffff" : Theme.label
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                }
                Text {
                    text: row.modelData.dir || "Project root"
                    color: row.index === oq.selectedIndex ? "#ccffffff" : Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 11 }
                }
            }
            HoverHandler { id: hover }
            TapHandler { onTapped: { oq.selectedIndex = row.index; oq.accept() } }
        }
    }
}
