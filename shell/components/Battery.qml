pragma Singleton
// The battery, as the menu bar, lock screen, widgets and Control Center show
// it. The level is the firmware's own (/sys/class/power_supply/BAT*/capacity,
// weighted by each battery's full charge when there are two), which is what
// other systems show; UPower's combined percentage, worked out from energy
// readings, can stop short of 100% when full or wander. Fully charged reads
// 100%. The time left (or until full) is UPower's estimate, smoothed, and
// "Calculating…" for the first minute after the power changes, as on the
// Mac. Connecting power plays the charging chime (Settings › Sound).
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import "battery.js" as B

Singleton {
    id: battery
    readonly property var device: UPower.displayDevice
    readonly property bool present: device.isLaptopBattery
    readonly property bool full: device.state === UPowerDeviceState.FullyCharged
    readonly property bool charging: device.state === UPowerDeviceState.Charging || full
    readonly property bool onPower: !UPower.onBattery
    // 0…1.
    property real firmwareLevel: -1
    readonly property real level: full ? 1 : firmwareLevel >= 0 ? firmwareLevel : device.percentage
    readonly property int percent: Math.round(level * 100)

    // Read again whenever UPower sees a change, and every half minute.
    Process {
        id: reader
        command: ["sh", "-c", "for b in /sys/class/power_supply/*; do [ \"$(cat \"$b/type\" 2>/dev/null)\" = Battery ] || continue; "
            + "[ \"$(cat \"$b/scope\" 2>/dev/null)\" = Device ] && continue; "
            + "c=$(cat \"$b/capacity\" 2>/dev/null) || continue; "
            + "f=$(cat \"$b/energy_full\" 2>/dev/null || cat \"$b/charge_full\" 2>/dev/null || echo 1); echo \"$c $f\"; done"]
        stdout: StdioCollector { onStreamFinished: battery.firmwareLevel = B.level(text) }
    }
    function read() { if (present && !reader.running) reader.running = true }
    Timer { interval: 30000; repeat: true; running: battery.present; triggeredOnStart: true; onTriggered: battery.read() }
    Connections {
        target: battery.device
        function onPercentageChanged() { battery.read() }
        function onStateChanged() { battery.read() }
    }

    // Time left, smoothed (UPower's estimate jumps with each reading).
    property real smoothed: 0
    property real changedAt: Date.now()
    readonly property real rawSeconds: charging ? device.timeToFull : device.timeToEmpty
    onRawSecondsChanged: {
        if (rawSeconds <= 0) return
        smoothed = smoothed > 0 ? smoothed * 0.8 + rawSeconds * 0.2 : rawSeconds
    }
    onChargingChanged: { smoothed = 0; changedAt = Date.now() }
    property real now: Date.now()
    Timer { interval: 15000; repeat: true; running: battery.present; onTriggered: battery.now = Date.now() }
    readonly property bool calculating: smoothed <= 0 || now - changedAt < 60000
    // "3:25 remaining", "1:10 until full", "Calculating…", "Fully charged",
    // "Not charging" (on power but held back: a charge limit, or too warm;
    // there's no estimate then, so it said Calculating… for ever).
    readonly property string timeText: {
        if (!present) return ""
        if (full) return "Fully charged"
        // (UPower can still say discharging for a moment after the plug goes in.)
        if (onPower && !charging) return now - changedAt < 60000 ? "Calculating…" : "Not charging"
        if (calculating) return "Calculating…"
        const m = Math.round(smoothed / 60)
        const t = Math.floor(m / 60) + ":" + String(m % 60).padStart(2, "0")
        return charging ? t + " until full" : t + " remaining"
    }
    readonly property string sourceText: onPower ? "Power Adapter" : "Battery"

    // The charging chime, when power is connected (not at login).
    property bool settled: false
    Timer { interval: 4000; running: true; onTriggered: battery.settled = true }
    onOnPowerChanged: {
        changedAt = Date.now()
        if (onPower && settled && present && Prefs.chargingSound)
            Quickshell.execDetached(["sh", "-c", "pw-play \"$1\" 2>/dev/null || paplay \"$1\" 2>/dev/null || true", "sh",
                Prefs.soundPath("Charging")])
    }
}
