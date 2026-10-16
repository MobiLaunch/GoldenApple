// Run with: node --test tests/window-placement.mjs
// Checks the production QML/Hyprland wiring and the actual geometry helper.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { fileURLToPath } from "node:url";

const root = new URL("../", import.meta.url);
const read = (path) => readFileSync(new URL(path, root), "utf8");
const source = read("apps/lib/WindowGeometry.js");
const geometry = {};
runInNewContext(source.replace(/^\.pragma library\s*$/m, ""), geometry);

test("native apps and browser both use shared limits", () => {
    const app = read("apps/lib/AppWindow.qml");
    const browser = read("apps/browser/Browser.qml");
    assert.match(app, /WindowGeometry\.maximumWidth\(_placementScreenWidth\)/);
    assert.match(app, /WindowGeometry\.maximumHeight\(_placementScreenHeight/);
    assert.match(app, /maximumSize:\s*Qt\.size\(/);
    assert.match(app, /closeAction: function\(\) \{ win\.closeWindow\(\) \}/);
    assert.match(browser, /maximumWidth:\s*_maxLaunchWidth/);
    assert.match(browser, /maximumHeight:\s*_maxLaunchHeight/);
    assert.match(browser, /WindowGeometry\.maximumHeight\(Screen\.height/);
});

test("the compositor bias matches the layout contract", () => {
    const conf = read("compositor/hyprland/hyprland.conf");
    assert.match(conf, /match:class \.\*, float on, move/);
    assert.ok(conf.includes("((monitor_w-window_w)*0.5)"));
    assert.ok(conf.includes("((monitor_h-window_h)*0.5-" + geometry.CENTER_BIAS + ")"));
});

test("first frame leaves the menu bar, Dock and traffic lights accessible", () => {
    const screens = [
        [1366, 768, 54],
        [800, 600, 90],
        [640, 480, 90],
        [1920, 1080, 54],
        [1280, 720, 120],
        [1024, 768, 100],
        [2560, 1440, 140]
    ];
    for (const [screenWidth, screenHeight, dockSize] of screens) {
        const width = geometry.fitWidth(1180, screenWidth);
        const height = geometry.fitHeight(780, screenHeight, dockSize, 30);
        const x = (screenWidth - width) / 2;
        const y = (screenHeight - height) / 2 - geometry.CENTER_BIAS;
        assert.ok(x >= geometry.SIDE_MARGIN, "left margin");
        assert.ok(screenWidth - x - width >= geometry.SIDE_MARGIN, "right margin");
        assert.ok(y >= 30 + geometry.EDGE_MARGIN, "title bar cleared");
        assert.ok(screenHeight - y - height >= dockSize + geometry.DOCK_EXTRA + geometry.EDGE_MARGIN, "Dock cleared");
    }
});

test("unknown screen falls back to the toolkit's unconstrained size", () => {
    assert.equal(geometry.maximumWidth(0), geometry.UNKNOWN_SIZE);
    assert.equal(geometry.maximumHeight(0, 54, 30), geometry.UNKNOWN_SIZE);
});

test("launch animation targets the compositor's centered coordinates", () => {
    const launch = read("shell/AppLaunch.qml");
    assert.match(launch, /import "ui\/WindowGeometry\.js" as WindowGeometry/);
    assert.match(launch, /WindowGeometry\.fitWidth\(size\.w, width\)/);
    assert.match(launch, /WindowGeometry\.fitHeight\(size\.h, height, dockSize, Theme\.sizeMenubar\)/);
    assert.match(launch, /\(height - h\) \/ 2 - WindowGeometry\.CENTER_BIAS/);
    for (const [displayWidth, displayHeight, dockSize] of [[1920,1080,54],[1366,768,90],[800,600,90]]) {
        const width = geometry.fitWidth(1180, displayWidth);
        const height = geometry.fitHeight(780, displayHeight, dockSize, 30);
        assert.ok((displayHeight-height)/2-geometry.CENTER_BIAS >= 44);
        assert.ok((displayWidth-width)/2 >= 24);
    }
});

test("compositor exit uses a soft native fade rather than a false window fold", () => {
    const generator = read("design/build.mjs");
    const built = read("design/dist/hyprland-motion.conf");
    assert.match(generator, /animation = windowsOut, 1, 2, smooth, popin 100%/);
    assert.match(generator, /animation = fadeOut, 1, 2, smooth/);
    assert.match(built, /animation = windowsOut, 1, 2, smooth, popin 100%/);
    assert.match(built, /animation = fadeOut, 1, 2, smooth/);
});

test("Dock exits are deadline-driven and activating parked windows raises them", () => {
    const dock = read("shell/Dock.qml");
    assert.match(dock, /onRunningRecordsChanged: Qt\.callLater\(dock\.scheduleRecentExpiry\)/);
    assert.match(dock, /onTriggered: \{\s+dock\.expireRecent\(\)\s+\/\/[^\n]*\n\s+\/\/[^\n]*\n\s+Qt\.callLater\(dock\.scheduleRecentExpiry\)/);
    assert.match(dock, /id: recentExpiry\s+objectName: "dockRecentExpiry"\s+repeat: false/);
    assert.doesNotMatch(dock, /interval:\s*25; repeat: true/);
    assert.match(dock, /Hyprland\.dispatch\(`focuswindow address:\$\{address\}`\)/);
    assert.match(dock, /id: activatePulse/);
    assert.match(dock, /if \(Prefs\.reduceMotion\) \{ activatePulse\.stop\(\); icon\.activationLift = 0 \}/);
});
