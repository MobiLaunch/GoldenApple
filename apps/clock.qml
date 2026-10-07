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
            property string alarmMinutes: "10"
            property string alarmMessage: "Alarm"
            property string notice: ""

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

            function toggleTimer() {
                if (timerRunning) {
                    timerRemaining = Math.max(0, Math.ceil((timerDeadline - Date.now()) / 1000))
                    timerRunning = false
                } else if (timerRemaining > 0) {
                    timerDeadline = Date.now() + timerRemaining * 1000
                    timerRunning = true
                }
            }

            function resetTimer() {
                timerRunning = false
                timerRemaining = timerSeconds
            }

            function scheduleAlarm() {
                const minutes = Math.max(1, parseInt(alarmMinutes, 10) || 1)
                const unit = "golden-gate-alarm-" + Date.now()
                alarmProc.command = [
                    "systemd-run", "--user", "--quiet",
                    "--unit=" + unit,
                    "--on-active=" + minutes + "m",
                    "notify-send", "-u", "critical", "Clock", alarmMessage || "Alarm"
                ]
                alarmProc.running = true
                notice = "Alarm set for " + minutes + (minutes === 1 ? " minute from now." : " minutes from now.")
            }

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
                            clock.timerRunning = false
                            Quickshell.execDetached(["notify-send", "-u", "critical", "Clock", "Timer finished"])
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

            Process { id: alarmProc }

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
                    text: "Alarms are scheduled with your user session, so they keep counting even after Clock is closed."
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 12 }
                }
                TextField {
                    width: parent.width
                    placeholder: "Minutes from now"
                    text: clock.alarmMinutes
                    onTextChanged: clock.alarmMinutes = text.replace(/[^0-9]/g, "")
                }
                TextField {
                    width: parent.width
                    placeholder: "Alarm name"
                    text: clock.alarmMessage
                    onTextChanged: clock.alarmMessage = text
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Set Alarm"
                    prominent: true
                    enabled: parseInt(clock.alarmMinutes, 10) > 0
                    onClicked: clock.scheduleAlarm()
                }
                Text {
                    visible: !!clock.notice
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: clock.notice
                    color: Theme.accent
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
            }
        }
    }
}
