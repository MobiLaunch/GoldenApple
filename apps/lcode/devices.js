// Simulated devices. Sizes are in points; names are LCode's own.
// The app's window fills the screen minus the system areas (status bar, home
// indicator, camera housing in landscape), like a safe area.
.pragma library

var OS_NAME = "LOS";
var OS_VERSION = "26.0";

var DEVICES = [
    { id: "lphone-16", name: "LPhone 16", tablet: false, width: 393, height: 852, corner: 55, bezelX: 14, bezelY: 14, statusBar: 54, homeIndicator: 34, cutout: "island" },
    { id: "lphone-16-pro-max", name: "LPhone 16 Pro Max", tablet: false, width: 440, height: 956, corner: 62, bezelX: 14, bezelY: 14, statusBar: 62, homeIndicator: 34, cutout: "island" },
    { id: "lphone-se", name: "LPhone SE", tablet: false, width: 375, height: 667, corner: 0, bezelX: 22, bezelY: 96, statusBar: 20, homeIndicator: 0, cutout: "home-button" },
    { id: "lpad-air-11", name: "LPad Air 11-inch", tablet: true, width: 820, height: 1180, corner: 18, bezelX: 24, bezelY: 24, statusBar: 24, homeIndicator: 20, cutout: "none" },
    { id: "lpad-pro-13", name: "LPad Pro 13-inch", tablet: true, width: 1032, height: 1376, corner: 18, bezelX: 22, bezelY: 22, statusBar: 24, homeIndicator: 20, cutout: "none" },
];

function byId(id) {
    for (var i = 0; i < DEVICES.length; i++) if (DEVICES[i].id === id) return DEVICES[i];
    return null;
}

// orientation: 0 portrait, -90 landscape left (top of the device to the left), 90 landscape right.
function isLandscape(o) { return o !== 0; }

function screenSize(d, o) { return isLandscape(o) ? { w: d.height, h: d.width } : { w: d.width, h: d.height }; }

function bodySize(d, o) {
    var w = d.width + 2 * d.bezelX, h = d.height + 2 * d.bezelY;
    return isLandscape(o) ? { w: h, h: w } : { w: w, h: h };
}

function insets(d, o) {
    if (!isLandscape(o) || d.tablet) return { top: d.statusBar, bottom: d.homeIndicator, left: 0, right: 0 };
    // Phones hide the status bar in landscape and keep the camera side clear.
    if (d.cutout === "island") return { top: 0, bottom: 21, left: 59, right: 59 };
    return { top: 0, bottom: 0, left: 0, right: 0 };
}

function appSize(d, o) {
    var s = screenSize(d, o), i = insets(d, o);
    return { w: Math.round(s.w - i.left - i.right), h: Math.round(s.h - i.top - i.bottom) };
}

// Side of the square virtual display: big enough for both orientations.
function displaySide(d) {
    var p = appSize(d, 0), l = appSize(d, -90);
    return Math.max(p.w, p.h, l.w, l.h);
}

// What LCode's backend needs to run an app on the device.
function runTarget(d, o) {
    var a = appSize(d, o);
    return { id: d.id, name: d.name, side: displaySide(d), w: a.w, h: a.h };
}

// Your own devices (Settings ▸ Simulators): a name, a screen size in points,
// and the kind of hardware around it.
var STYLES = ["island", "home-button", "none"];
function customDevice(spec) {
    var tablet = !!spec.tablet, style = STYLES.indexOf(spec.style) >= 0 ? spec.style : "island";
    var homeButton = style === "home-button";
    return {
        id: spec.id, name: spec.name || "Custom Device", tablet: tablet, custom: true, style: style,
        width: Math.max(240, Math.min(2048, Math.round(spec.width || 393))),
        height: Math.max(240, Math.min(2048, Math.round(spec.height || 852))),
        corner: homeButton ? 0 : (spec.corner !== undefined ? spec.corner : (tablet ? 18 : 55)),
        bezelX: homeButton ? 22 : (tablet ? 22 : 14), bezelY: homeButton ? 96 : (tablet ? 22 : 14),
        statusBar: homeButton ? 20 : tablet ? 24 : style === "none" ? 24 : 54,
        homeIndicator: homeButton ? 0 : tablet ? 20 : 34,
        cutout: style,
    };
}
function all(custom) {
    var out = DEVICES.slice();
    for (var i = 0; i < (custom || []).length; i++) out.push(customDevice(custom[i]));
    return out;
}
function find(id, custom) {
    var list = all(custom);
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
    return null;
}
