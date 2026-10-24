# CitronOS 2 "Club Soda": UI/UX Audit

Audit date: 2026-10-24, at commit `ae8cbf4` (the CitronOS shell, after MacShell was
reverted). Findings share the `CS2-` numbering with
[03-BACKEND-AUDIT.md](03-BACKEND-AUDIT.md), and the status values are the same.

## Method and limits

This audit is based on the source code, the design tokens (`design/tokens.json` →
`apps/lib/theme/Theme.qml`), the shared component store (`apps/lib/`), every shell surface,
the larger apps, and the existing screenshots in `docs/screenshots/`. Counts come from
`git grep` over `apps/` and `shell/`.

There was no GPU or Wayland session in this container, so **motion smoothness, frame
pacing and visual rendering were not observed.** Findings about how things look or move
are drawn from the code and marked **Suspected** where the effect has to be seen to be
confirmed. Task T-0.2 in the backlog adds a real-session screenshot and video harness to
settle them.

---

## 1. The design system today

### What exists

- **One token source.** `design/tokens.json` is compiled by `design/build.mjs` into CSS,
  QML (`Theme.qml`), GTK CSS and Hyprland motion. Springs are defined once as
  `{response, dampingFraction}` and emitted as Bézier splines.
- **One component store.** `apps/lib/` provides AppWindow, Glass, Button, Checkbox, Switch,
  Slider, LevelSlider, Segmented, TextField, TextArea, PopupMenu, MenuList, PopUpButton,
  ModalSheet, SidebarRow, SidebarSection, ToolbarButton, ToolbarPill, TrafficLights,
  ProgressBar, EmptyState, Scroller, Symbol, ZoomMenu, AccountRow, FocusRing and
  FocusState. No app imports `QtQuick.Controls` directly, which is excellent.
- **Reduce Motion is wired through everywhere.** There are 323 references to
  `Theme.reduceMotion`, and `tests/micro-interactions.py` guards it.
- **Text Size support.** 836 `pixelSize` bindings go through `Theme.fs()`.

### Where it leaks

| Token family | Uses the token | Literal value | Notes |
|---|---:|---:|---|
| Colour (`"#RRGGBB[AA]"`) | — | **1,586** literals outside `theme/` | Top: Browser.qml 61, settings.qml 44, maps.qml 33, VoiceAssistant.qml 30, calculator.qml 27, LockSurface.qml 25 |
| Corner radius | **16** (`Theme.radius*`) | **426** `radius: <n>` | 25 distinct values, from 1 to 30 (10, 22, 8, 12, 18, 9, 7, 14 and so on) |
| Durations | 130 (`Theme.*`) | **198** `duration: <n>` | 40+ distinct values: 70, 85, 90, 95, 110, 125, 130, 140, 155, 175, 190, 225, 260, 280, 350, 565, 610, 955, 1220 … |
| Type sizes | 836 `Theme.fs(n)` | 17 distinct `n`; 5 raw literals | The semantic ramp (`textBody`, `textTitle1`, …) is used **5 times** in total |

These counts back findings CS2-018 and CS2-043 below.

---

## 2. Findings

### Finding ID: CS2-008

**Area:** Desktop shell / window management
**Category:** UI
**Severity:** P1
**Current implementation:** The menu bar and the Dock are layer surfaces on
`WlrLayer.Overlay`. They keep their exclusive zones and never hide. Nothing in the shell
reacts to a fullscreen window.
**Evidence:**
- `shell/Dock.qml:215` and `shell/MenuBar.qml:65` (`WlrLayershell.layer: WlrLayer.Overlay`).
- `git grep fullscreen shell` finds only the Window menu's *Enter Full Screen* action
  (`MenuBar.qml:673-709`), no handling of the state.

