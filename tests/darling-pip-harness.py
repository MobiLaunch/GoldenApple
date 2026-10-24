#!/usr/bin/env python3
"""PIP behavior results cannot hide timeout or nonzero process exit."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('pip_runner', ROOT / 'tools/darling/test-pip.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class PipHarnessTests(unittest.TestCase):
    def exercise(self, exit_code, timeout=False):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            app = root / 'PIPLab.app'
            binary = app / 'Contents/MacOS/PIPLab'
            binary.parent.mkdir(parents=True)
            binary.touch()
            output = root / 'output'
            output.mkdir()
            (output / 'results.json').write_text(json.dumps({'passed': True, 'checks': 21, 'failures': 0}))
            class Process:
                def wait(self, timeout):
                    if timeout_flag:
                        raise subprocess.TimeoutExpired('darling', timeout)
                    return exit_code
            timeout_flag = timeout
            def launch(command, **kwargs):
                # A regular file, never a PIPE awaiting service-held stdout.
                self.assertTrue(hasattr(kwargs['stdout'], 'fileno'))
                return Process()
            argv = ['test-pip', '--app', str(app), '--prefix', str(root / 'prefix'), '--output', str(output)]
            with patch.object(sys, 'argv', argv), patch.dict(runner.os.environ, {'DISPLAY': ':99'}), \
                 patch.object(runner.subprocess, 'Popen', side_effect=launch), \
                 patch.object(runner.gui, 'capture_live_backtrace') as trace, patch('builtins.print'):
                code = runner.main()
            result = json.loads((output / 'runner-result.json').read_text())
            self.assertEqual(result['behavior']['checks'], 21)
            self.assertEqual(trace.called, timeout or exit_code != 0)
            return code, result

    def test_clean_exit_and_behavior_pass(self):
        code, result = self.exercise(0)
        self.assertEqual(code, 0)
        self.assertTrue(result['passed'])

    def test_behavior_pass_does_not_mask_exit_hang(self):
        code, result = self.exercise(None, timeout=True)
        self.assertEqual(code, 1)
        self.assertFalse(result['passed'])
        self.assertEqual(result['phase'], 'clean-exit')

    def test_behavior_pass_does_not_mask_nonzero_exit(self):
        code, result = self.exercise(7)
        self.assertEqual(code, 1)
        self.assertFalse(result['passed'])
        self.assertEqual(result['launcher_exit'], 7)


if __name__ == '__main__':
    unittest.main()
