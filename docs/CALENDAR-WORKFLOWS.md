# Calendar: repeating events and series editing

The native Calendar supports creation, editing, duplication, and deletion of
local events. The existing store protects damaged data and maintains a last-good
backup. Editing keeps the event identity and verifies that the original values
have not changed in another window. Duplication creates an independent event.

The Repeat menu offers Never, Every Day, Every Week, Every Month, and Every
Year. An optional YYYY-MM-DD end date stops a series, inclusive of that day.
No end date means the series repeats indefinitely, computed only for dates
currently displayed. Weekly checks use UTC-day differences to avoid local
daylight saving transitions shifting the day of the week.

A 31st-of-the-month event skips months without a 31st. A February 29 yearly
event appears only in leap years. Existing events that lack repeat settings
remain one-time events.

Repeating events are stored as one series, not independent occurrences.
The date view projects occurrences without changing the saved source date.
Opening Edit offers This Date or Entire Series. A moved single occurrence
appears at the replacement date without moving the rest of the series;
individual dates can also be skipped. Whole-series rule edits are refused if
there are saved exceptions, rather than silently losing changed instances.
The backend supports restoring an exception, but the interface does not yet
provide a dedicated skipped-dates manager. Deleting a repeated event asks
whether to skip one date or delete its full series. Event reminders and
read-only CalDAV collection sync are provided in separate subsystems.
Two-way CalDAV, invitations, complex server recurrences and day/week views
are still not implemented.

Validation: tests/calendar-store.py checks backend persistence and stale edit
protection, tests/calendar-recurrence.mjs exercises the exact production
recurrence.js date rules, and CI runs QML syntax/load suites. No hardware
acceptance or live installed-session test has been performed for this batch.
