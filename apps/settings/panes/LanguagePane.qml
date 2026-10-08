// Language & Region: the language (the system locale, LANG) and the region's
// formats (dates, numbers, currency, measurement: LC_* for your account, as
// Setup Assistant saved them in region.json) are separate choices, so an
// English system with Swiss formats shows Swiss formats here.
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
    // The formats in use for new sessions: the saved ones, else the language's.
    readonly property string formats: sys.region.formats || baseLocale(lang)
    readonly property var formatLocales: [...new Set(locales.map((v) => baseLocale(v)).concat(sys.region.formats ? [sys.region.formats] : [])
        .filter((v) => /^[a-z]{2,3}_[A-Z]{2}$/.test(v)))]
        .sort((a, b) => localeLabel(a).localeCompare(localeLabel(b)))

    function setFormats(value) {
        if (!value || busy) return
        busy = true
        message = "Saving region formats…"
        sys.regionRun(["set-formats", value, Qt.locale(value).nativeTerritoryName || ""], (ok, why) => {
            busy = false
            message = ok ? "Apps you open after you next sign in show dates, numbers and currency for " + localeLabel(value) + "."
                         : (why || "The region formats couldn't be saved.")
        })
    }

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

    Component.onCompleted: { refresh(); sys.refreshRegion() }

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
    }

    Group {
        SetRow {
            title: "Region"
            subtitle: "Dates, numbers, currency and measurement. Apps you open after you next sign in use them; CitronOS's own apps are in English."
            PopUpButton {
                objectName: "regionFormats"
                width: 260
                menuParent: pane.nav.overlay
                enabled: !pane.busy && pane.formatLocales.length > 0
                options: pane.formatLocales.map((value) => (Qt.locale(value).nativeTerritoryName || value) + " (" + pane.localeLabel(value) + ")")
                current: Math.max(0, pane.formatLocales.indexOf(pane.formats))
                onPicked: (i) => { if (i >= 0 && i < pane.formatLocales.length) pane.setFormats(pane.formatLocales[i]) }
            }
        }
        SetRow {
            title: "Measurement system"
            Text {
                objectName: "regionMeasurement"
                text: Qt.locale(pane.formats || Qt.locale().name).measurementSystem === Locale.MetricSystem ? "Metric" : "US"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
            }
        }
        SetRow {
            title: "Date format"
            Text {
                objectName: "regionDate"
                text: new Date(2026, 0, 31).toLocaleDateString(Qt.locale(pane.formats || Qt.locale().name), Locale.ShortFormat)
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
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
