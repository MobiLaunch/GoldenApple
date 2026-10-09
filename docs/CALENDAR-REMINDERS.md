# Calendar event reminders

The bell in Calendar opts into background notification delivery. This
installs a user-level systemd timer and service that checks every minute
even if Calendar itself is closed. It does not run as root.

Each local event or individual changed occurrence supports a notification
at the event time, 5 minutes before, 15 minutes before or an hour before.
All-day events without a specified clock time notify at 9:00 AM local
time. The service accounts for moved or skipped occurrences.

For duplicate protection, each successfully delivered notification is
recorded in a private atomic JSON file under the XDG state directory.
Delivery failures never mark a reminder as sent. Damaged notification
history is preserved and blocks delivery rather than being overwritten.
Events missed by more than two minutes are not replayed hours later.

Offline tests: python tests/calendar-reminders.py and
python tests/calendar-store.py. Actual systemd user services, system bus
notifications, calendar permission settings and physical-device operation
have not yet been fully validated.
