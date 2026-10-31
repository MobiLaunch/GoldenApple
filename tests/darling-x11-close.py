#!/usr/bin/env python3
"""Verify close sender delivers WM_DELETE_WINDOW without destroying its target."""
import importlib.util
from pathlib import Path
import time
from Xlib import X, display

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('gui', ROOT / 'tools/darling/test-gui.py')
gui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gui)
connection = display.Display()
root = connection.screen().root
window = root.create_window(0, 0, 100, 100, 0, connection.screen().root_depth,
                            X.InputOutput, X.CopyFromParent)
try:
    delete = connection.intern_atom('WM_DELETE_WINDOW')
    window.set_wm_protocols([delete])
    window.map()
    connection.sync()
    gui.request_window_close(window.id)
    deadline = time.monotonic() + 3
    received = None
    while time.monotonic() < deadline:
        while connection.pending_events():
            event = connection.next_event()
            if event.type == X.ClientMessage:
                received = event
        if received:
            break
        time.sleep(0.01)
    assert received is not None, 'Close request was not received'
    assert received.client_type == connection.intern_atom('WM_PROTOCOLS')
    assert received.data[0] == 32 and received.data[1][0] == delete
    assert window.get_attributes().map_state == X.IsViewable, 'Sender destroyed target'
    print('PASS: WM_DELETE_WINDOW delivered; window remains owned by the app')
finally:
    window.destroy()
    connection.close()
