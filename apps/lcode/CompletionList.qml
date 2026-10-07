// The code completion list, under the word being typed: a badge for each
// kind (keyword, function, type, variable, snippet, word), the name with what
// you typed in bold, and a snippet's description underneath.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: list
    property var items: []
    property string prefix: ""
    property int index: 0
    property real fontSize: 13
    signal accepted(var item)
    readonly property var currentItem: items.length ? items[Math.max(0, Math.min(index, items.length - 1))] : null
    readonly property real rowHeight: Math.round(fontSize * 1.65)
    readonly property int shown: Math.min(9, items.length)
    width: 400
    height: shown * rowHeight + 8 + (footer.visible ? footer.height : 0)
    visible: items.length > 0

    readonly property var badges: ({
        keyword: { text: "K", color: "#d63aa8" },
        function: { text: "M", color: "#2fa8a0" },
        type: { text: "C", color: "#8f5bd6" },
        variable: { text: "V", color: "#3a82f0" },
        word: { text: "W", color: "#8e8e93" },
        snippet: { text: "{}", color: "#6e7681" },
    })

    function move(by) {
        if (!items.length) return
        index = (index + by + items.length) % items.length
        view.positionViewAtIndex(index, ListView.Contain)
    }
    onItemsChanged: { index = 0; view.positionViewAtBeginning() }

    // The name with the typed letters in bold.
    function marked(title) {
        const esc = (t) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        if (!prefix) return esc(title)
        const lower = title.toLowerCase(), want = prefix.toLowerCase()
        if (lower.startsWith(want)) return "<b>" + esc(title.slice(0, prefix.length)) + "</b>" + esc(title.slice(prefix.length))
        let out = "", j = 0
        for (let i = 0; i < title.length; i++) {
            if (j < want.length && lower[i] === want[j]) { out += "<b>" + esc(title[i]) + "</b>"; j++ }
            else out += esc(title[i])
        }
        return out
    }

    Rectangle {
        anchors.fill: parent
        radius: 9
        color: Theme.dark ? "#f02a2a2e" : "#f8ffffff"
        border { width: 1; color: Theme.dark ? "#33ffffff" : "#26000000" }
    }
    // A soft shadow.
    Rectangle {
        z: -1
        anchors { fill: parent; topMargin: 4; leftMargin: -2; rightMargin: -2; bottomMargin: -6 }
        radius: 12
        color: "#22000000"
    }

    ListView {
        id: view
        x: 4; y: 4
        width: parent.width - 8
        height: list.shown * list.rowHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: list.items
        currentIndex: list.index
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool selected: index === list.index
            readonly property var badge: list.badges[modelData.kind] || list.badges.word
            width: view.width
            height: list.rowHeight
            radius: 5
            color: selected ? Theme.accent : "transparent"
            Rectangle {
                id: badgeBox
                x: 5
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(list.rowHeight * 0.72); height: width
                radius: 4
                color: row.badge.color
                Text {
                    anchors.centerIn: parent
                    text: row.badge.text
                    color: "white"
                    font { family: Theme.fontUi; pixelSize: Math.max(9, list.fontSize - 3); weight: Font.Bold }
                }
            }
            Text {
                x: badgeBox.x + badgeBox.width + 8
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - detailText.implicitWidth - 16
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: list.marked(row.modelData.title)
                color: row.selected ? "white" : Theme.label
                font { family: "monospace"; pixelSize: list.fontSize - 1 }
            }
            Text {
                id: detailText
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text: row.modelData.kind === "snippet" ? (row.modelData.own ? "My Snippet" : "Snippet") : ""
                color: row.selected ? "#ddffffff" : Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Math.max(10, list.fontSize - 3) }
            }
            TapHandler {
                onTapped: list.index = row.index
                onDoubleTapped: list.accepted(row.modelData)
            }
        }
    }

    // A snippet's name and code.
    Column {
        id: footer
        visible: !!list.currentItem && list.currentItem.kind === "snippet"
        x: 12
        y: view.y + view.height + 2
        width: parent.width - 24
        height: visible ? implicitHeight + 10 : 0
        spacing: 2
        Rectangle { width: parent.width; height: 1; color: Theme.separator }
        Text {
            topPadding: 4
            text: list.currentItem ? list.currentItem.label || "" : ""
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
        }
        Text {
            width: parent.width
            elide: Text.ElideRight
            maximumLineCount: 3
            text: list.currentItem && list.currentItem.insert ? list.currentItem.insert.split("\n").slice(0, 3).join("\n").replace(/<#([^#\n]*)#>/g, "$1") : ""
            color: Theme.secondaryLabel
            font { family: "monospace"; pixelSize: Theme.fs(11) }
        }
    }
}
