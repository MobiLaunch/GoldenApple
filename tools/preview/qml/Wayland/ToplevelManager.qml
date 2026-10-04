pragma Singleton
import QtQuick
// --env GG_PREVIEW_ACTIVE=org.goldengate.Files puts that app in front (the
// menu bar then shows its name and its Window menu).
QtObject {
    readonly property string __active: __preview.env["GG_PREVIEW_ACTIVE"] ?? ""
    readonly property QtObject toplevels: QtObject { readonly property var values: [] }
    readonly property var activeToplevel: __active ? ({ appId: __active, title: "", close: () => __preview.log("close " + __active) }) : null
}
