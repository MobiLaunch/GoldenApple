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
Opening Edit changes the entire series, starting from its original date.
Deleting a series first asks for confirmation and explicitly says that
every occurrence will be deleted. Per-occurrence exceptions, event alarms,
attendees, CalDAV synchronization, and day/week views are not provided yet.

Validation: tests/calendar-store.py checks backend persistence and stale edit
protection, tests/calendar-recurrence.mjs exercises the exact production
recurrence.js date rules, and CI runs QML syntax/load suites. No hardware
acceptance or live installed-session test has been performed for this batch.
