#!/usr/bin/env bash
# One-time system-level setup for the CachyOS + SwayFX desktop on this machine.
#
# This is NOT for dotfile symlinking — see setup.sh for that. This script only
# does the things that can't be a symlink: package installs, mkinitcpio hooks,
# fstab, bootloader cmdline, and files under /etc that must be owned by root.
#
# Idempotent: safe to re-run. Each step checks current state before writing.
#
# Background on *why* these steps exist is summarized inline in each step's
# own comments, so this script is a self-contained reference on its own.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# This script runs long enough (package builds especially) that the default
# ~15min sudo timestamp can expire mid-run, re-prompting for your password
# out of nowhere. Ask once up front, then keep it alive in the background
# for the life of this script instead.
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

echo "==> Installing official packages from packages.txt"
# jack2 conflicts with pipewire-jack (the correct provider of the jack API
# under our PipeWire audio setup) -- pacman refuses to auto-resolve real
# package conflicts even with --noconfirm (it just accepts the shown
# default, [y/N] here, and aborts the whole transaction), so remove it
# explicitly first if present.
if pacman -Qi jack2 &>/dev/null; then
  # A plain -R refuses: ffmpeg/fluidsynth/portaudio/vlc-plugin-jack/waybar
  # all depend on the "jack" API jack2 provides, and pipewire-jack (which
  # provides the identical API) isn't installed yet to satisfy them. -Rdd
  # force-removes ignoring that check; the packages.txt install right below
  # installs pipewire-jack, which immediately restores the same provides.
  # Standard jack2 -> pipewire-jack migration pattern.
  sudo pacman -Rdd --noconfirm jack2
fi
grep -vE '^\s*(#|$)' packages.txt | sudo pacman -S --needed --noconfirm -

# Installing the openssh package does NOT enable the service -- Arch never
# auto-enables units on install. Found 2026-09-07 on a genuinely virgin VM
# (installer only, bootstrap.sh never run): sshd was never enabled, so the
# documented guestfish remote-access trick (VM-TESTING.md) had no daemon to
# actually connect to -- that recipe was written for a VM that had already
# run bootstrap.sh at least once, not a truly fresh install.
echo "==> Enabling sshd"
sudo systemctl enable --now sshd

echo "==> Enabling ufw (rules mostly NOT scripted -- environment-specific, e.g."
echo "    the libvirt/virbr0 rules in VM-TESTING.md -- add those by hand)"
# ssh is the one rule scripted here -- ufw's own default-deny-incoming policy
# would otherwise silently lock out remote access the moment this runs,
# since openssh is installed but nothing has allowed it through yet.
sudo ufw allow ssh
sudo systemctl enable --now ufw

# elephant-bin / elephant-desktopapplications-bin: walker 2.x's actual search
# engine + provider plugin — without these, walker's window opens but finds
# nothing.
# elephant-menus-bin: elephant's "Custom Menus" provider -- the walker-based
# theme picker (elephant/menus/cachyos_themes.lua) needs this to
# load Lua menu definitions at all; without it, `walker -m menus:...` has
# nothing to talk to.
#
# wlroots0.19 + swayfx: swayfx is the official `cachyos`-repo *binary*
# package (not the AUR `swayfx-git` this used to be -- that forced building
# wlroots0.19 AND scenefx-git from source, ~15-25s each, for zero benefit:
# scenefx0.5 is already an official prebuilt package). It still needs
# wlroots0.19 built from AUR first though (no prebuilt package anywhere) --
# found 2026-09-08 that `yay -S swayfx` does NOT auto-resolve/build a plain
# repo package's missing AUR dependency the way it does for an AUR target;
# it only did on the dev machine because wlroots0.19 already happened to be installed
# from an earlier session. wlroots0.19 has to be its own explicit entry,
# listed (and thus built) before swayfx. (A chaotic-aur build of swayfx
# needs zero building at all, depending on wlroots0.20 instead -- but
# chaotic-aur isn't a repo this box configures anywhere, found the same day
# blocking an entire fresh install with "database not found: chaotic-aur".
# Don't switch back to that without adding real repo setup here first.)
AUR_PACKAGES=(
  wlroots0.19 swayfx elephant-bin elephant-desktopapplications-bin elephant-menus-bin
  # bibata-cursor-theme-bin: Bibata-Modern-Ice, this box's actual cursor
  # theme -- AUR-packaged, installs system-wide to /usr/share/icons.
  bibata-cursor-theme-bin
  # tela-circle-icon-theme-all-git: Tela-circle-grey (this box's icon
  # theme, referenced by gtk-3.0/settings.ini + kdeglobals.tmpl) plus every
  # other Tela-circle color variant. The "-all" variant installs every
  # color (grey/dracula/pink/purple/black/etc.) in one go.
  tela-circle-icon-theme-all-git
  # hypa-ttfx-bin: provides the `ttfx` binary screensaver/run-screensaver.sh
  # calls to animate screensaver/cairn.txt -- the same tool (same CLI flags)
  # Omarchy's own screensaver uses under the hood.
  hypa-ttfx-bin
)

