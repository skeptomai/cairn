# How Omarchy's theme system works

Research notes from reading `basecamp/omarchy` (the `quattro` branch, current
as of 2026-09-10) plus the third-party `imbypass/omarchy-theme-hook` project
and `~/Projects/omarchy-emacs-themer` (this machine's own Emacs integration,
built against an older Omarchy schema — see the caveat at the end). Written
to inform planning Emacs theming for `cairn`, not as a general Omarchy
reference.

## The pipeline, end to end

Running `omarchy theme set "Tokyo Night"` invokes `bin/omarchy-theme-set`,
which does roughly:

1. **Stage the theme.** Copies the official theme from
   `$OMARCHY_PATH/themes/<name>/` into a scratch `next-theme` directory,
   then overlays anything the user has customized in
   `~/.config/omarchy/themes/<name>/` on top. A theme installed from a git
   repo is held to a denylist here — it can't ship Lua, terminal configs, or
   a VS Code extension descriptor; those are considered "code," not "color."
2. **Generate `colors.toml` if missing**, by parsing `alacritty.toml`
   (`omarchy-theme-colors-from-alacritty`) — a compatibility path for older
   themes that predate `colors.toml`.
3. **Render templates.** `omarchy-theme-set-templates` walks
   `$OMARCHY_PATH/default/themed/` (plus a user override directory) and
   substitutes color tokens into config files for apps that don't have
   their own native theme-switching mechanism.
4. **Atomically swap in the new theme**: the scratch directory is moved onto
   `~/.local/state/omarchy/current/theme`, replacing it in one `mv`, guarded
   by a `flock` so concurrent theme-set invocations can't race.
5. **Update the background**, notify the running Wayland shell
   (`omarchy-shell`) over its own IPC so it re-renders without waiting for
   the rest of the pipeline.
6. **Run a fixed list of `omarchy-theme-set-*` scripts in parallel** — one
   per app with a *native* theme mechanism Omarchy talks to directly:
   terminal restarts, Hyprland, btop, opencode, helix, foot, tmux, GNOME,
   Pi, Claude, Hermes, t3code, browser, VS Code, Obsidian, keyboard. Emacs
   is conspicuously **not** in this list — there's no
   `omarchy-theme-set-emacs`.
7. **Call `omarchy-hook theme-set "$THEME_NAME"`** — the generic extension
   point (see below), which is what community integrations like the Emacs
   one hook into.
8. Warm the theme-switcher's UI caches.

## The hook mechanism (`omarchy-hook`)

This is native to Omarchy core, not a third-party addition:

```bash
omarchy-hook theme-set "$THEME_NAME"
```

runs, in order:
- `~/.config/omarchy/hooks/theme-set` (a single file), if present
- every executable file in `~/.config/omarchy/hooks/theme-set.d/` (skipping
  `*.sample`), passing along the same arguments

A failing hook just logs `Hook failed: <path>` and the loop continues — one
broken integration can't block the others or the theme switch itself.

This is a completely generic mechanism (works for any hook name, not just
`theme-set`), and it's the *only* officially-supported way to add your own
per-app integration without patching Omarchy itself.

## The `colors.toml` schema has changed shape over time

This is the single most important thing to get right before writing any new
integration, and it's easy to get wrong by copying an example that's gone
stale.

**Current schema** (basecamp/omarchy `quattro`, e.g. `themes/tokyo-night/colors.toml`):

```toml
mode = "dark"
accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"
background = "#1a1b26"
dark_background = "#13141c"
darker_background = "#0e0e14"
lighter_background = "#24283b"
foreground = "#a9b1d6"
dark_foreground = "#565f89"
light_foreground = "#b4bee6"
bright_foreground = "#c0caf5"
red = "#f7768e"
yellow = "#e0af68"
orange = "#eb927b"
green = "#9ece6a"
cyan = "#449dab"
blue = "#7aa2f7"
magenta = "#ad8ee6"
brown = "#75493d"
bright_red = "#ff7a93"
# ...bright_yellow, bright_green, bright_cyan, bright_blue, bright_magenta
```

Semantic, flat key names. One `selection` color (not split fg/bg). Light vs.
dark is a `mode` field *inside* the file. No `color0`–`color15` indices, no
`cursor` key in the sample checked.

