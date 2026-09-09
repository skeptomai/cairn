# CLAUDE.md - Cairn Context for AI Assistants

## What this repo is

A CachyOS + SwayFX desktop stack: packages, system-level setup, and every
tracked config, meant to take someone from a fresh CachyOS install to a
working desktop. See `README.md` for the human-facing walkthrough — this
file is for AI-assistant-specific notes.

**Strategy**: configs live in this repo, symlinked into `~/.config/` by
`setup.sh`. System-level changes that can't be symlinks (packages,
mkinitcpio, limine cmdline, root-owned `/etc/greetd/*`) live in
`bootstrap.sh` instead.

## Adding a new tracked config

1. Move the real file/dir from `~/.config/<app>` into `<app>` (don't
   pre-`mkdir` the destination first — `mv` will nest it one level too deep
   if the target directory already exists; this bit us once already).
2. Symlink it back: `ln -sfn "$(realpath <app>)" ~/.config/<app>`.
3. Add a `link <app> <app>` line to `setup.sh`.
4. If it needs a new package, add it to `packages.txt`.
5. Note anything non-obvious in `README.md`.

## Things to not re-litigate

- **Hibernation** is real (disk-backed via `@swap` subvolume + swapfile),
  not zram — zram can't hold a hibernation image across a power cycle. Fully
  verified via a live hibernate/resume cycle on 2026-09-05. Don't suggest
  simplifying this to zram-only.
- **Hibernate needs three things together, or it silently fails to resume**
  (reads the image fine, fails validation, falls through to a cold boot —
  looks like hibernate "killed all processes"): the `nvidia-hibernate`/
  `nvidia-suspend`/`nvidia-resume` services enabled, `NVreg_
  PreserveVideoMemoryAllocations=1`, AND nvidia excluded from early KMS. The
  last one is the easy one to get wrong here specifically: CachyOS's `chwd`
  tool auto-generates `/etc/mkinitcpio.conf.d/10-chwd.conf` which force-adds
  nvidia to `MODULES` regardless of the base `mkinitcpio.conf` — don't edit
  that file (chwd regenerates it), the actual fix is a later-sorted
  `99-no-nvidia-early-kms.conf` drop-in that filters it back out. Full
  writeup: `docs/hibernate-swap-luks.md`. All three pieces are in
  `bootstrap.sh`. Regressed 2026-09-06 after the 2026-09-05 verification,
  once the dGPU was actively bound — hadn't hit the chwd interaction before.
- **Greetd's keyboard layout must match sway/config's own layout exactly**
  — a real, previously-confusing bug on the machine this was built on
  (correct passwords looking like failed logins because the greeter and
  the real session were reading different layouts), not an oversight.
  Both default to plain US QWERTY here; if you customize one, customize
  the other the same way.
- **`kdeglobals-file`** is named that way (not just `kdeglobals`) because it's
  a single file, not a directory, and the existing `link()` helper in
  `setup.sh` assumes directory-shaped sources elsewhere — check `setup.sh`
  before assuming a naming inconsistency is a mistake.
- **`swayosd` and `yazi`** are packages with no tracked config — that's
  correct, not missing. They run on packaged defaults here.

## Metadata

- **Distro**: CachyOS
- **Compositor**: SwayFX
