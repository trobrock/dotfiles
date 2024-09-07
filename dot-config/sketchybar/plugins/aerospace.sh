#!/usr/bin/env bash

if [ -z "$FOCUSED_WORKSPACE" ]; then
  FOCUSED_WORKSPACE=$(aerospace list-workspaces --focused)
fi

windows=$(aerospace list-windows --all --format "%{workspace},%{window-id}")

commands=()
for sid in $(sketchybar --query aerospace | jq -r '.bracket[]'); do
  sid=${sid#space.}
  window_count=$(echo "$windows" | grep "^$sid," | wc -l)

  if [ $window_count -eq 0 ] && [ "$FOCUSED_WORKSPACE" != "$sid" ]; then
    # No windows in this space, hide it
    commands+=(--set space.$sid drawing=off)
  else
    # Windows in this space, show it
    if [ "$FOCUSED_WORKSPACE" = "$sid" ]; then
      commands+=(--set space.$sid drawing=on label.color=0xffc3e88d)
    else
      commands+=(--set space.$sid drawing=on label.color=0xffffffff)
    fi
  fi
done

if [ ! -z "$commands" ]; then
  sketchybar "${commands[@]}"
fi