**Problem:** Hyprland draws Overlay layers above fullscreen windows. So video, games,
presentations and *Enter Full Screen* (⌃⌘F) are very likely covered by the menu bar at the
top and the Dock at the bottom. macOS hides both in fullscreen and reveals them when the
pointer touches the edge.
**Root cause:** Partially verified. The layer choice and the missing handling are
confirmed. Hyprland's ordering of the Overlay layer above fullscreen is documented
behaviour, but wasn't observed here.
**User impact:** Fullscreen isn't really fullscreen, on the most visible workflow in the OS.
**Recommended solution:**
- Track `Hyprland.focusedMonitor.activeWorkspace.hasfullscreen` (or the `fullscreen` raw
  event) per screen.
- When a window is fullscreen, slide the Dock and menu bar off the screen and set
  `exclusiveZone` to 0.
- Reveal them on a 2 px hot edge, with a hover delay (Dock about 0.3 s, menu bar on pointer
  dwell).
- Keep Overlay so Launchpad and Control Center still appear above.

**Alternative approaches:** Move both surfaces to `Top`. Hyprland then covers them in
fullscreen for free, but the code comment at `Dock.qml:213-214` explains why the layer was
pinned, so make the change carefully.
**Complexity:** Small.
**Dependencies:** None.
**Validation:**
- The real-session harness (T-0.2) opens `mpv --fs` and a ⌃⌘F window, and its screenshot
  shows no shell pixels.
- Moving the pointer to the bottom edge reveals the Dock within 300 ms.

**Status:** Partially verified.

### Finding ID: CS2-013

**Area:** Accessibility
**Category:** UI, Feature gap
**Severity:** P1
**Current implementation:** Settings → Accessibility offers three things: Reduce motion,
Reduce transparency and Text size. No screen reader is installed. Custom pointer surfaces in
the shell set few or no `Accessible` properties. The shared controls are better annotated.
**Evidence:**
- `apps/settings/panes/AccessibilityPane.qml` (58 lines, three rows).
- `distro/archiso/packages.x86_64` has no `orca`, `espeak-ng` or `at-spi2` packages.
- Pointer handlers against `Accessible.` annotations per file: `shell/Dock.qml` 2 vs 0,
  `shell/Spotlight.qml` 2 vs 0, `shell/Notifications.qml` 8 vs 0, `shell/DesktopWidgets.qml`
  5 vs 0, `apps/maps.qml` 12 vs 0, `apps/calculator.qml` 8 vs 0. `shell/ControlCenter.qml`
  (11 vs 29) shows how it should be done.

**Problem:**
- People who rely on a screen reader can't use CitronOS at all.
- There is no zoom, increased contrast, larger pointer, sticky keys, slow keys, mouse keys,
  colour filters, captions style or full keyboard access setting.
- The Dock, Spotlight results and notifications aren't announced to assistive technology.

**Root cause:** Confirmed.
**User impact:** The OS is excluded for blind and low-vision users and for those with motor
impairments. It also blocks institutional and education use.
**Recommended solution:**
1. Ship `orca`, `espeak-ng` and `at-spi2-core`, with VoiceOver-style toggles (⌘F5, Settings).
   Qt Quick exposes AT-SPI once `QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1` is set and the bridge is
   running. Verify that layer-shell surfaces are reachable.
2. Add **Zoom** (Hyprland `cursor:zoom_factor`, bound to ⌥⌘= and scroll with ⌃),
   **Increase contrast** (a Theme switch that raises borders, removes glass and adds
   outlines), **Pointer size** (`XCURSOR_SIZE` and `hyprctl setcursor`), and **Sticky / Slow /
   Mouse keys** (keyd or libinput).
3. Require `Accessible.role`, `Accessible.name` and `Accessible.onPressAction` on every
   pointer-handling item, with a lint in `tests/` that fails when a MouseArea or TapHandler
   sits in an item without them.

**Alternative approaches:** None needed.
**Complexity:** Large.
**Dependencies:** CS2-018 (shared components carry the annotations).
**Validation:** With Orca on, navigate Dock → open Files → Spotlight search → read a
notification, by keyboard alone with speech. The accessibility lint passes, and Zoom and
contrast are covered by screenshot tests.
**Status:** Confirmed.

