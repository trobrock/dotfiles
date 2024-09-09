#!/usr/bin/env bash

todoist sync
count=$(todoist list --filter "(today | overdue)" | wc -l | tr -d '[:space:]')
overdue_count=$(todoist list --filter "overdue" | wc -l | tr -d '[:space:]')
sketchybar --set $NAME label="$count"
if [ $overdue_count -gt 0 ]; then
  sketchybar --set $NAME icon.color=0xffff757f
fi
