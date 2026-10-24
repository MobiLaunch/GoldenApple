// What the desktop widgets show, fetched once and shared by every widget and
// the gallery's previews: the time, the weather where you are (the first place
// in Weather, else your time zone's city, from Open-Meteo every 15 minutes),
// today's events from Calendar, your latest note, the battery and what's playing.
// GG_WEATHER_FIXTURE=<dir> reads forecast.json (and geocode.json) from a folder.
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import QtQuick
import "../components"
import "weather.js" as Wx

Scope {
    id: feeds
    readonly property string home: Quickshell.env("HOME")
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/golden-gate"
    readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/golden-gate"
    readonly property string fixture: Quickshell.env("GG_WEATHER_FIXTURE") ?? ""

    // ------------------------------------------------------------------ time
    readonly property date now: clock.date
    SystemClock { id: clock; precision: SystemClock.Seconds }

    // ----------------------------------------------------------------- media
    readonly property var player: Mpris.players.values.find((p) => p.isPlaying) ?? (Mpris.players.values.length ? Mpris.players.values[0] : null)

    // --------------------------------------------------------------- battery
    // The firmware's level and the smoothed time left (components/Battery.qml).
    readonly property bool hasBattery: Battery.present
    readonly property real battery: hasBattery ? Battery.level : 1
    readonly property bool charging: Battery.charging || !hasBattery

    // --------------------------------------------------------------- weather
    property var place: null            // { name, lat, lon }
    property var forecast: null
    readonly property bool imperial: (Quickshell.env("GG_WEATHER_UNITS") ?? "") ? Quickshell.env("GG_WEATHER_UNITS") === "imperial"
        : Qt.locale().measurementSystem !== Locale.MetricSystem
    readonly property var weather: forecast ? Wx.summary(forecast, imperial) : null

    // A request that never answers (a captive portal, a dead link) is given up
    // after 20 seconds, so the widget shows no weather instead of waiting for good.
    property var inflight: []
    property int requestTimeout: 20000
    Timer {
        interval: Math.min(5000, feeds.requestTimeout / 2); repeat: true; running: feeds.inflight.length > 0
        onTriggered: { for (const r of feeds.inflight) if (Date.now() - r.at >= feeds.requestTimeout) r.x.abort() }
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
    function refreshWeather() {
        if (!place) return
        get(fixture ? "file://" + fixture + "/forecast.json" : Wx.forecastUrl(place.lat, place.lon), (j) => { if (j && j.current) feeds.forecast = j })
    }
    function useZone(zone) {
        const city = Wx.cityFromZone(zone)
        const fallback = { name: "San Francisco", lat: 37.7749, lon: -122.4194 }
        if (!city) { place = fallback; refreshWeather(); return }
        get(fixture ? "file://" + fixture + "/geocode.json" : Wx.geocodeUrl(city), (j) => {
            const r = j?.results?.[0]
            feeds.place = r ? { name: r.name, lat: r.latitude, lon: r.longitude } : fallback
            feeds.refreshWeather()
        })
    }
    FileView {
        path: feeds.configDir + "/weather.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let p = null
            try { p = JSON.parse(text()).places?.[0] ?? null } catch (e) { p = null }
            if (p) { feeds.place = { name: p.name, lat: p.lat, lon: p.lon }; feeds.refreshWeather() } else zone.running = true
        }
        onLoadFailed: zone.running = true
    }
    Process {
        id: zone
        command: ["readlink", "-f", "/etc/localtime"]
        stdout: StdioCollector { onStreamFinished: feeds.useZone(text.trim().split("zoneinfo/")[1] ?? "") }
    }
    Timer { interval: 15 * 60 * 1000; running: true; repeat: true; onTriggered: feeds.refreshWeather() }

    // -------------------------------------------------------------- calendar
    property var events: []
    readonly property string today: Qt.formatDate(now, "yyyy-MM-dd")
    // Today's events still to come (all-day ones first), then tomorrow's.
    readonly property var upNext: events.filter((e) => e.date === today && (!e.time || e.time >= Qt.formatTime(now, "HH:mm")))
        .sort((a, b) => (a.time || "").localeCompare(b.time || ""))
    FileView {
        path: feeds.dataDir + "/calendar/events.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const j = JSON.parse(text()); feeds.events = Array.isArray(j) ? j : (j.events ?? []) } catch (e) { feeds.events = [] } }
        onLoadFailed: feeds.events = []
    }

    // ----------------------------------------------------------------- notes
    // { title, body, path, modified } for the note changed last.
    property var note: null
    // Only looked for while a Notes widget is out (or the gallery shows one).
    property bool wantNotes: true
    onWantNotesChanged: if (wantNotes) notes.running = true
    Process {
        id: notes
        running: feeds.wantNotes
        command: ["sh", "-c", "f=$(find \"$HOME/Documents/Notes\" -name '*.md' -printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -n1); "
            + "[ -n \"$f\" ] || exit 0; printf '%s\\n' \"$f\"; head -c 600 \"${f#*\t}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                if (!lines[0]) { feeds.note = null; return }
                const head = lines[0].split("\t")
                const body = lines.slice(1).map((l) => l.replace(/^[#>*+ -]+/, "").replace(/\*\*|__|`/g, "").trim()).filter((l) => l)
                feeds.note = { modified: new Date(Number(head[0]) * 1000), path: head[1], title: body[0] ?? "New Note", body: body.slice(1).join(" ") }
            }
        }
    }
    Timer { interval: 60 * 1000; running: feeds.wantNotes; repeat: true; onTriggered: notes.running = true }
}
