# Your own icons

Anything you put in this folder replaces the built-in artwork with the same name.
Everything else keeps the default Golden Gate icons, so you can swap icons one at a
time.

```
icons/custom/
  apps/       files.svg, terminal.png, files-dark.svg ...
  places/     folder.svg, document.png, trash.svg ...
  symbols/    wifi.svg, bluetooth.svg ...
```

After adding or changing files, rebuild:

```sh
node icons/build.mjs          # rebuilds icons/GoldenGate and the prototype bundle
node icons/build.mjs --list   # prints every name you can override
```

The build prints which of your files it picked up. Reload the prototype to see them
in the Dock, Files, Spotlight and elsewhere.

## Names

| Folder    | Names |
|-----------|-------|
| `apps`    | files, browser, mail, messages, music, photos, settings, terminal, notes, calendar, calculator, maps, store, launcher, weather |
| `places`  | trash, folder, document, audio, image, disk |
| `symbols` | run `--list`; e.g. wifi, bluetooth, moon, search, control-center, logo (the menu-bar mark) |

Each app icon is also installed under the freedesktop names real Linux apps look
for (for example `files` becomes `system-file-manager`, `org.gnome.Nautilus`,
`thunar`...), so one file themes every file manager.

## Guidelines

**App icons**

- **SVG is best.** Any `viewBox` works; square is expected. SVGs stay sharp at every
  size, from the 16px menu to the 86px magnified Dock.
- **PNG works too.** Export at **1024 × 1024** with a transparent background. PNGs
  are installed as 512px threshold icons on Linux.
- **Draw the full icon shape yourself.** The system does not mask or clip app icons,
  so include your squircle (or whatever shape you want) in the artwork. To match the
  built-in set, fill the canvas edge to edge with a superellipse (n ≈ 5); the Dock
  adds the drop shadow.
- **Dark appearance.** Add `<name>-dark.svg` / `.png` to supply your own dark
  version. If you don't, your icon is used unchanged in dark mode. (The built-in icons
  generate their dark versions automatically.)

**Symbols**

- Draw on a 24 × 24 `viewBox`.
- Use `currentColor` for strokes and fills so the glyph follows the menu bar, sidebar
  and selection colours. Hard-coded colours stay fixed.
- About 1.75px stroke with round caps and joins matches the rest of the set.

**Licensing**

Use artwork you made or have the rights to. Apple's app icons and SF Symbols are
licensed for Apple platforms only, so copies of them can't ship in a Linux
distribution.
