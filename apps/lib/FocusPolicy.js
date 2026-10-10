.pragma library

// A schedule belongs to its start day, including an interval across midnight.
// Local calendar dates, rather than 24-hour offsets, also handle DST changes.
function scheduleWindow(policy, now) {
    const s = policy?.schedule
    if (!s?.enabled || !Array.isArray(s.days) || !s.days.length
        || !Number.isInteger(s.start) || !Number.isInteger(s.end)
        || s.start < 0 || s.start >= 1440 || s.end < 0 || s.end >= 1440
        || s.start === s.end) return null
    const date = new Date(now)
    for (let offset = -1; offset <= 0; offset++) {
        const start = new Date(date.getFullYear(), date.getMonth(), date.getDate() + offset,
                               Math.floor(s.start / 60), s.start % 60)
        if (!s.days.includes(start.getDay())) continue
        const end = new Date(date.getFullYear(), date.getMonth(), date.getDate() + offset + (s.end <= s.start ? 1 : 0),
                             Math.floor(s.end / 60), s.end % 60)
        if (start.getTime() <= now && now < end.getTime()) return {start:start.getTime(), end:end.getTime()}
    }
    return null
}

function state(policy, now) {
    policy = policy ?? {}
    const session = policy.session
    const scheduled = scheduleWindow(policy, now)
    if (session && typeof session === "object") {
        const until = Number(session.until ?? 0)
        if (session.on === true && Number.isFinite(until) && until >= 0 && (until === 0 || now < until))
            return {active:true, until:until, source:"manual"}
        if (Number(session.pauseUntil ?? 0) > now) return {active:false, until:0, source:"paused"}
    } else if (policy.dnd === true) {
        // A pre-upgrade permanent Do Not Disturb choice stays on.
        return {active:true, until:0, source:"manual"}
    }
    return scheduled ? {active:true, until:scheduled.end, source:"schedule"} : {active:false, until:0, source:"off"}
}

function start(minutes, now) {
    return {on:true, until:minutes > 0 ? now + minutes * 60000 : 0, pauseUntil:0}
}

function stop(policy, now) {
    const scheduled = scheduleWindow(policy, now)
    return {on:false, until:0, pauseUntil:scheduled?.end ?? 0}
}

function canonicalApp(key) {
    key = String(key || "").toLowerCase()
    const builtIn = ["clock", "calendar", "messages", "mail", "software", "airdrop"]
    return builtIn.includes(key) ? "org.goldengate." + key : key
}

function appKey(key) { return encodeURIComponent(canonicalApp(key)).replace(/\./g, "%2E") }

function appChoice(choices, key) {
    choices = choices ?? {}
    const canonical = canonicalApp(key)
    const shortName = canonical.split(".").pop()
    return choices[canonical] ?? (canonicalApp(shortName) === canonical ? choices[shortName] : null) ?? {}
}

function allows(policy, key, urgency) {
    return policy?.allowedApps?.[appKey(key)] === true || (policy?.allowCritical === true && urgency === 2)
}
