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
that a full Darling runtime or a third-party Mac GUI app runs successfully**.
The complete runtime build and interactive GUI checks remain unverified at the
time this milestone was written. CI separately builds an Intel Mach-O fixture on
macOS. Its build does not by itself prove Darling compatibility.

## Reproducible build

First target: x86_64 Linux, x86_64 Mac binaries, ordinary AppKit and the existing
X11 backend (XWayland for a Hyprland desktop). Metal is disabled explicitly for
this milestone to keep the baseline independent of GPU translation. Components
are `cli,gui_frameworks`, with i386 and Python 2 bytecode disabled. Upstream
Darling/Cocotron revisions and patch hashes are in
`third_party/darling/source.lock.json`.

Use a development machine with sufficient free space; upstream documentation
estimates up to 5 GB for source and 16 GB for a build. The script needs Git LFS,
Clang, CMake and Ninja, plus the framework build dependencies. On Ubuntu 24.04:

```bash
sudo apt-get update
sudo apt-get install -y cmake ninja-build clang bison flex libfuse-dev libudev-dev \
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
Staged files are not a relocatable runtime: install paths and capabilities need
packaging before they can be offered through Golden Gate's normal updater.

Run the focused tests after preparing the source:

```bash
sudo apt-get install -y clang libgnustep-base-dev
python3 tests/darling-patches.py "$HOME/Development/darling-gg-m1"
bash tests/darling/run-host.sh "$HOME/Development/darling-gg-m1"
```

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

After a complete build and ControllerLab pass, inspect Darling's existing
open-source TextEdit target (`src/external/TextEdit`) and trace its first failures.
Implement the APIs needed for a real open/edit/save workflow, with regression
fixtures for each fix. Do not label TextEdit or any downloaded catalog app as
supported until the workflow has been tested. Modern Auto Layout, stack/grid
views, storyboards, Core Animation, SwiftUI and application-specific services
remain substantial follow-on work.
