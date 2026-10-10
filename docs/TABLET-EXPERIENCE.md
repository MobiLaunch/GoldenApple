# Golden Gate tablet experience (iPad-inspired)

Tablet mode is an **adaptive shell and application layout**, not another OS,
partition, or profile. Turn it on in **System Settings → Desktop & Dock →
Tablet Mode**. Existing accounts, apps, desktop widget locations and files
remain unchanged. Turn it off to return to the standard macOS-like desktop.

## Home Screen and gestures

- **Swipe horizontally** on the Home Screen to turn icon pages. The pager
  snaps to complete pages, with tappable page dots above the Dock.
- **Portrait** places application icons in four columns. **Landscape** uses
  five to eight columns depending on available width.
- **Swipe down on Home** to open Golden Gate's real Spotlight search;
  tap the top-right corner or **swipe downward from the top-right menu-bar
  area** to show the existing Control Center. A downward swipe is recognized
  only when it moves at least the gesture threshold with little sideways drift.
- Installed apps retain their approved macOS-style launch icons. No generic
  Linux app is allowed to leak into the curated tablet grid.
- Widgets appear on the first page, followed by two rows of app icons;
  additional apps continue on swipeable pages. Wallpaper remains prominent,
  without permanent dashboard headings. Long-press an app or widget to edit.
  On small screens individual pages can scroll vertically to avoid clipping.
- A compact status strip shows time/date, Wi-Fi, battery and privacy indicators
  instead of desktop app menus, with a Control Center touch target.
- The normal iPad-like Dock is the same Dock used throughout Golden Gate.
  Its icon set, recent running apps and notification badges remain available.

## Home Screen customization

Tap **Edit Home** or choose **Desktop & Dock → Customize Home** to add,
remove, change size, and rearrange widgets. Long-press a widget to enter
editing, or tap its movement buttons to change order; where supported,
drag a widget to another position. Touch controls have 44-point tap areas.

Widget choices: Clock, Calendar, Weather, Music, Notes, Batteries.

Tablet widgets are saved to `~/.config/golden-gate/desktop.json` at
`tablet.widgets`. Traditional desktop widgets use the existing `widgets`
key and are never moved or overwritten by switching modes.

The tablet Home Screen is a Wayland **bottom-layer** surface, behind
regular application windows. The existing Spotlight, Control Center, menu bar
and Dock remain independent shell components.

## Tablet lock screen

Tablet Mode uses a larger centered clock, a bottom home indicator, and an
MPRIS-backed Now Playing card (when a player is connected) with working
previous/play/pause/next transport. The account portrait and PAM password field
appear when the screen wakes. Desktop mode and SDDM remain unchanged.

## Tablet application interfaces

The shared application window checks tablet mode as the preference changes.
Toolbars have 44-point controls and navigation rows have at least 46-point
targets in tablet mode. Below roughly 960px application width, several
first-party apps use a compact/mobile-style presentation:

| App | Tablet adaptation |
| --- | --- |
| Files | Content-first view; places sidebar becomes optional |
| Mail | Single reading/list pane with an Inbox back action; optional mailboxes sidebar |
| Notes | Full-width list or editor, with a save-aware back action |
| Messages | Conversations list or current conversation, with a back action |
| System Settings | Categories list becomes a separate screen leading into each pane |
| Photos | Gallery-first view with optional navigation sidebar |
| Calendar | Full-width calendar, toggleable agenda for selected day |
| Music | Full-width library content, toggleable navigation menu |

The same app processes and storage are retained. Landscape/large windows can
continue to show their split panes. Third-party Linux applications do not
automatically gain an iPad UI. This is not an emulation of Apple's proprietary
iPadOS or iPad apps.

## Implementation

- `shell/TabletHome.qml`: horizontal page snap, app columns, page dots,
  touch widget editor and the Home-to-Spotlight gesture
- `shell/widgets/tablet-layout.js`: validate, save and reorder tablet widgets
- `shell/MenuBar.qml`: top-right Control Center touch gesture
- `shell/components/Prefs.qml`: live tablet preference and widget state
- `apps/lib/AppWindow.qml`: shared tablet-width responsive policy
- `apps/lib/theme/Touch.qml`: touch-mode state for shared first-party controls
- `apps/lib/ToolbarButton.qml`, `SidebarRow.qml`: touch-safe hit targets
- Individual app QML files: portrait list-to-detail navigation

## Testing

```sh
node --test tests/tablet-home.mjs
python tests/tablet-app-interfaces.py
python tests/qml-load.py
```

CI also requests QML previews in portrait and landscape using
`GG_TABLET_PREVIEW=1`. Native touch-gesture arbitration, rotation,
multi-monitor interaction and live GPU/Wayland behavior still require
testing on physical touch hardware. The system does not currently include
a full iPadOS-style multitasking/window manager or tablet-specific versions
of every third-party app.
