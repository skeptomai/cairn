-- Was a symlink into an Omarchy-specific runtime path
-- (~/.local/state/omarchy/current/theme/neovim.lua) that this repo has no
-- equivalent of -- Cairn's own theming/ switcher doesn't drive neovim's
-- colorscheme. Static default instead; change `colorscheme` to whatever
-- you like from all-themes.lua.
return {
  { "LazyVim/LazyVim", opts = { colorscheme = "gruvbox" } },
}
