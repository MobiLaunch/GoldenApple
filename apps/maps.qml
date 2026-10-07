//@ pragma AppId org.goldengate.Maps
// Maps, laid out like Maps on macOS 27: the map fills the window under a glass
// sidebar (Search, Directions, Recents) and a floating panel that searches,
// shows a place, or plans a route by car, on foot or by bike, with the routes
// drawn in Maps blue and their times on the map.
//
// OpenStreetMap all the way down, no account: CARTO tiles (Esri imagery for
// Satellite and Hybrid), Photon search and Find Nearby, OSRM routes. Your
// location (the blue dot, ⌘L) from lib/location/locate.py with Location
// Services on. Favorites, recents and the last view are kept in
// ~/.config/golden-gate/maps.json. Long-press the map to drop a pin.
// GG_MAPS_FIXTURE=<dir> reads search.json / route.json / reverse.json from a
// folder instead of the network (tests).
import Quickshell
import Quickshell.Io
import QtQuick
import "lib"
import "lib/theme"
import "maps"
import "maps/api.js" as Api

ShellRoot {
    AppWindow {
        id: win
        title: "Maps"
        implicitWidth: Math.min(1280, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(800, (Quickshell.screens[0]?.height ?? 900) - 150)
        minimumSize: Qt.size(720, 480)
        sidebarWidth: app.sidebarOpen ? 200 : 0
        fullSizeContent: true
        background: map.styleDef.bg

        toolbarSidebar: [
            ToolbarButton { round: true; symbol: "sidebar"; checked: app.sidebarOpen; onClicked: app.sidebarOpen = !app.sidebarOpen }
        ]

        backdrop: [
            SlippyMap {
                id: map
                anchors.fill: parent
                style: app.mapStyle === "standard" && Theme.dark ? "dark" : app.mapStyle
                online: !app.fixture
                imperial: app.imperial
                scaleInset: win.contentX + app.panelWidth + 16
                onLongPressed: (la, lo) => app.dropPin(la, lo)

                LocationDot {
                    view: map
                    visible: !!app.here
                    lat: app.here?.lat ?? 0; lon: app.here?.lon ?? 0
                    accuracy: app.here?.accuracy ?? 0
                }

                Routes {
                    view: map
                    routes: app.mode === "directions" ? app.routes : []
                    selected: app.routeIndex
                    onPicked: (i) => app.routeIndex = i
                }
                Pin {
                    view: map
                    visible: app.mode === "directions" && !!app.from
                    lat: app.from?.lat ?? 0; lon: app.from?.lon ?? 0
                    dot: true; color: "#0a84ff"
                    label: app.from?.name ?? ""
                }
                Pin {
                    view: map
                    readonly property var pl: app.mode === "directions" ? app.to : app.place
                    visible: !!pl
                    lat: pl?.lat ?? 0; lon: pl?.lon ?? 0
                    color: pl ? Api.category(pl)[0] : "#ff3b30"
                    symbol: pl ? Api.category(pl)[1] : "pin"
                    label: pl?.name ?? ""
                }
                // Search results
                Repeater {
                    model: app.mode === "search" ? app.results : []
                    delegate: Pin {
                        required property var modelData
                        view: map
                        lat: modelData.lat; lon: modelData.lon
                        color: Api.category(modelData)[0]; symbol: Api.category(modelData)[1]
                        label: modelData.name
                        onClicked: app.showPlace(modelData)
                    }
                }
            }
        ]

        // ---------------------------------------------------------------- sidebar
        sidebar: [
            Column {
                width: parent.width
                component NavItem: Item {
                    id: navItem
                    property string symbol
                    property string text
                    property color tint: "#8e8e93"
                    property bool selected: false
                    signal clicked()
                    width: parent.width; height: 40
                    Rectangle {
                        anchors.fill: parent; radius: 10
                        color: Theme.dark ? "#ffffff" : "#000000"
                        opacity: navItem.selected ? (Theme.dark ? 0.12 : 0.07) : nh.hovered ? 0.04 : 0
                    }
                    Rectangle {
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 26; height: 26; radius: 7
                        color: navItem.tint
                        Symbol { anchors.centerIn: parent; name: navItem.symbol; tone: "white"; size: 14 }
                    }
                    Text {
                        x: 44; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 50; elide: Text.ElideRight
                        text: navItem.text
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 14 }
                    }
                    HoverHandler { id: nh }
                    TapHandler { onTapped: navItem.clicked() }
                }
                NavItem { symbol: "search"; text: "Search"; tint: "#8e8e93"; selected: app.mode === "search" || app.mode === "place"; onClicked: app.startSearch() }
                NavItem { symbol: "arrow-up"; text: "Directions"; tint: "#0a84ff"; selected: app.mode === "directions"; onClicked: app.startDirections(null) }
                Text {
                    visible: app.favorites.length > 0
                    leftPadding: 10; topPadding: 18; bottomPadding: 6
                    text: "Favorites"
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                }
                Repeater {
                    model: app.favorites
                    delegate: NavItem {
                        required property var modelData
                        symbol: "star"; tint: "#ffcc00"
                        text: modelData.name
                        onClicked: app.showPlace(modelData)
                    }
                }
                Text {
                    visible: app.recents.length > 0
                    leftPadding: 10; topPadding: 18; bottomPadding: 6
                    text: "Recents"
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                }
                Repeater {
                    model: app.recents
                    delegate: NavItem {
                        required property var modelData
                        symbol: Api.category(modelData)[1]; tint: Api.category(modelData)[0]
                        text: modelData.name
                        onClicked: app.showPlace(modelData)
                    }
                }
            }
        ]

        Item {
            id: app
            anchors.fill: parent

            readonly property string fixture: Quickshell.env("GG_MAPS_FIXTURE") ?? ""
            readonly property string configFile: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/golden-gate/maps.json"
            readonly property bool imperial: Qt.locale().measurementSystem !== Locale.MetricSystem
            readonly property bool h12: /a|AP/i.test(Qt.locale().timeFormat(Locale.ShortFormat))

            property bool sidebarOpen: true
            property string mode: "search"          // search | place | directions
            property string mapStyle: "standard"
            property var results: []
            property bool searching: false
            property int searchRevision: 0
            property var place: null
            property var recents: []
            property var from: null
            property var to: null
            property string travel: "car"
            property var routes: []
            property int routeIndex: 0
            property bool routing: false
            property int routeRevision: 0
            property string savedSnapshot: ""
            property bool routeFailed: false
            property bool stepsOpen: false
            property string editing: ""             // "from" | "to" while typing in a directions field
            property var favorites: []
            property var here: null                 // { lat, lon, accuracy, name } from the location helper
            property bool locating: false
            property string locateError: ""
            property string nearbyName: ""          // the Find Nearby category shown, if any
            readonly property real panelWidth: 360

            // A request that never answers (a captive portal, a dead link) is given up
            // after 20 seconds, so the page says it couldn't load instead of waiting for good.
            property var inflight: []
            property int requestTimeout: 20000
            Timer {
                interval: Math.min(5000, app.requestTimeout / 2); repeat: true; running: app.inflight.length > 0
                onTriggered: { for (const r of app.inflight) if (Date.now() - r.at >= app.requestTimeout) r.x.abort() }
            }

            function get(url, kind, done) {
                const x = new XMLHttpRequest()
                const req = { x, at: Date.now() }
                inflight = inflight.concat([req])
                x.onreadystatechange = () => {
                    if (x.readyState !== XMLHttpRequest.DONE) return
                    inflight = inflight.filter((r) => r !== req)
                    let j = null
                    try { j = JSON.parse(x.responseText) } catch (e) {}
                    done(j)
                }
                x.open("GET", fixture ? "file://" + fixture + "/" + kind + ".json" : url)
                x.send()
            }
            function search(q, then) {
                const revision = ++searchRevision
                if (!q.trim()) { searching = false; results = []; return }
                searching = true
                get(Api.searchUrl(q, map.lat, map.lon), "search", (j) => {
                    if (revision !== searchRevision) return
                    searching = false
                    results = (j?.features ?? []).map(Api.place)
                    if (then) then()
                })
            }
            function startSearch() { mode = "search"; place = null; nearbyName = ""; Qt.callLater(() => searchField.input.forceActiveFocus()) }
            // Where you are; fly there if asked (the location button, ⌘L).
            property bool flyHere: false
            function locateMe(fly) {
                flyHere = fly
                if (here && fly) flyToHere()
                if (locator.running) return
                locating = true
                locator.running = true
            }
            function located(r) {
                locating = false
                if (!r || !r.ok) { locateError = r?.error ?? "Your location couldn't be found."; return }
                locateError = ""
                here = { lat: r.lat, lon: r.lon, accuracy: r.accuracy ?? 0, name: "My Location", current: true }
                if (flyHere) flyToHere()
            }
            // Centred in the part of the map the panels don't cover.
            function flyToHere() {
                const z = Math.max(map.zoom, 15)
                const inset = win.contentX + panelWidth + 16
                const w = Api.worldPx(here.lat, here.lon, z)
                const c = Api.fromWorldPx(w.x - inset / 2, w.y, z)
                map.flyTo(c.lat, c.lon, z)
            }
            function isFavorite(p) { return !!p && favorites.some((f) => Math.abs(f.lat - p.lat) < 1e-5 && Math.abs(f.lon - p.lon) < 1e-5) }
            function toggleFavorite(p) {
                if (!p) return
                favorites = isFavorite(p) ? favorites.filter((f) => !(Math.abs(f.lat - p.lat) < 1e-5 && Math.abs(f.lon - p.lon) < 1e-5))
                                          : favorites.concat([{ name: p.name, address: p.address, lat: p.lat, lon: p.lon, kind: p.kind ?? "", key: p.key ?? "" }])
                save()
            }
            function nearby(cat) {
                const revision = ++searchRevision
                nearbyName = cat.name
                mode = "search"
                searching = true
                results = []
                get(Api.nearbyUrl(cat, map.lat, map.lon), "search", (j) => {
                    if (revision !== searchRevision) return
                    searching = false
                    results = (j?.features ?? []).map(Api.place)
                    if (results.length > 1) map.fit(results.map((r) => [r.lon, r.lat]), win.contentX + panelWidth + 16)
                })
            }
            function showPlace(p) {
                place = p
                mode = "place"
                recents = [p].concat(recents.filter((r) => !(Math.abs(r.lat - p.lat) < 1e-5 && Math.abs(r.lon - p.lon) < 1e-5))).slice(0, 8)
                save()
                const w = Api.worldPx(p.lat, p.lon, Math.max(map.zoom, 15))
                const c = Api.fromWorldPx(w.x - (win.contentX + panelWidth + 16) / 2, w.y, Math.max(map.zoom, 15))
                map.flyTo(c.lat, c.lon, Math.max(map.zoom, 15))
            }
            function dropPin(la, lo) {
                const pin = { name: "Dropped Pin", address: la.toFixed(5) + ", " + lo.toFixed(5), lat: la, lon: lo, kind: "", key: "" }
                showPlace(pin)
                get("https://photon.komoot.io/reverse?lang=en&lat=" + la + "&lon=" + lo, "reverse", (j) => {
                    const f = j?.features?.[0]
                    if (f && place === pin) { const r = Api.place(f); place = Object.assign({}, pin, { address: [r.name, r.address].filter((s) => s).join(", ") }) }
                })
            }
            function startDirections(dest) {
                mode = "directions"
                stepsOpen = false
                if (dest) to = dest
                if (!from && here) from = here
                if (!from && !to) editing = "to"
                else if (!from) editing = "from"
                else editing = ""
                if (from && to) route()
                Qt.callLater(() => { if (editing === "from") fromEnd.input.forceActiveFocus(); else if (editing === "to") toEnd.input.forceActiveFocus() })
            }
            function choose(p) {
                if (editing === "from") from = p; else to = p
                editing = !from ? "from" : !to ? "to" : ""
                results = []
                if (from && to) route()
                else map.flyTo(p.lat, p.lon, Math.max(map.zoom, 13))
                // On to the field still empty.
                Qt.callLater(() => { if (editing === "from") fromEnd.input.forceActiveFocus(); else if (editing === "to") toEnd.input.forceActiveFocus(); else app.forceActiveFocus() })
            }
            function swap() { const f = from; from = to; to = f; if (from && to) route() }
            function route() {
                const revision = ++routeRevision
                routing = true; routeFailed = false; routes = []; routeIndex = 0
                get(Api.routeUrl(travel, from, to), "route", (j) => {
                    if (revision !== routeRevision) return
                    routing = false
                    routes = j?.routes ?? []
                    routeFailed = !routes.length
                    if (routes.length) {
                        const all = [].concat(...routes.map((r) => r.geometry.coordinates))
                        map.fit(all, win.contentX + panelWidth + 16)   // the map is under the sidebar and panel too
                    }
                })
            }
            function save() {
                const snapshot = JSON.stringify({ favorites: favorites, recents: recents, view: { lat: map.lat, lon: map.lon, zoom: map.zoom }, style: mapStyle }, null, 1)
                if (snapshot === savedSnapshot) return
                Quickshell.execDetached(["mkdir", "-p", configFile.replace(/\/[^/]+$/, "")])
                store.setText(snapshot)
            }

            FileView {
                id: store
                path: app.configFile
                onSaved: app.savedSnapshot = text()
                printErrors: false
                blockWrites: true
                onLoaded: {
                    try {
                        const j = JSON.parse(text())
                        app.recents = j.recents ?? []
                        app.favorites = j.favorites ?? []
                        app.mapStyle = j.style ?? "standard"
                        if (j.view) { map.lat = j.view.lat; map.lon = j.view.lon; map.zoom = j.view.zoom }
                    } catch (e) {}
                }
                onLoadFailed: { zoneProc.running = true; app.locateMe(true) }
            }
            Component.onCompleted: app.locateMe(false)
            Process {
                id: locator
                command: ["python3", decodeURIComponent(Qt.resolvedUrl("lib/location/locate.py").toString().replace("file://", "")), "--app", "Maps"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) { r = null }
                        app.located(r)
                    }
                }
            }
            // First run: start over the city of the time zone (else San Francisco).
            Process {
                id: zoneProc
                command: ["readlink", "-f", "/etc/localtime"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const city = Api.cityFromZone(text.trim().split("zoneinfo/")[1] ?? "")
                        if (!city || app.fixture) return
                        app.get(Api.searchUrl(city), "search", (j) => {
                            const f = j?.features?.[0]
                            if (f) { map.lat = f.geometry.coordinates[1]; map.lon = f.geometry.coordinates[0]; map.zoom = 11 }
                        })
                    }
                }
            }
            Timer { interval: 3000; running: true; repeat: true; onTriggered: app.save() }

            // ------------------------------------------------------------ panel
            Rectangle {
                id: panel
                // Below the toolbar row, which is for dragging the window.
                x: 8; y: win.toolbarHeight
                width: app.panelWidth; height: parent.height - y - 8
                radius: 18
                color: Theme.dark ? "#eb28282b" : "#f0f6f6f8"
                border { width: 0.5; color: Theme.dark ? "#26ffffff" : "#1f000000" }
                Rectangle { z: -1; anchors { fill: parent; topMargin: 4; bottomMargin: -6; leftMargin: -1; rightMargin: -1 } radius: parent.radius + 1; color: "#1a000000" }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (w) => w.accepted = true }   // the map stays put under the panel

                // Search / place
                Item {
                    anchors.fill: parent
                    visible: app.mode !== "directions"
                    TextField {
                        id: searchField
                        x: 14
                        y: 14
                        width: parent.width - 28
                        height: 38
                        search: true
                        placeholder: "Search Maps"
                        onTextChanged: {
                            app.searchRevision++
                            app.searching = false
                            app.results = []
                            app.mode = "search"
                            searchTimer.restart()
                        }
                        onAccepted: app.search(text, () => {
                            if (app.results.length === 1)
                                app.showPlace(app.results[0])
                            else if (app.results.length > 1)
                                map.fit(app.results.map((r) => [r.lon, r.lat]), win.contentX + app.panelWidth + 16)
                        })
                        input.Keys.onEscapePressed: text = ""
                        Timer { id: searchTimer; interval: 350; onTriggered: app.search(searchField.text) }
                    }
                    // Results
                    ListView {
                        visible: app.mode === "search"
                        x: 8; y: 62; width: parent.width - 16; height: parent.height - 70
                        clip: true
                        model: app.results
                        delegate: Item {
                            required property var modelData
                            width: ListView.view.width; height: 56
                            Rectangle { anchors.fill: parent; radius: 10; color: Theme.dark ? "#ffffff" : "#000000"; opacity: rh.hovered ? 0.05 : 0 }
                            Rectangle {
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                width: 32; height: 32; radius: 16
                                color: Api.category(modelData)[0]
                                Symbol { anchors.centerIn: parent; name: Api.category(modelData)[1]; tone: "white"; size: 15 }
                            }
                            Column {
                                x: 52; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 60
                                Text { width: parent.width; elide: Text.ElideRight; text: modelData.name; color: Theme.label; font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold } }
                                Text { width: parent.width; elide: Text.ElideRight; text: modelData.address; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 12 } }
                            }
                            HoverHandler { id: rh }
                            TapHandler { onTapped: app.showPlace(modelData) }
                        }
                        Text {
                            visible: !app.results.length && (!!searchField.text || !!app.nearbyName || app.searching)
                            x: 10; y: 8; width: parent.width - 20; wrapMode: Text.Wrap
                            text: app.searching ? "Searching…" : "No Results"
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 13 }
                        }
                    }
                    // Find Nearby: Maps' categories, around what's on the map.
                    Column {
                        visible: app.mode === "search" && !searchField.text && !app.nearbyName && !app.results.length && !app.searching
                        x: 18; y: 66; width: parent.width - 36
                        spacing: 10
                        Text { text: "Find Nearby"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold } }
                        Grid {
                            columns: 4
                            columnSpacing: 6; rowSpacing: 12
                            Repeater {
                                model: Api.NEARBY
                                delegate: Column {
                                    required property var modelData
                                    width: 75
                                    spacing: 5
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 44; height: 44; radius: 22
                                        color: modelData.tint
                                        Symbol { anchors.centerIn: parent; name: modelData.symbol; tone: "white"; size: 18 }
                                        MouseArea { anchors.fill: parent; onClicked: app.nearby(modelData) }
                                    }
                                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.name; elide: Text.ElideRight
                                           color: Theme.label; font { family: Theme.fontUi; pixelSize: 11 } }
                                }
                            }
                        }
                        Text {
                            width: parent.width; wrapMode: Text.Wrap
                            topPadding: 6
                            text: "Search for a place or address, or long-press the map to drop a pin."
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 12 }
                        }
                    }
                    // Place card
                    Column {
                        visible: app.mode === "place" && !!app.place
                        x: 20; y: 70; width: parent.width - 40
                        spacing: 6
                        Text { width: parent.width; wrapMode: Text.Wrap; text: app.place?.name ?? ""; color: Theme.label; font { family: Theme.fontUi; pixelSize: 24; weight: Font.Bold } }
                        Text { width: parent.width; wrapMode: Text.Wrap; text: app.place?.address ?? ""; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 13 } }
                        Item { width: 1; height: 8 }
                        Rectangle {
                            width: parent.width; height: 44; radius: 12
                            color: "#0a84ff"
                            Row {
                                anchors.centerIn: parent; spacing: 8
                                Symbol { anchors.verticalCenter: parent.verticalCenter; name: "arrow-up"; tone: "white"; size: 15 }
                                Text { text: "Directions"; color: "#ffffff"; font { family: Theme.fontUi; pixelSize: 15; weight: Font.DemiBold } }
                            }
                            MouseArea { anchors.fill: parent; onClicked: app.startDirections(app.place) }
                        }
                        // Favorite, Share, Copy Coordinates: round buttons under Directions.
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            topPadding: 8
                            spacing: 22
                            Repeater {
                                model: [
                                    { s: "star", t: app.isFavorite(app.place) ? "Favorited" : "Favorite", lit: app.isFavorite(app.place), a: () => app.toggleFavorite(app.place) },
                                    { s: "share", t: "Share", a: () => { Quickshell.clipboardText = Api.shareUrl(app.place); app.toast = "Link copied" } },
                                    { s: "copy", t: "Coordinates", a: () => { Quickshell.clipboardText = app.place.lat.toFixed(5) + ", " + app.place.lon.toFixed(5); app.toast = "Coordinates copied" } }
                                ]
                                delegate: Column {
                                    required property var modelData
                                    spacing: 4
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 40; height: 40; radius: 20
                                        color: modelData.lit ? "#ffcc00" : (Theme.dark ? "#1fffffff" : "#e5e5ea")
                                        Symbol { anchors.centerIn: parent; name: modelData.s; size: 16; tone: modelData.lit ? "white" : "accent" }
                                        MouseArea { anchors.fill: parent; onClicked: modelData.a() }
                                    }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.t; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
                                }
                            }
                        }
                        Item { width: 1; height: 10 }
                        Rectangle {
                            width: parent.width; height: detailCol.height + 24; radius: 12
                            color: Theme.dark ? "#14ffffff" : "#ffffff"
                            Column {
                                id: detailCol
                                x: 14; y: 12; width: parent.width - 28; spacing: 10
                                Repeater {
                                    model: [["Address", app.place?.address ?? ""], ["Coordinates", app.place ? app.place.lat.toFixed(5) + ", " + app.place.lon.toFixed(5) : ""]].filter((r) => r[1])
                                    delegate: Column {
                                        required property var modelData
                                        width: detailCol.width
                                        Text { text: modelData[0]; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold } }
                                        Text { width: parent.width; wrapMode: Text.Wrap; text: modelData[1]; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13 } }
                                    }
                                }
                                Text {
                                    text: "Open in OpenStreetMap ↗"
                                    color: Theme.accent
                                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                                    TapHandler { onTapped: Qt.openUrlExternally(Api.shareUrl(app.place)) }
                                }
                            }
                        }
                    }
                }

                // Directions
                Item {
                    anchors.fill: parent
                    visible: app.mode === "directions"
                    Text {
                        x: 20; y: 18
                        text: "Directions"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 22; weight: Font.Bold }
                    }
                    ToolbarButton {
                        x: parent.width - width - 14; y: 12
                        round: true; symbol: "xmark"
                        onClicked: { app.routeRevision++; app.routing = false; app.mode = "search"; app.routes = [] }
                    }
                    // Car / walk / bike
                    Row {
                        x: 14; y: 60; width: parent.width - 28
                        spacing: 8
                        Repeater {
                            model: [{ m: "car", s: "car" }, { m: "foot", s: "person" }, { m: "bike", s: "wind" }]
                            delegate: Rectangle {
                                required property var modelData
                                width: (parent.width - 16) / 3; height: 34; radius: 10
                                color: app.travel === modelData.m ? "#0a84ff" : (Theme.dark ? "#1fffffff" : "#e5e5ea")
                                Symbol { anchors.centerIn: parent; name: modelData.s; tone: app.travel === modelData.m ? "white" : "gray"; size: 16 }
                                MouseArea { anchors.fill: parent; onClicked: { app.travel = modelData.m; if (app.from && app.to) app.route() } }
                            }
                        }
                    }
                    // From / to
                    Rectangle {
                        id: ends
                        x: 14; y: 106; width: parent.width - 28; height: 96; radius: 14
                        color: Theme.dark ? "#14ffffff" : "#ffffff"
                        component EndField: Item {
                            id: endField
                            property string which
                            property alias input: field
                            property color dotColor
                            width: ends.width - 56
                            height: 48

                            Rectangle {
                                x: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                radius: 9
                                color: endField.dotColor
                                Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: "#ffffff" }
                            }

                            TextField {
                                id: field
                                x: 42
                                width: parent.width - 48
                                anchors.verticalCenter: parent.verticalCenter
                                readonly property var value: endField.which === "from" ? app.from : app.to
                                text: value?.name ?? ""
                                placeholder: endField.which === "from" ? "Start" : "Destination"
                                onTextChanged: {
                                    if (!field.input.activeFocus)
                                        return
                                    app.searchRevision++
                                    app.searching = false
                                    app.results = []
                                    app.editing = endField.which
                                    dirTimer.restart()
                                }
                                onAccepted: app.search(text, () => {
                                    if (app.results.length)
                                        app.choose(app.results[0])
                                })
                                Connections {
                                    target: field.input
                                    function onActiveFocusChanged() {
                                        if (field.input.activeFocus) {
                                            app.editing = endField.which
                                            field.input.selectAll()
                                        }
                                    }
                                }
                            }
                        }
                        EndField { id: fromEnd; which: "from"; dotColor: "#0a84ff" }
                        EndField { id: toEnd; y: 48; which: "to"; dotColor: "#ff3b30" }
                        Rectangle { x: 42; y: 48; width: parent.width - 56; height: 0.5; color: Theme.separator }
                        ToolbarButton {
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            symbol: "chevron-updown"; tone: "accent"
                            onClicked: app.swap()
                        }
                        Timer { id: dirTimer; interval: 350; onTriggered: app.search(app.editing === "from" ? fromEnd.input.text : toEnd.input.text) }
                    }
                    // Suggestions while typing in a field; routes otherwise.
                    ListView {
                        x: 8; y: 214; width: parent.width - 16; height: parent.height - y - 8
                        clip: true
                        visible: !!app.editing && app.results.length > 0
                        model: visible ? app.results : []
                        delegate: Item {
                            required property var modelData
                            width: ListView.view.width; height: 50
                            Rectangle { anchors.fill: parent; radius: 10; color: Theme.dark ? "#ffffff" : "#000000"; opacity: sh.hovered ? 0.05 : 0 }
                            Column {
                                x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 24
                                Text { width: parent.width; elide: Text.ElideRight; text: modelData.name; color: Theme.label; font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold } }
                                Text { width: parent.width; elide: Text.ElideRight; text: modelData.address; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 12 } }
                            }
                            HoverHandler { id: sh }
                            TapHandler { onTapped: app.choose(modelData) }
                        }
                    }
                    Flickable {
                        x: 14; y: 214; width: parent.width - 28; height: parent.height - y - 8
                        visible: !(app.editing && app.results.length > 0)
                        contentHeight: routeCol.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: routeCol
                            width: parent.width
                            spacing: 10
                            Text {
                                visible: app.routing || app.routeFailed
                                text: app.routing ? "Finding routes…" : "Directions aren't available."
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: 13 }
                            }
                            Repeater {
                                model: app.routes
                                delegate: Rectangle {
                                    id: card
                                    required property var modelData
                                    required property int index
                                    readonly property bool chosen: index === app.routeIndex
                                    width: routeCol.width
                                    height: 84 + (chosen && app.stepsOpen ? steps.height + 10 : 0)
                                    radius: 14
                                    color: chosen ? "#0a84ff" : (Theme.dark ? "#14ffffff" : "#ffffff")
                                    Column {
                                        x: 18; y: 18
                                        Text {
                                            text: Api.duration(card.modelData.duration)
                                            color: card.chosen ? "#ffffff" : Theme.label
                                            font { family: Theme.fontUi; pixelSize: 19; weight: Font.Bold }
                                        }
                                        Text {
                                            text: Api.eta(card.modelData.duration, app.h12) + " · " + Api.distance(card.modelData.distance, app.imperial)
                                                  + (card.index === 0 && app.routes.length > 1 ? " · Fastest route" : "")
                                            color: card.chosen ? "#e6ffffff" : Theme.secondaryLabel
                                            font { family: Theme.fontUi; pixelSize: 13 }
                                        }
                                    }
                                    Rectangle {
                                        anchors { right: parent.right; rightMargin: 16; top: parent.top; topMargin: 32 }
                                        width: 20; height: 20; radius: 10
                                        color: card.chosen ? "#ffffff" : "#8e8e93"
                                        Text { anchors.centerIn: parent; text: "i"; color: card.chosen ? "#0a84ff" : "#ffffff"; font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold; italic: false } }
                                        MouseArea { anchors { fill: parent; margins: -6 } onClicked: { app.routeIndex = card.index; app.stepsOpen = !app.stepsOpen } }
                                    }
                                    Column {
                                        id: steps
                                        visible: card.chosen && app.stepsOpen
                                        x: 12; y: 80; width: parent.width - 24
                                        Repeater {
                                            model: steps.visible ? card.modelData.legs[0].steps : []
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: steps.width; height: Math.max(40, stepText.height + 16)
                                                color: "transparent"
                                                Symbol { x: 4; anchors.verticalCenter: parent.verticalCenter; name: Api.turnSymbol(modelData); tone: "white"; size: 16 }
                                                Column {
                                                    x: 32; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 36
                                                    Text { id: stepText; width: parent.width; wrapMode: Text.Wrap; text: Api.instruction(modelData); color: "#ffffff"; font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium } }
                                                    Text { visible: modelData.distance > 0; text: Api.distance(modelData.distance, app.imperial); color: "#ccffffff"; font { family: Theme.fontUi; pixelSize: 11 } }
                                                }
                                                Rectangle { anchors.bottom: parent.bottom; x: 32; width: parent.width - 32; height: 0.5; color: "#40ffffff" }
                                            }
                                        }
                                    }
                                    TapHandler { onTapped: { if (app.routeIndex !== card.index) app.stepsOpen = false; app.routeIndex = card.index } }
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------------------ map controls
            component GlassButton: Rectangle {
                id: gb
                property string symbol
                signal clicked()
                width: 38; height: 38; radius: 10
                color: Theme.dark ? "#e62c2c2e" : "#f2ffffff"
                border { width: 0.5; color: Theme.dark ? "#26ffffff" : "#26000000" }
                Symbol { anchors.centerIn: parent; name: gb.symbol; size: 16 }
                MouseArea { anchors.fill: parent; onClicked: gb.clicked() }
            }
            Column {
                anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: win.toolbarHeight + 4 }
                spacing: 8
                GlassButton {
                    objectName: "mapsLocate"
                    symbol: "location"
                    opacity: app.locating ? 0.6 : 1
                    onClicked: app.locateMe(true)
                }
                GlassButton {
                    id: styleBtn
                    symbol: "layers"
                    onClicked: menu.popup(styleBtn, -180, height + 6, Object.keys(Api.STYLES).filter((k) => k !== "dark").map((k) => ({
                        text: Api.STYLES[k].name, checked: app.mapStyle === k, action: () => { app.mapStyle = k; app.save() } })))
                }
            }
            Column {
                anchors { right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 26 }
                spacing: 0
                GlassButton { symbol: "plus"; radius: 10; onClicked: map.flyTo(map.lat, map.lon, Math.min(19, Math.round(map.zoom) + 1)) }
                GlassButton { symbol: "minus"; radius: 10; onClicked: map.flyTo(map.lat, map.lon, Math.max(2, Math.round(map.zoom) - 1)) }
            }

            // "Link copied", "Location Services are off": a capsule at the bottom, briefly.
            property string toast: ""
            onLocateErrorChanged: if (locateError && flyHere) toast = locateError
            onToastChanged: if (toast) toastTimer.restart()
            Timer { id: toastTimer; interval: 2600; onTriggered: app.toast = "" }
            Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 26 }
                visible: opacity > 0
                opacity: app.toast ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                width: toastText.implicitWidth + 32; height: 34; radius: 17
                color: Theme.dark ? "#e62c2c2e" : "#f2ffffff"
                border { width: 0.5; color: Theme.dark ? "#26ffffff" : "#26000000" }
                Text { id: toastText; anchors.centerIn: parent; text: app.toast; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium } }
            }

            Keys.onPressed: (e) => {
                const ctrl = e.modifiers & Qt.ControlModifier
                if (ctrl && e.key === Qt.Key_F) { app.startSearch(); e.accepted = true }
                else if (ctrl && e.key === Qt.Key_L) { app.locateMe(true); e.accepted = true }
                else if (ctrl && e.key === Qt.Key_R) { app.startDirections(app.place); e.accepted = true }
                else if (ctrl && (e.key === Qt.Key_Equal || e.key === Qt.Key_Plus)) { map.flyTo(map.lat, map.lon, Math.round(map.zoom) + 1); e.accepted = true }
                else if (ctrl && e.key === Qt.Key_Minus) { map.flyTo(map.lat, map.lon, Math.round(map.zoom) - 1); e.accepted = true }
            }
            focus: true
        }

        PopupMenu { id: menu; parent: win.overlay }
    }
}

