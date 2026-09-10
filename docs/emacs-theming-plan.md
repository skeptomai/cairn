# Plan: theme Emacs from Cairn's own theme system

Context: `~/Projects/omarchy-emacs-themer` themes Doom Emacs from *Omarchy's*
theme system (see `docs/omarchy-theme-system.md`). Omarchy no longer runs on
this machine — [[cachyos-replaced-omarchy-on-omen]] — so that integration's
push side (the `theme-set.d` hook) has had nothing to trigger it for some
time. This plan replaces it with the equivalent wired into `cairn`'s own
`theming/apply-theme.py` pipeline instead of Omarchy's.

**Good news going in**: Cairn's palette schema (`theming/palettes/*.toml`) is
already close to what the existing Emacs face-mapping expects — flat
`black`/`red`/`green`/`yellow`/`blue`/`magenta`/`cyan`/`white` plus
`bright-*` variants, and a `mode` field for light/dark, no separate
`light.mode` file needed. This is a more direct fit than Omarchy's *current*
semantic-only schema is (see the research doc's schema-drift section) — the
existing `20-emacs.sh` face list can be ported with light adaptation, not a
rewrite.

## Design

Mirror Cairn's existing pattern (`theming/templates/*.tmpl` rendered by
`apply-theme.py`, one `TARGETS` entry per app) instead of Omarchy's
hook-and-shell-variable approach — no `awk` parsing, no schema-fallback
dance, because `apply-theme.py` already has the full palette as a Python
dict before it ever touches a template.

1. **New template**: `theming/templates/emacs-theme.el.tmpl`, an
   `autothemer-deftheme` block using Cairn's `{{token}}` syntax directly
   (`{{bg}}`, `{{fg}}`, `{{red}}`, `{{bright-cyan}}`, etc.) — port the face
   list from `20-emacs.sh` (core faces, line numbers, search/match, syntax
   highlighting, mode-line, errors, diff, parens, LSP faces incl. the
   `lsp-ui-doc-frame-hook` trick, flycheck/flymake underlines) essentially
   as-is; it's a solid, already-tuned list.

2. **Light/dark mode-line and LSP-popup variants**: `20-emacs.sh` branches
   on a `light.mode` file to pick different mode-line/LSP-popup colors (see
   `PALETTE-DESIGN.md`'s table in the themer repo). Cairn's `apply-theme.py`
   already does exactly this kind of mode-keyed branching for GTK/Kvantum
   (`MODE_DEFAULTS` dict) — add an `EMACS_MODE_DEFAULTS`-style dict there,
   computing `ml-active-bg`, `ml-active-fg`, `ml-inactive-bg`,
   `ml-inactive-fg`, `ml-emphasis-fg`, `lsp-doc-bg`, `lsp-doc-fg`,
   `lsp-doc-header-bg`, `lsp-doc-header-fg` from Cairn's `bg`/`fg`/
   `selection`/`black`/`bright-black`/`blue` tokens, keyed by
   `tokens["mode"]`, merged into the token dict the same way
   `MODE_DEFAULTS[mode]` already is. Cairn has no `sel-fg`/`sel-bg` split
   (just one `selection`) — use `selection` for both roles, or add
   `hover-fg`/`hover-bg` (already in the palette schema) as the fg
   counterpart if plain `selection`-on-`selection` reads flat.

3. **Output path + `TARGETS` entry**: write to a fixed path, e.g.
   `~/.emacs.d/themes/cairn-theme.el` (or wherever
   `cairn-themer-theme-directory` defaults to — see below), overwritten on
   every switch, no per-preset history needed (unlike alacritty's
   per-preset files) since only "whatever's current" matters to a running
   Emacs. Reload step: if `emacsclient` exists and a server is running,
   call `(cairn-themer-install-and-load "<path>")` — a no-op cleanly if
   Emacs isn't running, matching this pipeline's existing `reload()` helper
   pattern (already swallows `FileNotFoundError`/timeouts for exactly this
   "app might not be running" case).

4. **Elisp side — fork, don't depend on, `omarchy-themer.el`**: its two
   generic functions (`*-install-and-load`, `*-add-theme-directory`) don't
   know or care that a theme file came from Omarchy — port them into cairn
   as `cairn-themer.el` (rename the `omarchy-*` prefix to `cairn-*` to avoid
   implying an Omarchy dependency that no longer exists), keep the
   `autothemer` dependency and the `lsp-ui-doc-frame-hook` integration
   as-is. Add `cairn-themer-sync-on-startup`, pointed at the fixed path from
   step 3 instead of Omarchy's `~/.local/state/omarchy/...` path.

5. **Doom config wiring** (in the *private* `dotfiles` repo's
   `doomemacs/doom/config.el` — personal editor config, out of `cairn`'s
   own scope same as other personal-app choices):
   ```elisp
   (use-package! cairn-themer
     :config
     (cairn-themer-add-theme-directory)
     (cairn-themer-sync-on-startup))
   ```
   plus `(server-start)` if not already present — required for the push
   side to reach a running session at all.

## Validation

- Run `theming/pick-theme.sh` (or `apply-theme.py <preset>` directly) with
  Emacs server running, confirm the running session updates live with no
  manual reload.
- Restart Emacs with a different preset already applied, confirm
  `cairn-themer-sync-on-startup` picks up the current one rather than
  showing stale colors.
- Spot-check each of Cairn's 5 existing presets (`gray-blue`, `gruvbox`,
  `nord`, `catppuccin-mocha`, `everforest`) against `PALETTE-DESIGN.md`'s
  contrast criteria (`selection` distinct from both `bg` and `fg`; ANSI
  colors spanning multiple hue families) before trusting all five will
  render well through this mapping — Cairn's palettes weren't designed
  against these specific constraints, so this is new information, not an
  assumption to carry over.

## Open questions for you

- **Keep `autothemer` as a dependency, or drop it for a plain
  `deftheme`/`custom-theme-set-faces`?** Keeping it is lower-risk (proven,
  same structure you already trust) but is one more package Doom has to
  manage. Dropping it removes a dependency at the cost of rewriting the
  palette-binding boilerplate `autothemer-deftheme` currently handles.
- **Archive `omarchy-emacs-themer`, or keep it around for other
  machines/future Omarchy use?** Its push side has nothing to trigger it on
  this machine anymore. If it's not used elsewhere, worth deciding whether
  this cairn integration fully replaces it or the two coexist.
- **`~/.emacs.d/themes/` as the output path** — confirm that's still
  where Doom expects `custom-theme-load-path` entries on this setup, or if
  it should be `doom-user-dir`-relative instead (the themer's own default
  is `(expand-file-name "themes/" doom-user-dir)`, not
  `user-emacs-directory`, in Doom's config.el usage — the package's
  built-in default customization differs slightly from Doom's own
  recommended override; worth picking one deliberately rather than
  inheriting whichever one happens to run first).
