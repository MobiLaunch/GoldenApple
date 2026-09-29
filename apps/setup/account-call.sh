#!/bin/sh
# The installed helper is root-owned. Never elevate a script in a user's home.
helper=/usr/lib/golden-gate/account-helper.py
if [ ! -f "$helper" ]; then
    printf '%s\n' 'Account creation needs the system setup helper. Run sudo scripts/install.sh --extras from the project first.' >&2
    exit 1
fi
if [ "$(id -un)" = golden ] && [ -d /run/archiso ]; then
    exec sudo -n /usr/bin/python3 -I "$helper"
fi
exec pkexec /usr/bin/python3 -I "$helper"