### Finding ID: CS2-018

**Area:** Design system
**Category:** UI, Architecture
**Severity:** P2
**Current implementation:** Tokens exist for radii (`radiusControl` 6, `radiusMenuItem` 8,
`radiusMenu` 14, `radiusField` 18, `radiusTile` 26, `radiusWindow` 22, `radiusSidebar` 16,
`radiusDock` 26) and for springs (six named springs, `Theme.qml:145-170`). Most code
ignores them.
**Evidence:** The token-usage table in §1: 426 literal radii against 16 token uses, 1,586
literal colours, and 198 literal durations against 130 tokenised ones.
**Problem:** Corner radii drift by one or two pixels between neighbouring surfaces (for
example 22, 20, 18 and 17 are all used for "panel"). Motion has more than 40 unrelated
durations, so interactions don't share a rhythm. A light/dark or accent change can't reach
the 1,586 hard-coded colours, which is a likely source of contrast bugs in dark mode and
with Increase Contrast (CS2-013).
**Root cause:** Confirmed. The tokens were added after most surfaces were written, and
nothing enforces them.
**User impact:** Surfaces feel almost-consistent rather than consistent, and dark mode and
accent themes keep needing fixes.
**Recommended solution:**
- **Radii:** collapse to 7 semantic tokens (`control`, `field`, `menu`, `card`, `panel`,
  `window`, `capsule`). Map each literal to the nearest one, review it in the screenshot
  diff, then add a lint that rejects `radius: <number>` outside `apps/lib/`.
- **Colour:** add semantic roles (`label`, `secondaryLabel`, `separator`, `fill`, `fillHover`,
  `fillPressed`, `destructive`, `success`, `warning`, `overlayScrim`, `shadow`). Migrate the
  top six files first, which cover 220 literals.
- **Motion:** see §3.

**Alternative approaches:** Leave existing literals and enforce tokens only on new code.
This is cheap, but the inconsistency stays.
**Complexity:** Medium (mechanical, needs screenshot review).
**Dependencies:** A real-session screenshot diff (T-0.2).
**Validation:** Literal radius count under 20, literal colour count under 200, and a
screenshot diff of every app in light and dark reviewed with no regressions.
**Status:** Confirmed.

### Finding ID: CS2-043

**Area:** Typography
**Category:** UI
**Severity:** P2
**Current implementation:**
`function fs(n) { return n > 24 ? n : Math.round(Math.max(12, n) * Math.max(1, Math.min(1.5, textScale))) }`.
**Evidence:** `apps/lib/theme/Theme.qml:53`. Call sites: `fs(12)`×258, `fs(13)`×190,
`fs(11)`×189, `fs(10)`×39, `fs(9)`×7, `fs(8)`×1.
**Problem:**
1. Every size below 12 is raised to 12, so `fs(8)` to `fs(12)` (494 call sites) all render
   the same. Captions, footnotes, badges, timestamps and secondary labels collapse into body
   text, flattening the hierarchy designers asked for.
2. Sizes above 24 never scale, so large titles ignore Text Size.
3. Text Size can't go below 100 %.
4. The semantic ramp (`textCaption2` … `textLargeTitle`, `Theme.qml:10-19`) is used 5 times.

**Root cause:** Confirmed (code). The visual effect follows directly.
**User impact:** Dense, flat-looking secondary text, and a Text Size setting that doesn't
reach titles.
**Recommended solution:**
- Replace `fs(n)` with semantic styles: `Theme.font.caption2 … largeTitle`, each a
  `{pixelSize, weight, letterSpacing}` scaled by `textScale`.
- Set the smallest legible size at 10 px (with tracking).
- Scale large titles at about half the rate.
- Allow a Text Size range of 85–150 %.
- Migrate by mapping each `fs(n)` to its nearest role, keeping a mechanical map in the
  migration script for review.

