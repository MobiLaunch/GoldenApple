#!/usr/bin/env python3
"""Compatibility labels must follow evidence, not installation or process survival."""
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('compatibility', ROOT / 'tools/darling/compatibility.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class EvidenceGates(unittest.TestCase):
    def setUp(self):
        self.data = json.loads(module.MANIFEST.read_text())

    def test_current_record(self):
        module.validate(self.data)

    def test_no_supported_label_for_unvalidated_app(self):
        target = self.data['targets'][0]
        target.update(status='supported', blockers=[])
        with self.assertRaisesRegex(ValueError, 'validated workflow'):
            module.validate(self.data)

    def test_no_validated_milestone_with_pending_checks(self):
        self.data['milestones'][0]['status'] = 'validated'
        with self.assertRaisesRegex(ValueError, 'not all passed'):
            module.validate(self.data)

    def test_result_requires_evidence(self):
        self.data['milestones'][1]['checks'][0]['status'] = 'passed'
        with self.assertRaisesRegex(ValueError, 'requires evidence'):
            module.validate(self.data)

    def test_prerequisites_must_pass(self):
        milestone = self.data['milestones'][1]
        milestone['status'] = 'validated'
        for check in milestone['checks']:
            check.update(status='passed', evidence=['https://example.invalid/test-evidence'])
        with self.assertRaisesRegex(ValueError, 'prerequisites'):
            module.validate(self.data)

    def test_cycles_are_rejected(self):
        self.data['milestones'][0]['requires'] = ['M2']
        with self.assertRaisesRegex(ValueError, 'cycle'):
            module.validate(self.data)


if __name__ == '__main__':
    unittest.main()
