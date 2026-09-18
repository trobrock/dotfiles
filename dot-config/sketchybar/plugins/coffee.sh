#!/usr/bin/env bash
# Idle inhibitor, mirroring StatusIsland.qml's idle-inhibit button. Hyprland
# tracks a Wayland idle inhibitor; on macOS the equivalent is `caffeinate`.
#
# Quickshell renders green/yellow normally but subtext under monochrome, which
# is what the bar uses.

set -uo pipefail

source "$CONFIG_DIR/theme.sh"

if pgrep -qf '/usr/bin/caffeinate'; then
  sketchybar --set "$NAME" icon="$GLYPH_IDLE_INHIBITED" icon.color="$SUBTEXT"
else
  sketchybar --set "$NAME" icon="$GLYPH_IDLE_NORMAL" icon.color="$SUBTEXT"
fi
