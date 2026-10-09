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
