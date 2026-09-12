#!/usr/bin/env python3
"""Render theming/templates/*.tmpl using a chosen palette, write the
real config files, and trigger each app's documented reload step.

Usage: apply-theme.py <preset-name>
Presets are TOML files in theming/palettes/<preset-name>.toml.
Run with no args to list available presets.
"""
import json
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

THEMING = Path(__file__).resolve().parent
CACHYOS = THEMING.parent
PALETTES = THEMING / "palettes"
TEMPLATES = THEMING / "templates"

# Tracks the last-applied preset so setup.sh can replay it on every run --
# needed because setup.sh only symlinks *files* (already correct, since
# whatever preset was last applied is what's committed), but gsettings/dconf
# writes (apply_gsettings_mode) are live system state, invisible to
# symlinking. Without this, a fresh install that skips install.sh's "pick a
# theme" step would leave dconf at whatever a fresh system defaults to,
# mismatched with the committed theme files.
CURRENT_PRESET_FILE = THEMING / ".current-preset"

TOKEN_RE = re.compile(r"\{\{([a-zA-Z0-9_-]+)\}\}")
HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")


def hex_to_rgb_str(hexval: str) -> str:
    h = hexval.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return f"{r},{g},{b}"


def list_presets() -> list[str]:
    return sorted(p.stem for p in PALETTES.glob("*.toml"))


# GTK3/Kvantum secondary-color and app-theme choices, keyed by the palette's
# `mode` (light/dark) rather than derived per-palette -- same "proportionate
# effort" call as everywhere else in this pipeline, just made mode-aware
# after a single dark-tuned set turned out unreadable against a light
# palette's background (found via Catppuccin Latte, 2026-09-07). The dark
# set is KDE Breeze Dark's own stock secondary colors (this box's original
# hardcoded values); the light set is the same hues darkened for contrast
# against a light bg, not a separate design language.
MODE_DEFAULTS = {
    "dark": {
        "gtk-theme-name": "adw-gtk3-dark",
        "gtk-prefer-dark": "1",
        "kvantum-theme": "KvArcDark",
        "fg-inactive-rgb": "218,193,187",
        "fg-link-rgb": "238,187,173",
        "fg-negative-rgb": "255,180,171",
        "fg-neutral-rgb": "217,198,129",
        "fg-visited-rgb": "219,170,156",
        "fg-negative-strong-rgb": "147,0,10",
        "fg-neutral-strong-rgb": "189,171,104",
    },
    "light": {
        "gtk-theme-name": "adw-gtk3",
        "gtk-prefer-dark": "0",
        "kvantum-theme": "KvArc",
        "fg-inactive-rgb": "110,90,85",
        "fg-link-rgb": "150,80,50",
        "fg-negative-rgb": "176,40,20",
        "fg-neutral-rgb": "130,105,10",
        "fg-visited-rgb": "130,70,55",
        "fg-negative-strong-rgb": "120,0,8",
        "fg-neutral-strong-rgb": "100,80,0",
    },
}


def load_palette(name: str) -> dict:
    path = PALETTES / f"{name}.toml"
    if not path.exists():
        available = ", ".join(list_presets())
        sys.exit(f"no such palette '{name}' (looked for {path})\navailable: {available}")
    with path.open("rb") as f:
        data = tomllib.load(f)
    tokens = {}
    for k, v in data.items():
        if not isinstance(v, str):
            continue
        tokens[k] = v
        if HEX_RE.match(v):
            tokens[f"{k}-rgb"] = hex_to_rgb_str(v)

    mode = tokens.get("mode", "dark")
    if mode not in MODE_DEFAULTS:
        sys.exit(f"{path}: unknown mode '{mode}' (expected 'light' or 'dark')")
    tokens.update(MODE_DEFAULTS[mode])
    tokens.update(emacs_mode_tokens(mode, tokens))
    return tokens


