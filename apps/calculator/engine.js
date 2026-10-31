// Calculator arithmetic and number formatting, as Calculator on the Mac does it:
// the expression is evaluated with the usual precedence (powers, then × and ÷,
// then + and −, parentheses first), numbers show thousands separators, and
// long results fall back to exponents. Also the scientific functions, the
// Programmer mode's 64-bit integer arithmetic, and unit conversion.
.pragma library

var OPS = { "+": "+", "-": "−", "*": "×", "/": "÷", "^": "^", "root": "ʸ√", "EE": "E", "logy": "log",
            "rpow": "ˣ√", "(": "(", ")": ")",
            "and": " AND ", "or": " OR ", "xor": " XOR ", "nor": " NOR ", "shl": " << ", "shr": " >> ", "mod": " mod " };
var PREC = { "+": 1, "-": 1, "*": 2, "/": 2, "^": 3, "root": 3, "EE": 3, "logy": 3, "rpow": 3 };
var RIGHT = { "^": true, "rpow": true };

function apply(op, a, b) {
    switch (op) {
    case "+": return a + b;
    case "-": return a - b;
    case "*": return a * b;
    case "/": return b === 0 ? NaN : a / b;
    case "^": return Math.pow(a, b);
    case "rpow": return Math.pow(b, a);                         // yˣ: the second number to the power of the first
    case "root": return b === 0 ? NaN : (a < 0 && Math.round(b) % 2 === 1 ? -Math.pow(-a, 1 / b) : Math.pow(a, 1 / b));
    case "EE": return a * Math.pow(10, b);
    case "logy": return Math.log(a) / Math.log(b);              // log base y of x
    }
    return NaN;
}

// tokens: numbers, operators ("+ - * / ^ root EE logy rpow") and parentheses.
// A trailing operator is dropped and open parentheses are closed, as the Mac does.
function evaluate(tokens) {
    var t = tokens.slice();
    while (t.length && typeof t[t.length - 1] !== "number" && t[t.length - 1] !== ")") t.pop();
    if (!t.length) return 0;
    var out = [], ops = [];
    function reduce() {
        var op = ops.pop(), b = out.pop(), a = out.pop();
        out.push(apply(op, a === undefined ? 0 : a, b === undefined ? 0 : b));
    }
    for (var i = 0; i < t.length; i++) {
        var x = t[i];
        if (typeof x === "number") out.push(x);
        else if (x === "(") ops.push(x);
        else if (x === ")") {
            while (ops.length && ops[ops.length - 1] !== "(") reduce();
            if (ops.length) ops.pop();
        } else {
            while (ops.length && ops[ops.length - 1] !== "(" &&
                   (PREC[ops[ops.length - 1]] > PREC[x] || (PREC[ops[ops.length - 1]] === PREC[x] && !RIGHT[x]))) reduce();
            ops.push(x);
        }
    }
    while (ops.length) { if (ops[ops.length - 1] === "(") ops.pop(); else reduce(); }
    return out.length ? out[out.length - 1] : 0;
}

function factorial(x) {
    if (x < 0 || x !== Math.floor(x) || x > 170) return NaN;
    var r = 1;
    for (var i = 2; i <= x; i++) r *= i;
    return r;
}

// One-number functions, applied to what's on the display. Angles in degrees
// unless rad is true.
function unary(name, x, rad) {
    var k = rad ? 1 : Math.PI / 180;
    switch (name) {
    case "x2": return x * x;
    case "x3": return x * x * x;
    case "sqrt": return x < 0 ? NaN : Math.sqrt(x);
    case "cbrt": return Math.cbrt(x);
    case "recip": return x === 0 ? NaN : 1 / x;
    case "fact": return factorial(x);
    case "exp": return Math.exp(x);
    case "exp10": return Math.pow(10, x);
    case "exp2": return Math.pow(2, x);
    case "ln": return x <= 0 ? NaN : Math.log(x);
    case "log10": return x <= 0 ? NaN : Math.log10(x);
    case "log2": return x <= 0 ? NaN : Math.log2(x);
    case "sin": return clean(Math.sin(x * k));
    case "cos": return clean(Math.cos(x * k));
    case "tan": return Math.abs(Math.cos(x * k)) < 1e-15 ? NaN : clean(Math.tan(x * k));
    case "asin": return Math.abs(x) > 1 ? NaN : Math.asin(x) / k;
    case "acos": return Math.abs(x) > 1 ? NaN : Math.acos(x) / k;
    case "atan": return Math.atan(x) / k;
    case "sinh": return Math.sinh(x);
    case "cosh": return Math.cosh(x);
    case "tanh": return Math.tanh(x);
    case "asinh": return Math.asinh(x);
    case "acosh": return x < 1 ? NaN : Math.acosh(x);
    case "atanh": return Math.abs(x) >= 1 ? NaN : Math.atanh(x);
    case "percent": return x / 100;
    case "neg": return -x;
    }
    return NaN;
}

