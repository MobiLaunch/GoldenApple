# Focus: durations, schedules and allowed interruptions

Settings → Focus and Control Center now share one saved interruption policy.
Choose 15 minutes, one hour, two hours or Until turned off. Settings offers a
Restart action to change an existing session's duration. Control Center shows
the end time and offers the same durations, Turn Off and Focus Settings.

Temporary sessions store an absolute end time. Restarting the shell or signing
back in does not restart the countdown. The menu-bar moon, Settings switch and
Control Center update when the session ends; notifications check the current
clock when they arrive, including just after resume from sleep. Old permanent
Do Not Disturb preferences remain active until changed.

A weekly schedule uses local start/end times and selected start days. Overnight
periods continue into the following morning, including after the last selected
start day. Dates are computed in local calendar time across daylight-saving
changes. Empty days or equal start/end times leave the schedule inactive with a
message. Turning Focus off pauses the current scheduled period, then the next
period runs normally. A manual session takes priority until its chosen deadline;
an active weekly schedule can continue after that deadline.

Clock, Calendar, Mail and Messages are available as exceptions before they first
notify. Other apps appear after notifying. An allowed app retains its enabled
banners/sounds; app-level notification restrictions still apply. Critical alerts
from any app can be allowed separately, off by default. Notification Center keeps
silenced notifications. Starting Focus removes existing disallowed banners;
ending it does not replay them.

Focus changes use the existing locked, atomic desktop preference writer. Session
changes update one key; schedule fields and app choices update individual keys,
preserving unrelated preferences. The interface shows the saved state while a
write is pending and reports failures. Settings controls scroll into view on
keyboard focus; schedule days flow onto more rows at larger text sizes. Control
Center's Focus tile, duration buttons, Back and Settings support keyboard use.

`tests/focus-policy.py` checks the production JavaScript policy, persisted expiry,
overnight/daytime schedules, pause/resume, daylight saving and exceptions.
`tests/focus-ui.py` loads production Settings, Control Center and Notifications
with isolated services, checking saving/failure, expiry, allowed delivery,
history, layout and keyboard access. Only the preference helper runs against
temporary configuration files; arbitrary desktop commands are never executed.
Both suites run in CI. Installed compositor/session behavior still needs a
user-device acceptance run. The broader notification-animation suite was not
rerun locally after automatic approval review blocked its potential external
geocoding request.

This batch adds one Do Not Disturb policy and one weekly schedule. Named Focus
profiles, people exceptions, context automation, calendar-driven activation and
cross-device synchronization remain future work.
