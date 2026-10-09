// Canonical macOS-like document sheet. Keep the dimmer, panel and content on
// one timeline and preserve the focus origin when the sheet closes.
import QtQuick
import QtQuick.Window
import "theme"

Item {
    id: sheet
    anchors.fill: parent
    visible: shown || dimmer.opacity > 0.001 || panel.opacity > 0.001
    z: 20

    property bool shown: false
    property real panelWidth: 480
    property real panelHeight: content.childrenRect.height + 40
    property bool dismissible: true
    property Item returnFocus: null
    default property alias content: content.data
    readonly property alias panel: panel
    signal closed()

    function open() {
        if (shown) return
        const active = sheet.Window.window?.activeFocusItem
        returnFocus = active && active !== panel ? active : null
        shown = true
        panel.forceActiveFocus()
    }
    function close() {
        if (!shown) return
        shown = false
        closed()
        const origin = returnFocus
        // A close callback may have opened a new sheet immediately. Returning
        // focus to the old trigger must not steal it from that new dialog.
        if (!shown) {
            returnFocus = null
            if (origin && origin.visible && origin.enabled) origin.forceActiveFocus()
        }
    }

    Rectangle {
        id: dimmer
        anchors.fill: parent
        radius: Theme.radiusWindow
        color: "#000000"
        opacity: sheet.shown ? (Theme.dark ? 0.32 : 0.14) : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.reduceMotion ? 0 : 155; easing.type: Easing.OutCubic }
        }
        MouseArea {
            anchors.fill: parent
            // Always absorb outside clicks while shown; a non-dismissible
            // confirmation cannot expose destructive controls behind it.
            enabled: sheet.shown
            onClicked: if (sheet.dismissible) sheet.close()
        }
    }

    Item {
        id: panel
        objectName: "sharedSheetPanel"
        focus: true
        // Keep the exit fade visible while making every child immediately inert.
        enabled: sheet.shown
        width: Math.min(sheet.panelWidth, Math.max(0, sheet.width - 32))
        height: Math.min(sheet.panelHeight, Math.max(0, sheet.height - Theme.sizeToolbar - 12))
        x: (parent.width - width) / 2
        y: Theme.sizeToolbar - 4 + (sheet.shown || Theme.reduceMotion ? 0 : -14)
        opacity: sheet.shown ? 1 : 0
        scale: sheet.shown || Theme.reduceMotion ? 1 : 0.985
        transformOrigin: Item.Top
        Behavior on y {
            enabled: !Theme.reduceMotion
            NumberAnimation { duration: 230; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: Theme.reduceMotion ? 0 : (sheet.shown ? 165 : 125) }
        }
        Behavior on scale {
            enabled: !Theme.reduceMotion
            NumberAnimation { duration: 230; easing.type: Easing.OutCubic }
        }
        Keys.onEscapePressed: if (sheet.dismissible) sheet.close()

        Rectangle {
            anchors.fill: parent
            radius: 22
            color: Theme.windowBg
            opacity: 0.9
        }
        Glass {
            anchors.fill: parent
            radius: 22
            role: "menu"
        }
        // Preserve interaction inside the sheet even when it overlays the
        // dimmer's click-away target.
        MouseArea { anchors.fill: parent; enabled: sheet.shown }
        Item {
            id: content
            anchors { fill: parent; margins: 20 }
        }
    }
}
