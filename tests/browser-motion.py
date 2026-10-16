#!/usr/bin/env python3
"""Web moves instead of cutting: every sheet and popover grows in and fades
(none just switches on), tabs grow in and slide to make room under one
highlight that springs between them, the progress bar runs to the end and
fades, a page fades in when its tab is chosen, the Tab Overview and the Start
Page cascade in, and the toolbar's buttons hop when something happens.

Reads apps/browser/*.qml (a running Web needs Chromium and a desktop user:
tests/native-browser.py drives that, and checks it still works)."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
qml = (ROOT / "apps/browser/Browser.qml").read_text()
start = (ROOT / "apps/browser/StartPage.qml").read_text()
button = (ROOT / "apps/browser/BrowserButton.qml").read_text()
failures = []


def check(cond, what):
    if not cond:
        failures.append(what)


def block(ident):
    """The top-level element with this id, as text."""
    m = re.search(r"\n    \w+ \{\n        id: %s\n" % ident, qml)
    if not m:
        return ""
    end = qml.find("\n    }\n", m.start())
    return qml[m.start():end]


# No sheet or popover just switches on: each reveals (grows and fades) instead.
switched = re.findall(r"\n    \w+ \{\n        id: (\w+)\n(?:        .*\n){0,4}?        visible: root\.\w+Open\n", qml)
check(not switched, f"these appear at once instead of growing in: {switched}")
for ident in ("tabOverview", "searchPopover", "findBar", "downloadsPopover", "settingsSheet", "websitePermissionsSheet",
              "privacySheet", "profileSheet", "tabGroupsManager", "tabGroupSheet", "passwordsSheet", "permissionSheet"):
    b = block(ident)
    check("readonly property bool reveal:" in b and "Behavior on opacity" in b and "Behavior on scale" in b,
          f"{ident} grows in and fades")

# Tabs.
check(re.search(r"id: tabRow[\s\S]{0,200}add: Transition", qml), "a new tab grows in")
check(re.search(r"id: tabRow[\s\S]{0,900}move: Transition", qml), "the other tabs slide to make room")
check("id: activeTabHighlight" in qml and re.search(r"activeTabHighlight[\s\S]{0,900}Behavior on x", qml),
      "one highlight springs between tabs")
check("opacity: tab.closeShown ? 1 : 0" in qml, "a tab's close button fades in under the pointer")
check("scale: tabDrag.active" in qml, "a dragged tab lifts")

# Loading and switching.
check("id: glide" in qml and "PauseAnimation" in qml, "the progress bar runs to the end, then fades")
check("id: pageIn" in qml, "a page fades in when its tab is chosen")
check("id: cardIn" in qml, "the Tab Overview's cards come up one after another")
check("id: favoriteIn" in start, "the Start Page's favorites come up one after another")
check("function bump()" in button and "bookmarkButton.bump()" in qml and "downloadsButton.bump()" in qml,
      "Favorite and Downloads hop when something happens")

# Reduce Motion is honoured everywhere it moves.
for name, text in (("Browser.qml", qml), ("StartPage.qml", start), ("BrowserButton.qml", button)):
    springs = text.count("Spring {")
    check(text.count("reduceMotion") >= springs, f"{name}: Reduce Motion stills what moves")

if failures:
    print("\n".join("FAIL " + f for f in failures), file=sys.stderr)
    sys.exit(1)
print("Web: sheets and popovers grow in, tabs slide under one highlight, loading glides, pages and overviews fade in")