if ! command -v yay &>/dev/null; then
  echo "==> Installing yay (AUR helper) -- not present on a fresh CachyOS install"
  YAY_TMP="$(mktemp -d)"
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$YAY_TMP/yay-bin"
  (cd "$YAY_TMP/yay-bin" && makepkg -si --noconfirm </dev/null)
  rm -rf "$YAY_TMP"
fi

echo "==> Installing AUR packages (via yay): ${AUR_PACKAGES[*]}"
# yay's --noconfirm does NOT suppress pacman's own final
# ":: Proceed with installation? [Y/n]" transaction prompt for the just-built
# packages -- found 2026-09-07 running this remotely over SSH: with stdin
# left open (piped through a monitoring wrapper) and nothing ever answering
# that prompt, the whole run silently stalled there forever, and everything
# after it in this script never ran, no error surfaced anywhere. `</dev/null`
# makes that prompt hit EOF and auto-select its capital-letter default (Y),
# so this can't silently stall again regardless of how bootstrap.sh itself
# gets invoked (interactively, piped, or through remote automation).
for pkg in "${AUR_PACKAGES[@]}"; do
  if ! pacman -Qi "$pkg" &>/dev/null; then
    yay -S --needed --noconfirm "$pkg" </dev/null
  else
    echo "    already installed: $pkg"
  fi
done

echo "==> Chromium managed-policy directory (owned by \$USER, not root -- so"
echo "    apply-theme.py can retint the browser on every switch without sudo)"
sudo mkdir -p /etc/chromium/policies/managed
sudo chown "$USER":"$USER" /etc/chromium/policies/managed

# ---------------------------------------------------------------------------
# Hibernation: real disk-backed swapfile + resume kernel params
#
# Why: wlogout's Hibernate button calls `systemctl hibernate`, but that has
# nothing to hibernate TO unless there's a swap device the kernel can write
# a memory image to and find again at boot. zram is RAM-backed and volatile,
# so a zram-only system can never actually hibernate.
#
# This box's root fs is btrfs with snapper auto-snapshots on the @ subvolume.
# A swapfile living inside a *snapshotted* subvolume is a known-bad btrfs
# pattern, so the swapfile lives in its own non-snapshotted sibling
# subvolume (@swap), matching how @home/@cache/@log are already laid out.
#
# Confirmed working end-to-end via a real hibernate -> power-cycle -> resume
# cycle on 2026-09-05 (verified after the fact via `journalctl --list-boots`
# + `journalctl -k`: hibernation entry logged at the end of one boot, then
# `PM: Image signature found, resuming` / `PM: hibernation: resume from
# hibernation` at the start of the next).
# ---------------------------------------------------------------------------

echo "==> Setting up hibernation swapfile (@swap subvolume)"

ROOT_UUID="$(findmnt -no UUID /)"   # must be computed fresh -- differs on every install, don't hardcode

if ! findmnt /swap &>/dev/null; then
  if ! sudo btrfs subvolume list / | grep -q ' @swap$'; then
    echo "    creating @swap subvolume"
    # @swap doesn't exist yet, so it can't be reached through the normal /
    # mount (that only exposes the @ subvolume). Mount the btrfs top level
    # (subvolid=5) at a scratch point, create @swap as its sibling, unmount.
    ROOT_DEVICE="$(findmnt -no SOURCE / | sed 's/\[.*\]//')"
    TMP_MNT="$(mktemp -d)"
    sudo mount -o subvolid=5 "${ROOT_DEVICE}" "${TMP_MNT}"
    sudo btrfs subvolume create "${TMP_MNT}/@swap"
    sudo umount "${TMP_MNT}"
    rmdir "${TMP_MNT}"
  fi
  sudo mkdir -p /swap
  grep -q '/swap ' /etc/fstab || echo "UUID=${ROOT_UUID} /swap          btrfs   subvol=/@swap,defaults,noatime 0 0" | sudo tee -a /etc/fstab
  sudo mount /swap
