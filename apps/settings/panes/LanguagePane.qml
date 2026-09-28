// Language & Region: the system language and formats, from locale settings.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    property string lang: ""
    Component.onCompleted: sys.sh("localectl status | sed -n 's/.*LANG=//p' | head -n1", (o) => lang = o.trim() || (Quickshell.env("LANG") ?? "").split(".")[0])
    Group {
        SetRow { title: "Preferred language"; Text { text: Qt.locale(pane.lang || Qt.locale().name).nativeLanguageName || pane.lang; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 13 } } }
        SetRow { title: "Region"; Text { text: Qt.locale(pane.lang || Qt.locale().name).nativeTerritoryName; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 13 } } }
        SetRow { title: "Measurement system"; Text { text: Qt.locale().measurementSystem === Locale.MetricSystem ? "Metric" : "US"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 13 } } }
        SetRow { title: "Date format"; Text { text: new Date().toLocaleDateString(Qt.locale(), Locale.ShortFormat); color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 13 } } }
    }
    Text {
        width: parent.width; wrapMode: Text.WordWrap
        text: "To change the system language, set LANG with: sudo localectl set-locale LANG=en_GB.UTF-8"
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: 11 }
    }
}
