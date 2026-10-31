#!/usr/bin/python3 -I
"""Root-owned setup helper. Run via pkexec; read secrets only from stdin.
No shell, arbitrary paths, command flags, or existing-account password changes.
"""
import fcntl
import importlib.util
import json
import os
import pwd
import re
import subprocess
import sys


def load_rules():
    # Beside this file, root-owned like it (/usr/lib/golden-gate); never sys.path.
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'account_rules.py')
    spec = importlib.util.spec_from_file_location('account_rules', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rules = load_rules()


def validate(data):
    name = data.get('username', '')
    full = data.get('fullName', '')
    password = data.get('password', '')
    problem = (rules.check_username(name, rules.names_in('/etc/passwd', '/etc/group'))
               or rules.check_full_name(full) or rules.check_password(password))
    if problem:
        raise ValueError(problem)
    return name, full.strip(), password


def create(data):
    name, full, password = validate(data)
    try:
        pwd.getpwnam(name)
    except KeyError:
        pass
    else:
        raise ValueError('That account already exists. Choose a different account name.')
    result = subprocess.run(['/usr/bin/useradd', '--create-home', '--user-group', '--groups', 'wheel',
                             '--shell', '/bin/bash', '--comment', full, '--', name], capture_output=True)
    if result.returncode:
        raise ValueError('The account could not be created. Check free space and try another name.')
    result = subprocess.run(['/usr/bin/chpasswd'], input=f'{name}:{password}\n', text=True, capture_output=True)
    if result.returncode:
        # Only this newly-created, still-locked account may be rolled back.
        cleanup = subprocess.run(['/usr/bin/userdel', '--remove', '--', name], capture_output=True)
        if cleanup.returncode:
            raise ValueError('Password setup failed. The new account remains locked; an administrator must remove it before retrying.')
        raise ValueError('Password setup failed. The new account was removed; please try again.')
    return {'ok': True, 'username': name}


def finish(data):
    name = data.get('username', '')
    if not isinstance(name, str) or not re.fullmatch(r'[a-z_][a-z0-9_-]{0,30}', name):
        raise ValueError('Invalid account name.')
    user = pwd.getpwnam(name)
    if user.pw_uid < 1000 or user.pw_uid >= 60000:
        raise ValueError('Setup only configures local desktop accounts.')
    preferences = data.get('preferences', {})
    # Drop privileges before touching the user's home; symlinks cannot turn
    # preference writes into root file writes. No inherited PYTHONPATH or HOME.
    result = subprocess.run(['/usr/bin/runuser', '-u', name, '--', '/usr/bin/env', '-i',
        'HOME=' + user.pw_dir, 'PATH=/usr/bin:/bin', '/usr/bin/python3', '-I',
        '/usr/lib/golden-gate/save-preferences.py', '--done'], input=json.dumps(preferences), text=True, capture_output=True)
    if result.returncode:
        raise ValueError('The account exists, but its settings could not be saved. Free disk space and retry.')
    return {'ok': True, 'username': name}


ZONEINFO = '/usr/share/zoneinfo'


def system(data):
    """The system-wide choices from Hello: the time zone, and the region's
    formats locale generated so dates and numbers can follow it. Each is
    reported on its own, so Hello can say which failed."""
    out = {'ok': True, 'zone': None, 'formats': None}
    zone = data.get('zone')
    if zone is not None:
        real = os.path.realpath(os.path.join(ZONEINFO, zone)) if isinstance(zone, str) else ''
        if not isinstance(zone, str) or not re.fullmatch(r'[A-Za-z_]+(/[A-Za-z0-9_+-]+){0,2}', zone) \
                or not real.startswith(ZONEINFO + '/') or not os.path.isfile(real):
            out['zone'] = 'That time zone isn\'t known to this system.'
        else:
            r = subprocess.run(['/usr/bin/timedatectl', 'set-timezone', zone], capture_output=True, text=True)
            if r.returncode:
                out['zone'] = 'The time zone couldn\'t be set (timedatectl failed).'
    formats = data.get('formats')
    if formats is not None:
        if not isinstance(formats, str) or not re.fullmatch(r'[a-z]{2,3}_[A-Z]{2}', formats):
            out['formats'] = 'Those region formats aren\'t known.'
        else:
            out['formats'] = generate_locale(formats)
    out['ok'] = not out['zone'] and not out['formats']
    return out


def generate_locale(name):
    """"" once name.UTF-8 is available to programs, or why it isn't."""
    have = subprocess.run(['/usr/bin/locale', '-a'], capture_output=True, text=True).stdout.split()
    if name + '.utf8' in have or name + '.UTF-8' in have:
        return ''
    entry = name + '.UTF-8 UTF-8'
    try:
        with open('/usr/share/i18n/SUPPORTED', encoding='utf-8') as f:
            if entry not in (line.strip() for line in f):
                return 'Formats for this region aren\'t available on this system.'
        try:
            with open('/etc/locale.gen', encoding='utf-8') as f:
                current = f.read()
        except FileNotFoundError:
            current = ''
        if entry not in (line.strip() for line in current.splitlines()):
            tmp = '/etc/locale.gen.gg-tmp'
            with open(tmp, 'w', encoding='utf-8') as f:
                f.write(current + ('' if current.endswith('\n') or not current else '\n') + entry + '\n')
                f.flush()
                os.fsync(f.fileno())
            os.chmod(tmp, 0o644)
            os.replace(tmp, '/etc/locale.gen')
    except OSError:
        return 'The region formats couldn\'t be prepared.'
    r = subprocess.run(['/usr/bin/locale-gen'], capture_output=True, text=True)
    return '' if r.returncode == 0 else 'The region formats couldn\'t be prepared (locale-gen failed).'


def main():
    if os.geteuid() != 0:
        raise ValueError('Administrator authorization is required to create an account.')
    raw = sys.stdin.read(16385)
    if len(raw) > 16384:
        raise ValueError('Setup request is too large.')
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError('Invalid setup request.')
    # Serialize account creation and reject duplicate retries safely.
    with open('/run/lock/golden-gate-setup.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if data.get('operation', 'create') == 'create':
            result = create(data)
        elif data.get('operation') == 'finish':
            result = finish(data)
        elif data.get('operation') == 'system':
            result = system(data)
        else:
            raise ValueError('Unknown setup operation.')
    print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError):
        # Never echo request contents or subprocess diagnostics (may contain PII).
        print(json.dumps({'ok': False, 'error': 'Account setup failed. Check the account name, password requirements, authorization, and free disk space.'}))
        sys.exit(1)
