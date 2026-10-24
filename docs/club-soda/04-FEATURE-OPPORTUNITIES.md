# CitronOS 2 "Club Soda": Feature Opportunities

Missing capabilities, ranked by value. Everything here is new work. Defects in existing
features are covered in [02](02-UI-UX-AUDIT.md) and [03](03-BACKEND-AUDIT.md).

**Class:**
- **E**: essential for a complete OS
- **U**: a meaningful usability improvement
- **D**: a competitive differentiator
- **X**: experimental or future

**Size:** S (days) · M (1–3 weeks) · L (a month or more).

The ranking follows one rule from the brief: reliability and integration before feature
count. Most **E** items are back-end services that several surfaces then share.

## 1. Ranked catalogue

| # | Opportunity | Class | Size | Why | Implementation notes |
|---|---|---|---|---|---|
| 1 | **Signed CitronOS package repository and release channels** | E | L | Fixes CS2-001, CS2-003 and CS2-011 together. Gives versioned, verifiable, revertible updates | PKGBUILDs, CI repository build and signing, `citronos-keyring`, stable, beta and dev repositories ([05: Packages](05-ARCHITECTURE-PROPOSAL.md#packages-updates-and-releases)) |
| 2 | **Disk encryption, zram, snapshots and rollback** | E | L | Laptops need encryption. Updates need a way back | LUKS2 + `sd-encrypt`, `zram-generator`, btrfs `@`/`@home` + `snap-pac`, boot-menu rollback (CS2-012) |
| 3 | **Accessibility foundation** | E | L | The OS is currently unusable with a screen reader | Orca + AT-SPI, Zoom, Increase Contrast, pointer size, sticky, slow and mouse keys, a lint for annotations (CS2-013) |
| 4 | **Network service: VPN, 802.1X, inline Wi-Fi prompts, captive portal** | E | M | Common networks can't be joined today | `citronos-networkd` on NetworkManager D-Bus with a secret agent; WireGuard and OpenVPN import; portal detection through NM's connectivity check opening a Web sheet (CS2-016, CS2-037) |
| 5 | **Bluetooth service with a pairing agent** | E | M | Keyboards and PIN devices can't pair | `citronos-bluetoothd` + `org.bluez.Agent1` + shell sheet. Feeds CitronPods and Nearby (CS2-014) |
| 6 | **Firewall, with AirDrop gated by network trust** | E | S | Exposure on public networks | firewalld zones mapped to NM connections; AirDrop off by default, "Everyone for 10 minutes" (CS2-017) |
| 7 | **Users & Groups done natively** | E | M | Shared and family computers | accountsservice: add, delete, admin, picture, password sheet (CS2-027) |
| 8 | **Per-app permissions** | E | M | Privacy expectations from macOS and iOS | Flatpak permission store and overrides, portal permissions, App Store pre-install disclosure (CS2-031) |
| 9 | **Mail, Calendar and Contacts on one accounts back end** | E | L | Mail and Calendar can't be primary tools today, and Contacts is missing | GOA (OAuth for Google and Microsoft) + EDS; a Contacts app; Internet Accounts in Settings (CS2-015, CS2-042) |
| 10 | **Preview app (PDF and images)** | E | M | No PDF viewer ships | Poppler-Qt6 or PDF.js inside Web's engine. Annotate, sign, rotate and merge later |
| 11 | **Backup and restore** | E | M | No way to recover a lost home folder | "Time Machine": `restic` or `borg` to an external disk or SMB, hourly with retention, a restore browser in Files. Snapshots (#2) cover system rollback |
| 12 | **Indexed Spotlight with search providers** | U | M | Files beyond five folder levels, content and metadata, contacts, mail | localsearch / tinysparql + a provider API ([05: Search](05-ARCHITECTURE-PROPOSAL.md#search), CS2-022) |
| 13 | **Clipboard history** | U | S | Expected by power users and a common reason to install add-ons | `wl-paste --watch` into a capped, encrypted-at-rest store; ⇧⌘V picker; skips password-manager MIME hints (`x-kde-passwordManagerHint`) |
| 14 | **Dock auto-hide, position and fullscreen behaviour** | U | M | Screen space on laptops | CS2-008 and CS2-034 |
| 15 | **Notification persistence, inline replies, third-party badges** | U | M | Missed notifications; badges only for CitronOS apps | `citronos-notifyd` + `LauncherEntry` API (CS2-024) |
| 16 | **Activity Monitor** | U | M | Users need to find and stop the process that's draining the battery | `/proc` + cgroups (per-app scopes) + `powertop`-style energy estimates; Force Quit integration |
| 17 | **Per-app systemd scopes** | U | S | Precondition for #16, for out-of-memory protection and for clean quits | Launch apps with `systemd-run --user --scope --unit=app-citronos-<id>-<n>` (or `app2unit`) instead of `DesktopEntry.execute()` |
| 18 | **Network locations in Files (SMB, SFTP, WebDAV)** | U | M | Home and office file shares | gvfs backends + "Connect to Server…" (⌘K), sidebar entries, credentials in the keyring |
| 19 | **Default-app and file-association UI in Files** | U | S | "Open With → Always" | Default Apps pane exists; add Get Info → "Open with" + "Change All…" writing `mimeapps.list` |
| 20 | **Unified keyboard-shortcut editor** | U | M | Shortcuts are spread across `hyprland.conf`, keyd and apps | Settings → Keyboard → Shortcuts writing a generated `shortcuts.conf` sourced by Hyprland; conflict detection |
| 21 | **Hot-plug and multi-display polish** | U | M | Docking stations, projectors | Arrangement UI, per-display Dock and menu bar choices, window restore after re-plug |
| 22 | **Widgets: interactive and configurable, with a widget SDK** | D | M | Desktop widgets exist; third parties can't add any | A QML widget package format (`metadata.json` + `Widget.qml`), sandboxed data through a provider service |
| 23 | **Citron as an OS assistant (with permissions)** | D | L | The current Citron chats but can't act | Provider interface + permissioned tools + confirmations ([05: Citron](05-ARCHITECTURE-PROPOSAL.md#citron-intelligence), CS2-028) |
| 24 | **Notification and document summaries** | D | M | Depends on #23 | Local-first where a local model is configured; always opt-in per app |
| 25 | **Shortcuts / automation** | D | L | A macOS-class differentiator on Linux | A small action graph (triggers: time, Focus, Wi-Fi, hot-key, AirDrop receive; actions: the same tools Citron uses), editor in its own app |
| 26 | **Peripheral framework beyond AirPods** | D | M | Battery and pairing cards for headsets, controllers, keyboards and mice | BlueZ Battery1, UPower devices, `hid-*` drivers; CitronPods becomes one provider (CS2-029) |
| 27 | **Handoff-style continuity with phones** | D | L | Messages and AirDrop already reach phones | KDE Connect protocol (Android) for clipboard, notifications and "Open on…"; iPhone through the existing BlueFerry path where possible |
| 28 | **Pen and touch polish** | U | M | Tablet mode exists | Pressure in Notes (Qt `QPointingDevice`), palm rejection, on-screen keyboard tuning (`squeekboard` ships) |
| 29 | **Keyboard backlight control** | U | S | Laptops | `brightnessctl --device='*::kbd_backlight'` through logind, with a Control Center tile and auto-dim |
| 30 | **Battery health and charge limit** | U | S | Longevity | `charge_control_end_threshold` (where the kernel exposes it), shown in the Battery pane, which already shows health |
| 31 | **Developer integration API** | X | L | Third-party apps that feel native | A documented QML module (`apps/lib`) + D-Bus services (Settings, Notifications, Search provider, Share sheet), shipped as `citronos-sdk`. LCode templates use it |
| 32 | **Android apps** | X | L | Big catalogue | Waydroid as an optional App Store source. Heavy (binder modules, ~2 GB image), so experimental only |
| 33 | **Local AI models** | X | M | Privacy and offline use | Ollama provider (#23), with model download in Settings, CPU and GPU checks, clear disk and RAM costs |

## 2. Recommended order

1. **Before any new features:** #1, #6 and the P0 fixes from [06](06-CLUB-SODA-ROADMAP.md).
   Without them, every other feature ships over an unsafe update channel.
2. **Platform services** (#4, #5, #7, #8, #15, #17). Each removes CLI scraping, fixes an
   audited defect and unlocks several later items.
3. **Daily-use completeness** (#2, #3, #9, #10, #11, #12, #13, #14).
4. **Differentiators** (#22–#27) only once 1–3 are in place.

## 3. Features to not add, or to scope down

| Item | Recommendation | Reason |
|---|---|---|
| **Mac Apps through Darling** in the App Store's main sections | Move to "Experimental", off Discover; later an optional `citronos-darling` package | Darling's GUI support is experimental (README). Unverified cask checksums and no sandbox (CS2-032). Large CI and maintenance cost (three `darling-*.yml` workflows, 14 `tests/darling-*.py` files plus `tests/darling/`, `third_party/darling`) |
| **LCode in the base image** | Keep the app, but install its toolchains on demand (`citronos-developer`) | It pulls compilers and Node into every install (CS2-039) |
| **The browser prototype** as a spec | Freeze it as a design sketchpad | A duplicate implementation (CS2-036) |
| **More glass effects** (window refraction on permanent surfaces) | Don't extend. Make it opt-in instead | Likely the largest idle GPU cost (CS2-007). The brief puts performance above visual sophistication |
| **A second browser engine or front end** | Don't | README already commits to one Web on Qt WebEngine |
| **An in-house email engine** | Don't grow `mail/helper.py` into one | EDS and GOA already solve OAuth, IDLE and caching (CS2-015) |
| **Android integration in the base image** | Optional only | Kernel modules and a 2 GB image don't fit the base OS |
| **Unrestricted AI actions** | Never | Every Citron tool must declare scopes and require confirmation for writes (brief §7) |
| **A Hyprland Lua config migration** (task #95 in the old plan) | Defer | It doesn't change anything users see and adds risk while HyprGlass pins Hyprland (CS2-009) |
