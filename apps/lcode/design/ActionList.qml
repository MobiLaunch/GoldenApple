// What happens on one event (when clicked, changed, …): a list of actions,
// each a card with its settings, added from a menu.
import QtQuick
import "../../lib"
import "../../lib/theme"
import "../../lib/kit/catalog.js" as Catalog

Column {
    id: list
    property var inspector: null
    property string event: "tap"
    property var actions: []
    signal commit(var list)
    spacing: 6

    readonly property var doc: inspector ? inspector.doc : null
    function update(i, patch) { const out = actions.slice(); out[i] = Object.assign({}, out[i], patch); commit(out) }
    function removeAt(i) { const out = actions.slice(); out.splice(i, 1); commit(out) }
    function moveBy(i, d) { const out = actions.slice(); const j = i + d; if (j < 0 || j >= out.length) return; const [a] = out.splice(i, 1); out.splice(j, 0, a); commit(out) }
    function fresh(kind) {
        const vars = doc ? doc.state : []
        const pick = (type) => (vars.find((v) => !type || v.type === type) || {}).name || ""
        switch (kind) {
        case "set": return { do: kind, var: pick(""), value: "" }
        case "increment": return { do: kind, var: pick("number"), by: 1 }
        case "toggle": return { do: kind, var: pick("bool") }
        case "append": return { do: kind, var: pick("list"), value: "" }
        case "removeItem": return { do: kind, var: pick("list") }
        case "clear": return { do: kind, var: pick("") }
        case "navigate": return { do: kind, screen: doc && doc.screens.length > 1 ? doc.screens[1].id : (doc ? doc.screens[0].id : "") }
        case "alert": return { do: kind, title: "Hello!", message: "" }
        case "notify": return { do: kind, title: "Done", message: "" }
        case "openUrl": return { do: kind, url: "https://" }
        case "copy": return { do: kind, text: "" }
        case "run": return { do: kind, command: "date", var: "" }
        case "script": return { do: kind, call: "greet" }
        default: return { do: kind }
        }
    }
    readonly property var varTypes: ({ increment: "number", toggle: "bool", append: "list", removeItem: "list" })
    readonly property var titles: ({ value: "Value", by: "Add", screen: "Screen", title: "Title", message: "Message", url: "Address",
                                     text: "Text", command: "Command", call: "Function", var: "Variable" })

    Text {
        text: (Catalog.CATALOG.events[list.event] || list.event)
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
    }
    Repeater {
        model: list.actions
        delegate: Rectangle {
            id: card
            required property var modelData
            required property int index
            readonly property var spec: Catalog.action(modelData.do) || { title: modelData.do, fields: [] }
            width: list.width
            height: body.height + 16
            radius: 10
            color: Theme.dark ? "#14ffffff" : "#0a000000"
            border { width: 0.5; color: Theme.separator }
            Column {
                id: body
                x: 8; y: 8
                width: parent.width - 16
                spacing: 6
                Row {
                    width: parent.width
                    spacing: 4
                    Symbol { anchors.verticalCenter: parent.verticalCenter; name: card.spec.symbol || "bolt"; size: 14; tone: "accent" }
                    PopUpButton {
                        width: parent.width - 18 - 26 - 8
                        options: Catalog.CATALOG.actions.map((a) => a.title)
                        current: Math.max(0, Catalog.CATALOG.actions.findIndex((a) => a.do === card.modelData.do))
                        menuParent: list.inspector.overlay
                        onPicked: (i) => { const out = list.actions.slice(); out[card.index] = list.fresh(Catalog.CATALOG.actions[i].do); list.commit(out) }
                    }
                    ToolbarButton {
                        id: cardMenu
                        height: 22
                        symbol: "ellipsis"
                        symbolSize: 12
                        Accessible.name: "Move or remove this action"
                        onClicked: list.inspector.designer.menu.popup(cardMenu, 0, cardMenu.height + 4, [
                            { text: "Move Up", enabled: card.index > 0, action: () => list.moveBy(card.index, -1) },
                            { text: "Move Down", enabled: card.index < list.actions.length - 1, action: () => list.moveBy(card.index, 1) },
                            { separator: true },
                            { text: "Remove Action", destructive: true, action: () => list.removeAt(card.index) },
                        ])
                    }
                }
                Repeater {
                    model: card.spec.fields
                    delegate: Row {
                        id: fieldRow
                        required property string modelData
                        width: body.width
                        spacing: 6
                        Text {
                            width: 62
                            height: 24
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignRight
                            text: list.titles[fieldRow.modelData] || fieldRow.modelData
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 11 }
                        }
                        Loader {
                            width: parent.width - 68
                            sourceComponent: fieldRow.modelData === "var" ? varC : fieldRow.modelData === "screen" ? screenC
                                           : fieldRow.modelData === "by" ? byC : textC
                            Component {
                                id: varC
                                PopUpButton {
                                    readonly property string want: list.varTypes[card.modelData.do] || ""
                                    readonly property var vars: (list.doc ? list.doc.state : []).filter((v) => !want || v.type === want)
                                    readonly property bool optional: card.modelData.do === "run"
                                    options: (optional ? ["Don't Keep the Output"] : []).concat(vars.map((v) => v.name))
                                    current: Math.max(0, (optional ? [""] : []).concat(vars.map((v) => v.name)).indexOf(card.modelData.var || ""))
                                    menuParent: list.inspector.overlay
                                    onPicked: (i) => list.update(card.index, { var: (optional ? [""] : []).concat(vars.map((v) => v.name))[i] })
                                }
                            }
                            Component {
                                id: screenC
                                PopUpButton {
                                    options: list.doc ? list.doc.screens.map((s) => s.title || s.id) : []
                                    current: list.doc ? Math.max(0, list.doc.screens.findIndex((s) => s.id === card.modelData.screen)) : 0
                                    menuParent: list.inspector.overlay
                                    onPicked: (i) => list.update(card.index, { screen: list.doc.screens[i].id })
                                }
                            }
                            Component {
                                id: byC
                                TextField {
                                    height: 24
                                    text: String(card.modelData.by === undefined ? 1 : card.modelData.by)
                                    onAccepted: { const n = parseFloat(text); if (!isNaN(n)) list.update(card.index, { by: n }) }
                                    input.onActiveFocusChanged: if (!input.activeFocus) { const n = parseFloat(text); if (!isNaN(n) && n !== card.modelData.by) list.update(card.index, { by: n }) }
                                }
                            }
                            Component {
                                id: textC
                                TextField {
                                    height: 24
                                    text: String(card.modelData[fieldRow.modelData] || "")
                                    placeholder: fieldRow.modelData === "value" ? "Text, a number, or {variable}" : ""
                                    onAccepted: list.update(card.index, { [fieldRow.modelData]: text })
                                    input.onActiveFocusChanged: if (!input.activeFocus && text !== String(card.modelData[fieldRow.modelData] || ""))
                                        list.update(card.index, { [fieldRow.modelData]: text })
                                }
                            }
                        }
                    }
                }
                Row {
                    visible: card.modelData.do !== "quit"
                    width: parent.width
                    spacing: 6
                    Text {
                        width: 62
                        height: 24
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                        text: "Only When"
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 11 }
                    }
                    PopUpButton {
                        width: parent.width - 68
                        readonly property var flags: (list.doc ? list.doc.state : []).filter((v) => v.type === "bool").map((v) => v.name)
                        options: ["Always"].concat(flags)
                        current: Math.max(0, [""].concat(flags).indexOf(card.modelData.when || ""))
                        menuParent: list.inspector.overlay
                        onPicked: (i) => list.update(card.index, { when: i ? flags[i - 1] : undefined })
                    }
                }
            }
        }
    }
    ToolbarButton {
        id: addButton
        height: 26
        symbol: "plus"
        symbolSize: 12
        text: "Add Action"
        onClicked: list.inspector.designer.menu.popup(addButton, 0, addButton.height + 4,
            Catalog.CATALOG.actions.filter((a) => a.do !== "removeItem" || list.event === "itemTap")
                .map((a) => ({ text: a.title, symbol: a.symbol, action: () => list.commit(list.actions.concat([list.fresh(a.do)])) })))
    }
}
