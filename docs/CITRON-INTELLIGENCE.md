# Citron Intelligence

A native CitronOS assistant using Google Gemini, built on the same QML controls
and Liquid Glass materials as the rest of the desktop. It implements the core
writing, question-answering and image workflows requested for CitronOS. It is an
independent implementation, with no Apple services or Apple Intelligence backend.

## Setup

1. Install this revision using the normal CitronOS install/update path. The
   system, user and ISO installs all include `gg-intelligence`, its desktop entry
   and the shared helper. Existing Python 3, Quickshell and libsecret packages
   are sufficient; no Gemini SDK or extra daemon is required.
2. Open **Settings → Citron Intelligence**. Get an API key from
   [Google AI Studio](https://aistudio.google.com/apikey), paste it into the masked
   field, enable the feature and choose **Save Settings**. The login keyring must
   be available and unlocked.
3. Use **Refresh Models** to list models available to your key. Select a text
   model and an image model, then save again. You can also enter exact model IDs.
4. Open **Citron Intelligence** from Applications, the menu bar wand, or
   **Super+Shift+Space**. Requests use your own Google project and its quota.

Defaults, checked against Google's model documentation on 2026-10-05, are
`gemini-3.8-flash` for text/vision and `gemini-3.1-flash-image` for image output.
Availability is project-dependent and model IDs can change. A 404 tells the user
to refresh/select a model; the app does not silently retry another billed model.

## Tools

| Tool | Behavior |
| --- | --- |
| Ask Anything | A chat: type below and press Return (Shift+Return for a new line), attach a photo, start over with the compose button. The latest 10 complete exchanges are sent as context. |
| Talk to Citron | ⇧⌘Space: Citron's orb over a glass capsule, live captions and a glow round the screen's edges. Speak, type, or interrupt; the mic is on only while it's open and unmuted. |
| Writing Tools | Proofread, rewrite, friendly, professional, concise, summary, key points, table and custom instructions (including translation). |
| Create Image | Native Gemini image generation. Preview outputs and save selected images as copies. |
| Edit Photo | Choose a photo and describe a change, such as removing a background object or changing lighting. Toggle between original and result. |
| In-app writing | Right-click → Writing Tools or Ctrl+Shift+W in shared multiline editors; dedicated actions in TextEdit, Notes' formatting menu and Mail's composer. |
| Photos | The wand and “Edit with Citron Intelligence…” send the selected photo to the editor window. Opening the window alone does not upload it. |

Writing Tools shows the exact selected text (the entire document when nothing is
selected). Choose **Send to Gemini**, review the response, then **Replace** or
**Copy**. Replacement is one undoable plain-text operation. It refuses to replace
text if the document or document identity changed after opening the sheet.
Notes' Markdown formatting outside the replaced selection is preserved.
In arbitrary third-party apps, copy text into the standalone Writing Tools page;
this version does not inject input or read other applications' selections.

```sh
gg-intelligence
gg-intelligence --writing
gg-intelligence --image
gg-intelligence --photo '/home/you/Pictures/Photo.jpg'
gg-intelligence --settings
```

## Data and credentials

- The feature starts disabled. Requests contain only the prompt, text/history
  shown in the conversation and image explicitly attached. No background screen,
  clipboard, file-library, email or notification scanning takes place.
- Keys live in Secret Service under `service=citron-intelligence, account=gemini`.
  Config contains only enablement and model names. The key and request bodies
  travel to the helper over stdin, never command-line arguments.
- Developers may provide `GEMINI_API_KEY` in the launching environment; this
  overrides the saved key and is identified in Settings. Removing the saved key
  also disables requests, but does not unset an environment variable.
- HTTPS requests go to Google's fixed Gemini endpoint, with `x-goog-api-key` in
  the header. Redirects are refused, and provider error bodies are not reflected
  into the UI. No automatic retries or local command execution are enabled.
- Text conversations remain in memory; the app does not persist them. Generated
  previews use private files under `$XDG_CACHE_HOME/golden-gate/intelligence`
  (default `~/.cache/golden-gate/intelligence`). Superseded previews are discarded;
  abandoned previews older than one day are removed when settings/status loads.
- **Save Copy** never overwrites an existing file. Originals are never modified.
  An existing name produces an error even if the file picker offered overwrite.
- The login keyring follows the OS's security: a passwordless live-USB keyring
  is not encrypted. The client does not provide Apple's on-device processing or
  Private Cloud Compute guarantees. Google's data terms and API billing apply.

## Talking to Citron

**Language.** Citron speaks one language: **Settings → Citron Intelligence →
Language**, by default the system's (`LANG`, else English). The session asks
Gemini Live for that language and tells Citron never to change it because of
noise, music, an accent, a foreign name or audio it couldn't make out; it
switches only when you ask it to, and keeps to the new one until you ask again.
A model that refuses an explicit `languageCode` is set up again without it, with
the instruction still in place.

**Shortcut behavior.** ⇧⌘Space opens the live microphone with an explicit user gesture. The Ask and Writing Tools commands remain text-first; while in voice mode the Type chip stops capture and keeps the overlay open.\n\n**Only speech is sent.** `live.py`'s `SpeechGate` listens to the microphone
100 ms at a time and sends Gemini only what sounds like someone talking: louder
than the room's noise floor (which it learns as it goes), with its energy in the
voice band, and rising and falling with syllables. Silence, a fan, mains hum,
hiss, a held note and lone clicks never leave the computer, so they can't start
a reply; a sound that switches on and then stays steady is let through for at
most about a second before it counts as part of the room. The 400 ms before
speech is sent with it, so the first syllable isn't lost, and `audioStreamEnd`
marks the end of it. While Citron is talking, interrupting it takes a voice
near the microphone, louder than what's left of Citron's own voice after echo
cancelling. Gemini's own detection is set to be slow to decide speech has
started (`START_SENSITIVITY_LOW`) and patient before deciding it has ended.

**Hearing itself.** If what Gemini transcribes from the microphone is what
Citron has just said (speakers into the microphone, an echo canceller letting it
through), it isn't shown as yours or answered round and round: for the rest of
the session the microphone rests while Citron talks, and a little longer after,
and Citron says why. Headphones let you interrupt it.

## Limits and errors

Image input supports PNG, JPEG and WebP, up to 10 MB; convert HEIC/RAW first.
Edits are prompt-based, without a brush/mask selection tool. Text input is limited
to 60,000 characters; accumulated chat context to 120,000. Empty, blocked,
malformed and truncated results are distinguished. Truncated Writing Tools
results cannot replace source text directly.

The helper has a 120-second network timeout, and the UI stops a request after
150 seconds. Cancel terminates the local worker and discards a late response;
it cannot recall data already received by Google or undo incurred API usage.
Offline, invalid-key, unavailable-model and quota errors leave input intact.

This release has no live web grounding, background personal
index, autonomous OS actions, notification summaries or cross-device continuity.
Answers cannot claim to have inspected files or performed actions outside the
explicit request. Image generation requires a compatible model and entitlement.

## Architecture and verification

`apps/lib/intelligence` holds the shared transport, writing sheet, settings panel
and Python REST helper. The installer's canonical UI layout retains their
relative paths. `apps/intelligence.qml` provides the standalone application;
the shared `TextArea` lazily creates Writing Tools only when requested.

Run without an API key:

```sh
python3 tests/intelligence.py
python3 tests/intelligence-ui.py  # PySide6 6.11.2, offscreen Qt
python3 tests/intelligence-live.py  # voice: language, speech gate, echo
python3 tests/native-app-backends.py
python3 tests/qml-load.py
```

The backend tests mock HTTP/keyring calls. Qt tests use the preview process
adapter but real Qt text selection, replacement and undo. Live Gemini calls,
Secret Service unlock UX and real Hyprland rendering still need a device test
with the user's API key; no key was supplied during implementation.

References: [Gemini models](https://ai.google.dev/gemini-api/docs/models),
[generateContent](https://ai.google.dev/api/generate-content),
[native image generation/editing](https://ai.google.dev/gemini-api/docs/image-generation),
[Qt TextSelection](https://doc.qt.io/qt-6/qml-qtquick-textselection.html).
