pragma Singleton
import QtQuick
// --env GG_PREVIEW_ACTIVE=org.goldengate.Files puts that app in front (the
// menu bar then shows its name and its Window menu).
QtObject {
    readonly property string __active: __preview.env["GG_PREVIEW_ACTIVE"] ?? ""
    // --env GG_PREVIEW_RUNNING=id,id… opens a window of each (app ids).
    readonly property QtObject toplevels: QtObject {
        readonly property var values: (__preview.env["GG_PREVIEW_RUNNING"] ?? "").split(",").filter((id) => id).map((id) => ({
            appId: id, title: id.split(".").pop() + " window",
            activate: () => __preview.log("activate " + id), close: () => __preview.log("close " + id)
        }))
    }
    readonly property var activeToplevel: __active ? ({ appId: __active, title: "", close: () => __preview.log("close " + __active) }) : null
}
