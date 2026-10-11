#!/usr/bin/env python3
"""Failure-path tests only; these do not establish Darling GUI support."""
import importlib.util
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('gui', ROOT / 'tools/darling/test-gui.py')
gui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gui)


def xwd(pixels, padding=b'', alpha=False):
    header = [100, 7, 2, 24, len(pixels), 1, 0, 0, 32, 0, 32, 32,
              len(pixels) * 4 + len(padding), 4, 0xff0000, 0xff00, 0xff, 8, 256, 0,
              len(pixels), 1, 0, 0, 0]
    return struct.pack('>25I', *header) + b''.join(struct.pack('<I', p | (i << 24 if alpha else 0)) for i, p in enumerate(pixels)) + padding


class HarnessTests(unittest.TestCase):
    def surface(self, data):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'screen.xwd'
            path.write_bytes(data)
            return gui.surface_has_content(path)

    def test_black(self):
        self.assertFalse(self.surface(xwd([0] * 20)))

    def test_padding_and_alpha_do_not_count_as_rendering(self):
        self.assertFalse(self.surface(xwd([0] * 20, b'colorful padding', True)))

    def test_nonuniform(self):
        self.assertTrue(self.surface(xwd([0, 0xffffff, 0x555555, 0x777777])))

    def test_truncated(self):
        with self.assertRaisesRegex(RuntimeError, 'Truncated XWD'):
            self.surface(xwd([0] * 20)[:-4])

    def test_command_stderr(self):
        with patch.object(gui.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'BadWindow')):
            with self.assertRaisesRegex(RuntimeError, 'BadWindow'):
                gui.xdo('getwindowgeometry', '123')

    def exercise_failure(self, black, cleanup_denied=False):
        import json
        calls = []
        state = {'exit': None}
        class Process:
            def poll(self): return state['exit']
            def terminate(self):
                if cleanup_denied: raise PermissionError('privileged launcher')
                state['exit'] = -15
            def kill(self): state['exit'] = -9
            def wait(self, timeout): return state['exit']
        def run(command, **kwargs):
            calls.append(command)
            if command[0] == 'xwd':
                Path(command[-1]).write_bytes(xwd([0] * 20 if black else [0, 0xffffff, 0x555555, 0x777777]))
            if command[:2] == ['xdotool', 'search']:
                return subprocess.CompletedProcess(command, 0, '123\n', '')
            if command[:2] == ['xdotool', 'getwindowgeometry']:
                return subprocess.CompletedProcess(command, 0, 'HEIGHT=380\n', '')
            if command[:2] == ['xdotool', 'type']:
                state['exit'] = 7
                return subprocess.CompletedProcess(command, 1, '', 'BadWindow during typing')
            return subprocess.CompletedProcess(command, 0, '', '')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            binary = root / 'ControllerLab.app/Contents/MacOS/ControllerLab'
            binary.parent.mkdir(parents=True)
            binary.touch()
            argv = ['test-gui', '--app', str(root / 'ControllerLab.app'), '--prefix', str(root / 'prefix'), '--output', str(root / 'result')]
            with patch.object(sys, 'argv', argv), patch.dict(gui.os.environ, {'DISPLAY': ':99'}), \
                 patch.object(gui.shutil, 'which', return_value='/fake/tool'), \
                 patch.object(gui.subprocess, 'Popen', return_value=Process()), \
                 patch.object(gui.subprocess, 'run', side_effect=run), \
                 patch.object(gui.time, 'monotonic', side_effect=range(0, 1000, 5)), \
                 patch.object(gui.time, 'sleep'), patch('builtins.print'):
                self.assertEqual(gui.main(), 1)
            result = json.loads((root / 'result/result.json').read_text())
            self.assertFalse(result['passed'])
            self.assertTrue((root / 'result/processes.log').exists())
            return result, calls

    def test_black_window_never_receives_input(self):
        result, calls = self.exercise_failure(True)
        self.assertEqual(result['phase'], 'rendering')
        self.assertNotIn('text-input', result['checks'])
        self.assertFalse(any(c[:2] == ['xdotool', 'type'] for c in calls))

    def test_privileged_cleanup_preserves_failure_report(self):
        result, _ = self.exercise_failure(True, cleanup_denied=True)
        self.assertEqual(result["phase"], "rendering")
        self.assertIn("privileged launcher", result["launcher_cleanup_error"])
        self.assertFalse(result["passed"])

    def test_input_crash_keeps_phase_stderr_and_natural_exit(self):
        result, _ = self.exercise_failure(False)
        self.assertEqual(result['phase'], 'typing')
        self.assertIn('BadWindow during typing', result['error'])
        self.assertEqual(result['launcher_exit_before_cleanup'], 7)
        self.assertNotIn('text-input', result['checks'])


if __name__ == '__main__':
    unittest.main()
