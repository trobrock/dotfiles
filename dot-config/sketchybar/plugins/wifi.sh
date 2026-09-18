#!/usr/bin/env bash
# Wi-Fi status + popup, standing in for WifiMenu.qml and scripts/network-status.
#
# Signal-strength glyphs match the Linux network-status script: RSSI is bucketed
# into the same five levels, with separate ethernet and disconnected glyphs.
# Disconnected renders red, matching StatusIsland's override.

set -uo pipefail

source "$CONFIG_DIR/theme.sh"

readonly WIFI_DEVICE=$(networksetup -listallhardwareports 2>/dev/null |
  awk '/Hardware Port: Wi-Fi/{getline; print $2; exit}')

wifi_ssid() {
  [ -n "$WIFI_DEVICE" ] || return 0
  # `networksetup -getairportnetwork` is unreliable on macOS 26 -- it reports
  # "You are not associated with an AirPort network" even while Wi-Fi is up.
  # ipconfig reads the interface summary directly and stays correct.
  # LC_ALL=C guards against "illegal byte sequence" on non-UTF8 SSID bytes.
  LC_ALL=C ipconfig getsummary "$WIFI_DEVICE" 2>/dev/null |
    awk -F': *' '/^ *SSID *:/ {print $2; exit}'
}

ethernet_active() {
  local iface
  for iface in $(networksetup -listallhardwareports 2>/dev/null |
    awk '/Hardware Port: (Ethernet|USB 10\/100\/1000 LAN|Thunderbolt Ethernet)/{getline; print $2}'); do
    if ifconfig "$iface" 2>/dev/null | grep -q 'status: active'; then
      return 0
    fi
  done
  return 1
}

render_popup() {
  local ssid=$1

  sketchybar --remove '/wifi.popup\./' >/dev/null 2>&1

  local header="Disconnected"
  [ -n "$ssid" ] && header="$ssid"

  sketchybar --add item wifi.popup.header popup."$NAME" \
             --set      wifi.popup.header icon.drawing=off \
                                          label="$header" \
                                          label.color="$TEXT" \
                                          label.padding_left=10 \
                                          label.padding_right=10 \
             --add item wifi.popup.settings popup."$NAME" \
             --set      wifi.popup.settings icon.drawing=off \
                                            label="Network settings" \
                                            label.color="$SUBTEXT" \
                                            label.padding_left=10 \
                                            label.padding_right=10 \
                                            click_script="open 'x-apple.systempreferences:com.apple.Network-Settings.extension'; sketchybar --set $NAME popup.drawing=off" \
             --add item wifi.popup.toggle popup."$NAME" \
             --set      wifi.popup.toggle icon.drawing=off \
                                          label="Toggle Wi-Fi" \
                                          label.color="$SUBTEXT" \
                                          label.padding_left=10 \
                                          label.padding_right=10 \
                                          click_script="$PLUGIN_DIR/wifi.sh toggle_power; sketchybar --set $NAME popup.drawing=off"
}

if [ "${SENDER:-}" = "wifi_menu_toggle" ]; then
  set -- toggle_popup
fi

case "${1:-}" in
  toggle_popup)
    render_popup "$(wifi_ssid)"
    sketchybar --set "$NAME" popup.drawing=toggle
    exit 0
    ;;
  toggle_power)
    [ -n "$WIFI_DEVICE" ] || exit 0
    if networksetup -getairportpower "$WIFI_DEVICE" 2>/dev/null | grep -q 'On$'; then
      networksetup -setairportpower "$WIFI_DEVICE" off
    else
      networksetup -setairportpower "$WIFI_DEVICE" on
    fi
    exit 0
    ;;
esac

if ethernet_active; then
  sketchybar --set "$NAME" icon="$GLYPH_ETHERNET" icon.color="$SUBTEXT"
  exit 0
fi

ssid=$(wifi_ssid)

if [ -z "$ssid" ]; then
  sketchybar --set "$NAME" icon="$GLYPH_WIFI_OFF" icon.color="$RED"
  exit 0
fi

# NOTE: the Linux bar buckets RSSI into five strength glyphs, but macOS exposes
# RSSI only to root (`wdutil info`) -- it is absent from ioreg and ipconfig on
# macOS 26. This shows a connected/disconnected distinction instead of a
# strength ramp. GLYPH_WIFI_1..2 stay unused for that reason.
sketchybar --set "$NAME" icon="$GLYPH_WIFI_4" icon.color="$SUBTEXT"
