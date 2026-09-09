#!/usr/bin/env bash
# Standalone gum theme picker — the day-to-day entry point. `install.sh`
# also calls this same script as its closing step; don't duplicate the
# gum-choose logic in both places.
#
# Usage:
#   ./pick-theme.sh              interactive gum picker
#   ./pick-theme.sh <preset>     apply a specific preset directly, no picker

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v gum &>/dev/null; then
  echo "gum is required (pacman -S gum)."
  exit 1
fi

mapfile -t PRESETS < <(find "$SCRIPT_DIR/palettes" -maxdepth 1 -name "*.toml" -exec basename {} .toml \; | sort)

if [ "${#PRESETS[@]}" -eq 0 ]; then
  echo "no palettes found in $SCRIPT_DIR/palettes"
  exit 1
fi

if [ $# -eq 1 ]; then
  CHOICE="$1"
else
  CHOICE="$(printf '%s\n' "${PRESETS[@]}" | gum choose --header "Pick a theme")"
fi

[ -n "$CHOICE" ] || exit 0
python3 "$SCRIPT_DIR/apply-theme.py" "$CHOICE"
