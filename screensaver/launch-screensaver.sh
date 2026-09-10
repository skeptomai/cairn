#!/usr/bin/env bash
# Launch the Cairn screensaver: one fullscreen ghostty per connected output,
# running run-screensaver.sh, which animates screensaver/cairn.txt with a
# random ttfx effect and exits on any keypress. Modeled on Omarchy's
# omarchy-launch-screensaver, adapted from Hyprland/hyprctl to Sway/swaymsg.
#
# Wired into sway/config's swayidle timeout chain -- not meant to be run
# interactively, though `./launch-screensaver.sh` works fine for testing.
#
# Usage:
#   ./launch-screensaver.sh                 idle-timeout / preview behavior:
#                                            any keypress just dismisses it
#   ./launch-screensaver.sh --lock-on-exit   "lock" behavior: the screensaver
#                                            plays first, and dismissing it
#                                            (any keypress) hands off directly
#                                            into the real lock (lockscreen/
#                                            lock.sh) instead of revealing the
#                                            desktop. Note this is NOT an
#                                            actual session lock by itself --
#                                            it's a plain window, so there's a
#                                            brief window where the screen is
#                                            covered but not yet genuinely
#                                            locked. Deliberately not used for
#                                            lid-close/before-sleep, which
#                                            need to lock instantly.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOCK_ON_EXIT=""
if [ "${1:-}" = "--lock-on-exit" ]; then
  LOCK_ON_EXIT="$SCRIPT_DIR/../lockscreen/lock.sh"
fi

# Already running (one or more outputs) -- don't stack a second set.
pgrep -f 'run-screensaver\.sh' &>/dev/null && exit 0

if ! command -v ttfx &>/dev/null; then
  echo "ttfx not found -- install the hypa-ttfx-bin AUR package (see bootstrap.sh)" >&2
  exit 1
fi

focused="$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name')"

for output in $(swaymsg -t get_outputs | jq -r '.[] | select(.active) | .name'); do
  swaymsg focus output "$output" >/dev/null
  # ghostty's --class only affects X11 WM_CLASS, not the Wayland app_id --
  # sway/config's for_window rule matches on this window's title instead
  # (ghostty titles a -e window with the command it's running).
  swaymsg exec -- ghostty --font-size=18 \
    --window-padding-x=0 --window-padding-y=0 \
    -e "$SCRIPT_DIR/run-screensaver.sh" "$LOCK_ON_EXIT" >/dev/null
  # No IPC event to wait on here (unlike Hyprland's socket/niri's window-id
  # polling) -- a short fixed sleep is enough to keep each output's window
  # from piling onto whichever one is still focused when the next exec
  # fires. Good enough for the handful of outputs a real desktop has.
  sleep 0.3
done

[ -n "$focused" ] && swaymsg focus output "$focused" >/dev/null
