## October 2026 — window edges, icons, typography, and charging

- Floating-window dragging/resizing uses Hyprland's built-in `general.snap`:
  a 12 px monitor/window attraction distance, no extra polling, no extra glass
  layer, and the same gaps as the rest of the desktop. Window › Move & Resize
  still offers explicit half/quarter tiling via `gg-tile`.
- Minimize and restore use the compositor's real window surface with a shorter
  300 ms/18% special-workspace transition. We deliberately do **not** pretend
  to have a macOS Genie morph until a real captured-window texture can be
  carried to the Dock without flashing or creating GPU stalls.
- The menu bar battery now has a real measured green fill and lightning symbol
  when charging, a restrained opacity pulse, no pulse once fully charged, and
  instant rendering under Reduce Motion. Percentage remains firmware-derived.
- The shared icon generator uses 24 normalized OrchardKit/Open Symbols
  Lucide regular-size glyphs, not Xcode template artboards. They are exposed
  consistently through Qt/Quickshell assets, GTK symbolic icons, and the web
  prototype. Custom local symbol overrides remain supported.
- Fontconfig's Golden Gate UI, Display and Mono aliases resolve a locally
  installed SFWindows copy when permitted by its license, and use open-source
  Inter/JetBrains Mono otherwise. No proprietary fonts ship with the project.

# Golden Gate micro-interaction polish

This pass focuses on **restraint**: small gestures, clear feedback and spring
motion that follows the control being manipulated. It is intentionally not
a systemwide magnification effect or a continuous ambient animation.

Apple's Human Interface Guidelines emphasize short, purposeful motion,
subtler feedback with pointer or trackpad input, and an equivalent
nonanimated presentation:
- https://developer.apple.com/design/human-interface-guidelines/motion
- https://developer.apple.com/design/human-interface-guidelines/feedback
- https://developer.apple.com/videos/play/wwdc2025/219/

## Shared components — one implementation everywhere

| Surface | Interaction | Reduce Motion |
| --- | --- | --- |
| Liquid Glass | Press contraction, pointer illumination, rim and lift | No travel animations; feedback appears immediately |
| Push/toolbar buttons | A 90 ms pressed state on keyboard/accessible activation matches pointer press | State change stays available; no travel |
| Segmented picker | Short hover highlight, compress label slightly on press, spring selection pill | Selection snaps directly |
| Search input | Right-side clear affordance and Escape clears without closing a dialog | Clear button fades without animation |
| Pop-up selector | The capsule remains pressed while its menu is visible | Selection is instant; no squash |
| Slider | Track subtly thickens on hover; keyboard changes ease to a new value while drag stays direct | Values and fill move immediately |
| Overlay scrollbar | Thumb brightens and track expands on deliberate hover | No width or fade transitions |
| Switch / checkbox | Space, Return and accessibility get the same pressed state as mouse activation | State changes immediately |
| Focus outline | Two low-cost accent strokes improve contrast on busy backgrounds | Instant focus indication |
| Traffic lights | Only the hovered control responds; keyboard and accessibility can activate each window action | Hover scale snaps immediately |
| Sidebar row | Pressed background compresses minimally, selected symbol gains emphasis | No animated scale |
| Menus | Hover selection washes in over 65 ms, without changing popup dimensions; Escape and click-away cancel pending selections | Highlight appears instantly |
| Inactive app window | A faint 180 ms toolbar tint changes visual hierarchy | Tint changes instantly |
| Dock labels | Deliberate 300 ms pointer dwell before reveal; leave/press cancels pending tooltip | Tooltip appears without scale motion |
| Dock recent apps | Last window closes: running dot fades, icon remains 900 ms, then icon/slot/divider collapse together over 220 ms; reopening reverses the same slot | Brief hold remains; departure snaps with no travel, including a mid-flight preference change |
| App closing | Native compositor fade, no replacement launch card over the disappearing window | Launch card is cancelled immediately; native compositor policy is unchanged |
| App switcher | Panel settles gently; selection follows current app | Panel appears in place, selection snaps |
| Notifications | Exit slides, card displacement, and springs are linked to the motion preference | Dismissal and reflow do not travel |
| Control Center | Module press and disclosure remain responsive; slide transitions are optional | Instant detail switches |
| Mission Control | Workspace tile hover increases only ~2.5%, not oversized magnification | No hover scale |

