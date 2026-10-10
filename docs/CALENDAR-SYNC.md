# Calendar remote sync: current support

Calendar's cloud button opens the account sheet. Enter the HTTPS URL for a
specific CalDAV calendar collection (not the general account home page), a
username and a password or provider-issued app-specific password. Select
Connect, then Sync Now. After that, you can optionally enable automatic read-only refresh every 15 minutes. The account sheet shows the last successful import time.

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
incremental ETag sync, OAuth login, two-way edits, and
invitation workflows are still pending.

Offline tests: python tests/calendar-caldav.py. Real provider and live
desktop testing remain necessary before treating this as production-ready.

Auto refresh runs in a systemd user timer (not as root), whether or not the Calendar window is open. If the network, keyring or provider is unavailable, the last successful import remains available. Disconnect disables the timer and removes the account and remote cache; a simultaneous in-flight import cannot write it back after disconnect. If the desktop keyring is locked at disconnection time, account data is still cleared locally and the UI warns that the stored keyring entry still needs cleanup. Automatic refreshing has not yet been acceptance-tested with real CalDAV providers.
