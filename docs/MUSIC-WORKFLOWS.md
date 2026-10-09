# Music playback and system controls

Music publishes its actual QtMultimedia playback state through the standard
[MPRIS interfaces](https://specifications.freedesktop.org/mpris/latest/).
Metadata, playback status, position, repeat, shuffle and volume are available to
Control Center, Now Playing and `playerctl`. System requests are forwarded to
the player; the publisher does not assume a command succeeded. Music's service
name includes its process ID, so another Music window cannot take over its name.
Raise shows Music's window; Quit waits for the final queue save.

The ISO package list includes `python-dbus-next`. Software Update reads that
same list and installs missing packages before updating the application tree.
A missing package or session bus leaves local playback available with a readable
notice and a Retry action. MPRIS OpenUri accepts local file addresses only;
internet stations are chosen through Music's Radio page.

## Reopening Music

The saved queue reopens **paused**, with the current track, local playback
position, shuffle order, repeat mode, volume and mute setting. A restored radio
station stays disconnected until Play is pressed. Missing local files are
removed from the restored queue with a notice. If the current file disappeared,
the saved position is discarded instead of being applied to a different song.
An explicit file-opening request is handled after restoration and takes priority.

Playback Options (the toolbar's ellipsis button) provides:

- Restore Queue on Next Launch: enabled initially; disabling it saves playback
  preferences while omitting the queue and position.
- Clear Queue: stops playback and removes the live and saved queue, keeping files.
- Forget Saved Queue: clears the live queue and moves the previous session to a
  dated backup. Use this to recover from a damaged session record.
- Retry System Media Controls and Retry Saving Queue.

Sessions live at `$XDG_STATE_HOME/golden-gate/music/session.json` (default
`~/.local/state/golden-gate/music/session.json`). Saves use a lock, a private
0600 temporary file, fsync and atomic replacement. A damaged record is refused
until explicitly forgotten. Position is checkpointed every five seconds during
playback; control changes, pause and normal close save promptly. Forced process
termination can lose the most recent checkpoint. A save failure keeps the
window open with Retry, Dismiss and Quit Without Saving actions.

## Interaction details

Next and Previous preserve paused or stopped playback. Previous restarts the
current song after three seconds; otherwise it selects the previous song.
Transport controls have keyboard focus and accessible names. Tab reaches them;
Space or Enter activates them. Playback Position accepts Left/Right in five-second
steps, Home for the beginning and End for the end. The volume slider supports
arrows, Home and End; changing volume unmutes playback. Escape closes its popover.
The floating player grows with Text Size to keep its two text lines legible.
Playback errors name the affected track and offer Retry without replacing the
queue. Radio streams cannot be sought.

## Validation

`python tests/music-workflow.py` tests persistence and a real MPRIS publisher on
an isolated `dbus-run-session`, including typed metadata, signed 64-bit positions,
property setters, transport commands, stale seek rejection, local URI decoding,
Seeked, and disconnect on EOF. `python tests/music-workflow.py Sessions Contracts`
runs persistence and serialization without a socket when a bus cannot be started.

`python tests/music-ui.py` loads only the production Player, MiniPlayer and MPRIS
bridge with fixture services and generated local WAV files. It checks paused
restoration, seeking, navigation, close-time saves, failure recovery, opt-out,
clear/forget, keyboard operation, large text and readable playback errors. It
also compiles the main window without starting its library or radio services.

CI runs the live private-bus and isolated QML suites. Audible playback, physical
media keys, actual compositor activation and installed Control Center remain
hardware/session checks. Playlist creation/editing, queue reordering/removal,
folder selection and a full macOS Music feature set remain future work.
