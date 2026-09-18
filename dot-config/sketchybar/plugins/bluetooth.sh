#!/usr/bin/env bash
# Bluetooth status + popup, standing in for BluetoothMenu.qml.
#
# StatusIsland.qml: enabled -> GLYPH_BT_ON (subtext under monochrome),
# disabled -> GLYPH_BT_OFF in overlay.

set -uo pipefail

source "$CONFIG_DIR/theme.sh"

powered() {
  [ "$(blueutil -p 2>/dev/null)" = "1" ]
}

render_popup() {
  sketchybar --remove '/bluetooth.popup\./' >/dev/null 2>&1

  local commands=()
  local header="Bluetooth off"
  powered && header="Bluetooth on"

  commands+=(--add item bluetooth.popup.header popup."$NAME"
             --set      bluetooth.popup.header icon.drawing=off
                                               label="$header"
                                               label.color="$TEXT"
                                               label.padding_left=10
                                               label.padding_right=10)

  # blueutil prints one line per connected device; pull the quoted name out.
  local index=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    local name address
    name=$(printf '%s' "$line" | sed -n 's/.*name: "\([^"]*\)".*/\1/p')
    address=$(printf '%s' "$line" | sed -n 's/^address: \([^,]*\),.*/\1/p')
    [ -n "$name" ] || continue

    commands+=(--add item "bluetooth.popup.device.$index" popup."$NAME"
               --set      "bluetooth.popup.device.$index" icon.drawing=off
                                                          label="$name"
                                                          label.color="$GREEN"
                                                          label.padding_left=10
                                                          label.padding_right=10
                                                          click_script="blueutil --disconnect $address; sketchybar --set $NAME popup.drawing=off")
    index=$((index + 1))
  done < <(blueutil --connected 2>/dev/null)

  commands+=(--add item bluetooth.popup.toggle popup."$NAME"
             --set      bluetooth.popup.toggle icon.drawing=off
                                               label="Toggle Bluetooth"
                                               label.color="$SUBTEXT"
                                               label.padding_left=10
                                               label.padding_right=10
                                               click_script="$PLUGIN_DIR/bluetooth.sh toggle_power; sketchybar --set $NAME popup.drawing=off")

  sketchybar "${commands[@]}"
}

if [ "${SENDER:-}" = "bluetooth_menu_toggle" ]; then
  set -- toggle_popup
fi

case "${1:-}" in
  toggle_popup)
    render_popup
    sketchybar --set "$NAME" popup.drawing=toggle
    exit 0
    ;;
  toggle_power)
    if powered; then
      blueutil -p 0
    else
      blueutil -p 1
    fi
    exit 0
    ;;
esac

if powered; then
  sketchybar --set "$NAME" icon="$GLYPH_BT_ON" icon.color="$SUBTEXT"
else
  sketchybar --set "$NAME" icon="$GLYPH_BT_OFF" icon.color="$OVERLAY"
fi
