#!/usr/bin/env bash
# The actual screensaver loop -- runs inside the fullscreen ghostty window
# launch-screensaver.sh spawns. Animates screensaver/cairn.txt with a random
# ttfx effect on repeat, exiting the moment any key is pressed. Modeled on
# Omarchy's omarchy-screensaver.
#
# Optional $1: path to a lock script to chain into on exit (instead of just
# quitting to reveal the desktop) -- how "lock" triggers a screensaver first,
# then the real lock, as one continuous action. See launch-screensaver.sh's
# --lock-on-exit.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BANNER="$SCRIPT_DIR/cairn.txt"
LOCK_ON_EXIT="${1:-}"

cleanup() {
  pkill -x ttfx 2>/dev/null
  # Deliberately does NOT try to kill sibling screensaver instances on other
  # outputs here (single-output machine, not needed). A `pgrep -f
  # run-screensaver.sh`-based version of that was tried and removed
  # 2026-09-10: ghostty itself is launched as `ghostty ... -e
  # .../run-screensaver.sh ...`, so its own argv matches that same pattern
  # -- the kill loop was killing its own parent ghostty window right as it
  # tried to exec into $LOCK_ON_EXIT, silently taking the whole process
  # down before the real lock ever started. If multi-monitor support is
  # ever needed, coordinate cleanup centrally from launch-screensaver.sh
  # (which already tracks what it spawned) rather than pattern-matching
  # from inside an instance that can't safely distinguish "sibling script"
  # from "my own hosting terminal."
  if [ -n "$LOCK_ON_EXIT" ]; then
    exec "$LOCK_ON_EXIT"
  fi
  exit 0
}
trap cleanup SIGINT SIGTERM SIGHUP SIGQUIT

printf '\033]11;rgb:00/00/00\007'   # black background
tput civis                          # hide cursor
trap 'tput cnorm' EXIT

# The pty starts at the default 80x24 and only resizes once the compositor
# reports the real window size -- ttfx measures the terminal once at
# startup, so starting it before the resize lands draws an 80x24 canvas in
# the corner of the fullscreen window instead of filling it.
deadline=$((SECONDS + 2))
while ((SECONDS < deadline)) && [[ "$(stty size 2>/dev/null)" == "24 80" ]]; do
  sleep 0.02
done

while true; do
  ttfx -i "$BANNER" \
    --frame-rate 60 --canvas-width 0 --canvas-height 0 --reuse-canvas \
    --anchor-canvas c --anchor-text c \
    --random-effect --no-eol --no-restore-cursor &
  ttfx_pid=$!

  while kill -0 "$ttfx_pid" 2>/dev/null; do
    if read -r -n1 -t1; then
      cleanup
    fi
  done
done
