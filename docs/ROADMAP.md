# Roadmap

## 0.1: foundation

- [x] Design tokens → CSS / QML / GTK / Hyprland
- [x] Original icon theme, with custom overrides
- [x] Interactive reference shell (browser)
- [x] Quickshell menu bar, Control Center, Dock, Spotlight
- [x] Hyprland config, fontconfig, GTK overrides, installer
- [x] archiso profile and CI workflow

## 0.2: complete the desktop

- [x] Reference apps: Web, Mail, Messages, Music, Calendar, Maps, Weather,
      Software, Notes, Terminal, Calculator alongside Files, Photos and Settings
- [x] Boot, lock screen, Mission Control, app switcher, edge tiling,
      notification history, Quick Look, Downloads stack, dynamic wallpaper
- [x] Quickshell notification server (banners, actions, swipe, Do Not Disturb)
- [x] Quickshell app switcher and lock screen (`ext-session-lock` + PAM)
- [x] Login screen: SDDM theme using the same glass materials
- [x] Boot splash: Plymouth theme
- [x] ⌘ shortcuts in apps: a keyd layer mapping Super+letter to Ctrl+letter,
      Ctrl+Shift in terminals
- [x] Run the QML shell for real (headless Sway + llvmpipe) and fix what it
      surfaced: Qt's 8-segment spline limit, `clip-path`-free icons,
      shader-free symbol tinting for the software renderer
- [x] Playwright click-through of the reference shell in CI

## 0.3: boot it

- [x] First ISO build via the *Build ISO* action (AUR fallback for packages
      outside the official repos; Quickshell comes from the official repos)
- [x] Boot test: every ISO is booted in QEMU on plain VGA, virtio-gpu and
      virtio-gpu with 3D, and must reach the desktop with no Hyprland config
      errors. It surfaced and fixed the Hyprland 0.53+ rule syntax, the move
      away from hyprpaper, and the live session's home ownership and lockout
- [ ] Screenshot for the 3D boot test (QEMU's screendump can't read a GL display)
- [ ] Run on hardware under Hyprland with a GPU: blur, the focus grab,
      global shortcuts and the PAM lock can only be checked there
- [ ] Port hyprland.conf to Lua (Hyprland 0.56 loads .conf as its legacy format)
- [ ] Verify the keyd per-app classes against real window classes
- [ ] Compare the QML shell with the prototype screenshot by screenshot

## 0.3.1: deliberate micro-interactions (2026-10-09)

- [x] Keyboard and screen-reader actions give the same short tactile feedback as a pointer click
- [x] Shared segmented/sidebar controls: soft selection and press response without layout shift
- [x] Liquid Glass: pointer illumination and press effects honor Reduce Motion
- [x] Traffic lights: individually responsive pointer hover, keyboard and accessibility activation
- [x] Search-field clear affordance and Escape to clear without dismissing dialogs
- [x] Pop-up active state, keyboard toggle feedback, slider/scrollbar ease and focus halos
- [x] Dock label hover intent, subtle inactive-window depth, short menu selection fade
- [x] Shared AppWindow: synchronized, interruptible leading/trailing sidebar choreography
- [x] Canonical attached modal sheets for Files and LCode, with exit fade and focus return
- [x] Design popovers preserve focus and adapt their entrance to screen edges
- [x] Notification Center, Mission Control, switcher and Control Center transition polish
- [x] LCode debug console, Find bar and editor tab micro-choreography
- [x] Files Quick Look aspect morph and image fade-in, with inert exit surfaces
- [x] Modal and popover contents disable input immediately on dismissal
- [x] Offscreen native-control regressions and source contracts in CI
- [ ] Installed-GPU motion/blur tests with physical trackpad and pointer
- [ ] Screen-reader acceptance, localized large-text overflow, slow-GPU frame profiling

See [Micro-interaction design and QA](UI-MICRO-INTERACTIONS.md).

## 0.4: signature details

- [x] `hyprglass` plugin: per-surface refraction and blur for the glass
      layers (thresholds per namespace, `hyprglass-sync.sh`)