**Alternative approaches:** As a one-line interim fix, change the floor from 12 to 10 and
apply `textScale` above 24 too. Review in screenshots, since secondary labels will get
smaller.
**Complexity:** Small (interim) or Medium (semantic styles).
**Dependencies:** None.
**Validation:** Screenshot diffs at 85 %, 100 % and 150 % Text Size, and a check that
`fs(11)` and `fs(12)` are distinguishable.
**Status:** Confirmed.

### Finding ID: CS2-019

**Area:** Code structure (UI)
**Category:** Architecture
**Severity:** P2
**Current implementation:** Several user-facing surfaces are single QML files of more than
1,000 lines.
**Evidence:** `apps/browser/Browser.qml` 3,157 lines, `apps/files.qml` 2,038,
`apps/calendar.qml` 1,505, `apps/mail.qml` 1,386, `shell/ControlCenter.qml` 1,263,
`apps/lcode/design/DesignInspector.qml` 1,046, `apps/software.qml` 1,013.
**Problem:** These files are hard to review and to test in isolation. Every change to them
reloads and re-instantiates everything. They also invite the string-presence CI guards
(CS2-033), because there's no component boundary to test.
**Root cause:** Confirmed.
**User impact:** Indirect: slower fixes and more regressions.
**Recommended solution:** Split by role: toolbar, sidebar, content view, sheets, model or
controller (JS or Python). For example `browser/Toolbar.qml`, `TabStrip.qml`, `Sheets/*.qml`
and `BrowserController.js`. Use `Loader` for sheets so they're built only when opened. Do
it file by file behind the existing behaviour tests.
**Alternative approaches:** None needed.
**Complexity:** Medium per file.
**Dependencies:** CS2-033 (move the guards to behaviour tests first).
**Validation:** No file over 800 lines in `apps/` and `shell/`, the existing tests pass, and
the time for each app's first frame doesn't get worse.
**Status:** Confirmed.

### Finding ID: CS2-027

**Area:** System Settings → Users & Groups
**Category:** UI, Feature gap
**Severity:** P2
**Current implementation:** The pane lists accounts (by running a shell pipeline over
`getent`). **Change Password…** opens a Ghostty terminal that runs `passwd`. There is no way
to add or remove a user, change the account picture, change the full name, or set admin
rights.
**Evidence:** `apps/settings/panes/UsersPane.qml:11` (listing pipeline), `:20` (`ghostty -e
sh -c "passwd; …"`).
**Problem:** A raw terminal is the opposite of a native OS settings experience. Ordinary
account management needs the command line.
**Root cause:** Confirmed.
**User impact:** A visibly unfinished Settings pane. Family and shared computers can't be set
up.
**Recommended solution:** Use `accountsservice` (`org.freedesktop.Accounts`, which polkit
already gates): *Add User…*, *Delete User…* (keep the home folder or not), picture, full name,
*Allow user to administer this computer*, and *Change Password…* in a native sheet
(`SetPassword` asks polkit). Share the password rules with the installer
(`apps/setup/account_rules.py`).
**Alternative approaches:** None needed.
**Complexity:** Medium.
**Dependencies:** `accountsservice` in the package list.
**Validation:** Create, promote, demote and delete a user in a VM, and change your own
password, all without a terminal.
**Status:** Confirmed.

### Finding ID: CS2-030

