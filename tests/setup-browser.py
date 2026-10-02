#!/usr/bin/env python3
"""Data and privileged-operation tests. All account commands are mocked."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]

def module(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / file)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

account = module('account', 'apps/setup/account-helper.py')
prefs = module('preferences', 'apps/setup/save-preferences.py')
web = module('model', 'apps/browser/model.py')

class Setup(unittest.TestCase):
    def data(self, **extra):
        return dict(username='jordan', fullName='Jordan Ferguson', password='test-only-password', **extra)

    def test_invalid_accounts_never_spawn_commands(self):
        for name in ['-root', '../root', 'ROOT', 'new:user', 'a\nroot', '', 'a'*32]:
            with self.subTest(name=name), patch.object(account.subprocess, 'run') as run:
                with self.assertRaises(ValueError):
                    account.create(dict(self.data(), username=name))
                run.assert_not_called()

    def test_reject_password_newlines_and_short_passwords(self):
        for password in ['short', 'password\nroot:x', 'bad\0password']:
            with self.assertRaises(ValueError):
                account.validate(dict(self.data(), password=password))

    def test_existing_account_is_never_modified(self):
        with patch.object(account.pwd, 'getpwnam', return_value=object()), patch.object(account.subprocess, 'run') as run:
            with self.assertRaises(ValueError):
                account.create(self.data())
            run.assert_not_called()

    def test_password_only_uses_stdin(self):
        with patch.object(account.pwd, 'getpwnam', side_effect=KeyError), patch.object(account.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            self.assertTrue(account.create(self.data())['ok'])
            self.assertNotIn('test-only-password', repr([c.args for c in run.call_args_list]))
            self.assertEqual(run.call_args_list[1].kwargs['input'], 'jordan:test-only-password\n')
            self.assertNotIn('shell', run.call_args_list[0].kwargs)

    def test_failed_password_rolls_back_only_new_account(self):
        with patch.object(account.pwd, 'getpwnam', side_effect=KeyError), patch.object(account.subprocess, 'run', side_effect=[subprocess.CompletedProcess([], c) for c in [0, 1, 0]]) as run:
            with self.assertRaises(ValueError):
                account.create(self.data())
            self.assertEqual(run.call_args_list[-1].args[0], ['/usr/bin/userdel', '--remove', '--', 'jordan'])

    def test_save_marker_written_after_preferences(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp)
            prefs.save({'layout':'us', 'variant':'', 'look':'dark', 'location':False}, config)
            self.assertEqual(json.loads((config/'golden-gate/appearance.json').read_text())['mode'], 'dark')
            self.assertTrue((config/'golden-gate/setup-done').exists())
            self.assertFalse(json.loads((config/'golden-gate/privacy.json').read_text())['location'])

    def test_failed_save_never_marks_setup_complete(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp)
            (config/'hypr').write_text('not a directory')
            with self.assertRaises(OSError):
                prefs.save({}, config)
            self.assertFalse((config/'golden-gate/setup-done').exists())

    def test_keyboard_injection_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                prefs.save({'layout':'us\nexec=bad'}, Path(tmp))

    def test_web_is_the_only_browser_surface(self):
        packages = (ROOT/'distro/archiso/packages.x86_64').read_text()
        self.assertNotIn('\nfirefox\n', '\n' + packages + '\n')
        desktop = (ROOT/'apps/desktop/org.goldengate.Web.desktop').read_text()
        self.assertIn('Name=Web', desktop)
        self.assertIn('Exec=', desktop)


class BrowserData(unittest.TestCase):
    def test_address_or_search(self):
        self.assertEqual(web.address_url('example.com/path'), 'https://example.com/path')
        self.assertEqual(web.address_url('localhost:8080/a'), 'http://localhost:8080/a')
        self.assertEqual(web.address_url('127.0.0.1:8000'), 'http://127.0.0.1:8000')
        self.assertIn('q=repair+tips',web.address_url('repair tips'))

    def test_search_engine_selection(self):
        self.assertIn("duckduckgo.com", web.address_url("golden gate linux", "duckduckgo"))
        self.assertIn("search.brave.com", web.address_url("golden gate linux", "brave"))
        self.assertIn("bing.com", web.address_url("golden gate linux", "bing"))
        self.assertIn("google.com", web.address_url("golden gate linux", "google"))
        # Direct URLs must never be rewritten through a search engine.
        self.assertEqual(
            web.address_url("https://example.com/path", "google"),
            "https://example.com/path",
        )

    def test_pasted_active_content_rejected(self):
        for value in ['javascript:alert(1)', 'data:text/html,hi', 'file:///etc/passwd', 'ftp://example.com']:
            with self.assertRaises(ValueError):
                web.address_url(value)

    def test_search_engines_are_selectable(self):
        self.assertIn('duckduckgo.com', web.address_url('repair tips', 'duckduckgo'))
        self.assertIn('search.brave.com', web.address_url('repair tips', 'brave'))
        self.assertIn('bing.com', web.address_url('repair tips', 'bing'))
        self.assertIn('google.com', web.address_url('repair tips', 'google'))

    def test_invalid_saved_browser_state_is_sanitized(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'state.json'
            path.write_text(json.dumps({
                'settings': {'tabLayout': 'broken', 'searchEngine': 'evil',
                             'showFavoritesOnFocus': 'yes', 'restoreSession': None,
                             'privacyProtection': 'yes'},
                'tabGroups': [
                    {'name': 'Work', 'tabs': [
                        {'title': 'Good', 'url': 'https://example.com'},
                        {'title': 'Bad', 'url': 'javascript:alert(1)'}]},
                    {'name': '', 'tabs': [{'title': 'X', 'url': 'https://x.example'}]},
                ],
            }))
            store = web.Store(path)
            self.assertEqual(store.data['settings']['tabLayout'], 'separate')
            self.assertEqual(store.data['settings']['searchEngine'], 'duckduckgo')
            self.assertTrue(store.data['settings']['showFavoritesOnFocus'])
            self.assertTrue(store.data['settings']['restoreSession'])
            self.assertTrue(store.data['settings']['privacyProtection'])
            self.assertEqual(store.data['tabGroups'], [
                {'name': 'Work', 'tabs': [{'title': 'Good', 'url': 'https://example.com'}]}
            ])

    def test_private_state_never_written(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'state.json'
            store=web.Store(path, private=True)
            store.visit('https://example.com','Example')
            store.save()
            self.assertFalse(path.exists())
            self.assertFalse(store.data['history'])

    def test_corrupt_state_and_invalid_restored_urls(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'state.json'
            path.write_text('{broken')
            self.assertEqual(web.Store(path).data['tabs'],['about:blank'])
            path.write_text(json.dumps({'tabs':['javascript:alert(1)','https://example.com'], 'bookmarks':[{},None]}))
            store=web.Store(path)
            self.assertEqual(store.data['tabs'],['https://example.com'])
            self.assertEqual(store.data['bookmarks'],[])

    def test_atomic_round_trip_and_bounded_history(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'state.json'
            store=web.Store(path)
            for i in range(305): store.visit(f'https://example.com/{i}',f'Page {i}')
            store.save()
            self.assertEqual(len(web.Store(path).data['history']),300)
            self.assertEqual(path.stat().st_mode & 0o777,0o600)

if __name__ == '__main__':
    unittest.main(verbosity=2)
