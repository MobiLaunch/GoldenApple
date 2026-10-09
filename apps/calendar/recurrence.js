.pragma library
// Calendar-day rules; use UTC to avoid shifting with daylight saving changes.
function utcDay(iso) {
    return Date.UTC(Number(iso.slice(0, 4)), Number(iso.slice(5, 7)) - 1,
                    Number(iso.slice(8, 10))) / 86400000
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
    return (Array.isArray(events) ? events : [])
        .filter(e => occursOn(e, date))
        .map(e => Object.assign({}, e, {occurrenceDate:date}))
}
function summary(event) {
    const r = event?.repeat || "never"
    const labels = {daily:"Daily", weekly:"Weekly", monthly:"Monthly", yearly:"Yearly"}
    if (r === "never") return ""
    return (labels[r] || "") + (event?.until ? " until " + event.until : "")
}