- [ ] Genie minimise as a Hyprland plugin (mesh-warp the window texture)
- [x] Mission Control / Spaces overview in the Linux shell
- [ ] Global app menus in the menu bar: today an app gets Window and Help
      (the desktop gets Files' menus); a first-party action registry, then
      the appmenu D-Bus bridge for GTK3/Qt, are still to do
- [x] Widgets on the desktop

## 0.5: native apps

- [x] Files, Settings, the installer, Disk Utility and the other default apps
      are native QML apps on one shared component store (`apps/lib`)
- [x] Files: range/toggle/multiple selection, copy/cut/paste, Duplicate,
      Get Info, transfer progress/cancellation and Keep Both/Skip conflicts
- [x] Files: sortable list headings and per-folder view/sort preferences
- [x] Files: Undo Rename and Undo New Folder (an empty, unchanged folder only)
- [x] Calendar: event editing/duplication; validated daily, weekly, monthly and yearly repeat rules
- [x] Calendar: occurrence-specific edit/move/skip, opt-in background event reminders
- [x] Calendar: read-only CalDAV collection sync with credentials in Secret Service
- [x] Calendar: Changed Dates manager for restoring edited/skipped occurrences
- [x] Calendar: Month, Week and Day views with matching navigation and agendas
- [x] Calendar: opt-in background CalDAV refresh with account-disconnect race protection
- [ ] Calendar: two-way CalDAV, invitations, complex recurrence, multi-calendar discovery
- [x] Focus: timed Do Not Disturb, weekly/overnight schedule, allowed apps,
      critical-alert opt-in and shared expiry status in Settings/Control Center
- [ ] Focus: named profiles, people exceptions and app/context automation
- [ ] Files: marquee selection, Open With, column/gallery views, tags,
      smart folders, transfer queue and broader undo/redo
- [ ] Branding package (`golden-gate-branding`: os-release)

## 0.6: from the audits (2026-10-07)

What the fixes cover, and how far that has been shown. "Tested" means a
unit or preview-harness test in `tests/` (run in CI) with the service
stood in for; none of it has yet been through a clean install on real
hardware, which is the acceptance step still to come.

Tested:

- [x] Renames never replace: `renameat2(RENAME_NOREPLACE)`, or a hard link /
      reserved directory where that's missing, else refused (Files, Notes)
- [x] Notes: a note changed elsewhere is saved beside it, never over it;
      titles rename through one locked helper; Recently Deleted keeps
      every note and its origin under one lock
- [x] Calendar: a damaged store is never written over; Restore puts back
      only a copy that passes the same check, and keeps each damaged copy
- [x] Clock: alarms and the timer are reported only once systemd took them
      and they're saved; a unit is turned off again if saving fails; a
      cancelled, paused or restarted timer's firing says nothing; a timer
      lost with the user's service manager is set again
- [x] Software Update: staged first, then applied as a transaction that puts
      the previous version back if a step fails (packages it added and
      services it turned on stay); Liquid Glass is turned off, with a
      notice, when the plugin wasn't built for the installed Hyprland
- [x] Settings: preferences change key by key under a lock (two windows keep
      both changes), are applied to the session only once saved, and a
      damaged file is refused rather than replaced
- [x] Displays: a new scale reverts after 15 s unless kept, through a
      watchdog of its own, so closing Settings doesn't keep it
- [x] Setup: the installer takes over from Hello (and Hello comes back if it
      can't start); the region's formats show in Language & Region; what
      was put off is listed under Finish Setting Up until it's done
- [x] Golden Gate UI: edge-to-edge sidebars; window contents solid by
      default (the Transparency slider moves the glass); Control Center
      grouped in one panel, as in Big Sur; » lists every hidden menu;
      long path names shortened in the middle; Close and Quit told apart
      (document apps keep running without a window)

To verify on real hardware: the HyprGlass plugin against each Hyprland
release, the display watchdog under a real compositor, an update and its
rollback on an installed system, and a clean install end to end.

Music now publishes local playback to MPRIS, restores queues paused with a
saved position, and reports playback and save failures with recovery actions.
See [Music workflows](MUSIC-WORKFLOWS.md) for controls and validation boundaries.
Music now supports creating, editing, safely deleting and restoring M3U playlists, song
ordering, and reorder/remove controls for the Playing Next queue.
Verify physical media keys, audible output, and Control Center on the installed
desktop; the live MPRIS contract runs on a private session bus in CI.

Still to do:

- [ ] Global app menus: today an app gets Window and Help (the desktop gets
      Files' menus); an action registry, then the appmenu D-Bus bridge
- [ ] Layout at large Text Size and in longer languages: toolbars, menus and
      Control Center keep fixed widths (Control Center's text stops at 115%)
- [ ] Printing and PDF; backup and recovery; full account management
- [ ] Per-app privacy permissions; accessibility beyond motion,
      transparency and text size (screen reader validation, zoom, keys)
- [ ] Network configuration (hidden/enterprise Wi-Fi, VPN, proxy, DNS);
      display resolution, arrangement and rotation
- [ ] Disk encryption at install; migration at Setup
- [ ] Mail (folders, attachments, drafts), Calendar (two-way CalDAV, invitations,
      advanced recurrence), Photos editing; Music smart playlists and library folder selection
      and removal, and library folder preferences
- [ ] Translated UI (formats already follow the region; the apps are English)
