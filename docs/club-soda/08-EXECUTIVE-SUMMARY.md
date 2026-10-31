# CitronOS 2 "Club Soda": Executive Summary

*Audit of commit `ae8cbf4` (CitronOS Sprite 3.5, the CitronOS shell after MacShell was
reverted), 2026-10-24. The details are in
[01 Inventory](01-SYSTEM-INVENTORY.md), [02 UI/UX](02-UI-UX-AUDIT.md),
[03 Backend](03-BACKEND-AUDIT.md), [04 Opportunities](04-FEATURE-OPPORTUNITIES.md),
[05 Architecture](05-ARCHITECTURE-PROPOSAL.md), [06 Roadmap](06-CLUB-SODA-ROADMAP.md) and
[07 Backlog](07-IMPLEMENTATION-BACKLOG.md).*

## Where CitronOS stands

CitronOS is unusually broad for its age:
- a complete Quickshell desktop: menu bar, Dock, Launchpad, Control Center, Spotlight,
  Mission Control, notifications, lock screen, widgets and tablet mode;
- 22 first-party apps;
- a 34-pane System Settings that mostly changes the real system;
- a graphical installer, a first-run assistant, a bootable ISO with a QEMU boot test, and
  135 test files.

The data-handling code is careful: atomic writes, refusing to overwrite damaged files, and
conflict detection, all of it tested. Its UI is honest: updates report each part's real
outcome, and Citron doesn't claim abilities it lacks.

What holds it back from being a mature OS isn't the number of features. It's **trust,
supervision and integration.** The ways it updates and elevates privilege aren't safe
yet. The desktop is one process that, when it fails, takes the lock screen and
notifications with it. Most system integration is done by scraping command-line tools
rather than talking to the services underneath. The test suite passes, but much of CI
checks that strings exist in files rather than that behaviour works.

**Test baseline:** of 135 test files, 125 passed and 10 failed only because of this
environment (no Darling source checkout, running as root, generated symbols not built).
There were no real failures. None of the three P0 problems below is caught by any test.

## The most serious problems (fix first)

| ID | Problem | Why it matters |
|---|---|---|
| **CS2-001** (P0) | Software Update's passwordless polkit rule also covers changing the update source and running the downloaded `install.sh` as root | Any program running as the user can become root silently |
| **CS2-002** (P0) | Control Center joins Wi-Fi by building a shell command around the network name | A nearby attacker can run code with a crafted SSID and one tap |
| **CS2-003** (P0) | Updates are unsigned snapshots of a *development branch*, executed as root | Every push reaches every installed machine; a compromised GitHub account compromises them all |
| CS2-004 (P1) | The startup-crash pattern (asynchronous theme icons) is back in Launchpad and Tablet Home | Intermittent desktop crashes at login (fix reverted with MacShell) |
| CS2-005 (P1) | The lock screen shares the shell's process, and lock restore isn't enabled | A crash while locked can leave the session impossible to unlock |
| CS2-006 (P1) | Services are supervised by `sh` loops, with no back-off, journal or isolation | Crash loops, and no diagnosis or safe mode |
| CS2-007 (P1) | Liquid Glass copies the windows behind the Dock and menu bar about 30 times a second by default | Probably the largest idle GPU and battery cost (not yet measured) |
| CS2-009/010/011 (P1) | Not packaged; the ISO isn't reproducible; the compositor plugin is pinned to one Hyprland version on a rolling distro | Updates and builds break with upstream timing, and systems drift |
| CS2-012 (P1) | The installer has no encryption, swap or zram, and can't install alongside another OS | Unsafe laptop default, and some users can't install |
| CS2-013 (P1) | Accessibility amounts to three toggles; there's no screen reader | Unusable for blind and low-vision users |

## Largest UI/UX inconsistencies

- **The design tokens exist but are mostly bypassed:**
  - 426 literal corner radii (16 uses of the radius tokens);
  - 1,586 hard-coded colours;
  - 198 literal animation durations across more than 40 distinct values (CS2-018).
- **The type scale collapses:** `Theme.fs()` raises every size below 12 px to 12, so
  494 call sites asking for 8–12 px render the same size. Large titles also ignore
  Text Size (CS2-043).
- **Fullscreen isn't really fullscreen:** the menu bar and Dock stay on top (CS2-008), and
  the Dock can't auto-hide or move (CS2-034).
- **Native in some places, a terminal in others:** Users & Groups changes your password by
  opening a terminal (CS2-027). Control Center sends you to Settings to type a Wi-Fi
  password (CS2-037).
- **Mismatch with apps from outside:** Flatpak apps very likely don't get the CitronOS
  theme (CS2-030).
- **The README shows the browser prototype, not the OS** (CS2-035).

## Major missing capabilities

- Signed, versioned releases.
- Disk encryption and snapshots.
- A screen reader and real accessibility.
- VPN and enterprise Wi-Fi.
- Bluetooth pairing with PINs.
- A firewall.
- Native user management and per-app permissions.
- OAuth mail accounts.
- Two-way calendar sync.
- Missing apps: Contacts, Preview (PDF), Activity Monitor.
- Backup.
- Indexed search.
- Clipboard history.

## Top opportunities

1. **A signed CitronOS package repository** fixes the three P0s at the root, and gives
   versioning, rollback and reproducibility.
