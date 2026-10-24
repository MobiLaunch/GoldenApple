// Paragraph styles for Notes, done on the note's Markdown: Qt's TextEdit can
// format characters from QML (bold, italic, …) but has no QML API for block
// formats, so a style change rewrites the prefix of that block's Markdown line
// ("# " title, "## " heading, "- [ ] " checklist, …) and reloads the text.
// Plain-text positions don't change, since the prefixes aren't text.
.pragma library

var MARK = /^(\s*)(#{1,6}\s+|(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?)?/;
var LIST = /^\s*(?:[-*+]|\d+[.)])\s+/;

// Index of the Markdown line where each document block starts. Blocks are
// separated by blank lines, except list items and headings, which start a
// block on their own; other lines continue the block above (Qt wraps long
// paragraphs at 80 columns when it writes Markdown).
function blockLines(md) {
    var lines = md.split("\n"), starts = [], prevBlank = true, prevHeading = false;
    for (var i = 0; i < lines.length; i++) {
        var l = lines[i];
        if (!l.trim()) { prevBlank = true; continue; }
        var heading = /^#{1,6}\s/.test(l);
        if (prevBlank || prevHeading || heading || LIST.test(l)) starts.push(i);
        prevBlank = false;
        prevHeading = heading;
    }
    return starts;
}

// The block the cursor is in. TextEdit.getText() separates blocks with U+2029
// (paragraph separator); "\n" is accepted too.
function blockAt(plainBefore) {
    return (plainBefore.match(/[\n\u2029]/g) || []).length;
}
function lineStart(plainBefore) {
    return Math.max(plainBefore.lastIndexOf("\n"), plainBefore.lastIndexOf("\u2029")) + 1;
}

var PREFIX = {
    title: "# ", heading: "## ", subheading: "### ", body: "",
    bullet: "- ", number: "1. ", check: "- [ ] ",
};

// The style of a block's line: title | heading | subheading | bullet | number | check | done | body.
function styleOf(md, block) {
    var starts = blockLines(md), lines = md.split("\n");
    if (block >= starts.length) return "body";
    var l = lines[starts[block]];
    if (/^#\s/.test(l)) return "title";
    if (/^##\s/.test(l)) return "heading";
    if (/^#{3,6}\s/.test(l)) return "subheading";
    if (/^\s*[-*+]\s+\[[xX]\]\s/.test(l)) return "done";
    if (/^\s*[-*+]\s+\[ \]\s/.test(l)) return "check";
    if (/^\s*\d+[.)]\s/.test(l)) return "number";
    if (/^\s*[-*+]\s/.test(l)) return "bullet";
    return "body";
}

// Gives a block a style; applying its current list style again turns it back
// into body text (a toggle, like the toolbar buttons on the Mac).
function setStyle(md, block, style) {
    var starts = blockLines(md), lines = md.split("\n");
    if (!starts.length) { return PREFIX[style] + md; }
    if (block >= starts.length) block = starts.length - 1;
    var i = starts[block], current = styleOf(md, block);
    if (current === style || (style === "check" && current === "done")) style = "body";
    var rest = lines[i].replace(MARK, "");
    var wasList = current === "bullet" || current === "number" || current === "check" || current === "done";
    var toList = style === "bullet" || style === "number" || style === "check";
    lines[i] = PREFIX[style] + rest;
    // A paragraph becoming a list item, or the reverse, needs the blank lines
    // around it to match (list items sit together; paragraphs apart).
    if (!toList && wasList) {
        if (i + 1 < lines.length && lines[i + 1].trim() && LIST.test(lines[i + 1])) lines.splice(i + 1, 0, "");
        if (i > 0 && lines[i - 1].trim()) lines.splice(i, 0, "");
    }
    return lines.join("\n");
}

function toggleCheck(md, block) {
    var starts = blockLines(md), lines = md.split("\n");
    if (block >= starts.length) return md;
    var i = starts[block];
    if (/\[ \]/.test(lines[i])) lines[i] = lines[i].replace("[ ]", "[x]");
    else if (/\[[xX]\]/.test(lines[i])) lines[i] = lines[i].replace(/\[[xX]\]/, "[ ]");
    return lines.join("\n");
}

// A file name from the note's title.
function fileName(title) {
    var t = (title || "New Note").replace(/[\/\\:*?"<>|\u0000-\u001f]/g, "").trim().slice(0, 80);
    return (t || "New Note") + ".md";
}
