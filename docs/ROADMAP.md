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
- [ ] Files: column and gallery views, tags, smart folders, undo
- [ ] Branding package (`golden-gate-branding`: os-release)

## 0.6: from the branch audit (2026-10-07)

Done: no silent overwrites (rename, Notes, Calendar, disks), one account
made once at install, honest Setup finishing and Software Update results
with rollback, acknowledged preferences, location consent, lasting alarms,
a background keyring, Text Size and scroll bars in the native UI, a Glass
transparency slider, menu-bar overflow, path-bar folding, a Utilities folder,
and ⌘W/⌘Q told apart.

Still to do:

- [ ] Edge-to-edge sidebars (a design decision for every app at once)
- [ ] One grouped Control Center panel (today: modules over the wallpaper,
      a deliberate HyprGlass choice)
- [ ] Printing and PDF; backup and recovery; full account management
- [ ] Per-app privacy permissions; accessibility beyond motion,
      transparency and text size (screen reader validation, zoom, keys)
- [ ] Network configuration (hidden/enterprise Wi-Fi, VPN, proxy, DNS);
      display resolution, arrangement and rotation
- [ ] Disk encryption at install; migration at Setup
- [ ] Mail (folders, attachments, drafts), Calendar (editing, recurrence,
      CalDAV), Photos editing, MPRIS for Music
- [ ] Translated UI (formats already follow the region; the apps are English)
