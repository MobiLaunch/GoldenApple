.pragma library
// Where desktop widgets go. The desktop is a grid of cells, one small widget to
// a cell; a medium widget spans two cells across and a large one two by two,
// as on the Mac. Widgets are kept as { id, kind, size, col, row } so they stay
// put when the screen changes size, and two never share a cell. Plain functions
// over plain objects, tested by tests/logic.mjs.

var CELL = 164      // a small widget
var GAP = 16
var MARGIN = 24     // from the left edge of the screen
var TOP = 46        // from the top, under the menu bar

function span(size) {
    return size === "large" ? { w: 2, h: 2 } : size === "medium" ? { w: 2, h: 1 } : { w: 1, h: 1 }
}
function pixels(size) {
    var s = span(size)
    return { width: s.w * CELL + (s.w - 1) * GAP, height: s.h * CELL + (s.h - 1) * GAP }
}
function x(col) { return MARGIN + col * (CELL + GAP) }
function y(row) { return TOP + row * (CELL + GAP) }
// How many cells fit on a screen of this size (keeping clear of the Dock).
function grid(width, height) {
    return { cols: Math.max(1, Math.floor((width - MARGIN + GAP) / (CELL + GAP))),
             rows: Math.max(1, Math.floor((height - TOP - 96 + GAP) / (CELL + GAP))) }
}
// The cell nearest a point, for a widget dragged to (px, py).
function cellAt(px, py) {
    return { col: Math.round((px - MARGIN) / (CELL + GAP)), row: Math.round((py - TOP) / (CELL + GAP)) }
}

function overlaps(a, b) {
    var sa = span(a.size), sb = span(b.size)
    return a.col < b.col + sb.w && b.col < a.col + sa.w && a.row < b.row + sb.h && b.row < a.row + sa.h
}
// Whether `item` can sit at (col, row) without leaving the grid or covering
// another widget (it never collides with itself).
function fits(items, item, col, row, g) {
    var s = span(item.size)
    if (col < 0 || row < 0 || col + s.w > g.cols || row + s.h > g.rows) return false
    var moved = { size: item.size, col: col, row: row }
    for (var i = 0; i < items.length; i++)
        if (items[i].id !== item.id && overlaps(moved, items[i])) return false
    return true
}
// The free spot closest to (col, row), or null when the desktop is full.
function nearest(items, item, col, row, g) {
    var best = null, bestD = Infinity
    for (var r = 0; r < g.rows; r++)
        for (var c = 0; c < g.cols; c++) {
            if (!fits(items, item, c, r, g)) continue
            var d = (c - col) * (c - col) + (r - row) * (r - row)
            if (d < bestD) { bestD = d; best = { col: c, row: r } }
        }
    return best
}
// Where a new widget goes: down the left side first, then the next column,
// the way the Mac fills the desktop.
function firstFree(items, size, g) {
    var item = { id: "", size: size }
    for (var c = 0; c < g.cols; c++)
        for (var r = 0; r < g.rows; r++)
            if (fits(items, item, c, r, g)) return { col: c, row: r }
    return null
}
// The same widget at another size, kept where it is if it fits there, else
// moved to the nearest place it does; null when it fits nowhere.
function resized(items, item, size, g) {
    var next = { id: item.id, kind: item.kind, size: size, col: item.col, row: item.row }
    var at = nearest(items, next, item.col, item.row, g)
    if (!at) return null
    next.col = at.col; next.row = at.row
    return next
}
// The widgets a new account starts with: the date, the weather and a clock.
function defaults() {
    return [
        { id: "calendar-1", kind: "calendar", size: "small", col: 0, row: 0 },
        { id: "clock-1", kind: "clock", size: "small", col: 1, row: 0 },
        { id: "weather-1", kind: "weather", size: "medium", col: 0, row: 1 }
    ]
}
