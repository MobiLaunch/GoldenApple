pragma Singleton
import QtQuick
QtObject {
    readonly property QtObject toplevels: QtObject { readonly property var values: [] }
    readonly property QtObject activeToplevel: null
}