def emacs_mode_tokens(mode: str, tokens: dict) -> dict:
    """Mode-line and LSP-popup colors for emacs-theme.el.tmpl, computed from
    tokens already in the palette -- no new palette fields needed. Ported
    from cairn-emacs-themer's predecessor (omarchy-emacs-themer's
    20-emacs.sh), which branched on a `light.mode` sentinel file; cairn's
    `mode` field replaces that check.

    Light: active mode-line/LSP-popup use `selection`+`fg` (stands out from
    the near-white editor bg); inactive/header fall back to `bg`/`bright-black`.
    Dark: both use `black` (the ANSI black -- a dark panel color) with `fg`,
    since there's no separate "selection" panel look needed on dark themes.
    """
    if mode == "light":
        return {
            "ml-active-bg": tokens["selection"],
            "ml-active-fg": tokens["fg"],
            "ml-inactive-bg": tokens["bg"],
            "ml-inactive-fg": tokens["bright-black"],
            "ml-emphasis-fg": tokens["fg"],
            "lsp-doc-bg": tokens["selection"],
            "lsp-doc-fg": tokens["fg"],
            "lsp-doc-header-bg": tokens["blue"],
            "lsp-doc-header-fg": tokens["bg"],
        }
    return {
        "ml-active-bg": tokens["black"],
        "ml-active-fg": tokens["fg"],
        "ml-inactive-bg": tokens["black"],
        "ml-inactive-fg": tokens["bright-black"],
        "ml-emphasis-fg": tokens["blue"],
        "lsp-doc-bg": tokens["black"],
        "lsp-doc-fg": tokens["fg"],
        "lsp-doc-header-bg": tokens["bright-black"],
        "lsp-doc-header-fg": tokens["fg"],
    }


def render(template_path: Path, tokens: dict) -> str:
    text = template_path.read_text()
    missing = set()

    def repl(m: re.Match) -> str:
        key = m.group(1)
        if key not in tokens:
            missing.add(key)
            return m.group(0)
        return tokens[key]

    out = TOKEN_RE.sub(repl, text)
    if missing:
        raise SystemExit(f"{template_path}: palette is missing token(s): {sorted(missing)}")
    return out


def write(out_path: Path, content: str) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(content)
    print(f"  wrote {out_path}")


def reload(cmd: list[str]) -> None:
    try:
        subprocess.run(cmd, check=False, capture_output=True, timeout=5)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass


# (template filename, output path, reload command or None)
TARGETS = [
    ("waybar-theme.css.tmpl", CACHYOS / "waybar" / "theme.css", ["pkill", "-SIGUSR2", "waybar"]),
    ("swaync-theme.css.tmpl", CACHYOS / "swaync" / "theme.css", ["swaync-client", "--reload-css"]),
    ("walker-style.css.tmpl", CACHYOS / "walker" / "themes" / "gray-blue" / "style.css", None),
    ("kdeglobals.tmpl", CACHYOS / "kdeglobals-file", None),
    # GTK3/Kvantum have no live-reload mechanism -- take effect next launch,
    # same as kdeglobals/btop/walker above.
    ("gtk-settings.ini.tmpl", CACHYOS / "gtk-3.0" / "settings.ini", None),
    ("kvantum.kvconfig.tmpl", CACHYOS / "Kvantum" / "kvantum.kvconfig", None),
    ("ghostty-theme.conf.tmpl", CACHYOS / "ghostty" / "theme.conf", [
        "busctl", "--user", "call", "com.mitchellh.ghostty", "/com/mitchellh/ghostty",
        "org.gtk.Actions", "Activate", "sava{sv}", "reload-config", "0", "0",
    ]),
    # btop has no live-reload mechanism -- takes effect next launch, like
    # walker/kdeglobals above. color_theme in btop.conf is set once (see
    # README) to "cachyos", so this same file just gets overwritten in place
    # on every preset switch rather than needing a per-preset file.
    ("btop-theme.theme.tmpl", CACHYOS / "btop" / "themes" / "cachyos.theme", None),
    # Vesktop/Vencord hot-reloads quickCss.css on write -- no reload command
    # needed, unlike everything else in this list that needs a kill signal
    # or D-Bus call.
    ("discord-quickcss.css.tmpl", CACHYOS / "vesktop" / "quickcss.css", None),
]

