.pragma library
// The firmware's charge level from /sys/class/power_supply (Battery.qml):
// "capacity full" per battery, one line each; the level is the capacities
// weighted by each battery's full charge (laptops with two batteries), 0…1,
// or -1 when there's nothing to go on.
function level(text) {
    let sum = 0, weight = 0
    for (const line of String(text).split("\n")) {
        const parts = line.trim().split(/\s+/)
        if (!/^\d+$/.test(parts[0] ?? "")) continue     // an empty line isn't a battery at 0%
        const c = Number(parts[0]), f = Number(parts[1])
        if (c > 100) continue
        const w = f > 0 ? f : 1
        sum += c * w
        weight += w
    }
    return weight > 0 ? sum / weight / 100 : -1
}
