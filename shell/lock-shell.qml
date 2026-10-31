// The lock screen on its own, apart from the shell: `qs -p lock-shell.qml`
// (citronos-lock.service, `gg-lock serve`). A crash in the shell can't take it
// down, and if it crashes while locked, Hyprland keeps the session locked
// (misc:allow_session_lock_restore) and systemd starts it again a second
// later. It locks at once then, because $XDG_RUNTIME_DIR/citronos-locked says
// the session is locked.
//   gg-lock     lock (hypridle's lock_cmd, ⌃⌘Q, Lock Screen in the menus)
import Quickshell

ShellRoot {
    LockScreen {}
}
