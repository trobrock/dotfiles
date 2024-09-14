#!/usr/bin/env bash

FOCUSED_WORKSPACE=${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused)}

windows=$(aerospace list-windows --all --format "%{workspace},%{window-id}")
mapfile -t sids < <(sketchybar --query aerospace | jq -r '.bracket[]')

commands=()
for sid in "${sids[@]}"; do
  sid=${sid#space.}
  window_count=$(echo "$windows" | grep -c "^$sid,")

  if [ "$window_count" -eq 0 ] && [ "$FOCUSED_WORKSPACE" != "$sid" ]; then
    commands+=(--set "space.$sid" drawing=off)
  else
    label_color=$([[ "$FOCUSED_WORKSPACE" = "$sid" ]] && echo "0xffc3e88d" || echo "0xffffffff")
    commands+=(--set "space.$sid" drawing=on label.color="$label_color")
  fi
done

[ "${#commands[@]}" -gt 0 ] && sketchybar "${commands[@]}"
