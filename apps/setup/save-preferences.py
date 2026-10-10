#!/usr/bin/python3
"""Save first-run choices as the target user.

    save-preferences.py < PREFS            the choices (no completion marker)
    save-preferences.py --done < PREFS     the choices, then setup-done, last

Hello saves the choices, applies the system-wide ones (time zone, region
formats) and only then marks setup done, so a failure part way leaves Setup
to run again. Choices put off for later are listed in setup-deferred.json.

The region's formats (dates, numbers, currency, measurement) go to
~/.config/environment.d as LC_* variables; the language of CitronOS's own
apps stays English (LANG is left alone)."""
import datetime
import json
import os
from pathlib import Path
import re
import sys

DEFERRABLE = {'timezone', 'formats', 'location'}


def atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    with temporary.open('w') as stream:
        stream.write(text)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def save(data, config, done=False):
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
    zone = data.get('zone', '')
    if not isinstance(zone, str) or (zone and not re.fullmatch(r'[A-Za-z_]+(/[A-Za-z0-9_+-]+){0,2}', zone)):
        raise ValueError('Invalid time zone')
    formats = data.get('formats', '')
    if not isinstance(formats, str) or (formats and not re.fullmatch(r'[a-z]{2,3}_[A-Z]{2}', formats)):
        raise ValueError('Invalid region formats')
    region = data.get('region', '')
    if not isinstance(region, str) or len(region) > 60 or any(ord(c) < 32 for c in region):
        raise ValueError('Invalid region')
    deferred = data.get('deferred', [])
    if not isinstance(deferred, list) or not set(deferred) <= DEFERRABLE:
        raise ValueError('Invalid deferred choices')
    privacy = {k: bool(data.get(k, False)) for k in ('location', 'shareDiagnostics', 'shareWithDevelopers')}

    atomic(config / 'hypr/golden-gate/input.conf', f'input {{\n    kb_layout = {layout}\n    kb_variant = {variant}\n}}\n')
    atomic(config / 'golden-gate/privacy.json', json.dumps(privacy) + '\n')
    atomic(config / 'golden-gate/appearance.json', json.dumps({'mode': mode}) + '\n')
    if zone or formats or region:
        atomic(config / 'golden-gate/region.json', json.dumps({'region': region, 'zone': zone, 'formats': formats}) + '\n')
    if formats:
        atomic(config / 'environment.d/90-golden-formats.conf',
               ''.join(f'{k}={formats}.UTF-8\n' for k in ('LC_TIME', 'LC_NUMERIC', 'LC_MONETARY', 'LC_PAPER', 'LC_MEASUREMENT')))
    if not done:
        return
    if deferred:
        atomic(config / 'golden-gate/setup-deferred.json', json.dumps(sorted(set(deferred))) + '\n')
    else:
        try:
            (config / 'golden-gate/setup-deferred.json').unlink()
        except FileNotFoundError:
            pass
    # Last: Setup doesn't run again once this exists.
    atomic(config / 'golden-gate/setup-done', datetime.datetime.now(datetime.timezone.utc).isoformat() + '\n')


if __name__ == '__main__':
    try:
        save(json.load(sys.stdin), Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))),
             done='--done' in sys.argv[1:])
    except (ValueError, OSError, TypeError):
        print('Settings could not be saved. Check free space and folder permissions.', file=sys.stderr)
        sys.exit(1)
