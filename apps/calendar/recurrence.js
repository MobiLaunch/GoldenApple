.pragma library
// Calendar-day rules; use UTC to avoid shifting with daylight saving changes.
function utcDay(iso) {
    return Date.UTC(Number(iso.slice(0, 4)), Number(iso.slice(5, 7)) - 1,
                    Number(iso.slice(8, 10))) / 86400000
}
// Dates are ISO calendar days, never parsed as local-midnight strings.
function shiftDay(date, amount) {
    const d = new Date(utcDay(date) * 86400000)
    d.setUTCDate(d.getUTCDate() + amount)
    return d.toISOString().slice(0, 10)
}
function weekDays(date) {
    const start = -new Date(utcDay(date) * 86400000).getUTCDay()
    return Array.from({length:7}, (_, i) => shiftDay(date, start + i))
}
function displayedDays(mode, selected) {
    return mode === "week" ? weekDays(selected) : [selected]
}
function occursOn(event, date) {
    if (!event || typeof event.date !== "string" || typeof date !== "string")
        return false
    if (date < event.date || (event.until && date > event.until))
        return false
    const repeat = event.repeat || "never"
    if (repeat === "never") return date === event.date
    const delta = utcDay(date) - utcDay(event.date)
    if (delta < 0 || !Number.isFinite(delta)) return false
    if (repeat === "daily") return true
    if (repeat === "weekly") return delta % 7 === 0
    if (repeat === "monthly") return date.slice(8, 10) === event.date.slice(8, 10)
    if (repeat === "yearly") return date.slice(5, 10) === event.date.slice(5, 10)
    return false
}
function occurrencesOn(events, date) {
    const result = []
    for (const event of (Array.isArray(events) ? events : [])) {
        const exceptions = event.exceptions || {}
        if (occursOn(event, date) && !Object.prototype.hasOwnProperty.call(exceptions, date))
            result.push(Object.assign({}, event, {occurrenceDate:date, displayedDate:date}))
        for (const original in exceptions) {
            if (!Object.prototype.hasOwnProperty.call(exceptions, original))
                continue
            const override = exceptions[original]
            if (!override || override.date !== date) continue
            result.push(Object.assign({}, event, override, {
                date:event.date, occurrenceDate:original, displayedDate:date,
                occurrenceEdited:true
            }))
        }
    }
    // Native Calendar orders all-day items first, then timed items.
    result.sort((a, b) => (a.time || "").localeCompare(b.time || "") ||
        (a.title || "").localeCompare(b.title || "") || (a.id || "").localeCompare(b.id || ""))
    return result
}
function summary(event) {
    const r = event?.repeat || "never"
    const labels = {daily:"Daily", weekly:"Weekly", monthly:"Monthly", yearly:"Yearly"}
    if (r === "never") return ""
    return (labels[r] || "") + (event?.until ? " until " + event.until : "")
}
