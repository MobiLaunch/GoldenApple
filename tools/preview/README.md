# UI preview

Renders the Golden Gate shell, or any app, to a PNG without Quickshell or
Hyprland, for design review and before/after comparisons.

```sh
python3 tools/preview/preview.py shell -o desktop.png
python3 tools/preview/preview.py shell --dark --do controlcenter.detail:wifi -o wifi.png
python3 tools/preview/preview.py shell --notify --do notifications.toggleCenter -o center.png
python3 tools/preview/preview.py app apps/settings.qml --env GG_SETTINGS_PANE=displays -o displays.png
tools/preview/gallery.sh /tmp/gallery          # every surface and app, light and dark
```

`--do target.function[:arg…]` calls an `IpcHandler`, as `qs ipc call` would.
`--crop x,y,w,h` keeps part of the screen.

Some states have a switch of their own:

```sh
# an app in front, with the menu bar's Window menu open
python3 tools/preview/preview.py shell --env GG_PREVIEW_ACTIVE=org.goldengate.Files --do menubar.open:window -o window.png
# Mission Control, with sample windows on three desktops
python3 tools/preview/preview.py shell --env GG_PREVIEW_WINDOWS=1 --do missioncontrol.toggle -o mc.png
# the green button's Move & Resize menu
python3 tools/preview/preview.py app apps/files.qml --env GG_ZOOM_MENU_PREVIEW=1 -o zoom.png
# Quick Look on a file
python3 tools/preview/preview.py app apps/files.qml --env GG_FILES_PATH=$PWD/tools/preview/cache/home/Pictures \
  "--env=GG_FILES_SELECT=$PWD/tools/preview/cache/home/Pictures/Muir Woods.png" --env GG_FILES_QUICKLOOK=1 -o look.png
```

How it works:

- `qml/` stands in for Quickshell's modules. Every window (`PanelWindow`,
  `FloatingWindow`, `PopupWindow`) is drawn into one scene, placed by its
  anchors and margins, stacked by layer as Hyprland does. The backdrop is
  blurred behind HyprGlass's glass surfaces and app windows.
- `Process` answers from `FIXTURES` in `preview.py`. Read-only commands run for
  real, in a sample home folder (`cache/home`: notes, documents, photos), with
  stand-ins for `nmcli`, `getent`, `gsettings` and the like first on `PATH`.
  Anything that could change the system is never run.
- Golden Gate's fontconfig rules apply, so SF Pro falls back to Inter as on the
  real system.

Limits: window rounding and shadows are Hyprland's, and in software GL a layer
effect blanks the window, so app windows show square corners and no shadow.
Network content (map tiles, weather, the App Store) shows its offline state.

`tests/qml-load.py` uses the harness to load the shell and every app, and fails
on QML errors that a syntax check can't see (a type that doesn't resolve, a
property newer Qt marks final).