**Area:** Third-party app appearance
**Category:** UI
**Severity:** P2
**Current implementation:** GTK 3 and GTK 4 apps are themed through `~/.config/gtk-{3,4}.0/gtk.css`.
The App Store installs Flathub apps into the user's Flatpak installation. Nothing grants
Flatpaks read access to those files or sets their colour scheme or accent.
**Evidence:** No `flatpak override` anywhere in `scripts/install.sh`, `apps/software/helper.py`
or `compositor/hyprland/apply-preferences.sh`.
**Problem:** Most apps users will install come from Flathub, and those apps very likely
ignore CitronOS's GTK CSS. They follow the portal's colour scheme but not CitronOS metrics,
accent colours or radii, so they look like stock GNOME next to native apps.
**Root cause:** Suspected. Flatpak sandboxing doesn't expose `~/.config/gtk-4.0` by default.
This wasn't seen on a running system.
**User impact:** Visual inconsistency for the apps people use most.
**Recommended solution:** Run `flatpak override --user --filesystem=xdg-config/gtk-4.0:ro
--filesystem=xdg-config/gtk-3.0:ro` once, set by `gg-apply-preferences`. Publish the accent
through the portal (`org.freedesktop.appearance` `accent-color`, which xdg-desktop-portal-gtk
reads from the GNOME `accent-color` key the shell already sets). For Qt Flatpaks, ship the
platform theme extension for the KDE runtime if one exists.
**Alternative approaches:** Accept stock libadwaita in Flatpaks and match only the accent.
This is lower risk, since libadwaita apps sometimes break under custom CSS.
**Complexity:** Small.
**Dependencies:** None.
**Validation:** Screenshot a Flathub GTK 4 app (for example Text Editor) before and after,
in light and dark, with two accents.
**Status:** Suspected.

### Finding ID: CS2-034

**Area:** Dock
**Category:** UI, Feature gap
**Severity:** P2
**Current implementation:** The Dock is always visible at the bottom, with a fixed exclusive
zone. It can't hide automatically, move to the left or right, or be limited to the main
display.
**Evidence:** `shell/Dock.qml:205-218` (anchored bottom; no `autohide` option in
`Prefs.qml` or the Settings Dock pane); `git grep -ci autohide shell/Dock.qml` is 0.
**Problem:** On small laptop screens, a permanent 76 px Dock takes vertical space that macOS
users usually get back with *Automatically hide and show the Dock*. Multi-monitor users get
a Dock on every screen with no choice.
**Root cause:** Confirmed.
**User impact:** Less room for content, and a desktop that can't be shaped to the user.
**Recommended solution:** Add `dock.autohide` (with an edge hot zone, reveal delay and a
spring slide, all off when Reduce Motion is on), `dock.position` (bottom, left, right), and
`dock.displays` (all, or main only). Share the hide and reveal logic with the fullscreen
behaviour from CS2-008.
**Alternative approaches:** None needed.
**Complexity:** Medium.
**Dependencies:** CS2-008.
**Validation:** Screenshot tests for each position and for auto-hide. Windows use the space
the Dock gave up.
**Status:** Confirmed.

### Finding ID: CS2-037

**Area:** Control Center → Wi-Fi
**Category:** UI
**Severity:** P3
**Current implementation:** Tapping a secured network you haven't joined before closes
Control Center and opens System Settings → Wi-Fi to ask for the password.
**Evidence:** `shell/ControlCenter.qml:104-108` (the `|| gg-settings wifi` fallback).
**Problem:** The user is moved into another app for a one-field prompt. macOS asks inline.
**Root cause:** Confirmed.
**User impact:** A context switch and a slower join.
**Recommended solution:** An inline password sheet in the Control Center Wi-Fi detail view,
backed by `citronos-networkd`'s secret agent (CS2-016). This also replaces the shell-string
join from CS2-002.
**Alternative approaches:** None needed.
**Complexity:** Small (after CS2-016).
**Dependencies:** CS2-002, CS2-016.
**Validation:** Join a WPA2 network from Control Center without Settings opening.
**Status:** Confirmed.

### Finding ID: CS2-035

**Area:** Documentation and screenshots
**Category:** UI (product truthfulness)
**Severity:** P3
**Current implementation:**
- README's main screenshot grid (Files, Control Center, Mission Control, Spotlight, Maps,
  Weather, Music, Settings, Mail, Calendar, Lock) is produced by the **browser prototype**
  (`prototype/tests/screenshots.mjs`). The real shell appears only in a smaller second grid.
