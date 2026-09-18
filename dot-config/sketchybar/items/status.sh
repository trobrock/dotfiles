# modules/StatusIsland.qml with iconOnly + monochrome: a run of icon-only
# buttons tinted subtext, taking on color only to signal a problem state.
#
# Quickshell's visual order (left to right) is:
#   tailscale, idle-inhibit, bluetooth, wifi, vox, battery
#
# Right-position items stack right-to-left in the order added, so this file
# adds them in reverse. `vox` (voxtype) has no macOS counterpart; the mic-mute
# indicator driven by `hush` occupies the same slot.

status_defaults=(
  label.drawing=off
  icon.color="$SUBTEXT"
  icon.padding_left="$STATUS_PADDING"
  icon.padding_right="$STATUS_PADDING"
)

sketchybar --add item battery right \
           --set      battery "${status_defaults[@]}" \
                              update_freq=120 \
                              script="$PLUGIN_DIR/battery.sh" \
           --subscribe battery system_woke power_source_change

sketchybar --add event microphone_status_change \
           --add item  microphone right \
           --set       microphone "${status_defaults[@]}" \
                                  update_freq=10 \
                                  script="$PLUGIN_DIR/microphone.sh" \
           --subscribe microphone microphone_status_change

# alt-n triggers wifi_menu_toggle; the popup contents must be rendered before
# the popup is shown, so the keybind cannot just set popup.drawing.
sketchybar --add event wifi_menu_toggle \
           --add item wifi right \
           --set      wifi "${status_defaults[@]}" \
                           update_freq=15 \
                           click_script="$PLUGIN_DIR/wifi.sh toggle_popup" \
                           script="$PLUGIN_DIR/wifi.sh" \
           --subscribe wifi wifi_change wifi_menu_toggle

# alt-b triggers bluetooth_menu_toggle -- see the wifi note above.
sketchybar --add event bluetooth_menu_toggle \
           --add item bluetooth right \
           --set      bluetooth "${status_defaults[@]}" \
                                update_freq=15 \
                                click_script="$PLUGIN_DIR/bluetooth.sh toggle_popup" \
                                script="$PLUGIN_DIR/bluetooth.sh" \
           --subscribe bluetooth bluetooth_menu_toggle

# Hyprland's idle inhibitor; on macOS this is `caffeinate`.
sketchybar --add event        coffee_changed \
           --add item  coffee right \
           --subscribe coffee coffee_changed \
           --set       coffee "${status_defaults[@]}" \
                              update_freq=5 \
                              click_script="$SCRIPT_DIR/toggle-caffeinate.sh" \
                              script="$PLUGIN_DIR/coffee.sh"

sketchybar --add item tailscale right \
           --set      tailscale "${status_defaults[@]}" \
                                update_freq=30 \
                                click_script="$PLUGIN_DIR/tailscale.sh toggle_popup" \
                                script="$PLUGIN_DIR/tailscale.sh"
