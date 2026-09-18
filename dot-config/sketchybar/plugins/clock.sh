#!/usr/bin/env bash
# modules/Clock.qml formats the bar label as "MMM d · h:mm AP".

set -uo pipefail

# %-d and %-I strip the leading zero, matching Qt's "d" and "h".
sketchybar --set "$NAME" label="$(date '+%b %-d · %-I:%M %p')"