- `docs/ARCHITECTURE.md` still describes the apps as "GNOME apps + libadwaita CSS" and says
  "when the QML shell and the prototype disagree, the prototype is the spec". The README
  says the reverse ("the live QML desktop is authoritative").
- `compositor/hyprland/hyprland.conf` says "CitronOS Music has no MPRIS yet", but
  `apps/music/mpris.py` exists and is tested.

**Evidence:** As listed above.
**Problem:** Visitors judge the OS by renders of a different implementation, and contributors
get conflicting guidance about which implementation is the source of truth.
**Root cause:** Confirmed.
**User impact:** Expectations that don't match the product, and wasted contributor effort.
**Recommended solution:** Generate README screenshots from the real-session harness
(T-0.2). Rewrite `ARCHITECTURE.md` around the QML desktop, and state that the prototype is a
sketchpad, not a spec. Fix stale comments as they're found.
**Alternative approaches:** None needed.
**Complexity:** Small.
**Dependencies:** T-0.2.
**Validation:** Every README image has a generator that runs against Quickshell.
**Status:** Confirmed.

### Finding ID: CS2-036

**Area:** Reference prototype
**Category:** Architecture
**Severity:** P3
**Current implementation:** `prototype/` is a full browser implementation of the desktop
and its apps (about 3,500 lines of JavaScript plus CSS), still maintained: 37 commits since
2026-09-24, against 967 for `shell/` and `apps/`.
**Evidence:** `git log --since=2026-09-24 -- prototype | wc -l`.
**Problem:** Every interaction exists twice. Divergence is guaranteed, and the CI `ui` job
spends time on the copy that doesn't ship.
**Root cause:** Confirmed.
**User impact:** Indirect.
**Recommended solution:** Freeze the prototype: keep it for design exploration, drop it from
README and from required CI, and stop porting features to it.
**Alternative approaches:** Delete it, and keep the tokens and the screenshot tooling it
pioneered.
**Complexity:** Small.
**Dependencies:** CS2-035.
**Validation:** The prototype gets no feature commits in M2 and M3.
**Status:** Confirmed.

---

## 3. Proposed motion system

The springs in `Theme.qml:145-170` are a good base. What's missing is a closed vocabulary
that every surface uses, and a ban on ad-hoc durations.

| Role | Use for | Spring (response / damping) or curve | Reduce Motion |
|---|---|---|---|
| `tap` | Press-down scale, toggle thumb | 0.18 s / 0.86, or 90 ms `OutCubic` | Opacity only, 60 ms |
| `snappy` | Menus, popovers, the switcher, tooltips | 0.28 s / 0.88 | Fade, 100 ms |
| `panel` | Control Center, Notification Center, Spotlight | 0.38 s / 0.82 | Fade, 140 ms |
| `sheet` | Modal sheets, app sheets | 0.42 s / 0.90 | Fade, 160 ms |
| `window` | Open, close, minimise, Mission Control | 0.48 s / 0.84 | Cross-fade, 180 ms |
| `bouncy` | Dock bounce, attention, badge pop | 0.55 s / 0.62 | None |
| `ambient` | Glass light, Citron orb | Linear loops ≥ 4 s | Paused |

Rules:

1. `duration:` must be a `Theme.motion.*` value (lint in `tests/`). Literals are allowed only
   in `apps/lib/`.
2. Interruptible: every presentation animates from the current value (Behaviors or
   `SpringAnimation`), never jumps back to the start.
3. Don't animate layout properties (`width`, `height`, anchors) in lists. Animate `scale`,
   `opacity` and `x`/`y` on a `layer.enabled` item only for the length of the transition.
4. Compositor animations stay off for shell layers (already done in `hyprland.conf`), so QML
   owns all of the shell's motion.
5. **Budgets** (enforced by the T-0.2 harness): input to first frame under 50 ms for Spotlight
   and Control Center, no dropped frames at 60 Hz on an Intel UHD 620 in a 60-frame
   presentation, and 120 Hz where the display supports it.

