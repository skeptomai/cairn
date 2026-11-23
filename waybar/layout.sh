#!/bin/sh
# Emits waybar JSON on startup and on every keyboard-layout change.
emit() {
    swaymsg -t get_inputs | jq -c -M '
      [.[] | select(.type=="keyboard") | .xkb_active_layout_name][0]
      | {text: (if test("Dvorak") then "Dvorak" else "QWERTY" end),
         tooltip: "Super+Ctrl+Space or click to toggle"}'
}
emit
swaymsg -t subscribe -m '["input"]' | while read -r _; do emit; done
