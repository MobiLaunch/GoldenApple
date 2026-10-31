# CitronOS 2 "Club Soda": Architecture Proposal

This proposes the target architecture for Club Soda and a migration path from today's
(commit `ae8cbf4`). It keeps what works: Hyprland, Quickshell and QML, the token pipeline,
the `apps/lib` component store, the Python helpers that already have careful data-safety
rules, and the existing tests. It replaces what the audit found fragile.

## Principles

1. **One owner per piece of state.** Every domain (network, Bluetooth, notifications,
   preferences, search) has one long-running service that owns its state and publishes
   changes. Surfaces read from it and ask it to change things. No surface scrapes a CLI.
2. **Event-first.** Services subscribe to D-Bus signals, inotify, PipeWire and uevents.
   Timers exist only for genuinely time-based work (clocks, schedules).
3. **Argv, never shell strings**, for anything that carries data (CS2-002).
4. **Privilege is narrow and per action.** Each privileged operation has its own helper
   and its own polkit action. Nothing passwordless can execute downloaded code (CS2-001).
5. **Packages are the unit of delivery.** If pacman doesn't own it, CitronOS doesn't ship
   it (CS2-011).
6. **The UI process is disposable.** A shell crash must not lose notifications, unlock
   the screen, or leave the user stuck (CS2-005, CS2-006, CS2-024).

## Target layout

```
                       ┌──────────────── user session (systemd --user) ────────────────┐
 Hyprland ──────────── │ citronos-session.target  (BindsTo=graphical-session.target)     │
   + HyprGlass (pkg)   │                                                                 │
                       │  UI processes (restartable, stateless)                          │
                       │   citronos-shell.service     qs -c golden-gate                  │
                       │   citronos-lock.service      qs -c golden-gate-lock  (CS2-005)  │
                       │   apps: app-citronos-<id>@.scope  (per-app scopes)              │
                       │                                                                 │
                       │  Services (own state, D-Bus, Python + dbus-next)                │
                       │   citronos-settingsd   org.citronos.Settings1        (CS2-023)  │
                       │   citronos-notifyd     org.freedesktop.Notifications            │
                       │                        org.citronos.Notifications1   (CS2-024)  │
                       │                        com.canonical.Unity.LauncherEntry        │
                       │   citronos-networkd    org.citronos.Network1 → NetworkManager   │
                       │   citronos-bluetoothd  org.citronos.Bluetooth1 → BlueZ + Agent1 │
                       │   citronos-searchd     org.citronos.Search1 → localsearch       │
                       │   citronos-intelligd   org.citronos.Intelligence1 (providers)   │
                       │   citronos-airdrop     (socket-activated, firewall-aware)       │
                       │   evolution-data-server + goa-daemon (Mail/Calendar/Contacts)   │
                       └─────────────────────────────────────────────────────────────────┘
 System (root)
   polkit actions: org.citronos.update.packages | update.citronos | update.source |
                   touchid | (accountsservice, udisks2, NetworkManager: upstream)
   pacman repo: [citronos] signed;  packages: citronos, citronos-runtime, -shell, -apps,
                -theme, -hyprland-config, -keyring, -hyprland, -hyprglass, -pods-engine
   firewalld (zones ↔ NM connections), zram, btrfs + snap-pac
```

### Why Python and D-Bus for the services

- Python and `dbus-next` are already in the image and in CI (`python-dbus-next` is in
  `packages.x86_64`, and the tests install `dbus-next==0.2.3`).
- The existing helpers' logic (atomic writes, refusal rules, conflict checks) moves into
  services largely unchanged.
- QML talks to services through a small generic bridge: one `DBusObject` item in
  `apps/lib`, implemented as a Quickshell `Process` running a long-lived `gg-dbus-bridge`
  JSON-lines client, until Quickshell gains a general D-Bus type. **This bridge is the
  first piece to build and to measure.** If its latency is poor, write it as a small Qt
  plugin instead.

Rust or C++ services would use less memory, but would add a third language and lose
the existing code. They can come later for any service that measurements show to be hot.

## Service boundaries