2. **A small set of session services** (settings, notifications, network, Bluetooth,
   search) on D-Bus. This removes CLI scraping, fixes several defects at once, and gives
   every surface live state.
3. **Make the design system enforceable:** role tokens plus a lint with a shrinking
   baseline, plus a dozen missing shared components. Consistency then becomes the
   default.
4. **Citron as a permissioned OS assistant**, with several providers including local
   models. This is the clearest differentiator, once search and settings are services.

## Recommended technical direction

Keep **Hyprland + Quickshell/QML + Python helpers**, the token pipeline and the `apps/lib`
component store. Change four things:

1. Deliver everything as **signed pacman packages**, on stable and beta channels.
2. Run the session under **systemd user units**, with the lock screen and notifications
   outside the UI process.
3. Integrate through **D-Bus services that own their state**, not command-line scraping.
4. Use **Evolution Data Server and GNOME Online Accounts** for accounts, mail, calendar and
   contacts, instead of growing an in-house sync engine.

Scope down Darling/Mac Apps, LCode's toolchains and the browser prototype to optional
extras.

## Highest-priority work (M1: Trust and stability, about 3 weeks)

| Task | What it does |
|---|---|
| T-1.1 | Pass the SSID as an argument, never inside a shell string |
| T-1.2 | Give changing the update source its own polkit action, which always asks for a password |
| T-1.3 | Install only signed, tagged releases; `dev` becomes opt-in |
| T-1.4 | One `AppIcon` component that loads theme icons safely |
| T-1.5 | Run the lock screen as its own process, with lock restore |
| T-1.6 | systemd user units, crash limits and a safe mode |
| T-1.7 / T-1.8 | No Wi-Fi password in argv; AirDrop off by default, plus a firewall |
| T-1.9 / T-1.10 | Show preference-write failures; add security lints to CI |

All of these are small or medium tasks. Exit criteria are in
[06 M1](06-CLUB-SODA-ROADMAP.md).

## Vision for Club Soda

Club Soda should be the release where CitronOS becomes **something you can trust and
hand to someone else**:

- it installs encrypted;
- it updates from signed releases and can roll back;
- it survives its own crashes;
- it speaks to its hardware through proper services;
- anyone can use it, including with a screen reader;
- every surface looks and moves as though one team designed it.

The glass, the motion and the macOS-class apps are already there. Club Soda makes them
dependable.

---

## Scorecard

Scale: 0–10, where 10 means release-quality for a mainstream desktop OS. **U** means
unverified: it needs a GPU, a session or hardware this audit didn't have, and it gets no
score rather than a guess. "—" means the dimension doesn't apply.

| Subsystem | Complete­ness | Reliability | UI consist­ency | Interaction | Perfor­mance | Maintain­ability | Integration | Access­ibility | Release readiness | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|
| Desktop shell | 8 | 5 | 7 | U | U | 5 | 6 | 3 | 5 | CS2-004/005/006/007/025; strong Dock and notification tests |
| Window management | 7 | 6 | 7 | U | U | 6 | 7 | 3 | 5 | Tiling, snapping and Mission Control tested; CS2-008 |
| Design system | 8 | — | 5 | U | — | 5 | 8 | 4 | 6 | One token source, one component store; CS2-018/043 |
| System Settings | 7 | 7 | 8 | U | 7 | 6 | 6 | 4 | 6 | `settings-*` tests; gg-pref measured at 40 ms; CS2-014/016/027 |
| Core apps (Files, Web, Notes, Music, Calendar, Maps, Weather, Clock) | 7 | 8 | 7 | U | U | 5 | 7 | 3 | 7 | Data-safety tests throughout; monoliths CS2-019; CS2-042 |
| Mail and Messages | 3 | 6 | 7 | U | U | 6 | 3 | 3 | 3 | CS2-015; Messages needs a paired iPhone |
| App Store | 7 | 7 | 7 | U | U | 6 | 7 | 3 | 6 | Flatpak solid; CS2-031/032 |
| System integration (network, Bluetooth, audio, power) | 6 | 5 | 7 | U | 5 | 4 | 4 | 3 | 5 | PipeWire and UPower native; CLI scraping CS2-014/016/026 |
| Citron Intelligence | 5 | 7 | 8 | U | U | 6 | 2 | 3 | 6 | Keys handled well, honest prompt; CS2-028 |
| CitronPods and peripherals | 4 | U | 7 | U | U | 5 | 4 | 2 | 2 | CS2-029 |
| Installer and first run | 5 | 7 | 8 | U | — | 6 | 6 | 3 | 5 | `installer-*` safety tests; CS2-012 |
| Updates and release engineering | 6 | 6 | 7 | — | — | 3 | 3 | — | **2** | CS2-001/003/009/010/011 |
| Security | 4 | — | — | — | — | 4 | — | — | **2** | Three P0s; good secret handling elsewhere |
| Accessibility | 2 | — | — | — | — | — | 2 | **2** | 2 | CS2-013 |
| Tests and CI | 7 | 7 | — | — | — | 5 | — | — | 6 | 135 files, ISO and boot tests; grep guards CS2-033 |

**Overall: 5 out of 10.** It is feature-rich, careful with user data and visually
ambitious, but not yet safe to distribute widely. Fixing M1 alone would move updates and
security from 2 to about 6, and the shell's reliability from 5 to about 7. Those are the
largest gains available anywhere in the system for the effort.
