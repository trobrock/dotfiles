#!/usr/bin/env bash
# Workspace states, mirroring modules/Workspaces.qml in minimal mode.
#
#   focused              lavender label + lavender indicator
#   visible elsewhere    blue label + blue indicator (Hyprland: active on
#                        another monitor)
#   otherwise            subtext label, no indicator
#
# Quickshell dims workspaces that do not exist yet to `overlay`, because in
# Hyprland an empty workspace has no object at all. Reproducing that here made
# an empty workspace look miscolored rather than empty, and overlay is hard to
# read against a translucent bar, so occupied and empty both use subtext and
# only the focused workspace stands out.
#
# Quickshell always shows workspaces 1-5 and only shows 6-10 when occupied, so
# the bar cannot grow without bound. Same rule here.

set -uo pipefail

source "$CONFIG_DIR/theme.sh"

readonly ALWAYS_SHOWN_MAX=5

focused=${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused 2>/dev/null)}
visible=$(aerospace list-workspaces --monitor all --visible 2>/dev/null)
windows=$(aerospace list-windows --all --format '%{workspace}' 2>/dev/null)

# Avoid mapfile: macOS ships bash 3.2 at /bin/bash, so this stays runnable by
# hand even though sketchybar itself uses Homebrew bash.
sids=()
while IFS= read -r line; do
  [ -n "$line" ] && sids+=("$line")
done < <(sketchybar --query aerospace | jq -r '.bracket[]')

[ "${#sids[@]}" -gt 0 ] || exit 0

contains_line() {
  printf '%s\n' "$2" | grep -qxF -- "$1"
}

commands=()
for item in "${sids[@]}"; do
  sid=${item#space.}

  occupied=false
  contains_line "$sid" "$windows" && occupied=true

  # Hide unoccupied overflow workspaces, but never the fixed launch targets.
  if ! $occupied && [ "$focused" != "$sid" ] &&
     ! { [[ $sid =~ ^[0-9]+$ ]] && [ "$sid" -le "$ALWAYS_SHOWN_MAX" ]; }; then
    commands+=(--set "$item" drawing=off)
    continue
  fi

  if [ "$focused" = "$sid" ]; then
    label_color=$LAVENDER
    indicator=$LAVENDER
  elif contains_line "$sid" "$visible"; then
    label_color=$BLUE
    indicator=$BLUE
  else
    label_color=$SUBTEXT
    indicator=$TRANSPARENT
  fi

  commands+=(--set "$item" drawing=on \
                           label.color="$label_color" \
                           background.color="$indicator")
done

[ "${#commands[@]}" -gt 0 ] && sketchybar "${commands[@]}"