| Service | Owns | Replaces today | Consumers | Key events |
|---|---|---|---|---|
| `citronos-settingsd` | Typed preferences with defaults, per-domain files, last-good backups | `desktop.json` + `gg-pref` + `FileView` in many places | Shell, Settings, every app | `Changed(key, value)` |
| `citronos-notifyd` | Notification store (SQLite), Focus rules, badges, progress | In-shell `NotificationServer`, `mail-badges.json` | Shell (banners, Notification Center, Dock badges), Settings | `Added`, `Removed`, `BadgeChanged` |
| `citronos-networkd` | Wi-Fi scan, join (with secrets), VPN import, 802.1X, captive portal | `nmcli` text in Control Center, Settings and the menu bar | Control Center, Settings, menu bar, AirDrop (trust zone) | NM `StateChanged`, `AccessPointAdded` |
| `citronos-bluetoothd` | Adapter, devices, pairing agent, battery, accessory profiles | `bluetoothctl` in Settings and Control Center; CitronPods glue | Control Center, Settings, Nearby card, CitronPods card | BlueZ `PropertiesChanged`, agent requests |
| `citronos-searchd` | Search providers, ranking, recents | `find` in Spotlight | Spotlight, Files, Citron | Streaming results per query |
| `citronos-intelligd` | Providers, tool registry, permission prompts, audit log | `intelligence/helper.py`, `live.py` (kept as provider code) | Citron overlay, Writing Tools, Photos editing | `ConfirmationRequested`, stream chunks |
| `citronos-airdrop` | LocalSend protocol, transfers | `airdropd.py` (kept, run as a unit) | AirDrop app, share sheet, notifications | Socket activation |

### State management in QML

- Each service gets one singleton in `apps/lib/services/` (`Network.qml`,
  `Bluetooth.qml`, `Settings.qml`, …) that mirrors the service's properties and exposes
  async methods returning `{ok, error}`.
- Every write path shows its failure through the shared `InlineBanner`. Silent
  fire-and-forget writes go away (CS2-023).
- Optimistic UI is allowed only where the service echoes a confirmation. Otherwise the
  control shows a busy state.

## UI library (`apps/lib`)

**Keep:** the single Theme singleton, Glass, AppWindow, the controls, and the rule that
no app imports `QtQuick.Controls`.

