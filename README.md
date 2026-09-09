# Cairn

A CachyOS + SwayFX desktop — packages, system-level setup, and every
tracked config, meant to take you from a fresh CachyOS install to a
working, themeable desktop. Self-contained: everything needed lives in
this repo.

## Installing on a fresh CachyOS system

```bash
sudo pacman -S --needed git
git clone https://github.com/<you>/cairn.git ~/cairn
cd ~/cairn
./install.sh     # gum-driven: bootstrap.sh + setup.sh + a theme picker, narrated
```

Or run the pieces yourself:

```bash
./bootstrap.sh   # one-time: packages, hibernation swapfile, mkinitcpio/limine, greetd, UWSM session, Tailscale enable
./setup.sh       # idempotent: symlink dotfiles into ~/.config
python3 theming/apply-theme.py gray-blue   # pick a theme — see theming/README.md
```

Reboot after `bootstrap.sh` — the new initramfs (`resume` hook) and boot
cmdline (`resume=`/`resume_offset=`) only take effect on the next boot.

## Theming

`theming/` is a small hand-rolled cross-app theme switcher — one palette
TOML per preset (`gray-blue`, `gruvbox`, `nord`, `catppuccin-mocha`,
`everforest`), templated out to waybar/swaync/walker/alacritty/ghostty/
kdeglobals by `theming/apply-theme.py`. See `theming/README.md` for the
palette schema and how to add a new preset or app.

### What `bootstrap.sh` does, in order

1. Installs everything in `packages.txt` via `pacman`, plus the AUR
   packages listed in its own `AUR_PACKAGES` array via `yay`: `swayfx`
   (the official cachyos-repo binary -- still needs `yay` since it depends
   on `wlroots0.19`, which has no prebuilt package anywhere), `elephant-bin`
   + `elephant-desktopapplications-bin` (walker 2.x's actual search
   engine/provider — without these walker opens but silently finds nothing).
2. Sets up real disk-backed hibernation: creates the `@swap` btrfs subvolume
   (kept separate from the snapshotted `@` root — swapfiles inside a
   snapshotted subvolume are a known-bad btrfs pattern), a 32G NOCOW
   swapfile, adds the `resume` mkinitcpio hook, and adds
   `resume=UUID=...`/`resume_offset=...` to the Limine kernel cmdline.
   Confirmed working via a real hibernate → power-cycle → resume cycle
   on 2026-09-05.
3. Installs `/etc/greetd/config.toml` (rendered from `greetd/config.toml.tmpl`
   using `localectl`'s currently-configured layout — whatever you picked in
   the CachyOS installer, not a hardcoded default) and `/etc/greetd/regreet.toml`,
   and writes the same layout to `~/.config/sway/local.conf.d/10-keyboard.conf`
   so the real session matches. These have to agree, or correctly-typed
   passwords look like login failures — the greeter and your real session
   are separate processes reading separate layout config. Enables
   `greetd.service`.
4. Installs `/usr/share/wayland-sessions/sway-uwsm.desktop` — the session
   entry the greeter lists, launching Sway via UWSM.
5. Enables `tailscaled.service`. Joining the tailnet itself
   (`sudo tailscale up`) is an interactive step (browser auth) and is left
   as a manual follow-up, not scripted.

It's idempotent — every step checks current state first, so re-running it
after a partial failure is safe.

### What `setup.sh` does

Symlinks each subdirectory here into `~/.config/` (backing up anything real
it finds into `~/.config-backup-<timestamp>/` first). Re-run any time after
editing files here or in `~/.config` — since most of it is symlinks already,
this just fixes up anything that got unlinked.

`packages.txt` installs `zsh` and a few plugins, but no `.zshrc` is tracked
here — shell config is left to you, same as the other personal-app choices
noted below.

Includes `uwsm/` → `~/.config/uwsm`, which carries the
`SWAY_UNSUPPORTED_GPU=true` env var this machine's proprietary NVIDIA driver
needs to let Sway start at all (the old `sway --unsupported-gpu` CLI flag
was removed upstream in favor of this env var). **Both `bootstrap.sh` and
`setup.sh` are required for a working login** — the session *entry* is
installed by `bootstrap.sh` (root-owned, under `/usr/share`), but the env
var that entry actually needs at runtime only exists after `setup.sh` has
symlinked `uwsm/` into `~/.config`.

