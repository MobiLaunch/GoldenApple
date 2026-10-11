# Darling compatibility development

This project expands Darling's own macOS API implementations. Work is pinned,
tested in small increments and kept separate from the installed `darling-bin`
until the runtime is validated and packaged for Arch.

## Milestones

| Milestone | Outcome | Completion gate |
| --- | --- | --- |
| M1: AppKit baseline | Unchanged Intel ControllerLab edits and saves | Visible window, typed input, saved content, resize and clean close under Darling |
| M2: PIP framework | Framework loads and manages a supplied view in a floating window | Native behavior tests, then the same Intel fixture using Darling's installed PIP |
| M3: TextEdit | A real document workflow | Open, edit, save, close and reopen without data loss |
| M4: IINA | Actual media playback and PIP | Unchanged official app plays audio/video, enters/exits PIP and closes cleanly |
| M5: Packaging | Installable Golden Gate runtime | Arch install, Settings upgrade, provenance and rollback tested |

M2 source work can proceed while M1 builds, but M2 cannot be called validated
before its prerequisite and runtime checks pass. TextEdit is the document target;
IINA is the media target. Installing the runtime or observing a surviving process
does not establish app compatibility.

The authoritative progress and blocker record is
[`compatibility.json`](../third_party/darling/compatibility.json). Inspect it with:

```bash
python3 tools/darling/compatibility.py list
python3 tools/darling/compatibility.py target iina
python3 tools/darling/compatibility.py list --json
python3 tools/darling/compatibility.py check
```

The validator rejects supported-app labels without a validated workflow,
milestones with unfinished checks, results without evidence, unknown
dependencies and cycles. Status is a checked-in evidence snapshot. CI does not
silently edit it or publish a runtime when a build finishes; update evidence
after reviewing the actual results.

## Work structure

| Location | Responsibility |
| --- | --- |
| `third_party/darling/source.lock.json` | Exact source revisions, patch repositories and SHA-256 checksums |
| `third_party/darling/patches/` | Cocotron and Darling root changes; no bundled Apple framework binaries |
| `third_party/darling/compatibility.json` | Milestones, dependencies, evidence and per-app blockers |
| `tools/darling/build.py` | Prepare, configure, build and stage; never replace the host runtime |
| `tests/darling/` | Behavior tests exercising actual implementation source |
| `tools/darling/build-pip-tests.sh` | Compile the PIP patch against macOS AppKit and build the Intel fixture |
| `.github/workflows/darling-pip.yml` | Fast native framework validation independent of the lengthy full build |
| `.github/workflows/darling-gui.yml` | Source protection, native fixtures, full build and Darling runtime tests |

Root and Cocotron patches are checked before either repository is changed.
Each repository must be pristine or match its complete expected patch series,
including newly added files. Local edits are refused and preserved. An apply
failure rolls back completed groups. A machine interruption is not a
cross-repository transaction; rerun preparation to preflight each group. Existing
M1 checkouts can gain the root PIP patch without resetting Cocotron.

## M2 implementation scope

`0003-pip-framework.patch` adds an independent implementation at the private
framework install name IINA expects. Its interface follows the selectors visible
in IINA 1.5.0's
[bridging header](https://github.com/iina/iina/blob/v1.5.0/iina/iina-Bridging-Header.h)
and
[window controller](https://github.com/iina/iina/blob/v1.5.0/iina/MainWindowController.swift).
It uses ARC with zeroing weak delegate and replacement-window references.

Implemented source behavior:

- Copyable playback snapshots, transactional updates and play/pause intent
  callbacks. Failed updates leave the prior state intact.
- A resizable floating panel that reparents the app's existing view; it does not
  decode video or manufacture a substitute player.
- Matching-controller dismissal, restoration of the original parent, frame and
  autoresizing settings, and a replacement-window fallback if the parent is gone.
- Close notifications independent of the window delegate slot; a subclass can
  install its own delegate. Reentrant dismissal delivers close callbacks once.
- PIP-local layout and disappearance hooks that an app subclass can override.

Not implemented: Apple's PIP animations, screen-edge snapping, transport skip
and stop controls, aspect-ratio enforcement during arbitrary manual resizing,
full NSViewController containment/lifecycle semantics, or media/GPU decoding.
Reparenting restores the view as the parent's last subview; original z-order
restoration is also deferred. Resolving this dependency does not mean IINA's
remaining frameworks or Swift requirements work.

`tests/darling/pip.m` tests the actual PIP library on native AppKit. The build
script extracts only the framework additions from the locked patch and creates
an Intel fixture linked to
`/System/Library/PrivateFrameworks/PIP.framework/Versions/A/PIP`. Native tests
override framework lookup to use the built implementation. The Darling job uses
the same Intel fixture without that override, so it must load the framework from
the installed patched runtime. Native tests do not prove Darling GUI support.

Build and run on macOS:

```bash
bash tools/darling/build-pip-tests.sh "$HOME/Development/pip-tests"
```

Use the M1 build instructions for the full Linux runtime. Runtime testing belongs
in a disposable development environment with a fresh `DPREFIX`. The default
Golden Gate updater still does not install this patched runtime.

## Recording a compatibility failure

Record the app version and executable architecture, source lock/runtime package,
display backend and the complete loader or framework log. Preserve the first
primary failure, rather than only trailing messages. Implement that dependency,
add a focused source/fixture regression, then rerun the unchanged application.
Attach CI or manual evidence before changing a milestone or support label.

The observed IINA 1.5.0 failure is the missing PIP framework. Keep that blocker in
the record until a test with an installed patched runtime gets past it. Later
failures become additional recorded requirements rather than guessed support.