**Add:**
- **Tokens with roles.** Type (`Theme.font.*`), radius (`Theme.radius.*`, 7 values),
  colour roles, and motion roles (`Theme.motion.tap … ambient`).
  [02 §3](02-UI-UX-AUDIT.md#3-proposed-motion-system) has the motion table.
- **New components:** AppIcon, SearchField, ListRow, FormRow, FormSection, Popover,
  Alert, ConfirmSheet, Toast, InlineBanner, Spinner, Tooltip, NavigationSplitView and
  Badge. [02 §4](02-UI-UX-AUDIT.md#4-proposed-shared-components-additions-to-appslib)
  lists them.
- **Lints** in `tests/design-lint.py`, which fails on:
  - `radius:` or `duration:` with a literal value outside `apps/lib`;
  - new `#RRGGBB` colours outside `theme/`;
  - pointer handlers without `Accessible.*`;
  - `dispatch("exec " + …)` or `["sh","-c", … + …]`.

  Existing violations go in a baseline file that may only shrink.

## Search

```
Spotlight / Files / Citron ──► org.citronos.Search1.Query(text, scopes) ──► results stream
                                   │
              providers: apps (desktop entries) · settings panes · calculator/units ·
                         files (localsearch/tinysparql: names, content, metadata) ·
                         contacts/mail/calendar (EDS) · recent documents (recently-used.xbel) ·
                         web suggestion (opt-in) · Citron answer (opt-in, explicit)
```

- Each provider is a Python module with `search(query, limit) -> Iterable[Result]` and a
  timeout. The service merges and ranks results by type priority, then prefix match,
  then frecency.
- Spotlight renders the results as they stream in. The first results must arrive in
  under 50 ms (apps and settings are in memory).
- Indexing respects `.nomedia`, `~/.local/share/Trash` and per-folder exclusions in
  Settings → Spotlight, which already toggles result kinds.

## Mail, Calendar, Contacts

**Recommendation:** keep the CitronOS UIs, and replace the back ends with
**GNOME Online Accounts and Evolution Data Server**, reached over D-Bus. (EDS doesn't
need GNOME Shell.)

| Option | Pros | Cons |
|---|---|---|
| **EDS + GOA** (recommended) | OAuth2 (Google, Microsoft), IMAP IDLE, offline cache, CalDAV/CardDAV read-write, EWS; one account set-up for all three apps; mature | Adds about 5 packages and its own processes; Evolution's camel mail store isn't built for third-party UIs, so Mail may need a thin Python IMAP layer with GOA tokens |
| Grow the Python helpers | Keeps the code style | An email and calendar sync engine is a multi-year project; OAuth, IDLE and caching are all still to build |
| Ship Thunderbird or Geary | Complete today | Not CitronOS-native; breaks cohesion |

**Pragmatic split:**
- Calendar and Contacts use EDS directly (`evolution-data-server` D-Bus API).
- Mail uses GOA for accounts and OAuth tokens, plus an upgraded Python engine: long-lived
  process, IMAP IDLE, an SQLite cache keyed by `UIDVALIDITY`/UID, folders, search
  through IMAP `SEARCH`, attachments, `APPEND` to Sent, threading headers.
- Settings gains **Internet Accounts**, which Mail, Calendar, Contacts and Messages all
  use.

## Packages, updates and releases

### Packaging (CS2-011)

| Package | Contents | Notes |
|---|---|---|
| `citronos-runtime` | `/usr/share/golden-gate/{apps,ui,runtime}`, `/usr/lib/golden-gate/*`, `/usr/bin/gg-*` | Replaces the `install.sh --system` copy step. Wrappers move from `/usr/local/bin` to `/usr/bin` |
| `citronos-shell` | `/etc/xdg/quickshell/golden-gate` | Quickshell resolves `-c golden-gate` through XDG config dirs, so per-user copies go away. Check that Quickshell 0.3.x searches `$XDG_CONFIG_DIRS` |
| `citronos-hyprland-config` | `/usr/share/golden-gate/hypr/*.conf`; a user stub `~/.config/hypr/hyprland.conf` that `source`s it | Updates never rewrite users' files |
| `citronos-theme` | GTK CSS, fontconfig, Plymouth, SDDM, cursor and icon theme | — |
| `citronos-hyprland`, `citronos-hyprglass` | Built together from source in CI | Kept in lock-step (CS2-009) |
| `citronos-pods-engine`, `blueferry-backend`, `quickshell` | Built from pinned sources | Ends AUR `HEAD` builds (CS2-010) |
| `citronos-keyring` | The CitronOS packaging key | Pacman trust. Rotate yearly |
| `citronos` | Meta package with the full `depends=` | One install line |
| `citronos-developer` | LCode toolchains | Optional (CS2-039) |
| `citronos-darling` | Darling and Mac app support | Optional (CS2-032) |

### Release flow

```
main ──► tag vX.Y.Z ──► CI: build pkgs (pinned Arch Linux Archive date) ──► sign ──►
          [citronos-testing] ──► automated upgrade test from vX.Y-1 (QEMU) + boot test ──►
          promote to [citronos] (stable)        ISO built from the same package set
```

- **Channels.** `stable` and `beta` are repositories. `dev` may track branch builds and
  is never the default (CS2-003).
- **Software Update** becomes: snapshot (btrfs + `snap-pac`, CS2-012), then
  `pacman -Syu`, then `flatpak update`. Report the result for each part (keep
  `update-outcomes` semantics), and roll back to the snapshot if the update fails.
- **Version identity.** One `VERSION` file feeds `Release.qml`, `os-release`, package
  `pkgver` and git tags (CS2-038).
- **Interim, before packages exist.** Add signed release bundles: `minisign`, with the
  public key in `/usr/share/golden-gate/release.pub`, verified by `golden_update.py`
  before anything is unpacked. Make the default source a `releases` endpoint, not a
  branch.

### Privileges (CS2-001)

| Action | Helper | Default |
|---|---|---|
| `org.citronos.update.packages` | `update-packages` (pacman, flatpak) | `auth_admin_keep`; the passwordless rule may apply |
| `org.citronos.update.source` | `update-source` | `auth_admin`; never cached, never in a rule |
| `org.citronos.touchid` | `touchid-helper.py` | `auth_admin` (unchanged) |
| Users, disks, network | accountsservice, udisks2, NetworkManager | Upstream polkit actions |

## Citron Intelligence

```
 Citron overlay / Writing Tools / Photos ──► org.citronos.Intelligence1
     ├─ Provider interface: models() · generate(stream) · image() · live(audio)
     │     Gemini (today's code) · OpenAI-compatible (any vendor or local server) · Ollama
     ├─ Tool registry: each tool declares {name, scopes, reversible, confirm}
     │     read-only: search, open app, read selection, read current page (explicit)
     │     write:     set Wi-Fi/Bluetooth/Focus/brightness/appearance (confirm unless
     │                user marked "always allow"), create calendar event (confirm),
     │                send message/mail (always confirm, show the full text)
     ├─ Permission store: per tool × per app, visible in Settings → Citron
     └─ Audit log: every tool call, its arguments and the confirmation outcome (local)
```

- **Prompt-injection posture.** Content from pages, mail and files is passed as data with
  provenance. Write tools never run without an on-screen confirmation the model can't
  produce. A red-team test suite guards this.
- **Resources.** Voice keeps today's `pw-record`/`pw-play` path. Each cloud provider
  states its latency budget, and the local provider checks RAM and VRAM before offering a
  model.
- **Privacy.** Nothing is sent without the user summoning Citron or turning on a feature.
  On-screen context is used only after an explicit "Use what's on screen" action, each
  time.

## Peripherals

`citronos-bluetoothd` exposes an accessory model:
`{id, kind (headphones|keyboard|mouse|controller|phone), battery{left,right,case,main}, features[]}`.
CitronPods becomes one provider of battery and features, fed by its engine, and other
devices get battery from BlueZ `Battery1` and UPower. A feature (noise control, ear
detection) appears only if its provider reports it working for that model. Nothing is
simulated.

## Process lifecycle

- `gg-session` starts Hyprland. Hyprland's `exec-once` runs only
  `systemctl --user start citronos-session.target`.
- `citronos-shell.service`: `Restart=on-failure`, `RestartSec=1`, `StartLimitBurst=5`
  in 60 s, then `OnFailure=citronos-shell-safe.service`, which is the same shell with
  `GG_SAFE=1`: no glass, no widgets, no Citron. Logs go to the journal.
- Apps launch into `app-citronos-<appid>-<rand>.scope` (systemd-run), which gives
  Activity Monitor per-app CPU and memory, out-of-memory isolation, and clean quits.
- The lock screen is its own unit. `misc:allow_session_lock_restore = true`. The unit
  restarts on failure, and re-locks if logind reports `LockedHint=true`.

## Testing strategy

| Layer | What | Where |
|---|---|---|
| Unit | Python services and helpers, JS logic (`tests/logic.mjs`, which isn't in CI yet) | `native-controls` job |
| Component | QML components and surfaces in the preview harness, asserting behaviour, not strings | `tools/preview` |
| **Session** (new) | Headless Hyprland + Quickshell: 10 cold starts with crash detection; screenshots of every surface in light and dark; scripted interactions through `qs ipc`; performance capture (start-up time, idle CPU, RSS) | New `session.yml`, building on the reverted `tests/shell-shots.sh` |
| Security (new) | Shell-string lint, polkit and helper scan, Flatpak overrides scan | `generated` job |
| Upgrade (new) | Install vN-1 in QEMU, update to vN, boot, run the session smoke test | Release pipeline |
| Hardware | A small matrix (Intel iGPU laptop, AMD laptop, NVIDIA desktop, VM) running a checklist before each stable release | Manual, tracked in an issue template |

## Current → proposed (per brief §12)

| Current approach | Why it fails | Proposed replacement | Expected improvement | Migration risk |
|---|---|---|---|---|
| Updates = git snapshot + `install.sh` as root | Unsigned, tracks a dev branch, passwordless (CS2-001, CS2-003) | Signed pacman repository + channels; interim signed bundles | Verifiable, versioned, revertible | High: touches every install. Keep a one-time bridge update that installs the packages and removes the old copies |
| `install.sh` copies into `/usr` and `~/.config` | No ownership or deps; dotfile rewrites (CS2-011) | PKGBUILDs; `/etc/xdg` defaults | pacman integrity; no `/home` writes | Medium: a path change for the shell config |
| `sh` loops in `exec-once` | No back-off, journal or isolation (CS2-006) | systemd user units + session target | Supervision, logs, safe mode | Low |
| One shell process for everything | One fault takes down all (CS2-005, CS2-024) | Separate lock, notification and settings services | Crash containment | Medium: IPC latency to verify |
| CLI scraping (`nmcli`, `bluetoothctl`) | Polling, fragile parsing, injection, argv secrets (CS2-002, CS2-014, CS2-016) | D-Bus services with agents | Live state, PIN pairing, VPN | Medium |
| `find` for Spotlight | Slow, shallow, names only (CS2-022) | localsearch + providers | Fast, deep, content search | Low |
| Live window capture for glass | Idle GPU cost (CS2-007) | Opt-in; capture on damage | Battery life | Low (looks change) |
| Literal radii, colours and durations | Drift (CS2-018, CS2-043) | Role tokens + lint baseline | Consistency | Low: needs screenshot review |
| Python helper copy-paste | Fixes don't propagate (CS2-020) | `citronos` Python package | One implementation | Low |
| Hand-made mail engine | Not a daily driver (CS2-015) | GOA + EDS (+ upgraded IMAP engine) | OAuth, sync, multiple accounts | Medium |
| HyprGlass binary pinned to an Arch Hyprland | Breaks on routine updates (CS2-009) | Lock-step packages built from source | Glass survives updates | Medium: CitronOS then owns the Hyprland version |
