#!/usr/bin/python3
"""Save first-run choices as the target user; completion marker is written last."""
import datetime
import json
import os
from pathlib import Path
import re
import sys


def save(data, config):
    if not isinstance(data, dict):
        raise ValueError('Invalid preferences')
    layout, variant = data.get('layout', 'us'), data.get('variant', '')
    if not isinstance(layout, str) or not re.fullmatch(r'[a-z0-9_,+-]{1,40}', layout):
        raise ValueError('Invalid keyboard layout')
    if not isinstance(variant, str) or not re.fullmatch(r'[a-zA-Z0-9_,+-]{0,60}', variant):
        raise ValueError('Invalid keyboard variant')
    mode = data.get('look', 'light')
    if mode not in ('light', 'dark', 'auto'):
        raise ValueError('Invalid appearance')
    privacy = {k: bool(data.get(k, False)) for k in ('location', 'shareDiagnostics', 'shareWithDevelopers')}
    def atomic(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + '.tmp')
        with temporary.open('w') as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)
    atomic(config / 'hypr/golden-gate/input.conf', f'input {{\n    kb_layout = {layout}\n    kb_variant = {variant}\n}}\n')
    atomic(config / 'golden-gate/privacy.json', json.dumps(privacy) + '\n')
    atomic(config / 'golden-gate/appearance.json', json.dumps({'mode': mode}) + '\n')
    atomic(config / 'golden-gate/setup-done', datetime.datetime.now(datetime.timezone.utc).isoformat() + '\n')


if __name__ == '__main__':
    try:
        save(json.load(sys.stdin), Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))))
    except (ValueError, OSError, TypeError):
        print('Settings could not be saved. Check free space and folder permissions.', file=sys.stderr)
        sys.exit(1)