// sin 180° is 0, not 1.2e-16.
function clean(v) { return Math.abs(v) < 1e-12 ? 0 : v; }

// Thousands separators on the integer part of a numeric string, as typed.
function groupTyped(s) {
    var neg = s.charAt(0) === "-";
    if (neg) s = s.slice(1);
    var dot = s.indexOf(".");
    var intPart = dot < 0 ? s : s.slice(0, dot), frac = dot < 0 ? "" : s.slice(dot);
    intPart = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return (neg ? "-" : "") + intPart + frac;
}

// A computed number for display: at most `digits` significant digits (9, as
// the Mac's basic calculator; 12 in Scientific).
function format(n, digits) {
    var d = digits || 9;
    if (!isFinite(n)) return "Error";
    if (n === 0) return "0";
    var abs = Math.abs(n);
    if (abs >= Math.pow(10, d) || abs < Math.pow(10, -(d - 1))) {
        var e = n.toExponential(Math.min(d - 4, 8)).replace(/\.?0+e/, "e").replace("e+", "e");
        return e;
    }
    var s = Number(n.toPrecision(d)).toString();
    if (s.indexOf("e") >= 0) s = Number(n).toFixed(d - 1).replace(/\.?0+$/, "");
    return groupTyped(s);
}

function expression(tokens, current, digits) {
    var out = "";
    for (var i = 0; i < tokens.length; i++)
        out += typeof tokens[i] === "number" ? format(tokens[i], digits) : (OPS[tokens[i]] || tokens[i]);
    if (current !== "") out += groupTyped(current);
    return out;
}

