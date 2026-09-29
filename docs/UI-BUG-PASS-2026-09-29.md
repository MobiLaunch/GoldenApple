# Dock, Web, Hello, and motion follow-up

This follow-up builds on PR #2's first control/app pass.

## Dock and motion

- Increased the native dock surface to include labels, bounce, and spring headroom.
  Labels stay within horizontal screen bounds, including long app names.
- Magnification uses the resting layout's center, rather than the moving shelf.
  Icons interpolate toward their target, share a bottom baseline, and fit narrow screens.
- The input region covers magnified icons without reserving extra desktop space.
- The reference prototype batches pointer updates into one animation frame, tracks
  labels through size transitions, clamps tooltip bounds, and fits smaller viewports.
- Both paths respect reduced motion. Reduced motion also disables launch bounce.
- The launch animation stops obsolete handoff timers, matches the launched app
  before capturing a window, and clamps estimated window size to the display.
- Trash now returns to its empty icon after its last file is removed.

## Native Web browser

`apps/browser/` owns the UI and uses Qt WebEngine's Chromium engine through PySide6.
The dock and new-install HTTP/HTTPS defaults point to `org.goldengate.Web`.
The image includes `pyside6`, `qt6-webengine`, and Python.

Implemented: native toolbar and traffic lights, tabs and sidebar, address/search,
start-page favorites, bookmark/history lists, navigation shortcuts, download save
chooser/progress/cancellation, persistent normal profile, isolated private windows,
user-initiated pop-up tabs, permission prompts, full-screen escape, tab crash notice,
light/dark colors, and software graphics opt-in for VMs. Website titles are rendered
as plain text; start-page values are HTML-escaped. Pasted executable URL schemes
are rejected. Certificate validation and the Chromium sandbox remain enabled.

A profile lock and local IPC prevent simultaneous normal windows from corrupting
one profile. State writes are debounced and atomic. Restore is capped at 30 tabs,
with background tabs deferred until selection; history is bounded at 300 entries.
Normal renderer crashes do not destroy the window or its other tabs.

This is an initial Safari-inspired Chromium browser, not a claim of Safari feature
parity. No iCloud, extension manager, credential vault, or commercial streaming DRM
configuration is included. Engine updates come from Arch's Qt WebEngine package.

## Firefox

Stopped automatic installation of the privileged Firefox autoconfig and stylesheet.
Recovery only disables files marked as Golden Gate-owned, retaining dated backups.
`gg-firefox-recover` enters Firefox Troubleshoot Mode without resetting the profile.
No crash log was supplied: the exact Firefox crash cause is still unconfirmed.

## Hello / local accounts

Account creation follows Hello, before connectivity and analytics. Installed users
may keep their current account. New accounts require administrator authorization
(or the existing live-image privilege path) and use a root-owned, isolated Python
helper. Passwords travel through stdin, never command arguments or environment.
Existing accounts cannot be overwritten; failed password creation rolls back only
the account created by that request. New accounts join wheel with password-required
sudo authorization. Preferences for another user are written after dropping to that
user, so user-controlled home paths never receive root-privileged writes.

Finish now waits for preference writes and displays failures rather than marking
setup complete before a detached command succeeds. Account setup uses real keyboard
buttons, a scrollable form, and guarded transitions. The page transition animates a
free-positioned loader, fixing the previous conflict between anchors and animated x.
New accounts inherit light/dark appearance on first login. Existing live ISO limits
still apply: no disk installer or persistent storage is created; the current session
keeps its original user until an explicit sign-in.

## Validation

- Native Qt controls: 8 regression cases.
- Existing app logic: 7 regression cases.
- Account/helper/preference/browser data: 14 cases, with privileged commands mocked.
- Real Qt WebEngine: 8 cases using a local HTTP fixture, plus normal and compact
  rendered previews. The root-only local test harness explicitly disables sandboxing
  for fixtures; production launchers never do. CI runs as an ordinary user.
- 123 QML files parsed; Python and JavaScript syntax and shell scripts checked.
- Staged system installation completed; browser desktop entry and root helper permissions verified
  (wallpaper rasterization skipped locally because librsvg is unavailable).
- Added a prototype dock-label viewport regression and native browser/setup CI job.
- Local Playwright Chromium download was truncated; the prototype suite runs in CI.

Full Arch/Hyprland/Quickshell validation, real PAM/account creation and greeter
handoff, GPU/VM comparisons, external-site compatibility, and frame-time measurements
remain hardware checks. No numerical FPS improvement is claimed from code inspection.
