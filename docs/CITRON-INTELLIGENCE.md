# Citron Intelligence

A native CitronOS assistant for words, built on the same QML controls and Liquid
Glass materials as the rest of the desktop. Text goes to **Aion Labs**
(`api.aionlabs.ai`, OpenAI-compatible); voice is heard and spoken **on this
computer** (whisper-cpp and Piper), so only the words of a voice conversation
leave it. It is an independent implementation, with no Apple services or Apple
Intelligence backend.

## Setup

1. Install this revision using the normal CitronOS install/update path. The
   system, user and ISO installs include `gg-intelligence`, its desktop entry, the
   shared helper, `whisper-cpp` (speech to text) and `piper-tts` (text to speech).
2. Open **Settings → Citron Intelligence**. Paste your Aion Labs API key (from
   the [Aion Labs dashboard](https://www.aionlabs.ai/)) into the masked field,
   enable the feature and choose **Save Settings**. The login keyring must be
   available and unlocked.
3. Pick a **Model**. The list is Aion's own (`GET /v1/models`, which needs no
   key), loaded when the pane opens; the default is `aion-labs/aion-3.5-mini`.
4. Open Citron from Applications, the menu bar wand, or **Super+Shift+Space**
   (voice). Requests use your own Aion Labs account and its allowance.

Aion's models are text-only and tuned for conversation and storytelling (their
descriptions say so); they think before answering, and Citron keeps that
reasoning out of what it shows and says (`reasoning_split`, and any `<think>`
text a model puts inline is removed).

## Tools

| Tool | Behavior |
| --- | --- |
| Ask Anything | A chat: type below and press Return. The latest exchanges are sent as context. |
| Talk to Citron | ⇧⌘Space or Ask Citron opens the morphing haze and starts listening at once. Only a brief status and speech captions appear. Esc or the shortcut dismisses and stops capture. |
| Writing Tools | Proofread, rewrite, friendly, professional, concise, summary, key points, table and custom instructions (including translation). |
| In-app writing | Right-click → Writing Tools or Ctrl+Shift+W in shared multiline editors; dedicated actions in TextEdit, Notes' formatting menu and Mail's composer. |

Creating and editing images went with Gemini: Aion Labs' models work with text.
`gg-intelligence --image` and `--photo` say so and exit; Photos no longer offers
"Edit with Citron".

Writing Tools shows the exact selected text (the entire document when nothing is
selected). Choose **Send to Aion Labs**, review the response, then **Replace** or
**Copy**. Replacement is one undoable plain-text operation, refused if the
document changed after the sheet opened.

```sh
gg-intelligence
gg-intelligence --voice
gg-intelligence --writing
gg-intelligence --settings
```

## Talking to Citron

```
microphone ─► speech gate ─► whisper-cpp ─► Aion Labs ─► Piper ─► speaker
 (PipeWire)    (voice.py)     (on device)    (the words)   (on device)  (PipeWire)
```

- **Only speech is transcribed.** `voice.py`'s `SpeechGate` listens 100 ms at a
  time and keeps only what sounds like someone talking: louder than the room's
  learned noise floor, with its energy in the voice band, rising and falling with
  syllables. Silence, a fan, hum, hiss, a held note and clicks never become a
  request. The 400 ms before speech is kept with it, so the first syllable isn't
  lost; 600 ms of quiet ends an utterance (30 s at most).
- **Speech to text, on this computer.** Each utterance is written to a private,
  owner-only file in the runtime directory (`$XDG_RUNTIME_DIR`, memory), read by
  `whisper-cli` in Citron's language, and deleted at once. Whisper's notes on
  non-speech (`[BLANK_AUDIO]`, "(music)") and the lines it imagines from silence
  are dropped.
- **The reply, streamed.** The words go to Aion with a few previous turns and an
  instruction to answer briefly, plainly and in Citron's language. The caption
  grows as the answer arrives.
- **Spoken as it comes.** A Piper process starts the moment you stop talking, so
  its voice loads while Whisper and Aion work; each sentence is spoken as soon as
  it's whole. In testing, first audio came about 2.3 s after speech ended on CPU.
  **Speak Replies** off shows the answer without speaking it.
