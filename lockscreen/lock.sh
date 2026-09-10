#!/usr/bin/env bash
# The actual lock invocation -- rustlock (built from source, see
# bootstrap.sh) instead of plain swaylock. Kept as its own script so
# sway/config's several call sites (idle lock, before-sleep, lid close,
# $mod+l) share one tuned configuration instead of repeating these flags.
exec rustlock \
  --screenshots \
  --clock \
  --effect-blur 7x5 \
  --effect-vignette 0.5:0.5 \
  --ring-shape hexagon \
  --indicator-radius 100 \
  --indicator-thickness 7 \
  --ring-color 6fd6c2 \
  --key-hl-color 6fd6c2 \
  --verifying-color 0072FF \
  --line-color 00000000 \
  --inside-color 1b1e2688 \
  --separator-color 00000000 \
  --fade-in 0.3 \
  --wrong-password-duration 800 \
  --pam-service rustlock
