data="$(~/.config/scripts/calendar.sh)"

title=$(printf '%s' "$data" | jq -r '.title')

sketchybar --set "$NAME" label="$title" click_script="~/.config/scripts/open_calendar_event.sh"
