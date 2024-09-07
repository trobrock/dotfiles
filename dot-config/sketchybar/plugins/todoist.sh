#!/usr/bin/env bash

today_count=$(todoist list --filter '(today | overdue)' | wc -l | tr -d '[:space:]')
sketchybar --set $NAME label="$today_count"
