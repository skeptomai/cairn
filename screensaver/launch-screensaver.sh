#!/usr/bin/env bash
# Launch the Cairn screensaver: one fullscreen ghostty per connected output,
# running run-screensaver.sh, which animates screensaver/cairn.txt with a
# random ttfx effect and exits on any keypress. Modeled on Omarchy's
# omarchy-launch-screensaver, adapted from Hyprland/hyprctl to Sway/swaymsg.
#
# Wired into sway/config's swayidle timeout chain -- not meant to be run
# interactively, though `./launch-screensaver.sh` works fine for testing.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    -e "$SCRIPT_DIR/run-screensaver.sh" >/dev/null
  # No IPC event to wait on here (unlike Hyprland's socket/niri's window-id
  # polling) -- a short fixed sleep is enough to keep each output's window
  # from piling onto whichever one is still focused when the next exec
  # fires. Good enough for the handful of outputs a real desktop has.
  sleep 0.3
done

[ -n "$focused" ] && swaymsg focus output "$focused" >/dev/null