## 4. Proposed shared components (additions to `apps/lib/`)

These patterns are currently re-implemented in more than one place. Each new component
carries its accessibility annotations, so CS2-013's lint passes by construction.

| Component | Replaces | Why |
|---|---|---|
| `AppIcon` | Images using `Quickshell.iconPath()` in Dock, Launchpad, Tablet Home, Mission Control, Spotlight, Notifications, widgets | Fixes CS2-004 in one place. Consistent fallback and size buckets. |
| `SearchField` | Ad-hoc search `TextField`s in Settings, Files, Music, Mail, Maps, Passwords, App Store, Launchpad | ⌘F focus, clear button, Escape handling, a recents menu |
| `ListRow` / `FormRow` / `FormSection` | `apps/settings/{Group,SetRow}.qml` (Settings-only) and similar rows in Mail, Passwords, App Store and Disk Utility | One grouped-form look across the OS |
| `Popover` | `apps/lcode/design/Popover.qml`, Control Center detail views, Calendar event popovers | An arrow, glass, a dismiss policy and focus trapping |
| `Alert` / `ConfirmSheet` | Per-app destructive confirmations | Consistent button order, destructive red (`tests/button-destructive.py` already checks this) |
| `Toast` / `InlineBanner` | Per-app error labels (Settings `failed()`, Mail, App Store) | Every surface reports errors the same way, including the silent write failures from CS2-023 |
| `Spinner` | 1 spinner implementation plus ad-hoc progress | Indeterminate progress |
| `Tooltip` | Tooltip code in 4 files outside `apps/lib` (Dock `tipText` and others) | Shared delay, placement and style |
| `NavigationSplitView` | The sidebar and content layout re-done in each app | Collapsing sidebar, tablet behaviour (`tests/tablet-app-interfaces.py`) |
| `Badge` | Dock badges, sidebar counts, tab counts | One size, colour and motion |

## 5. Surface-by-surface notes (from code reading)

Each line names the file and what to check in the real-session harness.

- **Dock** (`shell/Dock.qml`): a strong lifecycle (tests `dock-lifecycle`, `dock-running`,
  `dock-motion`, `dock-drag`). Gaps: CS2-008, CS2-034, accessibility annotations (CS2-013),
  and badges for third-party apps (CS2-024).
- **Launchpad** (`shell/Applications.qml`): folders and drag to rearrange exist. Fix CS2-004
  and CS2-025. Check keyboard navigation (arrow keys, Return, typing to search).
- **Control Center** (`shell/ControlCenter.qml`): the best-annotated surface. Fix CS2-002,
  CS2-026 and CS2-037, and split the file (CS2-019).
- **Spotlight** (`shell/Spotlight.qml`): calculator, conversions, Settings panes, files and
  web. It needs an index (CS2-022), accessibility annotations, Quick Look on the selected
  result (⌘Y), and Contacts and recent documents once those exist.
- **Notifications** (`shell/Notifications.qml`): grouping, swipe to dismiss and Focus are in
  place. Fix persistence (CS2-024), add inline reply where `x-kde-reply`-style or GNOME
  `inline-reply` actions are offered, and accessibility annotations.
- **Window management** (`hyprland.conf` rules, `gg-tile`, Mission Control): every window
  floats and is centred, with Sequoia-style tiling and Mission Control. Check: dialogs are
  centred over their parent (Hyprland `windowrule` for `modal`), windows never open under the
  menu bar (`tests/window-placement.mjs` covers the geometry), and placement is restored
  after a display is unplugged.
- **Lock screen** (`shell/components/LockSurface.qml`): visually complete. Reliability issue
  CS2-005.
- **Settings**: 34 panes, mostly wired to real back ends (`tests/settings-wiring.py`). The
  thin panes are Users (CS2-027), Accessibility (CS2-013) and Network (CS2-016: no VPN set-up
  or 802.1X).
