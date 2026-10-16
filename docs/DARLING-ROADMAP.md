# Darling compatibility development

This project expands Darling's own macOS API implementations. Work is pinned,
tested in small increments and kept separate from the installed `darling-bin`
until the runtime is validated and packaged for Arch.

M1 and M2 are validated for ControllerLab and PIPLab in the
[October 11 runtime run](https://github.com/MobiLaunch/GoldenApple/actions/runs/38159189870):
real rendering, input/save, resize and clean exit; 21 PIP checks and clean exit.
The test environment uses Ubuntu/Xvfb software rendering with MIT-SHM disabled.
TextEdit, IINA and the Arch deployment workflow still require their own evidence.

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
| `third_party/darling/patches/` | Cocotron, objc4 and Darling root changes; no bundled Apple framework binaries |
| `third_party/darling/compatibility.json` | Milestones, dependencies, evidence and per-app blockers |
| `tools/darling/build.py` | Prepare, configure, build and stage; never replace the host runtime |
| `tests/darling/` | Behavior tests exercising actual implementation source |
| `tools/darling/build-pip-tests.sh` | Compile the PIP patch against macOS AppKit and build the Intel fixture |
| `.github/workflows/darling-pip.yml` | Fast native framework validation independent of the lengthy full build |
| `.github/workflows/darling-gui.yml` | Source protection, native fixtures, full build and Darling runtime tests |

Root, Cocotron and objc4 patches are checked before any repository is changed.
Each repository must be pristine or match its complete expected patch series,
including newly added files. Local edits are refused and preserved. An apply
failure rolls back completed groups. A machine interruption is not a
cross-repository transaction; rerun preparation to preflight each group. Existing
M1 checkouts can gain the root PIP patch without resetting Cocotron.
When the root patch series changes, an existing partly patched root checkout is
refused; use a fresh dedicated source directory rather than reset local work.

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

The initial native suite passed all **21 behavior checks**, and the Intel fixture
compiled with the required framework install name. The verified
[CI result](https://github.com/MobiLaunch/GoldenApple/actions/runs/38099631559/job/114352693782)
includes playback snapshots, view reparenting/restoration, play/pause delegation,
reentrant close handling, weak ownership and teardown. Native AppKit already
delivers disappearance callbacks; the implementation supplies an explicit
fallback only when the base controller lacks that hook, avoiding duplicate
native delivery. Full Darling execution remains pending in the evidence record.

Build and run on macOS:

```bash
bash tools/darling/build-pip-tests.sh "$HOME/Development/pip-tests"
```

Use the M1 build instructions for the full Linux runtime. Runtime testing belongs
in a disposable development environment with a fresh `DPREFIX`. The default
Golden Gate updater still does not install this patched runtime.

## Arch package development

The source package recipe is now implemented; installation, upgrade, rollback
and GUI compatibility remain unvalidated. M5 cannot pass before M1 and M2.
`tools/darling/package-arch.py` exports a standalone build context containing the
locked patches, build tool and runtime auditor, with a deterministic source
archive and SHA-256 checksum. It never repackages Ubuntu build output as an Arch
binary. Arch compiles its own host executables and libraries against its own
dependencies.

The package is named `golden-gate-darling-experimental`, provides `darling`, and
declares conflicts with `darling`, `darling-bin` and `darling-git`. It installs
under `/usr`, preserving the upstream launcher's setuid mode and the guest root
filesystem layout. It retains provenance in
`/usr/share/golden-gate/darling/build.json`. It does not touch existing user
prefixes or run applications during packaging. No Settings integration or
automatic replacement has been enabled.

Each new stage must be empty. `build.py` enables upstream's `DEBIAN_PACKAGING`
flag solely to suppress its install-time host-session shutdown script; the
components are still explicitly `cli,gui_frameworks`. Before accepting output,
`runtime.py` checks the source lock, install prefix, host ELF architecture,
launcher mode, PIP's x86_64 Mach-O dylib identity and framework links. These are
structural checks, not proof that a GUI application works.

Export a source recipe from the Golden Gate checkout:

```bash
python3 tools/darling/package-arch.py "$HOME/Development/gg-darling-arch"
```

The `Darling Arch packaging` workflow validates that recipe with Arch's
`makepkg --printsrcinfo` and uploads the source build context. Its manual
`build_runtime` option additionally compiles an experimental Arch package as an
ordinary user in a disposable container; it does not install or publish it.
The package dependencies and full Arch compilation still need build evidence.
The first [Arch recipe CI run](https://github.com/MobiLaunch/GoldenApple/actions/runs/38105408413/job/114369764248)
passed all 14 source/staging/package checks and `makepkg --printsrcinfo` on Arch.
The full package build was deliberately skipped in this metadata run; this
result does not establish install, upgrade, rollback or GUI support.
Do not replace the desktop runtime with this development output until the GUI,
package installation and rollback gates pass.

### Source download profiles

The first full-runtime CI attempt failed **before compilation**, downloading
prebuilt Swift assets from `git-lfs.darlinghq.org`; its connection retries lasted
almost two hours. Source acquisition now checks out LFS pointers without
smudging, then explicitly materializes required assets with bounded connection
and transfer timeouts. Acquisition has its own CI step and log.

The default AppKit/PIP baseline excludes the Swift submodule. Patch
`0004-optional-swift-runtime.patch` makes upstream's previously unconditional
Swift installation optional, keeping its upstream default enabled. Golden
Gate's builder explicitly disables it for the baseline; it does not install LFS
pointer files as pretend libraries. `--with-swift` fetches and enables upstream's
prebuilt Swift assets, and fails if they cannot be downloaded. The selection is
recorded as `swift_runtime` in package provenance.

This baseline is sufficient to attempt the Objective-C fixtures, not IINA's
Swift requirements. The Swift assets and real IINA workflow remain blocked;
the default experimental Arch recipe uses the same baseline. No existing
Darling installation is altered by this source-download change.

### Objective-C runtime build configurations

After the download fix, [the baseline build](https://github.com/MobiLaunch/GoldenApple/actions/runs/38105520143/job/114370175926)
reached compilation and failed in `objc-runtime.mm` with `mismatch in debug-ness
macros`. The pinned objc4 CMake file unconditionally defined
`OBJC_IS_DEBUG_BUILD=1`, while `RelWithDebInfo` supplied `NDEBUG` and the runtime
header set `DEBUG=0`. Patch `0005-objc-build-mode.patch` selects zero for CMake's
Release, RelWithDebInfo and MinSizeRel modes, and one for Debug or an unspecified
mode. The objc4 revision and patch hash are locked alongside the other sources.

`tests/darling-build-modes.py` uses the actual pinned runtime CMake file, config
header and consistency guard. It reproduces the original RelWithDebInfo failure,
then compiles C and C++ probes in all five patched configurations. Only the
target/link graph is replaced by static probes; this is a configuration check,
not a complete runtime build or GUI compatibility result. The full build still
has to pass before the unchanged Intel fixtures can run.

### Filesystem-events guest headers

The [next runtime attempt](https://github.com/MobiLaunch/GoldenApple/actions/runs/38108726501/job/114379715729)
passed objc4 and reached step 15,512 of 16,561 before `fseventsd.m` failed to find
`asm/types.h`. The guest daemon consumes Linux fanotify UAPI definitions, but
Clang's Darwin target omits Ubuntu's native multiarch include directory.
Patch `0006-fsevents-linux-uapi.patch` finds the Linux architecture headers and
exposes only their `asm` subtree through a private build-directory symlink for
that target. Host libc include directories are not added to the guest SDK.
Missing userspace kernel headers now fail during configuration with the required
package names: `linux-libc-dev` on Debian/Ubuntu and `linux-api-headers` on Arch.

`tests/darling-fsevents-build.py` reproduces the original compiler failure using
the pinned fanotify header and FSEvents CMake file, then compiles a Darwin-target
probe with both multiarch and flat header layouts. Ten structure size, alignment
and offset checks compare against the native Linux ABI. It also verifies repeat
configuration and missing-header rejection. This focused check does not execute
the daemon or validate filesystem-event delivery under Darling.

### Dynamic-loader static unwind codegen

The [following runtime build](https://github.com/MobiLaunch/GoldenApple/actions/runs/38111862708/job/114389016455)
passed filesystem-events compilation, then failed at step 15,906 of 16,561 while
linking `dyld`. Clang 18 lowered libunwind's x86_64 register-name switch into a
relative pointer table. The pinned ld64 cannot encode its 32-bit relative fixups
in a loader using chained fixups and reports `chained binds not implemented yet`.
Patch `0007-dyld-static-unwind-tables.patch` applies `-fno-jump-tables` only to the
static unwind target's C++ objects. Shared libunwind, other libraries, loader
chained fixups and release optimization remain unchanged. Static unwind's switch
dispatch may be less compact; no runtime performance result is claimed.

`tests/darling-dyld-link.py` builds the pinned ld64 and compiles the actual pinned
register-name function with the libunwind CMake flags and root target override.
The original probe must reproduce the linker failure; the patched probe must
link as an x86_64 Mach-O loader retaining its chained-fixup load command. The
test also verifies that another target keeps ordinary table generation and that
193 native register-name results agree before and after the compiler workaround.
This is a focused codegen/link test, not a full dyld build or execution result.

## M3 TextEdit workflow

The pinned Darling tree carries Apple's open-source TextEdit sample at
`src/external/TextEdit`, but upstream has its CMake target disabled and installs
no app bundle. `tools/darling/build-textedit.sh` builds that exact source
revision (the submodule commit recorded by the locked Darling commit, so the
runtime source lock is unchanged) as an unchanged x86_64 Mac app with Apple's
SDK. Its nibs are already compiled in the source; no Interface Builder step is
needed. The macOS job also launches it natively once as a sanity check.

`tools/darling/test-textedit.py` runs two Darling sessions on the same plain
text file outside the prefix, passed as `-NSOpen`: open, type a unique marker,
Command-S, Command-Q with exit 0, then reopen and repeat. Each saved file must
equal the previous contents with exactly that session's marker inserted, so a
lost, truncated or replaced document fails wherever the caret lands; the
second save proves the reopened document loaded the first save.
`tests/darling-textedit-harness.py` checks that logic with simulated X11 and
processes.

The first full-runtime run showed TextEdit idle in its run loop with no window:
the `xtrace` rerun (`test-textedit.py --xtrace`, run automatically after a
failure) showed launch completing normally. TextEdit declares its documents
only as UTIs (`LSItemContentTypes`), and its default type is `public.text`.
Pinned Cocotron matched `CFBundleTypeName` only, so neither the `-NSOpen` file
nor an untitled document found a document class. The workspace UTI methods
TextEdit calls were unimplemented, and Darling declares no core UTIs because it
has no CoreTypes.bundle:

| Patch | Repository | Change | Host test |
| --- | --- | --- | --- |
| `0010-core-uti-fallback` | darling | Built-in core UTI table (identifiers, parents, extensions); reflexive, transitive `UTTypeConformsTo` | `tests/darling-core-utis.py` |
| `0011-uti-document-types` | cocotron | Document types match names or UTIs, by conformance; file UTIs come from LaunchServices; `NSDocument` readable/writable types list UTIs; `MacWorkspace` UTI methods | `tests/darling/document-types.m` via `run-host.sh` |
| `0012-plain-text-documents` | cocotron | `NSAttributedString` reads plain text (BOM, UTF-8, then Latin fallbacks) and writes it losslessly; `NSTextContainer` reports horizontal layout | `tests/darling/plain-text.m` via `run-host.sh` |
| `0013-paragraph-tab-stops` | cocotron | Copied and decoded paragraph styles own mutable tab stops; `-[NSMutableParagraphStyle copy]` returns an immutable copy, not itself | `tests/darling/paragraph-style.m` via `run-host.sh` |

With 0010 and 0011 the next run opened the file (`open(GoldenGateNote.txt)` in the trace) and then showed
an alert: Cocotron had no plain-text reader or writer, and `NSDocument` listed its readable types by
name, so TextEdit's `readableTypeForType:` matched nothing. When no document window appears, the
harness now OCRs each visible window into the job log.

With 0012 TextEdit read the file and then aborted with "attempting to mutate an immutable object":
for plain text it copies the default paragraph style and clears its tab stops, and Cocotron's copy
kept an immutable tab-stop array.

The CI step is non-blocking while M3 is in progress, so a TextEdit failure is
recorded without hiding M1/M2 regressions. The first documents are ASCII plain
text; rich text, UTF-8 encoding detection and the Save panel for untitled
documents are follow-on checks, not covered by this gate.

## Recording a compatibility failure

Record the app version and executable architecture, source lock/runtime package,
display backend and the complete loader or framework log. Preserve the first
primary failure, rather than only trailing messages. Implement that dependency,
add a focused source/fixture regression, then rerun the unchanged application.
Attach CI or manual evidence before changing a milestone or support label.

The observed IINA 1.5.0 failure is the missing PIP framework. Keep that blocker in
the record until a test with an installed patched runtime gets past it. Later
failures become additional recorded requirements rather than guessed support.
