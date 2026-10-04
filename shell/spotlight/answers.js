.pragma library
// Spotlight's answers, the parts that need no system: arithmetic, unit
// conversions and which System Settings pane a search means. Plain functions
// over strings, tested by tests/logic.mjs.

// ------------------------------------------------------------- calculator
// A small, safe expression parser (no eval): + - × ÷ ^ %, parentheses,
// sqrt sin cos tan log ln abs round, pi and e. "20% of 150" works too.
var FUNCS = {
    sqrt: Math.sqrt, sin: Math.sin, cos: Math.cos, tan: Math.tan, abs: Math.abs,
    round: Math.round, floor: Math.floor, ceil: Math.ceil,
    log: function (x) { return Math.log(x) / Math.LN10 }, ln: Math.log
}

function tokenize(text) {
    var s = text.toLowerCase().replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-").replace(/π/g, "pi").replace(/\*\*/g, "^")
    var out = [], i = 0
    while (i < s.length) {
        var c = s[i]
        if (c === " ") { i++; continue }
        var num = /^(\d+(\.\d*)?|\.\d+)(e[+-]?\d+)?/.exec(s.slice(i))
        if (num) { out.push({ t: "num", v: parseFloat(num[0]) }); i += num[0].length; continue }
        var word = /^[a-z]+/.exec(s.slice(i))
        if (word) { out.push(word[0] === "x" ? { t: "op", v: "*" } : { t: "word", v: word[0] }); i += word[0].length; continue }
        if ("+-*/^%()".indexOf(c) >= 0) { out.push({ t: "op", v: c }); i++; continue }
        return null
    }
    return out
}

function parse(tokens) {
    var pos = 0
    function peek() { return tokens[pos] }
    function take() { return tokens[pos++] }
    function isOp(v) { var t = peek(); return t && t.t === "op" && t.v === v }
    function primary() {
        var t = take()
        if (!t) throw "end"
        if (t.t === "num") return postfix(t.v)
        if (t.t === "op" && t.v === "(") { var v = expr(); if (!isOp(")")) throw "paren"; take(); return postfix(v) }
        if (t.t === "op" && t.v === "-") return -power()
        if (t.t === "op" && t.v === "+") return power()
        if (t.t === "word") {
            if (t.v === "pi") return postfix(Math.PI)
            if (t.v === "e") return postfix(Math.E)
            if (FUNCS[t.v]) {
                var arg = isOp("(") ? (take(), (function () { var a = expr(); if (!isOp(")")) throw "paren"; take(); return a })()) : power()
                return postfix(FUNCS[t.v](arg))
            }
        }
        throw "token"
    }
    function postfix(v) { while (isOp("%")) { take(); v = v / 100 } return v }
    function power() { var b = primary(); if (isOp("^")) { take(); return Math.pow(b, power()) } return b }
    function term() {
        var v = power()
        for (;;) {
            if (isOp("*")) { take(); v *= power() }
            else if (isOp("/")) { take(); v /= power() }
            else if (peek() && (peek().t === "num" || peek().t === "word" || (peek().t === "op" && peek().v === "("))) v *= power()   // 2pi, 3(4)
            else return v
        }
    }
    function expr() {
        var v = term()
        for (;;) {
            if (isOp("+")) { take(); v += term() }
            else if (isOp("-")) { take(); v -= term() }
            else return v
        }
    }
    var result = expr()
    if (pos !== tokens.length) throw "trailing"
    return result
}

// "1234567.5" → "1,234,567.5"; at most 10 significant digits, no float noise.
function format(v) {
    if (!isFinite(v)) return null
    var r = Math.abs(v) >= 1e15 || (Math.abs(v) < 1e-6 && v !== 0) ? v.toExponential(6).replace(/\.?0+e/, "e") : String(parseFloat(v.toPrecision(10)))
    if (r.indexOf("e") >= 0) return r
    var parts = r.split("."), sign = parts[0][0] === "-" ? "-" : ""
    var int = parts[0].replace("-", "").replace(/\B(?=(\d{3})+(?!\d))/g, ",")
    return sign + int + (parts[1] ? "." + parts[1] : "")
}

