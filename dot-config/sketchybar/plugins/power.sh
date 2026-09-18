#!/usr/bin/env bash
# Power menu, standing in for PowerMenu.qml.
#
# Lock and sleep act immediately. Log out, restart, and shut down first swap
# the entry for an inline "Confirm" row, so there is no single-click path to a
# destructive action -- the same guarantee the Quickshell menu makes.

set -uo pipefail

source "$CONFIG_DIR/theme.sh"

readonly ITEM=power

# Appends one popup row to the global `args` array. Avoids mapfile so the
# script stays runnable under macOS's bash 3.2.
args=()
entry() {
  local name=$1 label=$2 color=$3 script=$4
  args+=(--add item "$name" "popup.$ITEM"
         --set "$name" icon.drawing=off
               "label=$label"
               "label.color=$color"
               label.padding_left=12
               label.padding_right=12
               "click_script=$script")
}

close_popup="sketchybar --set $ITEM popup.drawing=off"

render_menu() {
  sketchybar --remove "/$ITEM.popup\\./" >/dev/null 2>&1

  args=()
  # `pmset displaysleepnow` only locks if the screen-lock delay is immediate;
  # see docs/macos-desktop.md.
  entry "$ITEM.popup.lock" "Lock" "$TEXT" "pmset displaysleepnow; $close_popup"
  entry "$ITEM.popup.sleep" "Sleep" "$TEXT" "pmset sleepnow; $close_popup"
  entry "$ITEM.popup.logout" "Log Out" "$YELLOW" "$PLUGIN_DIR/power.sh confirm logout"
  entry "$ITEM.popup.restart" "Restart" "$PEACH" "$PLUGIN_DIR/power.sh confirm restart"
  entry "$ITEM.popup.shutdown" "Shut Down" "$RED" "$PLUGIN_DIR/power.sh confirm shutdown"

  sketchybar "${args[@]}"
}

# Runs the actual action. Kept in this script rather than inlined into a
# click_script so the AppleScript quoting never has to survive a round trip
# through sketchybar's config strings.
run_action() {
  case "${1:-}" in
    logout)   osascript -e 'tell application "System Events" to log out' ;;
    restart)  osascript -e 'tell application "System Events" to restart' ;;
    shutdown) osascript -e 'tell application "System Events" to shut down' ;;
    *)        exit 1 ;;
  esac
}

confirm_action() {
  local action=$1 label

  case $action in
    logout)   label="Confirm log out" ;;
    restart)  label="Confirm restart" ;;
    shutdown) label="Confirm shut down" ;;
    *)        exit 1 ;;
  esac

  sketchybar --remove "/$ITEM.popup\\./" >/dev/null 2>&1

  args=()
  entry "$ITEM.popup.confirm" "$label" "$RED" \
    "$PLUGIN_DIR/power.sh run $action; $close_popup"
  # Cancel is the default selection in Quickshell; keep it present and
  # unmistakable here.
  entry "$ITEM.popup.cancel" "Cancel" "$SUBTEXT" "$PLUGIN_DIR/power.sh menu"

  sketchybar "${args[@]}"
}

case "${1:-}" in
  run)
    run_action "${2:-}"
    exit 0
    ;;
  confirm)
    confirm_action "${2:-}"
    exit 0
    ;;
  menu)
    render_menu
    exit 0
    ;;
esac

# Triggered by alt-shift-esc: build the menu, then show it.
if [ "${SENDER:-}" = "power_menu_toggle" ]; then
  render_menu
  sketchybar --set "$ITEM" popup.drawing=toggle
fi
