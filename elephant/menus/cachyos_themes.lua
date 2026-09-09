--
-- Theme picker for elephant/walker, mirroring Omarchy's own
-- default/elephant/omarchy_themes.lua (v3, github.com/basecamp/omarchy)
-- one-for-one in structure, adapted to this repo's palette/apply pipeline.
--
Name = "cachyosthemes"
NamePretty = "CachyOS Themes"
HideFromProviderlist = true

function GetEntries()
  local entries = {}
  local home = os.getenv("HOME")
  -- setup.sh creates this as a stable pointer to wherever the repo actually
  -- got cloned -- don't hardcode a specific clone path here.
  local cachyos_dir = home .. "/.local/share/cairn-repo"
  local palettes_dir = cachyos_dir .. "/theming/palettes"
  local previews_dir = cachyos_dir .. "/theming/previews"
  local pick_theme = cachyos_dir .. "/theming/pick-theme.sh"

  local handle = io.popen("find '" .. palettes_dir .. "' -maxdepth 1 -name '*.toml' 2>/dev/null | sort")
  if not handle then
    return entries
  end

  for path in handle:lines() do
    local preset = path:match("([^/]+)%.toml$")
    if preset then
      -- pull the display name out of the TOML's `name = "..."` line, since
      -- this is a tiny standalone Lua script with no TOML parser available
      local display_name = preset
      local f = io.open(path, "r")
      if f then
        for line in f:lines() do
          local n = line:match('^name%s*=%s*"(.-)"')
          if n then
            display_name = n
            break
          end
        end
        f:close()
      end

      table.insert(entries, {
        Text = display_name,
        Preview = previews_dir .. "/" .. preset .. ".png",
        PreviewType = "file",
        Actions = {
          activate = pick_theme .. " " .. preset,
        },
      })
    end
  end
  handle:close()

  return entries
end
