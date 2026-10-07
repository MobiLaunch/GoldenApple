//@ pragma AppId org.goldengate.Clock
import Quickshell
import Quickshell.Io
import QtQuick
import "lib"
import "lib/theme"

ShellRoot {
    AppWindow {
        id: win
        title: "Clock"
        implicitWidth: 760
        implicitHeight: 540
        minimumSize: Qt.size(620, 440)
        background: Theme.contentBg

        toolbarCenter: Segmented {
            id: tabs
            anchors.verticalCenter: parent.verticalCenter
            options: ["World Clock", "Alarm", "Stopwatch", "Timer"]
            current: clock.page
            onPicked: (i) => clock.page = i
        }

        Item {
            id: clock
            anchors.fill: parent

            property int page: 0
            property var world: []
            property bool stopwatchRunning: false
            property double stopwatchStarted: 0
            property double stopwatchBase: 0
            property double stopwatchElapsed: 0
            property int timerSeconds: 300
            property int timerRemaining: timerSeconds
            property bool timerRunning: false
            property double timerDeadline: 0
            property string alarmTime: "07:00"
            property string alarmMessage: "Alarm"
            property bool alarmDaily: false
            property var alarms: []
            property string notice: ""
            property bool noticeBad: false
            property bool busy: helper.running
            // Alarms and the timer live in the user's systemd (clock/helper.py):
            // they go off with Clock closed, and Clock shows them when it opens.
            readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("clock/helper.py").toString().replace("file://", ""))

            function formatDuration(seconds, tenths) {
                const value = Math.max(0, seconds)
                const h = Math.floor(value / 3600)
                const m = Math.floor((value % 3600) / 60)
                const s = Math.floor(value % 60)
                const fraction = Math.floor((value - Math.floor(value)) * 10)
                return (h ? String(h).padStart(2, "0") + ":" : "")
                    + String(m).padStart(2, "0") + ":"
                    + String(s).padStart(2, "0")
                    + (tenths ? "." + fraction : "")
            }

            function toggleStopwatch() {
                if (stopwatchRunning) {
                    stopwatchBase = stopwatchElapsed
                    stopwatchRunning = false
                } else {
                    stopwatchStarted = Date.now()
                    stopwatchRunning = true
                }
            }

            function resetStopwatch() {
                stopwatchRunning = false
                stopwatchBase = 0
                stopwatchElapsed = 0
            }

            // Runs one helper command; `done` gets its reply once it's in.
            property var queue: []
            function call(args, done) {
                queue = queue.concat([{ args: args, done: done ?? null }])
                if (!helper.running) callNext()
            }
            function callNext() {
                if (!queue.length) return
                helper.current = queue[0]
                queue = queue.slice(1)
                helper.command = ["python3", helperPath].concat(helper.current.args)
                helper.running = true
            }
            function say(text, bad) { notice = text; noticeBad = !!bad }

            function applyStatus(r) {
                alarms = r.alarms ?? []
                const t = r.timer ?? {}
                if (t.seconds) timerSeconds = t.seconds
                if (t.deadline) {
                    timerDeadline = t.deadline * 1000
                    timerRemaining = Math.max(0, Math.ceil((timerDeadline - Date.now()) / 1000))
                    timerRunning = true
                } else {
                    timerRunning = false
                    timerRemaining = t.remaining !== undefined ? t.remaining : timerSeconds
                }
            }
            function refresh() { call(["status"], (r) => { if (r.ok) applyStatus(r) }) }

            function toggleTimer() {
                if (timerRunning)
                    call(["timer-pause"], (r) => r.ok ? applyStatus({ alarms: alarms, timer: r.timer }) : say(r.error, true))
                else if (timerRemaining > 0)
                    call(["timer-start", String(timerRemaining)], (r) => {
                        if (r.ok) { applyStatus({ alarms: alarms, timer: r.timer }); say("") }
                        else say(r.error, true)
                    })
            }

            function resetTimer() {
                call(["timer-cancel"], (r) => {
                    timerRunning = false
                    timerRemaining = timerSeconds
                })
            }

            function scheduleAlarm() {
                const t = alarmTime.trim()
                call(["alarm-add", t, alarmMessage || "Alarm"].concat(alarmDaily ? ["daily"] : []), (r) => {
                    if (!r.ok) { say(r.error, true); return }
                    say((alarmDaily ? "Alarm set for " + t + " every day." : "Alarm set for " + t + "."), false)
                    refresh()
                })
            }
            function removeAlarm(id) {
                call(["alarm-remove", id], (r) => { if (!r.ok) say(r.error, true); refresh() })
            }

            Component.onCompleted: refresh()

            // Only while the stopwatch or a timer runs (20 times a second, for
            // the stopwatch's hundredths).
            Timer {
                interval: 50
                running: clock.stopwatchRunning || clock.timerRunning
                repeat: true
                onTriggered: {
                    if (clock.stopwatchRunning)
                        clock.stopwatchElapsed = clock.stopwatchBase + (Date.now() - clock.stopwatchStarted) / 1000
                    if (clock.timerRunning) {
                        clock.timerRemaining = Math.max(0, Math.ceil((clock.timerDeadline - Date.now()) / 1000))
                        if (clock.timerRemaining <= 0) {
                            // The notification comes from the timer's own unit.
                            clock.timerRunning = false
                            clock.timerRemaining = clock.timerSeconds
                        }
                    }
                }
            }

            Timer {
                interval: 30000
                repeat: true
                running: true
                triggeredOnStart: true
                onTriggered: if (!worldProc.running) worldProc.running = true
            }

            Process {
                id: worldProc
                command: ["sh", "-c",
                    "printf 'Cupertino\\t'; TZ=America/Los_Angeles date '+%H:%M|%a %b %-d'; " +
                    "printf 'New York\\t'; TZ=America/New_York date '+%H:%M|%a %b %-d'; " +
                    "printf 'London\\t'; TZ=Europe/London date '+%H:%M|%a %b %-d'; " +
                    "printf 'Tokyo\\t'; TZ=Asia/Tokyo date '+%H:%M|%a %b %-d'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        clock.world = text.split("\n").filter((line) => line.includes("\t")).map((line) => {
                            const parts = line.split("\t")
                            const t = parts[1].split("|")
                            return { city: parts[0], time: t[0], date: t[1] ?? "" }
                        })
                    }
                }
            }

            Process {
                id: helper
                property var current: null
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) {}
                        const c = helper.current
                        if (c && c.done) c.done(r ?? { ok: false, error: "Clock's helper didn't answer." })
                    }
                }
                onExited: Qt.callLater(clock.callNext)
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.contentBg
            }

            Column {
                visible: clock.page === 0
                anchors { fill: parent; margins: 34 }
                spacing: 16

                Text {
                    text: "World Clock"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 28; weight: Font.Bold }
                }

                Repeater {
                    model: clock.world
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 72
                        radius: 14
                        color: Theme.dark ? "#0dffffff" : "#07000000"
                        border { width: 0.5; color: Theme.separator }

                        Column {
                            x: 16
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: modelData.city
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: 15; weight: Font.DemiBold }
                            }
                            Text {
                                text: modelData.date
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: 11 }
                            }
                        }

                        Text {
                            anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                            text: modelData.time
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: 30; weight: Font.Light }
                        }
                    }
                }
            }

            Column {
                visible: clock.page === 1
                anchors.centerIn: parent
                width: Math.min(440, parent.width - 60)
                spacing: 16

                Symbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "bell"
                    size: 48
                    tone: "accent"
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Set an Alarm"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 24; weight: Font.Bold }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Alarms go off with Clock closed, and one missed while the computer was off goes off when you next sign in."
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 12 }
                }
                Row {
                    width: parent.width
                    spacing: 8
                    TextField {
                        objectName: "clockAlarmTime"
                        width: 90
                        placeholder: "07:30"
                        text: clock.alarmTime
                        onTextChanged: clock.alarmTime = text.replace(/[^0-9:]/g, "")
                    }
                    TextField {
                        width: parent.width - 98
                        placeholder: "Alarm name"
                        text: clock.alarmMessage
                        onTextChanged: clock.alarmMessage = text
                    }
                }
                Checkbox {
                    text: "Every day"
                    checked: clock.alarmDaily
                    onToggled: (on) => clock.alarmDaily = on
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: clock.busy ? "Setting…" : "Set Alarm"
                    prominent: true
                    enabled: /^([01]\d|2[0-3]):[0-5]\d$/.test(clock.alarmTime) && !clock.busy
                    onClicked: clock.scheduleAlarm()
                }
                Repeater {
                    model: clock.alarms
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 46
                        radius: 12
                        color: Theme.dark ? "#0dffffff" : "#07000000"
                        border { width: 0.5; color: Theme.separator }
                        Text {
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.time
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: 20; weight: Font.Light }
                        }
                        Text {
                            x: 84; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 84 - 90
                            elide: Text.ElideRight
                            text: modelData.name + (modelData.daily ? " · every day" : "")
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 12 }
                        }
                        Button {
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: "Delete"
                            destructive: true
                            onClicked: clock.removeAlarm(modelData.id)
                        }
                    }
                }
                Text {
                    objectName: "clockNotice"
                    visible: !!clock.notice
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: clock.notice
                    color: clock.noticeBad ? "#ff453a" : Theme.accent
                    font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium }
                }
            }

            Column {
                visible: clock.page === 2
                anchors.centerIn: parent
                width: 420
                spacing: 24

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: clock.formatDuration(clock.stopwatchElapsed, true)
                    color: Theme.label
                    font { family: "JetBrains Mono"; pixelSize: 54; weight: Font.Light }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12
                    Button {
                        text: clock.stopwatchRunning ? "Stop" : "Start"
                        prominent: !clock.stopwatchRunning
                        destructive: clock.stopwatchRunning
                        onClicked: clock.toggleStopwatch()
                    }
                    Button {
                        text: "Reset"
                        enabled: clock.stopwatchElapsed > 0
                        onClicked: clock.resetStopwatch()
                    }
                }
            }

            Column {
                visible: clock.page === 3
                anchors.centerIn: parent
                width: 460
                spacing: 22

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: clock.formatDuration(clock.timerRemaining, false)
                    color: Theme.label
                    font { family: "JetBrains Mono"; pixelSize: 56; weight: Font.Light }
                }

                ProgressBar {
                    width: 360
                    anchors.horizontalCenter: parent.horizontalCenter
                    value: clock.timerSeconds > 0 ? 1 - clock.timerRemaining / clock.timerSeconds : 0
                }

                Row {
                    visible: !clock.timerRunning
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Button {
                        text: "− 1 min"
                        onClicked: {
                            clock.timerSeconds = Math.max(60, clock.timerSeconds - 60)
                            clock.timerRemaining = clock.timerSeconds
                        }
                    }
                    Button {
                        text: "+ 1 min"
                        onClicked: {
                            clock.timerSeconds += 60
                            clock.timerRemaining = clock.timerSeconds
                        }
                    }
                    Button {
                        text: "+ 5 min"
                        onClicked: {
                            clock.timerSeconds += 300
                            clock.timerRemaining = clock.timerSeconds
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12
                    Button {
                        text: clock.timerRunning ? "Pause" : "Start"
                        prominent: !clock.timerRunning
                        onClicked: clock.toggleTimer()
                    }
                    Button {
                        text: "Reset"
                        onClicked: clock.resetTimer()
                    }
                }
                Text {
                    visible: clock.noticeBad && !!clock.notice
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: clock.notice
                    color: "#ff453a"
                    font { family: Theme.fontUi; pixelSize: 12 }
                }
                Text {
                    visible: clock.timerRunning
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "The timer keeps going if you close Clock."
                    color: Theme.tertiaryLabel
                    font { family: Theme.fontUi; pixelSize: 11 }
                }
            }
        }
    }
}
