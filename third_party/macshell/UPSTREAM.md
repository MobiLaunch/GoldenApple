# MacShell

CitronOS's menu bar, Dock, Control Center, Spotlight, notifications, desktop
widgets, screenshots and lock screen come from MacShell by Rickky (MIT, see
LICENSE): https://github.com/0-ss/MacShell

| | |
|---|---|
| Upstream commit | c151c7cec78dd298dfb8e4948e174fd433c6cbf6 (2026-10-18) |
| `MacShell/` | `shell/macshell/`; its `shell.qml` is `MacShell.qml`, a Scope that `shell/shell.qml` loads |
| `MacLock/` | `shell-lock/`, installed as the Quickshell config `golden-gate-lock` |
| Not taken | `install.sh`, `MacShell/macshell-update` (Software Update installs the shell), `MacLock/hyprland.lua` |

Local changes are listed in `docs/SHELL.md`. To compare with a newer
upstream: `git diff --no-index <upstream>/MacShell shell/macshell`.
