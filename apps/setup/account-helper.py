#!/usr/bin/python3 -I
"""Root-owned setup helper. Run via pkexec; read secrets only from stdin.
No shell, arbitrary paths, command flags, or existing-account password changes.
"""
import fcntl
import json
import os
import pwd
import re
import subprocess
import sys


def validate(data):
    name = data.get('username', '')
    full = data.get('fullName', '')
    if isinstance(full, str):
        full = full.strip()
    password = data.get('password', '')
    if not isinstance(name, str) or not re.fullmatch(r'[a-z_][a-z0-9_-]{0,30}', name):
        raise ValueError('Use a lowercase account name, starting with a letter, up to 31 characters.')
    if not isinstance(full, str) or not full or len(full) > 80 or any(ord(c) < 32 or c in ':,' for c in full):
        raise ValueError('Enter a full name without colons, commas, or control characters.')
    if not isinstance(password, str) or not 8 <= len(password) <= 256 or any(c in password for c in '\n\r\0'):
        raise ValueError('Use a password of 8–256 characters without line breaks.')
    return name, full, password


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
        '/usr/lib/golden-gate/save-preferences.py'], input=json.dumps(preferences), text=True, capture_output=True)
    if result.returncode:
        raise ValueError('The account exists, but its settings could not be saved. Free disk space and retry.')
    return {'ok': True, 'username': name}


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
