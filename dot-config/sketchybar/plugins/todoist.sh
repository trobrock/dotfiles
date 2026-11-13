#!/usr/bin/env bash
# Todoist count and popup, matching modules/Todoist.qml on Linux.

set -uo pipefail

source "$CONFIG_DIR/theme.sh"

readonly ITEM=todoist
readonly HELPER="$HOME/.config/scripts/todoist-bar"

data=''

fetch_data() {
  data="$($HELPER fetch 2>/dev/null || true)"
  if ! printf '%s' "$data" | jq -e 'type == "object" and (.tasks | type == "array")' >/dev/null 2>&1; then
    data='{"count":0,"tasks":[],"stale":false,"error":"Could not read Todoist data"}'
  fi
}

update_item() {
  local count error stale color
  count=$(printf '%s' "$data" | jq -r '.count // 0')
  error=$(printf '%s' "$data" | jq -r '.error // ""')
  stale=$(printf '%s' "$data" | jq -r '.stale // false')
  color=$SUBTEXT
  if [ "$count" -gt 0 ] 2>/dev/null; then
    color=$BLUE
  elif [ -n "$error" ] && [ "$stale" != true ]; then
    color=$RED
  fi
  sketchybar --set "$ITEM" label="$count" icon.color="$color"
}

remove_popup() {
  sketchybar --remove "/$ITEM.popup\\./" >/dev/null 2>&1 || true
}

render_popup() {
  local error stale task_count shown index id content due suffix
  remove_popup

  args=()
  args+=(--add item "$ITEM.popup.header" "popup.$ITEM"
         --set "$ITEM.popup.header" icon="$GLYPH_TODOIST"
               icon.color="$BLUE"
               label="Todoist · Today"
               label.color="$TEXT"
               label.font="$FONT_FAMILY:Bold:14.0"
               label.padding_right=14
               click_script="open https://app.todoist.com/app/today")

  error=$(printf '%s' "$data" | jq -r '.error // ""')
  stale=$(printf '%s' "$data" | jq -r '.stale // false')
  if [ -n "$error" ]; then
    suffix=$error
    [ "$stale" = true ] && suffix="Showing saved tasks · $error"
    suffix=$(printf '%s' "$suffix" | tr '\n' ' ' | cut -c1-90)
    args+=(--add item "$ITEM.popup.error" "popup.$ITEM"
           --set "$ITEM.popup.error" icon.drawing=off
                 label="$suffix"
                 label.color="$RED"
                 label.padding_left=12
                 label.padding_right=12)
  fi

  task_count=$(printf '%s' "$data" | jq '.tasks | length')
  shown=$task_count
  [ "$shown" -gt 8 ] && shown=8

  if [ "$shown" -eq 0 ]; then
    args+=(--add item "$ITEM.popup.empty" "popup.$ITEM"
           --set "$ITEM.popup.empty" icon.drawing=off
                 label="Nothing due today."
                 label.color="$SUBTEXT"
                 label.padding_left=12
                 label.padding_right=12)
  else
    index=0
    while [ "$index" -lt "$shown" ]; do
      id=$(printf '%s' "$data" | jq -r ".tasks[$index].id // \"\"")
      content=$(printf '%s' "$data" | jq -r ".tasks[$index].content // \"Untitled task\" | gsub(\"[\\r\\n]+\"; \" \" )")
      due=$(printf '%s' "$data" | jq -r ".tasks[$index].due // \"Due today\"")
      [ -z "$due" ] && due="Due today"
      [ "${#content}" -gt 48 ] && content="${content:0:48}…"
      args+=(--add item "$ITEM.popup.task.$index" "popup.$ITEM"
             --set "$ITEM.popup.task.$index" icon="○"
                   icon.color="$GREEN"
                   label="$content  ·  $due"
                   label.color="$TEXT"
                   label.padding_right=12
                   click_script="$PLUGIN_DIR/todoist.sh task $id")
      index=$((index + 1))
    done
  fi

  if [ "$task_count" -gt 8 ]; then
    args+=(--add item "$ITEM.popup.more" "popup.$ITEM"
           --set "$ITEM.popup.more" icon.drawing=off
                 label="+ $((task_count - 8)) more in Todoist"
                 label.color="$SUBTEXT"
                 label.padding_left=12
                 label.padding_right=12
                 click_script="open https://app.todoist.com/app/today")
  fi

  args+=(--add item "$ITEM.popup.help" "popup.$ITEM"
         --set "$ITEM.popup.help" icon.drawing=off
               label="Click to complete · right-click to open"
               label.color="$OVERLAY"
               label.font="$FONT_FAMILY:Regular:11.0"
               label.padding_left=12
               label.padding_right=12)

  sketchybar "${args[@]}"
}

open_task() {
  local task_id=$1 url
  url=$(printf '%s' "$data" | jq -r --arg id "$task_id" '.tasks[] | select(.id == $id) | .url' | head -n 1)
  case "$url" in
    https://app.todoist.com/*) open "$url" ;;
    *) open "https://app.todoist.com/app/today" ;;
  esac
}

case "${1:-update}" in
  toggle)
    fetch_data
    update_item
    render_popup
    sketchybar --set "$ITEM" popup.drawing=toggle
    ;;
  task)
    fetch_data
    if [ "${BUTTON:-left}" = right ]; then
      open_task "${2:-}"
    elif [[ "${2:-}" =~ ^[A-Za-z0-9_-]+$ ]]; then
      completion_result=$("$HELPER" complete "$2" 2>/dev/null || true)
      completion_error=$(printf '%s' "$completion_result" | jq -r 'if .ok == true then "" else (.error // "Could not complete task") end' 2>/dev/null || printf '%s' 'Could not complete task')
      fetch_data
      if [ -n "$completion_error" ]; then
        data=$(printf '%s' "$data" | jq -c --arg error "$completion_error" '.error = $error')
      fi
      update_item
      render_popup
      sketchybar --set "$ITEM" popup.drawing=on
    fi
    ;;
  *)
    fetch_data
    update_item
    ;;
esac
