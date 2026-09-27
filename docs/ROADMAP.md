# Roadmap

## 0.1: foundation (this branch)

- [x] Design tokens → CSS / QML / GTK / Hyprland
- [x] Original icon theme, with custom overrides
- [x] Interactive reference shell (browser)
- [x] Quickshell menu bar, Control Center, Dock, Spotlight (syntax-checked)
- [x] Hyprland config, fontconfig, GTK overrides, installer
- [x] archiso profile and CI workflow

## 0.2: boot it

- [ ] First ISO build via the *Build ISO* action; fix whatever it surfaces
      (package availability, the Quickshell version in the repos)
- [ ] Run the QML shell on hardware; match it against the prototype screenshot by screenshot
- [ ] Login screen: SDDM theme using the same glass materials
- [ ] Lock screen: hyprlock config with the clock and glass input
- [ ] Notification banners (mako styling or a Quickshell notification server)
- [ ] ⌘ shortcuts in apps: a keyd layer mapping Super+C/V/X/Z/A/… to Ctrl
      (terminal-aware)

## 0.3: signature details

- [ ] `hyprglass` plugin: per-surface refraction using `liquid-glass.frag`
- [ ] Genie minimise as a Hyprland plugin (mesh-warp the window texture)
- [ ] Mission Control / Spaces overview
- [ ] Global app menus in the menu bar (appmenu D-Bus bridge; GTK3/Qt first)
- [ ] App switcher (⌘Tab) as a Quickshell surface
- [ ] Widgets on the desktop

## 0.4: native apps

- [ ] Files: GTK4 app matching the prototype (floating sidebar, glass toolbar,
      icon/list/column/gallery views)
- [ ] Settings: native app with the prototype's pane structure
- [ ] Installer: Calamares with a Golden Gate theme
- [ ] Branding package (`golden-gate-branding`: os-release, Plymouth splash)
- [ ] Choose a public product name