The new shared-control behavior is additive: MouseArea, TapHandler and keyboard
activation still invoke the original actions. The glass shader is not
replaced; there are no extra full-screen texture passes, per-frame timers,
always-on effects, or geometry-changing menu animations.

## Verification

- `python tests/native-controls.py`: offscreen Qt keyboard feedback, disabled
  controls, segmented selection with Reduce Motion, pending-menu-action cancellation,
  and existing widgets.
- `python tests/micro-interactions.py`: shell and shared-control behavior
  contracts, including honoring Reduce Motion.
- `python tests/dock-motion.py`: Dock launch bounces and notification badges.
- `python tests/dock-lifecycle.py`: isolated, fixture-only close/reopen, slot/divider
  geometry, delegate/capture identity, pinned apps, startup retention, stale
  timer cancellation and mid-flight Reduce Motion. No full shell or external services.
- `python tests/menu-popup.py`: popup-surface stability on menu switching.
- `python tests/check-qml.py`: QML parser validation across the tree.

## Final polish: tactile menus and mid-flight accessibility

### Dock lifecycle and close handoff

Dock recent-icon cleanup now uses a **single-shot timer** for the nearest
pending deadline, instead of polling every 25 ms throughout the hold and exit.
A new open, a pin action or a resumed drag reschedules the same timer; after
the final slot is removed it stops completely. The existing keyed delegates and
220 ms width/opacity collapse remain, so the Dock's glass backing retains its
geometry as the gap closes. A 90 ms upward/165 ms settling nudge confirms an
already-running app was selected; it does not change slot dimensions or replay
the longer launch bounce. Reduce Motion cancels the nudge immediately.

The shell's opening card now uses the compositor's exact 28 px upward center
bias, plus the shared screen-fit helper, avoiding the last-frame correction
seen when its estimated rectangle disagreed with the actual window frame.
The native compositor exit and opacity fade last 200 ms rather than 100 ms;
closing still does not draw a fake window-snapshot card. Dock restore explicitly
focuses the returned window after moving it to the Dock monitor's workspace.

Transient app identity is separate from window-list identity. Keyed ScriptModels
keep pinned icons, running icons and unaffected backdrop captures alive when
one window changes. A just-closed transient icon remains briefly, then its
opacity and entire slot width follow one transition. Each slot owns its gap;
the final transient divider follows the remaining slot presence, so destruction
at zero width cannot introduce a spacing jump. These durations are Golden Gate
design choices, not claims about Apple's exact timings.

Reopening during the hold or departure reuses the same delegate, and launching
from a recent icon extends its lifetime through the existing eight-second
startup timeout. Synthetic entries without a relaunch command are inert after
their last window closes. Pinned apps keep their position. Dock density does
not increase icon size when an app closes, and the layer-shell reserve no
longer follows crowded-icon sizing; app exits do not resize the compositor's
work area. Density can tighten when additional apps open and resets next session.

Normal close leaves Hyprland's window texture fade unobstructed. The previous
opaque app-color launch card was not a window snapshot; inserting it on close
could flash over the real window. The legacy fold API remains opt-in for
experiments, not the default close effect and not a true Genie implementation.
Launching/resetting cancels every prior close timer/fade; closing the first
window before handoff removes its pending overlay immediately. Periodic legacy
frame tracking is disabled unless that effect is explicitly enabled.

Installed-GPU acceptance is still required: record rapid close/reopen at 60/120
Hz, several unpinned apps leaving together, crowded Dock sizing, pin/drag during
the recent hold, multi-monitor launch/focus and Reduce Motion mid-departure.
Mock captures verify object lifetime, not actual GPU frametimes or texture output.

Context menus in both native apps and the shell settle from only 97.5% to
full scale in 170 ms. The earlier 90%-to-100% spring took 435 ms and felt
disconnected from the pointer. Crucially, shell popup *surfaces* never change
size or anchor while mapped: the adjustment only touches rendered menu
content, preserving the compositor safety invariant. Reduce Motion continues
to skip entry movement.

