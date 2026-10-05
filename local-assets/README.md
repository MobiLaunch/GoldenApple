# Local typography and symbol overrides

CitronOS prefers **SF Pro Text**, **SF Pro Display**, and **SF Mono** when those fonts are installed, but the repository does not redistribute Apple font binaries or SF Symbols artwork.

For a local ISO build, place font files you are licensed to use in:

```
local-assets/fonts/
```

Supported extensions are `.otf`, `.ttf`, and `.ttc`.

To override CitronOS's built-in monochrome UI symbols, place SVG files in:

```
local-assets/symbols/
```

Use the same filenames as the files under `apps/lib/assets/symbols/` (including tone suffixes such as `@dark`, `@gray`, or `@accent` when you want to replace those variants). The ISO builder overlays these files into the shared app/shell symbol store and the SDDM login theme.

The contents of both local asset directories are ignored by git.
