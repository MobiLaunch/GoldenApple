#!/bin/sh
# One native Golden Gate interface to the connected CitronPods daemon.
set -eu
case "${1:-status}" in
  status)
    if ! busctl --user --no-pager --quiet status org.citronos.CitronPods1 >/dev/null 2>&1; then
      printf '%s\n' 'CitronPods engine is not online. Install with gg-install-citronpods ARCHIVE.zip'
      exit 1
    fi
    busctl --user call org.citronos.CitronPods1 /org/citronos/CitronPods org.citronos.CitronPods1 GetState
    ;;
  show) exec qs -c golden-gate ipc call citronpods show ;;
  settings) exec gg-settings airpods ;;
  restart) exec systemctl --user restart citronpods-daemon.service ;;
  start) exec systemctl --user start citronpods-daemon.service ;;
  stop) exec systemctl --user stop citronpods-daemon.service ;;
  logs) exec journalctl --user -u citronpods-daemon.service --no-pager -n 100 ;;
  *) echo 'Usage: gg-citronpods [status|show|settings|start|stop|restart|logs]' >&2; exit 2 ;;
esac
