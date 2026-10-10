#!/usr/bin/env python3
"""LCode Simulator display agent.

The Simulator runs apps on a private, headless X server (Xvfb). This agent is
the only process that talks to that server: it streams the app's pixels to
image files for the device window, acts as a minimal window manager (every
top-level window fills the device's app area, the way a phone shows apps
full screen) and injects touches and keys with XTEST.

It runs as its own process because Xlib ends the process when its server
goes away; a Simulator shutdown must never take the LCode helper with it.

    lcode_sim.py agent :91 FRAME_DIR WIDTH HEIGHT

stdin, one JSON object per line:
    {"t": "region", "w": 393, "h": 764}     app area after a rotation
    {"t": "motion", "x": 10, "y": 20}
    {"t": "button", "b": 1, "down": true}
    {"t": "key", "code": 38, "down": true}  X keycode (evdev + 8)
stdout, one JSON object per line:
    {"frame": "/run/.../frame-1.bmp", "seq": 7, "w": 393, "h": 764,
     "window": true, "top": [r, g, b], "bottom": [r, g, b]}
"""
from __future__ import annotations

import ctypes
import ctypes.util
import json
import os
import select
import struct
import sys
import time

FRAME_INTERVAL = 1 / 30
MANAGE_EVERY = 5          # frames between window-management passes
ZPIXMAP = 2
ALL_PLANES = 0xFFFFFFFF
POINTER_ROOT = 1
VIEWABLE = 2


class _ImageFuncs(ctypes.Structure):
    _fields_ = [(name, ctypes.c_void_p) for name in
                ("create_image", "destroy_image", "get_pixel", "put_pixel", "sub_image", "add_pixel")]


class XImage(ctypes.Structure):
    _fields_ = [
        ("width", ctypes.c_int), ("height", ctypes.c_int), ("xoffset", ctypes.c_int), ("format", ctypes.c_int),
        ("data", ctypes.c_void_p), ("byte_order", ctypes.c_int), ("bitmap_unit", ctypes.c_int),
        ("bitmap_bit_order", ctypes.c_int), ("bitmap_pad", ctypes.c_int), ("depth", ctypes.c_int),
        ("bytes_per_line", ctypes.c_int), ("bits_per_pixel", ctypes.c_int),
        ("red_mask", ctypes.c_ulong), ("green_mask", ctypes.c_ulong), ("blue_mask", ctypes.c_ulong),
        ("obdata", ctypes.c_void_p), ("f", _ImageFuncs),
    ]


class XWindowAttributes(ctypes.Structure):
    _fields_ = [
        ("x", ctypes.c_int), ("y", ctypes.c_int), ("width", ctypes.c_int), ("height", ctypes.c_int),
        ("border_width", ctypes.c_int), ("depth", ctypes.c_int), ("visual", ctypes.c_void_p),
        ("root", ctypes.c_ulong), ("class_", ctypes.c_int), ("bit_gravity", ctypes.c_int),
        ("win_gravity", ctypes.c_int), ("backing_store", ctypes.c_int), ("backing_planes", ctypes.c_ulong),
        ("backing_pixel", ctypes.c_ulong), ("save_under", ctypes.c_int), ("colormap", ctypes.c_ulong),
        ("map_installed", ctypes.c_int), ("map_state", ctypes.c_int), ("all_event_masks", ctypes.c_long),
        ("your_event_mask", ctypes.c_long), ("do_not_propagate_mask", ctypes.c_long),
        ("override_redirect", ctypes.c_int), ("screen", ctypes.c_void_p),
    ]


def _load(name: str, fallback: str) -> ctypes.CDLL:
    return ctypes.CDLL(ctypes.util.find_library(name) or fallback)


