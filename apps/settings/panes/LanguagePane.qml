// Language & Region: change the installed system locale without leaving Settings.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    property string lang: ""
    property var locales: []
    property bool busy: false
    property string message: ""

    function baseLocale(value) {
        return String(value || "").split(".")[0].split("@")[0]
    }

    function localeLabel(value) {
        const base = baseLocale(value)
        if (!base || base === "C" || base === "POSIX")
            return value
        const locale = Qt.locale(base)
        const language = locale.nativeLanguageName || base
        const territory = locale.nativeTerritoryName
        return territory ? language + " — " + territory : language
    }

    function refresh() {
        sys.sh("localectl status | sed -n 's/.*LANG=//p' | head -n1", (o) => {
            pane.lang = o.trim() || (Quickshell.env("LANG") ?? "")
        })
        sys.sh("localectl list-locales 2>/dev/null || locale -a 2>/dev/null", (o) => {
            const values = [...new Set(o.split("\n").map((v) => v.trim()).filter((v) => v && v !== "C" && v !== "POSIX"))]
            pane.locales = values.sort((a, b) => pane.localeLabel(a).localeCompare(pane.localeLabel(b)))
        })
    }

    function setLocale(value) {
        if (!value || busy)
            return
        busy = true
        message = "Applying language…"
        sys.run(["localectl", "set-locale", "LANG=" + value], (out, code) => {
            busy = false
            if (code === 0) {
                lang = value
                message = "Language changed. It will be used fully after you sign out and back in."
            } else {
                message = out.trim() || "The system language could not be changed."
            }
        })
    }

    Component.onCompleted: refresh()

    Group {
        SetRow {
            title: "Preferred language"
            subtitle: pane.busy
                ? "Waiting for administrator authorization…"
                : "Applies to the login screen and your next session."
            PopUpButton {
                width: 260
                menuParent: pane.nav.overlay
                enabled: !pane.busy && pane.locales.length > 0
                options: pane.locales.map((value) => pane.localeLabel(value))
                current: {
                    const exact = pane.locales.indexOf(pane.lang)
                    if (exact >= 0) return exact
                    const base = pane.baseLocale(pane.lang)
                    return Math.max(0, pane.locales.findIndex((value) => pane.baseLocale(value) === base))
                }
                onPicked: (i) => {
                    if (i >= 0 && i < pane.locales.length)
                        pane.setLocale(pane.locales[i])
                }
            }
        }
        SetRow {
            title: "Region"
            Text {
                text: Qt.locale(pane.baseLocale(pane.lang) || Qt.locale().name).nativeTerritoryName || "—"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 13 }
            }
        }
        SetRow {
            title: "Measurement system"
            Text {
                text: Qt.locale(pane.baseLocale(pane.lang) || Qt.locale().name).measurementSystem === Locale.MetricSystem ? "Metric" : "US"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 13 }
            }
        }
        SetRow {
            title: "Date format"
            Text {
                text: new Date().toLocaleDateString(Qt.locale(pane.baseLocale(pane.lang) || Qt.locale().name), Locale.ShortFormat)
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 13 }
            }
        }
    }

    Group {
        visible: !!pane.message
        SetRow {
            title: pane.message
        }
    }
}
