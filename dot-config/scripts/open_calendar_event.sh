#!/usr/bin/env bash

data="$(~/.config/scripts/calendar.sh)"
conference_url=$(echo "$data" | jq -r '.conference_url')

if [[ -z "$conference_url" || "$conference_url" == "null" ]]; then
  notify-send "No conference link found" "Please check your calendar for details." 
else
  xdg-open "$conference_url" &>/dev/null
fi
