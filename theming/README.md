# Theming system

Cross-app color theming for the CachyOS+SwayFX desktop. Hand-rolled, not
matugen: the starter presets are named, published palettes —
gruvbox/nord/catppuccin/everforest — and matugen's whole point is
*deriving* a palette algorithmically from a wallpaper, which won't
reproduce colors people actually recognize as those names.

## Usage

```bash
python3 theming/apply-theme.py <preset-name>   # e.g. gruvbox
python3 theming/apply-theme.py                  # lists available presets
```

Or via the installer's closing step: `install.sh` offers a `gum
choose` picker over whatever's in `palettes/` automatically.

## Adding a new preset

Copy `palettes/gray-blue.toml`, rename it, replace every hex value with your
own. Every key in that file must be present — `apply-theme.py` fails loudly
(naming the missing token and which template needed it) rather than
producing a half-themed desktop.

## Adding a new app to the switcher

1. Find the app's real color file (not just a `theme = "name"` pointer —
   trace it to wherever the actual hex/RGB values live).
2. Copy that file into `templates/<something>.tmpl`, replace hex values with
   `{{token}}` placeholders using the keys from `palettes/gray-blue.toml`.
3. Add an entry to the `TARGETS` list in `apply-theme.py` (template name,
   real output path, reload command or `None`).
4. If the app needs decimal `R,G,B` instead of hex (like kdeglobals), use
   `{{token-rgb}}` — every hex-valued palette key automatically gets a
   `-rgb` sibling token, no extra code needed.
5. If the app doesn't auto-reload on its own, find its actual live-reload
   mechanism rather than assuming a restart is required — Ghostty looks
   like it needs a restart but actually exposes a D-Bus `reload-config`
   action (`busctl --user call com.mitchellh.ghostty /com/mitchellh/ghostty
   org.gtk.Actions Activate sava{sv} reload-config 0 0`) that live-updates
   already-open windows. Check `busctl --user tree <bus-name>` +
   `org.gtk.Actions List` for anything GTK-based before assuming there's no
   way to avoid a restart.

## Palette schema

| Key | Used for |
|---|---|
| `name` | Human-readable label (shown in kdeglobals, not load-bearing elsewhere) |
| `mode` | `"light"` or `"dark"` — picks GTK3/Kvantum base theme + kdeglobals' secondary colors (see `MODE_DEFAULTS` in `apply-theme.py`), not derived from `bg`'s lightness |
| `bg` / `fg` | Primary background/foreground |
| `hover-bg` / `hover-fg` | Hover/highlight state |
| `accent` | Borders, focus rings, the "this app's color" highlight |
| `danger` | Alerts (waybar's notification-bell red, walker's error state) |
| `selection` | Terminal text-selection background |
| `black` `red` `green` `yellow` `blue` `magenta` `cyan` `white` | Standard ANSI 0-7 |
| `bright-*` | Standard ANSI 8-15 |

## What's deliberately out of scope (v1)

- **GTK3 base theme / Kvantum**: point at packaged themes (`adw-gtk3`/
  `adw-gtk3-dark`, `KvArc`/`KvArcDark`, picked by each preset's `mode`)
  rather than a per-preset generated theme pack — a deliberate proportionate
  call for this exact small Qt/GTK-base surface. kdeglobals itself *is*
  fully per-preset (plain INI, no asset-pack dependency); GTK3/Kvantum only
  get a light-vs-dark base pick, not custom per-preset colors within that
  base.
- **Chromium**: not out of scope, just a different mechanism with real
  limits. `apply_chromium_theme()` retints the toolbar/tab accent color via
  Chromium's managed-policy mechanism (`BrowserColorScheme: "device"`).
  `apply_gsettings_mode()` (see below) now sets the actual
  `org.gnome.desktop.interface color-scheme` dconf key Chromium's `"device"`
  setting reads to decide its own chrome light/dark — so Chromium's chrome
  itself may now follow `mode` too, not just its accent color, without any
  Chromium-specific code; worth confirming next time it's open during a
  switch. Genuinely out of Chromium's own control from here: per-tab web
  content that ignores `prefers-color-scheme` is up to each site.
- **GNOME dconf sync**: `apply_gsettings_mode()` sets
  `org.gnome.desktop.interface {color-scheme, gtk-theme}` on every switch —
  found necessary because `adw-gtk3` (the light GTK3 variant) is built to
  auto-sync with that system-wide preference rather than always rendering
  light, so a leftover dark dconf value (from this box's earlier HyDE/
  GNOME-ish era) silently overrode `gtk-3.0/settings.ini` alone. This is
  also the same backend the Chromium point above depends on.
- **fastfetch**: no config currently tracked, nothing broken to fix; its
  logo art is mood/wallpaper-adjacent, not palette-driven.

## Vesktop (Discord)

Vesktop (the Vencord-based Discord client, package `vesktop-bin`) ignores
GTK/system theming entirely — it needs its own CSS injection to reskin, same
category of problem as Chromium above, different mechanism. Vencord exposes
a single `quickCss.css` file (`~/.config/vesktop/settings/quickCss.css`)
that supports `@import url(...)` and hot-reloads live on save, no app
restart needed — this is the same mechanism pywal/wallust Discord
integrations use (e.g. `ZephyrCodesStuff/pywal-vencord`,
`guglicap/wal-discord`).

`templates/discord-quickcss.css.tmpl` `@import`s a published BetterDiscord
recolor theme
([DiscordRecolor](https://github.com/mwittrien/BetterDiscordAddons/tree/master/Themes/DiscordRecolor))
that exposes the whole UI as CSS custom properties, then overrides those
properties from this preset's palette. Rendered output is
`vesktop/quickcss.css` (tracked in this repo), symlinked by `setup.sh` to
the live `~/.config/vesktop/settings/quickCss.css` path — only that one file
is symlinked; the rest of `~/.config/vesktop/settings/` (`settings.json`,
caches, session data) is live Vencord state this repo doesn't own.

`apply-theme.py`'s `ensure_vesktop_quickcss_enabled()` also patches
`settings.json`'s `useQuickCss` key back to `true` on every preset switch —
Vencord's own toggle for whether it reads `quickCss.css` at all, which lives
in that same live-state file outside this repo's control, so a preset
switch alone can't guarantee it stays on (e.g. after a fresh Vesktop install
or a toggle flipped off by hand).
