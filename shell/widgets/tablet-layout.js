.pragma library
// Pure, deterministic tablet Home Screen widget mutations. Tablet widgets
// are separate from desktop widgets so switching modes never shuffles either.
var CATALOG = {
    calendar: ["small", "medium"], clock: ["small"],
    weather: ["small", "medium"], music: ["small", "medium"],
    notes: ["small", "medium"], battery: ["small"]
}

function defaults() {
    return [
        {id: "tablet-weather-1", kind: "weather", size: "medium"},
        {id: "tablet-calendar-1", kind: "calendar", size: "small"},
        {id: "tablet-clock-1", kind: "clock", size: "small"}
    ]
}

function valid(item) {
    return !!item && typeof item.id === "string" &&
        /^[a-zA-Z0-9_-]{1,80}$/.test(item.id) &&
        Object.prototype.hasOwnProperty.call(CATALOG, item.kind) &&
        CATALOG[item.kind].includes(item.size)
}

function normalized(cards) {
    if (!Array.isArray(cards)) return defaults()
    const seen = new Set()
    return cards.filter(card => {
        if (!valid(card) || seen.has(card.id)) return false
        seen.add(card.id)
        return true
    }).slice(0, 20).map(card => ({id:card.id, kind:card.kind, size:card.size}))
}

function add(cards, kind, size) {
    const items = normalized(cards)
    if (!Object.prototype.hasOwnProperty.call(CATALOG, kind) ||
        !CATALOG[kind].includes(size) || items.length >= 20) return items
    let n = 1
    while (items.some(c => c.id === "tablet-" + kind + "-" + n)) n++
    return items.concat([{id:"tablet-" + kind + "-" + n,kind:kind,size:size}])
}

function remove(cards, id) {
    return normalized(cards).filter(c => c.id !== id)
}

function resize(cards, id, size) {
    return normalized(cards).map(card => card.id === id && CATALOG[card.kind].includes(size)
        ? {id:card.id, kind:card.kind, size:size} : card)
}

function move(cards, id, destination) {
    const next = normalized(cards)
    const old = next.findIndex(item => item.id === id)
    if (old < 0 || !Number.isInteger(destination)) return next
    const item = next.splice(old, 1)[0]
    next.splice(Math.max(0, Math.min(next.length, destination)), 0, item)
    return next
}
