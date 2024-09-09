#!/usr/bin/env bash

todoist sync
count=$(todoist list --filter "(today | overdue)" | wc -l | tr -d '[:space:]')
overdue_count=$(todoist list --filter "overdue" | wc -l | tr -d '[:space:]')

sketchybar --set $NAME label="$count"

if [ $overdue_count -gt 0 ]; then
  sketchybar --set $NAME icon= icon.color=0xffff757f
elif [ $count -eq 0 ]; then
  sketchybar --set $NAME icon=󱁖 icon.color=0xffc3e88d
else
  sketchybar --set $NAME icon= icon.color=0xff737aa2
fi