**An older schema** (what `imbypass/omarchy-theme-hook`'s `theme-set` script
and this machine's `20-emacs.sh` both assume, per their own
`extract_color "color0"`-style calls): flat `color0`…`color15` (ANSI-16
indexed), plus separate `foreground`/`background`/`cursor`/
`selection_foreground`/`selection_background` keys, and light/dark signaled
by a **separate `light.mode` sentinel file** next to `colors.toml`, not a
field inside it.

**Practical consequence**: against a current-schema theme like
`tokyo-night`, `imbypass`'s `theme-set` script's `extract_color "color0"`
etc. all return empty strings — those keys don't exist anymore. Every
variable it tries to export (`primary_background`, `normal_red`, ...) comes
back blank. `20-emacs.sh` on this machine has a fallback for exactly this:
if `$primary_background` is empty, it parses `alacritty.toml` directly with
`awk` instead. In practice, on current Omarchy, **the fallback path is
almost certainly what's actually running**, not the "primary" path the code
is written to prefer — the primary path is effectively dead code against
today's themes. It still works because `omarchy-theme-set-templates`
renders a real `alacritty.toml` from the current schema regardless, and
`20-emacs.sh`'s `awk`-based extraction reads real hex values out of that.

**Takeaway for any new integration**: read colors directly from the
*current* `colors.toml` (semantic keys: `background`, `foreground`, `red`,
`orange`, `green`, `cyan`, `blue`, `magenta`, `brown`, `accent`, `selection`,
`muted`, plus `bright_*` variants), check `mode` inside that same file for
light/dark, and don't assume `color0`–`color15` or a separate `light.mode`
file exist — they may not, on a from-scratch integration written today.

## Two integration patterns Omarchy itself uses

1. **Talk to the app's native config format via a template**, rendered by
   `omarchy-theme-set-templates` from `$OMARCHY_PATH/default/themed/*` (or a
   user override in `~/.config/omarchy/themed/`) using `colors.toml`
   directly — no shell-variable indirection. This is the "first-class"
   path, reserved for apps Omarchy's own `omarchy-theme-set-*` scripts talk
   to.
2. **A community hook script**, run via `omarchy-hook theme-set`, that reads
   `colors.toml` (or `alacritty.toml` as a fallback) itself and pushes the
   result into the target app however that app expects — a generated theme
   file plus a live-reload call, in the Emacs case.

Everything Omarchy ships natively uses pattern 1. Third-party integrations
(this machine's Emacs one included) use pattern 2, because pattern 1
requires either a PR to Omarchy itself or a local override in
`~/.config/omarchy/themed/`.

## Where this leaves the Emacs integration specifically

`~/Projects/omarchy-emacs-themer` implements pattern 2:

- **Push** (system → Emacs, live): `20-emacs.sh`, installed as
  `~/.config/omarchy/hooks/theme-set.d/20-emacs.sh`, generates a complete
  `autothemer`-based theme file
  (`~/.local/state/omarchy/current/theme/omarchy-doom-theme.el`) from
  whatever colors it can extract (primary path first, `alacritty.toml`
  fallback second, per the schema caveat above), then calls
  `emacsclient -e '(omarchy-themer-install-and-load "...")'` to push it into
  every running Emacs session immediately.
- **Pull** (Emacs startup): `omarchy-themer-sync-on-startup` checks for that
  same generated file and loads it, so a freshly-started Emacs doesn't show
  stale colors from whatever theme was active when it was last edited by
  hand.
- The elisp side (`omarchy-themer.el`) is intentionally generic — its two
  real functions, `omarchy-themer-install-and-load` (copy a theme file into
  `custom-theme-load-path` and load it, disabling whatever was active first
  so faces don't bleed between themes) and
  `omarchy-themer-add-theme-directory`, don't know or care that the theme
  file came from Omarchy specifically. Anything that can write a valid
  Emacs theme file to a known path and call `emacsclient` could reuse this
  side unchanged.
- `docs/PALETTE-DESIGN.md` in that repo documents which color-slot
  properties make a palette render well through this specific mapping
  (`sel-bg` needing to be tonally distinct from both `fg` and `bg` is the
  one most themes get wrong) — worth reading before assuming any given
  palette will look good, independent of which system generates it.
- `docs/dynamic-conversion-plan.md` explored a richer alternative (parsing
  Omarchy's `neovim.lua` per-theme file for more prescriptive theming
  instead of deriving everything from raw ANSI colors) but that's a plan,
  not what's shipped — `20-emacs.sh` as written today only ever reads
  `colors.toml`/`alacritty.toml`.