// The answer to a calculation, or null if the text isn't one. A bare number
// isn't: there has to be an operator, a function or a percentage.
function calculate(text) {
    var q = String(text || "").trim()
    if (!q || q.length > 120) return null
    var of = /^([\d.]+)\s*%\s*of\s+(.+)$/i.exec(q)
    if (of) {
        var base = calculate(of[2]) || (isFinite(parseFloat(of[2])) && /^[\d.\s]+$/.test(of[2]) ? { value: parseFloat(of[2]) } : null)
        if (!base) return null
        var p = parseFloat(of[1]) / 100 * base.value
        return { value: p, display: format(p), expression: q }
    }
    if (!/[+\-*/^%×÷x(]|sqrt|sin|cos|tan|log|ln|abs|round|floor|ceil|pi|π/i.test(q.replace(/^-/, ""))) return null
    var tokens = tokenize(q)
    if (!tokens || !tokens.length) return null
    try {
        var v = parse(tokens)
        var shown = format(v)
        return shown === null ? null : { value: v, display: shown, expression: q }
    } catch (e) {
        return null
    }
}

// ------------------------------------------------------- unit conversions
// name → [kind, factor to the kind's base unit, label]
var UNITS = {}
function unit(names, kind, factor, label) { names.forEach(function (n) { UNITS[n] = [kind, factor, label] }) }
unit(["mm", "millimeter", "millimeters", "millimetre", "millimetres"], "length", 0.001, "mm")
unit(["cm", "centimeter", "centimeters", "centimetre", "centimetres"], "length", 0.01, "cm")
unit(["m", "meter", "meters", "metre", "metres"], "length", 1, "m")
unit(["km", "kilometer", "kilometers", "kilometre", "kilometres"], "length", 1000, "km")
unit(["in", "inch", "inches", "\""], "length", 0.0254, "in")
unit(["ft", "foot", "feet", "'"], "length", 0.3048, "ft")
unit(["yd", "yard", "yards"], "length", 0.9144, "yd")
unit(["mi", "mile", "miles"], "length", 1609.344, "mi")
unit(["mg", "milligram", "milligrams"], "mass", 1e-6, "mg")
unit(["g", "gram", "grams"], "mass", 0.001, "g")
unit(["kg", "kilo", "kilos", "kilogram", "kilograms"], "mass", 1, "kg")
unit(["lb", "lbs", "pound", "pounds"], "mass", 0.45359237, "lb")
unit(["oz", "ounce", "ounces"], "mass", 0.028349523125, "oz")
unit(["ml", "milliliter", "milliliters", "millilitre", "millilitres"], "volume", 0.001, "mL")
unit(["l", "liter", "liters", "litre", "litres"], "volume", 1, "L")
unit(["floz", "fl oz", "fluid ounce", "fluid ounces"], "volume", 0.0295735295625, "fl oz")
unit(["cup", "cups"], "volume", 0.2365882365, "cups")
unit(["pt", "pint", "pints"], "volume", 0.473176473, "pt")
unit(["qt", "quart", "quarts"], "volume", 0.946352946, "qt")
unit(["gal", "gallon", "gallons"], "volume", 3.785411784, "gal")
unit(["b", "byte", "bytes"], "data", 1, "B")
unit(["kb", "kilobyte", "kilobytes"], "data", 1e3, "KB")
unit(["mb", "megabyte", "megabytes"], "data", 1e6, "MB")
unit(["gb", "gigabyte", "gigabytes"], "data", 1e9, "GB")
unit(["tb", "terabyte", "terabytes"], "data", 1e12, "TB")
unit(["s", "sec", "secs", "second", "seconds"], "time", 1, "s")
unit(["min", "mins", "minute", "minutes"], "time", 60, "min")
unit(["h", "hr", "hrs", "hour", "hours"], "time", 3600, "h")
unit(["day", "days"], "time", 86400, "days")
unit(["week", "weeks"], "time", 604800, "weeks")
unit(["mph"], "speed", 0.44704, "mph")
unit(["kmh", "km/h", "kph"], "speed", 1 / 3.6, "km/h")
unit(["m/s", "mps"], "speed", 1, "m/s")
unit(["c", "°c", "celsius"], "temperature", "c", "°C")
unit(["f", "°f", "fahrenheit"], "temperature", "f", "°F")
unit(["k", "kelvin"], "temperature", "k", "K")

function toKelvin(v, u) { return u === "c" ? v + 273.15 : u === "f" ? (v - 32) * 5 / 9 + 273.15 : v }
function fromKelvin(v, u) { return u === "c" ? v - 273.15 : u === "f" ? (v - 273.15) * 9 / 5 + 32 : v }

// "5 km in mi", "70 f to c", "3 cups in ml" → { value, display }, or null.
function convert(text) {
    var m = /^\s*(-?[\d.,]+)\s*([a-z°"'\/ ]+?)\s+(?:to|in|as|into|=)\s+([a-z°"'\/ ]+?)\s*$/i.exec(String(text || ""))
    if (!m) return null
    var n = parseFloat(m[1].replace(/,/g, ""))
    var from = UNITS[m[2].trim().toLowerCase()], to = UNITS[m[3].trim().toLowerCase()]
    if (!isFinite(n) || !from || !to || from[0] !== to[0]) return null
    var v = from[0] === "temperature" ? fromKelvin(toKelvin(n, from[1]), to[1]) : n * from[1] / to[1]
    // As the Mac rounds them: 3.11 mi, 21.1 °C, 709.8 mL, 0.0254 m.
    var a = Math.abs(v)
    var rounded = a >= 100 ? Math.round(v * 10) / 10 : a >= 1 ? Math.round(v * 100) / 100 : parseFloat(v.toPrecision(3))
    var shown = format(rounded)
    return { value: v, display: shown + " " + to[2], expression: format(n) + " " + from[2] }
}

// --------------------------------------------------- System Settings panes
// [pane id (gg-settings), title, words people search for]
var PANES = [
    ["wifi", "Wi-Fi", "wifi wireless internet network ssid"],
    ["bluetooth", "Bluetooth", "airpods headphones pair devices"],
    ["network", "Network", "ethernet vpn proxy ip dns"],
    ["battery", "Battery", "power energy charging low power"],
    ["general", "General", "system"],
    ["about", "About", "version computer name hardware memory serial"],
    ["update", "Software Update", "updates upgrade golden gate packages"],
    ["storage", "Storage", "disk space"],
    ["accessibility", "Accessibility", "zoom reduce motion transparency contrast"],
    ["appearance", "Appearance", "dark mode light mode accent color theme glass"],
    ["dock", "Desktop & Dock", "dock size magnification hot corners"],
    ["displays", "Displays", "brightness resolution night shift scale monitor"],
    ["wallpaper", "Wallpaper", "background desktop picture"],
    ["focus", "Focus", "do not disturb notifications dnd"],
    ["sound", "Sound", "volume output input microphone speakers"],
    ["privacy", "Privacy & Security", "location camera permissions firewall"],
    ["users", "Users & Groups", "accounts password login user"],
    ["keyboard", "Keyboard", "shortcuts layout input sources key repeat"],
    ["trackpad", "Trackpad & Mouse", "mouse scrolling tap click pointer speed"],
    ["datetime", "Date & Time", "clock time zone"],
    ["language", "Language & Region", "locale region format"]
]

function settings(text) {
    var q = String(text || "").trim().toLowerCase()
    if (q.length < 2) return []
    var hits = []
    PANES.forEach(function (p) {
        var title = p[1].toLowerCase()
        var score = title.indexOf(q) === 0 ? 0 : title.indexOf(q) > 0 ? 1
            : p[2].split(" ").some(function (w) { return w.indexOf(q) === 0 }) || p[2].indexOf(q) >= 0 ? 2 : -1
        if (score >= 0) hits.push({ pane: p[0], title: p[1], score: score })
    })
    return hits.sort(function (a, b) { return a.score - b.score }).slice(0, 4)
}