The shared search field cancels a **currently running** clear-button fade
when Reduce Motion turns on. It snaps the opacity back to its declarative
shown/hidden state in the same event, rather than leaving an intermediate
opacity that may intercept focus or confuse the user. The native-control
regression exercises this mid-animation preference change.

Overlay scrollbar tracks and thumbs now clamp to the available height of
tiny inspector panels. A 24-pixel minimum thumb no longer sticks out of a
shorter track or produces negative thumb coordinates; ordinary scrollbars
retain the same tactile width and color transitions. Auto-hidden scrollbars
are no longer invisible input blockers: their drag hit area activates only
for a visible, hovered, active or pressed scrollbar. Source-contract tests
cover these conditions.

## Window and navigation choreography

**Sidebars and inspector panels** use a 215 ms ease, with the public width
remaining the desired width and the animated presentation feeding both
`contentX` and `contentWidth`. Both edges, separators, toolbar positioning
and clipped panel areas follow a common boundary. A toggle can reverse
mid-flight without leaving a blank stripe between glass and content.
Intermediate widths are clamped so narrow panels cannot make their children
negative-sized. There is no sidebar entrance on the app's first frame.

**Document sheets** are now one reusable `apps/lib/ModalSheet.qml` component.
The New Project and other LCode sheets use this shared component, as do Files'
Rename, New Folder and Empty Trash confirmations. The scrim and attached
sheet animate together; the sheet remains mounted for its short exit fade,
but it stops intercepting input on dismissal. A remembered focus origin is
restored on close. Escape and click-away respect dismissibility.

**LCode's console** docks from the editor's bottom seam. The editor height
and the console's visible edge follow the same 205 ms eased boundary;
physical dragging bypasses animation so the divider stays under the pointer.
The resize handle measures movement in the stationary editor coordinate
space, preventing drag-feedback jitter. Find/Replace opens with a short 170 ms
content reflow; tabs tint and compress very slightly on interaction. The
toolbar activity capsule follows the animated inspector boundary, but yields
gracefully when the workspace is too narrow, instead of painting over adjacent
scheme and inspection controls.

**Files Quick Look** now grows only ~2.8% rather than bouncing in, morphs
between preview aspect ratios, and fades loaded images into the card.
A loading image retains the previous preview dimensions until the new image
is ready, avoiding a double resize; failed images show an explicit fallback
message instead of a blank rectangle. A
temporary "Preparing Preview" label keeps large images from appearing blank.
Preview controls and document-sheet buttons stop accepting input as soon as
dismissal begins, even while the exit fade remains visible. No second action
can slip through during the transition.

**Design popovers** scale and fade in on the side of their source with room
available, and restore focus on dismissal. If reopened during a fade, the
animation is retargeted instead of spawning a stale second surface.

When **Reduce Motion** is enabled, sidebar widths snap and sheet/popover
scale/translation is suppressed. Color and opacity changes still identify the
current state, without relying on direction of travel.

**Tests**: `python tests/window-choreography.py` enforces shared-QML
contracts; `python tests/native-controls.py` exercises sheet entrance,
Escape/focus return and rapid reopening in Qt; `python
tests/files-interactions.py` drives the actual Files QML through sidebar
toggles and dialogs. They run in CI, but physical trackpad, GPU refraction and
installed Hyprland window behavior still require hands-on validation.

### Browser and navigator continuity

**LCode navigator sections** (Project, Find, Issues, Reports) crossfade over
125 ms rather than abruptly replacing the content. The outgoing section is
disabled as soon as navigation changes, preventing accidental input during the
exit fade. Folder disclosure arrows use a consistent 125 ms eased rotation.

**Document tabs** fade on insertion/removal, and neighboring tabs move into
the new position instead of teleporting. Programmatic file opens automatically
scroll the selected tab into view. Motion is disabled for Reduce Motion.

**Files grid/list** swaps views over 125 ms and immediately transfers
interaction rights to the incoming view. Its outgoing scrollbar disappears
rather than hanging over the new view; the shared Scroller now honors the
associated Flickable's visible/enabled state. The switch preserves the current
selected item in the viewport or, with no selection, the relative scroll
position. List-row hover and selection receive a short 95 ms color response.

**Activity capsule regression:** Removed a duplicate `visible` binding in
LCode Workspace, which could break QML parsing. Its content is clipped and
constrained when inspector motion reduces the available toolbar width.
Guard checks prevent the invalid binding from returning.

