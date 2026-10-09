//@ pragma AppId org.goldengate.Calendar
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "lib"
import "lib/theme"
import "calendar/recurrence.js" as Recurrence

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
                    ToolbarButton { symbol: "chevron-left"; onClicked: cal.shiftRange(-1) }
                    ToolbarButton { symbol: "chevron-right"; onClicked: cal.shiftRange(1) }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: cal.rangeLabel
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.Bold }
                }
            },
            Row {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8

                ToolbarPill {
                    ToolbarButton {
                        text: "Month"
                        checked: cal.viewMode === "month"
                        onClicked: cal.changeView("month")
                    }
                    ToolbarButton {
                        text: "Week"
                        checked: cal.viewMode === "week"
                        onClicked: cal.changeView("week")
                    }
                    ToolbarButton {
                        text: "Day"
                        checked: cal.viewMode === "day"
                        onClicked: cal.changeView("day")
                    }
                }
                ToolbarButton {
                    round: true
                    symbol: "cloud"
                    Accessible.name: "CalDAV calendar sync and account"
                    onClicked: cal.openCalDav()
                }
                ToolbarButton {
                    round: true
                    symbol: "bell"
                    enabled: !cal.remindersPending
                    Accessible.name: cal.remindersEnabled ? "Turn Calendar reminders off" : "Turn Calendar reminders on"
                    onClicked: cal.toggleReminders()
                }
                ToolbarButton {
                    round: true
                    symbol: "plus"
                    enabled: !cal.broken
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
                font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold }
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
                    font { family: Theme.fontUi; pixelSize: Theme.fs(18); weight: Font.Bold }
                }
                Text {
                    width: parent.width - 16
                    x: 8
                    text: Qt.formatDate(cal.selectedDate, "MMMM d, yyyy")
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
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
                            width: parent.width - 120
                            spacing: 2

                            Text {
                                width: parent.width
                                text: modelData.title
                                elide: Text.ElideRight
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
                            }
                            Text {
                                width: parent.width
                                text: (modelData.time || "All day") + (modelData.remote ? " · CalDAV · Read-only" : "") + (modelData.repeat && modelData.repeat !== "never" ? " · " + Recurrence.summary(modelData) : "")
                                elide: Text.ElideRight
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(10) }
                            }
                        }

                        ToolbarButton {
                            anchors { right: parent.right; rightMargin: 66; verticalCenter: parent.verticalCenter }
                            round: true
                            symbol: "copy"
                            enabled: !modelData.remote && !cal.broken && !duplicateProc.running
                            Accessible.name: "Duplicate event"
                            onClicked: cal.duplicateEvent(modelData.id)
                        }
                        ToolbarButton {
                            anchors { right: parent.right; rightMargin: 36; verticalCenter: parent.verticalCenter }
                            round: true
                            symbol: "pencil"
                            enabled: !modelData.remote && !cal.broken
                            Accessible.name: "Edit event"
                            onClicked: cal.requestEdit(modelData)
                        }
                        ToolbarButton {
                            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            round: true
                            symbol: "trash"
                            enabled: !modelData.remote && !cal.broken && !deleteProc.running
                            Accessible.name: "Delete event"
                            onClicked: cal.requestDelete(modelData)
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
            readonly property string reminderHelper: Qt.resolvedUrl("calendar/reminders.py").toString().replace("file://", "")
            readonly property string calDavHelper: Qt.resolvedUrl("calendar/caldav.py").toString().replace("file://", "")
            property date today: new Date()
            property date visibleMonth: new Date(today.getFullYear(), today.getMonth(), 1)
            property date selectedDate: new Date(today.getFullYear(), today.getMonth(), today.getDate())
            property string viewMode: "month"
            property var events: []
            property bool loading: true
            property string error: ""
            property bool broken: false         // the store can't be read: nothing is saved over it
            property bool canRestore: false

            property string draftTitle: ""
            property string draftDate: Qt.formatDate(selectedDate, "yyyy-MM-dd")
            property string draftTime: ""
            property string draftCalendar: "Home"
            property string editingId: ""
            property var editingOriginal: ({})
            property string draftRepeat: "never"
            property string draftUntil: ""
            property int draftReminder: -1
            readonly property var reminderValues: [-1, 0, 5, 15, 60]
            property bool remindersEnabled: false
            property bool remindersPending: false
            property bool calDavConfigured: false
            property bool calDavPending: false
            property string calDavUrl: ""
            property string calDavUsername: ""
            property string calDavPassword: ""
            property string calDavMessage: ""
            readonly property var repeatOptions: ["never", "daily", "weekly", "monthly", "yearly"]
            property string deleteTarget: ""
            property string deleteTitle: ""
            property bool deleteIsSeries: false
            property string deleteOccurrence: ""
            property var deleteOriginal: ({})
            property bool editingOccurrence: false
            property string editingDate: ""
            property var pendingEdit: ({})
            property string resetOccurrenceDate: ""
            property var resetOriginal: ({})
            property string exceptionsMessage: ""
            readonly property var pendingSeries: events.find(e => e.id === pendingEdit.id) || ({})

            readonly property string selectedKey: Qt.formatDate(selectedDate, "yyyy-MM-dd")
            readonly property var agendaKeys: Recurrence.displayedDays(viewMode, selectedKey)
            readonly property string rangeLabel: viewMode === "month"
                ? Qt.formatDate(visibleMonth, "MMMM yyyy")
                : viewMode === "day" ? Qt.formatDate(selectedDate, "MMMM d, yyyy")
                : Qt.formatDate(new Date(Number(agendaKeys[0].slice(0,4)),
                        Number(agendaKeys[0].slice(5,7))-1, Number(agendaKeys[0].slice(8,10))), "MMM d")
                    + " – " + Qt.formatDate(new Date(Number(agendaKeys[6].slice(0,4)),
                        Number(agendaKeys[6].slice(5,7))-1, Number(agendaKeys[6].slice(8,10))), "MMM d, yyyy")
            readonly property var selectedEvents: Recurrence.occurrencesOn(events, selectedKey)
            readonly property int year: visibleMonth.getFullYear()
            readonly property int month: visibleMonth.getMonth()
            readonly property int firstWeekday: new Date(year, month, 1).getDay()
            readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()

            function changeView(mode) {
                if (mode !== "month" && mode !== "week" && mode !== "day")
                    return
                viewMode = mode
                visibleMonth = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1)
            }

            function shiftRange(delta) {
                if (viewMode === "month") {
                    visibleMonth = new Date(year, month + delta, 1)
                    selectedDate = new Date(year, month + delta, Math.min(
                        selectedDate.getDate(), new Date(year, month + delta + 1, 0).getDate()))
                } else {
                    const shift = viewMode === "week" ? delta * 7 : delta
                    selectedDate = new Date(selectedDate.getFullYear(), selectedDate.getMonth(),
                                            selectedDate.getDate() + shift)
                    visibleMonth = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1)
                }
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
                return Recurrence.occurrencesOn(events, key).length
            }

            function openAdd() {
                if (broken)
                    return
                draftTitle = ""
                draftDate = selectedKey
                draftTime = ""
                draftCalendar = "Home"
                editingId = ""
                editingOriginal = ({})
                draftRepeat = "never"
                draftUntil = ""
                draftReminder = -1
                error = ""
                addDialog.visible = true
                Qt.callLater(() => titleField.input.forceActiveFocus())
            }

            function requestEdit(event) {
                if (broken || addProc.running || !event || !event.id)
                    return
                if (event.repeat && event.repeat !== "never") {
                    pendingEdit = event
                    editScope.visible = true
                } else openEdit(event, false)
            }

            function openEdit(event, oneOccurrence) {
                if (broken || addProc.running || !event || !event.id)
                    return
                const original = events.find(e => e.id === event.id)
                if (!original) { error = "Refresh Calendar to edit this event."; return }
                editingId = event.id
                editingOriginal = JSON.parse(JSON.stringify(original))
                editingOccurrence = !!oneOccurrence
                editingDate = event.occurrenceDate || original.date
                draftTitle = editingOccurrence ? event.title : original.title
                draftDate = editingOccurrence ? (event.displayedDate || editingDate) : original.date
                draftTime = editingOccurrence ? (event.time || "") : (original.time || "")
                draftCalendar = editingOccurrence ? (event.calendar || "Home") : (original.calendar || "Home")
                draftRepeat = original.repeat || "never"
                draftUntil = original.until || ""
                draftReminder = editingOccurrence ? (event.reminder ?? original.reminder ?? -1) : (original.reminder ?? -1)
                error = ""
                addDialog.visible = true
                Qt.callLater(() => titleField.input.forceActiveFocus())
            }

            function addEvent() {
                if (!draftTitle.trim() || broken || addProc.running)
                    return
                addProc.command = editingId
                    ? (editingOccurrence ? ["python3", helper, "occurrence-edit", editingId, editingDate]
                                         : ["python3", helper, "edit", editingId])
                    : ["python3", helper, "add"]
                addProc.stdinEnabled = true
                addProc.running = true
            }

            function duplicateEvent(id) {
                if (broken || duplicateProc.running)
                    return
                duplicateProc.command = ["python3", helper, "duplicate", id]
                duplicateProc.running = true
            }

            function requestDelete(event) {
                if (broken || deleteProc.running || !event || !event.id)
                    return
                deleteTarget = event.id
                deleteTitle = event.title
                deleteIsSeries = event.repeat && event.repeat !== "never"
                deleteOccurrence = event.occurrenceDate || event.date
                const source = events.find(e => e.id === event.id)
                deleteOriginal = source ? JSON.parse(JSON.stringify(source)) : ({})
                deleteConfirm.visible = true
            }

            function deleteEvent(id) {
                if (deleteProc.running || skipProc.running)
                    return
                deleteProc.command = ["python3", helper, "delete", id]
                deleteProc.running = true
            }

            function skipOccurrence() {
                if (skipProc.running || deleteProc.running || !deleteOriginal.id)
                    return
                skipProc.command = ["python3", helper, "occurrence-skip", deleteTarget, deleteOccurrence]
                skipProc.stdinEnabled = true
                skipProc.running = true
            }

            function resetOccurrence(date) {
                if (resetProc.running || !pendingSeries.id) return
                resetOccurrenceDate = date
                resetOriginal = JSON.parse(JSON.stringify(pendingSeries))
                resetProc.command = ["python3", helper, "occurrence-reset", pendingSeries.id, date]
                resetProc.stdinEnabled = true
                resetProc.running = true
            }

            function restore() {
                if (!restoreProc.running)
                    restoreProc.running = true
            }

            function reload() {
                if (!loadProc.running)
                    loadProc.running = true
            }

            Component.onCompleted: { reload(); reminderStatus.running = true; calDavStatus.running = true }

            function toggleReminders() {
                if (remindersPending) return
                remindersPending = true
                reminderToggle.command = ["python3", reminderHelper, remindersEnabled ? "disable" : "enable"]
                reminderToggle.running = true
            }

            function openCalDav() {
                calDavMessage = ""
                calDavAccount.visible = true
                calDavStatus.running = true
            }

            function saveCalDav() {
                if (calDavPending || !calDavUrl.trim() || !calDavUsername.trim() || !calDavPassword)
                    return
                calDavPending = true
                calDavConfig.stdinEnabled = true
                calDavConfig.running = true
            }

            function syncCalDav() {
                if (calDavPending) return
                calDavPending = true
                calDavSync.running = true
            }

            function disconnectCalDav() {
                if (calDavPending) return
                calDavPending = true
                calDavDisconnect.running = true
            }

            Process {
                id: calDavStatus
                command: ["python3", cal.calDavHelper, "status"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) {}
                        if (r?.ok) {
                            cal.calDavConfigured = !!r.configured
                            if (r.configured) {
                                cal.calDavUrl = r.url || ""
                                cal.calDavUsername = r.username || ""
                            }
                        } else if (r?.error) cal.calDavMessage = r.error
                    }
                }
            }

            Process {
                id: calDavConfig
                command: ["python3", cal.calDavHelper, "configure"]
                stdinEnabled: true
                onStarted: {
                    write(JSON.stringify({url:cal.calDavUrl.trim(), username:cal.calDavUsername.trim(), password:cal.calDavPassword}))
                    cal.calDavPassword = ""
                    stdinEnabled = false
                }
                onExited: cal.calDavPending = false
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) {}
                        if (r?.ok) {
                            cal.calDavConfigured = true
                            cal.calDavMessage = "Account saved. Select Sync Now to import remote events."
                        } else cal.calDavMessage = r?.error ?? "Could not save CalDAV account."
                    }
                }
            }

            Process {
                id: calDavSync
                command: ["python3", cal.calDavHelper, "sync"]
                onExited: cal.calDavPending = false
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) {}
                        if (r?.ok) {
                            cal.calDavMessage = "Synced " + r.count + " event(s)" + (r.skipped ? "; " + r.skipped + " unsupported event(s) were skipped." : ".")
                            cal.reload()
                        } else cal.calDavMessage = r?.error ?? "CalDAV sync failed. Existing events were kept."
                    }
                }
            }

            Process {
                id: calDavDisconnect
                command: ["python3", cal.calDavHelper, "disconnect"]
                onExited: cal.calDavPending = false
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) {}
                        if (r?.ok) {
                            cal.calDavConfigured = false
                            cal.calDavUrl = ""
                            cal.calDavUsername = ""
                            cal.calDavPassword = ""
                            cal.calDavMessage = "Disconnected. Local events are unchanged."
                            cal.reload()
                        } else cal.calDavMessage = r?.error ?? "Could not disconnect CalDAV."
                    }
                }
            }

            Process {
                id: reminderStatus
                command: ["python3", cal.reminderHelper, "status"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) {}
                        if (r?.ok) cal.remindersEnabled = !!r.enabled
                    }
                }
            }

            Process {
                id: reminderToggle
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) {}
                        if (r?.ok) cal.remindersEnabled = !!r.enabled
                        else cal.error = r?.error ?? "Calendar reminders could not be changed."
                    }
                }
                onExited: {
                    cal.remindersPending = false
                    reminderStatus.running = true
                }
            }

            Process {
                id: loadProc
                command: ["python3", cal.helper, "list"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            cal.broken = !r.ok && !!r.broken
                            cal.canRestore = !!r.canRestore
                            if (r.ok) {
                                cal.events = r.events ?? []
                                cal.error = r.remoteError || (r.invalid ? r.invalid + (r.invalid === 1 ? " event couldn't be shown: its date or time isn't valid." : " events couldn't be shown: their dates or times aren't valid.") : "")
                            } else {
                                cal.events = []
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
                        calendar: cal.draftCalendar,
                        repeat: cal.draftRepeat,
                        until: cal.draftRepeat === "never" ? "" : cal.draftUntil.trim(),
                        reminder: cal.draftReminder,
                        expected: cal.editingOriginal
                    }))
                    stdinEnabled = false
                }
                onExited: stdinEnabled = true
            }

            Process {
                id: duplicateProc
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) cal.reload()
                            else cal.error = r.error ?? "The event could not be duplicated."
                        } catch (e) {
                            cal.error = "The event could not be duplicated."
                        }
                    }
                }
            }

            Process {
                id: resetProc
                stdinEnabled: true
                onStarted: {
                    write(JSON.stringify({expected: cal.resetOriginal}))
                    stdinEnabled = false
                }
                onExited: stdinEnabled = true
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) {}
                        if (r?.ok) {
                            cal.exceptionsMessage = "Restored " + cal.resetOccurrenceDate + "."
                            cal.reload()
                        } else cal.exceptionsMessage = r?.error ?? "This date could not be restored."
                    }
                }
            }

            Process {
                id: restoreProc
                command: ["python3", cal.helper, "restore"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) {}
                        if (r && r.ok) cal.reload()
                        else cal.error = r?.error ?? "The earlier copy couldn't be put back."
                    }
                }
            }

            Process {
                id: skipProc
                stdinEnabled: true
                onStarted: {
                    write(JSON.stringify({expected:cal.deleteOriginal}))
                    stdinEnabled = false
                }
                onExited: stdinEnabled = true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) cal.reload()
                            else cal.error = r.error ?? "This occurrence could not be skipped."
                        } catch (e) {
                            cal.error = "This occurrence could not be skipped."
                        }
                    }
                }
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

            // The window draws under its toolbar: the weekdays start below it.
            Column {
                visible: cal.viewMode === "month"
                anchors { fill: parent; leftMargin: 24; rightMargin: 24; topMargin: win.toolbarHeight + 4; bottomMargin: 18 }
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
                            font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold }
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
                                border { width: 0.5; color: Theme.separator }

                                // Today: the date in a red circle, as in Calendar on the Mac.
                                Rectangle {
                                    x: 5; y: 4
                                    width: 24; height: 24; radius: 12
                                    color: "#ff3b30"
                                    visible: dayCell.today
                                }
                                Text {
                                    x: 5; y: 4
                                    width: 24; height: 24
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: dayCell.valid ? dayCell.day : ""
                                    color: dayCell.today ? "#ffffff" : Theme.label
                                    font {
                                        family: Theme.fontUi
                                        pixelSize: Theme.fs(13)
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
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(9) }
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

            // Compact day/week agenda: the same recurrence projection and event
            // actions as Month, including moved dates and read-only CalDAV.
            Row {
                id: agendaRow
                visible: cal.viewMode !== "month"
                anchors { fill: parent; leftMargin: 20; rightMargin: 20
                          topMargin: win.toolbarHeight + 8; bottomMargin: 16 }
                spacing: 6
                Repeater {
                    model: cal.agendaKeys
                    delegate: Rectangle {
                        id: agendaDay
                        required property string modelData
                        readonly property var dayEvents: Recurrence.occurrencesOn(cal.events, modelData)
                        readonly property bool isSelected: modelData === cal.selectedKey
                        readonly property bool isToday: modelData === Qt.formatDate(cal.today, "yyyy-MM-dd")
                        width: (agendaRow.width - 6 * (cal.agendaKeys.length - 1)) / cal.agendaKeys.length
                        height: agendaRow.height
                        radius: 12
                        color: agendaDay.isSelected
                            ? Qt.rgba(Theme.accent.r,Theme.accent.g,Theme.accent.b,0.09)
                            : (Theme.dark ? "#0bffffff" : "#07000000")
                        border { width: 0.5; color: Theme.separator }
                        Rectangle {
                            id: agendaHeader
                            x: 4; y: 4; width: parent.width - 8; height: 52
                            color: "transparent"
                            Text {
                                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                width: parent.width - 16
                                text: Qt.formatDate(new Date(Number(agendaDay.modelData.slice(0,4)),
                                        Number(agendaDay.modelData.slice(5,7))-1,
                                        Number(agendaDay.modelData.slice(8,10))),
                                        cal.viewMode === "day" ? "dddd, MMMM d" : "ddd d")
                                elide: Text.ElideRight
                                color: agendaDay.isToday ? "#ff453a" : Theme.label
                                font { family: Theme.fontUi; pixelSize: Theme.fs(cal.viewMode === "day" ? 17 : 12); weight: Font.DemiBold }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: cal.selectedDate = new Date(
                                    Number(agendaDay.modelData.slice(0,4)),
                                    Number(agendaDay.modelData.slice(5,7))-1,
                                    Number(agendaDay.modelData.slice(8,10)))
                                onDoubleClicked: cal.openAdd()
                            }
                        }
                        Rectangle {
                            x: 8; y: 56; width: parent.width - 16; height: 1
                            color: Theme.separator
                        }
                        Flickable {
                            id: agendaScroller
                            x: 5; y: 64
                            width: parent.width - 10
                            height: parent.height - 72
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            contentHeight: agendaEntries.implicitHeight
                            Column {
                                id: agendaEntries
                                width: agendaScroller.width
                                spacing: 6
                                Text {
                                    width: parent.width
                                    visible: agendaDay.dayEvents.length === 0
                                    text: "No events"
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Theme.tertiaryLabel
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                                }
                                Repeater {
                                    model: agendaDay.dayEvents
                                    delegate: Rectangle {
                                        id: eventTile
                                        required property var modelData
                                        width: agendaEntries.width
                                        height: 62
                                        radius: 8
                                        color: Theme.dark ? "#16ffffff" : "#ffffff"
                                        border { width: 1; color: Theme.separator }
                                        Rectangle {
                                            x: 4; y: 7; width: 3; height: parent.height - 14
                                            radius: 2; color: Theme.accent
                                        }
                                        Column {
                                            anchors { left: parent.left; leftMargin: 12; right: parent.right
                                                      rightMargin: 7; verticalCenter: parent.verticalCenter }
                                            spacing: 2
                                            Text {
                                                width: parent.width
                                                text: eventTile.modelData.title
                                                elide: Text.ElideRight
                                                color: Theme.label
                                                font { family: Theme.fontUi; pixelSize: Theme.fs(cal.viewMode === "day" ? 13 : 11); weight: Font.DemiBold }
                                            }
                                            Text {
                                                width: parent.width
                                                text: (eventTile.modelData.time || "All day") +
                                                    (eventTile.modelData.remote ? " · CalDAV" : "")
                                                elide: Text.ElideRight
                                                color: Theme.secondaryLabel
                                                font { family: Theme.fontUi; pixelSize: Theme.fs(10) }
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: !eventTile.modelData.remote && !cal.broken
                                            onClicked: cal.requestEdit(eventTile.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Glass {
                visible: !!cal.error
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
                width: Math.min(560, parent.width - 40)
                height: Math.max(50, errorText.implicitHeight + 24)
                radius: 16
                tint: Theme.dark ? "#d02b1f24" : "#eefdf0f0"
                z: 40

                Button {
                    id: restoreButton
                    objectName: "calendarRestore"
                    visible: cal.broken && cal.canRestore
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: "Restore"
                    onClicked: cal.restore()
                }

                Text {
                    id: errorText
                    objectName: "calendarError"
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter
                              right: restoreButton.visible ? restoreButton.left : parent.right; rightMargin: 12 }
                    text: cal.error
                    horizontalAlignment: restoreButton.visible ? Text.AlignLeft : Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: "#ff453a"
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                }
            }

            Glass {
                id: addDialog
                parent: win.overlay
                visible: false
                anchors.centerIn: parent
                width: 420
                height: (cal.draftRepeat === "never" || cal.editingOccurrence ? 360 : 425) + (cal.error ? 38 : 0)
                radius: 22
                tint: Theme.glassRegular.tint
                z: 100

                Column {
                    anchors { fill: parent; margins: 20 }
                    spacing: 12

                    Text {
                        text: cal.editingOccurrence ? "Edit This Occurrence" : (cal.editingId ? (cal.draftRepeat !== "never" ? "Edit Repeating Event" : "Edit Event") : "New Event")
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(18); weight: Font.DemiBold }
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
                        width: parent.width
                        spacing: 12
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Reminder"
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                        }
                        PopUpButton {
                            menuParent: win.overlay
                            options: ["None", "At Event Time", "5 Minutes Before", "15 Minutes Before", "1 Hour Before"]
                            current: Math.max(0, cal.reminderValues.indexOf(cal.draftReminder))
                            onPicked: (i) => cal.draftReminder = cal.reminderValues[i]
                        }
                    }

                    Row {
                        width: parent.width
                        visible: !cal.editingOccurrence
                        spacing: 12
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Repeat"
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                        }
                        PopUpButton {
                            id: repeatPicker
                            menuParent: win.overlay
                            options: ["Never", "Every Day", "Every Week", "Every Month", "Every Year"]
                            current: cal.repeatOptions.indexOf(cal.draftRepeat)
                            onPicked: (i) => {
                                cal.draftRepeat = cal.repeatOptions[i]
                                if (i === 0) cal.draftUntil = ""
                            }
                        }
                    }

                    TextField {
                        id: repeatUntil
                        width: parent.width
                        visible: !cal.editingOccurrence && cal.draftRepeat !== "never"
                        placeholder: "Repeat until YYYY-MM-DD (optional)"
                        text: cal.draftUntil
                        onTextChanged: cal.draftUntil = text
                    }

                    Text {
                        width: parent.width
                        visible: !!cal.editingId && !cal.editingOccurrence && cal.draftRepeat !== "never"
                        text: "Editing changes every occurrence of this series."
                        wrapMode: Text.WordWrap
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }

                    Text {
                        width: parent.width
                        visible: !!cal.error
                        text: cal.error
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: "#ff453a"
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Button { text: "Cancel"; enabled: !addProc.running; onClicked: addDialog.visible = false }
                        Button {
                            text: cal.editingId ? "Save Changes" : "Add"
                            prominent: true
                            enabled: !addProc.running && cal.draftTitle.trim().length > 0
                            onClicked: cal.addEvent()
                        }
                    }
                }
            }

            Glass {
                id: calDavAccount
                objectName: "calendarCalDavAccount"
                parent: win.overlay
                visible: false
                anchors.centerIn: parent
                width: Math.min(480, parent.width - 32)
                height: Math.min(parent.height - 24, cal.calDavConfigured ? 305 : 385)
                radius: 22
                tint: Theme.glassRegular.tint
                z: 120
                Column {
                    anchors { fill: parent; margins: 20 }
                    spacing: 10
                    Text {
                        text: "CalDAV Calendar"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(18); weight: Font.DemiBold }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: "Read-only synchronization. Remote events cannot be edited here. Use your calendar's HTTPS collection URL."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    TextField {
                        width: parent.width
                        visible: !cal.calDavConfigured
                        enabled: !cal.calDavPending
                        placeholder: "https://calendar.example.com/path/"
                        text: cal.calDavUrl
                        onTextChanged: cal.calDavUrl = text
                    }
                    TextField {
                        width: parent.width
                        visible: !cal.calDavConfigured
                        enabled: !cal.calDavPending
                        placeholder: "CalDAV username"
                        text: cal.calDavUsername
                        onTextChanged: cal.calDavUsername = text
                    }
                    TextField {
                        width: parent.width
                        visible: !cal.calDavConfigured
                        enabled: !cal.calDavPending
                        password: true
                        placeholder: "Password or app-specific password"
                        text: cal.calDavPassword
                        onTextChanged: cal.calDavPassword = text
                    }
                    Text {
                        width: parent.width
                        visible: cal.calDavConfigured
                        text: cal.calDavUsername + " · " + cal.calDavUrl
                        wrapMode: Text.WrapAnywhere
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        visible: !!cal.calDavMessage
                        text: cal.calDavMessage
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Button { text: "Close"; enabled: !cal.calDavPending; onClicked: calDavAccount.visible = false }
                        Button {
                            visible: cal.calDavConfigured
                            text: "Disconnect"
                            enabled: !cal.calDavPending
                            onClicked: cal.disconnectCalDav()
                        }
                        Button {
                            text: cal.calDavConfigured ? "Sync Now" : "Connect"
                            prominent: true
                            enabled: !cal.calDavPending && (cal.calDavConfigured ||
                                (cal.calDavUrl.trim().length > 0 && cal.calDavUsername.trim().length > 0 && cal.calDavPassword.length > 0))
                            onClicked: {
                                if (cal.calDavConfigured) cal.syncCalDav()
                                else cal.saveCalDav()
                            }
                        }
                    }
                }
            }

            Glass {
                id: exceptionsSheet
                objectName: "calendarExceptionManager"
                parent: win.overlay
                visible: false
                anchors.centerIn: parent
                width: Math.min(460, parent.width - 30)
                height: Math.min(470, parent.height - 24)
                radius: 22
                tint: Theme.glassRegular.tint
                z: 120
                Column {
                    anchors { fill: parent; margins: 18 }
                    spacing: 10
                    Text {
                        text: "Changed Dates"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(18); weight: Font.DemiBold }
                    }
                    Text {
                        width: parent.width
                        text: "Restore a date to the original repeating event. Other dates are untouched."
                        wrapMode: Text.WordWrap
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    Flickable {
                        id: exceptionList
                        width: parent.width
                        height: 264
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentHeight: exceptionRows.implicitHeight
                        Column {
                            id: exceptionRows
                            width: exceptionList.width
                            spacing: 6
                            Repeater {
                                model: Object.keys(cal.pendingSeries.exceptions || {}).sort()
                                delegate: Rectangle {
                                    id: exRow
                                    required property string modelData
                                    readonly property var change: (cal.pendingSeries.exceptions || {})[modelData]
                                    width: parent.width
                                    height: 54
                                    radius: 8
                                    color: Theme.dark ? "#16ffffff" : "#09000000"
                                    Text {
                                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                        width: parent.width - 104
                                        text: exRow.modelData + (exRow.change ? " → " + exRow.change.date : " · Skipped")
                                        elide: Text.ElideRight
                                        color: Theme.label
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                                    }
                                    Button {
                                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                        text: "Restore"
                                        enabled: !resetProc.running
                                        onClicked: cal.resetOccurrence(exRow.modelData)
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        visible: !!cal.exceptionsMessage
                        text: cal.exceptionsMessage
                        wrapMode: Text.WordWrap
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                    Button {
                        text: "Close"
                        enabled: !resetProc.running
                        onClicked: exceptionsSheet.visible = false
                    }
                }
            }

            Glass {
                id: editScope
                objectName: "calendarEditScope"
                parent: win.overlay
                visible: false
                anchors.centerIn: parent
                width: 390
                height: Object.keys(cal.pendingSeries.exceptions || {}).length ? 226 : 180
                radius: 22
                tint: Theme.glassRegular.tint
                z: 110
                Column {
                    anchors { fill: parent; margins: 20 }
                    spacing: 12
                    Text {
                        text: "Edit Repeating Event"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(18); weight: Font.DemiBold }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Change only this date, update the series, or restore a previously changed date?"
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    Button {
                        visible: Object.keys(cal.pendingSeries.exceptions || {}).length > 0
                        text: "Manage Changed Dates…"
                        onClicked: {
                            editScope.visible = false
                            cal.exceptionsMessage = ""
                            exceptionsSheet.visible = true
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Button { text: "Cancel"; onClicked: editScope.visible = false }
                        Button {
                            text: "Entire Series"
                            onClicked: { editScope.visible = false; cal.openEdit(cal.pendingEdit, false) }
                        }
                        Button {
                            text: "This Date"
                            prominent: true
                            onClicked: { editScope.visible = false; cal.openEdit(cal.pendingEdit, true) }
                        }
                    }
                }
            }

            Glass {
                id: deleteConfirm
                objectName: "calendarDeleteConfirmation"
                parent: win.overlay
                visible: false
                anchors.centerIn: parent
                width: Math.min(420, parent.width - 32)
                height: Math.max(184, confirmDetail.implicitHeight + 132)
                radius: 22
                tint: Theme.glassRegular.tint
                z: 110

                Column {
                    anchors { fill: parent; margins: 20 }
                    spacing: 12

                    Text {
                        width: parent.width
                        text: cal.deleteIsSeries ? "Delete Repeating Event?" : "Delete Event?"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(18); weight: Font.DemiBold }
                    }
                    Text {
                        id: confirmDetail
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Delete “" + cal.deleteTitle + "”? " +
                            (cal.deleteIsSeries ? "You can skip only this date or delete the entire series." : "This event will be removed.") +
                            " This cannot be undone."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Button { text: "Cancel"; onClicked: deleteConfirm.visible = false }
                        Button {
                            visible: cal.deleteIsSeries
                            text: "Only This Date"
                            enabled: !skipProc.running && !deleteProc.running
                            onClicked: {
                                deleteConfirm.visible = false
                                cal.skipOccurrence()
                            }
                        }
                        Button {
                            text: cal.deleteIsSeries ? "Entire Series" : "Delete"
                            enabled: !deleteProc.running && !skipProc.running
                            onClicked: {
                                deleteConfirm.visible = false
                                cal.deleteEvent(cal.deleteTarget)
                            }
                        }
                    }
                }
            }
        }
    }
}
