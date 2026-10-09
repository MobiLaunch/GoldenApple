# October 8 audit: first bug-fix batch

This batch addresses concrete data-loss, asynchronous feedback, and keyboard
interaction defects identified in the next-level audit. It does not close the
entire feature-gap backlog.

## Changes

- **Passwords:** Recover, Add, and Rename refuse a credential identity collision
  instead of overwriting another item. Web and Passwords serialize their keyring
  writes. Verification-code renames save the replacement before removing the
  old item. Editing waits for the selected secret to load. Unsaved edits survive
  automatic locking in memory, behind the lock screen; navigation and closing
  offer Keep Editing, Discard, or Save. The confirmation supports Tab and Escape.
  Keyboard typing resets the idle timer, and late helper responses cannot
  populate secrets while locked.
- **Mail:** The current composition autosaves and restores a private local draft
  (mode 0600). Writes use atomic replacement. A damaged draft is preserved and
  reported. Closing waits for pending saves; a failed save keeps Mail open.
  This is one local composition, not a server-synchronized Drafts folder.
- **Photos:** An item is removed from the displayed collection only after
  `gio trash` succeeds. A failure leaves it visible and reports the reason.
- **AirPlay Receiver:** Switches and configuration reflect confirmed results.
  Failed settings writes do not restart the receiver, operations disable their
  controls while pending, and service failures show a reason and refresh the
  actual enabled/running state.
- **Wi-Fi:** Joining shows progress, prevents duplicate connection requests,
  uses a bounded NetworkManager wait, and retains the network and failure reason
  for retry. Radio changes refresh the confirmed state after completion.
- **Settings:** Search results work with Up, Down, and Return. Action rows support
  Tab, Space, Return, a focus ring, and an accessibility action. Pane transitions
  and sidebar scrolling honor Reduce Motion.
- **Web:** Downloads distinguish completed, cancelled, interrupted, paused, and
  active states. Completed downloads offer Show in Files; failed/cancelled
  downloads offer Retry. The Passwords entry point opens the system Passwords
  app. Launcher failures produce feedback.

## Regression checks

New CI checks exercise the actual QML with isolated system-command fixtures,
private Mail draft persistence and damage protection, and the production Web
window's download-state labels. Passwords' stand-in keyring tests cover recovery,
creation, and rename collisions while verifying both credentials survive.

The QML syntax check and targeted interaction/backend suites pass. The final
full app-load test was blocked by automatic approval review because Maps makes
external tile requests that may disclose coordinates. No claim is made here of
real-device Wi-Fi, AirPlay, mail-server, or complete first-boot verification.
The full Web launcher suite could not complete: its isolated HOME cannot find
this container's user-installed PySide6. The download-state check instead loads
the production QML window with a temporary profile; it does not validate a
complete desktop session or the Arch WebEngine fallback.

## Still outstanding

The larger audit recommendations remain separate work: backup and restore,
encrypted installation, broader settings parity, richer app workflows, and a
full hardware/setup acceptance pass. This batch also does not add photo undo,
multiple/server-synchronized Mail drafts, or password import/export.
