import QtQuick
// Creates its component (or the file at `source`) while active.
QtObject {
    id: loader
    default property Component component
    property string source
    property bool active: false
    property bool loading: false
    property QtObject item: null
    function sync() {
        if (active && !item) {
            const c = component ?? Qt.createComponent(Qt.resolvedUrl(source, loader))
            if (c.status === Component.Error) { console.warn("LazyLoader:", c.errorString()); return }
            item = c.createObject(loader)
        } else if (!active && item) {
            item.destroy(); item = null
        }
    }
    onActiveChanged: sync()
    Component.onCompleted: sync()
}
