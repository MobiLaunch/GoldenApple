"""Browser state and address handling, independent of Qt."""
import ipaddress
import json
import os
from pathlib import Path
from urllib.parse import quote_plus, urlsplit


def address_url(text):
    value = text.strip()
    if not value or value == 'about:blank':
        return 'about:blank'
    # Never execute pasted javascript or accept arbitrary application protocols.
    if value.startswith(('https://', 'http://')):
        parsed = urlsplit(value)
        if parsed.hostname and not any(c.isspace() for c in value):
            return value
        raise ValueError('Enter a valid web address.')
    if '://' in value or value.lower().startswith(('javascript:', 'data:', 'file:', 'chrome:', 'qrc:')):
        raise ValueError('Only http and https web addresses are supported.')
    host = value.split('/')[0].split(':')[0]
    local = host == 'localhost'
    try:
        ipaddress.ip_address(host)
        local = True
    except ValueError:
        pass
    if not any(c.isspace() for c in value) and (local or '.' in host):
        return ('http://' if local else 'https://') + value
    return 'https://duckduckgo.com/?q=' + quote_plus(value)


class Store:
    def __init__(self, path, private=False):
        self.path = Path(path)
        self.private = private
        self.data = {
            'bookmarks': [],
            'history': [],
            'tabs': ['about:blank'],
            'readingList': [],
            'closedTabs': [],
            'tabGroups': [],
            'settings': {
                'tabLayout': 'separate',
                'searchEngine': 'duckduckgo',
                'showFavoritesOnFocus': True,
                'restoreSession': True,
            },
        }
        if not private:
            try:
                saved = json.loads(self.path.read_text())
                for key, default in self.data.items():
                    value = saved.get(key)
                    if isinstance(default, list) and isinstance(value, list):
                        self.data[key] = value
                    elif isinstance(default, dict) and isinstance(value, dict):
                        self.data[key] = {**default, **value}
            except (OSError, ValueError, AttributeError):
                pass
        for key in ('bookmarks', 'history', 'readingList', 'closedTabs'):
            self.data[key] = [r for r in self.data[key] if isinstance(r, dict)
                              and isinstance(r.get('title'), str) and self.valid(r.get('url'))]
        self.data['closedTabs'] = self.data['closedTabs'][:30]
        self.data['tabs'] = [v for v in self.data['tabs'] if v == 'about:blank' or self.valid(v)][:30] or ['about:blank']
        self.data['tabGroups'] = [
            g for g in self.data['tabGroups']
            if isinstance(g, dict) and isinstance(g.get('name'), str)
            and isinstance(g.get('tabs', []), list)
        ][:20]

    @staticmethod
    def valid(url):
        if not isinstance(url, str):
            return False
        try:
            return urlsplit(url).scheme in ('https', 'http') and bool(urlsplit(url).hostname)
        except ValueError:
            return False

    def save(self):
        if self.private:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        temp = self.path.with_suffix('.tmp')
        # Each normal window is a single instance (QLockFile in browser.py).
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as stream:
            json.dump(self.data, stream, ensure_ascii=False)
        temp.replace(self.path)

    def visit(self, url, title):
        if self.private or not self.valid(url):
            return
        self.data['history'] = ([{'url': url, 'title': title or url}] +
                                [r for r in self.data['history'] if r['url'] != url])[:300]
