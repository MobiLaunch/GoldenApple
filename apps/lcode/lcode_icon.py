"""App icons designed in LCode's project editor, drawn the Golden Gate way:
a squircle with a gradient, a glyph (a Golden Gate symbol, a few letters or
an emoji, or an image), the Liquid Glass rim and sheen, and a dark variant
(graphite body, glyph in the icon's colour) like the system's own icons.

    icon = {"background": ["#5ea3e8", "#2f5f99"], "angle": 160,
            "glyph": {"kind": "symbol", "value": "sparkles", "color": "#ffffff"},
            "scale": 1.0, "gloss": True}
"""
from __future__ import annotations

import base64
import html
import math
import mimetypes
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
SYMBOLS = (HERE.parent / "lib" / "assets" / "symbols").resolve()


def squircle(size: float = 100, n: float = 5, steps: int = 160) -> str:
    r = size / 2
    pts = []
    for i in range(steps):
        a = i / steps * math.pi * 2
        c, s = math.cos(a), math.sin(a)
        pts.append((r + r * math.copysign(abs(c) ** (2 / n), c), r + r * math.copysign(abs(s) ** (2 / n), s)))
    return "M" + "L".join(f"{x:.2f} {y:.2f}" for x, y in pts) + "Z"


SQ = squircle()

# What a new project's icon looks like, per template.
TEMPLATE_GLYPHS = {"goldengate": "sparkles", "python": "python", "cargo": "rust", "meson": "c-language", "swift": "swift"}


def default_icon(toolchain: str, accent: str = "#0a84ff", kind: str = "app") -> dict:
    top = mix(accent, "#ffffff", 0.35)
    glyph = TEMPLATE_GLYPHS.get(toolchain, "appicon") if kind == "app" else ("terminal" if kind == "tool" else "layers")
    return {"background": [top, accent], "angle": 160, "glyph": {"kind": "symbol", "value": glyph, "color": "#ffffff"},
            "scale": 1.0, "gloss": True}


def hex_rgb(c: str) -> tuple[int, int, int]:
    c = c.lstrip("#")
    if len(c) == 8:
        c = c[2:]
    if len(c) == 3:
        c = "".join(ch * 2 for ch in c)
    try:
        return int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)
    except (ValueError, IndexError):
        return 10, 132, 255


def mix(a: str, b: str, t: float) -> str:
    ra, ga, ba = hex_rgb(a)
    rb, gb, bb = hex_rgb(b)
    return "#%02x%02x%02x" % (round(ra + (rb - ra) * t), round(ga + (gb - ga) * t), round(ba + (bb - ba) * t))


def safe_color(c, fallback: str) -> str:
    c = str(c or "")
    return c if re.fullmatch(r"#[0-9a-fA-F]{3}([0-9a-fA-F]{3})?([0-9a-fA-F]{2})?", c) else fallback


def symbol_body(name: str, color: str) -> str:
    """A symbol's drawing (24×24), recoloured."""
    path = SYMBOLS / f"{name}.svg"
    if not re.fullmatch(r"[a-z0-9-]+", name or "") or not path.is_file():
        path = SYMBOLS / "appicon.svg"
    text = path.read_text(encoding="utf-8")
    m = re.match(r"<svg([^>]*)>(.*)</svg>\s*$", text, re.S)
    attrs, body = (m.group(1), m.group(2)) if m else ("", text)
    stroke = re.search(r'stroke-width="([^"]+)"', attrs)
    wrap = (f'<g fill="none" stroke="{color}" stroke-width="{stroke.group(1) if stroke else 1.75}" '
            'stroke-linecap="round" stroke-linejoin="round">')
    return wrap + body.replace("#ffffff", color) + "</g>"


def image_href(path: pathlib.Path) -> str:
    kind = mimetypes.guess_type(str(path))[0] or "image/png"
    return f"data:{kind};base64," + base64.b64encode(path.read_bytes()).decode()


