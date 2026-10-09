// Focus: Do Not Disturb, which the shell's notifications follow.
import Quickshell
import Quickshell.Io
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."
import "../../lib/FocusPolicy.js" as Policy

Pane {
    id: pane
    objectName: "focusPane"
    headerSymbol: "moon"; headerTint: "#5e5ce6"; headerTitle: "Focus"
    headerText: "Silence interruptions for a while or on a schedule. Notifications still reach Notification Center, and the moon shows when Focus is on."
    readonly property var prefs: sys.prefs.focus ?? ({})
    readonly property bool dnd: status.active
    property bool saving: false
    property int duration: 1
    readonly property var durations: [15, 60, 120, 0]
    readonly property var schedule: Object.assign({enabled:false, days:[1,2,3,4,5], start:1320, end:420}, prefs.schedule ?? {})
    property var seen: ({})
    readonly property var apps: {
        const all = Object.assign({"org.goldengate.clock":{name:"Clock"}, "org.goldengate.calendar":{name:"Calendar"},
                                  "org.goldengate.mail":{name:"Mail"}, "org.goldengate.messages":{name:"Messages"}}, seen)
        const canonical = {}
        for (const key in all) canonical[Policy.canonicalApp(key)] = {key:Policy.canonicalApp(key), name:all[key].name || key}
        return Object.values(canonical).sort((a,b) => a.name.localeCompare(b.name))
    }
    FocusState { id: status; objectName: "focusState"; policy: pane.prefs }
    property Item focusedControl: null
    function revealControl(item) { focusedControl = item; focusReveal.restart() }
    onContentHeightChanged: focusReveal.restart()
    onHeightChanged: focusReveal.restart()
    Timer {
        id: focusReveal; interval: 0
        onTriggered: {
            const item = pane.focusedControl
            if (item?.activeFocus) pane.reveal(item.mapToItem(pane.contentItem, 0, 0).y, item.height)
        }
    }
    function reveal(y, itemHeight) {
        const top = y - 12, bottom = y + itemHeight + 12
        if (top < contentY) contentY = Math.max(0, top)
        else if (bottom > contentY + height) contentY = Math.min(Math.max(0, contentHeight - height), bottom - height)
    }
    function save(key, value) {
        if (saving) return
        saving = true
        sys.run(["gg-pref", "focus." + key, JSON.stringify(value)], (out, code, error) => {
            saving = false
            if (code !== 0) { sys.failed("Focus", error?.trim() || "the change couldn't be saved"); return }
            sys.prefs = sys.setIn(sys.prefs, ["focus"].concat(key.split(".")), value)
        })
    }
    function setSchedule(key, value) { save("schedule." + key, value) }
    function toggleDay(day, on) {
        const days = schedule.days.filter((d) => d !== day)
        if (on) days.push(day)
        setSchedule("days", days.sort())
    }
    function timeOptions() {
        return Array.from({length:48}, (_,i) => String(Math.floor(i/2)).padStart(2,"0") + ":" + (i%2 ? "30" : "00"))
    }
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/golden-gate/notifiers.json"
        printErrors: false; watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { pane.seen = JSON.parse(text()) } catch (e) { pane.seen = ({}) } }
    }
    Group {
        title: "Do Not Disturb"
        SetRow {
            title: "Do Not Disturb"; symbol: "moon"; symbolTint: "#5e5ce6"
            subtitle: pane.saving ? "Saving Focus…" : status.summary
            Switch {
                id: focusToggle
                objectName: "focusSwitch"
                onActiveFocusChanged: if (activeFocus) pane.revealControl(focusToggle)
                enabled: !pane.saving
                checked: pane.dnd
                onToggled: (on) => { pane.save("session", on ? status.start(pane.durations[pane.duration]) : status.stop()); checked = Qt.binding(() => pane.dnd) }
            }
        }
        SetRow {
            title: "Turn on for"
            subtitle: "Choose a duration, then turn on Do Not Disturb."
            PopUpButton {
                id: durationPopup
                objectName: "focusDuration"
                onActiveFocusChanged: if (activeFocus) pane.revealControl(durationPopup)
                enabled: !pane.saving
                menuParent: pane.nav.overlay
                options: ["15 minutes", "1 hour", "2 hours", "Until turned off"]
                current: pane.duration
                onPicked: (i) => pane.duration = i
            }
        }
        SetRow {
            visible: pane.dnd
            title: "Restart with chosen duration"
            subtitle: "Use this to change the end time of the current session."
            Button {
                id: restartButton
                text: "Restart"; enabled: !pane.saving
                onActiveFocusChanged: if (activeFocus) pane.revealControl(restartButton)
                onClicked: pane.save("session", status.start(pane.durations[pane.duration]))
            }
        }
    }
    Group {
        title: "Allowed Interruptions"
        Repeater {
            model: pane.apps
            delegate: SetRow {
                required property var modelData
                title: modelData.name
                subtitle: "Keep this app's enabled banners and sounds during Focus."
                Switch {
                    id: allowedSwitch
                    objectName: "focusAllow:" + modelData.key
                    onActiveFocusChanged: if (activeFocus) pane.revealControl(allowedSwitch)
                    enabled: !pane.saving
                    checked: pane.prefs.allowedApps?.[Policy.appKey(modelData.key)] === true
                    onToggled: (on) => { pane.save("allowedApps." + Policy.appKey(modelData.key), on); checked = Qt.binding(() => pane.prefs.allowedApps?.[Policy.appKey(modelData.key)] === true) }
                }
            }
        }
        SetRow {
            title: "Allow critical alerts"
            subtitle: "Allow alerts that any app marks as critical. Disabled app notifications stay disabled."
            Switch {
                id: criticalSwitch
                enabled: !pane.saving; checked: pane.prefs.allowCritical === true
                onActiveFocusChanged: if (activeFocus) pane.revealControl(criticalSwitch)
                onToggled: (on) => { pane.save("allowCritical", on); checked = Qt.binding(() => pane.prefs.allowCritical === true) }
            }
        }
    }
    Group {
        title: "Weekly Schedule"
        SetRow {
            title: "Use a schedule"
            subtitle: "Uses this computer's local time. Turning Focus off pauses only the current scheduled period."
            Switch {
                id: scheduleToggle
                objectName: "focusScheduleSwitch"
                onActiveFocusChanged: if (activeFocus) pane.revealControl(scheduleToggle)
                checked: pane.schedule.enabled; enabled: !pane.saving
                onToggled: (on) => {
                    // Save the displayed defaults with the first enable, so
                    // no incomplete schedule can look enabled without acting.
                    if (!pane.prefs.schedule) pane.save("schedule", Object.assign({}, pane.schedule, {enabled:on}))
                    else pane.setSchedule("enabled", on)
                    checked = Qt.binding(() => pane.schedule.enabled)
                }
            }
        }
        Column {
            width: parent.width
            visible: pane.schedule.enabled
            spacing: 10
            Text {
                x: 14; width: parent.width - 28
                text: "Start days"; color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
            }
            Flow {
                x: 14; width: parent.width - 28; spacing: 10
                Repeater {
                    model: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
                    delegate: Checkbox {
                        id: dayBox
                        required property string modelData
                        required property int index
                        objectName: "focusDay:" + index
                        onActiveFocusChanged: if (activeFocus) pane.revealControl(dayBox)
                        width: Math.min(Theme.fh(124), parent.width)
                        text: modelData; checked: pane.schedule.days.includes(index); enabled: !pane.saving
                        onToggled: (on) => { pane.toggleDay(index, on); checked = Qt.binding(() => pane.schedule.days.includes(index)) }
                    }
                }
            }
            SetRow {
                title: "From"
                PopUpButton {
                    id: startPopup
                    objectName: "focusStart"
                    onActiveFocusChanged: if (activeFocus) pane.revealControl(startPopup)
                    menuParent: pane.nav.overlay; enabled: !pane.saving
                    options: pane.timeOptions(); current: Math.floor(pane.schedule.start / 30)
                    onPicked: (i) => { pane.setSchedule("start", i * 30); current = Qt.binding(() => Math.floor(pane.schedule.start / 30)) }
                }
            }
            SetRow {
                title: "Until"
                PopUpButton {
                    id: endPopup
                    objectName: "focusEnd"
                    onActiveFocusChanged: if (activeFocus) pane.revealControl(endPopup)
                    menuParent: pane.nav.overlay; enabled: !pane.saving
                    options: pane.timeOptions(); current: Math.floor(pane.schedule.end / 30)
                    onPicked: (i) => { pane.setSchedule("end", i * 30); current = Qt.binding(() => Math.floor(pane.schedule.end / 30)) }
                }
            }
            Text {
                x: 14; width: parent.width - 28; bottomPadding: 14; wrapMode: Text.WordWrap
                text: !pane.schedule.days.length ? "Choose at least one start day to activate the schedule."
                    : pane.schedule.start === pane.schedule.end ? "Choose different start and end times to activate the schedule."
                    : pane.schedule.end < pane.schedule.start ? "Ends the following morning, including after the last selected start day."
                    : "Focus turns on and off automatically on the selected days."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
            }
        }
    }
}
