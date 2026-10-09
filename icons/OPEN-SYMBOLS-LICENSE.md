# OrchardKit/Open Symbols — Lucide artwork

Source: https://github.com/OrchardKit/open-symbols/tree/main/lucide

This distribution uses the **Regular-S** Lucide contours from OrchardKit's
SF Symbols template conversions. The templates contain multiple weights and an
artboard intended for Xcode. Only the normalized plain SVG contours are included
in `icons/orchard-symbols.mjs`, then generated into shell, Qt and GTK assets.

Lucide and its derived OrchardKit set are licensed under the ISC License.

> Copyright (c) Lucide Contributors
>
> Permission to use, copy, modify, and/or distribute this software for any
> purpose with or without fee is hereby granted, provided that the above
> copyright notice and this permission notice appear in all copies.
>
> THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
> WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
> MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
> ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
> WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
> ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
> OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

The Golden Gate project does **not** redistribute Apple's SF Symbols fonts
or proprietary SF Pro/SF Mono fonts. For the typography pipeline, SFWindows
(https://github.com/bradleyhodges/SFWindows) can be used as a source of
locally installed fonts only if the user's intended use complies with Apple's
font license. No network downloads or font binaries are included in installer
scripts. Use `scripts/install-local-sfwindows.sh PATH_TO_SFWINDOWS` to add
your own lawful local copy. In its absence, Inter Variable and JetBrains Mono
remain the default redistributable fallbacks.

The shell's icons use the same SVG mapping as the prototype and toolkit icons;
individual `icons/custom/symbols/*.svg` always override the defaults.