fi

if [ ! -f /swap/swapfile ]; then
  # sized off actual RAM (rounded up a GiB), not hardcoded -- a hardcoded 32G
  # (sized for the dev machine's real ~30GB RAM) doesn't fit a small test VM's disk.
  # Hibernation needs swap >= RAM to hold the full image.
  MEM_KB="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
  SWAP_SIZE_G="$(( (MEM_KB + 1024*1024 - 1) / (1024*1024) ))G"
  echo "    creating /swap/swapfile (${SWAP_SIZE_G}, NOCOW)"
  sudo touch /swap/swapfile
  sudo chattr +C /swap/swapfile   # NOCOW must be set BEFORE data is written — btrfs requirement for swapfiles
  sudo chmod 600 /swap/swapfile
  sudo fallocate -l "${SWAP_SIZE_G}" /swap/swapfile
  sudo mkswap /swap/swapfile
fi

grep -q '/swap/swapfile' /etc/fstab || echo "/swap/swapfile                            none           swap    defaults 0 0" | sudo tee -a /etc/fstab
sudo swapon /swap/swapfile 2>/dev/null || true   # already active is fine

echo "    resolving resume_offset (do NOT hardcode — it depends on this file's physical extents)"
RESUME_OFFSET="$(sudo btrfs inspect-internal map-swapfile -r /swap/swapfile)"
echo "    resume_offset = ${RESUME_OFFSET}"

if ! grep -q '^HOOKS=.*resume' /etc/mkinitcpio.conf; then
  echo "    adding 'resume' hook to mkinitcpio.conf (after plymouth, before filesystems)"
  sudo sed -i 's/\(plymouth\) \(.*\)filesystems/\1 \2resume filesystems/' /etc/mkinitcpio.conf
  sudo mkinitcpio -P
fi

if ! grep -q "resume=UUID=${ROOT_UUID}" /etc/default/limine; then
  echo "    adding resume= / resume_offset= to limine kernel cmdline"
  sudo sed -i "s|\(KERNEL_CMDLINE\[default\]+=\"[^\"]*\)\"|\1 resume=UUID=${ROOT_UUID} resume_offset=${RESUME_OFFSET}\"|" /etc/default/limine
  sudo limine-update
fi

