#!/usr/bin/env bash
# The test VM's swayidle blanks its virtual output after 600s idle and only
# wakes on real input -- but nothing's touching the VM's keyboard/mouse while
# no one is connected via virt-viewer, so it sits blanked. spice/virt-viewer
# then shows "Display output is not active" until DPMS is explicitly turned
# back on. This isn't a crash -- see VM-TESTING.md.
#
# Usage: ./vm-wake-display.sh <user@host>   (e.g. youruser@192.168.122.39 --
# pass your VM's own user/IP, no default is assumed)
set -euo pipefail

vm_host="${1:?usage: $0 <user@host>}"

# The VM's default shell is fish (see VM-TESTING.md), which chokes on plain
# `VAR=$(...)` syntax -- run the actual logic through bash explicitly.
# swaymsg also needs SWAYSOCK spelled out over a plain, non-interactive SSH
# session: the socket filename embeds sway's PID, so it isn't a fixed path.
#
# ssh joins multiple local arguments with spaces and hands the result to the
# remote login shell (fish) unquoted, so the whole remote command has to
# travel as ONE argument (not split across `bash -c` + a separate string)
# or fish tries to parse the bash-only syntax inside it itself.
remote_cmd='bash -c "sock=\$(ls -t /run/user/1000/sway-ipc.*.sock 2>/dev/null | head -1); if [ -z \"\$sock\" ]; then echo no sway-ipc socket found -- is sway even running? >&2; exit 1; fi; SWAYSOCK=\$sock swaymsg \"output * dpms on\""'

ssh "$vm_host" "$remote_cmd"
