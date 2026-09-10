# Cairn

A CachyOS + SwayFX desktop — packages, system-level setup, and every
tracked config, meant to take you from a fresh CachyOS install to a
working, themeable desktop. Self-contained: everything needed lives in
this repo.

## Installing on a fresh CachyOS system

The full path from a blank machine to a working themed desktop, in order.
Verified end-to-end on 2026-09-09 (see `VM-TESTING.md`).

1. **Run the base CachyOS installer** as normal (disk partitioning,
   username, etc). When it asks which desktop environment to install,
   choose **no desktop** — this repo installs and configures SwayFX
   itself via `packages.txt`/`bootstrap.sh`; picking KDE/GNOME/etc. here
   just installs a whole desktop stack this repo doesn't use and never
   removes. Pick whatever keyboard layout/variant you actually use (e.g.
   Dvorak) when the installer asks — `bootstrap.sh` later reads this back
   via `localectl` rather than assuming US QWERTY.

   The installer's own keyboard step does **not** offer modifier options
   like `ctrl:swapcaps`. If you use one, set it *before* running
   `bootstrap.sh` (see "Customizing the keyboard layout" below) — otherwise
   `bootstrap.sh` will faithfully carry forward "no option set" and your
   session ends up without it.

2. **Get this repo onto the machine and run the installer:**

   ```bash
   sudo pacman -S --needed git
   git clone https://github.com/skeptomai/cairn.git ~/cairn
   cd ~/cairn
   ./install.sh
   ```

   `install.sh` is driven by [`gum`](https://github.com/charmbracelet/gum)
   (a small CLI tool for interactive prompts/confirmations in shell
   scripts) — it self-installs `gum` first if missing (chicken-and-egg on
   a truly fresh system, since nothing else here has installed it yet),
   then narrates and confirms each step before doing anything: `bootstrap.sh`
   (packages, hibernation swapfile, mkinitcpio/limine, greetd, UWSM session,
   Tailscale enable, keyboard layout), `setup.sh` (symlinks every tracked
   config into `~/.config`), and a theme picker, finally offering to reboot
   for you.

   Prefer to run the pieces yourself instead:

   ```bash
   ./bootstrap.sh
   ./setup.sh
   python3 theming/apply-theme.py gray-blue   # or theming/pick-theme.sh for the interactive picker
   ```

3. **Reboot** (or accept `install.sh`'s own reboot prompt) — the new
   initramfs (`resume` hook) and boot cmdline (`resume=`/`resume_offset=`)
   only take effect on the next boot, and `greetd` needs to actually start
   to hand you the new `sway-uwsm` session.

4. **Log in at the greeter.** Its keyboard layout was rendered by
   `bootstrap.sh` from the same `localectl` snapshot as your real session,
   so they should already agree — if a correctly-typed password looks like
   a failed login, see the Troubleshooting section below.

That's it — you land in a fully symlinked, themed SwayFX session with
waybar, walker, swaync, and everything else in this repo already wired up.

### Customizing the keyboard layout

`bootstrap.sh` doesn't hardcode a layout — it reads whatever `localectl`
already reports and threads it through to both the greeter and the real
session. To set something the base installer's keyboard picker doesn't
expose (like swapping Ctrl and Caps Lock):

```bash
sudo localectl set-x11-keymap us pc105 dvorak ctrl:swapcaps   # example: Dvorak + swapped Ctrl/Caps
cd ~/cairn && ./bootstrap.sh    # re-run to regenerate the greeter + sway keyboard config from the new setting
```

Re-running `bootstrap.sh` is safe (idempotent) and only the keyboard step's
output will actually change if that's all you altered.

## Theming

`theming/` is a small hand-rolled cross-app theme switcher — one palette
TOML per preset (`gray-blue`, `gruvbox`, `nord`, `catppuccin-mocha`,
`everforest`), templated out to waybar/swaync/walker/alacritty/ghostty/
kdeglobals by `theming/apply-theme.py`. See `theming/README.md` for the
palette schema and how to add a new preset or app.

## Screensaver

`screensaver/` animates `screensaver/cairn.txt` (an ASCII "CAIRN" banner)
with a random [`ttfx`](https://github.com/Hypabolic/Hypa-TTFX) effect,
fullscreen, one instance per connected output — modeled on
[Omarchy](https://github.com/basecamp/omarchy)'s own screensaver, adapted
from Hyprland/`hyprctl` to Sway/`swaymsg`. Wired into `sway/config`'s
`swayidle` chain: it comes up after 150s idle, the actual lock screen takes
over at 300s (killing the screensaver first if it's still up), and any
input exits it immediately. Requires the `hypa-ttfx-bin` AUR package
(installed by `bootstrap.sh`), which provides `ttfx`.

Run it manually any time with `screensaver/launch-screensaver.sh`.

## Lock screen

The actual lock command (`lockscreen/lock.sh`) is
[`rustlock`](https://github.com/JorySeverijnse/rustlock), not `swaylock` —
a blurred/vignetted screenshot background, a themed hexagon ring indicator,
and a centered clock, instead of a flat color and a bare circle. `swaylock`
stays installed (`packages.txt`) purely as a trivial fallback; it's not
what any keybind or `swayidle` stage actually calls.

`rustlock` is built from source by `bootstrap.sh`, not installed from AUR,
because it needs one local patch:
`lockscreen/rustlock-disable-session-keys.patch` removes its upstream
`F1`/`F2`/`F3` → suspend/reboot/poweroff bindings, which fire with **no
password check and no confirmation** — a stray function-key press while
typing your password would otherwise reboot or power off the machine.
`bootstrap.sh` clones the latest `rustlock` master, applies the patch,
builds it, and installs the binary to `/usr/local/bin/rustlock` (ahead of
`/usr/bin` in `PATH`) every time it runs — there's no version pin, so
re-running `bootstrap.sh` picks up upstream fixes for free, patch
permitting. It also installs `lockscreen/rustlock.pam` to
`/etc/pam.d/rustlock` — required, or PAM falls back to `pam_deny` and
rejects every password, including a correct one.

## Emacs theming

Doom Emacs stays in sync with whatever theme is currently applied via
[`cairn-emacs-themer`](https://github.com/skeptomai/cairn-emacs-themer) —
a small elisp package (built on
[`autothemer`](https://github.com/jasonm23/autothemer)) that installs and
loads a generated theme file, both on Emacs startup and live while it's
already running.

The generation itself lives entirely in this repo, not in
`cairn-emacs-themer`: `theming/templates/emacs-theme.el.tmpl` is rendered
by `apply-theme.py` on every `theming/pick-theme.sh` switch, straight from
the palette dict already in hand — no shell/`awk` color extraction needed.
The rendered file is written to `emacs/cairn-theme.el` (tracked here, same
as every other app's generated theme output) and pushed to a running Emacs
via `emacsclient` — a no-op if Emacs isn't open.

On the Emacs side, add the package and point it at this repo's stable
location:

```elisp
;; packages.el
(package! cairn-themer
  :recipe (:host github :repo "skeptomai/cairn-emacs-themer" :files ("*.el")))

;; config.el
(use-package! cairn-themer
  :config
  (cairn-themer-add-theme-directory)
  (cairn-themer-sync-on-startup))
```

`cairn-themer-sync-on-startup` finds the current theme via
`~/.local/share/cairn-repo` — the same stable pointer `sway/config` already
uses for `screensaver`/`lockscreen` scripts, maintained by `setup.sh`
regardless of where this repo actually got cloned — so a fresh Emacs never
shows stale colors from a previous session. You do need `(server-start)`
running for the live-update side to have anything to push to.

See `cairn-emacs-themer`'s own `docs/PALETTE-DESIGN.md` for what makes a
palette render well through this face mapping (`selection` needs to be
tonally distinct from both `bg` and `fg` — `everforest` and `nord` among
this repo's presets currently fall short of that, a known gap, not yet
fixed).

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
├── screensaver/                 # ttfx-animated ASCII screensaver, launched by sway/config's swayidle
├── lockscreen/                   # rustlock config + build patch (see bootstrap.sh)
├── emacs/                        # generated cairn-theme.el, loaded via cairn-emacs-themer
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
`sway/local.conf.d/10-keyboard.conf` (in this repo checkout — that's where
`~/.config/sway/local.conf.d/10-keyboard.conf` resolves to once `setup.sh`
has symlinked `~/.config/sway`) — a mismatch here means what you type at
the greeter isn't what you think it is. Re-running `bootstrap.sh`
regenerates both from `localectl status`; if that's still wrong, fix it
with `localectl set-x11-keymap <layout> [variant] [options]` and re-run.

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
