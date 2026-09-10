# Emacs theming from Cairn's own theme system — shipped

Status: **implemented and verified** (2026-09-10). This doc now records what
actually shipped; see git history in `cairn`, `cairn-emacs-themer`, and the
private `dotfiles` repo for the detailed commits.

Context: `~/Projects/omarchy-emacs-themer` themes Doom Emacs from *Omarchy's*
theme system (see `docs/omarchy-theme-system.md`). Omarchy no longer runs on
this machine — [[cachyos-replaced-omarchy-on-omen]] — so that integration's
push side had nothing to trigger it. This replaced it with the equivalent
wired into `cairn`'s own `theming/apply-theme.py` pipeline.

## What shipped

- **[cairn-emacs-themer](https://github.com/skeptomai/cairn-emacs-themer)**
  — a fresh repo seeded from `omarchy-emacs-themer`'s code (not a
  GitHub-native fork; `omarchy-emacs-themer` itself is untouched). Purely
  the elisp consumer side now: `cairn-themer-install-and-load`,
  `cairn-themer-add-theme-directory`, `cairn-themer-sync-on-startup`. The
  Omarchy `theme-set` hook (`20-emacs.sh`, `install.sh`'s hook-install
  step) was dropped entirely, along with `tests/` and
  `docs/dynamic-conversion-plan.md` (both for an abandoned, never-shipped
  Omarchy-`neovim.lua`-parsing approach). `docs/PALETTE-DESIGN.md` was
  kept — the mapping/contrast principles are unchanged, only the color
  source moved.
- **`autothemer` confirmed still live**: `jasonm23/autothemer`, not
  archived, actively pushed, on MELPA — kept as the dependency.
- **`cairn-themer-theme-directory`** now defaults to a
  `doom-user-dir`-relative path (falling back to `user-emacs-directory`
  for non-Doom installs), per the confirmed decision to use Doom's own
  recommended convention.
- **`cairn-themer-current-theme-file`** defaults to
  `~/.local/share/cairn-repo/emacs/cairn-theme.el` — resolved through
  cairn's existing stable repo-location pointer (the same convention
  `sway/config` already uses for `screensaver`/`lockscreen` scripts).
  **This required a matching change to the private `dotfiles` repo's
  `cachyos/setup.sh`**, which didn't previously create that symlink at
  all (only the public `cairn` repo's own `setup.sh` did) — this machine
  runs `dotfiles/cachyos`, not a `cairn` clone, so the pointer now
  resolves to that checkout instead.
- **`theming/templates/emacs-theme.el.tmpl`** (in `cairn`, mirrored into
  the private `dotfiles` repo) — the ported face list, rendered directly
  from the palette dict `apply-theme.py` already has in hand. Two token
  gaps vs. the original ANSI-16 schema, resolved: no dedicated cursor
  color (uses `accent`) and no split selection foreground/background (uses
  plain `fg` paired with the single `selection` color — checked against a
  real palette where a dedicated pair would have resolved identically
  anyway).
- **`apply-theme.py`** gained `emacs_mode_tokens()` (mode-line/LSP-popup
  colors, computed per-palette from tokens already present — mirrors the
  existing `MODE_DEFAULTS` pattern for GTK/Kvantum, but computed rather
  than static, since these need the theme's actual colors) and a `TARGETS`
  entry writing `emacs/cairn-theme.el` and pushing it via `emacsclient`
  (a no-op if Emacs isn't running, via the existing `reload()` helper's
  graceful FileNotFoundError/timeout handling).
- **Doom config** (private `dotfiles` repo): `packages.el`/`config.el`
  swapped from `omarchy-themer` to `cairn-themer`. `server-start` was
  already unconditional elsewhere (the `claude-code-ide` MCP integration),
  so nothing new needed there.

## Verification performed

- Rendered the template directly and loaded the output in a throwaway
  batch Emacs with a freshly-fetched `autothemer` — confirmed the theme
  registers (`custom-theme-p`), enables (`custom-enabled-themes`), and
  produces correct face specs, for both a dark (`catppuccin-mocha`) and
  light (`catppuccin-latte`) preset.
- `doom sync` on the real machine — `cairn-themer` cloned, built, and
  byte-compiled via `straight.el` with no errors.
- Started a real, isolated Doom Emacs daemon (`--daemon=cairn-test`, so as
  not to touch the actual daily-driver session) and confirmed via its
  startup log and live `emacsclient` face-spec queries:
  - **Pull (startup sync)**: found the theme file through the
    `~/.local/share/cairn-repo` stable pointer and loaded it automatically
    — no manual step.
  - **Push (live update)**: `emacsclient -e '(cairn-themer-install-and-load ...)'`
    updated the running session's actual face colors immediately, with no
    restart.
- Programmatically checked all 5 existing presets against
  `PALETTE-DESIGN.md`'s "`selection` must be tonally distinct from both
  `bg` and `fg`" rule (RGB Euclidean distance). **Found two real flags**:
  `everforest` and `nord` both have `selection` quite close to `bg`
  (distance ~41–44, vs. 100+ for the other three) — meaning selected/
  region-highlighted text will show noticeably weaker contrast on those
  two themes specifically. Not fixed as part of this work; a real,
  actionable finding for whenever those two presets get attention, not an
  assumption carried over from the plan.

## Open items, not addressed here

- The `everforest`/`nord` `selection` contrast finding above.
- The real daily-driver Emacs session hasn't yet been restarted to pick up
  `cairn-themer` for actual use — validated via an isolated test daemon
  instead, deliberately, so as not to disrupt an active session mid-work.
