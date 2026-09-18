#!/usr/bin/env bash
# Microphone mute state, driven by the `hush` daemon's state file.
#
# This occupies the slot StatusIsland.qml gives to voxtype, which has no macOS
# counterpart. Quickshell tints that button mauve, or subtext under monochrome.

set -uo pipefail

source "$CONFIG_DIR/theme.sh"

readonly STATE_FILE="$HOME/.local/state/hush/muted"

if [ "$SENDER" = "microphone_status_change" ] && [ -n "${MUTED:-}" ]; then
  muted=$MUTED
elif [ -r "$STATE_FILE" ]; then
  muted=$(cat "$STATE_FILE")
else
  # No hush state yet: hide rather than report a state we cannot verify.
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

if [ "$muted" = "true" ]; then
  sketchybar --set "$NAME" drawing=on icon="$GLYPH_MIC_MUTED" icon.color="$RED"
else
  sketchybar --set "$NAME" drawing=on icon="$GLYPH_MIC_ON" icon.color="$SUBTEXT"
fi
