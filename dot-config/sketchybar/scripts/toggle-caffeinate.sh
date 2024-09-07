#!/usr/bin/env bash

PID=$(pgrep -f "/usr/bin/caffeinate")
if [ -n "$PID" ]; then
  kill "$PID"
else
  /usr/bin/caffeinate -dmi &
fi

sketchybar --trigger coffee_changed
