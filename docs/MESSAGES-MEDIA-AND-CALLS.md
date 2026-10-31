# Messages media and video calls — capability boundaries

Golden Gate's native Messages application uses the experimental [BlueFerry](https://github.com/erikwb/blueferry) Bluetooth adapter for plain-text iMessage, SMS and RCS routed through a paired iPhone. **Bluetooth MAP does not transport photo/video attachments or Apple FaceTime signaling.** We must not promise otherwise.

## Photo and video sending: BlueBubbles (optional)

Messages now has a media picker, photo/video preview, queued send action and a **Media Relay Settings…** panel. The media sender is separate from BlueFerry:

1. On a Mac you control, install and configure [BlueBubbles Server](https://docs.bluebubbles.app/landing-page). Verify the Mac can send an attachment in its own Messages app.
2. Expose the BlueBubbles HTTP API over *trusted HTTPS* (for example, a verified private HTTPS reverse proxy). The helper refuses remote plain HTTP.
3. In Messages, choose **Media Relay Settings…** from a conversation menu, or attach a file and select **Setup**. Enter the HTTPS server URL and API password.
4. Choose a photo or video with the **+** button, preview it and click Send. The file is sent to BlueBubbles as a multipart upload to `/api/v1/message/attachment`, addressed to the direct recipient. The server needs to be reachable from Golden Gate.
5. The app says *accepted by relay* only when BlueBubbles replies successfully. Final delivery to the iPhone recipient is not guaranteed until Apple's service has confirmed it. Media sent this way may not appear in BlueFerry's local conversation list because BlueFerry cannot fetch attachment metadata.

The credentials live at `~/.config/golden-gate/messages-media.json` (mode 0600). The UI sends the password to the local helper on stdin (never in the shell command arguments). Relay traffic requires TLS except for an explicitly configured loopback server. Current limit: one photo/video per message, <=100 MiB, direct one-to-one handles only, media file formats JPEG, PNG, GIF, WebP, HEIC, MOV, MP4, M4V, WebM. Group attachments are deliberately disabled rather than risk sending to the wrong thread.

To reset, close Messages and delete the configuration file. **Neither a BlueBubbles Mac relay nor the third-party Apple direct-transport helper is included in the Golden Gate distribution**; users must configure and operate their own compatible bridge. If none is configured, text messaging still works via BlueFerry and photo/video send stays unavailable.

### Alternative transport work

The open-source [gutbash/blue](https://github.com/gutbash/blue) project has a separate Rust direct iMessage implementation with received attachment downloads, but its exposed D-Bus API presently does not expose an attachment-sending method. Integrating outgoing Apple media without a Mac requires carefully extending and testing such a provider, including Apple account registration and its changing, unofficial protocol. It is **not** implemented or advertised here.

## Video calling and FaceTime

**Joining an Apple FaceTime call:** An Apple user creates a FaceTime invite link; Messages → Contact Card → FaceTime Link opens a dialog for that link and launches the system Web browser. Golden Gate does not authenticate as an Apple FaceTime client, create FaceTime sessions, or answer native FaceTime ring events. Web support from non-Apple devices is documented by Apple for Chrome/Edge on Android/Windows; Linux is **not formally listed**, so Chromium compatibility must be tested on installed hardware and is not guaranteed.

**Starting a real independent video call:** Contact Card → Video generates a random, unpredictable room on the configured WebRTC meeting server and opens it with Golden Gate Web. The invitation is filled into the Messages compose field **but is not sent automatically**. The other participant can join through that WebRTC provider, subject to its authentication requirements.

Default server: `https://meet.jit.si`, a test-oriented public service that may require the meeting organizer to sign in. For regular use, configure `GG_VIDEO_CALL_SERVER=https://meet.yourdomain.example` to use a self-hosted or organization-hosted Jitsi Meet server. The app hands camera/microphone permission requests to the browser's existing per-site permission UI. No video data is carried by BlueFerry.

## Source and tests

- `apps/messages.qml`: composer, attachments, preview, relay setup, cards, call actions.
- `apps/messages/ContactCard.qml` and `Avatar.qml`: native contact presentation with optional synced photographs.
- `apps/messages/media.py`: restricted photo/video BlueBubbles multipart transport; JSON response.
- `apps/messages/call-links.py`: FaceTime URL checks and WebRTC room links.
- `tests/messages-media.py`: negative tests for unsupported transport/unsafe paths, a fake multipart API, credential permissions and URL validation.

Run `python3 tests/messages-media.py` to validate without an iPhone, Mac, Apple ID or network connection.