**Keyboard-aware navigator:** Arrow Up/Down roves through project entries;
Right expands a collapsed folder or steps into its children, while Left
collapses the folder or moves to its parent. A thin accent outline marks
*keyboard focus* separately from the editor's selected file. The navigator no
longer writes over Workspace's live `selectedPath` binding, so the selection
continues tracking the active editor even after a pointer click. The active
navigator icon also shows its checked state.

**Inspector context changes:** The file and App Designer inspectors gently
crossfade while immediately handing input to the incoming pane. Switching from
a three-tab design component to a plain, two-tab component clamps the selected
tab to Layout if Actions was active, preventing an empty inspector. File, design
selection, and inspector-tab changes reset the pane to its heading.

**Finder sort headings:** List-view column headers now show subtle hover and
press states and a pointing cursor; the actively sorted column has stronger
text contrast. Shared sidebar rows expose their selection and press action to
accessibility services, and toolbar toggles announce their checked state.

**Finder's keyboard-first browsing:** Typing a filename prefix selects the
next matching entry without filtering the folder, moving files, or changing
the search bar. A repeated single character cycles through matching entries,
and an unmatched prefix can restart from the newest character. The passive
"Jump to" cue fades after 950 ms. Arrow keys clear that prefix; Home/End and
Page Up/Down navigate the grid or list, including Shift range selection.
Typing never intercepts an open document sheet, Get Info dialog, transfer
conflict or Quick Look. Escape on the Empty Trash sheet uses its close action
rather than changing a bound visibility flag.

**Menu-bar stability:** A title switch explicitly hides the previous popup
before changing the anchor and item geometry. The displayed menu rows now live
in an independent snapshot instead of a QML binding to the incoming rows:
otherwise both sides of the shape comparison always matched, and a menu could
resize while still mapped. A dedicated live-state preview assertion now
checks the requested menu title, actual displayed menu rows, and fully
opened popup after switching File → Edit. Pixel-difference diagnostics
remain visible in the test output, but are not used as a flaky pass/fail
criterion when Qt's offscreen compositor settles or refraction changes.
The popup geometry guards remain enforced in CI.

**CI stabilization:** Native search-field tests now click the center of the
fully revealed clear affordance instead of using a fragile hard-coded
coordinate before its fade-in has completed. The native TextInput has a
stable scoped `objectName` for Qt/PySide focus tests; reading its QML
alias directly had triggered a Python QQuickTextInput* converter error.
The separate Music playlist regression found filenames sorted by their
extensions instead of their displayed names; Music now sorts by the stem.

**Finder grid marquee:** Dragging from empty grid space now paints a
slim accent-outlined selection rectangle over matching icons. Shift extends
the existing selection, Control toggles the intersecting icons, and an
unmodified drag replaces it. The hit area stays behind actual icon delegates,
so file dragging and folder DropAreas retain their own input route. The
marquee uses live delegate geometry and only selects instantiated cells;
it does not silently select out-of-view files or start destructive operations.
The rectangle appears directly under the cursor with no lag or bounce, and
it is removed immediately on release. QML regression contracts and native
Files tests cover the modifier cases and inactive grid.

**Dialog continuity:** Shared document sheets absorb clicks on their
backdrop even when dismissal is forbidden, rather than allowing the click to
trigger a control underneath. A close callback that opens a replacement sheet
retains the original focus origin and keeps focus inside the new sheet until
the final dismissal. Files' Get Info now uses this common sheet rather than
an unguarded floating rectangle, including small-screen scrolling and Escape
dismissal. Copy Path acknowledges success with a brief "Copied" label that
resets on close or reopening.

**Quick Look keyboard ownership:** Opening Quick Look moves keyboard focus
to its card. Left/Up and Right/Down still change Files' selection underneath,
then return focus to the preview; Return opens the item and Space/Escape
dismiss it. The preview stays in place during repeated navigation instead of
forcing the user to click Finder between files. Native interaction tests cover
navigation, focus retention and dismissal.

