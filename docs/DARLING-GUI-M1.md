# Darling GUI compatibility: milestone 1

## Implemented

Golden Gate now carries a pinned, reproducible source patch series for Darling's
Cocotron AppKit implementation. It does not replace the installed `darling-bin`
package automatically.

The Golden Gate launcher also now passes the executable's Linux path to Darling.
Previously it passed `/Volumes/SystemRoot` plus that path, but Darling's host CLI
calls Linux `realpath()` and adds the prefix itself. The original argument failed
before the executable reached Darling's compatibility frameworks. The launcher
regression test now models that host-side file check.

| Patch | Before | After |
| --- | --- | --- |
| Controller loading | No `isViewLoaded`, `viewIfLoaded`, `loadViewIfNeeded` or `viewDidLoad` implementation | Non-loading state queries, lazy loading, initialization callback and reentrancy protection |
| Callback timing | Controller subclasses never receive `viewDidLoad` through the loading path | Programmatic loading notifies after `loadView` completes; nib loading notifies at outlet assignment |
| Failed loading | No explicit loading-state guard | Exceptions propagate and clear the guard, permitting retries |
| Controller ownership | Metadata and retained view/represented object were not released | Superclass initialization and owned-object cleanup |
| Layout sentinel | `0xbff0000000000000` was converted numerically to a huge positive CGFloat | Both correctly and historically misspelled symbols export numeric `-1.0` |

