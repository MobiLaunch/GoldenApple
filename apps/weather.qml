//@ pragma AppId org.goldengate.Weather
// Weather, laid out like Weather on macOS 27: the sky for the current conditions
// fills the window, the place and temperature sit over a grid of glass cards,
// and a sidebar lists your places (search to add one, right-click to remove).
//
// Forecasts come from Open-Meteo (no key needed), the map from CARTO/OSM with
// RainViewer radar. Units follow the locale (°F, mph, inHg and miles in the US).
// Places are kept in ~/.config/golden-gate/weather.json. My Location comes
// first, from lib/location/locate.py (Location Services on); without it, the
// city of your time zone. °C or °F follows the locale until you choose. GG_WEATHER_FIXTURE=<dir> reads forecast.json, air.json and
// geocode.json from a folder instead of the network (tests, screenshots).
import Quickshell
import Quickshell.Io
import QtQuick
import "lib"
import "lib/theme"
import "weather"
import "weather/api.js" as Api

ShellRoot {
    AppWindow {
        id: win
        title: "Weather"
        // 1100 × 860 as on the Mac, smaller on a small screen.
        implicitWidth: Math.min(1100, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(860, (Quickshell.screens[0]?.height ?? 900) - 150)
        minimumSize: Qt.size(640, 480)
        fullSizeContent: true
        forceDark: true              // white text and glass whatever the appearance
        sidebarWidth: app.sidebarOpen ? 262 : 0
        background: sky.palette[1]

        toolbarLeft: [
            ToolbarButton {
                round: true; symbol: "sidebar"; tone: "white"
                glassColor: "#2effffff"; checked: app.sidebarOpen
                onClicked: app.sidebarOpen = !app.sidebarOpen
            }
        ]
        toolbarRight: [
            ToolbarButton {
                objectName: "weatherUnits"
                text: app.imperial ? "°F" : "°C"
                tone: "white"
                glassColor: "#2effffff"
                Accessible.name: "Temperature unit"
                onClicked: { app.unitChoice = app.imperial ? "metric" : "imperial"; app.save() }
            }
        ]

        backdrop: [
            Sky {
                id: sky
                anchors.fill: parent
                radius: Theme.radiusWindow
                animated: true
                kind: Quickshell.env("GG_WEATHER_SKY") || (app.cur ? Api.sky(app.cur.weather_code, app.cur.is_day) : "cloudy")
            }
        ]

        sidebar: [
            // Search
            TextField {
                id: search
                width: parent.width
                height: 32
                search: true
                placeholder: "Search for a city"
                onTextChanged: { app.searchRevision++; app.searching = false; app.results = []; searchTimer.restart() }
                onAccepted: if (app.results.length) app.addPlace(app.results[0])
                input.Keys.onEscapePressed: text = ""
                Timer { id: searchTimer; interval: 300; onTriggered: app.geocode(search.text) }
            },
            // Places, or search results while searching
            ListView {
                y: 44; width: parent.width; height: parent.height - 44
                clip: true
                spacing: 8
                visible: !search.text
                model: app.places
                delegate: LocationCard {
                    id: placeCard
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    place: modelData
                    f: app.forecasts[app.key(modelData)] ?? null
                    imperial: app.imperial; h12: app.h12
                    selected: index === app.selected
                    onActivated: app.selected = index
                    onMenuRequested: (mx, my) => placeMenu.popup(placeCard, mx, my, [
                        { text: "Delete", enabled: app.places.length > 1, destructive: true, action: () => app.removePlace(index) }
                    ])
                }
            },
            ListView {
                y: 44; width: parent.width; height: parent.height - 44
                clip: true
                visible: !!search.text
                model: app.results
                delegate: Item {
                    required property var modelData
                    width: ListView.view.width; height: 44
                    Rectangle { anchors.fill: parent; radius: 10; color: "#ffffff"; opacity: resultHover.hovered ? 0.14 : 0 }
                    Column {
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        Label { text: modelData.name; px: 13; w: Font.DemiBold }
                        Label { text: [modelData.admin1, modelData.country].filter((s) => s).join(", "); px: 11; alpha: 0.7 }
                    }
                    HoverHandler { id: resultHover }
                    TapHandler { onTapped: app.addPlace(modelData) }
                }
                Label {
                    visible: app.results.length === 0 && !searchTimer.running
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 20
                    text: app.searching ? "Searching…" : "No Results"
                    px: 13; alpha: 0.7
                }
            }
        ]

        Item {
            id: app
            anchors.fill: parent
            focus: true
            Keys.onPressed: (e) => {
                const page = scroller.height - 80, max = Math.max(0, scroller.contentHeight - scroller.height)
                const to = e.key === Qt.Key_Down ? scroller.contentY + 40 : e.key === Qt.Key_Up ? scroller.contentY - 40
                         : e.key === Qt.Key_PageDown || e.key === Qt.Key_Space ? scroller.contentY + page
                         : e.key === Qt.Key_PageUp ? scroller.contentY - page
                         : e.key === Qt.Key_Home ? 0 : e.key === Qt.Key_End ? max : NaN
                if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_F) {   // ⌘F: search
                    app.sidebarOpen = true; search.input.forceActiveFocus(); e.accepted = true; return
                }
                if ((e.modifiers & Qt.ControlModifier) && (e.modifiers & Qt.MetaModifier) && e.key === Qt.Key_S) {   // ⌃⌘S: sidebar
                    app.sidebarOpen = !app.sidebarOpen; e.accepted = true; return
                }
                if (isNaN(to)) return
                scrollAnim.to = Math.max(0, Math.min(max, to)); scrollAnim.restart()
                e.accepted = true
            }
            NumberAnimation { id: scrollAnim; target: scroller; property: "contentY"; duration: 260; easing.type: Easing.OutCubic }

            property bool sidebarOpen: false
            property var places: []
            property int selected: 0
            property var forecasts: ({})
            property var airs: ({})
            property var results: []
            property bool searching: false
            property int searchRevision: 0
            property string radarBase: ""
            property bool online: true

            readonly property string fixture: Quickshell.env("GG_WEATHER_FIXTURE") ?? ""
            readonly property string units: Quickshell.env("GG_WEATHER_UNITS") ?? ""
            property string unitChoice: ""             // "metric" | "imperial" once chosen
            readonly property bool imperial: units ? units === "imperial"
                : unitChoice ? unitChoice === "imperial" : Qt.locale().measurementSystem !== Locale.MetricSystem
            readonly property bool h12: /a|AP/i.test(Qt.locale().timeFormat(Locale.ShortFormat))
            readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/golden-gate"

            readonly property var place: places[selected] ?? null
            readonly property var f: place ? forecasts[key(place)] ?? null : null
            readonly property var air: place ? airs[key(place)] ?? null : null
            readonly property var cur: f ? f.current : null
            readonly property int today: f ? Math.max(0, f.daily.time.indexOf(Api.dateOf(f.current.time))) : 0
            readonly property int hourIdx: f ? Math.max(0, f.hourly.time.findIndex((t) => t.substr(0, 13) === f.current.time.substr(0, 13))) : 0

            function key(p) { return Number(p.lat).toFixed(3) + "," + Number(p.lon).toFixed(3) }
            function url(kind, arg1, arg2) {
                if (fixture) return "file://" + fixture + "/" + kind + ".json"
                return kind === "forecast" ? Api.forecastUrl(arg1, arg2) : kind === "air" ? Api.airUrl(arg1, arg2) : Api.geocodeUrl(arg1)
            }
            // A request that never answers (a captive portal, a dead link) is given up
            // after 20 seconds, so the page says it couldn't load instead of waiting for good.
            property var inflight: []
            property int requestTimeout: 20000
            Timer {
                interval: Math.min(5000, app.requestTimeout / 2); repeat: true; running: app.inflight.length > 0
                onTriggered: { for (const r of app.inflight) if (Date.now() - r.at >= app.requestTimeout) r.x.abort() }
            }

            function get(u, done) {
                const x = new XMLHttpRequest()
                const req = { x, at: Date.now() }
                inflight = inflight.concat([req])
                x.onreadystatechange = () => {
                    if (x.readyState !== XMLHttpRequest.DONE) return
                    inflight = inflight.filter((r) => r !== req)
                    let json = null
                    if (x.status === 200 || (x.status === 0 && x.responseText)) {
                        try { json = JSON.parse(x.responseText) } catch (e) { json = null }
                    }
                    done(json)
                }
                x.open("GET", u)
                x.send()
            }
            function refresh(p) {
                const k = key(p)
                get(url("forecast", p.lat, p.lon), (j) => {
                    if (j && j.current) { const m = Object.assign({}, forecasts); m[k] = j; forecasts = m; online = true }
                    else if (!fixture) online = false
                })
                get(url("air", p.lat, p.lon), (j) => { if (j && j.current) { const m = Object.assign({}, airs); m[k] = j; airs = m } })
            }
            function refreshAll() {
                for (const p of places) refresh(p)
                if (!fixture) get("https://api.rainviewer.com/public/weather-maps.json", (j) => {
                    const frames = j?.radar?.past ?? []
                    radarBase = frames.length ? j.host + frames[frames.length - 1].path : ""
                })
            }
            function geocode(q) {
                const revision = ++searchRevision
                if (!q.trim()) { searching = false; results = []; return }
                searching = true
                get(url("geocode", q), (j) => {
                    if (revision !== searchRevision) return
                    searching = false
                    results = (j?.results ?? []).map((r) => ({ name: r.name, admin1: r.admin1 ?? "", country: r.country ?? "", lat: r.latitude, lon: r.longitude }))
                })
            }
            function addPlace(r) {
                const p = { name: r.name, admin1: r.admin1, country: r.country, lat: r.lat, lon: r.lon }
                let i = places.findIndex((q) => key(q) === key(p))
                if (i < 0) { places = places.concat([p]); i = places.length - 1; refresh(p); save() }
                selected = i
                search.text = ""
            }
            function removePlace(i) {
                if (places.length <= 1) return
                places = places.filter((_, j) => j !== i)
                selected = Math.min(selected, places.length - 1)
                save()
            }
            function save() {
                Quickshell.execDetached(["mkdir", "-p", configDir])
                store.setText(JSON.stringify({ places: places.filter((q) => !q.current), units: unitChoice }, null, 1))
            }
            // My Location: found again each time Weather opens; it leads the list.
            property string locateError: ""
            function locate() { locator.running = true }
            function located(r) {
                if (!r || !r.ok) {
                    locateError = r?.error ?? ""
                    if (!places.length) firstRun()
                    return
                }
                const here = { name: r.name || "My Location", admin1: r.admin1 ?? "", country: r.country ?? "",
                               lat: r.lat, lon: r.lon, current: true }
                const was = places[selected]
                const rest = places.filter((q) => !q.current && !q.home)
                places = [here].concat(rest)
                selected = was && !was.current && !was.home ? Math.max(0, places.findIndex((q) => key(q) === key(was))) : 0
                refresh(here)
                save()
            }
            Process {
                id: locator
                command: ["python3", decodeURIComponent(Qt.resolvedUrl("lib/location/locate.py").toString().replace("file://", "")), "--app", "Weather"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) { r = null }
                        app.located(r)
                    }
                }
            }
            // First run: the city of this machine's time zone, else San Francisco.
            function firstRun() {
                zoneProc.running = true
            }
            function startWith(p) { places = [Object.assign(p, { home: true })]; selected = 0; save(); refreshAll() }

            FileView {
                id: store
                objectName: "weatherStore"
                path: app.configDir + "/weather.json"
                printErrors: false
                onLoaded: {
                    let saved = {}
                    try { saved = JSON.parse(text()) } catch (e) { saved = {} }
                    app.unitChoice = saved.units ?? ""
                    const ps = saved.places ?? []
                    if (ps.length) { app.places = ps; app.refreshAll() }
                    app.locate()
                }
                onLoadFailed: app.locate()
            }
            Process {
                id: zoneProc
                command: ["readlink", "-f", "/etc/localtime"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const zone = text.trim().split("zoneinfo/")[1] ?? ""
                        const city = Api.cityFromZone(zone)
                        const fallback = { name: "San Francisco", admin1: "California", country: "United States", lat: 37.7749, lon: -122.4194 }
                        if (!city) { app.startWith(fallback); return }
                        app.get(app.url("geocode", city), (j) => {
                            const r = j?.results?.[0]
                            app.startWith(r ? { name: r.name, admin1: r.admin1 ?? "", country: r.country ?? "", lat: r.latitude, lon: r.longitude } : fallback)
                        })
                    }
                }
            }
            Timer { interval: 15 * 60 * 1000; running: true; repeat: true; onTriggered: app.refreshAll() }

            // ------------------------------------------------------------ content
            Flickable {
                id: scroller
                anchors.fill: parent
                contentWidth: width
                contentHeight: (grid.y + grid.height * grid.scale) + 40
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                // Offline: a glass card, so the message reads over any sky.
                Glass {
                    anchors.centerIn: parent
                    visible: !app.f && !app.online
                    role: "regular"
                    width: 300; height: offline.implicitHeight + 40
                    radius: 22
                    EmptyState {
                        id: offline
                        anchors.centerIn: parent
                        width: parent.width - 24
                        symbol: "wifi"
                        title: "Weather Unavailable"
                        text: "Check your internet connection."
                        actionText: "Try Again"
                        onAction: app.refreshAll()
                    }
                }

                // The card grid: 5 columns of 148 with 18 between (the Mac's sizes),
                // scaled down to fit a narrow window.
                Item {
                    id: grid
                    readonly property real u: 148
                    readonly property real g: 18
                    readonly property real full: 5 * u + 4 * g
                    function cx(c) { return c * (u + g) }
                    function cw(n) { return n * u + (n - 1) * g }
                    function ry(r) { return r === 0 ? 0 : 124 + g + (r - 1) * (u + g) }
                    function rh(r, n) { return ry(r + n - 1) + (r + n - 1 === 0 ? 124 : u) - ry(r) }
                    width: full; height: ry(5) + u
                    y: 58 + header.openHeight + 22
                    x: (parent.width - width * scale) / 2
                    scale: Math.min(1, (scroller.width - 40) / full)
                    transformOrigin: Item.TopLeft
                    visible: !!app.f

                    readonly property color tint: sky.cardTint

                    Card {
                        x: grid.cx(0); y: grid.ry(0); width: grid.cw(2); height: grid.rh(0, 1)
                        tint: grid.tint; title: "Today"; symbol: "info"
                        Label {
                            width: parent.width
                            text: app.f ? Api.summary(app.f, app.imperial) : ""
                            px: 13; w: Font.Medium
                        }
                        Label {
                            anchors.bottom: parent.bottom
                            text: app.f ? "H:" + Api.temp(app.f.daily.temperature_2m_max[app.today], app.imperial)
                                        + "   L:" + Api.temp(app.f.daily.temperature_2m_min[app.today], app.imperial) : ""
                            px: 11; w: Font.DemiBold; alpha: 0.6
                        }
                    }
                    Card {
                        id: aqiCard
                        x: grid.cx(2); y: grid.ry(0); width: grid.cw(2); height: grid.rh(0, 1)
                        tint: grid.tint; title: "Air Quality"; symbol: "grid"
                        readonly property real aqi: app.air?.current?.us_aqi ?? 0
                        readonly property var yesterday: {
                            const h = app.air?.hourly
                            if (!h) return null
                            const i = h.time.findIndex((t) => t.substr(0, 13) === app.air.current.time.substr(0, 13))
                            return i >= 24 ? h.us_aqi[i - 24] : null
                        }
                        Label { y: 0; text: app.air ? Api.aqiCategory(aqiCard.aqi) : "Unavailable"; px: 14; w: Font.Medium; alpha: 0.9 }
                        ScaleBar {
                            y: 30; width: parent.width
                            value: aqiCard.aqi / 300
                            stops: [[0, "#34c759"], [0.2, "#ffd60a"], [0.4, "#ff9500"], [0.6, "#ff3b30"], [0.8, "#af52de"], [1, "#8e1b2b"]]
                        }
                        Label {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            text: app.air ? Api.aqiSentence(aqiCard.aqi, aqiCard.yesterday) : ""
                            px: 12; w: Font.DemiBold
                        }
                    }
                    WindCard {
                        x: grid.cx(4); y: grid.ry(0); width: grid.cw(1); height: grid.rh(0, 1)
                        tint: grid.tint
                        imperial: app.imperial
                        speed: app.cur ? Api.speed(app.cur.wind_speed_10m, app.imperial) : 0
                        gusts: app.cur ? Api.speed(app.cur.wind_gusts_10m, app.imperial) : 0
                        direction: app.cur?.wind_direction_10m ?? 0
                    }

                    HourlyCard {
                        x: grid.cx(0); y: grid.ry(1); width: grid.cw(4); height: grid.rh(1, 1)
                        tint: grid.tint; f: app.f; imperial: app.imperial; h12: app.h12
                    }
                    MoonCard {
                        x: grid.cx(4); y: grid.ry(1); width: grid.cw(1); height: grid.rh(1, 1)
                        tint: grid.tint
                    }

                    DailyCard {
                        x: grid.cx(0); y: grid.ry(2); width: grid.cw(2); height: grid.rh(2, 3)
                        tint: grid.tint; f: app.f; imperial: app.imperial
                    }
                    MapCard {
                        x: grid.cx(2); y: grid.ry(2); width: grid.cw(2); height: grid.rh(2, 2)
                        tint: grid.tint
                        lat: app.place?.lat ?? 0; lon: app.place?.lon ?? 0
                        place: app.place?.name ?? ""
                        temperature: app.cur ? Api.temp(app.cur.temperature_2m, app.imperial) : ""
                        radarBase: app.radarBase
                        online: !app.fixture && app.online
                    }
                    SunCard {
                        x: grid.cx(4); y: grid.ry(2); width: grid.cw(1); height: grid.rh(2, 1)
                        tint: grid.tint; f: app.f; h12: app.h12
                    }
                    ValueCard {
                        id: uvCard
                        x: grid.cx(4); y: grid.ry(3); width: grid.cw(1); height: grid.rh(3, 1)
                        tint: grid.tint; title: "UV Index"; symbol: "sun-max"
                        readonly property real uv: app.f ? app.f.hourly.uv_index[app.hourIdx] ?? 0 : 0
                        readonly property var window: {
                            if (!app.f) return []
                            const h = app.f.hourly, day = Api.dateOf(app.f.current.time), hrs = []
                            for (let i = 0; i < h.time.length; i++)
                                if (Api.dateOf(h.time[i]) === day && h.uv_index[i] >= 3) hrs.push(h.time[i])
                            return hrs
                        }
                        value: Math.round(uv)
                        detail: Api.uvCategory(uv)
                        note: window.length
                              ? "Use sun protection " + Api.clockText(window[0], app.h12, false) + "–" + Api.clockText(window[window.length - 1].substr(0, 11) + String(Api.hourOf(window[window.length - 1]) + 1).padStart(2, "0") + ":00", app.h12, false) + "."
                              : "Low for the rest of the day."
                        ScaleBar {
                            y: 66; width: parent.width
                            value: uvCard.uv / 11
                            stops: [[0, "#34c759"], [0.3, "#ffd60a"], [0.55, "#ff9500"], [0.8, "#ff3b30"], [1, "#af52de"]]
                        }
                    }
                    DaylightCard {
                        x: grid.cx(2); y: grid.ry(4); width: grid.cw(2); height: grid.rh(4, 1)
                        tint: grid.tint; f: app.f; h12: app.h12
                    }
                    ValueCard {
                        x: grid.cx(4); y: grid.ry(4); width: grid.cw(1); height: grid.rh(4, 1)
                        tint: grid.tint; title: "Feels Like"; symbol: "thermometer"
                        value: app.cur ? Api.temp(app.cur.apparent_temperature, app.imperial) : ""
                        note: app.cur ? Api.feelsSentence(app.cur.temperature_2m, app.cur.apparent_temperature, app.cur.relative_humidity_2m, app.cur.wind_speed_10m) : ""
                    }

                    ValueCard {
                        x: grid.cx(0); y: grid.ry(5); width: grid.cw(1); height: grid.rh(5, 1)
                        tint: grid.tint; title: "Cloud Cover"; symbol: "cloud"
                        value: app.cur ? app.cur.cloud_cover + "%" : ""
                        note: app.cur ? Api.cloudSentence(app.cur.cloud_cover) : ""
                    }
                    ValueCard {
                        x: grid.cx(1); y: grid.ry(5); width: grid.cw(1); height: grid.rh(5, 1)
                        tint: grid.tint; title: "Precipitation"; symbol: "drop"
                        value: app.f ? Api.rain(app.f.daily.precipitation_sum[app.today], app.imperial) : ""
                        detail: "Today"
                        note: {
                            if (!app.f) return ""
                            const d = app.f.daily
                            const t = d.precipitation_sum[app.today + 1]
                            if (t > 0.2) return Api.rain(t, app.imperial) + " expected tomorrow."
                            for (let i = app.today + 2; i < d.time.length; i++)
                                if (d.precipitation_sum[i] > 0.2) return "Next expected is " + Api.rain(d.precipitation_sum[i], app.imperial) + " on " + Api.weekday(d.time[i]) + "."
                            return "None expected in the next 10 days."
                        }
                    }
                    ValueCard {
                        x: grid.cx(2); y: grid.ry(5); width: grid.cw(1); height: grid.rh(5, 1)
                        tint: grid.tint; title: "Visibility"; symbol: "eye"
                        value: app.cur ? Api.distance(app.cur.visibility, app.imperial) : ""
                        note: app.cur ? Api.visibilitySentence(app.cur.visibility) : ""
                    }
                    ValueCard {
                        x: grid.cx(3); y: grid.ry(5); width: grid.cw(1); height: grid.rh(5, 1)
                        tint: grid.tint; title: "Humidity"; symbol: "drop"
                        value: app.cur ? app.cur.relative_humidity_2m + "%" : ""
                        note: app.cur ? "The dew point is " + Api.temp(app.cur.dew_point_2m, app.imperial) + " right now." : ""
                    }
                    PressureCard {
                        x: grid.cx(4); y: grid.ry(5); width: grid.cw(1); height: grid.rh(5, 1)
                        tint: grid.tint; imperial: app.imperial
                        hpa: app.cur?.pressure_msl ?? 1013
                        trend: {
                            if (!app.f || app.hourIdx < 3) return 0
                            const p = app.f.hourly.pressure_msl, d = p[app.hourIdx] - p[app.hourIdx - 3]
                            return d > 0.8 ? 1 : d < -0.8 ? -1 : 0
                        }
                    }
                }
            }
            Scroller { flickable: scroller }

            // Scroll edge: content fades into the sky under the toolbar, as on macOS 27.
            Rectangle {
                id: edgeFade
                // Deeper once the header has folded, so cards fade out beneath it.
                width: parent.width; height: win.toolbarHeight + 16 + (header.height - 30) * header.fold
                radius: win.contentX > 0 ? 0 : Theme.radiusWindow
                opacity: Math.min(1, scroller.contentY / 40)
                readonly property color edge: Qt.darker(sky.palette[0], 1.0)
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(edgeFade.edge.r, edgeFade.edge.g, edgeFade.edge.b, 1) }
                    GradientStop { position: 0.55; color: Qt.rgba(edgeFade.edge.r, edgeFade.edge.g, edgeFade.edge.b, 0.8) }
                    GradientStop { position: 1; color: Qt.rgba(edgeFade.edge.r, edgeFade.edge.g, edgeFade.edge.b, 0) }
                }
            }
            // The place and its weather, pinned: as the cards scroll up under it,
            // the large temperature folds away into one line, as on the Mac.
            Column {
                id: header
                anchors.horizontalCenter: parent.horizontalCenter
                y: 58
                z: 4
                spacing: 0
                // Its height unfolded, where the cards start.
                readonly property real openHeight: locRow.implicitHeight + placeName.implicitHeight + bigTemp.implicitHeight
                                                   + condition.implicitHeight + highLow.implicitHeight
                // 0 at the top, 1 once scrolled past the large temperature.
                readonly property real fold: Math.max(0, Math.min(1, scroller.contentY / 90))
                Row {
                    id: locRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !!(app.place?.current || app.place?.home)
                    spacing: 3
                    Symbol { anchors.verticalCenter: parent.verticalCenter; name: "location"; tone: "white"; size: 9 }
                    Label { text: app.place?.current ? "MY LOCATION" : "HOME"; px: 10; w: Font.Bold }
                }
                Label {
                    id: placeName
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: app.place?.name ?? ""
                    px: 32; w: Font.Normal
                }
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: bigTemp.width; height: bigTemp.height * (1 - header.fold)
                    clip: true
                    Label {
                        id: bigTemp
                        objectName: "weatherTemp"
                        text: app.cur ? Api.temp(app.cur.temperature_2m, app.imperial) : ""
                        px: 96; w: Font.Thin
                        opacity: 1 - header.fold
                        // The degree sign hangs past the centre, as on the Mac.
                        leftPadding: 28
                    }
                }
                Label {
                    id: condition
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: app.cur ? (header.fold > 0.5 ? Api.temp(app.cur.temperature_2m, app.imperial) + "  |  " : "")
                                    + Api.conditionName(app.cur.weather_code) : ""
                    px: 20; w: Font.DemiBold
                }
                Label {
                    id: highLow
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !!app.f
                    opacity: 1 - header.fold
                    text: app.f ? "H:" + Api.temp(app.f.daily.temperature_2m_max[app.today], app.imperial)
                                 + "  L:" + Api.temp(app.f.daily.temperature_2m_min[app.today], app.imperial) : ""
                    px: 20; w: Font.DemiBold
                }
            }
        }
    }

    // Right-click menu on a place.
    PopupMenu { id: placeMenu; parent: win.overlay }
}

