#!/usr/bin/env bash

data="$(~/.config/scripts/calendar.sh)"
conference_url=$(echo "$data" | jq -r '.conference_url')

if [[ -z "$conference_url" || "$conference_url" == "null" ]]; then
  notify-send "No conference link found" "Please check your calendar for details." 
else
  if [[ "$conference_url" =~ ^https?://([^/]+\.)?zoom\.us/ ]] && command -v zoom-webapp-handler &>/dev/null; then
    zoom-webapp-handler "$conference_url" &>/dev/null &
  elif command -v xdg-open &>/dev/null; then
    xdg-open "$conference_url" &>/dev/null
  else
    # fallback for macOS, use open command
    open "$conference_url" &>/dev/null
  fi
fi