// ------------------------------------------------------------- Programmer
// 64-bit integers, shown unsigned in base 2, 8, 10 or 16, as the Mac does.
// Qt's JavaScript has no BigInt: a value is four 16-bit limbs, lowest first,
// so every product stays exact in a double.
function u64(n) {
    n = Math.max(0, Math.floor(n || 0));
    var r = [0, 0, 0, 0];
    for (var i = 0; i < 4 && n > 0; i++) { r[i] = n % 65536; n = Math.floor(n / 65536); }
    return r;
}
function isU64(x) { return Array.isArray(x) && x.length === 4; }
function isZero(a) { return !a[0] && !a[1] && !a[2] && !a[3]; }
function cmp(a, b) {
    for (var i = 3; i >= 0; i--) if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1;
    return 0;
}
function add(a, b) {
    var r = [0, 0, 0, 0], c = 0;
    for (var i = 0; i < 4; i++) { var t = a[i] + b[i] + c; r[i] = t % 65536; c = t >= 65536 ? 1 : 0; }
    return r;
}
function bnot(a) { return [65535 - a[0], 65535 - a[1], 65535 - a[2], 65535 - a[3]]; }
function neg(a) { return add(bnot(a), [1, 0, 0, 0]); }
function sub(a, b) { return add(a, neg(b)); }
function mul(a, b) {
    var r = [0, 0, 0, 0];
    for (var i = 0; i < 4; i++) {
        var c = 0;
        for (var j = 0; i + j < 4; j++) {
            var t = r[i + j] + a[i] * b[j] + c;
            r[i + j] = t % 65536; c = Math.floor(t / 65536);
        }
    }
    return r;
}
function band(a, b) { return [a[0] & b[0], a[1] & b[1], a[2] & b[2], a[3] & b[3]]; }
function bor(a, b) { return [a[0] | b[0], a[1] | b[1], a[2] | b[2], a[3] | b[3]]; }
function bxor(a, b) { return [a[0] ^ b[0], a[1] ^ b[1], a[2] ^ b[2], a[3] ^ b[3]]; }
function shl(a, n) {
    if (n >= 64) return [0, 0, 0, 0];
    var r = a.slice();
    for (var k = 0; k < n; k++) {
        var c = 0;
        for (var i = 0; i < 4; i++) { var t = r[i] * 2 + c; r[i] = t % 65536; c = t >= 65536 ? 1 : 0; }
    }
    return r;
}
function shr(a, n) {
    if (n >= 64) return [0, 0, 0, 0];
    var r = a.slice();
    for (var k = 0; k < n; k++) {
        var c = 0;
        for (var i = 3; i >= 0; i--) { var t = r[i] + c * 65536; r[i] = Math.floor(t / 2); c = t % 2; }
    }
    return r;
}
function small(a) { return a[0] + a[1] * 65536 + a[2] * 4294967296 + a[3] * 281474976710656; }  // exact below 2^53
function divmod(a, b) {
    if (isZero(b)) return null;
    var q = [0, 0, 0, 0], r = [0, 0, 0, 0];
    for (var i = 63; i >= 0; i--) {
        r = shl(r, 1);
        if (bit(a, i)) r[0] |= 1;
        if (cmp(r, b) >= 0) { r = sub(r, b); q = toggleBit(q, i); }
    }
    return [q, r];
}
function parseInt64(s, base) {
    var digits = "0123456789ABCDEF", v = [0, 0, 0, 0], b = u64(base);
    s = String(s || "").toUpperCase();
    for (var i = 0; i < s.length; i++) {
        var d = digits.indexOf(s.charAt(i));
        if (d < 0 || d >= base) continue;
        v = add(mul(v, b), u64(d));
    }
    return v;
}
function toBase(v, base) {
    if (isZero(v)) return "0";
    var digits = "0123456789ABCDEF", out = "", x = v.slice(), b = u64(base);
    while (!isZero(x)) { var qr = divmod(x, b); out = digits.charAt(qr[1][0]) + out; x = qr[0]; }
    if (base === 16 || base === 2) out = out.replace(/\B(?=(\w{4})+(?!\w))/g, " ");
    else if (base === 10) out = out.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return out;
}
var PPREC = { "*": 6, "/": 6, "mod": 6, "+": 5, "-": 5, "shl": 4, "shr": 4, "and": 3, "xor": 2, "or": 1, "nor": 1 };
function papply(op, a, b) {
    var q;
    switch (op) {
    case "+": return add(a, b);
    case "-": return sub(a, b);
    case "*": return mul(a, b);
    case "/": q = divmod(a, b); return q ? q[0] : null;
    case "mod": q = divmod(a, b); return q ? q[1] : null;
    case "and": return band(a, b);
    case "or": return bor(a, b);
    case "xor": return bxor(a, b);
    case "nor": return bnot(bor(a, b));
    case "shl": return shl(a, Math.min(64, small(b)));
    case "shr": return shr(a, Math.min(64, small(b)));
    }
    return null;
}
// tokens: 64-bit values and programmer operators. null means Error (÷ 0).
function pevaluate(tokens) {
    var t = tokens.slice();
    while (t.length && !isU64(t[t.length - 1])) t.pop();
    if (!t.length) return [0, 0, 0, 0];
    var out = [], ops = [];
    function reduce() {
        var op = ops.pop(), b = out.pop(), a = out.pop();
        out.push(a === null || b === null ? null : papply(op, a, b));
    }
    for (var i = 0; i < t.length; i++) {
        var x = t[i];
        if (isU64(x)) { out.push(x); continue; }
        while (ops.length && PPREC[ops[ops.length - 1]] >= PPREC[x]) reduce();
        ops.push(x);
    }
    while (ops.length) reduce();
    return out[out.length - 1];
}
function punary(name, v) {
    switch (name) {
    case "ones": return bnot(v);
    case "twos": return neg(v);
    case "shl1": return shl(v, 1);
    case "shr1": return shr(v, 1);
    case "rol": return bor(shl(v, 1), shr(v, 63));
    case "ror": return bor(shr(v, 1), shl(band(v, [1, 0, 0, 0]), 63));
    case "flipb": return [((v[0] & 255) << 8) | (v[0] >> 8), v[1], v[2], v[3]];   // the lowest two bytes swap
    case "flipw": return [v[1], v[0], v[2], v[3]];                                 // the lowest two words swap
    }
    return v;
}
function bit(v, i) { return (v[i >> 4] >> (i & 15)) & 1; }
function toggleBit(v, i) { var r = v.slice(); r[i >> 4] ^= 1 << (i & 15); return r; }
function pexpression(tokens, current, base) {
    var out = "";
    for (var i = 0; i < tokens.length; i++)
        out += isU64(tokens[i]) ? toBase(tokens[i], base) : (OPS[tokens[i]] || tokens[i]);
    return out + current;
}