## Directory structure

```
cairn/
├── README.md, CLAUDE.md      # this file / AI-assistant context
├── packages.txt               # pacman + AUR package list
├── bootstrap.sh                # one-time system-level setup (see above)
├── setup.sh                    # idempotent dotfile symlinking
├── install.sh                   # gum-driven wrapper: bootstrap -> setup -> theme
├── theming/                     # cross-app theme switcher (palettes/, templates/, apply-theme.py)
├── sway/config                 # SwayFX compositor config
├── waybar/                     # status bar (config-sway.jsonc, style.css, theme.css)
├── walker/                     # app launcher
├── swaync/                     # notification daemon
├── wlogout/                    # power menu (layout defines Lock/Hibernate/Logout/Shutdown/Suspend/Reboot)
├── alacritty/                  # terminal
├── ghostty/                     # terminal (theme.conf is generated, see theming/)
├── nvim/                       # LazyVim-based neovim config
├── gtk-3.0/, Kvantum/          # GTK3 + Qt theming
├── kdeglobals-file              # -> symlinked to ~/.config/kdeglobals
├── fastfetch/                   # includes several logo/*.icon assets
├── uwsm/                       # -> symlinked to ~/.config/uwsm (SWAY_UNSUPPORTED_GPU env var)
├── wayland-sessions/            # sway-uwsm.desktop (root-owned at runtime,
│                                 #   installed by bootstrap.sh, not symlinked)
└── greetd/                     # config.toml, regreet.toml (root-owned at runtime,
                                 #   installed by bootstrap.sh, not symlinked)
```

Note: `swayosd` and `yazi` are in `packages.txt` but have no tracked config
here — both work fine on their packaged defaults on this machine.

## Not tracked here

- `/etc/greetd/wallpaper.png` — a 24MB binary, not worth committing. Copy one
  manually after a fresh install; `bootstrap.sh` will warn if it's missing.
- Hardware-specific UUIDs (`ROOT_UUID` in `bootstrap.sh`) are specific to
  *this* machine's btrfs filesystem — on a different machine, get the real
  UUID with `blkid` / `lsblk -f` and update the script before running it.

## Troubleshooting

### Hibernate resumes into a cold boot instead of the saved session

Most likely the swapfile's physical layout changed and `resume_offset` is
stale (a stale offset points at wrong data, so the resume image isn't
found). Re-check it:

```bash
sudo btrfs inspect-internal map-swapfile -r /swap/swapfile
```

If it differs from the value in `/etc/default/limine`, update it there and
re-run `sudo limine-update`. **Never run `btrfs balance` or
`btrfs filesystem defragment` on `@swap`** — either can silently move the
swapfile's extents and invalidate the offset.

To confirm whether a given hibernate/resume actually happened cleanly
(rather than hanging or cold-booting), check the boot log:

```bash
journalctl --list-boots
journalctl -k -b <prior-boot-idx> | tail -5     # should end with "PM: hibernation: hibernation entry"
journalctl -b <next-boot-idx> | grep -i resume  # should show "PM: Image signature found, resuming"
```

### Login at the greeter fails even with the right password

Check `/etc/greetd/config.toml`'s `XKB_DEFAULT_*` env vars actually match
`~/.config/sway/local.conf.d/10-keyboard.conf` — a mismatch here means what
you type at the greeter isn't what you think it is. Re-running
`bootstrap.sh` regenerates both from `localectl status`; if that's still
wrong, fix it with `localectl set-x11-keymap <layout> [variant] [options]`
and re-run.

### Waybar/walker/swaync not appearing or misconfigured

```bash
pgrep waybar
journalctl --user -u waybar   # if run as a user unit; otherwise check sway's exec log
```

Verify the relevant config is actually a symlink into this repo (not a
stray real file left over from a prior setup):

```bash
ls -la ~/.config/waybar
```

## Maintenance

```bash
cd ~/cairn
git add -A
git commit -m "Update configs: <description>"
git push
```

Because most files are symlinks, editing under `~/.config/` and editing
under this repo are the same file — commit whenever changes are ready.
