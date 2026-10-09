# Calendar remote sync: current support

Calendar's cloud button opens the account sheet. Enter the HTTPS URL for a
specific CalDAV calendar collection (not the general account home page), a
username and a password or provider-issued app-specific password. Select
Connect, then Sync Now.

This is a read-only import: remote events are visible in Calendar alongside
local events, but remote events cannot be changed, duplicated or deleted.
Local events are never uploaded. This makes initial provider connectivity
safe to validate before enabling two-way edits.

The implementation uses the standard CalDAV calendar-query REPORT, expects
HTTP 207 XML multistatus, limits response size, does not follow redirects,
and requires HTTPS. Passwords are saved in the desktop's Secret Service
keyring using secret-tool, not the settings JSON file or command arguments.
The account metadata and remote event cache use private file permissions.
A network or parsing failure retains the previous imported cache.

The importer supports one-time events, simple daily/weekly/monthly/yearly
repeats, all-day dates and common timezone-qualified DTSTART fields.
Complex recurrence exceptions, COUNT, multiple BYDAY rules, unusual
timezones or unsupported RRULE clauses are skipped and reported. An empty
remote calendar is a valid sync. Remote data is not an authoritative backup.

Some services require app-specific passwords or OAuth. OAuth-only accounts
are not currently supported. Live provider login, multi-calendar discovery,
automatic incremental sync, ETag conflict handling, two-way edits, and
invitation workflows are still pending.

Offline tests: python tests/calendar-caldav.py. Real provider and live
desktop testing remain necessary before treating this as production-ready.