**Finder keyboard destinations:** The Favorites and volumes sidebar now
supports Up/Down and Home/End roving focus across sections; focus is outlined
independently from the currently selected location, and activation remains a
separate Return/Space action. Deeply scrolled destinations move into view as
focus changes. Path-bar breadcrumbs are actual focusable controls with
Return/Space and screen-reader press support, a slight press compression and
Reduce Motion support. Collapsed breadcrumb groups open their menu from the
keyboard rather than being mouse-only.

**Settings search continuity:** The suggestions overlay stays mounted through
a short fade but releases interaction immediately when the search loses focus.
Results now tint in softly as keyboard or pointer selection changes, with
zero scale/opacity travel when Reduce Motion is enabled.

**Verification-code timing:** A CI failure exposed a fractional-second
rollover where a valid six-digit verification code could appear with 0 seconds
remaining. Whole-second modulo now reports 1–30 seconds throughout the valid
window. A boundary regression covers 29.999, 30 and 59.999 seconds.

The acceptance boundary remains the same: connected GUI/native-preview
checks must run before these interactions can be called verified on a real
Wayland/Hyprland installation.

## Golden Gate shell restoration (2026-10-09)

Launchpad now supports arrow-key navigation through icons and across pages,
Home/End, Enter/Space activation and typing from a focused icon to search.
Opening a folder moves focus inside it; Escape closes the folder and restores
its original grid icon. Keyboard focus scrolls folder icons into view. Escape
clears a search first, then closes Launchpad on the next press; the shared
search field and its parent no longer both act on the same Escape event.
Fixture checks exercise these interactions with the production QML.

The Files breadcrumb keyboard check follows both QObject ownership and the
Qt visual tree, so it can find Repeater delegates on current Qt. It verifies
navigation from Downloads to the parent folder, rather than reactivating the
current path. The previous CI failure was a test lookup issue; the breadcrumb
was already present and usable.

The supplied Launchpad and Control Center references replace the earlier
Big Sur box. Control Center now paints separate canonical glass modules:
circular actions, individual Wi-Fi/Bluetooth/AirDrop pills, wide Focus and
Now Playing pills, a Mirroring pill, and vertical brightness/volume capsules.
The horizontal controls use radius = height / 2; there is no square
connectivity container. Its Wayland
surface stays fixed; a viewport scrolls additional controls on shorter screens.
The compact grid caps its unit at 56 px with 10 px gaps: its carrier is
282 px wide instead of 368 px, circles are 56 px across, connectivity/Focus
pills are 44 px tall and level capsules are 56 × 152 px. Now Playing is
76 px tall. Titles fit horizontally and secondary text elides as needed.
Pills and circular actions squash slightly on press and bounce to 102.5%
on release/keyboard activation, then settle within 335 ms. Reduce Motion
stops an active bounce immediately. Only visual transforms move; the grid
does not resize during interaction.
Control Center omits accent focus outlines on its actions, level capsules,
disclosures and detail switches while retaining keyboard/accessibility actions.
The shared level slider and switch still show focus rings in other surfaces.
Its entrance grows from 97.5% to 101.2% and settles at 100% over 270 ms,
alongside one 100 ms opacity fade. The content follows that opacity directly,
avoiding a second fade that continually chases the first. Opening/closing
stops the previous presentation animation; Reduce Motion snaps to the final
state and cancels an entrance in progress. The Wayland surface stays fixed.
Display and Now Playing expand into larger controls while existing network,
audio-output, mirroring and Focus workflows remain available.

`apps/lib/LevelSlider.qml` keeps external value bindings intact. Pointer input
updates the fill directly in a stationary hit area; keys and accessibility
change the level in five-percent steps. Return or the disclosure opens controls.
Its standalone fill animation can stop immediately for Reduce Motion.
The slider's painted glass stretches vertically by up to 5.5% when pulled
past an endpoint (4% at the endpoint), with a small opposing horizontal
compression. Release settles over 280 ms. The drag area stays outside the
transformed glass, so midpoint mapping and external value bindings remain
accurate. Keyboard endpoint changes get the same restrained settle; Reduce
Motion suppresses the stretch and cancels a settle in progress.
The search clear affordance also uses a standalone animation: toggling
Reduce Motion stops an unchanged, partially revealed affordance immediately
without Qt's non-root-animation warning.
Brightness commands are coalesced at 40 ms, with a 240 ms idle preference save,
so every pointer event does not start two system processes. An old brightness
probe cannot replace a level chosen during the current interaction.

