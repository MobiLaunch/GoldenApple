//@ pragma AppId org.goldengate.Calendar
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "lib"
import "lib/theme"

ShellRoot {
    AppWindow {
        id: win
        title: "Calendar"
        implicitWidth: 960
        implicitHeight: 680
        minimumSize: Qt.size(760, 520)
        sidebarWidth: 220
        fullSizeContent: true
        background: Theme.contentBg

        toolbarSidebar: [
            ToolbarButton {
                round: true
                symbol: "calendar"
                onClicked: cal.goToday()
            }
        ]

        toolbarItems: [
            Row {
                x: win.contentX + 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                ToolbarPill {
                    ToolbarButton { symbol: "chevron-left"; onClicked: cal.shiftMonth(-1) }
                    ToolbarButton { symbol: "chevron-right"; onClicked: cal.shiftMonth(1) }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(cal.visibleMonth, "MMMM yyyy")
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
                }
            },
            Row {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8

                ToolbarButton {
                    round: true
                    symbol: "plus"
                    onClicked: cal.openAdd()
                }
            }
        ]

        sidebar: [
            Text {
                width: parent.width - 12
                x: 8
                text: "Selected Day"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold }
            },
            Column {
                y: 26
                width: parent.width
                spacing: 8

                Text {
                    width: parent.width - 16
                    x: 8
                    text: Qt.formatDate(cal.selectedDate, "dddd")
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 18; weight: Font.Bold }
                }
                Text {
                    width: parent.width - 16
                    x: 8
                    text: Qt.formatDate(cal.selectedDate, "MMMM d, yyyy")
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 12 }
                }

                Item { width: 1; height: 6 }

                Repeater {
                    model: cal.selectedEvents
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 58
                        radius: 10
                        color: Theme.dark ? "#10ffffff" : "#07000000"
                        border { width: 0.5; color: Theme.separator }

                        Rectangle {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 4
                            height: 36
                            radius: 2
                            color: Theme.accent
                        }

                        Column {
                            x: 20
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 58
                            spacing: 2

                            Text {
                                width: parent.width
                                text: modelData.title
                                elide: Text.ElideRight
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                            }
                            Text {
                                width: parent.width
                                text: modelData.time || "All day"
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: 10 }
                            }
                        }

                        ToolbarButton {
                            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            round: true
                            symbol: "trash"
                            onClicked: cal.deleteEvent(modelData.id)
                        }
                    }
                }

                EmptyState {
                    visible: cal.selectedEvents.length === 0
                    width: parent.width
                    height: 170
                    symbol: "calendar"
                    title: "No Events"
                    text: "Nothing is scheduled for this day."
                }
            }
        ]

        Item {
            id: cal
            anchors.fill: parent

            readonly property string helper: Qt.resolvedUrl("calendar/helper.py").toString().replace("file://", "")
            property date today: new Date()
            property date visibleMonth: new Date(today.getFullYear(), today.getMonth(), 1)
            property date selectedDate: new Date(today.getFullYear(), today.getMonth(), today.getDate())
            property var events: []
            property bool loading: true
            property string error: ""

            property string draftTitle: ""
            property string draftDate: Qt.formatDate(selectedDate, "yyyy-MM-dd")
            property string draftTime: ""
            property string draftCalendar: "Home"

            readonly property string selectedKey: Qt.formatDate(selectedDate, "yyyy-MM-dd")
            readonly property var selectedEvents: events.filter((event) => event.date === selectedKey)
            readonly property int year: visibleMonth.getFullYear()
            readonly property int month: visibleMonth.getMonth()
            readonly property int firstWeekday: new Date(year, month, 1).getDay()
            readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()

            function shiftMonth(delta) {
                visibleMonth = new Date(year, month + delta, 1)
            }

            function goToday() {
                today = new Date()
                visibleMonth = new Date(today.getFullYear(), today.getMonth(), 1)
                selectedDate = new Date(today.getFullYear(), today.getMonth(), today.getDate())
            }

            function selectDay(day) {
                if (day < 1 || day > daysInMonth)
                    return
                selectedDate = new Date(year, month, day)
            }

            function eventCount(day) {
                const key = Qt.formatDate(new Date(year, month, day), "yyyy-MM-dd")
                return events.filter((event) => event.date === key).length
            }

            function openAdd() {
                draftTitle = ""
                draftDate = selectedKey
                draftTime = ""
                addDialog.visible = true
                Qt.callLater(() => titleField.input.forceActiveFocus())
            }

            function addEvent() {
                if (!draftTitle.trim())
                    return
                addProc.stdinEnabled = true
                addProc.running = true
            }

            function deleteEvent(id) {
                if (deleteProc.running)
                    return
                deleteProc.command = ["python3", helper, "delete", id]
                deleteProc.running = true
            }

            function reload() {
                if (!loadProc.running)
                    loadProc.running = true
            }

            Component.onCompleted: reload()

            Process {
                id: loadProc
                command: ["python3", cal.helper, "list"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                cal.events = r.events ?? []
                                cal.error = ""
                            } else {
                                cal.error = r.error ?? "Calendar data could not be read."
                            }
                        } catch (e) {
                            cal.error = "Calendar data could not be read."
                        }
                    }
                }
                onExited: cal.loading = false
            }

            Process {
                id: addProc
                command: ["python3", cal.helper, "add"]
                stdinEnabled: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                addDialog.visible = false
                                cal.reload()
                            } else {
                                cal.error = r.error ?? "The event could not be saved."
                            }
                        } catch (e) {
                            cal.error = "The event could not be saved."
                        }
                    }
                }
                onStarted: {
                    write(JSON.stringify({
                        title: cal.draftTitle.trim(),
                        date: cal.draftDate,
                        time: cal.draftTime.trim(),
                        calendar: cal.draftCalendar
                    }))
                    stdinEnabled = false
                }
                onExited: stdinEnabled = true
            }

            Process {
                id: deleteProc
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok)
                                cal.reload()
                            else
                                cal.error = r.error ?? "The event could not be deleted."
                        } catch (e) {
                            cal.error = "The event could not be deleted."
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.contentBg
            }

            Column {
                anchors { fill: parent; leftMargin: 24; rightMargin: 24; topMargin: 16; bottomMargin: 18 }
                spacing: 8

                Row {
                    width: parent.width
                    height: 26
                    Repeater {
                        model: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                        delegate: Text {
                            required property var modelData
                            width: parent.width / 7
                            height: parent.height
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: modelData
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold }
                        }
                    }
                }

                Grid {
                    id: monthGrid
                    width: parent.width
                    height: parent.height - 34
                    columns: 7
                    rows: 6
                    spacing: 0

                    Repeater {
                        model: 42

                        delegate: Item {
                            id: dayCell
                            required property int index
                            readonly property int day: index - cal.firstWeekday + 1
                            readonly property bool valid: day >= 1 && day <= cal.daysInMonth
                            readonly property date cellDate: new Date(cal.year, cal.month, Math.max(1, day))
                            readonly property bool today: valid
                                && day === cal.today.getDate()
                                && cal.month === cal.today.getMonth()
                                && cal.year === cal.today.getFullYear()
                            readonly property bool selected: valid
                                && day === cal.selectedDate.getDate()
                                && cal.month === cal.selectedDate.getMonth()
                                && cal.year === cal.selectedDate.getFullYear()
                            readonly property int count: valid ? cal.eventCount(day) : 0

                            width: monthGrid.width / 7
                            height: monthGrid.height / 6

                            Rectangle {
                                anchors { fill: parent; margins: 3 }
                                radius: 12
                                color: dayCell.selected
                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                    : dayHover.hovered && dayCell.valid
                                        ? (Theme.dark ? "#0dffffff" : "#07000000")
                                        : "transparent"
                                border {
                                    width: dayCell.today ? 1.5 : 0.5
                                    color: dayCell.today ? "#ff3b30" : Theme.separator
                                }

                                Text {
                                    x: 10
                                    y: 8
                                    text: dayCell.valid ? dayCell.day : ""
                                    color: dayCell.today ? "#ff3b30" : Theme.label
                                    font {
                                        family: Theme.fontUi
                                        pixelSize: 13
                                        weight: dayCell.today || dayCell.selected ? Font.DemiBold : Font.Normal
                                    }
                                }

                                Column {
                                    x: 10
                                    y: 34
                                    width: parent.width - 20
                                    spacing: 4

                                    Repeater {
                                        model: Math.min(3, dayCell.count)
                                        delegate: Rectangle {
                                            width: parent.width
                                            height: 5
                                            radius: 2.5
                                            color: Theme.accent
                                            opacity: 0.8
                                        }
                                    }
                                }

                                Text {
                                    visible: dayCell.count > 3
                                    anchors { right: parent.right; rightMargin: 8; bottom: parent.bottom; bottomMargin: 6 }
                                    text: "+" + (dayCell.count - 3)
                                    color: Theme.secondaryLabel
                                    font { family: Theme.fontUi; pixelSize: 9 }
                                }
                            }

                            HoverHandler { id: dayHover }
                            TapHandler {
                                enabled: dayCell.valid
                                onTapped: cal.selectDay(dayCell.day)
                                onDoubleTapped: {
                                    cal.selectDay(dayCell.day)
                                    cal.openAdd()
                                }
                            }
                        }
                    }
                }
            }

            Glass {
                visible: !!cal.error
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
                width: Math.min(520, parent.width - 40)
                height: 50
                radius: 16
                tint: Theme.dark ? "#d02b1f24" : "#eefdf0f0"
                z: 40

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    text: cal.error
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: "#ff453a"
                    font { family: Theme.fontUi; pixelSize: 12 }
                }
            }

            Glass {
                id: addDialog
                parent: win.overlay
                visible: false
                anchors.centerIn: parent
                width: 420
                height: 270
                radius: 22
                tint: Theme.glassRegular.tint
                z: 100

                Column {
                    anchors { fill: parent; margins: 20 }
                    spacing: 12

                    Text {
                        text: "New Event"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 18; weight: Font.DemiBold }
                    }

                    TextField {
                        id: titleField
                        width: parent.width
                        placeholder: "Event name"
                        text: cal.draftTitle
                        onTextChanged: cal.draftTitle = text
                    }

                    Row {
                        width: parent.width
                        spacing: 10
                        TextField {
                            width: (parent.width - parent.spacing) / 2
                            placeholder: "YYYY-MM-DD"
                            text: cal.draftDate
                            onTextChanged: cal.draftDate = text
                        }
                        TextField {
                            width: (parent.width - parent.spacing) / 2
                            placeholder: "Time, e.g. 14:30"
                            text: cal.draftTime
                            onTextChanged: cal.draftTime = text
                        }
                    }

                    TextField {
                        width: parent.width
                        placeholder: "Calendar"
                        text: cal.draftCalendar
                        onTextChanged: cal.draftCalendar = text
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Button { text: "Cancel"; onClicked: addDialog.visible = false }
                        Button {
                            text: "Add"
                            prominent: true
                            enabled: cal.draftTitle.trim().length > 0
                            onClicked: cal.addEvent()
                        }
                    }
                }
            }
        }
    }
}
