#!/usr/bin/env bash
# gum-driven orchestrator for the CachyOS+SwayFX desktop. Wraps the existing,
# unmodified bootstrap.sh/setup.sh — it doesn't replace them, it sequences
# and narrates them, plus adds the one step they don't cover: picking a
# theme at the end.
#
# Usage:
#   ./install.sh                    full interactive flow
#   ./install.sh --skip-bootstrap   skip bootstrap.sh (iterating on this script itself)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SKIP_BOOTSTRAP=false
for arg in "$@"; do
  case "$arg" in
    --skip-bootstrap) SKIP_BOOTSTRAP=true ;;
    *) echo "unknown arg: $arg"; exit 1 ;;
  esac
done

if ! command -v gum &>/dev/null; then
  echo "==> Installing gum (needed for this script's UI) -- not present on a fresh install"
  sudo pacman -S --needed --noconfirm gum
fi

gum style --border normal --margin "1 0" --padding "1 3" --border-foreground 212 \
  "$(gum style --bold 'CachyOS + SwayFX')" \
  "Bootstrap -> setup -> theme. Nothing here touches a working system without asking first."

# Before running this: get the repo onto the machine yourself (git clone, or
# however you'd normally move files onto a fresh install) -- this script
# assumes you're already sitting inside it.

# ---------------------------------------------------------------------------
# 1. Bootstrap (system-level: packages, hibernation, greetd, UWSM, Tailscale)
# ---------------------------------------------------------------------------
if ! $SKIP_BOOTSTRAP; then
  if gum confirm "Run bootstrap.sh now? (packages, hibernation swapfile, greetd, UWSM session, Tailscale enable)"; then
    "$SCRIPT_DIR/bootstrap.sh"
  else
    gum style --foreground 3 "skipped bootstrap.sh — run it yourself before setup.sh will do much good."
  fi
fi

# ---------------------------------------------------------------------------
# 2. Setup (idempotent symlinking)
# ---------------------------------------------------------------------------
if gum confirm "Run setup.sh now? (symlinks every tracked config into ~/.config)"; then
  "$SCRIPT_DIR/setup.sh"
fi

# ---------------------------------------------------------------------------
# 3. Theme picker — the closing "make it yours" step. Same script you can
#    run any time later for day-to-day switching: theming/pick-theme.sh
# ---------------------------------------------------------------------------
if gum confirm "Pick a theme now?"; then
  "$SCRIPT_DIR/theming/pick-theme.sh"
fi

echo
gum style --foreground 2 "Done. Reboot to pick up hibernation/greetd/session changes from bootstrap.sh."
if gum confirm "Reboot now?"; then
  sudo reboot
fi
