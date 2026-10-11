# Golden Gate's Darling patch series

This directory carries changes to Darling itself, not GUI replacements in Qt.
The upstream repositories remain authoritative. `source.lock.json` pins Darling,
its Cocotron submodule and SHA-256 hashes for every patch. Source trees and build
output stay outside the Golden Gate repository.

The first patches implement NSViewController loading and correct the intrinsic
size sentinel. See [the milestone record](../../docs/DARLING-GUI-M1.md) for scope,
tests, build dependencies and remaining blockers.

Licensing: `NSViewController.m` and its header originate in Darling's Cocotron
fork; retain their upstream licensing and notices. `NSLayoutConstraint.m` carries
the upstream GPL-3.0-or-later notice. These patches preserve those notices. The
full Darling distribution includes components with different licenses; packaging
must retain the source and notices for those components.
