// Calculator arithmetic and number formatting, as Calculator on the Mac does it:
// the expression is evaluated with the usual precedence (× and ÷ before + and −),
// numbers show thousands separators, and long results fall back to exponents.
.pragma library

var OPS = { "+": "+", "-": "−", "*": "×", "/": "÷" };

// tokens: numbers and operator characters, alternating, starting with a number.
function evaluate(tokens) {
    var t = tokens.slice();
    if (t.length && typeof t[t.length - 1] !== "number") t.pop();
    if (!t.length) return 0;
    // × and ÷ first
    var terms = [t[0]];
    for (var i = 1; i < t.length; i += 2) {
        var op = t[i], n = t[i + 1];
        if (op === "*") terms[terms.length - 1] *= n;
        else if (op === "/") terms[terms.length - 1] = n === 0 ? NaN : terms[terms.length - 1] / n;
        else terms.push(op, n);
    }
    var r = terms[0];
    for (var j = 1; j < terms.length; j += 2) r = terms[j] === "+" ? r + terms[j + 1] : r - terms[j + 1];
    return r;
}

// Thousands separators on the integer part of a numeric string, as typed.
function groupTyped(s) {
    var neg = s.charAt(0) === "-";
    if (neg) s = s.slice(1);
    var dot = s.indexOf(".");
    var intPart = dot < 0 ? s : s.slice(0, dot), frac = dot < 0 ? "" : s.slice(dot);
    intPart = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return (neg ? "-" : "") + intPart + frac;
}

// A computed number for display: at most 9 significant digits, like the Mac.
function format(n) {
    if (!isFinite(n)) return "Error";
    if (n === 0) return "0";
    var abs = Math.abs(n);
    if (abs >= 1e9 || abs < 1e-8) {
        var e = n.toExponential(5).replace(/\.?0+e/, "e").replace("e+", "e");
        return e;
    }
    var s = Number(n.toPrecision(9)).toString();
    if (s.indexOf("e") >= 0) s = Number(n).toFixed(8).replace(/\.?0+$/, "");
    return groupTyped(s);
}

function expression(tokens, current) {
    var out = "";
    for (var i = 0; i < tokens.length; i++)
        out += typeof tokens[i] === "number" ? format(tokens[i]) : OPS[tokens[i]];
    if (current !== "") out += groupTyped(current);
    return out;
}