# Loaded via cairn-emacs-themer (github.com/skeptomai/cairn-emacs-themer).
# reload()'s own FileNotFoundError/timeout handling already covers
# emacsclient not being installed or no server running -- same
# graceful-skip behavior as swaync-client/busctl above, nothing special
# needed here for "Emacs might not be open."
EMACS_THEME_PATH = CACHYOS / "emacs" / "cairn-theme.el"
TARGETS.append((
    "emacs-theme.el.tmpl", EMACS_THEME_PATH,
    ["emacsclient", "-e", f'(cairn-themer-install-and-load "{EMACS_THEME_PATH}")'],
))

ALACRITTY_TEMPLATE = "alacritty-theme.toml.tmpl"

CHROMIUM_POLICY_PATH = Path("/etc/chromium/policies/managed/color.json")


def apply_gsettings_mode(mode: str, tokens: dict) -> None:
    """Sync the GNOME/dconf color-scheme + gtk-theme keys to the palette's
    mode. Found 2026-09-07: a leftover dconf value from this box's earlier
    HyDE/GNOME-ish era (color-scheme=prefer-dark, gtk-theme=adw-gtk3-dark)
    was silently overriding gtk-3.0/settings.ini's own gtk-theme-name --
    adw-gtk3 (the light variant) is specifically built to auto-sync with
    this system-wide preference rather than always rendering light, so
    switching gtk-3.0/settings.ini alone left GTK3 apps still dark. This is
    also very likely the same backend Chromium's `BrowserColorScheme:
    "device"` (see apply_chromium_theme) reads from, so fixing this may
    also make Chromium's own chrome respond to mode -- not just the
    accent color, unlike this pipeline's other out-of-scope items.
    """
    if not shutil.which("gsettings"):
        return
    gtk_theme = tokens["gtk-theme-name"]
    color_scheme = "prefer-dark" if mode == "dark" else "prefer-light"
    reload(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", gtk_theme])
    reload(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", color_scheme])
    print(f"  gsettings: gtk-theme={gtk_theme} color-scheme={color_scheme}")


def apply_chromium_theme(tokens: dict) -> None:
    """Retint Chromium's toolbar/tab color via its managed enterprise-policy
    mechanism -- the same trick Omarchy uses (see omarchy-chromium-bin,
    bin/omarchy-theme-set-browser upstream). This alone is just the accent
    color, not a real light/dark switch -- but apply_gsettings_mode() (see
    above) now sets the actual dconf color-scheme key Chromium's own
    BrowserColorScheme: "device" reads, so Chromium's chrome itself may
    follow mode too as a side effect of that, not just this accent color.
    Requires bootstrap.sh's one-time chown of
    /etc/chromium/policies/managed to the current user.
    """
    if not CHROMIUM_POLICY_PATH.parent.is_dir():
        return  # omarchy-chromium-bin/bootstrap.sh step not present -- skip quietly
    # bg, not accent -- Chrome derives its *entire* tonal palette (toolbar,
    # New Tab Page background, buttons, etc.) from this one seed color, so
    # accent (meant for highlights/borders) produced a saturated, jarring
    # background instead of one that actually matches every other window's
    # neutral bg.
    policy = json.dumps({"BrowserThemeColor": tokens["bg"], "BrowserColorScheme": "device"})
    CHROMIUM_POLICY_PATH.write_text(policy)
    print(f"  wrote {CHROMIUM_POLICY_PATH}")
    if subprocess.run(["pgrep", "-x", "chromium"], capture_output=True).returncode == 0:
        reload(["chromium", "--refresh-platform-policy", "--no-startup-window"])


VESKTOP_SETTINGS_PATH = Path.home() / ".config" / "vesktop" / "settings" / "settings.json"


def ensure_vesktop_quickcss_enabled() -> None:
    """Vesktop's `useQuickCss` toggle lives in live app settings (Vesktop's
    own state, not something this repo symlinks), so a preset switch alone
    can't guarantee it's on -- a fresh install or a toggle flipped off by
    hand would silently leave quickcss.css written but ignored. Patches it
    back to true every run, same "resync live state alongside the file
    write" idea as apply_gsettings_mode above. Skipped quietly if Vesktop
    has never been launched yet (no settings.json to patch).
    """
    if not VESKTOP_SETTINGS_PATH.exists():
        return
    data = json.loads(VESKTOP_SETTINGS_PATH.read_text())
    if data.get("useQuickCss") is True:
        return
    data["useQuickCss"] = True
    VESKTOP_SETTINGS_PATH.write_text(json.dumps(data, indent=4))
    print(f"  vesktop: enabled useQuickCss in {VESKTOP_SETTINGS_PATH}")


def apply_wallpaper(preset: str) -> None:
    """Set the preset's wallpaper via waypaper. Always picks backgrounds/1-*
    (the lowest-numbered file) -- deterministic by design, not random: 2-*
    and 3-* exist as alternates a user can still pick by hand (mod+shift+w),
    not as a rotation. Presets without a backgrounds/ dir yet are skipped
    quietly, same as apply_chromium_theme's "step not present" skip.
    """
    backgrounds = PALETTES / preset / "backgrounds"
    if not backgrounds.is_dir():
        return
    candidates = sorted(
        p for p in backgrounds.iterdir()
        if p.suffix.lower() in (".jpg", ".jpeg", ".png") and p.stem[0].isdigit()
    )
    if not candidates:
        return
    wallpaper = candidates[0]
    if not shutil.which("waypaper"):
        return
    reload(["waypaper", "--wallpaper", str(wallpaper), "--backend", "swaybg", "--fill", "fill"])
    print(f"  waypaper: {wallpaper.name}")


def main() -> None:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <preset-name>")
        print(f"available presets: {', '.join(list_presets())}")
        sys.exit(1)

    preset = sys.argv[1]
    tokens = load_palette(preset)
    print(f"==> applying theme '{tokens.get('name', preset)}'")
    CURRENT_PRESET_FILE.write_text(preset + "\n")

    for tmpl_name, out_path, reload_cmd in TARGETS:
        rendered = render(TEMPLATES / tmpl_name, tokens)
        write(out_path, rendered)
        if reload_cmd:
            reload(reload_cmd)

    # alacritty gets its own per-preset theme file, then alacritty.toml's
    # import line is repointed at it.
    alacritty_theme_path = CACHYOS / "alacritty" / "themes" / f"{preset}.toml"
    rendered = render(TEMPLATES / ALACRITTY_TEMPLATE, tokens)
    write(alacritty_theme_path, rendered)

    alacritty_toml_path = CACHYOS / "alacritty" / "alacritty.toml"
    text = alacritty_toml_path.read_text()
    new_text, n = re.subn(
        r'import = \["[^"]*"\]',
        f'import = ["~/.config/alacritty/themes/{preset}.toml"]',
        text,
    )
    if n != 1:
        raise SystemExit(f"{alacritty_toml_path}: expected exactly one import=[...] line, found {n}")
    alacritty_toml_path.write_text(new_text)
    print(f"  pointed {alacritty_toml_path} at themes/{preset}.toml")

    apply_gsettings_mode(tokens.get("mode", "dark"), tokens)
    apply_chromium_theme(tokens)
    ensure_vesktop_quickcss_enabled()
    apply_wallpaper(preset)

    print(f"\ntheme '{preset}' applied.")
    print("kdeglobals changes take effect the next time a KDE-Frameworks app launches.")
    print("alacritty live-reloads open windows automatically (live_config_reload, its own default).")
    print("ghostty open windows were just reloaded via D-Bus (org.gtk.Actions reload-config).")

    # Fires on every theme switch, not just this one -- doubles as an
    # ongoing contrast smoke-test for swaync's notification styling (see the
    # sw-msg-body fix: notification text rendering wrong against a given
    # palette is exactly the kind of thing that's invisible until you
    # actually look at a live notification).
    reload([
        "notify-send", f"Theme: {tokens.get('name', preset)}",
        "Notification contrast check -- this text should be clearly readable.",
    ])


if __name__ == "__main__":
    main()
