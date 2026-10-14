#!/usr/bin/env python3
"""TextEdit workflow harness tests with simulated X11 and Darling processes.

These check the harness's pass/fail logic only; they do not establish that
TextEdit runs under Darling.
"""
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('textedit', ROOT / 'tools/darling/test-textedit.py')
textedit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(textedit)
sys.path.insert(0, str(ROOT / 'tests'))
gui_spec = importlib.util.spec_from_file_location('gui_harness', ROOT / 'tests/darling-gui-harness.py')
gui_harness = importlib.util.module_from_spec(gui_spec)
gui_spec.loader.exec_module(gui_harness)


class MarkerTests(unittest.TestCase):
    def test_insertions_anywhere_preserve_content(self):
        before = 'one\ntwo\n'
        for after in ('[m]one\ntwo\n', 'on[m]e\ntwo\n', 'one\ntwo\n[m]'):
            self.assertTrue(textedit.marker_inserted(before, after, '[m]'), after)

    def test_lost_or_replaced_content_fails(self):
        self.assertFalse(textedit.marker_inserted('one\ntwo\n', '[m]', '[m]'))
        self.assertFalse(textedit.marker_inserted('one\ntwo\n', '[m]one\n', '[m]'))
        self.assertFalse(textedit.marker_inserted('one\n', '[m][m]one\n', '[m]'))
        self.assertFalse(textedit.marker_inserted('one\n', 'one\n', '[m]'))


class WorkflowTests(unittest.TestCase):
    def run_workflow(self, save=True, lose_content=False, quit_code=0):
        launches = []

        class Process:
            def __init__(self, command, **kwargs):
                self.command, self.code = command, None
                launches.append(self)
            def poll(self): return self.code
            def wait(self, timeout=None):
                if self.code is None:
                    raise subprocess.TimeoutExpired(self.command, timeout)
                return self.code
            def terminate(self): self.code = -15

        typed = {}

        def run(command, **kwargs):
            if command[0] == 'xwd':
                Path(command[-1]).write_bytes(gui_harness.xwd([0, 0xffffff, 0x555555, 0x777777]))
            elif command[:2] == ['xdotool', 'search']:
                return subprocess.CompletedProcess(command, 0, '42\n', '')
            elif command[:2] == ['xdotool', 'getwindowname']:
                return subprocess.CompletedProcess(command, 0, 'GoldenGateNote.txt\n', '')
            elif command[:2] == ['xdotool', 'getwindowgeometry']:
                return subprocess.CompletedProcess(command, 0, 'WIDTH=600\nHEIGHT=400\n', '')
            elif command[:2] == ['xdotool', 'type']:
                typed['marker'] = command[-1]
            elif command[:3] == ['xdotool', 'key', '--clearmodifiers'] and command[3] == 'super+s' and save:
                path = Path(launches[-1].command[-1].removeprefix('/Volumes/SystemRoot'))
                text = path.read_text()
                path.write_text(typed['marker'] if lose_content else typed['marker'] + text)
            elif command[:3] == ['xdotool', 'key', '--clearmodifiers'] and command[3] == 'super+q':
                launches[-1].code = quit_code
            return subprocess.CompletedProcess(command, 0, '', '')

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            binary = root / 'TextEdit.app/Contents/MacOS/TextEdit'
            binary.parent.mkdir(parents=True)
            binary.write_text('')
            argv = ['test-textedit.py', '--app', str(root / 'TextEdit.app'),
                    '--prefix', str(root / 'prefix'), '--output', str(root / 'out')]
            with patch.object(sys, 'argv', argv), \
                    patch.dict(textedit.os.environ, {'DISPLAY': ':99'}), \
                    patch.object(textedit.shutil, 'which', return_value='/usr/bin/tool'), \
                    patch.object(textedit.subprocess, 'Popen', Process), \
                    patch.object(textedit.subprocess, 'run', side_effect=run), \
                    patch.object(textedit.gui.subprocess, 'run', side_effect=run), \
                    patch.object(textedit.gui, 'wait_until', side_effect=self.immediate), \
                    patch.object(textedit.gui, 'capture_live_backtrace'), \
                    patch.object(textedit.time, 'sleep'), \
                    patch('builtins.print'):
                code = textedit.main()
            result = json.loads((root / 'out/result.json').read_text())
            final = (root / 'out/documents' / textedit.DOCUMENT).read_text()
            return code, result, final, len(launches)

    @staticmethod
    def immediate(predicate, seconds):
        value = predicate()
        if not value:
            raise RuntimeError('Timed out waiting for the fixture')
        return value

    def test_two_sessions_pass(self):
        code, result, final, launches = self.run_workflow()
        self.assertEqual(code, 0)
        self.assertTrue(result['passed'])
        self.assertEqual(launches, 2)
        self.assertIn('session-2-saved-without-loss', result['checks'])
        self.assertIn('reopened-without-data-loss', result['checks'])
        self.assertTrue(final.endswith(textedit.BASELINE))
        self.assertEqual(final.count('[session'), 2)

    def test_unsaved_document_fails_in_first_session(self):
        code, result, _, launches = self.run_workflow(save=False)
        self.assertEqual(code, 1)
        self.assertEqual(result['phase'], 'session-1:save')
        self.assertIn('not written', result['error'])
        self.assertEqual(launches, 1)

    def test_replaced_content_is_data_loss(self):
        code, result, _, _ = self.run_workflow(lose_content=True)
        self.assertEqual(code, 1)
        self.assertIn('lost or changed', result['error'])

    def test_nonzero_quit_fails(self):
        code, result, _, _ = self.run_workflow(quit_code=6)
        self.assertEqual(code, 1)
        self.assertIn('quit with exit 6', result['error'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