Apple documents the lazy view and callback contracts in
[NSViewController](https://developer.apple.com/documentation/appkit/nsviewcontroller),
[viewDidLoad](https://developer.apple.com/documentation/appkit/nsviewcontroller/viewdidload()),
and [intrinsicContentSize](https://developer.apple.com/documentation/appkit/nsview/intrinsiccontentsize).
These patches implement a focused subset; they do not implement view appearance,
controller containment, a constraint solver or SwiftUI.

## Validation and its limits

`tests/darling/controller.m` executes the **actual patched controller source and
header**, compiled as Objective-C against GNUstep Foundation. The host harness
substitutes NSResponder, an NSObject-backed view and synchronous nib loading; it
does not substitute the controller implementation. It covers lazy queries,
programmatic and nib callback timing, recursive reads, repeat access, clearing
and reloading, failed-load retries, partial failure, superclass decoding,
owned-object cleanup and both layout exports.

`tests/darling-patches.py` verifies the actual pinned source blobs in disposable
Git repositories: forward application, repeat application, same-file drift,
untracked files, wrong revisions, wrong hashes and partial series. It preserves
the supplied source checkout and refuses to overwrite local edits.

Both tests passed locally and in Linux CI; the Intel fixture also compiled and
passed architecture verification on macOS CI. This is host-level behavior and
binary-build evidence, **not evidence
that a third-party Mac GUI app runs successfully**.
The full patched Ubuntu runtime compiled, passed the stage audit, and installed
in [run 38114854748](https://github.com/MobiLaunch/GoldenApple/actions/runs/38114854748)
on October 11, 2026. ControllerLab created an X11 window, but the captured
surface was entirely black and the window disappeared during input. The test
failed before saving; the log included `semaphore_timedwait failed (internally):
-111`. That message alone does not identify the cause. Interactive GUI support
and execution of the installed PIP fixture remain unverified. CI separately builds an Intel Mach-O fixture on
macOS. Its build does not by itself prove Darling compatibility.

## Reproducible build

First target: x86_64 Linux, x86_64 Mac binaries, ordinary AppKit and the existing
X11 backend (XWayland for a Hyprland desktop). Metal is disabled explicitly for
this milestone to keep the baseline independent of GPU translation. Components
are `cli,gui_frameworks`, with i386 and Python 2 bytecode disabled. Upstream
Darling/Cocotron/objc4 revisions and patch hashes are in
`third_party/darling/source.lock.json`.

Use a development machine with sufficient free space; upstream documentation
estimates up to 5 GB for source and 16 GB for a build. The script needs Git LFS,
Clang, CMake and Ninja, plus the framework build dependencies. On Ubuntu 24.04:

```bash
sudo apt-get update
sudo apt-get install -y cmake ninja-build clang linux-libc-dev bison flex libfuse-dev libudev-dev \
  pkg-config libcap2-bin git git-lfs libcairo2-dev libgl1-mesa-dev \
  libglu1-mesa-dev libtiff5-dev libfreetype6-dev libxml2-dev libegl1-mesa-dev \
  libfontconfig1-dev libbsd-dev libxrandr-dev libxcursor-dev libgif-dev \
  libpulse-dev libavformat-dev libavcodec-dev libswresample-dev libdbus-1-dev \
  libxkbfile-dev libssl-dev llvm-dev libelf-dev libcurl4-openssl-dev libedit-dev

python3 tools/darling/build.py stage \
  --source "$HOME/Development/darling-gg-m1" \
  --build "$HOME/Development/darling-gg-m1-build" \
  --stage "$HOME/Development/darling-gg-m1-stage" --jobs 2
```

`prepare` fetches pinned source and applies patches; `configure` also runs CMake;
`build` additionally compiles; `stage` additionally writes installation output
into a separate directory via DESTDIR. Nothing installs over the system Darling.
Use an empty stage on each attempt; stale files are refused. Staging suppresses
upstream's host-session shutdown script and verifies the locked runtime and PIP
layout before accepting the result. `--install-prefix /usr` is available for
Arch packaging; the development default remains `/usr/local`.
The Objective-C baseline omits upstream's prebuilt Swift assets. Use
`--with-swift` to fetch and install them explicitly; an unavailable asset server
is a build failure. The selection is retained in runtime provenance. This
baseline does not establish support for Swift applications such as IINA.
Staged files are not a relocatable runtime: install paths and capabilities need
packaging before they can be offered through Golden Gate's normal updater.

Run the focused tests after preparing the source:

```bash
sudo apt-get install -y clang cmake make linux-libc-dev libgnustep-base-dev
python3 tests/darling-patches.py "$HOME/Development/darling-gg-m1"
CC=clang CXX=clang++ python3 tests/darling-build-modes.py "$HOME/Development/darling-gg-m1"
CC=clang python3 tests/darling-fsevents-build.py "$HOME/Development/darling-gg-m1"
CC=clang CXX=clang++ python3 tests/darling-dyld-link.py "$HOME/Development/darling-gg-m1"
bash tests/darling/run-host.sh "$HOME/Development/darling-gg-m1"
```

The linker regression additionally needs the pinned libunwind, dyld and
cctools-port submodules; `prepare` fetches them. It builds the pinned ld64 in a
temporary directory and checks a small Mach-O loader without executing it.

The `Darling GUI compatibility` workflow runs the focused tests and builds the
Intel GUI fixture. Source/tooling pushes also build and stage the complete
runtime in a disposable runner, then attempt the unchanged fixture under Xvfb.
Its manual `full_runtime` option performs the same build. Build logs and GUI
results are uploaded even on failure. `tools/darling/test-gui.py` checks a visible
window, real typed input and saved file contents, resizing and clean exit; it
refuses to use an existing prefix.

## GUI fixture

`tools/darling/fixtures/ControllerLab.m` is an ordinary Cocoa app using a
programmatic NSViewController. Its editor, status label and Save button are
created in `viewDidLoad`; the missing upstream callback leaves the window empty.
It tests windows, input, scrolling, resizing, target/action and UTF-8 saving.
The same binary must be used unchanged on macOS and Darling.

Build on a Mac with Xcode command-line tools (or download the CI fixture):

```bash
bash tools/darling/build-fixture.sh "$HOME/Desktop/ControllerLab.app"
```

On the x86_64 Linux desktop, after installing the patched runtime in a disposable
development environment, use a **separate Darling prefix** and preserve output:

```bash
export DPREFIX="$HOME/.local/share/golden-gate/darling-gui-m1"
mkdir -p "$HOME/.local/state/golden-gate"
darling "$HOME/Downloads/ControllerLab.app/Contents/MacOS/ControllerLab" \
  2>&1 | tee "$HOME/.local/state/golden-gate/darling-controller-lab.log"
```

| Manual check | Required evidence |
| --- | --- |
| Window opens | Editor, Save and status are visible |
| Input | Type accented text, select, copy and paste |
| Resize | Editor remains usable and scrolls |
| Save | Status shows success; prefix home contains `Darling-ControllerLab.txt` with the edited text |
| Close/reopen | Process exits, and a second launch is usable |

Record the source lock, runtime package, GPU, display backend, log, screenshots
and results. A surviving process alone does not prove a usable GUI.

## Next compatibility target

### IINA 1.5.0: observed loader blocker

A user launch reached dyld and failed to load
`/System/Library/PrivateFrameworks/PIP.framework/Versions/A/PIP` with
`image not found`, followed by `No shared cache present`. The missing framework
is the primary reported dependency; changing the launcher path or waiting for
the M1 AppKit patch build does not implement it. The pinned upstream Darling
source has no PIP framework target. The subsequent
[M2 patch](DARLING-ROADMAP.md) adds a limited implementation; its runtime validation
is tracked separately. IINA 1.5.0 explicitly links this framework in its
[Xcode project](https://github.com/iina/iina/blob/v1.5.0/iina.xcodeproj/project.pbxproj)
and declares its interface in its
[bridging header](https://github.com/iina/iina/blob/v1.5.0/iina/iina-Bridging-Header.h).
This is a recorded blocker, not a complete inventory of IINA's requirements.

The App Store now identifies missing-library and missing-symbol failures from
the full launch log, retains the raw log, and presents the primary dependency
above the trailing diagnostic output. Runtime installation is labelled
experimental. A surviving launch process or a clean early exit is recorded only
as an attempted launch; neither is evidence of a visible, usable application.
IINA remains unsupported by this milestone. PIP needs an implementation and
real app validation before compatibility can be claimed.

After a complete build and ControllerLab pass, inspect Darling's existing
open-source TextEdit target (`src/external/TextEdit`) and trace its first failures.
Implement the APIs needed for a real open/edit/save workflow, with regression
fixtures for each fix. Do not label TextEdit or any downloaded catalog app as
supported until the workflow has been tested. Modern Auto Layout, stack/grid
views, storyboards, Core Animation, SwiftUI and application-specific services
remain substantial follow-on work.

## Diagnosing runtime failures

The GUI harness waits for a nonuniform surface before sending input. This is a
readiness check, not proof that controls work: text entry, target/action, saving,
resizing and clean exit still must pass. Results retain the failing phase,
command stderr, the launcher exit before cleanup, screenshots and available
process/kernel/coredump diagnostics. CI selects Mesa software rendering for
Xvfb; this is an environment change whose effect needs runtime verification.

CI uploads the audited runtime before GUI tests and runs PIP independently of a
ControllerLab failure. It looks for a previous runtime artifact on the same
branch and reuses it only after the current source-lock audit passes; an
unavailable or mismatched candidate triggers a fresh build. You can also
dispatch with `runtime_run` set to a specific run ID; an explicitly selected
invalid artifact is rejected. The artifact must come from this repository.
Archive verification preserves the stored setuid mode with
`--no-same-owner --same-permissions`: ordinary unprivileged tar extraction
discarded that bit in run 38116480508 and prevented testing. The fixed archive
roundtrip passes the same audit, including the original saved CI artifact. Installation preserves the launcher mode with root ownership
in a disposable Ubuntu runner. This archive is not an Arch package or a desktop
update; use the source packaging workflow for Arch.

## Rendering stack overflow, October 11, 2026

The audited archive installed successfully in runs 38151150502 and 38151581057.
The latter [GUI diagnostic artifact](https://github.com/MobiLaunch/GoldenApple/actions/runs/38151581057)
contains ControllerLab's core dump. Linux recorded SIGSEGV, but Darling forwards
signals and re-sends a fatal signal to the process, so the ordinary core's
current thread can be waiting in a syscall rather than at the original fault.
The saved Linux signal context on the alternate stack identifies the original
instruction as `__sincos_stret+4` in `libsystem_m.dylib`. Its stack repeats the
return address `__sincos_stret+9` down to the stack guard page.

Patch 0008 adds four source-specific `-fno-builtin-*` options to
`src/libm/Source/sincos.c`. Clang's Darwin backend had combined the wrapper's
`sin(v), cos(v)` pair into a call to the wrapper itself. The float wrapper had
the same code generation problem. Other libm sources retain their optimizations.
`tests/darling-sincos.py` uses the pinned source, aggregate declarations and CMake
flags: the unpatched Darwin assembly reproduces both recursive calls; patched
Release, RelWithDebInfo and Debug assembly calls the scalar functions instead.
Each mode also passes 84 numeric checks on the host, including the pi wrappers,
signed zero, NaN and infinity. These are compiler and numeric checks; the full
Darling rendering/input/save test must still pass with the rebuilt runtime.

## Window levels and X11 shared memory, October 11, 2026

Run 38152714287 built and installed the math fix. ControllerLab stayed alive
with a uniform surface and no recorded coredump. Both fixtures reported
`MESA: error: Failed to attach to x11 shm`. CI now disables MIT-SHM on its
private Xvfb displays to exercise ordinary X11 image transport; rendering and
input remain unverified until the runtime test passes. This does not alter a
user's desktop display server.

PIPLab wrote its result: 21 checks, one failure, at the visible floating-window
assertion. The pinned Quartz header numbered window levels sequentially,
making `NSFloatingWindowLevel` equal to 1. A Mac-built binary embeds 3.
Patch 0009 supplies macOS values for the eight existing named levels and maps
their Quartz keys, replacing the function's always-normal result for those
keys. Other keys retain the existing fallback. A probe compiles the actual
pinned Quartz implementation and AppKit enum declarations: the baseline
reproduces the mismatch; the patch passes 16 checks. The same probe runs against
Apple's frameworks in macOS CI, so the values are checked independently.

The GUI harness saves its result before cleanup and tolerates an inability to
signal Darling's privileged launcher. A failure-path regression confirms that
the failing phase and false result survive cleanup permission errors. The
PIP fixture also prints the window's visibility and actual/expected level.
These changes improve diagnosis; they do not establish complete GUI support.

## Interactive GUI and PIP behavior evidence, October 11, 2026

Run 38155520170 passed ControllerLab's rendering, real text input, target/action,
UTF-8 save and resize checks. Its failure was at close/exit. The harness used
xdotool's `windowclose`, which destroys the X resource without delivering the
normal Cocoa close request. It now sends WM_DELETE_WINDOW directly with Python Xlib (the Ubuntu runner's
xdotool predates `windowquit`), retains
the zero-exit requirement and captures a live fixture backtrace on failure.
This test correction still needs confirmation in the runtime run.

PIPLab reported 21 checks, zero failures, visible=1 and floating level=3. Its
workflow step timed out despite that result. The PIP runner now logs to a
regular file instead of a tee pipeline, measures the launcher's own exit with a
30-second deadline, and retains behavior results separately from exit status.
A hang or nonzero exit still fails, with a process list and live fixture
backtrace before disposable-prefix shutdown. Regression tests ensure a passing
behavior JSON cannot mask either failure. These harness-only changes reuse the
source-locked runtime from that run; IINA remains unverified.

## Validated fixture workflows, October 11, 2026

[Run 38159189870](https://github.com/MobiLaunch/GoldenApple/actions/runs/38159189870)
passed all three jobs, including the full Darling runtime job. ControllerLab's
result contains visible-window, nonuniform rendering, text-input, target-action,
UTF-8 save, resize and clean-exit, with launcher exit 0. PIPLab's behavior result
contains 21 checks and zero failures; its runner independently records exit 0.
The X11 protocol test also passed, delivering WM_DELETE_WINDOW without destroying
the target window. The runtime was reused only after matching the current source
lock, including patches 0001–0009.

M1 and M2 are now validated for these fixtures in this disposable Ubuntu/Xvfb
environment with software rendering and MIT-SHM disabled. This is actual Mac
Mach-O GUI execution under Darling, not a host-only test. It does not validate
TextEdit, IINA playback, Swift, hardware acceleration, the user's Wayland desktop
or the Arch install/update workflow. The artifact remains an experimental Ubuntu
runtime, not an update installed through Golden Gate Settings.
