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
- `python tests/menu-popup.py`: popup-surface stability on menu switching.
- `python tests/check-qml.py`: QML parser validation across the tree.

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

The acceptance boundary remains the same: connected GUI/native-preview
checks must run before these interactions can be called verified on a real
Wayland/Hyprland installation.

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

**Current status:** Code is committed, with offscreen and source-level
regressions added to CI. New commits are not called hardware-validated until
a real installation passes the acceptance list above.
