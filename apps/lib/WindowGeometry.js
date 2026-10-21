.pragma library
// Window placement is shared by Quickshell app windows and the Qt Web browser.
// The compositor's launch rule in compositor/hyprland/hyprland.conf centers a
// floating window with a 28px upward bias, between the menu bar and the Dock.
// Keep CENTER_BIAS in sync with that rule if its geometry ever changes.
var CENTER_BIAS = 28;
var SIDE_MARGIN = 24;
var EDGE_MARGIN = 14;
var DOCK_EXTRA = 22;
var UNKNOWN_SIZE = 16777215;

function dimension(value, fallback) {
    var n = Number(value);
    return isFinite(n) && n > 0 ? n : fallback;
}
function maximumWidth(displayWidth) {
    var w = dimension(displayWidth, 0);
    return w ? Math.max(160, Math.floor(w - SIDE_MARGIN * 2)) : UNKNOWN_SIZE;
}
function maximumHeight(displayHeight, dockSize, menuBarHeight) {
    var h = dimension(displayHeight, 0);
    if (!h) return UNKNOWN_SIZE;
    var menu = dimension(menuBarHeight, 30);
    var dock = dimension(dockSize, 54) + DOCK_EXTRA;
    // When centered with the compositor's upward bias, the top and bottom
    // distances are (H - h)/2 - B and (H - h)/2 + B respectively.
    var halfGap = Math.max(menu + EDGE_MARGIN + CENTER_BIAS,
                          dock + EDGE_MARGIN - CENTER_BIAS);
    return Math.max(140, Math.floor(h - 2 * halfGap));
}
function fitWidth(preferred, displayWidth) {
    return Math.min(preferred, maximumWidth(displayWidth));
}
function fitHeight(preferred, displayHeight, dockSize, menuBarHeight) {
    return Math.min(preferred, maximumHeight(displayHeight, dockSize, menuBarHeight));
}
