.pragma library
// Mission Control's spread: where each window goes so that all of them fit the
// area, side by side, as large as they can be (never larger than they are).
// Every number of rows is tried and the one whose windows come out largest is
// kept; rows go top to bottom by where the windows are, left to right within a
// row, each row centred. `label` is the room left under each window for its
// title. Plain function over plain objects, tested by tests/logic.mjs.
//   windows: [{ x, y, w, h }], area: { x, y, width, height } → [{ x, y, width, height }]
function spread(windows, area, gap, label) {
    const n = windows.length
    if (!n) return []
    gap = gap ?? 28
    label = label ?? 26
    let best = null
    for (let rows = 1; rows <= n; rows++) {
        const cols = Math.ceil(n / rows)
        const cw = (area.width - gap * (cols - 1)) / cols
        const ch = (area.height - gap * (rows - 1)) / rows - label
        if (cw <= 0 || ch <= 0) continue
        const s = Math.min(1, ...windows.map((w) => Math.min(cw / w.w, ch / w.h)))
        if (!best || s > best.s + 1e-9) best = { rows, cols, s, cw, ch }
    }
    if (!best) return windows.map(() => ({ x: area.x, y: area.y, width: 1, height: 1 }))
    const order = windows.map((w, i) => i).sort((a, b) =>
        (windows[a].y + windows[a].h / 2) - (windows[b].y + windows[b].h / 2) || windows[a].x - windows[b].x)
    const out = []
    const rowH = best.ch + label + gap
    const used = Math.ceil(n / best.cols)
    const top = area.y + (area.height - (used * rowH - gap)) / 2
    for (let r = 0; r < used; r++) {
        const row = order.slice(r * best.cols, (r + 1) * best.cols).sort((a, b) => windows[a].x - windows[b].x)
        const sizes = row.map((i) => {
            const w = windows[i], s = Math.min(1, best.cw / w.w, best.ch / w.h)
            return [w.w * s, w.h * s]
        })
        const total = sizes.reduce((t, s) => t + s[0], 0) + gap * (row.length - 1)
        let x = area.x + (area.width - total) / 2
        row.forEach((i, k) => {
            const [w, h] = sizes[k]
            out[i] = { x: x, y: top + r * rowH + (best.ch - h) / 2, width: w, height: h }
            x += w + gap
        })
    }
    return out
}

// For the arrow keys: the window in the row above (dir -1) or below (dir 1)
// that is closest across; i itself when there's none.
function nearest(rects, i, dir) {
    if (i < 0) return rects.length ? 0 : -1
    const r = rects[i], cx = r.x + r.width / 2, cy = r.y + r.height / 2
    let best = i, bestD = Infinity
    rects.forEach((o, j) => {
        const dy = (o.y + o.height / 2) - cy
        if (Math.sign(dy) !== dir || Math.abs(dy) < 8) return
        const d = Math.abs(o.x + o.width / 2 - cx) + Math.abs(dy) * 0.25
        if (d < bestD) { bestD = d; best = j }
    })
    return best
}