Launchpad uses the reference's 244 × 40 search field, 146-pixel row pitch and
100-pixel icon canvases at 1536 × 998, scaling the grid for the available
height above the live Dock. Eight columns/five rows fit 1280 × 720 and
1366 × 768 as well. It has a round search field,
page indicators above the real Dock, and wallpaper covering desktop widgets
even without effects. The actual menu bar and Dock stay in the Overlay layer;
opening Launchpad never remaps them or repeats the Dock entrance.
Opening a Dock destination dismisses
Launchpad. Search and folders use the shared glass, with a readable dark tint
behind white text in the fallback renderer. Spotlight has a taller round
search capsule and pill-shaped result selection.

Launchpad keeps its transparent Wayland window mapped between openings,
with hidden content, an empty input region and no keyboard focus while
closed. This preserves render resources rather than recreating the window
at each entrance. Two preparation frames at 0.1% opacity upload icons and
prepare the backdrop before one 150 ms fade; closing/reducing motion cancels
that preparation. Its grid does not zoom. Wallpaper blur is cached at a
quarter of each screen dimension, rather than allocating a full-resolution
blur layer. Launchpad is excluded from HyprGlass's layer list: its wallpaper
already supplies the blur, and a second full-screen glass mask added both
render work and a threshold transition during the fade. Its search and folder
retain canonical QML glass. Hyprland's matching layers have
`no_anim on`, avoiding a second whole-surface popin over the QML animations.
The catalog is frozen for each opening, so icon scans cannot rearrange it
during the fade. Dismissal clears the query/folder after the fade, not during
it. Wheel bursts change one page at a time; keyboard and dragging still work.

Validation: `tests/control-center.py` loads production QML with isolated
services and checks shapes, level-keyboard/external-state behavior, expanded
views, short-screen scrolling, dismissal/reopening and Launchpad shell layers.
The launcher fixture loads only the real launcher/Dock/menu bar, with no
Weather or Maps. Tests cover reference coordinates, laptop grids, stationary
icon/delegate geometry during the fade, catalog stability, wheel bursts,
query preservation during dismissal and Reduce Motion interruption.
`tests/native-controls.py` exercises level dragging, endpoints and mid-flight
Reduce Motion. Existing Focus, Utilities grouping, running-app Dock, menu,
symbol and QML regressions still apply. Headless previews establish geometry
and behavior; actual GPU refraction, Hyprland layer focus and physical touch
remain installed-device acceptance work.

## Real-device acceptance checklist

1. With a trackpad, sweep quickly across a row of Dock icons: labels should
   not flash. Rest for about a third of a second: the label should appear.
2. Press a push button with Space and Return, then with the mouse; all should
   visibly respond and activate exactly once. Disabled controls never activate.
3. Change a segmented picker with arrow keys or by clicking; its selection
   slides into the new position with no stretching of surrounding layout.
4. Shift focus between two windows. Only toolbar depth should recede;
   neither document content nor text contrast should be noticeably dimmed.
5. Open the menu bar, then change from File to Edit. Popup surfaces must
   not change size while mapped or trigger a compositor restart.
6. Visit Notification Center, Mission Control, the switcher, Control Center,
   and sliders while Reduce Motion is on; position/scale animation must stop.
7. Repeat on a real GPU with both Light/Dark and tinted/clear Liquid Glass.
   The headless software renderer cannot certify real refraction, compositing,
   physical touch input, or stable timing on installed hardware.
8. In Launchpad, confirm the menu bar and Dock stay above the grid during both
   entry and exit. Open a Dock app and verify Launchpad dismisses. At short
   display heights, scroll Control Center to Edit Controls and every extra.
   Restart the shell after updating, then verify the compositor has loaded
   the new `no_anim` layer rule. Check five rapid open/close cycles and wheel
   bursts on the installed GPU; there should be one fade and no desktop zoom.
9. Drag brightness/volume, change the same level from another app, and use
   keyboard arrows/Home/End. The fill must track actual state. Expand Display
   and Now Playing; Escape returns from details and closes the main controls.

**Current status:** Code is committed, with offscreen and source-level
regressions added to CI. New commits are not called hardware-validated until
a real installation passes the acceptance list above.
