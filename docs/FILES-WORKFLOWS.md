# Files: first feature-gap batch

Files now supports everyday multi-item workflows from its keyboard, context
menu, and toolbar menu. These changes build on the October 8 audit's Files,
operation-feedback, and state-restoration findings.

| Action | Keyboard (Command is mapped to Ctrl by keyd) |
| --- | --- |
| Range selection | Shift-click or Shift-arrow |
| Toggle an item | Command-click |
| Select all | Command-A |
| Copy / Cut / Paste | Command-C / Command-X / Command-V |
| Move copied items here | Shift-Command-V |
| Duplicate | Command-D |
| Get Info | Command-I |
| Undo Rename / New Folder | Command-Z |

Dragging carries the entire selection. Open, Trash and Put Back also operate on
the selection; opening several folders creates separate Files windows. Get Info
shows an item's type, location, size, modified time,
permissions and symlink target; it labels folder size as not counted.

Transfers show item and byte progress, Cancel, a persistent completed/skipped/
failed summary, and Show Results. Name conflicts offer Keep Both or Skip, with
an option to use the choice for remaining conflicts. Existing destinations are
never deliberately replaced. An operation already running produces feedback
rather than silently accepting another one.

Copies are built inside a private staging directory on the destination disk and
published only when complete. Cancellation removes the unfinished staging copy
and keeps completed items. Cross-volume moves copy first, verify that the source
hasn't changed, then remove it; if it changes, both copies are kept and reported.
Symlinks are copied as links, including dangling links. Device files and sockets
are refused. Undo checks item identity and refuses occupied original names or
changed/nonempty newly created folders.

Name, Date Modified, Size and Kind sorting are available. List headings toggle
sorting; grid/list and sort choices are remembered per folder. Reopening restores
the last folder unless the launcher supplies a location. A missing saved volume
falls back to Home with an explanation. Preferences are written atomically to
`$XDG_CONFIG_HOME/golden-gate/files.json` (normally `~/.config/...`). Sidebar
locations scroll at small window sizes and larger text scales.

## Validation and remaining scope

`tests/files-workflow.py` exercises the real filesystem and worker stdin/stdout
protocol, including cancellation, source modification, collision races,
cross-volume move behavior, symlinks, clipboard MIME parsing, Undo and persisted
preferences. `tests/files-interactions.py` loads the production QML with isolated
command fixtures for keyboard selection, clipboard shortcuts, conflict focus,
transfer summaries and per-folder view restoration. Existing Files helper and
disk/location suites remain in place. The new tests are included in CI.

Clipboard commands use the already-shipped `wl-clipboard` package. Clipboard
integration is tested with stand-ins; physical Wayland sessions and removable
volumes still need user-device validation. Cross-volume behavior is exercised
with a simulated EXDEV boundary, not a physical second filesystem.

This batch does not add marquee selection, Open With, column/gallery views,
tags, saved searches, a transfer queue, general undo/redo or persistent operation
history. Only Rename and New Folder are undoable here; copy/move/trash retain
their existing recovery scope. Music/MPRIS, Focus, Mail/Calendar accounts,
backup/recovery and encrypted installation remain separate feature milestones.
