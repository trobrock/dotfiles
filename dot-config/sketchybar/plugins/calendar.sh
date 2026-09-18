#!/usr/bin/env bash
# Upcoming calendar event, mirroring Bar.qml's contextGroup.
#
# Quickshell hides the pill unless there is a real event -- an empty title or
# the literal "no upcoming events" both count as nothing to show. Same rule
# here, so the center of the bar stays empty when there is no meeting.

set -uo pipefail

# Ensure standard file descriptors are valid — sketchybar may close them,
# which causes Python (gcalcli) to crash during stream initialization.
[[ -t 0 ]] || exec 0</dev/null
[[ -t 1 ]] || exec 1>/dev/null
[[ -t 2 ]] || exec 2>/dev/null

source "$CONFIG_DIR/theme.sh"

data="$(~/.config/scripts/calendar.sh)"
title=$(printf '%s' "$data" | jq -r '.title // ""')

normalized=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed 's/^ *//; s/ *$//')

if [ -z "$normalized" ] || [ "$normalized" = "no upcoming events" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

# maxTextWidth in Bar.qml caps the pill at 320px. At 14px CaskaydiaCove that is
# roughly 36 characters, so truncate there rather than letting the pill grow.
if [ "${#title}" -gt 36 ]; then
  title="${title:0:36}…"
fi

sketchybar --set "$NAME" drawing=on \
                         label="$title" \
                         click_script="~/.config/scripts/open_calendar_event.sh"
