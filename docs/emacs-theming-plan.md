# Plan: theme Emacs from Cairn's own theme system

Context: `~/Projects/omarchy-emacs-themer` themes Doom Emacs from *Omarchy's*
theme system (see `docs/omarchy-theme-system.md`). Omarchy no longer runs on
this machine — [[cachyos-replaced-omarchy-on-omen]] — so that integration's
push side (the `theme-set.d` hook) has had nothing to trigger it for some
time. This plan replaces it with the equivalent wired into `cairn`'s own
`theming/apply-theme.py` pipeline instead.

**Good news going in**: Cairn's palette schema (`theming/palettes/*.toml`) is
already close to what the existing Emacs face-mapping expects — flat
`black`/`red`/`green`/`yellow`/`blue`/`magenta`/`cyan`/`white` plus
`bright-*` variants, and a `mode` field for light/dark, no separate
`light.mode` file needed. This is a more direct fit than Omarchy's *current*
semantic-only schema is (see the research doc's schema-drift section) — the
existing `20-emacs.sh` face list can be ported with light adaptation, not a
rewrite.

## Decisions (confirmed 2026-09-10)

- **Keep `autothemer`** as the theme-definition engine, pending a quick
  liveness check — reuse the existing DSL rather than rewriting the face
  list against plain `deftheme`.
- **`omarchy-emacs-themer` stays untouched.** No changes, no archiving.
- **Theme directory**: `(expand-file-name "themes/" doom-user-dir)` —
  Doom's own recommended convention — not the package's original
  `user-emacs-directory` default.
- **New repo**: `cairn-emacs-themer`, seeded from `omarchy-emacs-themer`'s
  current code as a fresh history (same pattern as `cairn` itself being
  genericized from the private `dotfiles` repo) — not a GitHub-native fork.
  This repo becomes purely the *elisp* side (install/load a theme file,
  sync on startup). The Omarchy-hook push side (`20-emacs.sh`, the
  `~/.config/omarchy/hooks/` install step) is dropped entirely — the
  *generation* of the theme file moves into `cairn`'s own
  `theming/apply-theme.py`.

## Phases

### Phase 0 — Sanity check
- [ ] Confirm `autothemer` is still a live, installable package (not
      abandoned/broken) before building on it.

### Phase 1 — Seed `cairn-emacs-themer`
- [ ] Create the `cairn-emacs-themer` GitHub repo.
- [ ] Copy `omarchy-emacs-themer`'s current code in as a fresh initial
      commit (no linked history), matching how `cairn` itself was created.

### Phase 2 — Rebrand the elisp package
- [ ] Rename `omarchy-themer-*` → `cairn-themer-*` throughout
      (`cairn-themer.el`, package metadata, `README.md`).
- [ ] Change the theme-directory default to the `doom-user-dir`-relative
      path (decision above).
- [ ] Point `cairn-themer-sync-on-startup` at wherever `cairn`'s pipeline
      will write the live theme file (decided during Phase 4).

### Phase 3 — Drop the Omarchy-hook push side
- [ ] Remove `20-emacs.sh` and the `~/.config/omarchy/hooks/` install step
      from `install.sh` (or repurpose `install.sh` for whatever, if
      anything, `cairn-emacs-themer` still needs installed standalone).
- [ ] Update `README.md`/`CLAUDE.md` to describe the new cairn-driven push
      mechanism instead of the Omarchy hook one.

### Phase 4 — Build the generation side in `cairn`
- [ ] New `theming/templates/emacs-theme.el.tmpl`, porting `20-emacs.sh`'s
      face list (core faces, line numbers, search/match, syntax
      highlighting, mode-line, errors, diff, parens, LSP faces incl. the
      `lsp-ui-doc-frame-hook` trick, flycheck/flymake underlines) to
      Cairn's `{{token}}` syntax.
- [ ] Add light/dark mode-line & LSP-popup variant tokens to
      `apply-theme.py` (an `EMACS_MODE_DEFAULTS`-style dict alongside the
      existing `MODE_DEFAULTS`, keyed by `tokens["mode"]`) — Cairn has no
      `sel-fg`/`sel-bg` split (just one `selection`), decide there whether
      to reuse `selection` for both roles or bring in `hover-fg`/`hover-bg`
      as the counterpart.
- [ ] Add a `TARGETS` entry: render the template, write it to the Phase-2
      output path, reload via `emacsclient -e '(cairn-themer-install-and-load "...")'`
      guarded the same way this pipeline already guards other
      maybe-not-running apps.

### Phase 5 — Wire up Doom config
- [ ] In the *private* `dotfiles` repo's `doomemacs/doom/config.el`
      (personal editor config, out of `cairn`'s own scope): add
      `cairn-emacs-themer` to `packages.el`, add the `use-package!` block
      (`cairn-themer-add-theme-directory` + `cairn-themer-sync-on-startup`),
      confirm `(server-start)` is present.
- [ ] `doom sync`.

### Phase 6 — Validate
- [ ] Apply a theme via `theming/pick-theme.sh` with Emacs server running —
      confirm the live session updates with no manual reload.
- [ ] Restart Emacs with a theme already applied — confirm
      `cairn-themer-sync-on-startup` loads the current one, not stale
      colors.
- [ ] Spot-check all 5 existing presets (`gray-blue`, `gruvbox`, `nord`,
      `catppuccin-mocha`, `everforest`) against `PALETTE-DESIGN.md`'s
      contrast criteria — Cairn's palettes weren't designed against these
      constraints originally, so this is new information, not an
      assumption to carry over.

### Phase 7 — Close out
- [ ] Update this doc to reflect what actually shipped (vs. what was
      planned) for anything that changed during implementation.
- [ ] Commit and push `cairn-emacs-themer`, `cairn`, and the private
      `dotfiles` config change.
