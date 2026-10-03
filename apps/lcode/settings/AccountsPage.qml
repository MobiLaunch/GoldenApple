// Settings ▸ Accounts: who you are in source control (git's global identity).
import QtQuick
import "../../lib"
import "../../lib/theme"

Page {
    id: page
    property var identity: ({})
    property bool gitInstalled: true
    property string saved: ""

    function load() {
        page.backend.call("gitIdentity", {}, (r) => {
            if (!r.ok) return
            page.gitInstalled = r.installed
            page.identity = r.identity
        })
    }
    function save(key, value) {
        page.backend.call("gitIdentity", { values: { [key]: value } }, (r) => {
            if (!r.ok) return
            page.identity = r.identity
            page.saved = "Saved to your global Git configuration."
        })
    }
    Component.onCompleted: load()

    Row {
        spacing: 14
        Rectangle {
            width: 52; height: 52
            radius: 26
            gradient: Gradient {
                GradientStop { position: 0; color: "#8e8e93" }
                GradientStop { position: 1; color: "#5a5a5f" }
            }
            Text {
                anchors.centerIn: parent
                text: (page.identity.name || "?").split(/\s+/).filter((w) => w).slice(0, 2).map((w) => w[0].toUpperCase()).join("")
                color: "white"
                font { family: Theme.fontUi; pixelSize: 20; weight: Font.DemiBold }
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                text: page.identity.name || "No Name Set"
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 15; weight: Font.DemiBold }
            }
            Text {
                text: page.gitInstalled ? (page.identity.email || "Set your name and email to commit") : "Git isn't installed: sudo pacman -S git"
                color: page.gitInstalled ? Theme.secondaryLabel : "#ff453a"
                font { family: Theme.fontUi; pixelSize: 12 }
            }
        }
    }
    FormGap {}
    SidebarSection { text: "Source Control"; leftPadding: 0; topSpacing: 0 }
    FormRow {
        label: "Author Name"
        SettingField {
            enabled: page.gitInstalled
            value: page.identity.name || ""
            placeholder: "Your Name"
            onCommitted: (v) => page.save("name", v)
        }
    }
    FormRow {
        label: "Author Email"
        SettingField {
            enabled: page.gitInstalled
            value: page.identity.email || ""
            placeholder: "you@example.com"
            onCommitted: (v) => page.save("email", v)
        }
    }
    FormRow {
        label: "Default Branch"
        detail: page.saved || "Used for every repository on this computer (git config --global), and the “Created by” line of new files."
        SettingField {
            enabled: page.gitInstalled
            value: page.identity.defaultBranch || ""
            placeholder: "main"
            onCommitted: (v) => page.save("defaultBranch", v)
        }
    }
}
