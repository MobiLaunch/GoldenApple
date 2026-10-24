import QtQuick
// Notifications come from the harness (preview.py --notify), as if sent by apps.
QtObject {
    id: server
    property bool keepOnReload; property bool actionsSupported; property bool imageSupported
    property bool bodyMarkupSupported; property bool bodySupported: true; property bool persistenceSupported
    property bool actionIconsSupported; property bool inlineReplySupported; property var extraHints: []
    property var __tracked: []
    readonly property QtObject trackedNotifications: QtObject { readonly property var values: server.__tracked }
    signal notification(var n)
    property Component __n: Component {
        QtObject {
            id: n
            property int id; property string appName; property string appIcon; property string summary; property string body
            property string image; property string desktopEntry; property var actions: []; property int urgency: 1
            property real expireTimeout: -1; property bool resident
            property bool tracked: false
            onTrackedChanged: if (tracked && !server.__tracked.includes(n)) server.__tracked = server.__tracked.concat([n])
            signal closed(int reason)
            function dismiss() { server.__tracked = server.__tracked.filter((x) => x !== n); closed(2) }
            function expire() { dismiss() }
        }
    }
    function __send(fields) { const n = __n.createObject(server, fields); notification(n); return n }
    Component.onCompleted: __preview.registerNotificationServer(server)
}