cat <<'EOF'
    NOTE: if resume_offset ever needs recomputing (e.g. after any btrfs
    balance/defrag touched @swap — don't do that on purpose), re-run:
      sudo btrfs inspect-internal map-swapfile -r /swap/swapfile
    then update the resume_offset= value in /etc/default/limine and
    re-run `sudo limine-update`.
EOF

# ---------------------------------------------------------------------------
# NVIDIA hybrid-graphics hibernate support
#
# Why: this machine has an NVIDIA dGPU (Optimus-style, alongside the Intel
# iGPU) with the proprietary/open kernel modules loaded. Without these three
# services, the driver never saves/restores its own VRAM and pinned-memory
# state across hibernation, and NVreg_PreserveVideoMemoryAllocations isn't
# set either — the kernel reads the hibernation image back fine (no I/O
# error) but fails validation ("PM: hibernation: Failed to load image,
# recovering" / "resume failed (-5)"), silently falling through to a cold
# boot that looks like hibernate just killed every running process. Bit us
# for real on 2026-09-06 — the earlier "hibernate verified working" pass
# on 2026-09-05 predates the dGPU being actively bound.
# ---------------------------------------------------------------------------

if lspci -k | grep -qi nvidia; then
  echo "==> NVIDIA GPU detected -- enabling hibernate/suspend services"
  sudo systemctl enable nvidia-hibernate.service nvidia-suspend.service nvidia-resume.service

  if [ ! -f /etc/modprobe.d/nvidia-power-management.conf ]; then
    echo "    adding NVreg_PreserveVideoMemoryAllocations modprobe option"
    echo 'options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp' | sudo tee /etc/modprobe.d/nvidia-power-management.conf
  fi

  if [ ! -f /etc/mkinitcpio.conf.d/99-no-nvidia-early-kms.conf ]; then
    echo "    excluding nvidia modules from early KMS (CachyOS's chwd tool force-adds"
    echo "    them via /etc/mkinitcpio.conf.d/10-chwd.conf, which conflicts with"
    echo "    NVreg_PreserveVideoMemoryAllocations during hibernate resume -- see"
    echo "    docs/hibernate-swap-luks.md. Don't edit 10-chwd.conf itself, chwd"
    echo "    regenerates it -- filter the nvidia entries back out in a later file)"
    cat <<'EOF' | sudo tee /etc/mkinitcpio.conf.d/99-no-nvidia-early-kms.conf
mapfile -t MODULES < <(printf '%s\n' "${MODULES[@]}" | grep -vE '^nvidia(_drm|_modeset|_uvm)?$')
EOF
  fi

  sudo mkinitcpio -P
else
  echo "==> No NVIDIA GPU detected -- skipping NVIDIA hibernate workaround (see docs/hibernate-swap-luks.md)"
fi

# ---------------------------------------------------------------------------
# Keyboard layout: read whatever you already chose in the CachyOS installer
# (via localectl) instead of hardcoding one -- an earlier version of this
# script hardcoded "us" here, which silently overrode a Dvorak (or any
# other non-US) layout chosen at install time. Both the greeter and the
# real sway session need the SAME layout or a correctly-typed password at
# the greeter looks like a failed login (they're separate processes, so
# this can't just be set once and inherited).
# ---------------------------------------------------------------------------
XKB_LAYOUT="$(localectl status | sed -n 's/^\s*X11 Layout:\s*//p')"
XKB_VARIANT="$(localectl status | sed -n 's/^\s*X11 Variant:\s*//p')"
XKB_OPTIONS="$(localectl status | sed -n 's/^\s*X11 Options:\s*//p')"
XKB_LAYOUT="${XKB_LAYOUT:-us}"
echo "==> Detected keyboard layout: $XKB_LAYOUT${XKB_VARIANT:+ (variant: $XKB_VARIANT)}${XKB_OPTIONS:+ (options: $XKB_OPTIONS)}"

XKB_ENV="XKB_DEFAULT_LAYOUT=$XKB_LAYOUT"
[ -n "$XKB_VARIANT" ] && XKB_ENV="$XKB_ENV XKB_DEFAULT_VARIANT=$XKB_VARIANT"
[ -n "$XKB_OPTIONS" ] && XKB_ENV="$XKB_ENV XKB_DEFAULT_OPTIONS=$XKB_OPTIONS"

echo "==> Installing greetd config (keyboard layout matched to the session below)"
sed "s#{{XKB_ENV}}#$XKB_ENV#" greetd/config.toml.tmpl | sudo tee /etc/greetd/config.toml >/dev/null
sudo install -m 644 greetd/regreet.toml /etc/greetd/regreet.toml
# One of the user's own stone-creature theme photos (see theming/palettes/
# stone-creature/backgrounds/5-goyle5.jpg) -- tracked here like every other
# theme background, so a fresh install gets a real greeter wallpaper with no
# manual step. An earlier version of this file was a 24MB uncompressed PNG
# copied in by hand and deliberately left untracked; this one is a properly
# sized JPEG (~950KB), in line with every other tracked wallpaper.
sudo install -m 644 greetd/wallpaper.jpg /etc/greetd/wallpaper.jpg

echo "==> Writing matching sway keyboard layout to sway/local.conf.d/ (not tracked in git -- see sway/config's tail)"
# Written into the repo checkout itself (not $HOME/.config/sway/local.conf.d)
# because on a genuinely fresh install this runs *before* setup.sh has
# turned ~/.config/sway into a symlink to this checkout -- writing through
# $HOME/.config would land in a plain real directory that setup.sh then
# backs up and replaces, stranding this file. Writing here means it's
# already in place once the symlink exists, regardless of run order.
mkdir -p "sway/local.conf.d"
{
  echo "input \"type:keyboard\" {"
  echo "    xkb_layout $XKB_LAYOUT"
  [ -n "$XKB_VARIANT" ] && echo "    xkb_variant $XKB_VARIANT"
  [ -n "$XKB_OPTIONS" ] && echo "    xkb_options $XKB_OPTIONS"
  echo "}"
} > "sway/local.conf.d/10-keyboard.conf"
sudo systemctl enable greetd.service

# ---------------------------------------------------------------------------
# UWSM session entry: uses executable-name mode (Exec=uwsm start -e -D sway
# sway) deliberately, not a sibling .desktop-ID reference, so it has zero
# dependency on any other file existing. The matching
# SWAY_UNSUPPORTED_GPU=true env var (below) is what actually lets sway start
# on this machine's proprietary NVIDIA driver -- the old `--unsupported-gpu`
# CLI flag doesn't exist on this wlroots build.
# ---------------------------------------------------------------------------

echo "==> Installing sway-uwsm.desktop session entry"
sudo install -m 644 wayland-sessions/sway-uwsm.desktop /usr/share/wayland-sessions/sway-uwsm.desktop

echo "    NOTE: the SWAY_UNSUPPORTED_GPU=true env var this session needs lives in"
echo "    ~/.config/uwsm/env-sway.d/ -- that's a plain ~/.config symlink, so run"
echo "    setup.sh (not this script) to put it in place."

# The `sway` package itself ships a competing /usr/share/wayland-sessions/
# sway.desktop (plain `Exec=sway`, no uwsm) that shows up in the greeter's
# session list right alongside ours. Picking it (by accident, or because
# it happens to sort first) silently skips uwsm entirely -- sway itself
# starts and looks basically fine, but NOTHING that's WantedBy=
# graphical-session.target ever starts (elephant/walker/waybar all
# silently absent, no error anywhere). Found 2026-09-07 on the VM after a
# real reboot + greeter login picked the wrong one. This had already been
# hand-fixed on the dev machine once before (a stale sway.desktop.disabled from
# 2026-06 proves it) but a later `sway` package update simply re-shipped
# the file, since a rename isn't durable against reinstalls -- hence
# doing this here, every run, instead of as a one-off.
if [ -f /usr/share/wayland-sessions/sway.desktop ]; then
  echo "==> Disabling the stock (non-uwsm) sway.desktop session entry"
  sudo mv /usr/share/wayland-sessions/sway.desktop /usr/share/wayland-sessions/sway.desktop.disabled
fi

# ---------------------------------------------------------------------------
# Lock screen: rustlock, built from source (not the AUR package) because it
# needs a small local patch -- upstream binds F1/F2/F3 to
# suspend/reboot/poweroff on the LOCK SCREEN with no auth and no
# confirmation, so a stray function-key press while typing your password
# reboots or powers off the machine. lockscreen/rustlock-disable-session-keys.patch
# removes those three key bindings; everything else about rustlock is
# unpatched. Re-run this block any time to pick up upstream fixes -- it
# always rebuilds from the latest master, there's no version pin.
#
# The PAM service file is required -- without /etc/pam.d/rustlock, PAM
# falls back to /etc/pam.d/other (auth required pam_deny.so), so rustlock
# rejects every password including a correct one, with no error beyond a
# generic auth failure. Found the hard way 2026-09-09 after rebuilding the
# binary by hand outside this script and skipping this install step.
# ---------------------------------------------------------------------------

echo "==> Building rustlock (lock screen) from source with local patch applied"
RUSTLOCK_PATCH="$PWD/lockscreen/rustlock-disable-session-keys.patch"
RUSTLOCK_TMP="$(mktemp -d)"
git clone --depth 1 https://github.com/JorySeverijnse/rustlock.git "$RUSTLOCK_TMP/rustlock"
(
  cd "$RUSTLOCK_TMP/rustlock"
  git apply "$RUSTLOCK_PATCH"
  cargo build --release
)
sudo install -Dm755 "$RUSTLOCK_TMP/rustlock/target/release/rustlock" /usr/local/bin/rustlock
rm -rf "$RUSTLOCK_TMP"
sudo install -Dm644 lockscreen/rustlock.pam /etc/pam.d/rustlock

# ---------------------------------------------------------------------------
# Tailscale: enable the daemon, but joining the tailnet is an interactive
# step (opens a browser to authenticate) that can't safely be scripted here.
# ---------------------------------------------------------------------------

echo "==> Enabling tailscaled.service"
sudo systemctl enable --now tailscaled.service
if ! tailscale status &>/dev/null; then
  echo "    NOTE: not yet joined to a tailnet -- run 'sudo tailscale up' manually."
fi

echo "==> bootstrap.sh done. Run setup.sh next to symlink dotfiles into ~/.config."
