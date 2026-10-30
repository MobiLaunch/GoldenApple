#!/bin/sh
# The boot test's watch on what stops processes (citronos-boottest-signals.service,
# with gg.boottest only). Everything goes to the journal, which the boot test
# reads on the serial console (distro/archiso/boot-test.sh):
# - every SIGKILL and SIGXCPU, with the sender and the process it was for
#   (the kernel's signal_generate tracepoint);
# - the kernel's reason when it has one: a resource limit's "Watchdog Timeout"
#   (print_fatal_signals=1 on the command line), the out-of-memory killer;
# - for the shell (and each Quickshell app), its realtime run-time limit and any
#   thread on a realtime scheduling class, every 20 s for 5 minutes: a
#   realtime thread that runs past that limit is SIGKILLed by the kernel.
t=/sys/kernel/tracing
echo "sig == 9 || sig == 24" > "$t/events/signal/signal_generate/filter"
echo 1 > "$t/events/signal/signal_generate/enable"

dmesg -w | grep --line-buffered -E "Watchdog Timeout|Out of memory|oom-kill|invoked oom-killer" &

(
  i=0
  while [ "$i" -lt 15 ]; do
    sleep 20
    i=$((i + 1))
    for pid in $(pgrep -x qs); do
      limit=$(grep -i 'realtime timeout' "/proc/$pid/limits" 2>/dev/null | tr -s ' ')
      rt=$(ps -L -o tid=,cls=,rtprio=,comm= -p "$pid" 2>/dev/null | awk '$2 != "TS" && $2 != "B" && $2 != "IDL" { printf "%s ", $0 }')
      echo "qs[$pid] ${limit:-no limits}; realtime threads: ${rt:-none}"
    done
  done
) &

exec cat "$t/trace_pipe"
