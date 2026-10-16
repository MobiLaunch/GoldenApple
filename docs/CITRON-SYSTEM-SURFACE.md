# Citron Intelligence as a Golden Gate system surface

Citron is **not a standalone application**. It is a shell-managed, transient
overlay that shares the system's keyboard focus, theme, clipboard, and
backdrop capture. No app icon, separate Quickshell application process, Dock
entry, launchable desktop file, or chat sidebar is installed.

## Invoking the system overlay

- **⌘⇧Space** toggles the overlay. This does **not** enable the mic.
- **Menu Bar → Citron / Ask Citron** brings up the Ask mode.
- **Settings → Citron Intelligence** is the only configuration UI, containing
  the existing Gemini keyring, models, language and voice preferences.
- A contextual **Writing Tools** action may run
  `gg-intelligence --writing`. The existing clipboard text fills the local
  editor, but is not uploaded until the user explicitly submits a request.
- `gg-intelligence --image` shows the image-generation composer,
  `gg-intelligence --photo /path/to/image` selects an image for editing,
  and `gg-intelligence --voice` initiates an actual voice session.
- IPC direct: `qs -c golden-gate ipc call citron ask`, `writing`,
  `image`, `edit`, `voice`, `toggle`, `close`.

## Orb and interaction design

Reference: the user-supplied dark refractive sphere screenshot, including
its almost-black lens, narrow spectral caustic, faint elliptical highlight,
reflected scene at the bottom and gentle out-of-focus rim. The original
picture is a design reference, not embedded artwork.

The implementation uses `apps/lib/PrismOrb.qml` (the shared UI library).
It has a real `Glass` backdrop lens, so desktop contents beneath the
sphere can bend slightly. An elliptical gradient produces the blue,
peach, gold and lilac prismatic band. There is no per-frame CPU image
capture or remote image asset: all movement is done in Qt Quick. Under
Reduce Transparency and software rendering, the sphere remains a
legible dark object without requiring refraction. Under Reduce Motion,
its idle drift and bounces stop.

The overlay progresses through:

1. **Summoned/idle**: dark orb, short prompt, Ask/Write/Create/Edit Photo
   chips and translucent capsule; all other controls stay hidden.
2. **Listening**: mic button explicitly starts Gemini Live, showing
   status and a real transcript; tap again to mute.
3. **Thinking**: colored band drifts slowly while the existing Gemini
   request executes; Cancel stops the request.
4. **Response**: scrollable glass result unfolds below the orb. Copy
   text, preview an image or save the generated image directly.
5. **Dismissal**: Escape or Close removes the overlay and clears the
   conversation, writing draft, chosen image and temporary generated previews.

The prompt and result components shrink for laptops below 810px high;
content is scrollable, not clipped off-screen.

The Gemini helper and live-audio helper remain in the shared library and
start on demand. Credentials stay in the system keyring and requests are
written to helper stdin, never included in a shell command-line argument.
A voice session has no background microphone unless explicitly opened
and unmuted.

## Retired UI

The old `apps/intelligence.qml` window and
`org.goldengate.Intelligence.desktop` launcher were deleted. The
installer explicitly removes their former installed desktop shortcut
on both existing-user upgrades and new system images. Other shortcuts
that previously opened the app now route to the shell via IPC.

The backend remains intact, so installing or updating Golden Gate
does not erase the existing model/API configuration.

## Global softness and readability

All owned surfaces now share the updated `design/tokens.json` source:

- Light/Dark **primary, secondary and tertiary labels** now exceed
  **4.5:1** on standard content backgrounds, including tertiary labels
  previously too faint to read.
- The shared UI font helper raises small labels to **12px minimum** and
  retains accessibility text-scaling from Settings. Headline and body
  token sizes were slightly enlarged as well.
- Glass shadows use a broader Gaussian spread with **reduced opacity**.
  The same source updates GTK4/libadwaita, GTK3, HTML/prototype CSS,
  Qt/Quickshell and Hyprland compositor shadows. Controls remain subtler
  than dialog/menu and Dock shadows.
- Hyprland uses a wider, gentler shadow at 46px range, reduced strength
  and 9px offset, instead of a hard high-power drop shadow.
- Menu bar text gets a broader neutral contrast shadow to read over
  both dark and bright wallpapers.
- Tooltips, selected controls and input placeholders use system text
  contrast instead of nearly invisible tertiary alpha.

These changes affect **Golden Gate-managed** styling; a third-party
application using its own custom-rendered shadows and typography may
ignore these global theme overrides.

## Verification

Run `python tests/intelligence-shell-visuals.py`. The audit tests
desktop launcher removal, IPC routing, temporary state clearing,
prismatic orb visual contracts and WCAG contrast against the default
light and dark content surfaces. Existing AI service, voice and Qt
preview tests remain in CI, updated to test the integrated design.

Real GPU refraction, 720p/HiDPI fit, full voice sessions and the
installer's upgrade cleanup still require running the ISO or installed
desktop and examining screenshots/logs. Static source tests alone
cannot prove all per-monitor visual effects render correctly.
