// The navigator area, in the window's floating glass sidebar: the Project,
// Find, Issue and Report navigators, chosen from the icon strip on top.
import Quickshell
import QtQuick
import "../lib"
import "../lib/theme"
import "languages.js" as Languages

Item {
    id: nav
    property var app
    property var backend
    property string selectedPath: ""
    property int page: 0                       // 0 project, 1 find, 2 issues, 3 reports
    property var expanded: ({})
    property var findResults: []
    property bool findCase: false
    property bool searching: false
    signal openFile(string path, int line, int column)
    signal openProjectEditor()
    signal openReport(var report)
    signal fileMenu(Item from, real x, real y, string path, bool isDir)
    signal newItem(string dir, bool folder)

    function focusFind(text) {
        page = 1
        if (text) findField.text = text
        findField.input.forceActiveFocus()
        findField.input.selectAll()
    }

    function runFind() {
        if (!findField.text) return
        searching = true
        backend.call("find", { query: findField.text, caseSensitive: findCase }, (r) => {
            nav.searching = false
            nav.findResults = r.ok ? r.results : []
        })
    }

    function toggle(path) {
        const e = Object.assign({}, expanded)
        e[path] = !e[path]
        expanded = e
    }

    // Open every folder down to `path`, e.g. when a file opens from elsewhere.
    function reveal(path) {
        if (!app.project) return
        const e = Object.assign({}, expanded)
        let dir = path.substring(0, path.lastIndexOf("/"))
        while (dir.length > app.project.root.length) {
            e[dir] = true
            dir = dir.substring(0, dir.lastIndexOf("/"))
        }
        expanded = e
    }

    // The tree as visible rows: a node shows when every folder above it is open.
    readonly property var rows: {
        const out = []
        if (!app.project) return out
        const filter = filterField.text.trim().toLowerCase()
        if (filter) {
            for (const n of app.nodes)
                if (!n.dir && n.name.toLowerCase().includes(filter))
                    out.push(Object.assign({}, n, { depth: 0 }))
            return out
        }
        const shown = {}
        shown[app.project.root] = true
        for (const n of app.nodes) {
            if (!shown[n.parent]) continue
            out.push(n)
            if (n.dir && expanded[n.path]) shown[n.path] = true
        }
        return out
    }

    readonly property var issueRows: {
        const out = []
        const groups = {}
        const order = []
        for (const i of app.issues) {
            const key = i.path || ""
            if (!groups[key]) { groups[key] = []; order.push(key) }
            groups[key].push(i)
        }
        for (const key of order) {
            out.push({ header: true, title: key ? key.split("/").pop() : "Build " + app.schemeName, count: groups[key].length, path: key })
            for (const i of groups[key]) out.push(Object.assign({ header: false }, i))
        }
        return out
    }

    function fileSymbol(name, isDir) { return isDir ? "folder" : Languages.fileInfo(name).symbol }
    function fileColor(name, isDir) { return isDir ? "transparent" : Languages.fileInfo(name).color }

    // ---------------------------------------------------------------- strip
    Row {
        id: strip
        x: 2
        width: parent.width - 4
        height: 32
        spacing: (width - 4 * 34) / 3
        Repeater {
            model: [
                { symbol: "folder", tip: "Project Navigator (⌘1)" },
                { symbol: "search", tip: "Find Navigator (⌘4)" },
                { symbol: "warning", tip: "Issue Navigator (⌘5)" },
                { symbol: "clock", tip: "Report Navigator (⌘9)" },
            ]
            delegate: ToolbarButton {
                required property var modelData
                required property int index
                symbol: modelData.symbol
                symbolSize: 15
                tone: nav.page === index ? "accent" : "auto"
                checked: false
                Accessible.name: modelData.tip
                onClicked: nav.page = index
            }
        }
    }
    Rectangle {
        y: strip.height + 4
        width: parent.width
        height: 1
        color: Theme.separator
    }

    // -------------------------------------------------------------- project
    Item {
        id: projectPage
        visible: nav.page === 0
        anchors { fill: parent; topMargin: strip.height + 10 }

        SidebarRow {
            id: projectRow
            width: parent.width
            text: nav.app.project ? nav.app.project.name : ""
            leading: Component {
                Image {
                    sourceSize: Qt.size(44, 44)
                    source: Quickshell.iconPath("org.goldengate.LCode", true)
                }
            }
            leadingSize: 18
            onClicked: { nav.selectedPath = ""; nav.openProjectEditor() }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: (p) => nav.fileMenu(projectRow, p.position.x, p.position.y, nav.app.project.root, true)
            }
        }

        ListView {
            id: tree
            anchors { top: projectRow.bottom; left: parent.left; right: parent.right; bottom: filterBar.top; bottomMargin: 6 }
            clip: true
            model: nav.rows
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                id: node
                required property var modelData
                width: tree.width
                height: 28
                SidebarRow {
                    anchors.fill: parent
                    indent: node.modelData.depth * 14
                    text: node.modelData.name
                    selected: node.modelData.path === nav.selectedPath
                    leadingSize: 32
                    leading: Component {
                        Item {
                            Symbol {
                                visible: node.modelData.dir
                                anchors.verticalCenter: parent.verticalCenter
                                name: "chevron-small-right"
                                size: 12
                                tone: "gray"
                                rotation: nav.expanded[node.modelData.path] ? 90 : 0
                                Behavior on rotation { NumberAnimation { duration: Theme.reduceMotion ? 1 : 120 } }
                            }
                            Symbol {
                                x: 15
                                anchors.verticalCenter: parent.verticalCenter
                                name: nav.fileSymbol(node.modelData.name, node.modelData.dir)
                                size: 15
                                tone: node.modelData.dir ? "accent" : "auto"
                                color: nav.fileColor(node.modelData.name, node.modelData.dir)
                            }
                        }
                    }
                    onClicked: {
                        if (node.modelData.dir) {
                            nav.toggle(node.modelData.path)
                        } else {
                            nav.selectedPath = node.modelData.path
                            nav.openFile(node.modelData.path, 0, 0)
                        }
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: (p) => nav.fileMenu(node, p.position.x, p.position.y, node.modelData.path, node.modelData.dir)
                }
            }
        }

        Row {
            id: filterBar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            spacing: 6
            ToolbarButton {
                id: addButton
                anchors.verticalCenter: parent.verticalCenter
                symbol: "plus"
                symbolSize: 15
                onClicked: nav.fileMenu(addButton, 0, -6, nav.app.project.root, true)
            }
            TextField {
                id: filterField
                width: parent.width - addButton.width - 6
                height: 30
                search: true
                placeholder: "Filter"
            }
        }
    }

    // ----------------------------------------------------------------- find
    Item {
        visible: nav.page === 1
        anchors { fill: parent; topMargin: strip.height + 12 }

        Row {
            id: findRow
            width: parent.width
            spacing: 6
            TextField {
                id: findField
                width: parent.width - caseButton.width - 6
                height: 30
                search: true
                placeholder: "Find in Project"
                onAccepted: nav.runFind()
            }
            ToolbarButton {
                id: caseButton
                anchors.verticalCenter: parent.verticalCenter
                text: "Aa"
                checked: nav.findCase
                onClicked: { nav.findCase = !nav.findCase; nav.runFind() }
            }
        }
        Text {
            id: findSummary
            anchors { top: findRow.bottom; topMargin: 8; left: parent.left; leftMargin: 8 }
            readonly property int total: nav.findResults.reduce((n, f) => n + f.matches.length, 0)
            text: nav.searching ? "Searching…" : findField.text && nav.findResults.length + total > 0
                ? total + (total === 1 ? " result in " : " results in ") + nav.findResults.length + (nav.findResults.length === 1 ? " file" : " files")
                : ""
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 11 }
        }
        ListView {
            id: findList
            anchors { top: findSummary.bottom; topMargin: 6; left: parent.left; right: parent.right; bottom: parent.bottom }
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: {
                const out = []
                for (const f of nav.findResults) {
                    out.push({ header: true, path: f.path, count: f.matches.length })
                    for (const m of f.matches) out.push(Object.assign({ header: false, path: f.path }, m))
                }
                return out
            }
            delegate: Item {
                id: hit
                required property var modelData
                width: findList.width
                height: modelData.header ? 28 : 24
                SidebarRow {
                    anchors.fill: parent
                    visible: hit.modelData.header
                    text: hit.modelData.header ? hit.modelData.path.split("/").pop() : ""
                    symbol: "code"
                    symbolTone: "auto"
                    badge: hit.modelData.header ? String(hit.modelData.count) : ""
                    onClicked: nav.openFile(hit.modelData.path, 0, 0)
                }
                Rectangle {
                    visible: !hit.modelData.header
                    anchors { fill: parent; leftMargin: 2; rightMargin: 2 }
                    radius: 6
                    color: hitHover.hovered ? Theme.fill : "transparent"
                }
                Text {
                    visible: !hit.modelData.header
                    x: 30
                    width: parent.width - 36
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.StyledText
                    elide: Text.ElideRight
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 12 }
                    text: {
                        if (hit.modelData.header) return ""
                        const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                        const t = hit.modelData.text, a = hit.modelData.start, b = a + hit.modelData.length
                        return esc(t.slice(0, a)) + "<b>" + esc(t.slice(a, b)) + "</b>" + esc(t.slice(b))
                    }
                }
                HoverHandler { id: hitHover }
                TapHandler {
                    enabled: !hit.modelData.header
                    onTapped: nav.openFile(hit.modelData.path, hit.modelData.line, hit.modelData.column)
                }
            }
        }
    }

    // --------------------------------------------------------------- issues
    Item {
        visible: nav.page === 2
        anchors { fill: parent; topMargin: strip.height + 12 }
        EmptyState {
            anchors.fill: parent
            visible: nav.app.issues.length === 0
            symbol: "checkmark"
            title: "No Issues"
        }
        ListView {
            id: issueList
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: nav.issueRows
            delegate: Item {
                id: issue
                required property var modelData
                width: issueList.width
                height: modelData.header ? 28 : Math.max(26, message.implicitHeight + 10)
                SidebarRow {
                    anchors.fill: parent
                    visible: issue.modelData.header
                    text: issue.modelData.header ? issue.modelData.title : ""
                    symbol: issue.modelData.path ? "code" : "hammer"
                    symbolTone: "auto"
                    badge: issue.modelData.header ? String(issue.modelData.count) : ""
                }
                Rectangle {
                    visible: !issue.modelData.header
                    anchors { fill: parent; leftMargin: 2; rightMargin: 2 }
                    radius: 6
                    color: issueHover.hovered ? Theme.fill : "transparent"
                }
                Symbol {
                    visible: !issue.modelData.header
                    x: 22; y: 6
                    size: 14
                    name: issue.modelData.severity === "error" ? "xmark-circle" : "warning"
                    tone: issue.modelData.severity === "error" ? "red" : "auto"
                    color: issue.modelData.severity === "error" ? "transparent" : "#ffb800"
                }
                Text {
                    id: message
                    visible: !issue.modelData.header
                    x: 42; y: 5
                    width: parent.width - x - 8
                    text: issue.modelData.header ? "" : issue.modelData.message + (issue.modelData.line ? "  —  line " + issue.modelData.line : "")
                    wrapMode: Text.WordWrap
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 12 }
                }
                HoverHandler { id: issueHover }
                TapHandler {
                    enabled: !issue.modelData.header && !!issue.modelData.path
                    onTapped: nav.app.revealLocation(issue.modelData.path, issue.modelData.line, issue.modelData.column, issue.modelData.message)
                }
            }
        }
    }

    // -------------------------------------------------------------- reports
    Item {
        visible: nav.page === 3
        anchors { fill: parent; topMargin: strip.height + 12 }
        EmptyState {
            anchors.fill: parent
            visible: nav.app.reports.length === 0
            symbol: "clock"
            title: "No Reports"
            text: "Build the project to create a build log."
        }
        ListView {
            id: reportList
            anchors.fill: parent
            clip: true
            spacing: 2
            model: nav.app.reports
            delegate: SidebarRow {
                required property var modelData
                width: reportList.width
                height: 40
                text: modelData.title + "   " + modelData.time
                symbol: modelData.status === "ok" ? "checkmark" : modelData.status === "failed" ? "xmark-circle"
                      : modelData.status === "cancelled" ? "stop" : "clock"
                symbolTone: modelData.status === "failed" ? "red" : modelData.status === "ok" ? "accent" : "gray"
                onClicked: nav.openReport(modelData)
            }
        }
    }
}
