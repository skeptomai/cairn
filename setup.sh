#!/bin/bash
# CachyOS + SwayFX dotfiles setup — symlinks this directory's configs into
# ~/.config. For system-level package installs and one-time /etc changes
# (hibernation swapfile, mkinitcpio, limine, greetd), run bootstrap.sh first.
#
# Safe to re-run: existing real files are backed up once, existing correct
# symlinks are left alone.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"

# A stable, location-independent pointer to wherever this repo actually got
# cloned -- clone it anywhere you like. Anything that needs to find the
# repo's own files at runtime (elephant/menus/*.lua, notably) reads this
# symlink instead of hardcoding a path.
mkdir -p "$HOME/.local/share"
ln -sfn "$SCRIPT_DIR" "$HOME/.local/share/cairn-repo"

echo -e "${BLUE}=== CachyOS/Sway dotfiles setup ===${NC}"

link() {
  local src="$SCRIPT_DIR/$1" dest="$CONFIG_DIR/$2"
  if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(realpath "$src")" ]; then
    echo "OK      $dest"
    return
  fi
  if [ -e "$dest" ]; then
    mkdir -p "$BACKUP_DIR"
    echo -e "${YELLOW}BACKUP  $dest -> $BACKUP_DIR${NC}"
    mv "$dest" "$BACKUP_DIR/"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -sfn "$src" "$dest"
  echo -e "${GREEN}LINKED  $dest${NC}"
}

link sway sway
link waybar waybar
link walker walker
link wlogout wlogout
link alacritty alacritty
link ghostty ghostty
link gtk-3.0 gtk-3.0
link Kvantum Kvantum
link fastfetch fastfetch
link swaync swaync
link nvim nvim
link kdeglobals-file kdeglobals
link uwsm uwsm
link btop btop
link mimeapps.list mimeapps.list
link chromium-flags.conf chromium-flags.conf
link elephant/menus elephant/menus
# Only quickcss.css is symlinked -- the rest of ~/.config/vesktop/settings/
# (settings.json, session data, caches) is live Vesktop/Vencord state, not
# something this repo should own or overwrite.
link vesktop/quickcss.css vesktop/settings/quickCss.css

# nvim-ghostty.desktop: default text/plain handler (ghostty -e nvim), and
# thunar/nvim-ghostty as the mimeapps.list defaults for inode/directory and
# text/plain -- both previously pointed at org.kde.dolphin.desktop and
# org.gnome.TextEditor.desktop, neither of which is even installed here, so
# e.g. Ghostty's own "Open Config" context-menu action silently did nothing
# (xdg-open had no working handler to resolve to). Found 2026-09-07 while
# testing that exact menu action in the VM -- turned out to be broken on
# the dev machine itself too, just never previously exercised.
APPLICATIONS_DIR="$HOME/.local/share/applications"
mkdir -p "$APPLICATIONS_DIR"
if [ -L "$APPLICATIONS_DIR/nvim-ghostty.desktop" ] && [ "$(readlink -f "$APPLICATIONS_DIR/nvim-ghostty.desktop")" = "$(realpath "$SCRIPT_DIR/applications/nvim-ghostty.desktop")" ]; then
  echo "OK      $APPLICATIONS_DIR/nvim-ghostty.desktop"
else
  ln -sfn "$(realpath "$SCRIPT_DIR/applications/nvim-ghostty.desktop")" "$APPLICATIONS_DIR/nvim-ghostty.desktop"
  echo -e "${GREEN}LINKED  $APPLICATIONS_DIR/nvim-ghostty.desktop${NC}"
fi
update-desktop-database "$APPLICATIONS_DIR" 2>/dev/null || true

# elephant.service: walker 2.x's actual search backend daemon (see
# elephant-bin/elephant-desktopapplications-bin in bootstrap.sh's
# AUR_PACKAGES) -- without this enabled, walker's window opens but just
# shows "Waiting for elephant..." forever. This was never tracked here
# before 2026-09-06 -- it only worked on the dev machine because someone had enabled it
# by hand at some point; a fresh install had no idea it needed to exist.
link elephant.service systemd/user/elephant.service
link waybar.service systemd/user/waybar.service
link walker.service systemd/user/walker.service
systemctl --user daemon-reload
# elephant only scans its providers (incl. the menus/ dir's *.lua files,
# e.g. cachyos_themes.lua) once at startup, never hot-reloads -- found
# 2026-09-07 on the VM, where elephant had been running since boot, from
# before this script's *first* run had even created the elephant/menus
# symlink, so the walker theme picker came up silently empty ("missing
# provider"=menus in its journal) despite everything on disk being
# correct. `enable --now` alone is a no-op if the unit's already active,
# so explicitly restart every re-run -- cheap (a few ms), and the only way
# a *newly added* palette/menu actually gets picked up without a manual
# `systemctl --user restart elephant`.
systemctl --user enable elephant.service
systemctl --user restart elephant.service
# stop any leftover plain-exec'd waybar (pre-2026-09-07 sway/config launched
# it directly) before starting the managed service, so we don't end up with
# two waybar processes racing for the same layer-shell surface.
killall waybar 2>/dev/null || true
systemctl --user enable --now waybar.service
# walker's own sway/config `exec walker --gapplication-service` line was a
# plain exec with no restart-on-crash -- found 2026-09-07 when it had
# silently died on the dev machine (uptime days, not a fresh session) and the
# elephant-backed theme-picker menu came up empty with no error, same
# symptom class as the undocumented elephant.service gap above. Same fix:
# a real restart-on-failure service. Stop any leftover plain-exec'd
# instance first, same reasoning as waybar above.
killall walker 2>/dev/null || true
systemctl --user enable walker.service
# also always-restart: walker holds a connection to elephant made at its
# own startup, so if elephant was just restarted above, walker needs to
# reconnect too or it keeps talking to the now-dead old elephant process.
systemctl --user restart walker.service

# packages.txt installs zsh + a few plugins (autosuggestions, p10k, etc.),
# but .zshrc itself is deliberately not tracked here -- shell config is as
# personal as which apps you use day to day (see packages.txt's own note on
# why personal app choices aren't tracked). Bring your own .zshrc.

# Replay the last-applied theme preset, if any. Every OTHER theme-driven
# file above is already correct just from symlinking -- whatever preset was
# last applied is what's committed. But apply-theme.py also writes live
# gsettings/dconf state (org.gnome.desktop.interface color-scheme/gtk-theme
# -- see apply_gsettings_mode, needed because adw-gtk3 syncs with that
# system-wide preference instead of always rendering light) that symlinking
# can't touch at all. Without this, a fresh install that skips install.sh's
# "pick a theme" step would leave dconf at whatever a fresh system
# defaults to, mismatched with the committed theme files -- found
# 2026-09-07 while fixing exactly that mismatch by hand on an
# already-installed machine.
CURRENT_PRESET_FILE="$SCRIPT_DIR/theming/.current-preset"
if [ -f "$CURRENT_PRESET_FILE" ]; then
  PRESET="$(cat "$CURRENT_PRESET_FILE")"
  echo "==> Reapplying theme '$PRESET' (syncs gsettings/dconf; symlinked files are already correct)"
  python3 "$SCRIPT_DIR/theming/apply-theme.py" "$PRESET" >/dev/null
fi

echo
echo -e "${BLUE}Done.${NC} greetd/regreet configs under /etc are handled by bootstrap.sh (root-owned, not symlinked)."