class Display:
    """The few Xlib and XTEST calls the Simulator needs."""

    def __init__(self, name: str):
        self.x = x = _load("X11", "libX11.so.6")
        self.xtst = _load("Xtst", "libXtst.so.6")
        x.XOpenDisplay.restype = ctypes.c_void_p
        x.XOpenDisplay.argtypes = [ctypes.c_char_p]
        x.XDefaultRootWindow.restype = ctypes.c_ulong
        x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        x.XGetImage.restype = ctypes.POINTER(XImage)
        x.XGetImage.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int,
                                ctypes.c_uint, ctypes.c_uint, ctypes.c_ulong, ctypes.c_int]
        x.XQueryTree.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong),
                                 ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)),
                                 ctypes.POINTER(ctypes.c_uint)]
        x.XGetWindowAttributes.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(XWindowAttributes)]
        x.XMoveResizeWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_uint]
        x.XSetWindowBorderWidth.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_uint]
        x.XSetInputFocus.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
        x.XFree.argtypes = [ctypes.c_void_p]
        x.XFlush.argtypes = [ctypes.c_void_p]
        x.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.xtst.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
        self.xtst.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
        self.xtst.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]

        # Windows can vanish between listing and inspecting them; without a
        # handler, Xlib's default would exit on the resulting BadWindow.
        handler_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)
        self._on_error = handler_type(lambda _d, _e: 0)
        x.XSetErrorHandler(self._on_error)

        self.dpy = x.XOpenDisplay(name.encode())
        if not self.dpy:
            raise ConnectionError(f"Cannot open display {name}")
        self.root = x.XDefaultRootWindow(self.dpy)
        x.XSetInputFocus(self.dpy, POINTER_ROOT, POINTER_ROOT, 0)
        x.XFlush(self.dpy)
        destroy_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.POINTER(XImage))
        self._destroy_type = destroy_type

    def capture(self, w: int, h: int) -> bytes | None:
        img = self.x.XGetImage(self.dpy, self.root, 0, 0, w, h, ALL_PLANES, ZPIXMAP)
        if not img:
            return None
        try:
            im = img.contents
            if im.bits_per_pixel != 32 or im.bytes_per_line != w * 4:
                return None
            return ctypes.string_at(im.data, w * h * 4)
        finally:
            self._destroy_type(img.contents.f.destroy_image)(img)

    def manage(self, w: int, h: int) -> bool:
        """Pin mapped top-level windows to the app area; True if there are any."""
        root = ctypes.c_ulong()
        parent = ctypes.c_ulong()
        children = ctypes.POINTER(ctypes.c_ulong)()
        count = ctypes.c_uint()
        if not self.x.XQueryTree(self.dpy, self.root, ctypes.byref(root), ctypes.byref(parent),
                                 ctypes.byref(children), ctypes.byref(count)):
            return False
        found = False
        try:
            for i in range(count.value):
                win = children[i]
                attrs = XWindowAttributes()
                if not self.x.XGetWindowAttributes(self.dpy, win, ctypes.byref(attrs)):
                    continue
                if attrs.override_redirect or attrs.map_state != VIEWABLE:
                    continue
                found = True
                if (attrs.x, attrs.y, attrs.width, attrs.height, attrs.border_width) != (0, 0, w, h, 0):
                    self.x.XSetWindowBorderWidth(self.dpy, win, 0)
                    self.x.XMoveResizeWindow(self.dpy, win, 0, 0, w, h)
        finally:
            if children:
                self.x.XFree(children)
        self.x.XFlush(self.dpy)
        return found

    def motion(self, x: int, y: int) -> None:
        self.xtst.XTestFakeMotionEvent(self.dpy, -1, x, y, 0)
        self.x.XFlush(self.dpy)

    def button(self, button: int, down: bool) -> None:
        self.xtst.XTestFakeButtonEvent(self.dpy, button, int(down), 0)
        self.x.XFlush(self.dpy)

    def key(self, code: int, down: bool) -> None:
        if 8 <= code <= 255:
            self.xtst.XTestFakeKeyEvent(self.dpy, code, int(down), 0)
            self.x.XFlush(self.dpy)


def bmp(data: bytes, w: int, h: int) -> bytes:
    """A 32-bit top-down BMP around BGRX pixels, which Qt reads as RGB32."""
    size = len(data)
    header = struct.pack("<2sIHHI", b"BM", 54 + size, 0, 0, 54)
    info = struct.pack("<IiiHHIIiiII", 40, w, -h, 1, 32, 0, size, 2835, 2835, 0, 0)
    return header + info + data


def average_row(data: bytes, w: int, row: int) -> list[int]:
    line = data[row * w * 4:(row + 1) * w * 4]
    if not line:
        return [0, 0, 0]
    step = 16  # every 4th pixel
    b, g, r = line[0::step], line[1::step], line[2::step]
    n = max(1, len(b))
    return [sum(r) // n, sum(g) // n, sum(b) // n]


def agent(display: str, frame_dir: str, w: int, h: int) -> int:
    os.makedirs(frame_dir, exist_ok=True)
    dpy = Display(display)
    out = sys.stdout
    last = b""
    last_window = None
    has_window = False
    seq = 0
    tick = 0
    buffer = b""
    while True:
        started = time.monotonic()
        # Commands from the helper.
        while select.select([sys.stdin], [], [], 0)[0]:
            chunk = os.read(sys.stdin.fileno(), 65536)
            if not chunk:
                return 0
            buffer += chunk
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                try:
                    cmd = json.loads(line)
                except ValueError:
                    continue
                t = cmd.get("t")
                if t == "region":
                    w, h = int(cmd["w"]), int(cmd["h"])
                    last = b""
                elif t == "motion":
                    dpy.motion(int(cmd["x"]), int(cmd["y"]))
                elif t == "button":
                    dpy.button(int(cmd["b"]), bool(cmd["down"]))
                elif t == "key":
                    dpy.key(int(cmd["code"]), bool(cmd["down"]))
        if tick % MANAGE_EVERY == 0:
            has_window = dpy.manage(w, h)
        tick += 1
        data = dpy.capture(w, h)
        if data is not None and (data != last or has_window != last_window):
            seq += 1
            path = os.path.join(frame_dir, f"frame-{seq % 2}.bmp")
            tmp = path + ".tmp"
            with open(tmp, "wb") as fh:
                fh.write(bmp(data, w, h))
            os.replace(tmp, path)
            last, last_window = data, has_window
            try:
                out.write(json.dumps({"frame": path, "seq": seq, "w": w, "h": h, "window": has_window,
                                      "top": average_row(data, w, 0), "bottom": average_row(data, w, h - 1)}) + "\n")
                out.flush()
            except BrokenPipeError:
                return 0  # the helper went away
        rest = FRAME_INTERVAL - (time.monotonic() - started)
        if rest > 0:
            time.sleep(rest)


if __name__ == "__main__":
    if len(sys.argv) == 6 and sys.argv[1] == "agent":
        sys.exit(agent(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])))
    print(__doc__, file=sys.stderr)
    sys.exit(2)