def render(icon: dict | None, dark: bool = False, root: pathlib.Path | None = None, uid: str = "lc") -> str:
    icon = icon or default_icon("")
    bg = icon.get("background") or ["#5ea3e8", "#0a84ff"]
    c1 = safe_color(bg[0], "#5ea3e8")
    c2 = safe_color(bg[1] if len(bg) > 1 else bg[0], c1)
    glyph = icon.get("glyph") or {}
    gcolor = safe_color(glyph.get("color"), "#ffffff")
    if dark:
        # Golden Gate's dark icons: a graphite body with the glyph in the icon's colour.
        gcolor = gcolor if glyph.get("kind") == "image" else (c2 if gcolor.lower() in ("#fff", "#ffffff") else gcolor)
        c1, c2 = "#3a3a3e", "#161618"
    angle = float(icon.get("angle", 160)) % 360
    rad = math.radians(angle - 90)
    x1, y1 = 0.5 - math.cos(rad) / 2, 0.5 - math.sin(rad) / 2
    x2, y2 = 0.5 + math.cos(rad) / 2, 0.5 + math.sin(rad) / 2
    scale = max(0.3, min(1.6, float(icon.get("scale", 1.0) or 1.0)))
    kind = glyph.get("kind", "symbol")
    value = str(glyph.get("value") or "")
    if kind == "text":
        size = 46 * scale / max(1, len(value) ** 0.6)
        art = (f'<text x="50" y="52" text-anchor="middle" dominant-baseline="central" font-size="{size:.1f}" '
               f'font-family="SF Pro Display, Inter, sans-serif" font-weight="700" fill="{gcolor}">{html.escape(value[:4])}</text>')
    elif kind == "image" and root is not None and (root / value).is_file():
        art = (f'<image href="{image_href(root / value)}" x="0" y="0" width="100" height="100" '
               f'preserveAspectRatio="xMidYMid slice"/>')
    else:
        s = 58 * scale
        art = f'<g transform="translate({50 - s / 2:.2f} {50 - s / 2:.2f}) scale({s / 24:.4f})">{symbol_body(value or "appicon", gcolor)}</g>'
    gloss = icon.get("gloss", True)
    sheen = (f'<linearGradient id="{uid}-sheen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".28"/>'
             f'<stop offset=".45" stop-color="#fff" stop-opacity="0"/></linearGradient>'
             f'<linearGradient id="{uid}-rim" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".75"/>'
             f'<stop offset=".5" stop-color="#fff" stop-opacity=".08"/><stop offset="1" stop-color="#fff" stop-opacity=".45"/></linearGradient>') if gloss else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
            f'<defs><clipPath id="{uid}-clip"><path d="{SQ}"/></clipPath>'
            f'<linearGradient id="{uid}-bg" x1="{x1:.3f}" y1="{y1:.3f}" x2="{x2:.3f}" y2="{y2:.3f}">'
            f'<stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient>{sheen}</defs>'
            f'<path d="{SQ}" fill="url(#{uid}-bg)"/>'
            f'<g clip-path="url(#{uid}-clip)">{art}'
            + (f'<path d="{SQ}" fill="url(#{uid}-sheen)"/>' if gloss else "") + "</g>"
            + (f'<path d="{SQ}" fill="none" stroke="url(#{uid}-rim)" stroke-width="1.2"/>' if gloss else "")
            + "</svg>")


def write(icon: dict | None, folder: pathlib.Path, name: str = "icon", root: pathlib.Path | None = None) -> tuple[pathlib.Path, pathlib.Path]:
    folder.mkdir(parents=True, exist_ok=True)
    light, dark = folder / f"{name}.svg", folder / f"{name}-dark.svg"
    light.write_text(render(icon, False, root), encoding="utf-8")
    dark.write_text(render(icon, True, root, uid="lcd"), encoding="utf-8")
    return light, dark
