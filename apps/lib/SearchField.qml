// The search field every app uses: ⌘F (Ctrl+F) puts the cursor in it,
// results follow the typing (`searched`, once it pauses), Return searches at
// once and remembers it, Escape clears it and then lets go, and ↓ in an
// empty field offers the recent searches.
//   SearchField { id: find; onSearched: (text) => model.filter(text); menuLayer: win.overlay }
import QtQuick
import "theme"

TextField {
    id: field
    search: true
    placeholder: "Search"
    property bool findShortcut: true
    property int delay: 150
    property var recents: []
    property int maxRecents: 8
    property Item menuLayer: null           // where the recents menu opens (AppWindow's overlay)
    signal searched(string text)
    signal cancelled()                       // Escape in an empty field

    Component.onCompleted: input.Accessible.searchEdit = true
    function focusField() { input.forceActiveFocus(); input.selectAll() }
    function remember(text) {
        text = String(text).trim()
        if (!text) return
        recents = [text].concat(recents.filter((r) => r !== text)).slice(0, maxRecents)
    }
    function showRecents() {
        if (!recents.length) return false
        const layer = menuLayer ?? field.Window.contentItem
        if (!layer) return false
        const menu = recentsMenu.createObject(layer)
        menu.popup(field, 0, field.height + 4, [{ header: "Recent Searches" }]
            .concat(recents.map((r) => ({ text: r, action: () => { field.text = r; field.remember(r); field.searched(r) } })))
            .concat([{ separator: true }, { text: "Clear Recent Searches", action: () => field.recents = [] }]))
        return true
    }
    Component { id: recentsMenu; PopupMenu { menuWidth: Math.max(200, field.width) } }

    Shortcut {
        sequences: [StandardKey.Find]
        enabled: field.findShortcut && field.visible && field.enabled
        onActivated: field.focusField()
    }
    Timer { id: pause; interval: field.delay; onTriggered: field.searched(field.text) }
    Connections {
        target: field.input
        function onTextChanged() { pause.restart() }
    }
    onAccepted: { pause.stop(); remember(text); searched(text) }
    onCleared: { pause.stop(); searched("") }
    // TextField's own Escape clears a field with text in it; in an empty one
    // it comes here: let go of the cursor and let the window have it too.
    Keys.onEscapePressed: (event) => {
        input.focus = false
        cancelled()
        event.accepted = false
    }
    Keys.onDownPressed: (event) => { event.accepted = !text && showRecents() }
}
