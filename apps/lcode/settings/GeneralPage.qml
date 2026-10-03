// Settings ▸ General: appearance, startup, and new-project defaults.
import QtQuick
import "../../lib"
import "../../lib/theme"

Page {
    id: page

    FormRow {
        label: "Appearance"
        detail: "System follows Golden Gate's Light or Dark setting. Each appearance has its own editor theme (Themes)."
        Segmented {
            width: 260
            options: ["System", "Light", "Dark"]
            current: Math.max(0, ["system", "light", "dark"].indexOf(page.app.settings.appearance || "system"))
            onPicked: (i) => page.app.saveSettings({ appearance: ["system", "light", "dark"][i] })
        }
    }
    FormGap {}
    FormRow {
        label: "At Launch"
        labelHeight: 20
        Column {
            spacing: 8
            Checkbox {
                width: 440
                text: "Show the Welcome window"
                checked: page.app.settings.showWelcome !== false
                onToggled: (on) => page.app.saveSettings({ showWelcome: on })
            }
            Checkbox {
                width: 440
                text: "Reopen the files you had open in a project"
                checked: page.app.settings.reopenFiles !== false
                onToggled: (on) => page.app.saveSettings({ reopenFiles: on })
            }
        }
    }
    FormGap {}
    FormRow {
        label: "Organization Name"
        detail: "The copyright line in the header comment of new files."
        SettingField {
            value: page.app.settings.organizationName || ""
            placeholder: "Your name or company"
            onCommitted: (v) => page.app.saveSettings({ organizationName: v })
        }
    }
    FormRow {
        label: "Organization Identifier"
        detail: "Reverse-DNS, like com.example: new apps are identified as " + (page.app.settings.organizationIdentifier || "com.example") + ".MyApp."
        SettingField {
            value: page.app.settings.organizationIdentifier || ""
            placeholder: "com.example"
            onCommitted: (v) => page.app.saveSettings({ organizationIdentifier: v })
        }
    }
    FormRow {
        label: "New Projects Folder"
        detail: "Where New Project starts looking. Leave it empty for ~/Developer."
        SettingField {
            value: page.app.settings.projectsFolder || ""
            placeholder: "~/Developer"
            onCommitted: (v) => page.app.saveSettings({ projectsFolder: v })
        }
    }
}
