#!/usr/bin/env bash
# Battery, mirroring StatusIsland.qml's batteryIcon() and batteryColor().
#
# Icon thresholds: charging, fully charged, then >=90 / >=65 / >=40 / >=15 / low.
# Color: <=10 red, <=20 yellow, charging green, otherwise `text`. The bar runs
# monochrome, which pins anything above the 20% warning line to subtext.

set -uo pipefail

source "$CONFIG_DIR/theme.sh"

readonly WARNING_PERCENT=20
readonly CRITICAL_PERCENT=10

batt=$(pmset -g batt)
percent=$(printf '%s' "$batt" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')

# Desktops report no battery at all; Quickshell hides the button in that case.
if [ -z "$percent" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

charging=false
printf '%s' "$batt" | grep -q "AC Power" && charging=true

charged=false
printf '%s' "$batt" | grep -qi "charged" && charged=true

if $charging && ! $charged; then
  icon=$GLYPH_BAT_CHARGING
elif $charged; then
  icon=$GLYPH_BAT_FULL
elif [ "$percent" -ge 90 ]; then
  icon=$GLYPH_BAT_90
elif [ "$percent" -ge 65 ]; then
  icon=$GLYPH_BAT_65
elif [ "$percent" -ge 40 ]; then
  icon=$GLYPH_BAT_40
elif [ "$percent" -ge 15 ]; then
  icon=$GLYPH_BAT_15
else
  icon=$GLYPH_BAT_LOW
fi

if [ "$percent" -le "$CRITICAL_PERCENT" ]; then
  color=$RED
elif [ "$percent" -le "$WARNING_PERCENT" ]; then
  color=$YELLOW
else
  # monochrome && percent > warning -> subtext
  color=$SUBTEXT
fi

sketchybar --set "$NAME" drawing=on icon="$icon" icon.color="$color"
