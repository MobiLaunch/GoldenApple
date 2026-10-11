# Golden Gate's Darling patch series

This directory carries changes to Darling itself, not GUI replacements in Qt.
The upstream repositories remain authoritative. `source.lock.json` pins Darling,
its Cocotron and objc4 submodules and SHA-256 hashes for every patch. Source trees and build
output stay outside the Golden Gate repository.

The Cocotron patches implement NSViewController loading and correct the intrinsic
size sentinel. Root patches add a limited PIP framework implementation and an
optional Swift asset profile. The objc4 patch aligns the runtime's debug macro
with CMake's standard build configurations. The FSEvents root patch exposes
Linux architecture headers privately to the Darwin guest daemon on multiarch
hosts, without adding host libc headers to its include path.
The loader-link patch disables relative switch-table generation only in static
libunwind C++ objects, which must work with the pinned ld64 chained-fixup writer.
The math wrapper patch prevents Clang from combining scalar sin/cos calls into
a recursive call to the Darwin sin/cos pair implementation during rendering.
See [the roadmap](../../docs/DARLING-ROADMAP.md) and
[`compatibility.json`](compatibility.json) for milestones, evidence gates and
per-app blockers; [M1](../../docs/DARLING-GUI-M1.md) records the initial baseline.

Licensing: `NSViewController.m` and its header originate in Darling's Cocotron
fork; retain their upstream licensing and notices. `NSLayoutConstraint.m` carries
the upstream GPL-3.0-or-later notice. These patches preserve those notices. The
full Darling distribution includes components with different licenses; packaging
must retain the source and notices for those components.
The PIP implementation is independently written GPL-3.0-or-later code based on
interfaces used by open-source IINA. It contains no Apple framework binaries or
implementation code.
