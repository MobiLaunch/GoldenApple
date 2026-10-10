import QtQuick
// Reads the file for real (through preview.py), once, as soon as it has a path.
QtObject {
    id: fv
    property string path
    property bool printErrors: true
    property bool watchChanges: false
    property bool blockLoading: false
    property bool blockAllReads: false
    property bool blockWrites: false
    property bool preload: true
    property bool atomicWrites: true
    property QtObject adapter
    property bool __loaded: false
    property string __text: ""
    signal fileChanged()
    signal loadFailed(int error)
    signal saved()
    signal saveFailed(int error)
    function text() { return __text }
    function data() { return __text }
    function reload() { __load() }
    // Written for real only when the harness allows it (tests); otherwise logged.
    function setText(t) {
        __text = t
        if (__preview.allowWrites === true) { if (__preview.writeFile(path, t)) saved(); else saveFailed(5) }
        else __preview.log("write " + path)
    }
    function writeAdapter() {}
    function __load() {
        if (!path) return
        const r = __preview.readFile(path)
        if (r === null || r === undefined) { __loaded = false; loadFailed(2); return }
        __text = r; __loaded = true; loaded()
    }
    signal loaded()
    onPathChanged: Qt.callLater(__load)
}