// ------------------------------------------------------------- Conversion
// Each unit's size in its category's base unit; temperature has formulas.
var UNITS = {
    "Length": { "Millimeters": 0.001, "Centimeters": 0.01, "Meters": 1, "Kilometers": 1000, "Inches": 0.0254,
                "Feet": 0.3048, "Yards": 0.9144, "Miles": 1609.344, "Nautical Miles": 1852 },
    "Mass": { "Milligrams": 1e-6, "Grams": 0.001, "Kilograms": 1, "Metric Tons": 1000, "Ounces": 0.028349523125,
              "Pounds": 0.45359237, "Stones": 6.35029318 },
    "Temperature": { "Celsius": 1, "Fahrenheit": 1, "Kelvin": 1 },
    "Volume": { "Milliliters": 0.001, "Liters": 1, "Cubic Meters": 1000, "Teaspoons": 0.00492892159375,
                "Tablespoons": 0.01478676478125, "Fluid Ounces": 0.0295735295625, "Cups": 0.2365882365,
                "Pints": 0.473176473, "Quarts": 0.946352946, "Gallons": 3.785411784 },
    "Area": { "Square Meters": 1, "Square Kilometers": 1e6, "Square Feet": 0.09290304, "Square Miles": 2589988.110336,
              "Acres": 4046.8564224, "Hectares": 10000 },
    "Speed": { "Meters per Second": 1, "Kilometers per Hour": 1 / 3.6, "Miles per Hour": 0.44704, "Knots": 1852 / 3600 },
    "Time": { "Seconds": 1, "Minutes": 60, "Hours": 3600, "Days": 86400, "Weeks": 604800, "Years": 31557600 },
    "Data": { "Bytes": 1, "Kilobytes": 1e3, "Megabytes": 1e6, "Gigabytes": 1e9, "Terabytes": 1e12,
              "Kibibytes": 1024, "Mebibytes": 1048576, "Gibibytes": 1073741824 },
    "Energy": { "Joules": 1, "Kilojoules": 1000, "Calories": 4.184, "Kilocalories": 4184, "Watt-hours": 3600,
                "Kilowatt-hours": 3.6e6 },
    "Pressure": { "Pascals": 1, "Kilopascals": 1000, "Bars": 1e5, "Atmospheres": 101325, "PSI": 6894.757293168,
                  "mmHg": 133.322387415 },
    "Angle": { "Degrees": Math.PI / 180, "Radians": 1, "Gradians": Math.PI / 200, "Turns": 2 * Math.PI }
};
function categories() { return Object.keys(UNITS); }
function units(category) { return Object.keys(UNITS[category] || {}); }
function convert(value, category, from, to) {
    if (category === "Temperature") {
        var c = from === "Celsius" ? value : from === "Fahrenheit" ? (value - 32) * 5 / 9 : value - 273.15;
        return to === "Celsius" ? c : to === "Fahrenheit" ? c * 9 / 5 + 32 : c + 273.15;
    }
    var u = UNITS[category];
    if (!u || !(from in u) || !(to in u)) return NaN;
    return value * u[from] / u[to];
}
