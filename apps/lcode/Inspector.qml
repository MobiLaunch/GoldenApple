// The inspectors, in the trailing glass sidebar: the File inspector (identity,
// type, text settings) and the project's product type and bundle identifier.
import QtQuick
import "../lib"
import "../lib/theme"

Flickable {
    id: inspector
    property var app
    property var backend
    property var menuParent
    property string path: ""
    property var editor: null
    clip: true
    contentHeight: column.height + 20
    boundsBehavior: Flickable.StopAtBounds

    readonly property string fileName: path ? path.split("/").pop() : ""
    readonly property string fileType: {
        const n = fileName.toLowerCase()
        if (n === "package.swift") return "Swift Package Manifest"
        if (n.endsWith(".swift")) return "Swift Source"
        if (n.endsWith(".md")) return "Markdown Text"
        if (n.endsWith(".json")) return "JSON"
        if (/\.(c|h)$/.test(n)) return "C Source"
        if (/\.(png|jpe?g|svg|gif)$/.test(n)) return "Image"
        return "Plain Text"
    }

    component Field: Column {
        property string label
        property string value
        width: parent.width
        spacing: 2
        Text {
            text: parent.label
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 11 }
        }
        Text {
            width: parent.width
            text: parent.value || "—"
            wrapMode: Text.WrapAnywhere
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 12 }
        }
    }

    Column {
        id: column
        x: 6
        width: parent.width - 12
        spacing: 10

        Row {
            spacing: 6
            Symbol { name: "doc"; size: 15; tone: "accent"; anchors.verticalCenter: parent.verticalCenter }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "File"
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
            }
        }

        SidebarSection { text: "Identity and Type"; topSpacing: 4; leftPadding: 0 }
        Text {
            visible: !inspector.path
            text: "No Selection"
            color: Theme.tertiaryLabel
            font { family: Theme.fontUi; pixelSize: 13 }
        }
        Field { visible: !!inspector.path; label: "Name"; value: inspector.fileName }
        Field { visible: !!inspector.path; label: "Type"; value: inspector.fileType }
        Field {
            visible: !!inspector.path
            label: "Location"
            value: inspector.app.project && inspector.path.startsWith(inspector.app.project.root)
                ? (inspector.path.slice(inspector.app.project.root.length + 1).split("/").slice(0, -1).join("/") || "Project root")
                : ""
        }
        Field { visible: !!inspector.path; label: "Full Path"; value: inspector.path }

        Rectangle { width: parent.width; height: 1; color: Theme.separator; visible: !!inspector.editor }
        SidebarSection { visible: !!inspector.editor; text: "Text Settings"; topSpacing: 2; leftPadding: 0 }
        Row {
            visible: !!inspector.editor
            spacing: 8
            Text { width: 84; anchors.verticalCenter: parent.verticalCenter; text: "Indent Using"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 12 } }
            PopUpButton {
                options: ["Spaces", "Tabs"]
                current: inspector.editor && !inspector.editor.insertSpaces ? 1 : 0
                menuParent: inspector.menuParent
                onPicked: (i) => inspector.editor.insertSpaces = i === 0
            }
        }
        Row {
            visible: !!inspector.editor
            spacing: 8
            Text { width: 84; anchors.verticalCenter: parent.verticalCenter; text: "Tab Width"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 12 } }
            PopUpButton {
                options: ["2", "3", "4", "8"]
                current: inspector.editor ? Math.max(0, ["2", "3", "4", "8"].indexOf(String(inspector.editor.tabWidth))) : 2
                menuParent: inspector.menuParent
                onPicked: (i) => inspector.editor.tabWidth = [2, 3, 4, 8][i]
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.separator }
        Row {
            spacing: 6
            Symbol { name: "hammer"; size: 15; tone: "accent"; anchors.verticalCenter: parent.verticalCenter }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Project"
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
            }
        }
        Field { label: "Name"; value: inspector.app.project ? inspector.app.project.name : "" }
        Column {
            spacing: 4
            Text { text: "Product Type"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
            PopUpButton {
                options: ["App", "Command Line Tool", "Library"]
                current: inspector.app.project ? Math.max(0, ["app", "tool", "library"].indexOf(inspector.app.project.kind)) : 0
                menuParent: inspector.menuParent
                onPicked: (i) => {
                    const kind = ["app", "tool", "library"][i]
                    inspector.app.project = Object.assign({}, inspector.app.project, { kind: kind })
                    inspector.backend.call("saveMeta", { kind: kind, bundleId: bundleField.text })
                }
            }
        }
        Column {
            width: parent.width
            spacing: 4
            Text { text: "Bundle Identifier"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
            TextField {
                id: bundleField
                width: parent.width
                height: 28
                placeholder: "com.example.app"
                text: inspector.app.project ? inspector.app.project.bundleId : ""
                onAccepted: inspector.backend.call("saveMeta", { kind: inspector.app.project.kind, bundleId: text })
            }
        }
        Field { label: "Swift"; value: inspector.app.swiftVersion || (inspector.app.swiftPath ? inspector.app.swiftPath : "Not found") }
    }
}
