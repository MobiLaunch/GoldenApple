# UI and bug pass — 28 September 2026

Base: `claude/linux-macos-golden-gate-ui-pckc7s` at `3bbafd3ee4d63765d55991a16fcc9d2dd7176b4c` (newest branch tip at review time).

## Changes

| Area | Problem and change |
| --- | --- |
| Shared app controls | Buttons, toolbar buttons, checkboxes, segmented controls and pop-up buttons now support keyboard use, accessible roles and consistent focus rings. Disabled controls are dimmed; repeated Space presses do not repeatedly activate buttons. |
| Switch | `enabled_` previously blocked clicks but not drag changes. Pointer and keyboard paths now respect both disabled properties; dragging requires an active press. |
| Sliders | App track endpoints no longer change as the knob grows. Values used for rendering are bounded; zero-width travel cannot introduce NaN. Home/End and arrow keys work. Control Center sliders gain keyboard handling and a visible focus border; zero really draws an empty fill. |
| Pop-up menus | Up/Down, Enter/Space, Escape and Tab work; disabled entries and separators are skipped. Selection scrolls into view, focus returns to the invoker and menu width is constrained to the window. |
| Text fields / Spotlight | Text fields enter the tab order and truncate long placeholder text. Native Spotlight clips long input, respects IME preedit, elides long app names and scrolls results on short screens. Empty results cannot produce a negative selection. |
| Accessibility preferences | Shared timed springs and continuous springs honor Reduce Motion, including a running continuous spring when the setting changes. Maps fly-to respects it. Native app sidebars become opaque with Reduce Transparency. Shell preference values are bound into its theme. |
| Maps / Weather | Search generations discard stale responses, including during debounce and after clearing text. Route generations discard older travel-mode responses and responses arriving after directions close. |
| Maps geometry / idle work | Fly-to clamps latitude and zoom; longitude wrapping handles large negative values. Pinching stops an existing flight. Double-click cannot exceed the tile zoom cap. Unchanged saved state avoids recurring writes and mkdir processes while idle. |
| Music / Photos | File paths are encoded per component, preserving `#`, `?`, `%`, Unicode and spaces. Music owns a copy of its queue, clamps starting indices, clears the source for an empty queue and bounds seeking. Artist grouping uses a prototype-free dictionary. Photos supports dragging the video scrubber and avoids starting hidden videos after an item change. |
| Notes | Obsolete debounce timers stop on selection changes. Renames write through a separate atomic writer and only delete the original after successful completion. Failed saves keep the draft dirty and visible, report an error and prevent normal note switching/new-note/delete actions. Deletion uses the post-flush filename. Pending edits flush on orderly app exit. |
| Notifications | Summary/body are rendered as plain text, matching the server's advertised capabilities. A sender's zero (never expire) timeout is respected. |
| Window resizing | Frameless native app windows now expose diagonal resize targets at all four corners; the top corners were previously missing. |
| CI resilience | UI screenshots are still uploaded when possible, but exhausted GitHub artifact storage no longer marks otherwise-passing browser/shader validation as failed. Screenshot retention is limited to three days. |
| Browser reference launcher | Its application grid now has an initial keyboard selection, responds to Up/Down and launches the selected app with Enter. Selection is visible. Empty-result navigation is guarded. |

## Validation

- **122 native QML files parsed successfully** with Qt 6.11.2's QML parser. Parsing is not a substitute for resolving Quickshell imports on Arch.
- **8 native Qt tests passed**: actual offscreen controls exercised using pointer/key events, menu focus restoration, disabled states, slider endpoints, segmented selection and reduced-motion springs. Light and dark control previews were rendered and inspected.
- **7 JavaScript regression tests passed** against functions extracted from the actual QML: reserved-character media paths, out-of-order Maps/Weather searches, route races, map bounds, queue ownership and failed/successful note renames. Service doubles model callbacks; these do not run the real filesystem or network services.
- **10 shell scripts passed Bash syntax checking**. Modified prototype JavaScript also passed Node syntax checking.
- Added a native-controls CI job and a browser launcher regression scenario.
- **Browser smoke suite could not run locally**: Chromium was not installed, and the browser CDN returned an invalid/truncated archive. The existing Playwright CI job remains the browser gate.

## Remaining runtime verification

This environment did not run the full Arch ISO, Hyprland, Quickshell system services, hardware audio, Wi-Fi or Bluetooth. Test the draft PR in the live desktop before merging:

1. Tab through Settings and app toolbars, open long menus, toggle Reduce Motion/Transparency in both appearances.
2. Search rapidly and clear queries on a slow connection; change routing modes while requests are pending.
3. Play files whose names contain `#`, `?`, `%` and spaces; drag Photos' video scrubber.
4. Rename, switch, delete and close Notes while editing; simulate a read-only destination and verify the original survives and the draft remains available while the app is open. Forced process termination and failed writes during shutdown cannot guarantee draft recovery.
5. Check Spotlight on short/multiple displays, notification expiry, and the browser launcher's new keyboard scenario.

This is a scoped code and control-runtime pass, not a claim that the complete distribution is bug-free or hardware-certified. The existing visual language and artwork are retained.
