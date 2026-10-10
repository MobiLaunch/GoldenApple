import QtQuick
QtObject {
    property string splitMarker: "\n"
    signal read(string data)
    function __feed(t) {
        if (!t) return
        const parts = t.split(splitMarker)
        if (parts.length && parts[parts.length - 1] === "") parts.pop()
        for (const line of parts) read(line)
    }
}