- **Interrupting.** With PipeWire's WebRTC echo canceller (loaded for the session
  and removed after), talking over Citron stops it. Without one, the microphone
  rests while Citron talks ("speaker-safe mode").
- **Hearing itself.** If Whisper hears what Citron just said almost word for
  word, it isn't answered: from then on the microphone rests while Citron talks,
  and Citron says why. Headphones let you interrupt it.
- **Language.** Settings → Citron Intelligence → Language (default: the system's,
  else English). Whisper listens for it and Aion is told to answer in it unless
  you ask to switch. 22 languages, each with a Piper voice (two for some).

### Voice files

The first voice conversation downloads a Whisper model (**Fast**, base, 60 MB, or
**Accurate**, small, 190 MB) and the chosen language's Piper voice (about 60 MB)
to `~/.local/share/golden-gate/citron/`, with progress in the overlay. Each file
is checked against the size and SHA-256 in `apps/lib/intelligence/voices.json`
and refused otherwise; partial downloads are discarded. Settings shows how much
is still to fetch. After that, voice needs nothing but the network for Aion.

## Data and credentials

- The feature starts disabled. Requests contain only the prompt, the text/history
  shown in the conversation, or the words of what you said. No background screen,
  clipboard, file-library, email or notification scanning takes place.
- Keys live in Secret Service under `service=citron-intelligence, account=aion`.
  Config contains only enablement, the model, voice and language. The key and
  request bodies reach the helper over stdin, never command-line arguments, and
  never cross into QML. **Remove Saved Key** also clears a key saved for Gemini
  before this version.
- Developers may set `AION_API_KEY` in the launching environment; it overrides
  the saved key and Settings says so.
- HTTPS goes to Aion's fixed endpoint with `Authorization: Bearer` in the header.
  Redirects are refused and provider error bodies are never shown.
- Conversations stay in memory and are cleared on dismissal. No recordings are
  kept; the session's private folder is removed when it ends.
- A passwordless live-USB keyring is not encrypted. Aion Labs' terms apply to
  what you send; usage beyond its free allowance may be billed.

## Limits and errors

Text input is limited to 60,000 characters; chat context to 120,000. Empty,
filtered and truncated results are distinguished. The helper has a 120-second
network timeout (Aion's edge returns 524 for longer non-streamed requests), and
the UI stops a request after 150 seconds. Invalid-key, unavailable-model,
usage-limit (429) and network errors leave input intact; in voice, a refused key
ends the session, other failures are said and listening goes on.

## Architecture and verification

`apps/lib/intelligence` holds the shared transport (`Service.qml`), writing sheet,
settings panel, the REST helper (`helper.py`), the voice session (`voice.py`) and
the voice catalogue (`voices.json`). Run without an API key:

```sh
python3 tests/intelligence.py              # Aion contract, privacy, voice-file checksums
python3 tests/intelligence-live.py         # voice: gate, echo, turn pipeline, barge-in
python3 tests/intelligence-ui.py           # PySide6, offscreen Qt
python3 tests/intelligence-shell-visuals.py
```

The pipeline was also run end to end with the real `whisper-cli` and Piper, a
fake microphone playing a spoken question, and a local stand-in for Aion's SSE
stream: the question was transcribed exactly, answered across three turns with
history, and spoken. A live Aion call needs the user's key, which wasn't used in
testing (only an invalid key, to check the 401 path).

References: [Aion Labs API](https://www.aionlabs.ai/docs/api-reference/),
[whisper.cpp](https://github.com/ggml-org/whisper.cpp),
[Piper](https://github.com/OHF-Voice/piper1-gpl).

## Ambient voice identity

Citron's normal invocation is voice-first. `apps/lib/intelligence/CitronBlob.qml`
paints soft, morphing colour fields; movement follows normalized microphone
loudness while listening and speaker loudness while speaking. No PCM is shared
with QML. Reduce Motion freezes the animation without hiding captions or status.
