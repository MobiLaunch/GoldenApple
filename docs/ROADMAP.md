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
- [ ] Port hyprland.conf to Lua (the .conf format is deprecated since 0.54)
- [ ] Verify the keyd per-app classes against real window classes
- [ ] Compare the QML shell with the prototype screenshot by screenshot

## 0.4: signature details

- [ ] `hyprglass` plugin: per-surface refraction using `liquid-glass.frag`
- [ ] Genie minimise as a Hyprland plugin (mesh-warp the window texture)
- [ ] Mission Control / Spaces overview in the Linux shell
- [ ] Global app menus in the menu bar (appmenu D-Bus bridge; GTK3/Qt first)
- [ ] Widgets on the desktop

## 0.5: native apps

- [ ] Files: GTK4 app matching the prototype (floating sidebar, glass toolbar,
      icon/list/column/gallery views)
- [ ] Settings: native app with the prototype's pane structure
- [ ] Installer: Calamares with a Golden Gate theme
- [ ] Branding package (`golden-gate-branding`: os-release)
- [ ] Choose a public product name
