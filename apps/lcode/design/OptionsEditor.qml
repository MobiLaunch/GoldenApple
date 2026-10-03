// A short list to edit: a menu's options, or a list's rows (with their
// done marks when the list has check marks).
import QtQuick
import "../../lib"
import "../../lib/theme"

Column {
    id: oe
    property var values: []
    property bool checkable: false
    property var newItem: null                // what Add puts in (else "Option n" or a new row)
    signal commit(var list)
    width: parent ? parent.width : 0
    spacing: 4

    function titleOf(v) { return v !== null && typeof v === "object" ? String(v.title !== undefined ? v.title : "") : String(v) }
    function changed(i, title) {
        const list = values.slice()
        list[i] = typeof values[i] === "object" && values[i] !== null ? Object.assign({}, values[i], { title: title }) : title
        commit(list)
    }

    Repeater {
        model: oe.values
        delegate: Row {
            id: optRow
            required property var modelData
            required property int index
            width: oe.width
            spacing: 4
            Checkbox {
                visible: oe.checkable
                width: 20
                checked: typeof optRow.modelData === "object" && optRow.modelData !== null && !!optRow.modelData.done
                onToggled: (c) => {
                    const list = oe.values.slice()
                    list[optRow.index] = Object.assign(typeof optRow.modelData === "object" && optRow.modelData !== null ? optRow.modelData : { title: String(optRow.modelData) }, { done: c })
                    oe.commit(list)
                }
            }
            TextField {
                width: parent.width - 26 - (oe.checkable ? 24 : 0)
                height: 24
                text: oe.titleOf(optRow.modelData)
                onAccepted: if (text !== oe.titleOf(optRow.modelData)) oe.changed(optRow.index, text)
                input.onActiveFocusChanged: if (!input.activeFocus && text !== oe.titleOf(optRow.modelData)) oe.changed(optRow.index, text)
            }
            ToolbarButton {
                height: 24
                symbol: "minus"
                symbolSize: 11
                Accessible.name: "Remove"
                onClicked: { const list = oe.values.slice(); list.splice(optRow.index, 1); oe.commit(list) }
            }
        }
    }
    ToolbarButton {
        height: 24
        symbol: "plus"
        symbolSize: 11
        text: "Add"
        onClicked: {
            const objects = oe.checkable || (oe.values.length && typeof oe.values[0] === "object")
            oe.commit(oe.values.concat([oe.newItem !== null ? oe.newItem : objects ? { title: "New item", done: false } : "Option " + (oe.values.length + 1)]))
        }
    }
}
