# Roadmap inventory — 2026-10-09

Based on branch `claude/linux-macos-golden-gate-ui-pckc7s`, including the
Finder/Settings interaction regression fixes through `f1b0039`, and the Dock
lifecycle work described below. “Implemented” is source/fixture coverage,
not a claim that every workflow has passed clean-install hardware acceptance.

## Where the branch stands

| Area | Implemented in the branch | Remaining delivery / acceptance |
| --- | --- | --- |
| Foundation and desktop (0.1–0.2) | Shared design tokens/icons, reference shell, native shell/apps, boot/login/lock, Spaces, notifications, shortcuts, ISO/CI | End-to-end clean-account and installed-system acceptance |
| Boot and hardware (0.3) | ISO and QEMU boot matrix, legacy Hyprland configuration fixes | 3D boot screenshot, GPU/blur/focus/PAM checks, actual keyd app classes, Lua config migration, screenshot parity |
| Micro-interactions (0.3.1) | Shared tactile controls, keyboard/accessibility actions, motion-aware menus/sheets/sidebars; Finder type-to-select/sidebar/breadcrumbs; Settings suggestions; TOTP rollover; LCode transitions | Physical pointer/trackpad, screen reader, large text/localization and slow-GPU profiling |
| Signature details (0.4) | HyprGlass, Spaces/Mission Control, widgets | True texture-based Genie plugin; full app menus/action registry and D-Bus bridge |
| Files (0.5) | Selection/marquee, clipboard/conflicts/progress/cancellation, sortable per-folder views, safe rename/new-folder undo, shared Get Info/Quick Look | Open With, column/gallery, tags/smart folders, transfer queue, broader undo/redo |
| Calendar (0.5) | Editable/duplicable recurring events, occurrence exceptions, Changed Dates, Month/Week/Day, reminders, read-only CalDAV and opt-in refresh/disconnect protection | Two-way sync, invitations, complex recurrence, multi-calendar discovery |
| Focus (0.5) | Timed DND, overnight/weekly schedules, app exceptions, critical-alert opt-in, shared status/expiry | Named profiles, people exceptions, app/context automation |
| Music | Local MPRIS playback, paused queue/position restoration, error recovery, editable/restorable M3U playlists, queue reorder/remove | Smart playlists, library folder selection; physical media keys/audio/Control Center acceptance |
| Setup and reliability (0.6) | Save acknowledgements/locking, non-overwrite file operations, recovery stores, Clock lifecycle, update transactions/rollback, display watchdog, Finish Setting Up | Clean install → first use; real compositor display recovery; installed update/rollback; plugin compatibility |
| Wider platform gaps | Existing functional settings and native app foundations | Printing/PDF, backup/recovery, accounts/privacy/accessibility expansion, advanced network/display configuration, install encryption/migration, Mail workflows, Photos editing and translated UI |

The prior local unpublished Music work is not part of this batch: the published
branch already includes those workflows. Older local edits remain separate.

## This delivery: Dock close and app lifecycle

- Keep just-closed unpinned icons for 900 ms, then fade and close their gap/divider
  together over 220 ms; pinned icons remain. These are chosen product timings.
- Preserve existing icon and mock-capture delegates across window-list changes.
- Reverse departure when reopened; preserve a recent icon through pending startup.
- Stop close-time icon-size expansion and window-area reflow from Dock density.
- Use the native compositor close fade, avoiding a substitute app-color card flash.
- Cancel stale close timers/fades on launch/reset and pending overlays when the
  first window closes before launch handoff; honor mid-flight Reduce Motion.
- Add fixture-only regression coverage in CI. Hardware frametimes remain unverified.

## Continue in this order

1. **Accept the lifecycle batch on the installed desktop:** repeat close/reopen,
   several apps, crowded Dock, pin/drag, multiple monitors and motion settings;
   capture frametimes if a visible hitch remains.
2. **Clean setup → first-use gate:** fresh account, app launches, permissions,
   networking, sound, saving/reopening files, display rollback and recovery.
   Existing source/fixture checks do not close this acceptance gate.
3. **Files everyday workflows:** Open With first, then transfer queue and broader
   undo/redo. Keep destructive operations recoverable and conflict-aware.
4. **Platform integration:** first-party menu action registry, then D-Bus appmenu
   bridging; larger text/screen-reader acceptance alongside it.
5. **Expand services:** Calendar two-way sync, Focus profiles, Music library
   selection and Mail/Photos workflows in independently verified batches.

Full texture-warp Genie animation and broader service integrations are explicit
future work, not prerequisites hidden inside this Dock fix.
